#!/bin/tclsh
#==============================================================================
# tprocc_3engine_800wh_150vu.tcl
#
# Instrumentation script for the 800-warehouse /
# 150-VU / 30-min comparison across TidesDB, RocksDB and InnoDB, each under
# its own server config (restarted between engines):
#
#       tidesdb  ->  /data/mariadb/tidesdb.my.cnf
#       rocksdb  ->  /data/mariadb/rocksdb.my.cnf
#       innodb   ->  /data/mariadb/innodb.my.cnf
#
# Additions vs the original harness:
#   * probes the live server for each engine's authoritative on-disk store dir
#     (@@tidesdb_data_home_dir, @@rocksdb_datadir, @@datadir) rather than
#     hardcoding, and validates it is the expected, real directory
#   * asserts the LSM stores (#rocksdb, tidesdb_data) are clean after the
#     drop and before the build -- refuses to benchmark on dirty state
#   * captures the engine's on-disk data size after the measured run and
#     before the schema is deleted -> results/data_sizes.csv
#
# Drive it from the HammerDB-6.0 root, e.g.:
#   WH=800 VU_LIST="150" RAMPUP=3 DURATION=5 ITERS=2 \
#     ./hammerdbcli auto scripts/tcl/maria/tprocc/tprocc_3engine_800wh_150vu.tcl
#==============================================================================

proc envdef {name def} { expr {[info exists ::env($name)] ? $::env($name) : $def} }

#  knobs
set OUTDIR    [envdef OUTDIR   results]
set wh        [envdef WH       800]
set buildvu   [envdef BUILDVU  24]
set vu_list   [envdef VU_LIST  {150}]
set rampup    [envdef RAMPUP   5]
set duration  [envdef DURATION 30]
set iters     [envdef ITERS    1]

# engine -> {profileid  defaults-file  label  gnuplot-colour  gnuplot-pointtype}
set engines {
    tidesdb {2 /data/mariadb/tidesdb.my.cnf TidesDB #193EDB 7}
    rocksdb {4 /data/mariadb/rocksdb.my.cnf RocksDB #F7B701 6}
    innodb  {3 /data/mariadb/innodb.my.cnf  InnoDB  #E17510 5}
}

# Optional subset selection: ENGINES="tidesdb rocksdb" runs only those, in that
# order. Default (unset/empty) keeps all three in the order defined above.
if {[set _sel [string trim [envdef ENGINES ""]]] ne ""} {
    set _filtered {}
    foreach _k $_sel {
        if {[dict exists $engines $_k]} {
            lappend _filtered $_k [dict get $engines $_k]
        } else {
            puts "## WARN: ENGINES lists unknown engine '$_k' -- ignoring"
        }
    }
    if {[llength $_filtered]} { set engines $_filtered }
}

#  paths
set BIN            /data/mariadb/bin
set MARIADBD_SAFE  $BIN/mariadbd-safe
set MARIADB        $BIN/mariadb
set SOCK           /tmp/mariadb.sock
set PIDFILE        /data/mariadb/data/mariadb.pid    ;# pid-file from every cnf
set PLUGINDIR      /data/mariadb/lib/plugin
set JOBSDB         [envdef JOBSDB /tmp/hammer.DB]    ;# HammerDB jobs DB
set START_TIMEOUT  180
set STOP_TIMEOUT   180

# expected store dir per engine -- cross-checked against what the live server
# reports, so a mis-probe or a moved data dir is caught loudly
set EXPECT_DIR {
    tidesdb {/data/mariadb/tidesdb_data}
    rocksdb {/data/mariadb/data/#rocksdb}
    innodb  {/data/mariadb/data/tpcc}
}

file mkdir TMP
file mkdir $OUTDIR
file mkdir [file join $OUTDIR data]
file mkdir [file join $OUTDIR figures]
file mkdir [file join $OUTDIR logs]

# keepalive + give the time profiler room at high VU
giset commandline keepalive_margin 1200
giset timeprofile  xt_gather_timeout 1200

#  RESULT(enginekey) = list of {vu nopm tpm avg p95 p99}
array set RESULT   {}
array set BUILD    {}   ;# BUILD(enginekey)    = schema build wall-clock seconds
array set DATASIZE {}   ;# DATASIZE(enginekey) = {store_dir bytes human}
set PRESENT {}          ;# list of {enginekey label colour pt} that produced data

# MariaDB server lifecycle (via exec)
proc db_ping {} {
    global MARIADB SOCK
    expr {![catch {exec $MARIADB -uroot --socket=$SOCK --skip-ssl -N -B -e {SELECT 1} 2>/dev/null}]}
}

proc server_pid {} {
    global PIDFILE
    if {[catch {open $PIDFILE r} fh]} { return "" }
    set p [string trim [read $fh]]
    catch {close $fh}
    return $p
}

# run a scalar SQL query against the live server; "" on any error
proc sql_scalar {q} {
    global MARIADB SOCK
    if {[catch {exec $MARIADB -uroot --socket=$SOCK --skip-ssl -N -B -e $q 2>/dev/null} out]} {
        return ""
    }
    return [string trim $out]
}

# A clean shutdown must wait for the old mariadbd process and its pid file to be
# gone -- not just for the socket to stop answering.
proc stop_server {} {
    global MARIADB SOCK STOP_TIMEOUT PIDFILE
    set pid [server_pid]
    if {![db_ping] && $pid eq "" && ![file exists $PIDFILE]} { return }
    catch {exec $MARIADB -uroot --socket=$SOCK --skip-ssl -e {SHUTDOWN} 2>/dev/null}
    for {set i 0} {$i < $STOP_TIMEOUT} {incr i} {
        if {![db_ping] && ![file exists $PIDFILE] && !($pid ne "" && [file exists /proc/$pid])} {
            puts "    server stopped (after ${i}s)"
            after 1000
            return
        }
        after 1000
    }
    error "server did not stop within ${STOP_TIMEOUT}s"
}

proc start_server {cnf label} {
    global MARIADBD_SAFE START_TIMEOUT OUTDIR
    stop_server
    set log [file join $OUTDIR logs mariadbd-safe-$label.log]
    puts "    starting: mariadbd-safe --defaults-file=$cnf"
    exec $MARIADBD_SAFE --defaults-file=$cnf >& $log &
    for {set i 0} {$i < $START_TIMEOUT} {incr i} {
        if {[db_ping]} { puts "    server up after ${i}s under $cnf"; return }
        after 1000
    }
    error "server failed to start within ${START_TIMEOUT}s -- see $log and the cnf log-error"
}

# skip an engine cleanly if its cnf needs a plugin .so that isn't installed
proc engine_available {cnf} {
    global PLUGINDIR
    if {[catch {open $cnf r} fh]} { return 1 }
    set txt [read $fh]; catch {close $fh}
    foreach line [split $txt "\n"] {
        if {[regexp {^\s*plugin[-_]load[-_]add\s*=\s*(\S+)} $line -> so]} {
            if {![file exists [file join $PLUGINDIR $so]]} { return 0 }
        }
    }
    return 1
}

proc ensure_user {} {
    global MARIADB SOCK
    set sql {
        CREATE USER IF NOT EXISTS 'hammer'@'localhost' IDENTIFIED BY 'hammer';
        CREATE USER IF NOT EXISTS 'hammer'@'127.0.0.1' IDENTIFIED BY 'hammer';
        CREATE USER IF NOT EXISTS 'hammer'@'%'         IDENTIFIED BY 'hammer';
        GRANT ALL PRIVILEGES ON *.* TO 'hammer'@'localhost' WITH GRANT OPTION;
        GRANT ALL PRIVILEGES ON *.* TO 'hammer'@'127.0.0.1' WITH GRANT OPTION;
        GRANT ALL PRIVILEGES ON *.* TO 'hammer'@'%'         WITH GRANT OPTION;
        FLUSH PRIVILEGES;
    }
    exec $MARIADB -uroot --socket=$SOCK --skip-ssl -e $sql
    puts "    hammer user ensured"
}

# probe / validate / size / clean-assert

# authoritative on-disk data dir for this engine, probed from the live server
# tidesdb -> @@tidesdb_data_home_dir; rocksdb -> @@rocksdb_datadir
# (fallback @@datadir/#rocksdb); innodb -> @@datadir/tpcc (the schema dir)
proc store_dir {engine} {
    global EXPECT_DIR
    set datadir [string trimright [sql_scalar {SELECT @@datadir}] /]
    switch -- $engine {
        tidesdb {
            set d [sql_scalar {SELECT @@tidesdb_data_home_dir}]
            # Some plugin builds leave this variable NULL/empty even though the
            # server opens the store at the expected dir (see "TidesDB opened at
            # ..." in the error log). A NULL is printed as the literal string
            # "NULL" by mariadb -N -B, which would otherwise be mis-joined onto
            # datadir as .../NULL. Fall back to the expected path in that case.
            if {$d eq "" || $d eq "NULL"} {
                set d [dict get $EXPECT_DIR tidesdb]
                puts "    ## NOTE tidesdb_data_home_dir not reported by server -- falling back to expected $d"
            }
        }
        rocksdb {
            set d [sql_scalar {SELECT @@rocksdb_datadir}]
            if {$d eq "" || $d eq "NULL" || $d eq "." || $d eq "./.rocksdb"} { set d "#rocksdb" }
        }
        innodb  {
            # per-table (.ibd) tablespaces live under <datadir>/<schema>, not under
            # innodb_data_home_dir (that only relocates the shared ibdata1). So the
            # tpcc table data is @@datadir/tpcc regardless. Probe file_per_table so a
            # non-default OFF (all data in ibdata1) is surfaced rather than mis-sized.
            set fpt [sql_scalar {SELECT @@innodb_file_per_table}]
            set idh [sql_scalar {SELECT @@innodb_data_home_dir}]
            puts "    innodb probe: datadir='$datadir' file_per_table='$fpt' innodb_data_home_dir='$idh'"
            if {$fpt eq "0" || [string tolower $fpt] eq "off"} {
                puts "    ## WARN innodb file_per_table is OFF -- tpcc data is in the shared ibdata1, not @@datadir/tpcc"
            }
            set d [file join $datadir tpcc]
        }
        default { set d "" }
    }
    # resolve a relative store dir against the server's datadir
    if {$d ne "" && [string index $d 0] ne "/"} { set d [file join $datadir $d] }
    return [string trimright $d /]
}

# validate the probed dir is the expected directory and actually exists
proc validate_store_dir {engine dir} {
    global EXPECT_DIR
    set exp [string trimright [dict get $EXPECT_DIR $engine] /]
    puts "    store dir ($engine): probed='$dir'  expected='$exp'"
    if {$dir eq ""} { error "could not probe store dir for $engine from the live server" }
    if {$dir ne $exp} {
        puts "    ## WARN: probed store dir for $engine != expected config path ($exp)"
    }
    if {![file isdirectory $dir]} {
        error "store dir for $engine is not an existing directory: $dir"
    }
    puts "    store dir ($engine) validated as a real directory"
}

# on-disk size of a directory -> {bytes human}
proc dir_size {dir} {
    if {![file isdirectory $dir]} { return {0 0B} }
    set bytes 0; set human 0B
    catch { set bytes [lindex [exec du -sb  $dir] 0] }
    catch { set human [lindex [exec du -sh  $dir] 0] }
    return [list $bytes $human]
}

# refuse to benchmark on a dirty LSM store, assert no leftover tpcc data
proc assert_store_clean {engine dir} {
    lassign [dir_size $dir] bytes human
    puts "    pre-build store size ($engine): $human ($bytes bytes) at $dir"
    if {$engine eq "tidesdb"} {
        # tidesdb writes one object per table named <db>__<table>; any tpcc* => dirty
        set leftover [glob -nocomplain -directory $dir -tails -- tpcc*]
        if {[llength $leftover]} {
            error "tidesdb store NOT clean -- leftover tpcc objects: $leftover"
        }
    } elseif {$engine eq "rocksdb"} {
        # single shared RocksDB store; empty == CURRENT/MANIFEST/OPTIONS/LOG (<50MB)
        if {$bytes > 52428800} {
            error "rocksdb store NOT clean -- $human present at $dir (expected < 50MB empty)"
        }
    }
    puts "    store ($engine) confirmed clean before build"
}

# Skip unique-key checks during BUILD only (fast bulk load), enforce during the
# measured run -> fair vs InnoDB.
proc unique_skip {engine on} {
    global MARIADB SOCK
    set sql ""
    if {$engine eq "tidesdb"} {
        set sql "SET GLOBAL tidesdb_skip_unique_check=[expr {$on ? 1 : 0}]"
    } elseif {$engine eq "innodb" || $engine eq "rocksdb"} {
        set sql "SET GLOBAL unique_checks=[expr {$on ? 0 : 1}]"
    }
    if {$sql eq ""} { return }
    if {[catch {exec $MARIADB -uroot --socket=$SOCK --skip-ssl -e $sql} e]} {
        puts "    WARN unique_skip($engine,$on): $e"
    } else {
        puts "    unique_skip($engine) build=$on -> $sql"
    }
}

# HammerDB config
proc base_cfg {} {
    dbset db maria
    dbset bm TPC-C
    diset connection maria_host   localhost
    diset connection maria_port   3306
    diset connection maria_socket /tmp/mariadb.sock
    diset tpcc maria_user  hammer
    diset tpcc maria_pass  hammer
    diset tpcc maria_dbase tpcc
}

# pull one job's metrics out of the jobs DB
proc extract {jobid} {
    global JOBSDB
    sqlite3 _jdb $JOBSDB -readonly true
    set nopm 0; set tpm 0; set out ""
    catch {
        set out [_jdb onecolumn {SELECT output FROM JOBOUTPUT
                 WHERE jobid=$jobid AND output LIKE '%TEST RESULT%' LIMIT 1}]
    }
    regexp {achieved ([0-9]+) NOPM from ([0-9]+)} $out -> nopm tpm
    set avg 0; set p50 0; set p95 0; set p99 0; set got 0
    catch {
        _jdb eval {SELECT avg_ms AS a, p50_ms AS p50, p95_ms AS p95, p99_ms AS p99 FROM JOBTIMING
                   WHERE jobid=$jobid AND procname='NEWORD' AND summary=1 LIMIT 1} r {
            set avg $r(a); set p50 $r(p50); set p95 $r(p95); set p99 $r(p99); set got 1
        }
    }
    if {!$got} {
        set calls 0.0; set wa 0.0; set w50 0.0; set w95 0.0; set w99 0.0
        catch {
            _jdb eval {SELECT calls AS c, avg_ms AS a, p50_ms AS p50, p95_ms AS p95, p99_ms AS p99 FROM JOBTIMING
                       WHERE jobid=$jobid AND procname='NEWORD' AND summary=0} r {
                set calls [expr {$calls + $r(c)}]
                set wa    [expr {$wa  + $r(c)*$r(a)}]
                set w50   [expr {$w50 + $r(c)*$r(p50)}]
                set w95   [expr {$w95 + $r(c)*$r(p95)}]
                set w99   [expr {$w99 + $r(c)*$r(p99)}]
            }
        }
        if {$calls > 0} {
            set avg [expr {$wa/$calls}]; set p50 [expr {$w50/$calls}]
            set p95 [expr {$w95/$calls}]; set p99 [expr {$w99/$calls}]
        }
    }
    _jdb close
    return [list $nopm $tpm [format %.2f $avg] [format %.2f $p50] [format %.2f $p95] [format %.2f $p99]]
}

# TPM time-series (10s samples) for one job -> data file of "elapsed_sec tpm"
proc extract_series {jobid engine vu iter} {
    global JOBSDB OUTDIR
    sqlite3 _sdb $JOBSDB -readonly true
    set rows {}
    catch {
        _sdb eval {SELECT counter AS cnt, timestamp AS ts FROM JOBTCOUNT
                   WHERE jobid=$jobid AND metric='tpm' ORDER BY timestamp} r {
            lappend rows [list $r(cnt) $r(ts)]
        }
    }
    _sdb close
    if {[llength $rows] == 0} { return }
    if {[catch {clock scan [lindex [lindex $rows 0] 1] -format {%Y-%m-%d %H:%M:%S} -gmt 1} t0]} { return }
    set rel [file join data ts_${engine}_${vu}vu_iter${iter}.dat]
    set fh [open [file join $OUTDIR $rel] w]
    puts $fh "# elapsed_sec tpm   (job $jobid)"
    foreach row $rows {
        lassign $row cnt ts
        if {[catch {clock scan $ts -format {%Y-%m-%d %H:%M:%S} -gmt 1} t]} { continue }
        puts $fh "[expr {$t - $t0}] $cnt"
    }
    close $fh
}

# output writers
proc write_csv {} {
    global OUTDIR PRESENT RESULT
    set fh [open [file join $OUTDIR results.csv] w]
    puts $fh "engine,vu,iter,nopm,tpm,neword_avg_ms,neword_p50_ms,neword_p95_ms,neword_p99_ms"
    foreach e $PRESENT {
        lassign $e key label
        foreach row [lsort -integer -index 1 [lsort -integer -index 0 $RESULT($key)]] {
            puts $fh "$label,[join $row ,]"
        }
    }
    close $fh
    puts "wrote [file join $OUTDIR results.csv]"
}

proc write_build {} {
    global OUTDIR PRESENT BUILD wh buildvu
    set any 0
    foreach e $PRESENT { lassign $e key; if {[info exists BUILD($key)]} { set any 1 } }
    if {!$any} { return }
    set fh [open [file join $OUTDIR build_times.csv] w]
    puts $fh "engine,warehouses,build_vu,build_seconds"
    foreach e $PRESENT {
        lassign $e key label
        if {[info exists BUILD($key)]} {
            puts $fh "$label,$wh,$buildvu,[format %.1f $BUILD($key)]"
        }
    }
    close $fh
    puts "wrote [file join $OUTDIR build_times.csv]"
}

# on-disk data size per engine, captured after the run and before the delete
proc write_datasizes {} {
    global OUTDIR PRESENT DATASIZE
    set any 0
    foreach e $PRESENT { lassign $e key; if {[info exists DATASIZE($key)]} { set any 1 } }
    if {!$any} { return }
    set fh [open [file join $OUTDIR data_sizes.csv] w]
    puts $fh "engine,store_dir,bytes,human"
    foreach e $PRESENT {
        lassign $e key label
        if {[info exists DATASIZE($key)]} {
            lassign $DATASIZE($key) dir bytes human
            puts $fh "$label,$dir,$bytes,$human"
        }
    }
    close $fh
    puts "wrote [file join $OUTDIR data_sizes.csv]"
}

# =============================== main ========================================
foreach {engine spec} $engines {
    lassign $spec profileid cnf label colour pt
    if {![engine_available $cnf]} {
        puts "############################################################"
        puts "## SKIP $label: required plugin not installed (see plugin_load_add in $cnf)"
        puts "############################################################"
        continue
    }
    if {[catch {
        puts "############################################################"
        puts "## ENGINE: $label  (profileid $profileid, cnf $cnf)"
        puts "############################################################"

        start_server $cnf $label
        ensure_user

        jobs profileid $profileid

        # clean slate (server up -> correct plugin available)
        base_cfg
        diset tpcc maria_storage_engine $engine
        catch { vudestroy }
        catch { deleteschema }
        catch { vudestroy }

        # probe + validate the engine's on-disk store, and (for the LSM stores
        # the comparison cares about) PROVE it is clean before we build
        set _store [store_dir $engine]
        if {$engine ne "innodb"} {
            validate_store_dir $engine $_store
            assert_store_clean $engine $_store
        } else {
            puts "    innodb store dir (created by build): $_store"
        }

        # BUILD (unique checks skipped for a fast load on BOTH engines)
        puts ">>> $label: BUILD ($wh warehouses, $buildvu build VUs)"
        unique_skip $engine 1
        base_cfg
        diset tpcc maria_count_ware     $wh
        diset tpcc maria_num_vu         $buildvu
        diset tpcc maria_storage_engine $engine
        diset tpcc maria_partition      false
        set _bt0 [clock milliseconds]
        buildschema
        set BUILD($engine) [expr {([clock milliseconds] - $_bt0) / 1000.0}]
        puts ">>> $label: BUILD took [format %.1f $BUILD($engine)] s"
        catch { vudestroy }
        unique_skip $engine 0   ;# enforce uniqueness for the measured run

        # CHECK
        puts ">>> $label: CHECK"
        base_cfg
        diset tpcc maria_storage_engine $engine
        checkschema
        catch { vudestroy }

        # RUN SWEEP
        puts ">>> $label: RUN SWEEP $vu_list"
        base_cfg
        diset tpcc maria_driver       timed
        diset tpcc maria_rampup       $rampup
        diset tpcc maria_duration     $duration
        diset tpcc maria_timeprofile  true
        diset tpcc maria_allwarehouse false
        diset tpcc maria_partition    false

        foreach z $vu_list {
            for {set it 1} {$it <= $iters} {incr it} {
                puts "---- $label: $z VU  iter $it/$iters ----"
                loadscript
                vuset vu $z
                vuset logtotemp 1
                vucreate
                tcstart
                tcstatus
                set raw [ vurun ]
                tcstop
                vudestroy
                set jobid $raw
                if {![regexp {jobid=([0-9A-Za-z]+)} $raw -> jobid]} {
                    regexp {([0-9A-Fa-f]{16,})} $raw jobid
                }
                set m [extract $jobid]
                lappend RESULT($engine) [concat $z $it $m]
                extract_series $jobid $engine $z $it
                puts "---- $label: $z VU iter $it  jobid=$jobid  nopm=[lindex $m 0] tpm=[lindex $m 1] no_p99=[lindex $m 5]ms ----"
            }
        }

        if {[info exists RESULT($engine)]} {
            lappend PRESENT [list $engine $label $colour $pt]
        }

        # DATA SIZE on disk -- captured AFTER the measured run, BEFORE delete.
        # Re-probe (innodb's tpcc dir now exists) and validate the dir is real.
        set _store [store_dir $engine]
        catch { validate_store_dir $engine $_store }
        lassign [dir_size $_store] _bytes _human
        set DATASIZE($engine) [list $_store $_bytes $_human]
        puts ">>> $label: on-disk data size = $_human ($_bytes bytes) at $_store"
        if {$engine eq "innodb"} {
            # InnoDB also uses shared files in @@datadir (ibdata1, undo*, ib_logfile*)
            # not counted above; report the datadir total for full context.
            set _dd [string trimright [sql_scalar {SELECT @@datadir}] /]
            lassign [dir_size $_dd] _ddb _ddh
            puts ">>> $label: (context) full @@datadir = $_ddh ($_ddb bytes) at $_dd -- includes shared ibdata1/undo/redo + system schemas"
        }

        # DELETE (free disk before the next engine)
        puts ">>> $label: DELETE schema"
        catch { vudestroy }
        base_cfg
        diset tpcc maria_storage_engine $engine
        catch { deleteschema }
        catch { vudestroy }
        puts ">>> $label: DONE"

    } err]} {
        puts "!!! ENGINE $label FAILED: $err  -- continuing"
        catch { vudestroy }
        if {[info exists RESULT($engine)]} {
            lappend PRESENT [list $engine $label $colour $pt]
        }
    }
}

# stop the last engine's server so nothing is left running
catch { stop_server }

# write all artefacts
if {[llength $PRESENT] == 0} {
    puts "!!! no results captured -- nothing to write"
} else {
    write_csv
    write_build
    write_datasizes
    catch { file copy -force $JOBSDB [file join $OUTDIR hammer.DB] }
    puts "############################################################"
    puts "## RESULTS (engine vu iter nopm tpm no_avg no_p50 no_p95 no_p99)"
    foreach e $PRESENT {
        lassign $e key label
        foreach row [lsort -integer -index 1 [lsort -integer -index 0 $RESULT($key)]] {
            puts "## $label [join $row { }]"
        }
    }
    puts "## ---- on-disk data size (after run, before delete) ----"
    foreach e $PRESENT {
        lassign $e key label
        if {[info exists DATASIZE($key)]} {
            lassign $DATASIZE($key) dir bytes human
            puts "## $label  $human  ($bytes bytes)  $dir"
        }
    }
    puts "## artefacts in $OUTDIR"
    puts "############################################################"
}
#!/usr/bin/env bash
# Per engine:
#   1. restore the pristine datadir (system tables + benchmark user)
#   2. build the schema under a BUILD overlay (READ COMMITTED; everything else
#      as the run config), checkschema, clean shutdown
#   3. save a golden copy of the built database
#   4. per run - restore golden -> drop page cache -> start server in a
#      memory-limited cgroup -> verify the config took -> one timed run under a
#      wall-clock watchdog -> extract -> stop
#   5. sweep VU_LIST once each, then PEAK_ITERS runs at that engine's peak VU
#
# Smoke test:
#   WH=10 BUILDVU=4 VU_LIST="4 8" RAMPUP=1 DURATION=2 PEAK_ITERS=1 \
#   OUTDIR=/root/sqlanalysis/smoke ./bench.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
: "${OUTDIR:=/root/sqlanalysis/run3000}"
: "${ENGINES:=tidesdb innodb}"
: "${WH:=3000}"
: "${BUILDVU:=24}"
: "${VU_LIST:=4 8 16 32 64 128}"
: "${RAMPUP:=10}"
: "${DURATION:=20}"
: "${PEAK_ITERS:=3}"
: "${PARTITION:=$([ "$WH" -ge 200 ] && echo true || echo false)}"   # HammerDB's own rule
: "${MEMMAX:=96G}"          # same cap for both engines; includes page cache
: "${GOLDEN:=/bench-golden}"
: "${SAMPLE_INT:=1}"        # engine/RSS sampling interval, matches tcset refreshrate
: "${STALL_FLOOR:=1000}"    # tpm below this for 2 samples = stalled -> capture diagnostics
: "${KEEP_GOLDEN:=0}"
: "${CPUS:=$(lscpu -p=CPU,ONLINE | awk -F, '!/^#/ && $2=="Y"{printf "%s%s",s,$1; s=","}')}"

BASE=/data/mariadb; BIN=$BASE/bin; DATADIR=$BASE/data; TDBDIR=$BASE/tidesdb_data
SOCK=/tmp/mariadb.sock; HDB=/root/HammerDB-6.0
M="$BIN/mariadb -uroot --socket=$SOCK --skip-ssl"
declare -A CNF=([tidesdb]=/root/sqlanalysis/tidesdb.cnf [innodb]=/root/sqlanalysis/innodb.cnf)
declare -A LABEL=([tidesdb]=TidesDB [innodb]=InnoDB)

mkdir -p "$OUTDIR"/{logs,data,cnf} "$GOLDEN"
export TMP="$OUTDIR/hdbtmp"; mkdir -p "$TMP"
export WH BUILDVU PARTITION RAMPUP DURATION
JOBSDB="$TMP/hammer.DB"
LOG="$OUTDIR/bench.log"
log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }
die() { log "FATAL: $*"; stop_server; exit 1; }

# exact matching only: a shell whose command line merely mentions the server
# must never look like the server (this cost 10 minutes and a kill last time)
srv_pids() { pgrep -x mariadbd; pgrep -f "^/bin/sh $BIN/mariadbd-safe"; }
server_up() { $M -N -B -e "SELECT 1" >/dev/null 2>&1; }

stop_server() {
    server_up && $M -e "SHUTDOWN" >/dev/null 2>&1
    for _ in $(seq 600); do [ -z "$(srv_pids)" ] && break; sleep 1; done
    if [ -n "$(srv_pids)" ]; then log "server did not stop, killing"; kill -9 $(srv_pids) 2>/dev/null; sleep 3; fi
    rm -f "$DATADIR/mariadb.pid" "$SOCK"
    return 0
}

start_server() {   # cnf tag
    [ -z "$(srv_pids)" ] || die "a server is already running"
    systemd-run --scope -q --unit="bench-$$-$RANDOM" -p MemoryMax="$MEMMAX" -p MemorySwapMax=0 \
        taskset -c "$CPUS" "$BIN/mariadbd-safe" --defaults-file="$1" \
        >"$OUTDIR/logs/server-$2.log" 2>&1 &
    for _ in $(seq 900); do server_up && return 0; sleep 1; done
    tail -30 "$DATADIR/mariadb.err" >>"$LOG" 2>/dev/null
    die "server failed to start ($2)"
}

# Refuse to measure a server that did not take its configuration.
verify_config() {   # engine tag mode
    local e=$1 tag=$2 mode=$3 f="$OUTDIR/logs/config-$2.txt" bad=""
    $M -N -B -e "SELECT @@version; SHOW GLOBAL VARIABLES;
                 SELECT PLUGIN_NAME,PLUGIN_STATUS,PLUGIN_MATURITY FROM information_schema.PLUGINS
                 WHERE PLUGIN_TYPE='STORAGE ENGINE';" >"$f" 2>&1
    v() { awk -v k="$1" '$1==k{print $2; exit}' "$f"; }
    local want; want=$([ "$e" = tidesdb ] && echo TidesDB || echo InnoDB)
    [ "$(v default_storage_engine)" = "$want" ] || bad+=" engine=$(v default_storage_engine)"
    [ "$(v log_bin)" = "OFF" ] || bad+=" log_bin=$(v log_bin)"
    if [ "$mode" = run ]; then
        [ "$(v transaction_isolation)" = "REPEATABLE-READ" ] || bad+=" iso=$(v transaction_isolation)"
        if [ "$e" = tidesdb ]; then
            [ "$(v tidesdb_memtable_sync_mode)" = "NONE" ] || bad+=" sync=$(v tidesdb_memtable_sync_mode)"
            [ "$(v tidesdb_block_cache_size)" = "34359738368" ] || bad+=" cache=$(v tidesdb_block_cache_size)"
            [ "$(v tidesdb_max_open_sstables)" = "65536" ] || bad+=" open_sst=$(v tidesdb_max_open_sstables)"
            [ "$(v tidesdb_log_level)" = "NONE" ] || bad+=" log_level=$(v tidesdb_log_level)"
            grep -qiE "^tidesdb[[:space:]]+ACTIVE" "$f" || bad+=" plugin-not-active"
        else
            [ "$(v innodb_flush_log_at_trx_commit)" = "0" ] || bad+=" flush=$(v innodb_flush_log_at_trx_commit)"
            [ "$(v innodb_doublewrite)" = "ON" ] || bad+=" doublewrite=$(v innodb_doublewrite)"
            [ "$(v innodb_buffer_pool_size)" = "68719476736" ] || bad+=" pool=$(v innodb_buffer_pool_size)"
        fi
    fi
    [ -z "$bad" ] || die "config check failed ($tag):$bad"
    log "config ok ($tag): $(head -1 "$f") $want $mode"
}

# data state
save_copy() {   # dest
    rm -rf "$1"; mkdir -p "$1"
    cp -a "$DATADIR" "$1/data"
    [ -d "$TDBDIR" ] && cp -a "$TDBDIR" "$1/tidesdb_data"
    sync
}

restore_copy() {   # src tag
    [ -d "$1/data" ] || die "no copy at $1"
    stop_server
    # keep this run's server log before the restore overwrites it -- losing these
    # is why an 18-minute stall last time could not be diagnosed afterwards
    [ -n "${2:-}" ] && [ -f "$DATADIR/mariadb.err" ] && cp "$DATADIR/mariadb.err" "$OUTDIR/logs/err-$2.log"
    rm -rf "$DATADIR" "$TDBDIR"
    cp -a "$1/data" "$DATADIR"
    [ -d "$1/tidesdb_data" ] && cp -a "$1/tidesdb_data" "$TDBDIR"
    # the copy leaves the database in the page cache, which TidesDB (buffered
    # reads) could exploit and InnoDB (O_DIRECT) could not - start every run cold
    sync; echo 3 > /proc/sys/vm/drop_caches
}

make_pristine() {
    [ -d "$GOLDEN/pristine/data" ] && { log "pristine copy exists"; return; }
    [ -d "$TDBDIR" ] && [ -n "$(ls -A "$TDBDIR" 2>/dev/null)" ] && die "$TDBDIR not empty"
    log "creating pristine datadir copy"
    start_server "$BASE/my.cnf" pristine
    $M -e "CREATE USER IF NOT EXISTS 'hammer'@'localhost' IDENTIFIED BY 'hammer';
           GRANT ALL PRIVILEGES ON *.* TO 'hammer'@'localhost' WITH GRANT OPTION;
           DROP DATABASE IF EXISTS tpcc;" || die "could not create hammer user"
    stop_server; rm -rf "$TDBDIR"
    save_copy "$GOLDEN/pristine"
}

# hammerdb 
hdb() {   # timeout script logfile
    ( cd "$HDB" && timeout --signal=KILL "$1" taskset -c "$CPUS" ./hammerdbcli auto "$2" ) >"$3" 2>&1
}

# if the transaction counter flatlines while a run should be busy,
# capture what the engine is doing and let the run continue.
stall_watch() {   # tag logfile
    local tag=$1 rl=$2 low=0
    sleep $(( RAMPUP * 60 + 60 ))
    while kill -0 "$HDB_PID" 2>/dev/null; do
        local tpm; tpm=$(grep -aoE "^[0-9]+ MariaDB tpm" "$rl" | tail -1 | awk '{print $1}')
        if [ -n "$tpm" ] && [ "$tpm" -lt "$STALL_FLOOR" ]; then
            low=$((low+1))
            if [ "$low" -ge 2 ]; then
                log "STALL detected in $tag (tpm=$tpm) -- capturing diagnostics"
                local d="$OUTDIR/logs/stall-$tag"; mkdir -p "$d"
                $M -e "SHOW ENGINE ${ENG_UP} STATUS\G" >"$d/engine-status.txt" 2>&1
                $M -e "SHOW FULL PROCESSLIST" >"$d/processlist.txt" 2>&1
                local pid; pid=$(pgrep -x mariadbd | head -1)
                cat /proc/$pid/status >"$d/proc-status.txt" 2>&1
                for t in /proc/$pid/task/*; do
                    echo "--- $t" >>"$d/stacks.txt"; cat $t/stack >>"$d/stacks.txt" 2>/dev/null
                done
                timeout 35 perf record -F 99 -g -p "$pid" -o "$d/perf.data" -- sleep 30 >/dev/null 2>&1
                log "STALL diagnostics in $d"
                low=0
            fi
        else low=0; fi
        sleep 30
    done
}

build_engine() {
    local e=$1 bcnf="$OUTDIR/cnf/build-$e.cnf"
    cp "${CNF[$e]}" "$bcnf"
    { echo; echo "[mysqld]"; echo "# BUILD overlay (bench.sh), not a measured run
      echo "transaction_isolation=READ-COMMITTED"; } >>"$bcnf"
    restore_copy "$GOLDEN/pristine"
    start_server "$bcnf" "build-$e"
    verify_config "$e" "build-$e" build
    log "building $e: $WH WH, $BUILDVU build VUs, partition=$PARTITION"
    local t0=$SECONDS
    export ENGINE=$e
    hdb $(( WH * 20 + 3600 )) "$HERE/hdb_build.tcl" "$OUTDIR/logs/hdb-build-$e.log"
    local secs=$(( SECONDS - t0 ))
    grep -q BENCH_CHECK_DONE "$OUTDIR/logs/hdb-build-$e.log" || die "build/check failed for $e"
    grep -qiE "Error in Virtual User|FINISHED FAILED" "$OUTDIR/logs/hdb-build-$e.log" && die "build had VU errors ($e)"
    $M -N -B -e "SELECT TABLE_NAME,ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA='tpcc'" \
        >"$OUTDIR/logs/tables-$e.txt"
    local want; want=$([ "$e" = tidesdb ] && echo TidesDB || echo InnoDB)
    awk -v w="$want" '$2!=w{bad=1} END{exit bad}' "$OUTDIR/logs/tables-$e.txt" || die "tpcc tables not all $want"
    stop_server
    local size; size=$(du -sb "$DATADIR" "$TDBDIR" 2>/dev/null | awk '{s+=$1} END{print s}')
    [ -f "$OUTDIR/build_times.csv" ] || echo "engine,warehouses,build_vu,build_seconds,bytes_on_disk" >"$OUTDIR/build_times.csv"
    echo "${LABEL[$e]},$WH,$BUILDVU,$secs,$size" >>"$OUTDIR/build_times.csv"
    log "built $e in ${secs}s, $(numfmt --to=iec "$size"); saving golden copy"
    save_copy "$GOLDEN/$e"
}

one_run() {   # engine phase vu iter
    local e=$1 ph=$2 vu=$3 it=$4 tag="$1-$3vu-$2-$4"
    restore_copy "$GOLDEN/$e" "$tag"
    start_server "${CNF[$e]}" "run-$tag"
    verify_config "$e" "run-$tag" run
    ENG_UP=$([ "$e" = tidesdb ] && echo TIDESDB || echo INNODB)
    "$HERE/sample.sh" "$OUTDIR/logs/sample-$tag.csv" "$e" "$SAMPLE_INT" & local SP=$!
    $M -e "SHOW ENGINE $ENG_UP STATUS\G" >"$OUTDIR/logs/status-$tag-before.txt" 2>&1
    log "run $tag: ${RAMPUP}m rampup + ${DURATION}m measure"
    export VU=$vu
    local rl="$OUTDIR/logs/hdb-$tag.log"
    hdb $(( (RAMPUP + DURATION) * 60 + 900 )) "$HERE/hdb_run.tcl" "$rl" & HDB_PID=$!
    stall_watch "$tag" "$rl" & local WP=$!
    wait $HDB_PID; local rc=$?
    kill $WP 2>/dev/null; kill $SP 2>/dev/null
    local timed_out=0
    { [ $rc -eq 137 ] || [ $rc -eq 124 ]; } && { timed_out=1; log "run $tag TIMED OUT"; }
    local jobid; jobid=$(awk '/BENCH_JOBID/{print $2}' "$rl" | tail -1)
    local jdb; jdb=$(grep -aoE "on-disk database [^ ]+" "$rl" | awk '{print $3}' | tail -1)
    [ -n "$jdb" ] && [ -f "$jdb" ] && JOBSDB=$jdb
    $M -e "SHOW ENGINE $ENG_UP STATUS\G" >"$OUTDIR/logs/status-$tag-after.txt" 2>&1
    python3 "$HERE/extract.py" "$JOBSDB" "$OUTDIR" "${LABEL[$e]}" "$ph" "$vu" "$it" "${jobid:--}" "$timed_out" | tee -a "$LOG"
    stop_server
}

peak_vu() { awk -F, -v e="${LABEL[$1]}" '$1==e && $2=="sweep" && $13=="ok" && $5>b {b=$5; v=$3} END{print v}' "$OUTDIR/results.csv"; }

write_run_json() {
    python3 - "$OUTDIR/run.json" <<EOF
import json, subprocess, sys
v = subprocess.run(["$BIN/mariadbd","--version"], capture_output=True, text=True).stdout.split()[2]
json.dump({
 "mariadb_version": v.split("-")[0], "tidesdb_version": "10.1.0", "tidesql_version": "5.1.0",
 "hammerdb_version": "6.0", "warehouses": $WH, "build_vu": $BUILDVU,
 "partition": "$PARTITION" == "true", "vu_list": [int(x) for x in "$VU_LIST".split()],
 "rampup_min": $RAMPUP, "duration_min": $DURATION, "peak_iters": $PEAK_ITERS,
 "isolation": "REPEATABLE READ",
 "durability": "non-durable (commit to OS, doublewrite on, binlog off)",
 "use_all_warehouses": True, "sample_interval_s": $SAMPLE_INT,
 "memory": "64G engine budget each, cgroup MemoryMax=$MEMMAX, caches dropped before each run",
 "state": "database restored from a golden copy before every run",
 "host": "i9-13900 (8P+16E, 24 threads), 125 GB RAM, NVMe; HammerDB on the same host",
 "cpus": "$CPUS"}, open(sys.argv[1],"w"), indent=1)
EOF
}

# main 
log "=== start: engines=[$ENGINES] WH=$WH VU=[$VU_LIST] ${RAMPUP}+${DURATION}m peak=$PEAK_ITERS mem=$MEMMAX"
/root/sqlanalysis/check-parity.sh | tee -a "$LOG" || die "cnf parity check failed"
cp "${CNF[tidesdb]}" "${CNF[innodb]}" "$OUTDIR/cnf/"
cp /root/sqlanalysis/plot.py "$OUTDIR/" 2>/dev/null
write_run_json
stop_server
make_pristine

for e in $ENGINES; do
    build_engine "$e"
    for vu in $VU_LIST; do one_run "$e" sweep "$vu" 1; done
    pv=$(peak_vu "$e")
    if [ -n "$pv" ] && [ "$PEAK_ITERS" -gt 0 ]; then
        log "$e peak at $pv VU; $PEAK_ITERS runs there"
        for i in $(seq 1 "$PEAK_ITERS"); do one_run "$e" peak "$pv" "$i"; done
    else
        log "$e: no ok sweep run to take a peak from"
    fi
    [ "$KEEP_GOLDEN" = 1 ] || { log "removing golden copy for $e"; rm -rf "$GOLDEN/$e"; }
done

restore_copy "$GOLDEN/pristine" final
log "=== done; plotting"
( cd "$OUTDIR" && python3 plot.py --dir . ) 2>&1 | tee -a "$LOG"

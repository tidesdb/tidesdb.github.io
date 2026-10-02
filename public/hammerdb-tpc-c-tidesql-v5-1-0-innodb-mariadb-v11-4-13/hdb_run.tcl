# One timed TPROC-C run. bench.sh restores the DB, starts the server and enforces a timeout.
proc need {n} { if {![info exists ::env($n)]} { puts "BENCH_ERROR missing env $n"; exit 1 }; return $::env($n) }
dbset db maria
dbset bm TPC-C
diset connection maria_host localhost
diset connection maria_port 3306
diset connection maria_socket /tmp/mariadb.sock
diset tpcc maria_user hammer
diset tpcc maria_pass hammer
diset tpcc maria_dbase tpcc
diset tpcc maria_driver      timed
diset tpcc maria_rampup      [need RAMPUP]
diset tpcc maria_duration    [need DURATION]
# every VU draws a new warehouse per transaction from the whole schema; without
# this each VU keeps one home warehouse and a 3000 WH build is mostly idle
diset tpcc maria_allwarehouse true
diset tpcc maria_timeprofile true
diset tpcc maria_keyandthink false
# log and continue on a transaction error; the aborted txn is not counted in NOPM
diset tpcc maria_raiseerror  false
# state is reset by restoring a copy of the database before every run
diset tpcc maria_purge       false
giset commandline keepalive_margin 1200
giset timeprofile  xt_gather_timeout 1200
# 1 s transaction counter samples (default 10) for a readable throughput timeline
tcset refreshrate 1
tcset timestamps 1
loadscript
vuset vu [need VU]
vuset logtotemp 1
vucreate
tcstart
tcstatus
set raw [vurun]
tcstop
catch { vudestroy }
set jobid ""
if {![regexp {jobid=([0-9A-Za-z]+)} $raw -> jobid]} { regexp {([0-9A-Fa-f]{16,})} $raw jobid }
puts "BENCH_JOBID $jobid"

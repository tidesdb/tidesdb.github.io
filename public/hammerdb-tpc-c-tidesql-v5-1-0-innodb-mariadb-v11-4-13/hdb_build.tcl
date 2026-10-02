# Build the TPROC-C schema for one engine. All settings from the environment.
proc need {n} { if {![info exists ::env($n)]} { puts "BENCH_ERROR missing env $n"; exit 1 }; return $::env($n) }
dbset db maria
dbset bm TPC-C
diset connection maria_host localhost
diset connection maria_port 3306
diset connection maria_socket /tmp/mariadb.sock
diset tpcc maria_user hammer
diset tpcc maria_pass hammer
diset tpcc maria_dbase tpcc
diset tpcc maria_count_ware     [need WH]
diset tpcc maria_num_vu         [need BUILDVU]
diset tpcc maria_storage_engine [need ENGINE]
diset tpcc maria_partition      [need PARTITION]
diset tpcc maria_history_pk     false
giset commandline keepalive_margin 7200
puts "BENCH_BUILD_START"
buildschema
catch { vudestroy }
puts "BENCH_BUILD_DONE"
checkschema
catch { vudestroy }
puts "BENCH_CHECK_DONE"

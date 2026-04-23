set tmpdir $::env(TMP)
puts "SETTING CONFIGURATION"
dbset db maria
dbset bm TPC-C
diset connection maria_host localhost
diset connection maria_port 3306
diset connection maria_socket /tmp/mariadb.sock
diset tpcc maria_user hammerdb
diset tpcc maria_pass hammerdb123
diset tpcc maria_dbase tpcc
diset tpcc maria_driver timed
diset tpcc maria_rampup 1
diset tpcc maria_duration 2
diset tpcc maria_allwarehouse true
diset tpcc maria_timeprofile true
loadscript
puts "TEST STARTED"
vuset vu 8
vucreate
tcstart
tcstatus
set jobid [ vurun ]
vudestroy
tcstop
puts "TEST COMPLETE"
set of [ open $tmpdir/maria_tprocc w ]
puts $of $jobid
close $of

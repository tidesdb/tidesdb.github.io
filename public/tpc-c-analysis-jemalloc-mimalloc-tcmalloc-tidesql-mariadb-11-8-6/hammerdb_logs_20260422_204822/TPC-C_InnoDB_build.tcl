puts "SETTING CONFIGURATION"
dbset db maria
dbset bm TPC-C
diset connection maria_host localhost
diset connection maria_port 3306
diset connection maria_socket /tmp/mariadb.sock
diset tpcc maria_count_ware 40
diset tpcc maria_num_vu 8
diset tpcc maria_user hammerdb
diset tpcc maria_pass hammerdb123
diset tpcc maria_dbase tpcc
diset tpcc maria_storage_engine [string tolower InnoDB]
diset tpcc maria_partition false
puts "SCHEMA BUILD STARTED"
buildschema
puts "SCHEMA BUILD COMPLETED"

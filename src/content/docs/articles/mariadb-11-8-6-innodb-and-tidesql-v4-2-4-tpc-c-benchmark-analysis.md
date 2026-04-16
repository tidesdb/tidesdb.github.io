---
title: "MariaDB 11.8.6 InnoDB & TidesDB (TideSQL v4.2.4) TPC-C Benchmark Analysis"
description: "Analysis on small cache/buffer and large cache/buffer configurations storage engine performance comparison in MariaDB 11.8.6 InnoDB and TidesDB (TideSQL v4.2.4) TPC-C benchmarks."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-victoria-bowers-148548814-34000749.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-victoria-bowers-148548814-34000749.jpg
---

<div class="article-image">

![MariaDB 11.8.6 InnoDB & TidesDB (TideSQL v4.2.4) TPC-C Benchmark Analysis](/pexels-victoria-bowers-148548814-34000749.jpg)

</div>

*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on April 16th, 2026*

Following on the last lower level engine <a target="_blank" href="/articles/benchmark-analysis-tidesdb-v9-8-0-rocksdb-v11-0-4">analysis</a>, this analysis is the latest version of <a target="_blank" href="/reference/tidesql/">TideSQL v4.2.4</a> and <a target="_blank" href="https://github.com/tidesdb/tidesdb">TidesDB v9.0.8</a> within <a target="_blank" href="https://mariadb.com/">MariaDB 11.8.6</a>.  I am running TPC-C benchmarks utilizing <a target="_blank" href="https://hammerdb.com/">HammerDB</a>.

System specs
- AMD Ryzen Threadripper 2950X (16 cores 32 threads) @ 3.5GHz
- 128GB DDR4
- Ubuntu 22.04 x86_64
- GCC (glibc)
- XFS raw NVMe(SAMSUNG MZVLB512HAJQ-00000) w/discard, inode64, nodiratime, noatime, logbsize=256k, logbufs=8

First run, small buffers/caches at 64mb to see how the engines perform utilizing memory and disk i/o.

For each run I used `hammerdb_runner.sh` examples
```
./hammerdb_runner.sh -b tpcc --warehouses 40 --tpcc-vu 8 --tpcc-build-vu 8 --rampup 1 --duration 2 --settle 5 -H ~/HammerDB-5.0 -e innodb -u hammerdb --pass hammerdb123 -S /tmp/mariadb.sock

./hammerdb_runner.sh -b tpcc --warehouses 40 --tpcc-vu 8 --tpcc-build-vu 8 --rampup 1 --duration 2 --settle 5 -H ~/HammerDB-5.0 -e tidesdb -u hammerdb --pass hammerdb123 -S /tmp/mariadb.sock

```

The hammerdb_runner is available here: [hammerdb_runner.sh](/mariadb-11-8-6-innodb-and-tidesql-v4-2-4-tpc-c/hammerdb_runner.sh)


<details>
  <summary>Click to see MariaDB config</summary>
  
```
[mysqld]
basedir = /data/mariadb
datadir = /data/mariadb/data
port    = 3306
socket  = /tmp/mariadb.sock
user    = root
pid-file = /data/mariadb/data/mariadb.pid
log-error = /data/mariadb/data/mariadb.err

# Networking
bind-address = 127.0.0.1
max_connections = 1024
# thread_handling = pool-of-threads
# thread_pool_size = 16
table_open_cache=2000
table_open_cache_instances=16
back_log=1500
max_prepared_stmt_count=102400
innodb_open_files=1024

sort_buffer_size = 4M
join_buffer_size = 4M
read_buffer_size = 2M
read_rnd_buffer_size = 2M
tmp_table_size = 64M
max_heap_table_size = 64M

skip-log-bin
sync_binlog = 0

table_open_cache = 4096
table_definition_cache = 2048

# InnoDB (inspired by https://hammerdb.com/ci-config/maria.cnf)
default_storage_engine = InnoDB
innodb_buffer_pool_size = 64M
#innodb_buffer_pool_instances = 4
innodb_log_file_size = 24M
innodb_log_buffer_size = 24M
innodb_flush_log_at_trx_commit = 0
innodb_file_per_table = ON
innodb_doublewrite = 0
innodb_flush_method = O_DIRECT
innodb_io_capacity = 10000
innodb_io_capacity_max = 20000
innodb_purge_threads = 4
innodb_max_purge_lag_wait=0
innodb_max_purge_lag=0
innodb_max_purge_lag_delay=1
innodb_lru_scan_depth=128
innodb_read_only=0
innodb_adaptive_hash_index=0
innodb_undo_log_truncate=on
innodb_undo_tablespaces=1
innodb_fast_shutdown=0
innodb_max_dirty_pages_pct=1
innodb_max_dirty_pages_pct_lwm=0.1
innodb_adaptive_flushing=1
innodb_adaptive_flushing_lwm=0.1
innodb_flush_neighbors=0
innodb_read_io_threads=4
innodb_write_io_threads=4
innodb_read_ahead_threshold=0
innodb_buffer_pool_dump_at_shutdown=0
innodb_buffer_pool_load_at_startup=0
join_buffer_size=32K
sort_buffer_size=32K
innodb_use_native_aio=1
innodb_stats_persistent=1
innodb_log_write_ahead_size=4096
performance_schema=OFF

# Logging
slow_query_log = ON
slow_query_log_file = /data/mariadb/data/slow.log
long_query_time = 2

# Character set
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci

# TidesDB
plugin_load_add = ha_tidesdb.so
plugin_maturity = gamma

# Row locking, optimistic by default
tidesdb_pessimistic_locking = OFF

tidesdb_block_cache_size = 64M
tidesdb_max_open_sstables = 512
tidesdb_unified_memtable_sync_mode = NONE
tidesdb_unified_memtable_write_buffer_size = 64M
tidesdb_default_write_buffer_size = 64M
tidesdb_default_sync_mode = NONE
tidesdb_default_compression = NONE
tidesdb_flush_threads = 4
tidesdb_compaction_threads = 4
tidesdb_log_level = NONE
# tidesdb_print_all_conflicts = ON

[client]
port = 3306
socket = /tmp/mariadb.sock
default-character-set = utf8mb4

[mysqldump]
quick
max_allowed_packet = 64M

[mariadb-backup]
# mariabackup settings (defaults are fine)

```

</details>

Both engines are aligned in configuration. Results below.

![](/mariadb-11-8-6-innodb-and-tidesql-v4-2-4-tpc-c/hammerdb_results_20260416_180716/chart_tpcc_nopm.png)
![](/mariadb-11-8-6-innodb-and-tidesql-v4-2-4-tpc-c/hammerdb_results_20260416_180716/chart_tpcc_latency.png)
![](/mariadb-11-8-6-innodb-and-tidesql-v4-2-4-tpc-c/hammerdb_results_20260416_180716/chart_tpcc_tpm.png)


![](/mariadb-11-8-6-innodb-and-tidesql-v4-2-4-tpc-c/hammerdb_results_20260416_182002/chart_tpcc_nopm.png)
![](/mariadb-11-8-6-innodb-and-tidesql-v4-2-4-tpc-c/hammerdb_results_20260416_182002/chart_tpcc_latency.png)
![](/mariadb-11-8-6-innodb-and-tidesql-v4-2-4-tpc-c/hammerdb_results_20260416_182002/chart_tpcc_tpm.png)


At 64MB TidesDB hit 69,320 NOPM / 160,779 TPM versus InnoDB's 16,816 NOPM / 39,251 TPM, a 4.12x gap. NEWORD average fell from 8.18 ms to 3.723 ms, p99 from 16.442 ms to 5.89 ms. PAYMENT went 7.52 ms / 21.392 ms p99 down to 1.437 ms / 3.23 ms p99. DELIVERY, the heaviest transaction, dropped from 65.521 ms / 87.456 ms p99 to 10.28 ms / 16.878 ms p99, and SLEV collapsed from 55.293 ms average to 2.147 ms. InnoDB is thrashing a buffer pool that cannot fit the working set, paging B-tree and undo constantly. TidesDB writes land in the memtable and flush out sequentially, so the 64MB block cache plus bloom filters are enough to keep reads cheap.

Second run, larger buffers/caches mainly. For TidesDB we have 16GB block cache and 512MB unified memtable size. For InnoDB we have 16GB buffer pool and some other settings to align with TidesDB. This is testing mainly memory utilization, contention, etc.

<details>
  <summary>Click to see MariaDB config</summary>
  
```
[mysqld]
basedir = /data/mariadb
datadir = /data/mariadb/data
port    = 3306
socket  = /tmp/mariadb.sock
user    = root
pid-file = /data/mariadb/data/mariadb.pid
log-error = /data/mariadb/data/mariadb.err

# Networking
bind-address = 127.0.0.1
max_connections = 1024
# thread_handling = pool-of-threads
# thread_pool_size = 16
table_open_cache=2000
table_open_cache_instances=16
back_log=1500
max_prepared_stmt_count=102400
innodb_open_files=1024

sort_buffer_size = 24M
join_buffer_size = 24M
read_buffer_size = 24M
read_rnd_buffer_size = 24M
tmp_table_size = 4G
max_heap_table_size = 256M

skip-log-bin
sync_binlog = 0

table_open_cache = 4096
table_definition_cache = 2048

# InnoDB (inspired by https://hammerdb.com/ci-config/maria.cnf)
default_storage_engine = InnoDB
innodb_buffer_pool_size = 16G
#innodb_buffer_pool_instances = 4
innodb_log_file_size = 2G
innodb_log_buffer_size = 512M
innodb_flush_log_at_trx_commit = 0
innodb_file_per_table = ON
innodb_doublewrite = 0
innodb_flush_method = O_DIRECT
innodb_io_capacity = 10000
innodb_io_capacity_max = 20000
innodb_purge_threads = 4
innodb_max_purge_lag_wait=0
innodb_max_purge_lag=0
innodb_max_purge_lag_delay=1
innodb_lru_scan_depth=128
innodb_read_only=0
innodb_adaptive_hash_index=0
innodb_undo_log_truncate=on
innodb_undo_tablespaces=1
innodb_fast_shutdown=0
innodb_max_dirty_pages_pct=1
innodb_max_dirty_pages_pct_lwm=0.1
innodb_adaptive_flushing=1
innodb_adaptive_flushing_lwm=0.1
innodb_flush_neighbors=0
innodb_read_io_threads=8
innodb_write_io_threads=8
innodb_read_ahead_threshold=0
innodb_buffer_pool_dump_at_shutdown=0
innodb_buffer_pool_load_at_startup=0
join_buffer_size=32K
sort_buffer_size=32K
innodb_use_native_aio=1
innodb_stats_persistent=1
innodb_log_write_ahead_size=4096
performance_schema=OFF

# Logging
slow_query_log = ON
slow_query_log_file = /data/mariadb/data/slow.log
long_query_time = 2

# Character set
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci

# TidesDB
plugin_load_add = ha_tidesdb.so
plugin_maturity = gamma

# Row locking, optimistic by default
tidesdb_pessimistic_locking = OFF

tidesdb_block_cache_size = 16G
tidesdb_max_open_sstables = 512
tidesdb_unified_memtable_sync_mode = NONE
tidesdb_unified_memtable_write_buffer_size = 512M
tidesdb_default_write_buffer_size = 512M
tidesdb_default_sync_mode = NONE
tidesdb_default_compression = NONE
tidesdb_flush_threads = 8
tidesdb_compaction_threads = 8
tidesdb_log_level = NONE
# tidesdb_print_all_conflicts = ON

[client]
port = 3306
socket = /tmp/mariadb.sock
default-character-set = utf8mb4

[mysqldump]
quick
max_allowed_packet = 64M

[mariadb-backup]
# mariabackup settings (defaults are fine)

```
</details>



![](/mariadb-11-8-6-innodb-and-tidesql-v4-2-4-tpc-c/hammerdb_results_20260416_183948/chart_tpcc_nopm.png)
![](/mariadb-11-8-6-innodb-and-tidesql-v4-2-4-tpc-c/hammerdb_results_20260416_183948/chart_tpcc_latency.png)
![](/mariadb-11-8-6-innodb-and-tidesql-v4-2-4-tpc-c/hammerdb_results_20260416_183948/chart_tpcc_tpm.png)


![](/mariadb-11-8-6-innodb-and-tidesql-v4-2-4-tpc-c/hammerdb_results_20260416_184738/chart_tpcc_nopm.png)
![](/mariadb-11-8-6-innodb-and-tidesql-v4-2-4-tpc-c/hammerdb_results_20260416_184738/chart_tpcc_latency.png)
![](/mariadb-11-8-6-innodb-and-tidesql-v4-2-4-tpc-c/hammerdb_results_20260416_184738/chart_tpcc_tpm.png)

With 16GB buffers on both sides TidesDB reached 128,400 NOPM / 297,433 TPM, InnoDB 37,423 NOPM / 87,167 TPM, a 3.43x gap. Throughput scaled for both (InnoDB 2.23x, TidesDB 1.85x over their small-buffer runs), but the tail is where it gets ugly. NEWORD p99 is 3.023 ms on TidesDB, 153.846 ms on InnoDB. DELIVERY p99 is 7.84 ms vs 278.751 ms. PAYMENT p99 is 1.956 ms vs 61.443 ms. The standard deviations show why, InnoDB NEWORD sd 27,072 and DELIVERY sd 53,663 versus 529 and 3,897 on TidesDB. Those are flush and checkpoint stalls, most transactions are fast once the working set fits, but evictions block everything behind them. LSM writes are append-only to the memtable, no in-place updates, no doublewrite, no purge thread, and compaction runs off the critical path, so commit latency stays tight under load. Even with 256x the buffer pool of the small run, InnoDB cannot match the LSM on a write-heavy OLTP mix at this concurrency.


TidesDB wins both runs and the reason is primarily architectural, not tuning.

At 64MB InnoDB is memory-starved and gets beat 4.12x on NOPM. Give both engines 16GB and InnoDB scales 2.23x off a much lower base, TidesDB 1.85x, and TidesDB still wins 3.43x. The tail latency gap actually gets worse (NEWORD p99 3 ms vs 154 ms, DELIVERY p99 8 ms vs 279 ms). More buffer pool doesn't fix InnoDB's problem, it just delays it. The stalls do seem to be flush and checkpoint pauses blocking everything behind them, which you can see in the standard deviations (53k vs 3.8k on DELIVERY).

LSM writes append to a memtable, compaction runs off the critical path in background, no in-place page updates, no doublewrite, no purge thread catching up. That's why commit latency stays tight even when InnoDB's latency is spiking into the hundreds of ms.

You can find the raw data below:
| File | SHA256 Checksum |
|------|-----------------|
| [Small cache/buffer InnoDB](/mariadb-11-8-6-innodb-and-tidesql-v4-2-4-tpc-c/hammerdb_results_20260416_180716/hammerdb_results_20260416_180716.csv) | `ed82ad7acc8d1030f9a346cb00b72cbeb2c65ec07f08cb261dc86c15c7dfab8b` |
| [Small cache/buffer TidesDB](/mariadb-11-8-6-innodb-and-tidesql-v4-2-4-tpc-c/hammerdb_results_20260416_182002/hammerdb_results_20260416_182002.csv) | `f0ccbe509c3c8c0d568f10070070eaf9ba7129a4f36e2a77935cab75c0691504` |
| [Large cache/buffer InnoDB](/mariadb-11-8-6-innodb-and-tidesql-v4-2-4-tpc-c/hammerdb_results_20260416_183948/hammerdb_results_20260416_183948.csv) | `643db8337a977e946c777b5c7bae4017524a754a1e5a6fee1fbbbb401775aba8` |
| [Large cache/buffer TidesDB](/mariadb-11-8-6-innodb-and-tidesql-v4-2-4-tpc-c/hammerdb_results_20260416_184738/hammerdb_results_20260416_184738.csv) | `46323f2daf3b122ff775a57e3b6d67c329e819febe27640cf0ae6caddeaa4c89` |


That's all for now, thank you for reading!
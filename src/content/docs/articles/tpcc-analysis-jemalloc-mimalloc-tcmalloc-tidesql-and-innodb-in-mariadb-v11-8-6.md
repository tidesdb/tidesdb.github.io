---
title: "TPC-C Analysis with jemalloc, mimalloc, tcmalloc on TideSQL & InnoDB in MariaDB v11.8.6"
description: "TPC-C analysis with jemalloc, mimalloc, tcmalloc on TideSQL & InnoDB in MariaDB v11.8.6"
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-mary-vinitha-1373669599-37195530.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-mary-vinitha-1373669599-37195530.jpg
---

<div class="article-image">

![TPC-C Analysis with jemalloc, mimalloc, tcmalloc on TideSQL & InnoDB in MariaDB v11.8.6](/pexels-mary-vinitha-1373669599-37195530.jpg)

</div>

*by <a target="_blank"  href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on April 22nd, 2026*

Well I had a thought recently and it was to run analysis with different allocators running in TidesDB in which is the lower level component for the MariaDB plugin <a href="/reference/tidesql">TideSQL</a>.  In TidesDB you can configure jemalloc, mimalloc, or tcmalloc as the allocator when building.  I've run this analysis using <a href="https://hammerdb.com">HammerDB</a> TPROC-C and a custom <a href="/mariadb-11-8-6-innodb-and-tidesql-v4-2-4-tpc-c/hammerdb_runner.sh">script</a> to automate the processes.


When installing TideSQL you can specify the allocator to build with TidesDB, the installer does all the mapping for you

Because TidesDB and TideSQL don't come packaged in MariaDB and are external in this analysis I had to rebuild TidesDB with each allocator and restart my MariaDB server also to load the new allocator on MariaDB so both library and engine use the same allocator.

like in my command below:
```
-- First i installed MariaDB with TidesDB and TideSQL 
./install.sh --mariadb-prefix /data/mariadb --tidesdb-prefix /data/tidesdb --build-dir /data/tidesql-build --mariadb-version    
  mariadb-11.8.6 

-- Now I went ahead with glibc allocator

-- Then before each other besides glibc allocator analysis I rebuilt TidesDB, rebuilt plugin and restarted MariaDB server.

cd /data/tidesql-build/tidesdb-lib

cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/data/tidesdb \
  -DTIDESDB_BUILD_TESTS=OFF \
  -DBUILD_SHARED_LIBS=ON \
  -DTIDESDB_WITH_JEMALLOC=ON

-- Now I went ahead with mimalloc allocator

cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/data/tidesdb \
  -DTIDESDB_BUILD_TESTS=OFF \
  -DBUILD_SHARED_LIBS=ON \
  -DTIDESDB_WITH_MIMALLOC=ON

-- Now I went ahead with tcmalloc allocator

cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/data/tidesdb \
  -DTIDESDB_BUILD_TESTS=OFF \
  -DBUILD_SHARED_LIBS=ON \
  -DTIDESDB_WITH_JEMALLOC=OFF \
  -DTIDESDB_WITH_MIMALLOC=OFF \
  -DTIDESDB_WITH_TCMALLOC=ON


-- For rebuilding its simple as  
./install.sh \
  --mariadb-prefix /data/mariadb \
  --tidesdb-prefix /data/tidesdb \
  --build-dir /data/tidesql-build \
  --rebuild-plugin


-- Then when restarting server
LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2 /data/mariadb/bin/mariadbd-safe --defaults-file=/data/mariadb/my.cnf &
LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libmimalloc.so.2 /data/mariadb/bin/mariadbd-safe --defaults-file=/data/mariadb/my.cnf &
LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libtcmalloc.so.4 /data/mariadb/bin/mariadbd-safe --defaults-file=/data/mariadb/my.cnf &
```
*installed TidesDB v9.0.9, TideSQL v4.2.5*

The specs for the environment are
- AMD Ryzen Threadripper 2950X (16 cores 32 threads) @ 3.5GHz
- 128GB DDR4
- Ubuntu 22.04 x86_64
- XFS raw NVMe(SAMSUNG MZVLB512HAJQ-00000) w/discard, inode64, nodiratime, noatime, logbsize=256k, logbufs=8

<details>
<summary>my.cnf</summary>

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
innodb_log_file_size = 64M
innodb_log_buffer_size = 64M
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

[client]
port = 3306
socket = /tmp/mariadb.sock
default-character-set = utf8mb4

[mysqldump]
quick
max_allowed_packet = 64M

[mariadb-backup]
```
</details>



I ran the script twice per engine per allocator (glibc, jemalloc, mimalloc, and tcmalloc).

```
./hammerdb_runner.sh -b tpcc --warehouses 40 --tpcc-vu 8 --tpcc-build-vu 8 --rampup 1 --duration 2 --settle 5 -H ~/HammerDB-5.0 -e <innodb|tidesdb> -u hammerdb --pass hammerdb123 -S /tmp/mariadb.sock
```

![TPCC NOPM by Allocator](/tpc-c-analysis-jemalloc-mimalloc-tcmalloc-tidesql-mariadb-11-8-6/tpcc_allocators_nopm.png)

![TPCC Average Latency by Allocator](/tpc-c-analysis-jemalloc-mimalloc-tcmalloc-tidesql-mariadb-11-8-6/tpcc_allocators_latency.png)

From the analysis what we see is in MariaDB 11.8.6 the two engines respond very differently to allocator choice. InnoDB is effectively flat across all four allocators, the spread between the best (glibc, ~16.9k NOPM) and the worst (mimalloc, ~16.6k NOPM) is under 2.1%, and average new-order latency stays inside an 8.10–8.18 ms band regardless of which allocator the server is preloaded with. TidesDB on the other hand is strongly allocator-sensitive in that jemalloc (~75.1k NOPM) and tcmalloc (~74.5k NOPM) are the clear winners, glibc (~68.8k) is roughly 8–9% behind them, and mimalloc is the outlier going the other way at ~42.7k NOPM, a ~43% drop versus jemalloc, with average new-order latency rising from ~3.46 ms to ~4.91 ms and p95 from ~5.0 ms to ~7.4 ms. 

The article's takeaway is rather split, for InnoDB the allocator basically does not matter at this scale, while for TidesDB jemalloc and tcmalloc are interchangeable best picks, glibc is acceptable, and mimalloc should be avoided in this configuration. Even at its worst case TidesDB still does ~2.5x the throughput of InnoDB, and at its best ~4.5x, so the engine difference dominates the allocator difference in every cell of the matrix.

That's all for this article.

*Thank you for reading*

--


Learn more about jemalloc, mimalloc, and tcmalloc:
- [jemalloc](https://jemalloc.net/)
- [mimalloc](https://microsoft.github.io/mimalloc/)
- [tcmalloc](https://github.com/gperftools/gperftools)

Learn more about TidesDB:
- [TidesDB Design Doc](/getting-started/how-does-tidesdb-work)
- [TidesDB GitHub](https://github.com/tidesdb/tidesdb)

Learn more about TideSQL:
- [TideSQL Design Doc](/reference/tidesql)
- [TideSQL GitHub](https://github.com/tidesdb/tidesql)

You can find all the data from the analysis below:

| Engine | Allocator | Run | File | SHA-256 |
|---|---|---|---|---|
| InnoDB | glibc | 1 | [hammerdb_results_20260422_204822.csv](/tpc-c-analysis-jemalloc-mimalloc-tcmalloc-tidesql-mariadb-11-8-6/hammerdb_results_20260422_204822.csv) | `80b06c93ffe973c030f77429625167476fcfd49b463f1d1ff5e2e30e15791265` |
| InnoDB | glibc | 2 | [hammerdb_results_20260422_205525.csv](/tpc-c-analysis-jemalloc-mimalloc-tcmalloc-tidesql-mariadb-11-8-6/hammerdb_results_20260422_205525.csv) | `cb99223245f4487d067f51968d4a190af637530732a9a5d7821ff0182a46d6e9` |
| InnoDB | jemalloc | 1 | [hammerdb_results_20260422_212522.csv](/tpc-c-analysis-jemalloc-mimalloc-tcmalloc-tidesql-mariadb-11-8-6/hammerdb_results_20260422_212522.csv) | `ff79aaaa8c44f319f103b87e36bb79626aa9fa49eb1003f98e2574356ddd44bb` |
| InnoDB | jemalloc | 2 | [hammerdb_results_20260422_213140.csv](/tpc-c-analysis-jemalloc-mimalloc-tcmalloc-tidesql-mariadb-11-8-6/hammerdb_results_20260422_213140.csv) | `88ae6fb5f9c1bd35d88a492f505cab16ee26bf4b797baa7f82479893add8d359` |
| InnoDB | mimalloc | 1 | [hammerdb_results_20260422_215543.csv](/tpc-c-analysis-jemalloc-mimalloc-tcmalloc-tidesql-mariadb-11-8-6/hammerdb_results_20260422_215543.csv) | `f3282fd9d72cca0068f8973c2f3db138e2831920fee83cb9c3faee40501c37d4` |
| InnoDB | mimalloc | 2 | [hammerdb_results_20260422_220446.csv](/tpc-c-analysis-jemalloc-mimalloc-tcmalloc-tidesql-mariadb-11-8-6/hammerdb_results_20260422_220446.csv) | `285cde838f2421d8e1db43dfbd68701cfbf492433301e42e44904abab8f4617b` |
| InnoDB | tcmalloc | 1 | [hammerdb_results_20260422_223711.csv](/tpc-c-analysis-jemalloc-mimalloc-tcmalloc-tidesql-mariadb-11-8-6/hammerdb_results_20260422_223711.csv) | `48c8ad610e4c9bb32b9ab0c33af3349d4a794c9d4cbf9b0553d7c478da563994` |
| InnoDB | tcmalloc | 2 | [hammerdb_results_20260422_224756.csv](/tpc-c-analysis-jemalloc-mimalloc-tcmalloc-tidesql-mariadb-11-8-6/hammerdb_results_20260422_224756.csv) | `e9caa67036bdeacc64fe709834aa17d1758b85ac36d7c0dfbc8a5e7edc4ccee7` |
| TidesDB | glibc | 1 | [hammerdb_results_20260422_210138.csv](/tpc-c-analysis-jemalloc-mimalloc-tcmalloc-tidesql-mariadb-11-8-6/hammerdb_results_20260422_210138.csv) | `cbfbc3cb6665fbafd075f5a159a790998c1c8d709e3b30dc7b297a7e6c78a1cf` |
| TidesDB | glibc | 2 | [hammerdb_results_20260422_210755.csv](/tpc-c-analysis-jemalloc-mimalloc-tcmalloc-tidesql-mariadb-11-8-6/hammerdb_results_20260422_210755.csv) | `8a0abffb770f37451fcce693f502c6dd3e2c0702def8b6eff883c6dd293bd450` |
| TidesDB | jemalloc | 1 | [hammerdb_results_20260422_213748.csv](/tpc-c-analysis-jemalloc-mimalloc-tcmalloc-tidesql-mariadb-11-8-6/hammerdb_results_20260422_213748.csv) | `39d496b0128c1523e857ae1fe613cdd6ac62b5e1749b2bd15641f9c83a1a8327` |
| TidesDB | jemalloc | 2 | [hammerdb_results_20260422_214352.csv](/tpc-c-analysis-jemalloc-mimalloc-tcmalloc-tidesql-mariadb-11-8-6/hammerdb_results_20260422_214352.csv) | `7e308e4c272507d4760b8a05cb667313bd67dff74d4932370087d866a264c9b0` |
| TidesDB | mimalloc | 1 | [hammerdb_results_20260422_221243.csv](/tpc-c-analysis-jemalloc-mimalloc-tcmalloc-tidesql-mariadb-11-8-6/hammerdb_results_20260422_221243.csv) | `8e18f4c4d25f1be5d48f1d61753585cc5d997894afd2e77512b95f377229660b` |
| TidesDB | mimalloc | 2 | [hammerdb_results_20260422_222049.csv](/tpc-c-analysis-jemalloc-mimalloc-tcmalloc-tidesql-mariadb-11-8-6/hammerdb_results_20260422_222049.csv) | `ead9b35bc0f09e70cb502654f2d821d9a282533c7bdeb2b17b22c3d22cb6ba44` |
| TidesDB | tcmalloc | 1 | [hammerdb_results_20260422_225637.csv](/tpc-c-analysis-jemalloc-mimalloc-tcmalloc-tidesql-mariadb-11-8-6/hammerdb_results_20260422_225637.csv) | `82ecdd2c3ed1aa252879284d0e3f5c1a7d4fd625741ba38008758223e7358dbc` |
| TidesDB | tcmalloc | 2 | [hammerdb_results_20260422_230301.csv](/tpc-c-analysis-jemalloc-mimalloc-tcmalloc-tidesql-mariadb-11-8-6/hammerdb_results_20260422_230301.csv) | `49c71d8042e88265367b154db6e9fcb744de18eb2eb3766e1e30202521f5f0f6` |
 
Bundle of all data: [hammerdb_mariadb_allocator_analysis.zip](/tpc-c-analysis-jemalloc-mimalloc-tcmalloc-tidesql-mariadb-11-8-6/hammerdb_mariadb_allocator_analysis.zip) (bfd2d99e7a9c873e37bab370d5f1c26671d349fd0e8fa3feb8758d2668641016)
 

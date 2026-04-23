---
title: "PGO Build TPC-C Analysis MariaDB v11.8.6 TideSQL"
description: "PGO build TPC-C analysis for MariaDB v11.8.6 with TideSQL."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-canan-i-ldeniz-2158600658-37211413.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-canan-i-ldeniz-2158600658-37211413.jpg
---

<div class="article-image">

![PGO Build TPC-C Analysis MariaDB v11.8.6 TideSQL](/pexels-canan-i-ldeniz-2158600658-37211413.jpg)

</div>

*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on April 23rd, 2026*

Most of you probably don't know you can build TideSQL with PGO. Profile-Guided Optimization is a three-phase build. The compiler emits an instrumented binary, you run a representative workload through it to collect profile data, then the compiler does a second build that uses those profiles to guide inlining, branch layout, block ordering, register allocation, and code placement. The binary ends up tuned for the paths your engine actually exercises.

<a href="/reference/tidesql">TideSQL</a> ships this behind `./install.sh --pgo`. Phase one builds <a href="https://mariadb.org">MariaDB</a> with `-fprofile-generate`. Phase two runs `mtr --suite=tidesdb`, the TidesDB test suite, as the training workload so the profile captures the TidesDB storage engine paths. Phase three rebuilds with `-fprofile-use` plus `-fprofile-correction`. The whole thing is wired for TidesDB, so InnoDB rides along and only picks up what falls out of the shared MariaDB front-end. It still picks up a little, just not much.

In the last analysis I ran four allocators, glibc, jemalloc, mimalloc, and tcmalloc. This time only glibc and jemalloc.

Previous article on the same environment, [TPC-C Analysis with glibc, jemalloc, mimalloc, tcmalloc on TideSQL & InnoDB in MariaDB v11.8.6](https://tidesdb.com/articles/tpcc-analysis-jemalloc-mimalloc-tcmalloc-tidesql-and-innodb-in-mariadb-v11-8-6/).

I utilize <a href="https://hammerdb.com">HammerDB</a> for all of my TPC-C analyses (TPROC-C), similar to last article using this script [hammerdb_runner.sh](https://tidesdb.com/mariadb-11-8-6-innodb-and-tidesql-v4-2-4-tpc-c/hammerdb_runner.sh).
```
./hammerdb_runner.sh -b tpcc --warehouses 40 --tpcc-vu 8 --tpcc-build-vu 8 --rampup 1 --duration 2 --settle 5 -H ~/HammerDB-5.0 -e tidesdb|innodb -u hammerdb --pass hammerdb123 -S /tmp/mariadb.sock
```

**Environment**
- AMD Ryzen Threadripper 2950X (16 cores 32 threads) @ 3.5GHz
- 128GB DDR4
- Ubuntu 22.04 x86_64
- GCC (glibc)
- XFS raw NVMe (SAMSUNG MZVLB512HAJQ-00000) with discard, inode64, nodiratime, noatime, logbsize=256k, logbufs=8
- TidesDB v9.0.9, TideSQL v4.2.6, MariaDB v11.8.6

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

**Throughput**

InnoDB moves a little, which is what you'd expect from an engine the profile doesn't target. TPM goes from 39,324 to 39,536 on glibc (+0.54%), and from 39,174 to 39,938 on jemalloc (+1.95%). NOPM tracks +1.22% and +2.04%. A small, free lift from the shared MariaDB front-end getting profiled.


![InnoDB TPM non-PGO vs PGO](/pgo-build-analysis-mariadb-v11-8-6-tidesql/plot_innodb_tpm.svg)


TidesDB moves more. On glibc, TPM climbs from 160,223 to 173,144 (+8.06%) and NOPM from 68,805 to 74,590 (+8.41%). On jemalloc the gap widens, TPM from 174,510 to 202,961 (+16.30%) with NOPM up +4.88%. PGO plus jemalloc clears 200k TPM.


![TidesDB TPM non-PGO vs PGO](/pgo-build-analysis-mariadb-v11-8-6-tidesql/plot_tidesdb_tpm.svg)


NOPM side by side.


![NOPM non-PGO vs PGO](/pgo-build-analysis-mariadb-v11-8-6-tidesql/plot_nopm_combined.svg)


![PGO uplift TPM](/pgo-build-analysis-mariadb-v11-8-6-tidesql/plot_uplift_tpm.svg)


**Latency**

New-order p95. InnoDB picks up a real win here, 12.94 -> 12.13 ms on glibc (-6.25%) and 13.03 -> 12.22 ms on jemalloc (-6.22%). The shared MariaDB front-end paths are hot enough in the profile that the new-order path benefits even with an unrelated storage engine underneath. Same reason throughput ticked up a bit, the profile reaches InnoDB through MariaDB, not through the engine.

TidesDB does better, 5.33 -> 4.90 ms on glibc (-8.05%) and 5.00 -> 4.40 ms on jemalloc (-12.00%).


![New-Order p95 latency](/pgo-build-analysis-mariadb-v11-8-6-tidesql/plot_neword_p95.svg)


![PGO uplift new-order p95](/pgo-build-analysis-mariadb-v11-8-6-tidesql/plot_uplift_neword.svg)


Delivery is the heaviest write in TPC-C. InnoDB p95 doesn't move, it edges up slightly (+0.73%, +1.04%), which is noise more than regression but also not a win. The training workload doesn't exercise InnoDB's write path, so there's nothing for PGO to tune there.

TidesDB goes the other way, 17.26 -> 15.78 ms on glibc (-8.61%) and 14.44 -> 12.47 ms on jemalloc (-13.62%). This is the LSM write path, which is exactly where the training workload lives.


![Delivery p95 latency](/pgo-build-analysis-mariadb-v11-8-6-tidesql/plot_delivery_p95.svg)


![PGO uplift delivery p95](/pgo-build-analysis-mariadb-v11-8-6-tidesql/plot_uplift_delivery.svg)


**Takeaway**

PGO buys TidesDB 8% to 16% more TPM and takes 8% to 14% off tail latency depending on allocator. InnoDB isn't the target of the profile, but it still benefits a bit, 1% to 2% on throughput and a genuine 6% drop on new-order p95. Delivery sits flat for InnoDB because the training workload doesn't exercise that path. PGO follows the paths you profiled.

PGO plus jemalloc stacks. TidesDB under that build hits 202,961 TPM against an InnoDB baseline of 39,174 on the same box, roughly 5.2x throughput with roughly 6.4x better delivery p95.

If you're building TideSQL from source and running TidesDB in production, `--pgo` is worth the extra step.

*Thank you for reading.*

--

**Raw data**

| Config | Run | File | SHA-256 |
|---|---|---|---|
| InnoDB non-PGO glibc     | 1 | [hammerdb_results_20260422_204822.csv](/pgo-build-analysis-mariadb-v11-8-6-tidesql/hammerdb_results_20260422_204822.csv) | `80b06c93ffe973c030f77429625167476fcfd49b463f1d1ff5e2e30e15791265` |
| InnoDB non-PGO glibc     | 2 | [hammerdb_results_20260422_205525.csv](/pgo-build-analysis-mariadb-v11-8-6-tidesql/hammerdb_results_20260422_205525.csv) | `cb99223245f4487d067f51968d4a190af637530732a9a5d7821ff0182a46d6e9` |
| InnoDB non-PGO jemalloc  | 1 | [hammerdb_results_20260422_212522.csv](/pgo-build-analysis-mariadb-v11-8-6-tidesql/hammerdb_results_20260422_212522.csv) | `ff79aaaa8c44f319f103b87e36bb79626aa9fa49eb1003f98e2574356ddd44bb` |
| InnoDB non-PGO jemalloc  | 2 | [hammerdb_results_20260422_213140.csv](/pgo-build-analysis-mariadb-v11-8-6-tidesql/hammerdb_results_20260422_213140.csv) | `88ae6fb5f9c1bd35d88a492f505cab16ee26bf4b797baa7f82479893add8d359` |
| TidesDB non-PGO glibc    | 1 | [hammerdb_results_20260422_210138.csv](/pgo-build-analysis-mariadb-v11-8-6-tidesql/hammerdb_results_20260422_210138.csv) | `cbfbc3cb6665fbafd075f5a159a790998c1c8d709e3b30dc7b297a7e6c78a1cf` |
| TidesDB non-PGO glibc    | 2 | [hammerdb_results_20260422_210755.csv](/pgo-build-analysis-mariadb-v11-8-6-tidesql/hammerdb_results_20260422_210755.csv) | `8a0abffb770f37451fcce693f502c6dd3e2c0702def8b6eff883c6dd293bd450` |
| TidesDB non-PGO jemalloc | 1 | [hammerdb_results_20260422_213748.csv](/pgo-build-analysis-mariadb-v11-8-6-tidesql/hammerdb_results_20260422_213748.csv) | `39d496b0128c1523e857ae1fe613cdd6ac62b5e1749b2bd15641f9c83a1a8327` |
| TidesDB non-PGO jemalloc | 2 | [hammerdb_results_20260422_214352.csv](/pgo-build-analysis-mariadb-v11-8-6-tidesql/hammerdb_results_20260422_214352.csv) | `7e308e4c272507d4760b8a05cb667313bd67dff74d4932370087d866a264c9b0` |
| InnoDB PGO glibc         | 1 | [hammerdb_results_20260423_173043.csv](/pgo-build-analysis-mariadb-v11-8-6-tidesql/hammerdb_results_20260423_173043.csv) | `0dd3f1d2b39cb639dfabedd02565e053fce435b41ec37fe73e68f2b678ad3fba` |
| InnoDB PGO glibc         | 2 | [hammerdb_results_20260423_173714.csv](/pgo-build-analysis-mariadb-v11-8-6-tidesql/hammerdb_results_20260423_173714.csv) | `f0953e900ef71f23bff1231d0436b325b503a8fe76efa3f831a19a03e0b3e07a` |
| InnoDB PGO jemalloc      | 1 | [hammerdb_results_20260423_180420.csv](/pgo-build-analysis-mariadb-v11-8-6-tidesql/hammerdb_results_20260423_180420.csv) | `cbd34c74772add4abbcc8d6364867d3fbe214a69a7375f0d9706a2a0f3aa208a` |
| InnoDB PGO jemalloc      | 2 | [hammerdb_results_20260423_181013.csv](/pgo-build-analysis-mariadb-v11-8-6-tidesql/hammerdb_results_20260423_181013.csv) | `22dfc3ec7a15bfc1ecf24bbb43a62a6054f40229842fbb0c9a52177270942649` |
| TidesDB PGO glibc        | 1 | [hammerdb_results_20260423_174319.csv](/pgo-build-analysis-mariadb-v11-8-6-tidesql/hammerdb_results_20260423_174319.csv) | `2a33e00e6261f0462a2707f810e2c6e74378f340666f8f6761172c849f10fc7e` |
| TidesDB PGO glibc        | 2 | [hammerdb_results_20260423_174954.csv](/pgo-build-analysis-mariadb-v11-8-6-tidesql/hammerdb_results_20260423_174954.csv) | `19503610230a2aa7d3277b8b43489f2fb928e2fd6f30b9d23e3a70d2564c634a` |
| TidesDB PGO jemalloc     | 1 | [hammerdb_results_20260423_181701.csv](/pgo-build-analysis-mariadb-v11-8-6-tidesql/hammerdb_results_20260423_181701.csv) | `f1f40449707bb140bd57d2d6a06f225ed29edec6bf1893f0c7dfec5c4205d1d5` |
| TidesDB PGO jemalloc     | 2 | [hammerdb_results_20260423_182443.csv](/pgo-build-analysis-mariadb-v11-8-6-tidesql/hammerdb_results_20260423_182443.csv) | `af184c1b974cd82226b8c39b2831e9e7caf1a716e2e0cc50f0519497ecaf4b1b` |

You can find all data in one zip here: <a href="/pgo-build-analysis-mariadb-v11-8-6-tidesql/hammerdb_results_all.zip">hammerdb_results_all.zip</a> (3be7e9c3e9bc2cbdbcb22e60b9c177f15c50145915b03e875bb3d1b6e376797e)
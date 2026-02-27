---
title: "Benchmark Analysis on TidesDB (TideSQL v3.3.5) & InnoDB in MariaDB v12.2.2 & InnoDB in MySQL v9.5.0"
description: "Benchmark analysis comparing TidesDB (TideSQL v3.3.5) and InnoDB in MariaDB v12.2.2 and InnoDB in MySQL v9.5.0"
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-oidonnyboy-5717911.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-oidonnyboy-5717911.jpg
---

<div class="article-image">

![Benchmark Analysis on TidesDB (TideSQL v3.3.5) & InnoDB in MariaDB v12.2.2 & InnoDB in MySQL v9.5.0](/pexels-oidonnyboy-5717911.jpg)

</div>

*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on February 27th, 2026*

I'm back with another article, I've been putting in consistent work into the <a href="https://mariadb.org">MariaDB</a> plugin engine.  Believe it or not when you work on something like this you will encounter a lot of unexpected edge cases that in the end you have to patch or handle at the storage engine level, so working on the plugin, the underlying library still got lots of love and attention, in which translates to better performance and stability for both.

If you want to learn more about the TidesDB MariaDB engine check out <a href="/reference/tidesql">TideSQL</a>.

Anyway, enough with that, I recently ran the <a href="https://github.com/tidesdb/sqlbench">sqlbench</a> shell program with below params on the Threadripper dedicated box we have setup which I will describe further below.

```
nohup env \
  BUILD_DIR=/data/mariadb \
  MYSQL_BIN=/data/mariadb/bin/mariadb \
  MYSQLD=/data/mariadb/bin/mariadbd \
  PLUGIN_DIR=/data/mariadb/lib/plugin \
  DATA_DIR=/data/db-bench \
  TABLE_SIZES="1000000" \
  TABLES=8 \
  THREAD_COUNTS="1 8 16 32" \
  TIME=300 \
  WARMUP=120 \
  ENGINES="TidesDB InnoDB" \
  WORKLOADS="oltp_read_write oltp_point_select oltp_insert oltp_write_only" \
  TIDESDB_SYNC_MODE=0 \
  ITERATIONS=1 \
  TIDESDB_COMPRESSION=LZ4 \
  INNODB_COMPRESSION=LZ4 \
  TIDESDB_BLOCK_CACHE=2147483648 \
  INNODB_BUFFER_POOL=2G \
  INNODB_FLUSH=0 \
  ./sqlbench.sh > sqlbench.log 2>&1 &
tail -f sqlbench.log
```
*this is my exactly command*

So as you can above we have decently sized tables, 1 iteration, 8 tables, decently sized cache/buffer, running 4 different workloads and 2 different engines (TidesDB and InnoDB) with 4 different thread counts (1, 8, 16, 32).  Simple stuff, you can run yourself.   I did not want to do more than 2GB for the cache/buffer as I wanted to see how the engines perform with limited resources.

I do hope soon to have <a href="https://hammerdb.com">HammerDB</a> pushing the limits of TidesDB in MariaDB to see how it performs not using sysbench but under tpcc, tpch and other real world workloads.  Shout out to Steve Shaw!


Environment:
- AMD Ryzen Threadripper 2950X (16 cores 32 threads) @ 3.5GHz
- 128GB DDR4
- Ubuntu 22.04 x86_64
- GCC (glibc)
- XFS raw NVMe(SAMSUNG MZVLB512HAJQ-00000) w/discard, inode64, nodiratime, noatime, logbsize=256k, logbufs=8
- Underlying TidesDB version used was v8.6.1

To also note, I ran the same benchmark on <a href="https://dev.mysql.com/doc/relnotes/mysql/9.5/en/">MySQL v9.5.0</a>, so we will look at those numbers as well, this would be more comparing the two InnoDB storage engines within MySQL and MariaDB as opposed to the databases themselves.  TidesDB isn't fully supported in MySQL.


```
nohup env \
  MYSQL_BIN=/data/mysql-9.5.0/bin/mysql \
  SOCKET=/data/mysql.sock \
  SIZE_DATA_DIR=/data/data \
  TABLE_SIZES="1000000" \
  TABLES=8 \
  THREAD_COUNTS="1 8 16 32" \
  TIME=300 \
  WARMUP=120 \
  ENGINES="InnoDB" \
  WORKLOADS="oltp_read_write oltp_point_select oltp_insert oltp_write_only" \
  ITERATIONS=1 \
  INNODB_BUFFER_POOL=2G \
  INNODB_FLUSH=0 \
  INNODB_COMPRESSION=LZ4 \
  ./sqlbench.sh > sqlbench.log 2>&1 &
tail -f sqlbench.log
```
*MySQL sqlbench command, you can see same params but with MySQL instead of MariaDB*

Configurations used:


| Setting | MariaDB | MySQL | Notes |
|---|---|---|---|
| Config source | `--no-defaults` + CLI flags | `/data/my.cnf` | MariaDB uses no config file |
| skip-grant-tables | Set | Set | No auth overhead |
| skip-networking | Set | Set | Unix socket only |
| performance_schema | OFF (default) | OFF (explicit) | MySQL defaults to ON; forced OFF |
| log_bin | OFF (not set) | OFF (`disable-log-bin`) | MySQL defaults to ON; forced OFF |
| innodb_buffer_pool_size | 2G | 2G | Matched via env var |
| innodb_flush_log_at_trx_commit | 0 | 0 | Benchmark mode: flush once/sec |
| innodb_doublewrite | ON (default) | ON (default) | Same default on both |
| innodb_flush_method | default | default (O_DIRECT) | MariaDB 12.x default is also O_DIRECT on Linux |
| innodb_file_per_table | ON (default) | ON (default) | Same default on both |
| innodb_io_capacity | 200 (default) | 200 (explicit) | MySQL 9.5 changed default to 10000; forced to 200 |
| innodb_io_capacity_max | 2000 (default) | 2000 (explicit) | MySQL 9.5 changed default to 20000; forced to 2000 |
| innodb_read_io_threads | 4 (default) | 4 (explicit) | MySQL 9.5 changed default to 16; forced to 4 |
| innodb_write_io_threads | 4 (default) | 4 (explicit) | Same default, set explicitly for safety |
| Redo log size | 64M (`innodb_log_file_size`) | 64M (`innodb_redo_log_capacity`) | Different variable name, same effective size |
| Server-level config | `innodb_compression_algorithm=lz4` | N/A (per-table only) | MariaDB sets algorithm globally |
| CREATE TABLE syntax | `PAGE_COMPRESSED=1` | `COMPRESSION='lz4'` | sqlbench.sh auto-detects and uses correct syntax |
| Supported algorithms | LZ4, ZSTD, Snappy, Zlib | LZ4, Zlib | MySQL only supports lz4/zlib; others fall back to lz4 |
| Mechanism | In-buffer compression | Transparent page compression + hole punching | MySQL requires filesystem support (XFS, ext4, NTFS) |

Benchmark Parameters:

| Setting | Value | Notes |
|---|---|---|
| TABLE_SIZES | 1000000 | 1M rows per table |
| TABLES | 8 | 8 sysbench tables |
| THREAD_COUNTS | 1 8 16 32 | Concurrency sweep |
| TIME | 300 | 5 minutes per test |
| WARMUP | 120 | 2 minutes warmup |
| ITERATIONS | 1 | Single run per config |
| WORKLOADS | oltp_read_write oltp_point_select oltp_insert oltp_write_only | 4 workloads |

These MySQL defaults were overridden to match MariaDB for fair comparison:

| Setting | MySQL 9.5 Default | MariaDB Default | Benchmark Value |
|---|---|---|---|
| performance_schema | ON | OFF | OFF |
| log_bin | ON | OFF | OFF |
| innodb_io_capacity | 10000 | 200 | 200 |
| innodb_io_capacity_max | 20000 | 2000 | 2000 |
| innodb_read_io_threads | 16 | 4 | 4 |
| innodb_redo_log_capacity | 100M | N/A (64M log file) | 64M |

So the results are fairly interesting, to start we have TidesDB linearly scaling with CPU cores and threads, which is rather expected at this point.

Now what's also really cool to see is TidesDB performs really well for point look ups, selects in general, and absurdly fast on writes.  What makes TidesDB in some cases surpass InnoDB in read-write workloads is because of it's ability to linearly scale, there is little contention, the system has little blocking, the only blocking really is when the system has to start applying the brakes a bit to prevent OOM.  One thing I noticed in the benchmarks is TidesDB in some cases has larger storage size though based on observation over time it is transient and gets cleaned up as compactions occur and ref counts drop leading to free'd memory.  InnoDB depending on the workload, the environment, can show faster for RW and lower thread counts but again this is highly dependent on the environment, in this case the hardware isn't that modern, if TidesDB was run on a modern AMD or Intel, the numbers would be far more superior due to TidesDB internal optimizations and design.  The system tries to optimize for older hardware but we can only do so much until you're bounded.

Overal from my take is for super fast ingestion, TidesDB is king, over all, really TidesDB is keeping up with InnoDB which show's how well designed InnoDB is, really cool.

Now with the MySQL run, I made sure to properly align configurations, LZ4 compression enabled on both, same IO capacity, same thread counts, same redo log sizes, performance_schema off, binary logging off, the whole nine yards.  You can see the full config comparison tables above.  This matters a lot because MySQL 9.5 changed a bunch of defaults (io_capacity went from 200 to 10000, read_io_threads from 4 to 16, etc.) and if you don't normalize those you'll get misleading numbers.

Let's get into the actual numbers and charts.

**TPS Comparison**

![TPS Comparison](/tidesql-v3-3-5-innodb-in-mariadb-v12-2-2-mysql-v9-5-0/tps_comparison.png)

Starting with the average TPS chart above, for point selects all three engines are remarkably close.  At 1 thread TidesDB is at ~21K, MariaDB InnoDB at ~22.6K, and MySQL InnoDB at ~19.5K, all within 15% of each other.  At 32 threads, TidesDB leads at ~467K, MariaDB InnoDB at ~457K, and MySQL InnoDB at ~416K.  MariaDB InnoDB holds a consistent ~10% edge over MySQL across all thread counts here.  All three scale well which makes sense, point selects are read-only, no locking overhead.

For inserts, this is where TidesDB absolutely dominates.  TidesDB at 32 threads is pushing ~199K TPS with near-linear scaling from 16K at 1 thread, just absurd throughput.  For the two InnoDBs, MariaDB InnoDB is faster at 1 through 16 threads, starting at ~15.4K vs MySQL's ~12.9K and peaking at ~43K at 8 threads vs MySQL's ~30K.  But MariaDB InnoDB shows a write regression at high concurrency, dropping to ~27.5K at 32 threads, while MySQL InnoDB keeps climbing to ~38K.  So MariaDB wins the majority of the insert range but MySQL holds up better at the extreme end.  Worth noting this is a single iteration so the 32-thread crossover point warrants further testing.

Write-only workloads show MariaDB InnoDB ahead at low concurrency (~2.6K at 1 thread vs MySQL's ~1.5K) but MySQL catches up and slightly edges ahead at 16 threads (~4.9K vs ~2.5K).  TidesDB again dominates here, going from ~3.1K at 1 thread to ~19.8K at 32 threads.  MariaDB InnoDB has an interesting pattern, it dips at 16 threads then recovers to ~4.4K at 32 threads, suggesting some transient contention around that concurrency level.

For the mixed read-write workload, MariaDB InnoDB is the clear winner at low to mid concurrency, ~668 TPS at 1 thread and peaking at ~2,955 TPS at 8 threads, well ahead of both MySQL InnoDB (~548 at 1T, ~1,830 at 8T) and TidesDB (~369 at 1T, ~1,490 at 8T).  But at 32 threads TidesDB overtakes both at ~3,090 TPS, and MariaDB InnoDB regresses to ~2,098 while MySQL InnoDB climbs to ~2,510.  Again, the high-concurrency crossover is interesting but MariaDB InnoDB wins 3 out of 4 thread counts for mixed workloads.

### P95 Latency

![P95 Latency Comparison](/tidesql-v3-3-5-innodb-in-mariadb-v12-2-2-mysql-v9-5-0/p95_latency_comparison.png)

On the latency side, point selects are a wash, all three engines sit at 0.05-0.08ms P95 across all thread counts.  For inserts at 32 threads, all three are sub-millisecond (TidesDB 0.49ms, MariaDB InnoDB 0.32ms, MySQL InnoDB 0.31ms), really tight.

The spread shows up in write-only and read-write.  For write-only, MariaDB InnoDB's P95 jumps to 42.6ms at 16 threads and 45.8ms at 32 threads, while MySQL InnoDB stays at 3.3ms at 16 threads (spiking to 9.9ms at 32 threads) and TidesDB holds at 4.9-5.3ms.  MariaDB InnoDB's high tail latency on writes correlates with its throughput dip at 16 threads.  For read-write at 32 threads, MariaDB InnoDB is at 69.3ms P95 vs TidesDB at 14.5ms and MySQL InnoDB at 10.1ms.

### Scaling Efficiency

![Scaling Efficiency](/tidesql-v3-3-5-innodb-in-mariadb-v12-2-2-mysql-v9-5-0/scaling_efficiency.png)

The scaling efficiency chart above normalizes performance to single-thread baseline.  TidesDB achieves close to ideal linear scaling for point selects (~22x speedup at 32 threads vs ideal 32x) and very strong scaling for inserts (~12x) and read-write (~8x).  MariaDB InnoDB scales well for reads (~20x for point selects) but shows regression for inserts beyond 8 threads, peaking at ~2.8x and then dropping back to ~1.8x at 32 threads.  Write-only is erratic for MariaDB InnoDB, dipping below 1x at 16 threads then recovering to ~1.7x at 32 threads.  MySQL InnoDB shows ~21x scaling for point selects and a steady ~3x for inserts and write-only, no regression but no dramatic gains either.  Both InnoDBs are far from linear on writes but the patterns differ, MariaDB regresses then recovers while MySQL climbs gradually.

### TPS Over Time

![TPS Over Time at 32 Threads](/tidesql-v3-3-5-innodb-in-mariadb-v12-2-2-mysql-v9-5-0/tps_over_time_32t.png)

Looking at the time-series TPS data at 32 threads above, we can see the stability characteristics of each engine.  TidesDB maintains relatively consistent throughput throughout the 300 second runs with some periodic dips that correspond to back pressure being applied.  For read-write, all three engines are actually in the same band now (2K-3K TPS) with TidesDB slightly on top and more variance, while both InnoDBs show upward trends as their buffer pools warm.

The insert chart is dramatic, TidesDB is cruising at 150K-230K TPS while both InnoDBs oscillate between 27K-50K.  You can see the sawtooth pattern in both InnoDBs where they spike then drop as the flush cycle kicks in, but they recover and stay in the same general band.  For point selects, TidesDB and MariaDB InnoDB are overlapping at ~460K while MySQL InnoDB is a steady flat line at ~416K.

Write-only at 32 threads shows something interesting for MySQL InnoDB, it starts strong around 5.4K TPS but drops sharply in the last 50 seconds to ~2.3K-3K TPS.  This kind of late-run degradation suggests the redo log or buffer pool is hitting a pressure point.  MariaDB InnoDB and TidesDB both maintain more consistent throughput throughout.

### MySQL vs MariaDB InnoDB

Looking at the InnoDB comparison overall, MariaDB InnoDB wins the majority of test points, it's faster at low to mid concurrency across all workloads and consistently ahead on point selects.  Where it gets interesting is at 32 threads, MariaDB's InnoDB shows write regression on inserts and read-write while MySQL's InnoDB avoids that regression.  Whether this is a fundamental architectural difference or something specific to this config/hardware is hard to say from a single iteration.  The two forks use different compression mechanisms (in-buffer vs transparent page compression with hole punching), different redo log implementations, and likely diverge in their mutex/latch strategies.  I'd want to see multiple iterations and different hardware before drawing strong conclusions on the high-concurrency write behavior.

### Wrap Up

TidesDB is the clear winner for write-heavy and ingestion workloads, it's in a completely different league for inserts at 5-7x the throughput of either InnoDB.  For mixed and read-heavy workloads, TidesDB keeps up at low concurrency and overtakes both InnoDBs at higher thread counts.  Both InnoDB forks are solid engines, MariaDB's is generally faster across the board with MySQL's showing resilience specifically at very high concurrency writes.  Really cool to see all three engines performing well and I'm looking forward to running more iterations and testing on newer hardware.

*Thank you for reading!*

--- 

You can find the raw sqlbench data below:

| File | SHA-256 |
|---|---|
| <a href="/tidesql-v3-3-5-innodb-in-mariadb-v12-2-2-mysql-v9-5-0/run1/summary_20260227_022358.csv">run1/summary_20260227_022358.csv</a> | `368f77cd26bcbe6935391074500e2db08da7a6b58a682a13b9f5855ef4eaabe8` |
| <a href="/tidesql-v3-3-5-innodb-in-mariadb-v12-2-2-mysql-v9-5-0/run1/detail_20260227_022358.csv">run1/detail_20260227_022358.csv</a> | `4e078cec8852b218894586ca7e517510caeacffc6791c53f40650e860da5091e` |
| <a href="/tidesql-v3-3-5-innodb-in-mariadb-v12-2-2-mysql-v9-5-0/run2/summary_20260227_201257.csv">run2/summary_20260227_201257.csv</a> | `13b37da3236d3f499eb5468ead16e3be9e7ccfb1ef9488a5543cae91c38d3768` |
| <a href="/tidesql-v3-3-5-innodb-in-mariadb-v12-2-2-mysql-v9-5-0/run2/detail_20260227_201257.csv">run2/detail_20260227_201257.csv</a> | `0429f4af4daa2e824a1fb85daa0fa19c338125d764d946d45693ab21e5fa76f7` |
---
title: "iibench Analysis on TideSQL v4.5.1 MyRocks, InnoDB in MariaDB v11.8.6"
description: "iibench(index-insertion) benchmark on TideSQL v4.5.1 MyRocks, InnoDB in MariaDB v11.8.6"
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-sasha-vukovic-449306304-34169586.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-sasha-vukovic-449306304-34169586.jpg
---

<div class="article-image">

![Benchmark Analysis on TidesDB v9.2.1 and RocksDB v11.1.1](/pexels-sasha-vukovic-449306304-34169586.jpg)

</div>

*by <a target="_blank" href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on May 18th, 2026*

Recently I wrote a port of Tim Callaghan's iibench in which was rather dated and in Java, you can find it <a target="_blank" href="https://github.com/tmcallaghan/iibench-mysql">here</a>, also I was unsure of the license thus I rewrote the spefication in GO, a language in which I love and is perfect for a benchmarking tool and it's licensed under <a target="_blank" href="https://opensource.org/license/bsd-2-clause">BSD 2</a>.

The <a target="_blank" href="https://github.com/guycipher/iibench">tool</a> is very simple, it takes tasks in which you queue and run them.  For this work I setup the task queue below in TOML format.
```toml

[defaults]
driver  = "mariadb"
dialect = "mariadb"
dsn     = "iibench:iibench@unix(/tmp/mariadb.sock)/iibench"

num_secondary_indexes = 3
num_char_fields       = 4
length_char_fields    = 100
percent_compressible  = 30
rows_per_insert       = 1000
report_every          = "10s"
query_limit           = 10
writer_threads        = 16


[[task]]
name           = "innodb_load_30M"
table          = "purchases_innodb"
create_table   = true
table_options  = "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 ROW_FORMAT=DYNAMIC"
duration       = "20m"
max_rows_total = 30000000
log_file       = "innodb_load.tsv"

[[task]]
name                = "innodb_mixed_15m"
table               = "purchases_innodb"
create_table        = false
writer_threads      = 8
max_rows_per_second = 30000
query_threads       = 8
queries_per_second  = 300
query_start_at_rows = 1000000
duration            = "15m"
log_file            = "innodb_mixed.tsv"


[[task]]
name           = "tidesdb_load_30M"
table          = "purchases_tides"
create_table   = true
table_options  = "ENGINE=TidesDB DEFAULT CHARSET=utf8mb4"
duration       = "20m"
max_rows_total = 30000000
log_file       = "tidesdb_load.tsv"

[[task]]
name                = "tidesdb_mixed_15m"
table               = "purchases_tides"
create_table        = false
writer_threads      = 8
max_rows_per_second = 30000
query_threads       = 8
queries_per_second  = 300
query_start_at_rows = 1000000
duration            = "15m"
log_file            = "tidesdb_mixed.tsv"


[[task]]
name           = "rocksdb_load_30M"
table          = "purchases_rocks"
create_table   = true
table_options  = "ENGINE=RocksDB DEFAULT CHARSET=utf8mb4"
duration       = "20m"
max_rows_total = 30000000
log_file       = "rocksdb_load.tsv"

[[task]]
name                = "rocksdb_mixed_15m"
table               = "purchases_rocks"
create_table        = false
writer_threads      = 8
max_rows_per_second = 30000
query_threads       = 8
queries_per_second  = 300
query_start_at_rows = 1000000
duration            = "15m"
log_file            = "rocksdb_mixed.tsv"
```

The above TOML work queue runs six tasks sequentially against MariaDB over the Unix socket at /tmp/mariadb.sock, comparing InnoDB, TidesDB, and RocksDB on the same schema and workload. For each engine in turn, it does a load then a mixed phase on a separate table (purchases_innodb, purchases_tides, purchases_rocks).

transactionid INT AUTO_INCREMENT PRIMARY KEY, plus dateandtime DATETIME, four small ints (cashregisterid, customerid, productid, price), and four VARCHAR(100) padding columns where 70 bytes are random a-z and 30 bytes are uniform 'a' (compressible). 
  
Three canonical iibench secondary indexes are created:
1. marketsegment(price, customerid)
2. registersegment(cashregisterid, price, customerid)
3. pdc(price, dateandtime, customerid).

Each load task (*_load_30M) drops and recreates the table, builds one shared prepared multi-row INSERT of 1000 rows, and fans out 16 writer goroutines. The writers race uncapped until either 30,000,000 rows are inserted or 20 minutes elapse, whichever comes first. Each row in a batch gets a microsecond-stepped per-row timestamp so the pdc index sees real cardinality. Failed batches are not retried - their error codes are bucketed into the sidecar log instead.

Each mixed task (*_mixed_15m) reuses the populated table for exactly 15 minutes. 8 writer threads are throttled at a total 30,000 rows/sec (3,750/s each, enforced with a 1-second window), while 8 query threads run round-robin across the four iibench query types (pk, pdc, marketsegment, registersegment) at a total of 300 qps (37.5 qps each, ~26.6 ms between starts per thread, clamped so a slow query doesn't trigger burst-catchup). The query_start_at_rows = 1000000 gate trips instantly since the table already holds ~30M rows from the load.

Output lands in a fresh runs/<YYYYMMDD-HHMMSS>/ directory (with runs/latest symlinked to it). Each task writes a main TSV (elapsed_s, inserts, rates, p50/p99/p999 latency, error counts) plus a sidecar .errcodes TSV (elapsed_s, kind, code, int_count, cum_count) that gets populated only when errors occur.

For my analysis I used the MariaDB configuration file <a target="_blank" href="https://github.com/tidesdb/hammer/blob/master/my.cnf.example">here</a>

The key highlights in configuration are all engines are deliberately aligning variables that matter so the comparison measures engine architecture rather than sync latency or cache size. 

Each engine gets a 6 GB block/buffer cache, ~256 MB of write-side memory, 8 background threads, READ-COMMITTED isolation, LZ4 compression, and per-commit durability turned off (binlog disabled, doublewrite off, WAL flushed roughly every second instead of every commit).

The data on disk for these runs surpassed the set buffer/cache size of 6GB, hitting over triple that on disk based on analysis.

I ran this work on a fresh <a target="_blank" href="https://github.com/MariaDB/server/releases/tag/mariadb-11.8.6">MariaDB 11.8.6</a> install on this environment: 
- AMD Ryzen Threadripper 2950X (16 cores 32 threads) @ 3.5GHz
- 128GB DDR4
- Ubuntu 22.04 x86_64
- GCC (glibc)
- XFS raw NVMe (SAMSUNG MZVLB512HAJQ-00000) with discard, inode64, nodiratime, noatime, logbsize=256k, logbufs=8
- TidesDB v9.2.3 library used with TideSQL v4.5.1
- MyRocks plugin shipped in MariaDB. Lags upstream RocksDB by several major versions

So let's dive in.

**Load phase - 30M rows**

![Throughput](/iibench-tidesql-v4-5-1-myrocks-innodb-mariadb-v11-8-6-analysis/fig1_load_throughput.png)
![Load Summary](/iibench-tidesql-v4-5-1-myrocks-innodb-mariadb-v11-8-6-analysis/fig2_load_summary.png)
![Load Latency](/iibench-tidesql-v4-5-1-myrocks-innodb-mariadb-v11-8-6-analysis/fig3_load_latency.png)

TidesDB finished in 98s. MyRocks took 282s, InnoDB 299s. That's roughly 3x faster ingest.

TidesDB starts at ~425k ins/s and smoothly decays to ~175k as compaction back-pressure ramps. MyRocks holds around 100k but takes a hard stall down to ~40k near the 200s mark. InnoDB grinds from ~125k down to ~86k, classic B-tree degradation, no stalls but no recovery either.

TidesDB's worst p99 across the whole load (137ms) is lower than the mean p99 of either other engine (~700ms). Not close.

**Mixed phase - write+read**

![Mixed Insert Latency](/iibench-tidesql-v4-5-1-myrocks-innodb-mariadb-v11-8-6-analysis/fig4_mixed_insert_latency.png)

![Mixed Query Latency](/iibench-tidesql-v4-5-1-myrocks-innodb-mariadb-v11-8-6-analysis/fig5_mixed_query_latency.png)

Everyone's throttled to 30k ins/s and 300 qps. They all hit it. So throughput isn't the story, latency is.

On inserts, TidesDB wins clean. Mean p50 is 30ms vs MyRocks 57ms vs InnoDB 84ms. The tail is where it gets interesting though, across all 91 ten-second windows, 100% of TidesDB intervals had p99 below MyRocks's median p99. TidesDB's worst p99 ever (59ms) is lower than MyRocks's median (97ms) and InnoDB's median (112ms). InnoDB had 9 intervals over 200ms, peaking at 562ms. TidesDB had zero over 100ms.

On queries, MyRocks takes it and it's not really close, ~1ms p50, p99 never exceeds 1.73ms across the whole run. That's the cleanest result for any engine in any panel. InnoDB has the best median (0.32ms) but its p99 is 30x worse than its p50, write contention biting. TidesDB sits in the middle on tails but is ~3x slower than MyRocks at the median, with one outlier spike to 88ms near the end of the run.


![Summary](/iibench-tidesql-v4-5-1-myrocks-innodb-mariadb-v11-8-6-analysis/fig6_summary.png)

**TL;DR**

If you're writing heavy, TidesDB is the pick, half the mixed-write latency, p99 that doesn't even overlap the other two.

If you're read-heavy, MyRocks query latency is hard to argue with, honestly.

InnoDB is best query p50 and worst at basically everything else here.

One caveat, single run per engine. The intervals give you within-run variance, not run-to-run.


With that, this is my own analysis, please also do your own!

Thank you for reading.

-- 

You can find the raw data for this run here: <a href="/iibench-tidesql-v4-5-1-myrocks-innodb-mariadb-v11-8-6-analysis/iibench_run_may18th2026.zip"> iibench_run_may18th2026.zip (5618a170a0596accb34adaa1ed2463e54e3bc838ac170d8d46e3460758ab1978)</a>





---
title: "TidesDB vs InnoDB within MariaDB"
description: "Observations from custom benchmarks and Sysbench OLTP workloads comparing TidesDB 7 and InnoDB"
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-molnartamasphotography-25956362.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-molnartamasphotography-25956362.jpg
---

<div class="article-image ob-bottom">

![TidesDB vs InnoDB within MariaDB](/pexels-molnartamasphotography-25956362.jpg)

</div>

*by Alex Gaetano Padula*  
*published on January 29th, 2026*

---

Hey everyone, today I finally got a chance to benchmark <a href="/reference/tidesql/">TideSQL</a>, the pluggable TidesDB storage engine for MariaDB.

TidesDB's plugin engine is still in its early stages, but the feature set is shaping up well, and the performance characteristics are interesting enough to warrant an article and closer look. Below, I walk through both custom microbenchmarks and Sysbench OLTP workloads to highlight where TidesDB behaves differently from InnoDB.

Feel free to benchmark your own workloads or run Sysbench yourself. The custom benchmark data was gathered using these <a href="https://github.com/tidesdb/tidesql/tree/master/bench">scripts</a>.

All benchmarks were run with **sync mode enabled**, which is the default for MariaDB.

**Environment**
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)
- Ubuntu 23.04 x86_64 6.2.0-39-generic
- TidesDB v7.4.2
- MariaDB v12.1.2

---

## Single-threaded throughput at 100k rows

![Single-threaded throughput at 100k rows](/tidesdb-vs-innodb-within-mariadb/1.png)

Starting with the first figure, this compares single-threaded throughput across core operations at a dataset size of 100k rows.

TidesDB shows higher throughput for write-heavy operations, particularly bulk and sequential inserts. This aligns with its LSM-tree architecture.

InnoDB performs competitively on point selects, reflecting its B+-tree layout and optimized read paths.

Overall, the results highlight a trade-off between write-optimized and read-optimized storage engines under single-threaded execution.

---

## Sequential INSERT scaling

![Sequential INSERT scaling](/tidesdb-vs-innodb-within-mariadb/2.png)

This figure shows the execution time of sequential inserts as the row count increases.

Insertion cost grows roughly linearly with data size, showing stable behavior without sharp performance cliffs.

This behavior is consistent with TidesDB’s architecture, which amortizes write costs over time.

---

## Concurrent throughput (4 threads, 100k rows)

![Concurrent throughput (4 threads, 100k rows)](/tidesdb-vs-innodb-within-mariadb/3.png)

This figure compares total throughput under concurrent workloads using four threads.

TidesDB achieves higher throughput for concurrent inserts and updates, reflecting its mostly lock-free architecture and MVCC-based concurrency control.

InnoDB performs well for concurrent reads but shows lower throughput for write-heavy and mixed workloads, likely due to increased latch and lock contention.

---

## Sysbench OLTP benchmarks

In addition to the custom benchmarks above, I ran a set of Sysbench OLTP workloads using batched Lua scripts (you can find in TidesSQL repo). These tests better approximate real-world transactional behavior, including point reads, range scans, updates, and delete/insert cycles.

All tests were run with:
- 1 table
- 100k rows
- 4 threads
- Sync mode enabled
- _Identical_ batched workloads for both engines

---

### Sysbench OLTP throughput (TPS)

![Sysbench OLTP throughput](/tidesdb-vs-innodb-within-mariadb/sysbench_tps.png)

This figure compares transaction throughput across read-only, read-write, and write-only workloads.

InnoDB achieves higher throughput for read-only workloads, which is expected given its mature engine implementation.

TidesDB performs competitively in write-only workloads and slightly exceeds InnoDB in _this_ configuration. This reflects its write buffering and reduced coordination overhead under sustained writes.

For mixed read-write workloads, InnoDB maintains higher throughput, though the gap narrows compared to the read-only case.

---

### Sysbench OLTP average latency

![Sysbench OLTP average latency](/tidesdb-vs-innodb-within-mariadb/sysbench_latency_avg.png)

This figure shows average transaction latency.

In read-only and mixed workloads, InnoDB exhibits lower average latency, consistent with cache-friendly access patterns and minimal write coordination.

For write-only workloads, latency between the two engines is comparable, with TidesDB slightly lower in this configuration.

---

### Sysbench OLTP p95 latency

![Sysbench OLTP p95 latency](/tidesdb-vs-innodb-within-mariadb/sysbench_latency_p95.png)

This figure highlights tail latency behavior.

InnoDB maintains lower p95 latency for read-heavy and mixed workloads. TidesDB shows higher tail latency in read-write scenarios, mostly due to slower read paths (B+Tree vs LSM-tree).

For write-only workloads, TidesDB demonstrates slightly better tail latency.

---

## Summary

TidesDB favors write-heavy workloads, space efficiency benefiting from its LSM-tree architecture, adaptive compaction, and mostly lock-free design. It performs well under concurrent writes and scales predictably as data volume increases.

InnoDB excels in read-heavy and mixed workloads, delivering higher throughput and lower latency in those scenarios.

If you are looking to experiment with a high write-throughput engine inside MariaDB, TidesDB is worth evaluating. For read-heavy transactional workloads, InnoDB remains a strong default contender.

---

*Thanks for reading!*

**Raw Data**
- <a href="/tidesdb-vs-innodb-within-mariadb/tidesdb_innodb_benchmark_concurrent_results_100000.csv" download>tidesdb_innodb_benchmark_concurrent_results_100000.csv</a>
- <a href="/tidesdb-vs-innodb-within-mariadb/tidesdb_innodb_benchmark_results_500.csv" download>tidesdb_innodb_benchmark_results_500.csv</a> 
- <a href="/tidesdb-vs-innodb-within-mariadb/tidesdb_innodb_benchmark_results_5000.csv" download>tidesdb_innodb_benchmark_results_5000.csv</a> 
- <a href="/tidesdb-vs-innodb-within-mariadb/tidesdb_innodb_benchmark_results_100000.csv" download>tidesdb_innodb_benchmark_results_100000.csv</a> 
- <a href="/tidesdb-vs-innodb-within-mariadb/InnoDB_oltp_read_only_batched_20260128_230344.txt" download>InnoDB_oltp_read_only_batched_20260128_230344.txt</a> 
- <a href="/tidesdb-vs-innodb-within-mariadb/InnoDB_oltp_read_write_batched_20260128_230344.txt" download>InnoDB_oltp_read_write_batched_20260128_230344.txt</a> 
- <a href="/tidesdb-vs-innodb-within-mariadb/InnoDB_oltp_write_only_batched_20260128_230344.txt" download>InnoDB_oltp_write_only_batched_20260128_230344.txt</a> 
- <a href="/tidesdb-vs-innodb-within-mariadb/TidesDB_oltp_read_only_batched_20260128_230344.txt" download>TidesDB_oltp_read_only_batched_20260128_230344.txt</a> 
- <a href="/tidesdb-vs-innodb-within-mariadb/TidesDB_oltp_read_write_batched_20260128_230344.txt" download>TidesDB_oltp_read_write_batched_20260128_230344.txt</a> 
- <a href="/tidesdb-vs-innodb-within-mariadb/TidesDB_oltp_write_only_batched_20260128_230344.txt" download>TidesDB_oltp_write_only_batched_20260128_230344.txt</a> 

Thank you @theseyan for the feedback on grammar.
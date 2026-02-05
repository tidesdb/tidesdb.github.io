---
title: "Benchmark Analysis on TidesDB v8.1.1, RocksDB v10.10.1, and LMDB v0.9.24"
description: "Benchmark Analysis on TidesDB v8.1.1, RocksDB v10.10.1, and LMDB v0.9.24"
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-karola-g-4711782.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-karola-g-4711782.jpg
---

<div class="article-image">

![Benchmark Analysis on TidesDB v8.1.1, RocksDB v10.10.1, and LMDB v0.9.24](/pexels-karola-g-4711782.jpg)

</div>

*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on February 4th, 2026*

I came across a <a href="http://smalldatum.blogspot.com/2015/08/different-kinds-of-copy-on-write-for-b.html?m=1">post</a> by the Small Datum blog (Mark Callaghan) and in the comments there was some dicussion that inspired me to add LMDB to the <a href="https://github.com/tidesdb/benchtool">benchtool</a> and run some benchmarks across TidesDB, RocksDB, and LMDB.

**Environment**
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)
- Ubuntu 23.04 x86_64 6.2.0-39-generic
- TidesDB v8.1.1 (Compressed Block KLog format with LZ4 compression)
- <a href="https://rocksdb.org/">RocksDB</a> v10.10.1 (Compressed with LZ4 compression)
- <a href="https://www.symas.com/mdb">LMDB</a> v0.9.24 (Lightning Memory-Mapped Database)
- GCC (glibc)

## Write Throughput Comparison
![Write Throughput Comparison](/tidesdb-8-1-1-rocksdb-10-10-1-lmdb-0-9-24-bench/write_throughput.png)

## Write Latency Comparison
![Write Latency Comparison](/tidesdb-8-1-1-rocksdb-10-10-1-lmdb-0-9-24-bench/write_latency.png)

## Write Amplification Comparison
![Write Amplification Comparison](/tidesdb-8-1-1-rocksdb-10-10-1-lmdb-0-9-24-bench/write_amplification.png)

## Read Throughput Comparison
![Read Throughput Comparison](/tidesdb-8-1-1-rocksdb-10-10-1-lmdb-0-9-24-bench/read_throughput.png)

## Read Latency Comparison
![Read Latency Comparison](/tidesdb-8-1-1-rocksdb-10-10-1-lmdb-0-9-24-bench/read_latency.png)

## Range Query 
![Range Query](/tidesdb-8-1-1-rocksdb-10-10-1-lmdb-0-9-24-bench/range_query.png)

## Seek Performance
![Seek Performance](/tidesdb-8-1-1-rocksdb-10-10-1-lmdb-0-9-24-bench/seek_performance.png)

## Mixed Workload
![Mixed Workload](/tidesdb-8-1-1-rocksdb-10-10-1-lmdb-0-9-24-bench/mixed_workload.png)

## Disk Usage
![Disk Usage](/tidesdb-8-1-1-rocksdb-10-10-1-lmdb-0-9-24-bench/disk_usage2.png)

## CPU Usage
![CPU Usage](/tidesdb-8-1-1-rocksdb-10-10-1-lmdb-0-9-24-bench/cpu_usage.png)

## Memory Usage
![Memory Usage](/tidesdb-8-1-1-rocksdb-10-10-1-lmdb-0-9-24-bench/memory_usage.png)


TidesDB achieves 7.01 Mops/sec for sequential writes compared to RocksDB's 2.11 Mops/sec and LMDB's 2.38 Mops/sec. This advantage narrows under random access patterns, where TidesDB delivers 2.57 Mops/sec versus RocksDB's 1.98 Mops/sec and LMDB's 0.77 Mops/sec. The write amplification measurements show TidesDB at 1.04-1.10x across patterns, RocksDB at 1.23-1.41x, and LMDB at 1.64-1.80x. 

For read operations, LMDB dominates with 5.91 Mops/sec and 1.10μs average latency, benefiting from its memory-mapped architecture. TidesDB shows 2.86 Mops/sec with 2.59μs latency, while RocksDB trails at 0.99 Mops/sec and 7.52μs. In mixed workloads (50/50 read-write), TidesDB maintains 2.19 Mops/sec writes and 1.54 Mops/sec reads, RocksDB shows 1.53/1.03 Mops/sec, and LMDB exhibits asymmetric behavior at 0.70/6.94 Mops/sec. 

Resource utilization reveals TidesDB uses 2,483MB RSS with 573-671% CPU utilization across 8 threads, RocksDB uses 246-308MB RSS with 251-302% CPU, and LMDB uses 3,194-3,373MB RSS with 100% CPU.

That's it for this article, it's a short one, if you want to do a deeper dive on the data you can find the raw benchtool data in the article footer. 

*Thanks for reading!*

---

CSV Data:

- <a href="/tidesdb-8-1-1-rocksdb-10-10-1-lmdb-0-9-24-bench/tidesdb_rocksdb_lmdb_benchmark_results_20260204_165956.csv" download>tidesdb_rocksdb_lmdb_benchmark_results_20260204_165956.csv</a>

Thank you @TheSeyan for the feedback and suggestions!
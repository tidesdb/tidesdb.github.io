---
title: "Benchmark Analysis on TidesDB v7.4.4 & RocksDB v10.9.1"
description: "Performance benchmarks comparing TidesDB v7.4.4 and RocksDB v10.9.1 on write, read, and mixed workloads with default glibc allocator on Linux."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-pok-rie-33563-776326.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-pok-rie-33563-776326.jpg
---

<div class="article-image">

![TidesDB v7.4.4 vs RocksDB v10.9.1 Benchmarks](/pexels-pok-rie-33563-776326.jpg)

</div>

*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on Feb 1st, 2026*

Micro optimizations! I find myself almost every day performance testing components and different configurations to identify opportunities for optimization and then applying them. This includes optimizing for throughput, lower latency, space efficiency, and other aspects of performance. In this patch, I focused on reducing syscalls and CPU cycles, improving fast paths for comparisons, and enhancing cache locality. I worked on the bloom filter, the block manager skip list, and the core read paths within TidesDB.

I ran the benchmarks using `tidesdb_rocksdb.sh` within the <a href="https://github.com/tidesdb/benchtool">benchtool</a> repo on the specifications described below.

**Environment**
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)
- Ubuntu 23.04 x86_64 6.2.0-39-generic
- TidesDB v7.4.3 & v7.4.4
- RocksDB v10.9.1
- GCC (glibc)



**Gains from v7.4.3**
![Gains from v7.4.3](/tidesdb-v7-4-4-rocksdb-v10-9-1/fig1.png)

Overall, v7.4.4 delivers consistent and often substantial performance gains across the majority of workloads. Many read-, seek-, and range-oriented workloads show improvements in the 1.2x–1.6x range, with the largest gains exceeding 2.3x.


## TidesDB v7.4.4 & RocksDB v10.9.1 Comparisons

**Sequential Put Throughput**
![Sequential Put Throughput](/tidesdb-v7-4-4-rocksdb-v10-9-1/fig2.png)
TidesDB achieves substantially higher write throughput, sustaining approximately 6.7 million operations per second, compared to ~1.3 million operations per second for RocksDB.

**Random Put Throughput**
![Random Put Throughput](/tidesdb-v7-4-4-rocksdb-v10-9-1/fig3.png)
Random write performance shows a similar but less pronounced advantage for TidesDB. Under a randomized key distribution, TidesDB sustains roughly 2.8 million operations per second, while RocksDB reaches approximately 1.4 million operations per second. Although both systems experience a throughput reduction relative to sequential writes, the degradation is noticeably smaller for TidesDB.

**Random Read Throughput**
![Random Read Throughput](/tidesdb-v7-4-4-rocksdb-v10-9-1/fig4.png)
Random read throughput highlights a significant divergence between the two systems. TidesDB delivers close to 14 million iterator operations per second, exceeding RocksDB’s ~5.9 million operations per second by more than a factor of two.

**Range Scan Throughput**
![Range Scan Throughput](/tidesdb-v7-4-4-rocksdb-v10-9-1/fig5.png)
Range scan performance further reinforces the observed trend. TidesDB achieves approximately 800k range operations per second, while RocksDB reaches around 370k operations per second under the same configuration.

**Throughput Summary Across Workloads**
![Throughput Summary Across Workloads](/tidesdb-v7-4-4-rocksdb-v10-9-1/fig6.png)

**Median Latency (p50) Across Workloads**
![Median Latency (p50) Across Workloads](/tidesdb-v7-4-4-rocksdb-v10-9-1/fig7.png)

**Tail Latency (P95) Across Workloads**
![Tail Latency (P95) Across Workloads](/tidesdb-v7-4-4-rocksdb-v10-9-1/fig8.png)

**Extreme Tail Latency (p99) Across Workloads**
![Extreme Tail Latency (p99) Across Workloads](/tidesdb-v7-4-4-rocksdb-v10-9-1/fig9.png)

Taken together, the figures show a consistent performance advantage for TidesDB over RocksDB across a wide range of workloads. The log-scale throughput summary demonstrates that TidesDB sustains higher operations per second in most cases, with especially large gains in iterator-heavy reads and several write configurations, indicating that its advantages are broad rather than workload-specific. The median (p50) latency results show that TidesDB generally delivers lower typical request latency for PUT operations and remains competitive or better for range scans, reflecting lower baseline per-request overhead. RocksDB experiences higher and more variable tail latencies in multiple write workloads, due to background activity surfacing in the request paths, while TidesDB maintains lower, more stable tails. Even at the extreme tail (p99), TidesDB exhibits fewer severe outliers, better isolation of maintenance work and a more predictable service-time profile overall.

**Write / Space Amplification Across Write Workloads**
![Write / Space Amplification Across Write Workloads](/tidesdb-v7-4-4-rocksdb-v10-9-1/fig10.png)
TidesDB’s lower amplification in these scenarios is due to aggressive space reclamation that reduces the lifetime of overwritten data. TidesDB converts write throughput advantages into tangible storage efficiency gains, reducing disk footprint and, by extension, long-term I/O and compaction pressure.


This is all for this article, I hope you found it useful!  To download the latest patch you can go to <a href="https://github.com/tidesdb/tidesdb/releases">this page</a>.


*Thanks for reading!*

---

Want to learn about how TidesDB works? Check out <a href="/getting-started/how-does-tidesdb-work/">this page</a>.

For raw benchtool data, see below:

- <a href="/tidesdb_rocksdb_benchmark_results_20260131_225035.txt" download>tidesdb_rocksdb_benchmark_results_20260131_225035.txt</a>
- <a href="/tidesdb_rocksdb_benchmark_results_20260131_225035.csv" download>tidesdb_rocksdb_benchmark_results_20260129_173523.txt</a>
- <a href="/tidesdb_rocksdb_benchmark_results_20260129_181005.csv" download>tidesdb_rocksdb_benchmark_results_20260129_181005.csv</a>

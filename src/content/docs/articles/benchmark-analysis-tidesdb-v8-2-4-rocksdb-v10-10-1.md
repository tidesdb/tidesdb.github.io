---
title: "Benchmark Analysis on TidesDB v8.2.4 and RocksDB v10.10.1"
description: "Deep benchmark analysis on TidesDB v8.2.4 and RocksDB v10.10.1 across multiple workloads"
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-maksym-parovenko-2151629581-33338863.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-maksym-parovenko-2151629581-33338863.jpg
---

<div class="article-image">

![Benchmark Analysis on TidesDB v8.2.1 and RocksDB v10.10.1](/pexels-maksym-parovenko-2151629581-33338863.jpg)

</div>

*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on February 10th, 2026*

With the latest patch of TidesDB, of course there is another benchmark for you all.  The latest patch mainly worked on reducing allocations and work in the iterator read paths.

In this article I go through the usual tidesdb_rocksdb.sh script which runs the TidesDB <a target="_blank" href="https://github.com/tidesdb/benchtool">benchtool</a>.

The environment used:
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)
- Ubuntu 23.04 x86_64 6.2.0-39-generic
- TidesDB v8.2.4
- <a href="https://rocksdb.org/">RocksDB</a> v10.10.1 (Pinned L0 index/filter blocks, HyperClock cache, block indexes)
- GCC (glibc)
- LZ4 Compression used for both engines


**Write throughput (ops/sec)**

![Write throughput (ops/sec)](/benchmark-tidesdb-v8-2-4-rocksdb-v10-10-1/p1.png)

The throughput plot shows a consistent and often large advantage for TidesDB over RocksDB across nearly all write-heavy workloads. The gap is most pronounced in sequential and range-based workloads (e.g., write_seq_10M, range_random, range_seq), where TidesDB sustains roughly 2-4x higher ops/sec. 

**Average write latency (µs)**

![Average write latency (µs)](/benchmark-tidesdb-v8-2-4-rocksdb-v10-10-1/p2.png)


Average latency reveals a sharper contrast in tail sensitivity between the two engines. While both systems maintain low latency for most steady-state workloads, RocksDB exhibits rather extreme latency spikes in several batch-heavy and delete-mixed tests, reaching tens of milliseconds. TidesDB also shows increases under these stressors, but the magnitude is substantially smaller. 

**Write amplification**

![Write amplification](/benchmark-tidesdb-v8-2-4-rocksdb-v10-10-1/p3.png)

Write amplification is consistently lower for TidesDB, typically clustering around ~1.05-1.15, while RocksDB ranges higher, often exceeding ~1.25 and peaking further under mixed workloads. This difference is structurally important, lower amplification directly translates to reduced SSD wear, lower I/O pressure, and more stable long-term throughput.

**Read / iteration throughput**

![Read / iteration throughput](/benchmark-tidesdb-v8-2-4-rocksdb-v10-10-1/p4.png)

The read throughput plot shows TidesDB consistently outperforming RocksDB, often by 2-3x in iterator-heavy and range-scan workloads. The gap widens notably for seek, range_seq, and range_random tests.

**On-disk space footprint**

![On-disk space footprint](/benchmark-tidesdb-v8-2-4-rocksdb-v10-10-1/p5.png)

TidesDB generally occupies less on-disk space for the same logical workload, with especially large savings in delete-heavy and mixed write/read scenarios. RocksDB shows larger and more variable database sizes, consistent with higher space amplification and delayed reclamation of obsolete data during compaction.

**Total disk write volume**

![Total disk write volume](/benchmark-tidesdb-v8-2-4-rocksdb-v10-10-1/p6.png)

Total disk write volume strongly reinforces the amplification results. RocksDB writes substantially more data to disk across nearly all workloads, with extreme divergence in batch and delete-heavy tests where cumulative writes exceed TidesDB by a wide margin.

That's all for this article. The data shows us TidesDB has not regressed from previous versions and continues to perform very well.  The micro optimizations the past couple patches really shows in the read paths.

*Thanks for reading!*

-- 

Data:
- <a href="/benchmark-tidesdb-v8-2-4-rocksdb-v10-10-1/tidesdb_rocksdb_benchmark_results_20260210_034029.csv" download>tidesdb_rocksdb_benchmark_results_20260210_034029.csv</a>
- <a href="/benchmark-tidesdb-v8-2-4-rocksdb-v10-10-1/tidesdb_rocksdb_benchmark_results_20260210_034029.txt" download>tidesdb_rocksdb_benchmark_results_20260210_034029.txt</a>

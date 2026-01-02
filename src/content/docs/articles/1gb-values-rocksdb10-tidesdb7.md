---
title: "1GB Value Observations TidesDB 7 & RocksDB 10"
description: "An article on observations of 1GB value benchmarks between TidesDB 7 & RocksDB 10"
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-budget-bizar-92378004-16644281.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-budget-bizar-92378004-16644281.jpg
---

<div class="article-image">

![1GB Value Observations TidesDB 7 & RocksDB 10](/pexels-budget-bizar-92378004-16644281.jpg)

</div>

*by Alex Gaetano Padula*

*published on January 2nd, 2026*

This question comes up often on the TidesDB Discord, how do these engines handle very large values? In this article, I benchmark 1GB values against TidesDB 7 and RocksDB 10. The first run uses default configurations for both engines; The second increases the memtable write buffer and cache to 3GB each.

One recommendation before diving in, if possible, break up large values into smaller chunks with keys that sort near each other. This improves locality and reduces fragmentation. For example, a multi-gigabyte video file could be stored as sequential chunks in TidesDB, then read back in order for streaming playback.

# Test Configuration

All benchmarks were executed with sync mode disabled to measure maximum throughput potential. 

**We recommend you benchmark your own use case to determine which storage engine is best for your needs!**


**Hardware**
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)
- Ubuntu 23.04 x86_64 6.2.0-39-generic

**Software Versions**
- **TidesDB v7.0.10**
- **RocksDB v10.7.5**
- GCC with -O3 optimization

You can download the raw benchtool report for first run wih 64mb memtable write buffer and 64mb cache <a href="/large_value_benchmark_1gb_results_tdb7_rdb10_1.txt" download>here</a>

You can download the raw benchtool report for second run with 3GB memtable write buffer and 3GB cache <a href="/large_value_benchmark_1gb_results_tdb7_rdb10_2.txt" download>here</a>

You can find the **benchtool** source code <a href="https://github.com/tidesdb/benchtool" target="_blank">here</a> and run your own benchmarks!


## Findings

### Run 1 · Default Configuration (64MB memtable/cache)

| Operation | TidesDB | RocksDB | Winner |
|-----------|---------|---------|--------|
| **PUT** | 0.28 ops/sec | 0.44 ops/sec | RocksDB (1.57x) |
| **GET** | 1.49 ops/sec | 1.07 ops/sec | TidesDB (1.39x) |
| **RANGE** | 0.19 ops/sec | 0.84 ops/sec | RocksDB (4.4x) |

**Resource Usage (PUT)**

| Metric | TidesDB | RocksDB | Winner |
|--------|---------|---------|--------|
| Peak RSS | 1,059 MB | 6,166 MB | TidesDB (5.8x less) |
| Database Size | 40.16 MB | 1,060 MB | TidesDB (26x smaller) |
| Write Amplification | 1.01x | 1.00x | Similar |

**Resource Usage (GET)**

| Metric | TidesDB | RocksDB | Winner |
|--------|---------|---------|--------|
| Peak RSS | 25 MB | 3,095 MB | TidesDB (124x less) |
| Avg Latency | 621ms | 912ms | TidesDB (32% lower) |

### Run 2 · Optimized Configuration (3GB memtable/cache)

| Operation | TidesDB | RocksDB | Winner |
|-----------|---------|---------|--------|
| **PUT** | 0.19 ops/sec | 0.46 ops/sec | RocksDB (2.4x) |
| **GET** | 1.55 ops/sec | 1.04 ops/sec | TidesDB (1.49x) |
| **RANGE** | 0.18 ops/sec | 0.85 ops/sec | RocksDB (4.7x) |

**Resource Usage (PUT)**

| Metric | TidesDB | RocksDB | Winner |
|--------|---------|---------|--------|
| Peak RSS | 6,165 MB | 6,166 MB | Similar |
| Database Size | 40.16 MB | 1,060 MB | TidesDB (26x smaller) |
| Write Amplification | 1.00x | 1.00x | Similar |

**Resource Usage (GET)**

| Metric | TidesDB | RocksDB | Winner |
|--------|---------|---------|--------|
| Peak RSS | 25 MB | 3,095 MB | TidesDB (124x less) |
| Avg Latency | 601ms | 925ms | TidesDB (35% lower) |

### Key Observations

**RocksDB wins on writes and range scans with 1GB values.** 

RocksDB's write path seems to be optimized for large values but at quite a cost - it achieves 1.57-2.4x faster PUT throughput. For range queries, RocksDB is 4.4-4.7x faster. 

**TidesDB wins on point reads.** 

TidesDB achieves 1.39-1.49x faster GET operations with 32-35% lower latency. The WiscKey-style key-value separation pays off here - keys are stored separately from values, so finding the right key is fast even when values are massive.

**TidesDB uses dramatically less memory for reads.** 

During GET operations, TidesDB uses only 25 MB of RAM compared to RocksDB's 3,095 MB - that's 124x less memory. This is because TidesDB doesn't need to load entire 1GB values into memory to find them; it can locate the key first, then stream the value.

**TidesDB produces 26x smaller databases.** 

TidesDB's database size is 40.16 MB vs RocksDB's 1,060 MB. This is due to TidesDB's aggressive compaction and space reclamation. With 10 x 1GB values (10GB total data), TidesDB's 40MB footprint shows excellent space efficiency!

**Larger memtables hurt TidesDB's write performance.** 

Interestingly, increasing the memtable from 64MB to 3GB actually slowed TidesDB's writes (0.28 -> 0.19 ops/sec). This is because TidesDB's memtable is already well-tuned for default sizes, and larger buffers introduce a bit of overhead without benefit for this workload.

**Latency variance is higher with 1GB values.** 

TidesDB's p95 latency for writes reached 5-10 seconds in some cases, while RocksDB stayed more consistent at 1.3-2.2 seconds. Large values amplify key-value seperation inefficiencies in the write path.

## Conclusion

For 1GB values, RocksDB is the better choice for write-heavy and range-scan workloads, while TidesDB excels at point reads with dramatically lower memory usage.

If your use case involves storing very large values (videos, images, large documents) and you primarily read them by key, TidesDB offers quite compelling advantages at 1.4-1.5x faster reads, 124x less memory during reads, and 26x smaller database footprint.

However, if you're writing large values frequently or scanning ranges of them, RocksDB's mature large-value handling gives it a clear edge.

**My recommendation?** 

If you must store 1GB values, consider chunking them into smaller pieces (say, 4MB chunks) with sequential keys. This plays to TidesDB's strengths in write throughput and iteration while maintaining the ability to reconstruct the full value. Both engines will perform better with smaller, more manageable value sizes.

These results show general patterns, but your specific access patterns, hardware, and configuration will determine which engine performs best for you.

*Thanks for reading!*

---

**Links**
- GitHub · https://github.com/tidesdb/tidesdb
- Design deep-dive · https://tidesdb.com/getting-started/how-does-tidesdb-work

Join the TidesDB Discord for more updates and discussions at https://discord.gg/tWEmjR66cy

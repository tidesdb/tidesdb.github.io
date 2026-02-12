---
title: "Comparative Analysis of TidesDB v6 & RocksDB v10.7.5"
description: "Comprehensive performance benchmarks and architectural implications of both engines."
---

*by Alex Gaetano Padula*

*published on December 16th, 2025*

This document presents extensive performance benchmarks comparing **TidesDB** and **RocksDB**, two LSM-tree based storage engines. The tests cover 10 different workload scenarios with detailed metrics on throughput, latency, resource usage, and amplification factors.

**We recommend you benchmark your own use case to determine which storage engine is best for your needs!**

## Test Environment

**Hardware**
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)
- Ubuntu 23.04 x86_64 6.2.0-39-generic

**Software Versions**
- **TidesDB v6.0.0**
- **RocksDB v10.7.5**
- GCC with -O3 optimization

**Test Configuration**
- **Sync Mode** · DISABLED (maximum performance)
- **Default Batch Size** · 1000 operations
- **Threads** · 8 concurrent threads
- **Key Size** · 16 bytes (unless specified)
- **Value Size** · 100 bytes (unless specified)

You can download the raw benchtool report <a href="/benchmark_results_tdb6_rdb1075_1.txt" download>here</a>

You can find the **benchtool** source code <a href="https://github.com/tidesdb/benchtool" target="_blank">here</a> and run your own benchmarks!


## Executive Summary

This study presents a comprehensive performance comparison between TidesDB and RocksDB across multiple workload patterns, batch sizes, and data characteristics. Testing encompasses 10 distinct benchmark categories with varying operational patterns, revealing significant performance differentials that illuminate the architectural trade-offs between these storage engines.

Key findings indicate TidesDB demonstrates superior write throughput (1.32x to 3.28x faster) and substantially better space efficiency across most workloads. Most remarkably, TidesDB shows competitive read performance, achieving 1.76x faster random reads than RocksDB. 

## 1. Sequential Write Performance

Sequential write operations represent an idealized scenario where keys are inserted in order, minimizing internal reorganization overhead.

### Results Summary

| Metric | TidesDB | RocksDB | Advantage |
|--------|---------|---------|-----------|
| **Throughput** | 6,175,813 ops/sec | 1,881,405 ops/sec | <span style="color: green;">**TidesDB 3.28x**</span> |
| **Duration** | 1.619 seconds | 5.315 seconds | <span style="color: green;">**TidesDB 3.28x faster**</span> |
| **Median Latency** | 966 μs | 2,661 μs | <span style="color: green;">**TidesDB 2.8x lower**</span> |
| **P99 Latency** | 5,715 μs | 9,195 μs | <span style="color: green;">**TidesDB 1.6x lower**</span> |
| **Write Amplification** | 1.08x | 1.44x | <span style="color: green;">**TidesDB 25% lower**</span> |
| **Database Size** | 110.65 MB | 210.00 MB | <span style="color: green;">**TidesDB 1.9x smaller**</span> |
| **Peak Memory** | 2,483 MB | 2,737 MB | <span style="color: orange;">**TidesDB 9% lower**</span> |

### Analysis

TidesDB's performance advantage in sequential writes is extraordinary, achieving more than triple RocksDB's throughput at 6.18M ops/sec versus 1.88M ops/sec.

Write amplification strongly favors TidesDB at 1.08x versus 1.44x -- a 25% reduction indicating significantly less internal data movement during compaction and flushing operations. This low write amplification is crucial for SSD longevity and overall I/O efficiency.

The iteration throughput shows TidesDB at 8.22M ops/sec versus RocksDB's 5.30M ops/sec (1.55x faster), confirming that TidesDB's internal organization facilitates exceptionally fast sequential access patterns.

## 2. Random Write Performance

Random writes stress the storage engine's ability to handle dispersed key insertions, a more realistic workload for many applications.

### Results Summary

| Metric | TidesDB | RocksDB | Advantage |
|--------|---------|---------|-----------|
| **Throughput** | 2,591,250 ops/sec | 1,702,747 ops/sec | <span style="color: green;">**TidesDB 1.52x**</span> |
| **Duration** | 3.859 seconds | 5.873 seconds | <span style="color: green;">**TidesDB 1.52x faster**</span> |
| **Median Latency** | 2,831 μs | 4,696 μs | <span style="color: green;">**TidesDB 1.7x lower**</span> |
| **P99 Latency** | 8,389 μs | 12,071 μs | <span style="color: green;">**TidesDB 1.4x lower**</span> |
| **Write Amplification** | 1.12x | 1.33x | <span style="color: green;">**TidesDB 16% lower**</span> |
| **Database Size** | 89.75 MB | 113.17 MB | <span style="color: green;">**TidesDB 1.3x smaller**</span> |

### Analysis

Under random access patterns, TidesDB maintains a strong 52% throughput advantage at 2.59M ops/sec versus 1.70M ops/sec. The median latency advantage is particularly impressive -- 2,831 μs versus 4,696 μs represents a 1.7x improvement, indicating TidesDB handles random writes with significantly less overhead.

Write amplification remains favorable at 1.12x versus 1.33x (16% lower), demonstrating efficient internal organization even under randomized access patterns. The 1.3x smaller database size (89.75 MB vs 113.17 MB) continues to showcase TidesDB's superior space efficiency.

RocksDB shows faster iteration performance (4.23M ops/sec vs 3.26M ops/sec), suggesting its LSM-tree organization may be better optimized for post-write sequential scanning operations.

## 3. Random Read Performance

Read performance is critical for many database workloads, particularly those involving cache misses or cold data access.

### Results Summary

| Metric | TidesDB | RocksDB | Advantage |
|--------|---------|---------|-----------|
| **Throughput** | 2,554,727 ops/sec | 1,448,474 ops/sec | <span style="color: green;">**TidesDB 1.76x**</span> |
| **Duration** | 3.914 seconds | 6.904 seconds | <span style="color: green;">**TidesDB 1.76x faster**</span> |
| **Median Latency** | 3 μs | 5 μs | <span style="color: green;">**TidesDB 1.7x lower**</span> |
| **P99 Latency** | 5 μs | 13 μs | <span style="color: green;">**TidesDB 2.6x lower**</span> |
| **Peak Memory** | 1,722 MB | 332 MB | <span style="color: red;">**RocksDB 5.2x lower**</span> |

### Analysis

TidesDB demonstrates superior read performance, achieving 2.55M ops/sec versus RocksDB's 1.45M ops/sec -- a 76% advantage. This represents a complete reversal from earlier benchmarks where RocksDB held a 5.68x read advantage.

The latency characteristics are particularly impressive · TidesDB achieves 3 μs median latency versus RocksDB's 5 μs (1.7x lower), and at the P99 percentile, TidesDB's 5 μs versus RocksDB's 13 μs represents a 2.6x advantage. These microsecond-level latencies indicate highly efficient index structures and cache utilization.

However, RocksDB maintains a significant memory efficiency advantage during reads, consuming only 332 MB versus TidesDB's 1,722 MB (5.2x lower). This suggests TidesDB achieves its read performance through more aggressive memory caching, which could be a consideration for memory-constrained environments.

Iteration performance strongly favors TidesDB at 8.91M ops/sec versus 4.88M ops/sec (1.82x faster), confirming that sequential scanning is exceptionally efficient in TidesDB's architecture.

## 4. Mixed Workload Performance (50/50 Read/Write)

Real-world applications typically exhibit mixed access patterns. This test splits operations evenly between reads and writes.

### Results Summary

| Metric | TidesDB | RocksDB | Advantage |
|--------|---------|---------|-----------|
| **Write Throughput** | 2,162,367 ops/sec | 1,865,053 ops/sec | <span style="color: green;">**TidesDB 1.16x**</span> |
| **Read Throughput** | 1,450,517 ops/sec | 1,391,479 ops/sec | <span style="color: green;">**TidesDB 1.04x**</span> |
| **Write P50 Latency** | 3,084 μs | 3,917 μs | <span style="color: green;">**TidesDB 1.3x lower**</span> |
| **Read P50 Latency** | 5 μs | 5 μs | <span style="color: orange;">**Tied**</span> |
| **Write Amplification** | 1.09x | 1.25x | <span style="color: green;">**TidesDB 13% lower**</span> |
| **Database Size** | 43.86 MB | 78.19 MB | <span style="color: green;">**TidesDB 1.8x smaller**</span> |

### Analysis

Under mixed workloads, TidesDB demonstrates balanced performance advantages across both operations. The 16% write advantage (2.16M vs 1.87M ops/sec) and 4% read advantage (1.45M vs 1.39M ops/sec).

The read latency parity at 5 μs median is particularly noteworthy -- TidesDB matches RocksDB's read latency while maintaining superior write performance. 

The 1.8x difference in database size (43.86 MB vs 78.19 MB for identical data) demonstrates TidesDB's exceptional space efficiency, which translates to significant storage cost savings at scale. The 13% lower write amplification (1.09x vs 1.25x) further confirms TidesDB's efficiency advantages.

## 5. Hot Key Workload (Zipfian Distribution)

Many real-world applications exhibit skewed access patterns where certain keys are accessed much more frequently. This test uses a Zipfian distribution to simulate such "hot key" scenarios.

### Write-Only Zipfian Results

| Metric | TidesDB | RocksDB | Advantage |
|--------|---------|---------|-----------|
| **Throughput** | 2,930,965 ops/sec | 1,481,711 ops/sec | <span style="color: green;">**TidesDB 1.98x**</span> |
| **Duration** | 1.706 seconds | 3.375 seconds | <span style="color: green;">**TidesDB 1.98x faster**</span> |
| **Median Latency** | 2,421 μs | 3,384 μs | <span style="color: green;">**TidesDB 1.4x lower**</span> |
| **Database Size** | 10.10 MB | 61.81 MB | <span style="color: green;">**TidesDB 6.1x smaller**</span> |
| **Unique Keys** | 648,493 | 656,857 | <span style="color: orange;">**Similar**</span> |

### Mixed Zipfian Results

| Metric | TidesDB | RocksDB | Advantage |
|--------|---------|---------|-----------|
| **Write Throughput** | 2,944,365 ops/sec | 1,480,623 ops/sec | <span style="color: green;">**TidesDB 1.99x**</span> |
| **Read Throughput** | 2,725,468 ops/sec | 1,515,970 ops/sec | <span style="color: green;">**TidesDB 1.80x**</span> |
| **Read P50 Latency** | 2 μs | 3 μs | <span style="color: green;">**TidesDB 1.5x lower**</span> |
| **Database Size** | 10.15 MB | 56.25 MB | <span style="color: green;">**TidesDB 5.5x smaller**</span> |

### Analysis

The Zipfian workload continues to reveal exceptional performance from TidesDB. With nearly 2x write advantages (1.98x-1.99x) and 1.80x read advantage, TidesDB demonstrates superior handling of skewed access patterns that are common in real-world applications.

The space efficiency is extraordinary · 5.5x-6.1x smaller database sizes (10 MB vs 56-62 MB) for similar unique key counts indicate TidesDB's internal LSM architecture is highly effective for repeated writes to the same keys. RocksDB's LSM-tree architecture requires multiple versions of the same key to exist temporarily until compaction occurs, explaining the larger footprint.

TidesDB's read performance advantage in this scenario (2.73M ops/sec vs 1.52M ops/sec, with 2 μs vs 3 μs median latency) demonstrates excellent cache utilization for hot data. The consistent 2 μs read latency represents exceptional performance for frequently accessed keys.

**Key Insight** · While TidesDB shows balanced performance in uniform random workloads, it truly excels when access patterns exhibit locality -- a characteristic of most production workloads.

## 6. Delete Performance

Deletion efficiency impacts applications with high turnover rates, such as caching systems or time-series databases with retention policies.

### Results Summary

| Metric | TidesDB | RocksDB | Advantage |
|--------|---------|---------|-----------|
| **Throughput** | 3,805,864 ops/sec | 3,466,101 ops/sec | <span style="color: green;">**TidesDB 1.10x**</span> |
| **Duration** | 1.314 seconds | 1.443 seconds | <span style="color: green;">**TidesDB 1.10x faster**</span> |
| **Median Latency** | 1,930 μs | 2,357 μs | <span style="color: green;">**TidesDB 1.2x lower**</span> |
| **Write Amplification** | 0.18x | 0.28x | <span style="color: green;">**TidesDB 36% lower**</span> |
| **Final Database Size** | 0.00 MB | 63.77 MB | <span style="color: green;">**TidesDB complete**</span> |

### Analysis

TidesDB demonstrates a modest but consistent 10% advantage in delete throughput (3.81M vs 3.47M ops/sec), with 1.2x lower median latency. Both engines show impressive delete performance exceeding 3 million operations per second.

The write amplification factors are notable · both engines show values well below 1.0 (0.18x and 0.28x), indicating that deletion operations write significantly less data to disk than the original data size - expected behavior as deletions primarily involve tombstone markers rather than physical data removal. TidesDB's 36% lower write amplification (0.18x vs 0.28x) suggests more efficient tombstone handling.

The critical difference lies in space reclamation · TidesDB achieves a final database size of 0.00 MB after deleting all 5 million records, while RocksDB retains 63.77 MB. This demonstrates TidesDB performs immediate or aggressive garbage collection, while RocksDB requires explicit compaction to fully reclaim space. For applications with high delete rates or strict storage requirements, this difference could be operationally significant.

## 7. Large Value Performance

Many applications store larger values (documents, images, serialized objects). This test uses 4KB values with 256-byte keys.

### Results Summary

| Metric | TidesDB | RocksDB | Advantage |
|--------|---------|---------|-----------|
| **Throughput** | 318,774 ops/sec | 142,718 ops/sec | <span style="color: green;">**TidesDB 2.23x**</span> |
| **Duration** | 3.137 seconds | 7.006 seconds | <span style="color: green;">**TidesDB 2.23x faster**</span> |
| **Median Latency** | 22,563 μs | 35,069 μs | <span style="color: green;">**TidesDB 1.6x lower**</span> |
| **Write Amplification** | 1.05x | 1.21x | <span style="color: green;">**TidesDB 13% lower**</span> |
| **Database Size** | 302.33 MB | 348.24 MB | <span style="color: green;">**TidesDB 1.2x smaller**</span> |
| **Peak Memory** | 4,230 MB | 4,241 MB | <span style="color: orange;">**Similar**</span> |

### Analysis

TidesDB's performance advantage persists and strengthens with larger values, achieving 2.23x higher throughput (319K vs 143K ops/sec). This improvement over smaller value tests suggests TidesDB's architecture scales efficiently with value size.

The write amplification of 1.05x is particularly impressive, indicating minimal overhead despite the larger 4KB data size. This suggests highly efficient buffering and flushing strategies that avoid unnecessary data copying or reorganization.

Both engines show similar memory consumption (~4.2 GB), indicating comparable buffering strategies for large values. The 13% smaller database size for TidesDB (302 MB vs 348 MB) despite identical data suggests modest but consistent compression or more efficient metadata overhead.

Iteration performance strongly favors TidesDB at 961K ops/sec versus RocksDB's 444K ops/sec (2.17x faster), confirming that sequential access remains highly efficient even with large values probably because of key-value separation.

## 8. Small Value Performance

The converse scenario tests tiny 64-byte values with 16-byte keys,common in key-value caches and metadata stores.

### Results Summary

| Metric | TidesDB | RocksDB | Advantage |
|--------|---------|---------|-----------|
| **Throughput** | 1,470,133 ops/sec | 1,210,920 ops/sec | <span style="color: green;">**TidesDB 1.21x**</span> |
| **Duration** | 34.011 seconds | 41.285 seconds | <span style="color: green;">**TidesDB 1.21x faster**</span> |
| **Median Latency** | 4,265 μs | 5,521 μs | <span style="color: green;">**TidesDB 1.3x lower**</span> |
| **Write Amplification** | 1.24x | 1.50x | <span style="color: green;">**TidesDB 17% lower**</span> |
| **Database Size** | 520.86 MB | 444.23 MB | <span style="color: yellow;">**RocksDB 1.2x smaller**</span> |

### Analysis

With 50 million operations of small values, TidesDB maintains a 21% throughput advantage (1.47M vs 1.21M ops/sec). The 1.3x lower median latency (4,265 μs vs 5,521 μs) demonstrates consistent efficiency even at massive scale.

The 17% lower write amplification (1.24x vs 1.50x) indicates TidesDB maintains its efficiency advantage even with small records and high operation counts. This is particularly important for applications handling billions of small key-value pairs.

Interestingly, this is one of the few scenarios where RocksDB achieves a smaller database size (444 MB vs 521 MB, 1.2x smaller). This suggests RocksDB's compression or storage layout may be more efficient specifically for small uniform values at very large scale. However, TidesDB's iteration performance remains competitive at 2.44M ops/sec versus RocksDB's 2.37M ops/sec (1.03x faster).

## 9. Batch Size Analysis

Batch size significantly impacts throughput by amortizing synchronization and I/O overhead. This series tests batch sizes from 1 (no batching) to 10,000.

### Write Performance vs Batch Size

| Batch Size | TidesDB Throughput | RocksDB Throughput | TidesDB Advantage |
|------------|-------------------|-------------------|-------------------|
| **1** | 1,607,817 ops/sec | 862,733 ops/sec | <span style="color: green;">**1.86x**</span> |
| **10** | 2,615,187 ops/sec | 1,590,117 ops/sec | <span style="color: green;">**1.64x**</span> |
| **100** | 2,816,615 ops/sec | 1,998,387 ops/sec | <span style="color: orange;">**1.41x**</span> |
| **1,000** | 2,457,959 ops/sec | 1,863,018 ops/sec | <span style="color: yellow;">**1.32x**</span> |
| **10,000** | 658,860 ops/sec | 1,334,696 ops/sec | <span style="color: red;">**0.49x (RocksDB wins)**</span> |

### Analysis

The batch size analysis reveals non-linear performance characteristics with distinct optimal points:

1. **Optimal batch size differs** · TidesDB peaks at batch size 100 (2.82M ops/sec), while its performance degrades sharply at batch size 10,000. RocksDB shows more consistent performance across batch sizes, with best results at batch size 100 (2.00M ops/sec).

2. **Unbatched performance** · Even without batching, TidesDB maintains an 86% advantage (1.61M vs 863K ops/sec), suggesting efficient individual operation handling without requiring batching for good performance.

3. **Extreme batching** · At batch size 10,000, RocksDB outperforms TidesDB significantly (1.33M vs 659K ops/sec, 2.0x advantage).

4. **Write amplification remains favorable** · Across all batch sizes, TidesDB maintains lower write amplification (1.11x-1.26x vs 1.30x-1.40x for RocksDB), demonstrating consistent I/O efficiency regardless of batch configuration.

5. **Sweet spot** · For TidesDB, batch sizes between 10-100 provide optimal throughput (2.6M-2.8M ops/sec), while RocksDB performs best at 100-1,000 (1.9M-2.0M ops/sec).

### Latency Patterns

| Batch Size | TidesDB P50 | RocksDB P50 | Pattern |
|------------|-------------|-------------|---------|
| 1 | 2 μs | 3 μs | <span style="color: green;">Individual operation latency</span> |
| 10 | 23 μs | 31 μs | <span style="color: green;">~10x increase (expected amortization)</span> |
| 100 | 213 μs | 300 μs | <span style="color: green;">~100x increase (linear scaling)</span> |
| 1,000 | 2,725 μs | 4,022 μs | <span style="color: orange;">~1000x increase (linear)</span> |
| 10,000 | 66,285 μs | 60,819 μs | <span style="color: red;">Non-linear (saturation)</span> |

The near-linear relationship between batch size and latency (up to 1,000) confirms expected behavior: larger batches trade latency for throughput. The breakdown at 10,000 suggests internal buffer or lock contention limits, where TidesDB's latency increases disproportionately.

## 10. Delete Batch Size Analysis

Delete operations show different scaling characteristics than writes, revealing insights into tombstone management strategies.

### Delete Performance vs Batch Size

| Batch Size | TidesDB Throughput | RocksDB Throughput | TidesDB Advantage |
|------------|-------------------|-------------------|-------------------|
| **1** | 2,802,092 ops/sec | 944,562 ops/sec | <span style="color: green;">**2.97x**</span> |
| **100** | 3,756,625 ops/sec | 2,530,955 ops/sec | <span style="color: orange;">**1.48x**</span> |
| **1,000** | 2,982,304 ops/sec | 3,000,642 ops/sec | <span style="color: orange;">**1.00x (tied)**</span> |

### Analysis

Delete operations exhibit distinct batch size sensitivity patterns:

1. **Unbatched dominance** · TidesDB achieves nearly 3x higher throughput without batching (2.80M vs 945K ops/sec), suggesting exceptionally efficient individual delete operations. This dramatic advantage indicates TidesDB's tombstone mechanism has minimal per-operation overhead.

2. **Optimal batching** · TidesDB peaks at batch size 100 (3.76M ops/sec), representing a 34% improvement over unbatched deletes. RocksDB shows consistent improvement with larger batches, reaching peak performance at batch size 1,000.

3. **Performance convergence** · At batch size 1,000, both engines achieve similar throughput (2.98M vs 3.00M ops/sec), suggesting different internal optimization strategies that converge at scale. TidesDB's slight performance decline from batch=100 to batch=1,000 may indicate memory pressure or lock contention with large delete batches.

4. **Write amplification** · Both engines show remarkably low write amplification for deletes (0.18x-0.19x for TidesDB, 0.28x-0.33x for RocksDB), confirming that deletes primarily write tombstones rather than rewriting data. TidesDB's consistently lower amplification (36-42% lower) suggests more compact tombstone representation.

5. **Latency characteristics** · TidesDB maintains 2 μs median latency for unbatched deletes versus RocksDB's 8 μs (4x lower), demonstrating superior individual delete efficiency. At batch=100, latencies converge to ~180-300 μs range.

## Comparative Summary Tables

### Overall Performance Advantages

| Workload Type | Winner | Magnitude | Key Insight |
|---------------|--------|-----------|-------------|
| Sequential Write | TidesDB | <span style="color: green;">3.28x</span> | Exceptional sequential insertion |
| Random Write | TidesDB | <span style="color: green;">1.52x</span> | Strong performance under disorder |
| Random Read | TidesDB | <span style="color: green;">1.76x</span> | Dramatic architectural improvement |
| Mixed (50/50) | TidesDB | <span style="color: orange;">1.16x write / 1.04x read</span> | Balanced performance |
| Zipfian Write | TidesDB | <span style="color: green;">1.98x</span> | Excellent hot-key handling |
| Zipfian Mixed | TidesDB | <span style="color: green;">1.99x write / 1.80x read</span> | Superior cache utilization |
| Delete | TidesDB | <span style="color: orange;">1.10x</span> | Efficient tombstone management |
| Large Value | TidesDB | <span style="color: green;">2.23x</span> | Scales well with size |
| Small Value | TidesDB | <span style="color: orange;">1.21x</span> | Consistent advantage |

### Resource Efficiency Summary

| Metric | TidesDB Average | RocksDB Average | Winner |
|--------|-----------------|-----------------|--------|
| **Write Amplification** | 1.11x | 1.33x | <span style="color: orange;">**TidesDB (17% lower)**</span> |
| **Space Amplification** | 0.09x | 0.12x | <span style="color: orange;">**TidesDB (25% lower)**</span> |
| **Database Size** | Consistently smaller | Baseline | <span style="color: green;">**TidesDB (1.2x-6.1x smaller)**</span> |
| **Memory Usage (Writes)** | 2.5-11.6 GB | 2.7-11.6 GB | <span style="color: orange;">**TidesDB (slightly lower)**</span> |
| **Memory Usage (Reads)** | 1.7 GB | 0.3 GB | <span style="color: red;">**RocksDB (5.2x lower)**</span> |

### Latency Characteristics

| Percentile | Operation | TidesDB | RocksDB | Winner |
|------------|-----------|---------|---------|--------|
| **P50** | Random Write | 2,831 μs | 4,696 μs | <span style="color: green;">TidesDB (1.7x lower)</span> |
| **P50** | Random Read | 3 μs | 5 μs | <span style="color: green;">TidesDB (1.7x lower)</span> |
| **P50** | Zipfian Read | 2 μs | 3 μs | <span style="color: green;">TidesDB (1.5x lower)</span> |
| **P99** | Random Write | 8,389 μs | 12,071 μs | <span style="color: orange;">TidesDB (1.4x lower)</span> |
| **P99** | Random Read | 5 μs | 13 μs | <span style="color: green;">TidesDB (2.6x lower)</span> |

## Architectural Implications

### TidesDB's Design Philosophy

The benchmark results reveal TidesDB has evolved into a balanced, high-performance storage engine with several architectural strengths:

1. **Optimized Buffer Management** · The consistent 1.5x-3.3x write advantages across scenarios suggest highly efficient write buffering, possibly with intelligent memory allocation and asynchronous flushing strategies that minimize write latency.

2. **Superior Compression/Space Efficiency** · Database sizes 1.2x-6.1x smaller than RocksDB indicate either superior compression algorithms or highly efficient structural organization. The dramatic space savings in Zipfian workloads (6.1x smaller) suggest excellent update-in-place or deduplication strategies.

3. **Balanced Read/Write Optimization** · Unlike typical LSM-tree implementations that sacrifice read performance for write throughput, TidesDB achieves both excellent write performance (1.5x-3.3x faster) and competitive-to-superior read performance (1.04x-1.80x faster). 

4. **Efficient Index Structures** · The 3 μs median read latency with 2.55M ops/sec throughput indicates highly optimized index structures, likely with sophisticated caching layers that accelerate point lookups without sacrificing write performance.

5. **Immediate Garbage Collection** · The 0.00 MB database size after full deletion demonstrates eager space reclamation, eliminating the need for manual compaction operations. This is particularly valuable for applications with high turnover rates.

6. **Memory-for-Performance Trade** · TidesDB uses more memory during read operations (1.7 GB vs 0.3 GB), suggesting it achieves superior read performance through aggressive caching rather than minimal-memory index structures.

7. **Batch Size Sensitivity** · Performance peaks at moderate batch sizes (10-100), with degradation at very large batches (10,000). This suggests optimizations for typical operational patterns rather than extreme edge cases.

### RocksDB's Design Philosophy

RocksDB demonstrates different optimization priorities as a mature LSM-tree implementation:

1. **Memory-Efficient Reads** · The 5.2x lower memory usage during read operations (332 MB vs 1,722 MB) indicates conservative memory allocation strategies that prioritize predictable resource consumption over maximum performance.

2. **Consistent Performance Profile** · More predictable performance across batch sizes and workloads suggests conservative buffer management and well-balanced compaction strategies that avoid performance cliffs.

3. **LSM-Tree Maturity** · As a battle-tested LSM-tree implementation, RocksDB shows well-balanced performance without extreme optimizations in any single dimension, making it a reliable general-purpose choice.

4. **Lazy Garbage Collection** · Retaining 63-66 MB after full deletion indicates that compaction is decoupled from deletion, which can improve delete throughput at the cost of immediate space reclamation.

5. **Large Batch Efficiency** · Better performance with very large batches (10,000 operations) suggests optimizations for bulk loading and high-throughput scenarios where batching is maximized.

6. **Stable Write Amplification** · Consistent write amplification across workloads indicates predictable I/O patterns, which can be valuable for capacity planning and SSD wear management.

## Practical Recommendations

### Choose TidesDB When

1. **General-purpose high-performance workloads** where both reads and writes matter
2. **Storage cost is critical** (TidesDB's 1.2x-6.1x space savings translate to significant cost reductions)
3. **Write-heavy workloads** where TidesDB's 1.5x-3.3x write advantage provides substantial throughput gains
4. **Workloads with access locality** (hot keys, time-series data, recent data access patterns)
5. **Moderate batch sizes** are used (10-1,000 operations per batch)
6. **Immediate space reclamation is required** (delete-intensive applications, data retention policies)
7. **Write amplification must be minimized** (SSD longevity, I/O-constrained environments)
8. **Memory is available** for read caching to maximize performance

### Choose RocksDB When

1. **Memory constraints are strict** (RocksDB uses 5.2x less memory for read operations)
2. **Predictable performance is critical** over maximum throughput
3. **Very large batch sizes are standard** (>5,000 operations per batch)
4. **Mature ecosystem support is required** (extensive tooling, documentation, production validation)
5. **Conservative resource usage is prioritized** over peak performance
6. **Small value storage at massive scale** where RocksDB shows slight space efficiency advantages

## Conclusions

This comprehensive benchmark suite reveals that TidesDB v6.0.0 represents a significant advancement in storage engine design, achieving what has historically been difficult · excellent performance across both read and write operations without major trade-offs.

**TidesDB's Strengths**
- Superior write throughput (1.32x-3.28x faster across workloads)
- Competitive to superior read performance (1.04x-1.76x faster)
- Exceptional space efficiency (1.2x-6.1x smaller databases)
- Lower write amplification (17% reduction on average)
- Immediate space reclamation after deletes
- Excellent performance on skewed access patterns (Zipfian)
- Low-latency operations across all percentiles

**RocksDB's Strengths**
- Superior memory efficiency during reads (5.2x lower)
- More consistent performance across scenarios
- Better behavior with very large batch sizes (>5,000)
- Mature ecosystem and production validation
- Predictable resource consumption
- Slight space advantage with small values at massive scale

**The Bottom Line**

The benchmarks demonstrate that TidesDB has evolved beyond a write-optimized maestro into a truly balanced, high-performance storage engine. It achieves exceptional write throughput while simultaneously delivering competitive-to-superior read performance, a combination that positions it as a compelling choice for modern applications.

TidesDB's most remarkable achievement is delivering 1.76x faster random reads than RocksDB while maintaining 3.28x faster sequential writes and using 1.9x less storage space. 

The space efficiency alone - with databases 1.2x-6.1x smaller than RocksDB for identical data - represents substantial cost savings in cloud storage scenarios. At scale, this could translate to millions of dollars in reduced storage costs while simultaneously improving performance.

Very excite ;)

*Thanks for reading!*
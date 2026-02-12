---
title: "Comparative Analysis of TidesDB v7.0.7 & RocksDB v10.7.5"
description: "Comprehensive performance benchmarks comparing TidesDB v7.0.7 & RocksDB v10.7.5."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-therato-2419014.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-therato-2419014.jpg
---

<div class="article-image">

![Comparative Analysis of TidesDB v7.0.7 & RocksDB v10.7.5](/pexels-therato-2419014.jpg)

</div>

*by Alex Gaetano Padula*

*published on January 1st, 2026*

In this article we will compare the latest patch of TidesDB which is v7.0.7 with the latest patch of RocksDB which is v10.7.5 at the time of this writing.

In this patch I focused on seek and range performance improvements through prudent optimizations. The core focus was speeding up seeks and minimizing resource utilization by implementing iterator source caching. Sources are now cached and only rebuilt when absolutely necessary, such as after compaction. Additional enhancements include combined I/O operations in the block manager that group adjacent reads into single disk operations, and lazy evaluation that defers expensive decoding, decompression, and lookups until values are actually requested. These architectural improvements substantially reduce computational overhead while enabling efficient data reuse across operations, validated through expanded integration tests.

## Test Configuration

All benchmarks were executed with sync mode disabled to measure maximum throughput potential. The test environment used 8 threads across various workloads with 16-byte keys and 100-byte values as the baseline configuration. Tests were conducted on the same hardware to ensure fair comparison.

**We recommend you benchmark your own use case to determine which storage engine is best for your needs!**


**Hardware**
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)
- Ubuntu 23.04 x86_64 6.2.0-39-generic

**Software Versions**
- **TidesDB v7.0.7**
- **RocksDB v10.7.5**
- GCC with -O3 optimization

**Test Configuration**
- **Sync Mode** · DISABLED (maximum performance)
- **Default Batch Size** · 1000 operations
- **Threads** · 8 concurrent threads
- **Key Size** · 16 bytes (unless specified)
- **Value Size** · 100 bytes (unless specified)

You can download the raw benchtool report <a href="/benchmark_results_tdb707_rdb1075.txt" download>here</a>

You can download the raw benchtool report for large values <a href="/large_value_benchmark_results_tdb707_rdb1075.txt" download>here</a>

You can find the **benchtool** source code <a href="https://github.com/tidesdb/benchtool" target="_blank">here</a> and run your own benchmarks!

## Sequential Write Performance

Sequential writes represent the ideal case for LSM-tree architectures. TidesDB achieved 4.90M ops/sec versus RocksDB's 1.82M ops/sec - a **2.69x advantage**.

The performance gap narrows considerably when examining resource utilization. TidesDB consumed 480.8% CPU versus RocksDB's 246.3%, meaning TidesDB achieved roughly 1.35x better throughput per CPU cycle. The real win comes from TidesDB's ability to saturate available CPU resources more effectively. This suggests TidesDB's write path has lower per-operation overhead, allowing it to process more operations before hitting CPU saturation.

Write amplification tells an interesting story: TidesDB at 1.09x versus RocksDB at 1.41x. Lower write amplification typically correlates with better sequential write performance since less background work competes with foreground writes. TidesDB wrote 1205 MB to achieve 10M operations while RocksDB wrote 1562 MB - a 29% reduction in physical I/O.

Space amplification favored TidesDB slightly (0.18x vs 0.21x), with final database sizes of 194 MB versus 238 MB. TidesDB's SSTable format is more compact, and the compaction strategy triggers more aggressively under sequential write patterns.

## Random Write Performance

Random writes are where LSM-trees traditionally struggle compared to sequential patterns. TidesDB maintained 1.60M ops/sec versus RocksDB's 1.35M ops/sec (**1.18x**). The gap narrowed from the sequential case, as expected.

The iteration performance shows a slight regression: TidesDB at 3.67M ops/sec versus RocksDB at 3.83M ops/sec (0.96x). Random write patterns create more fragmentation in TidesDB's data structures, affecting scan efficiency. The database size tells the story: TidesDB produced a 216 MB database versus RocksDB's 116 MB - nearly 2x larger. TidesDB defers file deletion if reads are frequent.

CPU utilization remained high for TidesDB (483.5%) versus RocksDB (261.2%), but the throughput advantage decreased. TidesDB's parallelization strategy shows diminishing returns under random workloads due to increased lock contention on the memtable. The write amplification remained favorable for TidesDB (1.09x vs 1.32x), but the space amplification gap widened (0.19x vs 0.10x).

## Random Read Performance

Point lookups showed TidesDB at 1.72M ops/sec versus RocksDB at 1.50M ops/sec (**1.15x**). The latency numbers are revealing: TidesDB achieved p50 of 4μs and p99 of 11μs, while RocksDB showed p50 of 4μs and p99 of 14μs.

Memory usage patterns diverged. TidesDB peaked at 1853 MB RSS versus RocksDB's 356 MB - a 5.2x difference. TidesDB maintains larger in-memory structures through aggressive iterator and block index caching. The trade-off is deliberate: memory for speed. In memory-constrained environments, this becomes problematic.

The iteration performance advantage went to TidesDB (6.17M ops/sec vs 5.72M ops/sec), suggesting the iterator caching optimizations in v7.0.7 are effective. Database size after compaction favored TidesDB slightly (87 MB vs 86 MB), indicating similar compression efficiency.

## Mixed Workload Performance

The 50/50 read/write mix revealed interesting behavior. TidesDB writes performed at 1.85M ops/sec versus RocksDB's 1.73M ops/sec (**1.07x faster**), but reads showed TidesDB at 1.30M ops/sec versus RocksDB's 1.46M ops/sec (**0.89x slower**). This is counterintuitive given the pure read benchmark results.

The explanation lies in contention. Under mixed workloads, TidesDB's write-optimized architecture creates more lock contention and cache invalidation, degrading read performance. The iteration performance gap widened (TidesDB 2.65M ops/sec vs RocksDB 4.01M ops/sec) - fragmentation under concurrent read/write patterns affects TidesDB more severely.

Resource usage showed TidesDB consuming 572.4% CPU versus RocksDB's 495.8%, with lower memory footprint (1386 MB vs 1633 MB). The database size advantage went to TidesDB (43 MB vs 78 MB), indicating better space efficiency under mixed workloads.

## Zipfian Workload

Zipfian distributions simulate real-world access patterns where a small subset of keys receives most operations. This is where caching strategies matter most.

For write-only Zipfian patterns, TidesDB achieved 2.48M ops/sec versus RocksDB's 1.45M ops/sec (**1.71x**). More impressive is the iteration performance: TidesDB at 3.52M ops/sec versus RocksDB's 0.94M ops/sec (**3.74x**). TidesDB's iterator caching is highly effective when key locality is high.

The mixed Zipfian workload showed even better results: TidesDB writes at 2.38M ops/sec versus RocksDB's 1.37M ops/sec (**1.74x**), and reads at 2.81M ops/sec versus RocksDB's 1.71M ops/sec (**1.65x**). Complete reversal from the uniform random mixed workload - TidesDB's architecture excels when access patterns exhibit locality.

Database size differences were dramatic: TidesDB at 10 MB versus RocksDB at 64 MB. With only ~660K unique keys out of 5M operations, TidesDB's compaction strategy is more effective at reclaiming space from overwrites due to more aggressive merging of overlapping key ranges.

## Delete Performance

Batched deletes (batch=1000) showed TidesDB at 2.62M ops/sec versus RocksDB at 2.80M ops/sec (**0.94x**). This is one area where RocksDB maintains an edge. The write amplification for deletes was 0.19x for TidesDB versus 0.28x for RocksDB, suggesting TidesDB writes fewer tombstone markers.

Iteration after deletion revealed both databases handled tombstones differently. TidesDB maintained 2.87M ops/sec iteration speed while RocksDB reported 0 ops/sec (no keys remaining), indicating RocksDB may have compacted more aggressively during the delete phase.

## Large Value Performance

With 4KB values, TidesDB achieved only 60.9K ops/sec versus RocksDB's 104.6K ops/sec (**0.58x**). The latency distribution shows the problem: TidesDB p95 at 308ms and p99 at 516ms versus RocksDB's p95 at 137ms and p99 at 225ms.

Memory usage exploded for TidesDB (4146 MB vs 2723 MB), and CPU utilization dropped to 188% versus RocksDB's 189% - both systems became I/O bound. The write amplification remained favorable (1.07x vs 1.25x), but the throughput penalty is severe.

TidesDB's internal buffering and memory management are not optimized for large values under high thread counts. The memtable flush threshold and buffer pool sizing need tuning for large value workloads. The iteration performance advantage (906K ops/sec vs 392K ops/sec, **2.31x faster**) is impressive but doesn't compensate for the write performance regression.

## Small Value Performance

With 64-byte values and 50M operations, TidesDB achieved 1.09M ops/sec versus RocksDB's 1.03M ops/sec (**1.06x faster**). The performance gap is modest, but resource usage tells a different story.

Memory consumption was nearly identical (11.8 GB vs 11.7 GB), but disk writes favored TidesDB (4462 MB vs 5785 MB). Write amplification was 1.17x versus 1.52x - a 30% reduction. However, space amplification was worse for TidesDB (0.26x vs 0.11x), with final database sizes of 986 MB versus 437 MB.

TidesDB defers file removal if reads are frequent and reference counts are high.

## Seek Performance

Random seek operations showed TidesDB at 1.91M ops/sec versus RocksDB's 787K ops/sec (**2.43x**). Latency: TidesDB p50 of 3μs and p99 of 9μs versus RocksDB's p50 of 9μs and p99 of 23μs.

Sequential seek performance was even more dramatic: TidesDB at 4.62M ops/sec versus RocksDB's 2.76M ops/sec (**1.67x**). Latency advantage: TidesDB p50 of 1μs versus RocksDB's 2μs, with p99 of 3μs versus 6μs.

Zipfian seek patterns showed TidesDB at 3.22M ops/sec versus RocksDB's 633K ops/sec (**5.09x**) - the largest performance gap in the entire benchmark suite. When keys exhibit locality, TidesDB's cached iterators avoid expensive reconstruction.

CPU utilization during seeks was high for TidesDB (575-668%) versus RocksDB (450-716%), but the throughput advantage more than compensates. Memory usage remained reasonable for TidesDB (131-912 MB) versus RocksDB (180-236 MB).

## Range Query Performance

Range scans of 100 keys showed TidesDB at 362K ops/sec versus RocksDB's 302K ops/sec (**1.20x faster**). The latency distribution favored TidesDB: p50 of 15μs versus 22μs, with p99 of 64μs versus 62μs. The results are close, suggesting both engines handle moderate-size range queries efficiently.

Larger range scans (1000 keys) showed TidesDB at 49.8K ops/sec versus RocksDB's 43.0K ops/sec (**1.16x faster**). The latency gap widened: TidesDB p50 of 138μs versus RocksDB's 159μs, with p99 of 350μs versus 473μs.

Sequential range scans (100 keys) showed TidesDB at 426K ops/sec versus RocksDB's 422K ops/sec, essentially identical performance. This suggests that when data is naturally ordered, both engines achieve similar scan efficiency.

CPU utilization during range queries was consistently higher for TidesDB (658-763%) versus RocksDB (702-776%), with the gap narrowing as range size increased. This indicates both engines become increasingly CPU-bound as they process more keys per operation.

## Write Amplification Analysis

Across all workloads, TidesDB consistently achieved lower write amplification:
- Sequential writes · 1.09x vs 1.41x
- Random writes · 1.09x vs 1.32x
- Mixed workload · 1.11x vs 1.25x
- Large values · 1.07x vs 1.25x

The average advantage is approximately 20-25%. This translates directly to reduced SSD wear and longer device lifetime in production deployments. However, this comes at the cost of higher space amplification in some scenarios, suggesting TidesDB defers compaction more aggressively.

## Space Amplification

Space amplification results were mixed:
- Sequential writes · 0.18x vs 0.21x (TidesDB better)
- Random writes · 0.19x vs 0.10x (RocksDB better)
- Mixed workload · 0.08x vs 0.14x (TidesDB better)
- Small values · 0.26x vs 0.11x (RocksDB better)

## Batch Size Sensitivity

Batch size dramatically affects performance. For TidesDB:
- Batch=1 · 975K ops/sec (7.5μs latency)
- Batch=10 · 1.95M ops/sec (33.6μs latency)
- Batch=100 · 1.85M ops/sec (303μs latency)
- Batch=1000 · 1.65M ops/sec (3440μs latency)
- Batch=10000 · 912K ops/sec (57.8ms latency)

The optimal batch size is 10-100 for TidesDB. Beyond that, latency increases super-linearly while throughput degrades due to memtable lock contention and increased flush frequency at very large batch sizes.

RocksDB showed different characteristics:
- Batch=1 · 780K ops/sec
- Batch=10 · 1.30M ops/sec
- Batch=100 · 1.63M ops/sec
- Batch=1000 · 1.39M ops/sec
- Batch=10000 · 1.25M ops/sec

RocksDB's performance peaked at batch=100 and degraded less severely at larger batch sizes.

## CPU Efficiency

TidesDB consistently utilized more CPU resources (400-700%) versus RocksDB (200-400%). The higher utilization enables better throughput but raises questions about efficiency per core.

Calculating operations per CPU-second (total ops / [user time + system time]):
- Sequential writes · TidesDB 289K ops/CPU-sec vs RocksDB 98K ops/CPU-sec
- Random writes · TidesDB 230K ops/CPU-sec vs RocksDB 382K ops/CPU-sec
- Random reads · TidesDB 221K ops/CPU-sec vs RocksDB 179K ops/CPU-sec

For sequential writes and reads, TidesDB achieves better per-CPU efficiency. For random writes, RocksDB achieves better per-CPU efficiency despite lower absolute throughput. TidesDB's sequential code paths are well-optimized with minimal locking, while random write patterns incur higher per-operation overhead from skiplist insertions and memtable management.

## Memory Footprint

Memory usage patterns diverged:
- Random reads · TidesDB 1853 MB vs RocksDB 356 MB (5.2x)
- Random writes · TidesDB 2676 MB vs RocksDB 2938 MB (0.91x)
- Sequential writes · TidesDB 2415 MB vs RocksDB 2692 MB (0.90x)

TidesDB's read-heavy workloads consume more memory due to aggressive caching of iterators and block indices. Write-heavy workloads show comparable or lower memory usage. The iterator caching optimization deliberately trades memory for speed; a reasonable trade-off in modern servers but problematic in constrained environments.

## Iteration Performance

Full iteration throughput consistently favored TidesDB:
- Sequential writes · 6.74M ops/sec vs 4.95M ops/sec (1.36x)
- Random writes · 3.67M ops/sec vs 3.83M ops/sec (0.96x)
- Random reads · 6.17M ops/sec vs 5.72M ops/sec (1.08x)
- Zipfian writes · 3.52M ops/sec vs 0.94M ops/sec (3.74x)

The Zipfian result is particularly striking. When iterating over a small key space with high update frequency, TidesDB's cached iterators provide massive advantages by avoiding expensive iterator reconstruction. This validates the v7.0.7 optimization strategy of caching iterator sources and only rebuilding after compaction.

## 8KB Value Value Performance

The main benchmark suite tested 4KB values with 8 threads and showed TidesDB struggling with large value writes. To isolate whether this was a large-value issue or a high-concurrency issue, a dedicated test was run with 8KB values and 2 threads. The results show TidesDB excels with large values when thread count is moderate.

### Write Performance

**Sequential writes** showed TidesDB at 110.9K ops/sec versus RocksDB's 89.8K ops/sec - a **1.24x advantage**. This is a dramatic improvement over the 4KB results where TidesDB was 0.58x slower. The latency distribution confirms the improvement: TidesDB p50 of 8μs and p99 of 33μs versus RocksDB's p50 of 9μs and p99 of 42μs.

**Random writes** maintained similar performance: TidesDB at 108.3K ops/sec versus RocksDB's 92.0K ops/sec (**1.18x faster**). The consistency between sequential and random patterns suggests TidesDB's large value handling improves when thread count is reduced from 8 to 2.

This performance reversal is significant. The 4KB benchmark used 8 threads and showed severe degradation. The 8KB benchmark with 2 threads shows TidesDB winning. This is potentially due to **lock contention or memory bandwidth saturation** under high thread counts with large values. With fewer threads, TidesDB's architecture handles large values efficiently.

Write amplification remained favorable: TidesDB at 1.08-1.09x versus RocksDB's 1.10-1.12x. Space amplification was nearly identical (0.04x vs 0.05x), with TidesDB producing slightly smaller databases (31-32 MB vs 37-40 MB).

### Read Performance

The read performance results are striking and validate the earlier statement that TidesDB is "faster in the end with large value reads."

**Sequential reads** showed TidesDB at 762.5K ops/sec versus RocksDB's 336.9K ops/sec - a **2.26x advantage**. The latency numbers are exceptional: TidesDB p50 of 2μs and p99 of 5μs versus RocksDB's p50 of 5μs and p99 of 17μs. This is a 2.5x latency improvement at the median and 3.4x at p99.

**Random reads** maintained the advantage: TidesDB at 619.0K ops/sec versus RocksDB's 301.9K ops/sec (**2.05x faster**). Latency remained impressive: TidesDB p50 of 3μs versus RocksDB's 5μs, with p99 of 8μs versus 22μs.

Memory usage during reads was remarkably low for TidesDB: only 25 MB RSS versus RocksDB's 145-156 MB - a **6x memory advantage**. This contradicts the small value benchmark where TidesDB consumed 5x more memory. With large values, TidesDB's memory efficiency shines.

CPU utilization was also lower for TidesDB (144-150%) versus RocksDB (142-221%), suggesting better efficiency per operation. The combination of 2x throughput with lower memory and comparable CPU usage indicates TidesDB's read path is genuinely optimized for large values.

### Seek Performance

**Sequential seek** showed RocksDB at 405.1K ops/sec versus TidesDB's 283.5K ops/sec (**0.70x slower**). This is one area where RocksDB maintained an advantage with large values. The latency distribution shows RocksDB p50 of 4μs versus TidesDB's 6μs.

**Random seek** showed TidesDB at 245.0K ops/sec versus RocksDB's 220.0K ops/sec (**1.11x faster**). The latency was close: TidesDB p50 of 7μs versus RocksDB's 8μs, with p99 of 20μs versus 29μs.

The sequential seek regression is notable given TidesDB's dominance in small value seeks. This suggests the iterator caching optimization may not be as effective when values are large and sequential access patterns dominate. The cached iterators provide less benefit when the bottleneck shifts from index lookups to value retrieval.

### Range Query Performance

Range scans of 100 keys revealed unexpected behavior. **Sequential range queries** showed TidesDB at 12.4K ops/sec versus RocksDB's 40.7K ops/sec (**0.30x slower**). This is a regression.

The latency distribution explains the problem: TidesDB p50 of 154μs versus RocksDB's 45μs - a **3.4x latency disadvantage**. The p99 gap widened further: 319μs versus 120μs.

**Random range queries** showed even worse results: TidesDB at 12.2K ops/sec versus RocksDB's 6.2K ops/sec (**1.97x faster**), but both engines performed poorly. TidesDB's latency was p50 of 154μs versus RocksDB's 294μs, showing TidesDB actually had better per-operation latency despite similar throughput.

The CPU utilization during range queries was extreme: TidesDB at 197-198% versus RocksDB at 188-195%. Both engines became CPU-bound, but TidesDB's higher CPU usage with lower throughput on sequential ranges suggests inefficiency in the range scan implementation for large values.

### Iteration Performance

Full iteration throughput favored TidesDB:
- Sequential · 677K ops/sec vs 347K ops/sec (1.95x)
- Random · 643K ops/sec vs 343K ops/sec (1.87x)

This validates that TidesDB's iterator implementation is efficient for large values when performing full scans, even if range queries with limits show regressions.

### Large Value Buffering

Large values require larger internal buffers such as larger memtables, cache sizes and so forth. With 8 threads, buffer allocation and management overhead may dominate. So have an eye.

The read performance advantage suggests TidesDB's read path is better optimized for large sequential I/O patterns. The 2x throughput with 6x less memory indicates efficient streaming of large values without excessive buffering.

### Summary

The v7.0.7 iterator caching optimization successfully improved seek and range performance, delivering on its design goals. The trade-offs are reasonable for most server deployments but require careful evaluation based on specific workload characteristics and resource constraints.

---

*Thanks for reading!*
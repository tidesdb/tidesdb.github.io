---
title: "TidesDB v7.3.1 vs RocksDB v10.9.1 Performance Benchmark"
description: "In-depth performance benchmark comparing TidesDB v7.3.1 and RocksDB v10.9.1 across real-world workloads, measuring throughput, latency, and efficiency."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-elia-clerici-282848-912107.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-elia-clerici-282848-912107.jpg
---

<div class="article-image">

![TidesDB v7.3.1 vs RocksDB v10.9.1 Performance Benchmark](/pexels-elia-clerici-282848-912107.jpg)

</div>

*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on January 21st, 2026*

The latest <a href="https://github.com/tidesdb/tidesdb/releases/tag/v7.3.1">patch</a> of TidesDB (v7.3.1) improves latency consistency and overall performance across several core subsystems, with measurable gains across a range of workloads compared to earlier releases.

You can find the complete benchmark report below in 2 formats:
- [CSV](/tidesdb-v7-3-1-rocksdb-v10-9-1.csv)
- [Text](/tidesdb-v7-3-1-rocksdb-v10-9-1.txt)

You can find the source for the benchtool <a href="https://github.com/tidesdb/benchtool">here</a>.

Test environment: 

- Intel i7-11700K (16 cores), 46GB RAM, Linux 6.2.0, sync disabled, Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)

## Engine Comparison

<img src="/graphs/tidesdb-v7-3-1-rocksdb-v10-9-1_engine_comparison.png" alt="Engine Comparison" width="100%">

This chart shows the average throughput (operations per second) for each operation type. TidesDB outperforms RocksDB across all operations, with the most significant gains in PUT and SEEK operations.

## Throughput Overview

<img src="/graphs/tidesdb-v7-3-1-rocksdb-v10-9-1_throughput_overview.png" alt="Throughput Overview" width="100%">

A detailed breakdown of throughput across individual test configurations. Each test varies parameters like batch size, key pattern, and value size. TidesDB consistently achieves higher throughput across the majority of test scenarios.

## Operation Mix

<img src="/graphs/tidesdb-v7-3-1-rocksdb-v10-9-1_operation_mix.png" alt="Operation Mix" width="100%">

Aggregate throughput by operation type. TidesDB shows strong performance in DELETE, GET, PUT, RANGE, and SEEK operations.

## Latency Overview

<img src="/graphs/tidesdb-v7-3-1-rocksdb-v10-9-1_latency_overview.png" alt="Latency Overview" width="100%">

Average latency (in microseconds) for each operation type. Lower is better. TidesDB demonstrates lower average latency across most operations, particularly in PUT and SEEK workloads.

## Latency Percentiles

<img src="/graphs/tidesdb-v7-3-1-rocksdb-v10-9-1_latency_percentiles.png" alt="Latency Percentiles" width="100%">

Latency distribution showing min, p50, p95, p99, and max latencies. TidesDB shows tighter latency distributions with lower tail latencies, indicating more predictable performance.

## Latency Variability (CV%)

<img src="/graphs/tidesdb-v7-3-1-rocksdb-v10-9-1_variability_cv.png" alt="Latency Variability" width="100%">

Coefficient of Variation (CV%) measures latency consistency. Lower CV% means more consistent performance. Note that average CV values in this benchmark are higher than typical because this suite aggregates results across many different test configurations (batch sizes from 1 to 10,000, different key patterns, value sizes, etc.). The high throughput achieved by TidesDB, especially at smaller batch sizes, can contribute to higher relative variance. RocksDB shows notably higher CV on PUT operations due to background compaction causing latency spikes.

## Latency Standard Deviation

<img src="/graphs/tidesdb-v7-3-1-rocksdb-v10-9-1_latency_stddev.png" alt="Latency StdDev" width="100%">

Standard deviation of latency in microseconds. Lower values indicate more consistent response times. TidesDB maintains lower standard deviation in most workloads.

## Workload Comparison

<img src="/graphs/tidesdb-v7-3-1-rocksdb-v10-9-1_workload_comparison.png" alt="Workload Comparison" width="100%">

Performance comparison across different workload types: delete, mixed, range, read, seek, and write. TidesDB leads in all workload categories.

## Key Pattern Comparison

<img src="/graphs/tidesdb-v7-3-1-rocksdb-v10-9-1_pattern_put.png" alt="PUT Pattern Comparison" width="100%">

PUT throughput across different key patterns (random, sequential, zipfian). TidesDB shows strong performance across all access patterns.

<img src="/graphs/tidesdb-v7-3-1-rocksdb-v10-9-1_pattern_get.png" alt="GET Pattern Comparison" width="100%">

GET throughput by key pattern. Both engines perform similarly on random reads, with TidesDB having a slight edge.

<img src="/graphs/tidesdb-v7-3-1-rocksdb-v10-9-1_pattern_seek.png" alt="SEEK Pattern Comparison" width="100%">

SEEK throughput by key pattern. TidesDB significantly outperforms RocksDB, especially on sequential and zipfian patterns.

## Batch Size Impact

<img src="/graphs/tidesdb-v7-3-1-rocksdb-v10-9-1_sweep_put_batch_size.png" alt="PUT Batch Size Sweep" width="100%">

How batch size affects PUT throughput. Both engines benefit from batching, with TidesDB maintaining higher throughput across all batch sizes.

<img src="/graphs/tidesdb-v7-3-1-rocksdb-v10-9-1_sweep_delete_batch_size.png" alt="DELETE Batch Size Sweep" width="100%">

DELETE throughput vs batch size. Performance scales similarly for both engines with increasing batch sizes.

## Value Size Impact

<img src="/graphs/tidesdb-v7-3-1-rocksdb-v10-9-1_value_size_put.png" alt="Value Size Impact" width="100%">

How value size affects PUT throughput. Larger values reduce throughput for both engines, but TidesDB maintains a performance advantage.

## Range Query Performance

<img src="/graphs/tidesdb-v7-3-1-rocksdb-v10-9-1_sweep_range_range_size.png" alt="Range Size Sweep" width="100%">

RANGE query throughput vs range size. Both engines show similar scaling behavior as range size increases.

## Resource Usage

<img src="/graphs/tidesdb-v7-3-1-rocksdb-v10-9-1_resource_overview.png" alt="Resource Overview" width="100%">

Resource consumption comparison including memory usage, disk I/O, and CPU utilization across different operations.

## Write Amplification

<img src="/graphs/tidesdb-v7-3-1-rocksdb-v10-9-1_amplification.png" alt="Amplification Factors" width="100%">

Write, read, and space amplification factors. Lower amplification means more efficient use of storage I/O. TidesDB shows competitive amplification characteristics.

## Summary

TidesDB 7.3.1 outperforms RocksDB 10.9.1 across:

| Metric | TidesDB | RocksDB | Difference |
|--------|---------|---------|------------|
| Sequential PUT | 6.5M ops/s | 2.4M ops/s | **2.7x faster** |
| Random PUT | 2.6M ops/s | 1.8M ops/s | **1.4x faster** |
| Random GET | 2.6M ops/s | 1.4M ops/s | **1.9x faster** |
| Random SEEK | 2.9M ops/s | 1.1M ops/s | **2.6x faster** |
| PUT p99 latency | 2,149 μs | 5,946 μs | **2.8x lower** |
| PUT max latency | 4,218 μs | 181,680 μs | **43x lower** |
| PUT Latency CV | 109% | 265% | **2.4x more consistent** |
| Write amplification | 1.08x | 1.44x | **25% less I/O** |
| Database size | 111 MB | 207 MB | **47% smaller** |

The key takeaways are:

1. TidesDB delivers 1.4x to 2.7x higher throughput depending on workload.

2. RocksDB shows occasional latency spikes up to 181ms (likely from compaction). TidesDB's worst case is 4ms.

3. TidesDB shows lower CV on PUT operations (109% vs 265%), indicating more predictable write performance.

4. TidesDB show's consistently lower write amplification and smaller on-disk footprint.


*Thanks for reading!*

---

**Links**
- GitHub · https://github.com/tidesdb/tidesdb
- Design deep-dive · https://tidesdb.com/getting-started/how-does-tidesdb-work

Join the TidesDB Discord for more updates and discussions at https://discord.gg/tWEmjR66cy

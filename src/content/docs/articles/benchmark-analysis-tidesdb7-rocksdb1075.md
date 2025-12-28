---
title: "TidesDB 7.0.0 vs RocksDB 10.7.5: A Detailed Performance Analysis"
description: "A comprehensive examination of benchmark results comparing TidesDB 7.0.0 against RocksDB 10.7.5 across diverse workloads, with architectural insights and performance characteristics."
---

<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>

*by Alex Gaetano Padula*

*published on December 27th, 2025*

## Introduction

I've spent considerable time benchmarking TidesDB 7.0.0 against RocksDB 10.7.5, and the results reveal interesting performance characteristics that merit detailed analysis. This isn't a simple "X is faster than Y" comparison - the reality is more nuanced, with each engine showing distinct strengths depending on workload patterns, access patterns, and data characteristics.

The benchmarks cover 12 distinct test scenarios spanning sequential and random access patterns, various batch sizes, hot-key workloads, large and small values, and range queries. I'll walk through the results methodically, examining not just throughput numbers but also latency distributions, resource consumption, and amplification factors.

## Test Environment

**Hardware**
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)
- Ubuntu 23.04 x86_64 6.2.0-39-generic

**Software Versions**
- **TidesDB v7.0.0**
- **RocksDB v10.7.5**
- GCC with -O3 optimization

**Test Configuration**
- **Sync Mode** · DISABLED (maximum performance)
- **Threads** · 8 concurrent threads
- **Key Size** · 16 bytes (unless specified)
- **Value Size** · 100 bytes (unless specified)
- **Batch Size** · 1000 operations (unless specified)

All tests run with fsync disabled to measure pure engine performance without I/O subsystem interference. This is standard practice for understanding engine characteristics, though production deployments should carefully consider durability requirements.

## 1. Sequential Write Performance

Sequential writes represent the best-case scenario for LSM-based storage engines. TidesDB achieved **6.21M ops/sec** versus RocksDB's **2.36M ops/sec** - a **2.63x advantage**. This is substantial.

<canvas id="seqWriteChart" width="400" height="200"></canvas>
<script>
new Chart(document.getElementById('seqWriteChart'), {
  type: 'bar',
  data: {
    labels: ['Sequential Write', 'Iteration'],
    datasets: [{
      label: 'TidesDB (ops/sec)',
      data: [6205918, 6246221],
      backgroundColor: 'rgba(59, 130, 246, 0.8)'
    }, {
      label: 'RocksDB (ops/sec)',
      data: [2355460, 4980679],
      backgroundColor: 'rgba(239, 68, 68, 0.8)'
    }]
  },
  options: {
    responsive: true,
    scales: { y: { beginAtZero: true, title: { display: true, text: 'Operations/sec' }}}
  }
});
</script>

**Latency Analysis (per batch of 1000 operations)**

- TidesDB p50: 1,064 μs, p99: 2,352 μs
- RocksDB: Latency data not captured in baseline run


The iteration throughput (full scan) shows TidesDB at **6.25M ops/sec** versus RocksDB's **4.98M ops/sec** (1.25x faster). Sequential iteration is typically I/O bound, so the smaller gap here versus write throughput suggests TidesDB's advantage comes partly from more efficient write path batching and lower write amplification producing fewer SSTables to scan.


**Resource Consumption**

- Peak RSS: TidesDB 2,428 MB vs RocksDB 2,417 MB (essentially identical)
- Disk writes: TidesDB 1,204 MB vs RocksDB 1,623 MB
- Database size: TidesDB 123 MB vs RocksDB 203 MB

TidesDB wrote **26% less data** to disk and produced a **39% smaller database**. The write amplification tells the story: TidesDB at 1.09x versus RocksDB's 1.47x. For 10M operations totaling ~1.1GB of logical data, TidesDB wrote 1.2GB while RocksDB wrote 1.6GB.


## 2. Random Write Performance

Random writes stress the write path differently. Here TidesDB achieved **1.66M ops/sec** versus RocksDB's **1.35M ops/sec** - a **1.23x advantage**, much narrower than sequential writes.

<canvas id="randWriteChart" width="400" height="200"></canvas>
<script>
new Chart(document.getElementById('randWriteChart'), {
  type: 'bar',
  data: {
    labels: ['Random Write', 'Iteration'],
    datasets: [{
      label: 'TidesDB (ops/sec)',
      data: [1660333, 3730967],
      backgroundColor: 'rgba(59, 130, 246, 0.8)'
    }, {
      label: 'RocksDB (ops/sec)',
      data: [1352985, 3970276],
      backgroundColor: 'rgba(239, 68, 68, 0.8)'
    }]
  },
  options: {
    responsive: true,
    scales: { y: { beginAtZero: true, title: { display: true, text: 'Operations/sec' }}}
  }
});
</script>

**Latency Distribution (per batch of 1000 operations)**

- TidesDB: p50 2,937 μs, p95 4,541 μs, p99 5,363 μs, max 3.7 seconds
- RocksDB: Latency data not captured in baseline run

The max latency of 3.7 seconds indicates occasional stalls, likely from compaction or memory pressure. The iteration performance flipped: RocksDB was **6% faster** at 3.97M ops/sec versus TidesDB's 3.73M ops/sec. This suggests RocksDB's more aggressive compaction produces better-organized SSTables for random data, while TidesDB defers compaction to maximize write throughput.

**Space Amplification Reversal**

TidesDB's database size: 238 MB versus RocksDB's 118 MB. TidesDB used **2x more space** for random data. This is the flip side of lower write amplification - TidesDB appears to defer compaction more aggressively, trading space for write throughput.

## 3. Random Read Performance

Point lookups show TidesDB at **1.22M ops/sec** versus RocksDB's **1.08M ops/sec** - a **1.13x advantage**.

<canvas id="randReadChart" width="400" height="200"></canvas>
<script>
new Chart(document.getElementById('randReadChart'), {
  type: 'bar',
  data: {
    labels: ['Random Read'],
    datasets: [{
      label: 'TidesDB (ops/sec)',
      data: [1215655],
      backgroundColor: 'rgba(59, 130, 246, 0.8)'
    }, {
      label: 'RocksDB (ops/sec)',
      data: [1076898],
      backgroundColor: 'rgba(239, 68, 68, 0.8)'
    }]
  },
  options: {
    responsive: true,
    scales: { y: { beginAtZero: true, title: { display: true, text: 'Operations/sec' }}}
  }
});
</script>

**Latency Characteristics (per operation)**

- TidesDB: p50 5 μs, p95 10 μs, p99 14 μs, avg 5.82 μs
- RocksDB: p50 7 μs, p95 11 μs, p99 17 μs, avg 6.97 μs

TidesDB shows **consistently lower latencies** across all percentiles. The 2 μs difference at p50 (5 μs vs 7 μs) represents a **29% improvement** that compounds at scale. This is directly attributable to TidesDB's in-memory bloom filters and metadata - RocksDB must perform I/O to check bloom filters on disk.

**Memory Efficiency**

TidesDB's peak RSS during reads ⋅ 1,849 MB versus RocksDB's 376 MB. TidesDB used **4.9x more memory**. This is significant and architectural - TidesDB keeps metadata and bloom filters entirely in memory for all SSTables, enabling the 5 μs median lookup latencies we see. Additionally, TidesDB's lockless design uses reference counting with deferred cleanup, which maintains additional in-memory state to avoid lock contention. This is a deliberate tradeoff: memory for performance. The 1.5 GB difference translates to roughly 150 bytes per key for 10M keys - reasonable for in-memory indexes and bloom filters.

## 4. Mixed Workload (50/50 Read/Write)

The mixed workload (5M operations, 50% reads, 50% writes) shows:
- Writes ⋅ TidesDB 1.81M ops/sec vs RocksDB 1.60M ops/sec (**1.13x faster**)
- Reads ⋅ TidesDB 1.41M ops/sec vs RocksDB 1.27M ops/sec (**1.11x faster**)

<canvas id="mixedChart" width="400" height="200"></canvas>
<script>
new Chart(document.getElementById('mixedChart'), {
  type: 'bar',
  data: {
    labels: ['PUT', 'GET'],
    datasets: [{
      label: 'TidesDB (ops/sec)',
      data: [1807477, 1412719],
      backgroundColor: 'rgba(59, 130, 246, 0.8)'
    }, {
      label: 'RocksDB (ops/sec)',
      data: [1600257, 1271393],
      backgroundColor: 'rgba(239, 68, 68, 0.8)'
    }]
  },
  options: {
    responsive: true,
    scales: { y: { beginAtZero: true, title: { display: true, text: 'Operations/sec' }}}
  }
});
</script>

TidesDB maintained advantages in both operations. However, iteration performance shows RocksDB at 4.25M ops/sec versus TidesDB's 2.50M ops/sec ⋅ **1.7x faster**. This reinforces the pattern: TidesDB optimizes for write throughput and point queries by deferring compaction, while RocksDB's more aggressive compaction produces better-organized SSTables for sequential scans. The tradeoff is explicit: TidesDB accepts slower full scans in exchange for higher write throughput and lower write amplification.

**Resource Efficiency**
- Database size ⋅ TidesDB 43 MB vs RocksDB 82 MB
- Disk writes ⋅ TidesDB 616 MB vs RocksDB 690 MB
- Write amplification ⋅ TidesDB 1.11x vs RocksDB 1.25x

## 5. Hot Key Workload (Zipfian Distribution)

Zipfian distributions model real-world access patterns where a small set of keys receives most traffic. This is where things get interesting.

**Write-Only Zipfian**

TidesDB ⋅ **2.38M ops/sec** vs RocksDB ⋅ **1.46M ops/sec** (**1.63x faster**)

**Mixed Zipfian (50/50)**

- TidesDB writes ⋅ 2.48M ops/sec vs RocksDB ⋅ 1.42M ops/sec (**1.75x faster**)
- TidesDB reads ⋅ 2.79M ops/sec vs RocksDB ⋅ 1.55M ops/sec (**1.80x faster**)

<canvas id="zipfianChart" width="400" height="200"></canvas>
<script>
new Chart(document.getElementById('zipfianChart'), {
  type: 'bar',
  data: {
    labels: ['Zipfian Write', 'Zipfian Mixed PUT', 'Zipfian Mixed GET'],
    datasets: [{
      label: 'TidesDB (ops/sec)',
      data: [2381071, 2481314, 2792994],
      backgroundColor: 'rgba(59, 130, 246, 0.8)'
    }, {
      label: 'RocksDB (ops/sec)',
      data: [1462433, 1419570, 1551860],
      backgroundColor: 'rgba(239, 68, 68, 0.8)'
    }]
  },
  options: {
    responsive: true,
    scales: { y: { beginAtZero: true, title: { display: true, text: 'Operations/sec' }}}
  }
});
</script>

**Latency for Hot Keys (Mixed Zipfian)**

- TidesDB GET ⋅ p50 2 μs, p95 4 μs, p99 5 μs, avg 2.18 μs (per operation)
- TidesDB PUT ⋅ p50 2,802 μs, p95 3,745 μs, p99 4,477 μs (per batch of 1000)
- RocksDB ⋅ Latency data not captured in baseline run

The **2 μs median read latency** for hot keys is exceptional - 2.5x faster than the 5 μs seen for uniform random reads. This suggests TidesDB's in-memory structures combined with CPU caching are highly effective for skewed access patterns where hot keys remain in L1/L2 cache.


**Space Efficiency**
Database size: TidesDB 10.2 MB vs RocksDB 57.6 MB for the mixed workload. With only ~660K unique keys, TidesDB's database is **5.6x smaller**. The space amplification factors tell the story: TidesDB 0.02x vs RocksDB 0.10x.

## 6. Delete Performance

Deletes in LSM trees are typically implemented as tombstones, making them similar to writes. TidesDB achieved **2.96M ops/sec** versus RocksDB's **2.80M ops/sec** (**1.05x faster**) with batch size 1000.

<canvas id="deleteChart" width="400" height="200"></canvas>
<script>
new Chart(document.getElementById('deleteChart'), {
  type: 'bar',
  data: {
    labels: ['Batch=1', 'Batch=100', 'Batch=1000'],
    datasets: [{
      label: 'TidesDB DELETE (ops/sec)',
      data: [996481, 3378940, 2957270],
      backgroundColor: 'rgba(59, 130, 246, 0.8)'
    }, {
      label: 'RocksDB DELETE (ops/sec)',
      data: [904118, 2395746, 2804885],
      backgroundColor: 'rgba(239, 68, 68, 0.8)'
    }]
  },
  options: {
    responsive: true,
    scales: { y: { beginAtZero: true, title: { display: true, text: 'Operations/sec' }}}
  }
});
</script>

**Write Amplification for Deletes**
- TidesDB: 0.19x (batch=1000)
- RocksDB: 0.28x (batch=1000)

Both engines show sub-1.0 write amplification because deletes only write tombstones, not actual data. TidesDB's lower amplification suggests more efficient tombstone encoding or batching.

## 7. Value Size Impact

**Large Values (256B key, 4KB value, 1M ops)**

RocksDB ⋅ **107,883 ops/sec** vs TidesDB ⋅ **96,519 ops/sec** (**RocksDB 1.12x faster**)


This appears to be a RocksDB win on write throughput, but the full picture is more nuanced.

<canvas id="valueSizeChart" width="400" height="200"></canvas>
<script>
new Chart(document.getElementById('valueSizeChart'), {
  type: 'bar',
  data: {
    labels: ['Large Values (4KB) Write', 'Large Values (4KB) Iteration', 'Small Values (64B)'],
    datasets: [{
      label: 'TidesDB (ops/sec)',
      data: [96519, 834895, 875312],
      backgroundColor: 'rgba(59, 130, 246, 0.8)'
    }, {
      label: 'RocksDB (ops/sec)',
      data: [107883, 401126, 1011090],
      backgroundColor: 'rgba(239, 68, 68, 0.8)'
    }]
  },
  options: {
    responsive: true,
    scales: { y: { beginAtZero: true, title: { display: true, text: 'Operations/sec' }}}
  }
});
</script>

**The Key-Value Separation Tradeoff**

TidesDB uses key-value separation (vLog) for large values, which means each write operation involves:
1. Writing the key + pointer to the LSM tree
2. Writing the actual 4KB value to the append-only vLog

This dual-write path explains the higher system CPU time (12.9s vs 4.1s) and memory usage (3,809 MB vs 1,391 MB) - TidesDB is managing two separate write buffers simultaneously. The immediate write throughput is 11% slower, but the architectural benefits become clear in other metrics:

- **Iteration ⋅ 2.08x faster** (834K vs 401K ops/sec) - The LSM tree only contains keys+pointers, not full 4KB values

- **Write amplification ⋅ 1.07x vs 1.21x** - Better long-term efficiency

- **Database size ⋅ 302 MB vs 347 MB** - More compact despite separation overhead


This is the classic WiscKey tradeoff: accept slightly slower writes for dramatically faster scans and better write amplification. For values >8KB, the vLog benefits would be even more pronounced.

**Memory Consumption**

The 2.7x higher memory (3,809 MB vs 1,391 MB) comes from buffering both LSM writes and vLog writes, plus the reference-counted structures for lockless operation. This is a genuine cost of the architecture.

**Small Values (16B key, 64B value, 50M ops)**

RocksDB ⋅ **1.01M ops/sec** vs TidesDB ⋅ **875K ops/sec** (**RocksDB 1.15x faster**)

At 50M operations, RocksDB maintained better throughput. However, TidesDB's write amplification was 1.17x versus RocksDB's 1.52x - **23% lower**. TidesDB wrote 4.5GB versus RocksDB's 5.8GB. The space amplification difference is also notable: TidesDB used 2.2x more disk space (1,016 MB vs 453 MB), showing the deferred compaction strategy's cost at scale.

## 8. Batch Size Sensitivity

Batch size dramatically affects performance. Here's TidesDB's throughput across batch sizes:

<canvas id="batchSizeChart" width="400" height="200"></canvas>
<script>
new Chart(document.getElementById('batchSizeChart'), {
  type: 'line',
  data: {
    labels: ['1', '10', '100', '1000', '10000'],
    datasets: [{
      label: 'TidesDB (ops/sec)',
      data: [null, 1907314, 1816716, 1602457, 851792],
      borderColor: 'rgba(59, 130, 246, 1)',
      backgroundColor: 'rgba(59, 130, 246, 0.1)',
      tension: 0.1
    }, {
      label: 'RocksDB (ops/sec)',
      data: [null, 1394194, 1324289, 1242505, 1160367],
      borderColor: 'rgba(239, 68, 68, 1)',
      backgroundColor: 'rgba(239, 68, 68, 0.1)',
      tension: 0.1
    }]
  },
  options: {
    responsive: true,
    scales: { 
      y: { beginAtZero: true, title: { display: true, text: 'Operations/sec' }},
      x: { title: { display: true, text: 'Batch Size' }}
    }
  }
});
</script>

**Key Observations**
- Optimal batch size for TidesDB ⋅ **10** (1.91M ops/sec)
- Optimal batch size for RocksDB ⋅ **10** (1.39M ops/sec)
- At batch=10,000 ⋅ RocksDB maintains 1.16M ops/sec while TidesDB drops to 852K ops/sec (**36% slower**)

TidesDB's performance degrades more sharply with very large batches. The latency at batch=10,000 shows why: p50 of 53ms versus 4.4ms at batch=100 - a **12x increase**. Large batches appear to create head-of-line blocking in TidesDB's write path, possibly from the deferred cleanup mechanism accumulating too much work. RocksDB's latency also increases but more gradually (from ~4ms to ~8ms), suggesting better handling of large atomic writes.

## 9. Seek Performance

Seek operations test iterator positioning. Results vary dramatically by access pattern:

**Random Seek**

TidesDB ⋅ **2.06M ops/sec** vs RocksDB ⋅ **718K ops/sec** (**2.87x faster**)

**Sequential Seek**

TidesDB ⋅ **6.39M ops/sec** vs RocksDB ⋅ **1.60M ops/sec** (**3.99x faster**)

**Zipfian Seek**

TidesDB ⋅ **3.47M ops/sec** vs RocksDB ⋅ **571K ops/sec** (**6.08x faster**)

<canvas id="seekChart" width="400" height="200"></canvas>
<script>
new Chart(document.getElementById('seekChart'), {
  type: 'bar',
  data: {
    labels: ['Random Seek', 'Sequential Seek', 'Zipfian Seek'],
    datasets: [{
      label: 'TidesDB (ops/sec)',
      data: [2062339, 6385198, 3469523],
      backgroundColor: 'rgba(59, 130, 246, 0.8)'
    }, {
      label: 'RocksDB (ops/sec)',
      data: [718060, 1602962, 570573],
      backgroundColor: 'rgba(239, 68, 68, 0.8)'
    }]
  },
  options: {
    responsive: true,
    scales: { y: { beginAtZero: true, title: { display: true, text: 'Operations/sec' }}}
  }
});
</script>

**Latency Analysis (Sequential Seek, per operation):**
- TidesDB ⋅ p50 1 μs, p95 2 μs, p99 2 μs
- RocksDB ⋅ p50 3 μs, p95 8 μs, p99 9 μs

TidesDB's seek performance is exceptional ⋅ **3x faster at median, 4x faster at p95**. The 1 μs median latency for sequential seeks suggests highly optimized iterator implementation with in-memory index structures that avoid I/O entirely for positioning. RocksDB likely needs to consult on-disk indexes for each seek operation.

## 10. Range Query Performance

Range queries scan multiple consecutive keys. Testing with 100-key ranges:

TidesDB ⋅ **770K ops/sec** vs RocksDB ⋅ **189K ops/sec** (**4.08x faster**)

With 1000-key ranges
TidesDB ⋅ **44K ops/sec** vs RocksDB ⋅ **36K ops/sec** (**1.23x faster**)

<canvas id="rangeChart" width="400" height="200"></canvas>
<script>
new Chart(document.getElementById('rangeChart'), {
  type: 'bar',
  data: {
    labels: ['Range 100 keys', 'Range 1000 keys'],
    datasets: [{
      label: 'TidesDB (ops/sec)',
      data: [770213, 44156],
      backgroundColor: 'rgba(59, 130, 246, 0.8)'
    }, {
      label: 'RocksDB (ops/sec)',
      data: [188541, 36015],
      backgroundColor: 'rgba(239, 68, 68, 0.8)'
    }]
  },
  options: {
    responsive: true,
    scales: { y: { beginAtZero: true, title: { display: true, text: 'Operations/sec' }}}
  }
});
</script>

**Latency (100-key ranges)**
- TidesDB ⋅ p50 0 μs, p95 25 μs, p99 38 μs, avg 5.09 μs
- RocksDB ⋅ p50 29 μs, p95 63 μs, p99 71 μs, avg 36.92 μs

TidesDB's advantage shrinks with larger ranges (1000 keys), suggesting the benefit comes from iterator setup rather than scan throughput. Once iterating, both engines are I/O bound reading sequential data. The p50 of 0 μs for TidesDB is a measurement artifact (timer resolution), but the p95/p99 numbers (25 μs vs 63 μs) show real advantages - likely from faster iterator initialization due to in-memory indexes.

## Write Amplification Summary

Write amplification is critical for SSD longevity and write throughput:

<canvas id="writeAmpChart" width="400" height="200"></canvas>
<script>
new Chart(document.getElementById('writeAmpChart'), {
  type: 'bar',
  data: {
    labels: ['Sequential', 'Random', 'Mixed', 'Zipfian', 'Large Values', 'Small Values'],
    datasets: [{
      label: 'TidesDB Write Amp',
      data: [1.09, 1.09, 1.11, 1.04, 1.07, 1.17],
      backgroundColor: 'rgba(59, 130, 246, 0.8)'
    }, {
      label: 'RocksDB Write Amp',
      data: [1.47, 1.32, 1.25, 1.24, 1.21, 1.52],
      backgroundColor: 'rgba(239, 68, 68, 0.8)'
    }]
  },
  options: {
    responsive: true,
    scales: { y: { beginAtZero: true, title: { display: true, text: 'Write Amplification Factor' }}}
  }
});
</script>

TidesDB consistently shows **lower write amplification** across all workloads. The average across these tests:
- TidesDB ⋅ **1.10x**
- RocksDB ⋅ **1.34x**

This 22% reduction in write amplification translates directly to reduced SSD wear and potentially higher sustained write throughput.

## Space Amplification Patterns

Space amplification varies significantly by workload:

<canvas id="spaceAmpChart" width="400" height="200"></canvas>
<script>
new Chart(document.getElementById('spaceAmpChart'), {
  type: 'bar',
  data: {
    labels: ['Sequential', 'Random', 'Mixed', 'Zipfian'],
    datasets: [{
      label: 'TidesDB Space Amp',
      data: [0.11, 0.22, 0.08, 0.02],
      backgroundColor: 'rgba(59, 130, 246, 0.8)'
    }, {
      label: 'RocksDB Space Amp',
      data: [0.18, 0.11, 0.15, 0.10],
      backgroundColor: 'rgba(239, 68, 68, 0.8)'
    }]
  },
  options: {
    responsive: true,
    scales: { y: { beginAtZero: true, title: { display: true, text: 'Space Amplification Factor' }}}
  }
});
</script>

TidesDB shows **lower space amplification** for sequential and hot-key workloads but **higher** for random writes. This suggests TidesDB's compaction strategy is optimized for temporal or spatial locality in writes.

## CPU Utilization Patterns

TidesDB consistently shows **higher CPU utilization**:
- Sequential writes ⋅ TidesDB 511% vs RocksDB 306%
- Random writes ⋅ TidesDB 467% vs RocksDB 256%
- Mixed workload ⋅ TidesDB 553% vs RocksDB 489%

The higher CPU usage is a direct consequence of TidesDB's lockless architecture. Instead of blocking on locks, threads perform more work - reference counting operations, atomic updates, and deferred cleanup processing. This trades CPU cycles for eliminating lock contention, which explains the excellent multi-threaded scaling. On systems with spare CPU capacity, this is highly advantageous. On CPU-constrained systems, it could be problematic.

## Architectural Insights

Several patterns emerge from this data:

**1. TidesDB Optimizes for Write Throughput**

The 2.63x advantage in sequential writes and consistent wins in random writes show TidesDB prioritizes write path efficiency. Lower write amplification supports this.

**2. TidesDB Excels at Point Operations**

Seeks, point reads, and small range queries show TidesDB's largest advantages (2-6x). The sub-microsecond latencies are enabled by keeping all metadata and bloom filters in memory, eliminating I/O for existence checks.

**3. Lockless Architecture Enables High Concurrency**

TidesDB's lockless design using reference counting and deferred cleanup explains both the high CPU utilization (511% on 8 cores) and excellent multi-threaded scaling. The tradeoff is higher memory usage to maintain reference-counted structures and defer cleanup operations.

**4. Batch Size Matters More for TidesDB**

Performance degradation at batch=10,000 suggests TidesDB's write path has different batching characteristics than RocksDB.

**5. Memory vs Performance Tradeoff**

TidesDB uses significantly more memory (often 2-5x) to achieve better performance, though sometimes temporarily. This isn't overhead - it's architectural: in-memory bloom filters, metadata, and reference-counted structures for lockless operation. Classic space-time tradeoff.

## Workload Recommendations

Based on these results:

**Choose TidesDB for**
- Write-heavy workloads with small-to-medium values (<1KB)
- Point lookups and seeks
- Hot-key/skewed access patterns
- Sequential or temporally-local writes
- Scenarios where write amplification matters (SSD longevity)
- Systems with abundant memory and CPU
- Large value workloads (>4KB)

**Choose RocksDB for**
- Memory-constrained environments
- Full table scans and large range queries
- Random write workloads where space efficiency matters
- CPU-constrained systems
- Workloads requiring predictable performance across all batch sizes

## Conclusion

TidesDB 7.0.0 shows impressive performance characteristics, particularly for write throughput, point operations, and write amplification. The 2-6x advantages in seeks and hot-key workloads are substantial. 

RocksDB remains highly competitive, particularly for large values, memory efficiency, and scan operations. Its more mature compaction strategies produce better space utilization for random writes.

Neither engine is universally "better" - the choice depends on your specific workload characteristics, resource constraints, and performance priorities. I encourage you to run your own benchmarks with your actual data patterns before making a decision.

The raw benchmark data and tooling are available below for those who want to dig deeper into specific scenarios.

---

You can download the raw benchtool report <a href="/benchmark_results_tdb700_rdb1075.txt" download>here</a>

You can find the **benchtool** source code <a href="https://github.com/tidesdb/benchtool" target="_blank">here</a> and run your own benchmarks!

**We strongly recommend benchmarking your own use case to determine which storage engine is best for your needs.**

---

*Thanks for reading!*
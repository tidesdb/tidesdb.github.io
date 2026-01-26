---
title: "Benchmark Analysis on TidesDB v7.4.0(mimalloc) & RocksDB v10.9.1 (jemalloc)"
description: "Performance benchmarks comparing TidesDB v7.4.0 and RocksDB v10.9.1 on write, read, and mixed workloads with mimalloc and jemalloc allocators."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-katerina-stefanou-274128573-12889926.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-katerina-stefanou-274128573-12889926.jpg
---

<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/chartjs-chart-error-bars@4.4.0/build/index.umd.min.js"></script>

<div class="article-image">

![TidesDB v7.4.0 vs RocksDB v10.9.1 Benchmarks](/pexels-katerina-stefanou-274128573-12889926.jpg)

</div>

*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on January 25th, 2026*


TidesDB <a href="https://github.com/tidesdb/tidesdb/releases/tag/v7.4.0">v7.4.0</a> outperforms RocksDB <a href="https://github.com/facebook/rocksdb/releases/tag/v10.9.1">v10.9.1</a> across nearly all benchmarks:
- **Writes** · 1.6-4x faster with 10-27x more stable latencies
- **Reads** · Faster iteration (1.42x), seeks (up to 5.19x), range queries (1.15-1.25x), and hot-key GETs (1.72x)
- **Latency** · Better p50/p99 on both reads and writes, even when throughput is similar
- **Space** · 0.08-0.10x amplification vs 0.13-0.19x

Both engines tested with optimized allocators (TidesDB with mimalloc, RocksDB with jemalloc).

You can download the raw benchtool report #1 <a href="/tidesdb_rocksdb_benchmark_results_20260125_214032.txt" download>here</a> (RocksDB jemalloc & TidesDB mimalloc)

You can download the raw benchtool report #2 <a href="/tidesdb_rocksdb_benchmark_results_20260125_220432.txt" download>here</a>

You can find the **benchtool** source code <a href="https://github.com/tidesdb/benchtool" target="_blank">here</a> and run your own benchmarks!


## Introduction

As usual this article presents benchmark results comparing TidesDB against RocksDB. The goal is to provide reproducible, honest numbers that help developers make informed decisions about which engine fits their workload.

## Test Environment

| Component | Specification |
|-----------|---------------|
| **CPU** | Intel Core i7-11700K @ 3.60GHz (8 cores, 16 threads) |
| **Memory** | 46 GB |
| **Kernel** | Linux 6.2.0-39-generic |
| **Disk** | Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA) |

**Test Configuration**
- Sync mode: **Disabled** (maximum performance mode)
- Default batch size: 1000
- Default threads: 8
- Key size: 16 bytes (unless noted)
- Value size: 100 bytes (unless noted)

## Sequential Write Performance

Sequential writes are the best-case scenario for LSM-tree engines. Keys arrive in sorted order, minimizing compaction overhead.

| Metric | TidesDB v7.4.0 | RocksDB v10.9.1 | Ratio |
|--------|----------------|-----------------|-------|
| **Throughput** | 7,115,164 ops/sec | 1,801,804 ops/sec | **3.95x faster** |
| **Duration** | 1.405 sec | 5.550 sec | |
| **Avg Latency** | 1,044 μs | 4,439 μs | 4.3x lower |
| **p99 Latency** | 1,887 μs | 4,458 μs | 2.4x lower |
| **Max Latency** | 3,595 μs | 920,109 μs | **256x lower** |
| **Latency CV** | 25.36% | 678.52% | **27x more stable** |
| **Write Amp** | 1.09x | 1.41x | |
| **Space Amp** | 0.10x | 0.19x | |
| **Peak RSS** | 2,479 MB | 2,752 MB | |
| **DB Size** | 111 MB | 208 MB | |

The standout number here is the latency coefficient of variation (CV). TidesDB's 25% CV indicates predictable latency, while RocksDB's 678% CV reflects significant variance - likely from background compaction stalls. The 920ms max latency spike in RocksDB is a classic symptom of write stalls during L0->L1 compaction.

<canvas id="writePerformanceChart" style="max-height: 400px;"></canvas>

<script>
new Chart(document.getElementById('writePerformanceChart'), {
  type: 'bar',
  data: {
    labels: ['Sequential Write', 'Random Write', 'Large Value (4KB)', 'Small Value (64B)'],
    datasets: [
      {
        label: 'TidesDB v7.4.0',
        data: [7115164, 2522416, 368453, 1995834],
        backgroundColor: 'rgba(59, 130, 246, 0.8)',
        borderColor: 'rgba(59, 130, 246, 1)',
        borderWidth: 1
      },
      {
        label: 'RocksDB v10.9.1',
        data: [1801804, 1566226, 122519, 1431936],
        backgroundColor: 'rgba(239, 68, 68, 0.8)',
        borderColor: 'rgba(239, 68, 68, 1)',
        borderWidth: 1
      }
    ]
  },
  options: {
    responsive: true,
    plugins: {
      title: { display: true, text: 'Write Throughput Comparison (ops/sec)' },
      legend: { position: 'top' }
    },
    scales: {
      y: { 
        beginAtZero: true,
        title: { display: true, text: 'Operations per Second' }
      }
    }
  }
});
</script>

## Random Write Performance

Random writes stress the LSM-tree more heavily. Keys arrive out of order, creating more overlap between SST files and increasing compaction work.

| Metric | TidesDB v7.4.0 | RocksDB v10.9.1 | Ratio |
|--------|----------------|-----------------|-------|
| **Throughput** | 2,522,416 ops/sec | 1,566,226 ops/sec | **1.61x faster** |
| **Duration** | 3.964 sec | 6.385 sec | |
| **Avg Latency** | 2,985 μs | 5,106 μs | 1.7x lower |
| **p99 Latency** | 5,939 μs | 7,595 μs | 1.3x lower |
| **Max Latency** | 10,314 μs | 893,415 μs | **87x lower** |
| **Latency CV** | 34.42% | 521.07% | **15x more stable** |
| **Write Amp** | 1.11x | 1.32x | |
| **Space Amp** | 0.08x | 0.13x | |
| **DB Size** | 90 MB | 140 MB | |

The throughput advantage narrows from 3.95x to 1.61x under random writes, which is expected. The latency stability story remains consistent - TidesDB avoids the long-tail latency spikes that plague RocksDB under write pressure.

## Read Performance

Read performance varies significantly by access pattern. TidesDB dominates on iteration, seeks, and hot-key workloads, while showing competitive performance on uniform random point reads.

### Random Point Reads (10M ops)

| Metric | TidesDB v7.4.0 | RocksDB v10.9.1 | Winner |
|--------|----------------|-----------------|--------|
| **GET Throughput** | 1,005,624 ops/sec | 1,600,183 ops/sec | RocksDB (throughput) |
| **ITER Throughput** | 8,054,857 ops/sec | 5,663,800 ops/sec | **TidesDB 1.42x** |
| **GET p50 Latency** | 3.00 μs | 4.00 μs | **TidesDB 1.33x lower** |
| **GET p99 Latency** | 7.00 μs | 12.00 μs | **TidesDB 1.71x lower** |

**Key insight**

While RocksDB achieves higher GET throughput, TidesDB delivers better latency at every percentile. For latency-sensitive applications, TidesDB's lower p50 (3μs vs 4μs) and p99 (7μs vs 12μs) matter more than raw throughput. TidesDB's iteration is also 1.42x faster.

### Seek Performance

Seek operations position an iterator at a specific key—critical for range queries and prefix scans.

| Pattern | TidesDB ops/sec | RocksDB ops/sec | Ratio |
|---------|-----------------|-----------------|-------|
| Random | 1,288,318 | 890,820 | **1.45x faster** |
| Sequential | 3,926,977 | 1,867,375 | **2.10x faster** |
| Zipfian (hot keys) | 3,336,501 | 643,107 | **5.19x faster** |

TidesDB's seek performance is dramatically better, especially for Zipfian patterns where hot keys benefit from caching.

### Range Query Performance

Range queries scan multiple consecutive keys.

| Range Size | TidesDB ops/sec | RocksDB ops/sec | Ratio |
|------------|-----------------|-----------------|-------|
| 100 keys (random) | 345,330 | 294,095 | **1.17x faster** |
| 1000 keys (random) | 51,012 | 44,460 | **1.15x faster** |
| 100 keys (sequential) | 512,370 | 408,864 | **1.25x faster** |

TidesDB maintains a consistent advantage on range queries across different sizes and patterns.

<canvas id="readPerformanceChart" style="max-height: 400px;"></canvas>

<script>
new Chart(document.getElementById('readPerformanceChart'), {
  type: 'bar',
  data: {
    labels: ['Iteration (10M)', 'Random Seek', 'Sequential Seek', 'Zipfian Seek', 'Range (100 keys)'],
    datasets: [
      {
        label: 'TidesDB v7.4.0',
        data: [8054857, 1288318, 3926977, 3336501, 345330],
        backgroundColor: 'rgba(59, 130, 246, 0.8)',
        borderColor: 'rgba(59, 130, 246, 1)',
        borderWidth: 1
      },
      {
        label: 'RocksDB v10.9.1',
        data: [5663800, 890820, 1867375, 643107, 294095],
        backgroundColor: 'rgba(239, 68, 68, 0.8)',
        borderColor: 'rgba(239, 68, 68, 1)',
        borderWidth: 1
      }
    ]
  },
  options: {
    responsive: true,
    plugins: {
      title: { display: true, text: 'Read Performance Comparison (ops/sec)' },
      legend: { position: 'top' }
    },
    scales: {
      y: { 
        beginAtZero: true,
        title: { display: true, text: 'Operations per Second' }
      }
    }
  }
});
</script>

## Mixed Workload (50/50 Read/Write)

Real workloads rarely do pure reads or pure writes. This test interleaves both operations.

| Metric | TidesDB v7.4.0 | RocksDB v10.9.1 | Ratio |
|--------|----------------|-----------------|-------|
| **PUT Throughput** | 2,833,870 ops/sec | 2,077,171 ops/sec | **1.36x faster** |
| **GET Throughput** | 1,603,626 ops/sec | 1,570,407 ops/sec | 1.02x faster |
| **PUT Avg Latency** | 2,551 μs | 3,847 μs | 1.5x lower |
| **PUT p99 Latency** | 4,827 μs | 5,148 μs | |
| **PUT Max Latency** | 6,334 μs | 62,044 μs | **9.8x lower** |
| **PUT CV** | 29.79% | 57.23% | |
| **Write Amp** | 1.09x | 1.25x | |
| **Space Amp** | 0.08x | 0.14x | |
| **DB Size** | 44 MB | 79 MB | |

Under mixed load, TidesDB maintains its write advantage while matching RocksDB on reads. The max latency difference (6ms vs 62ms) matters for applications with SLA requirements.

## Zipfian (Hot Key) Workload

Zipfian distribution simulates real-world access patterns where some keys are accessed far more frequently than others.

### Zipfian Writes

| Metric | TidesDB v7.4.0 | RocksDB v10.9.1 | Ratio |
|--------|----------------|-----------------|-------|
| **Throughput** | 3,142,460 ops/sec | 1,551,264 ops/sec | **2.03x faster** |
| **Avg Latency** | 2,326 μs | 5,152 μs | 2.2x lower |
| **p99 Latency** | 4,197 μs | 8,028 μs | 1.9x lower |
| **Write Amp** | 1.04x | 1.24x | |
| **Space Amp** | 0.02x | 0.11x | |
| **DB Size** | 10 MB | 62 MB | **6x smaller** |

The space amplification difference is dramatic here. With hot keys, TidesDB's compaction strategy results in a 10 MB database vs RocksDB's 62 MB - a **6x difference**.

### Zipfian Mixed

| Metric | TidesDB v7.4.0 | RocksDB v10.9.1 | Ratio |
|--------|----------------|-----------------|-------|
| **PUT Throughput** | 2,995,513 ops/sec | 1,632,148 ops/sec | **1.84x faster** |
| **GET Throughput** | 3,161,078 ops/sec | 1,832,908 ops/sec | **1.72x faster** |
| **ITER Throughput** | 3,950,385 ops/sec | 2,107,646 ops/sec | **1.87x faster** |
| **GET Avg Latency** | 1.84 μs | 3.75 μs | 2x lower |
| **GET p99 Latency** | 4.00 μs | 10.00 μs | 2.5x lower |

TidesDB excels on hot-key workloads across all operations. The read performance advantage here (vs the disadvantage on uniform random reads) TidesDB's caching is effective for skewed access patterns.

<canvas id="zipfianChart" style="max-height: 400px;"></canvas>

<script>
new Chart(document.getElementById('zipfianChart'), {
  type: 'bar',
  data: {
    labels: ['PUT', 'GET', 'ITER'],
    datasets: [
      {
        label: 'TidesDB v7.4.0',
        data: [2995513, 3161078, 3950385],
        backgroundColor: 'rgba(59, 130, 246, 0.8)',
        borderColor: 'rgba(59, 130, 246, 1)',
        borderWidth: 1
      },
      {
        label: 'RocksDB v10.9.1',
        data: [1632148, 1832908, 2107646],
        backgroundColor: 'rgba(239, 68, 68, 0.8)',
        borderColor: 'rgba(239, 68, 68, 1)',
        borderWidth: 1
      }
    ]
  },
  options: {
    responsive: true,
    plugins: {
      title: { display: true, text: 'Zipfian Mixed Workload (ops/sec)' },
      legend: { position: 'top' }
    },
    scales: {
      y: { 
        beginAtZero: true,
        title: { display: true, text: 'Operations per Second' }
      }
    }
  }
});
</script>

## Large Value Performance (4KB values)

Larger values stress different parts of the system—more I/O bandwidth, different compression ratios, and different memory pressure.

| Metric | TidesDB v7.4.0 | RocksDB v10.9.1 | Ratio |
|--------|----------------|-----------------|-------|
| **Throughput** | 368,453 ops/sec | 122,519 ops/sec | **3.01x faster** |
| **Avg Latency** | 21,360 μs | 65,208 μs | 3.1x lower |
| **p99 Latency** | 39,027 μs | 1,072,529 μs | **27x lower** |
| **Max Latency** | 53,906 μs | 1,088,137 μs | **20x lower** |
| **Latency CV** | 20.05% | 233.19% | **12x more stable** |
| **Write Amp** | 1.03x | 1.22x | |
| **DB Size** | 302 MB | 347 MB | |

The p99 latency difference is striking - 39ms vs 1,072ms. For large values, RocksDB's compaction can cause **multi-second** stalls.

## Small Value Performance (64B values, 50M ops)

Small values test metadata overhead and per-operation costs.

| Metric | TidesDB v7.4.0 | RocksDB v10.9.1 | Ratio |
|--------|----------------|-----------------|-------|
| **Throughput** | 1,995,834 ops/sec | 1,431,936 ops/sec | **1.39x faster** |
| **Avg Latency** | 3,541 μs | 5,586 μs | 1.6x lower |
| **Max Latency** | 110,366 μs | 1,242,438 μs | **11x lower** |
| **Latency CV** | 77.41% | 603.04% | **7.8x more stable** |
| **Write Amp** | 1.17x | 1.48x | |
| **DB Size** | 664 MB | 472 MB | |

Interestingly, TidesDB uses more space here (664 MB vs 472 MB) but achieves lower write amplification.

## Batch Size Impact

Batch size significantly affects throughput. Here's how both engines scale:

| Batch Size | TidesDB ops/sec | RocksDB ops/sec | TidesDB Advantage |
|------------|-----------------|-----------------|-------------------|
| 1 | 1,035,154 | 872,584 | 1.19x |
| 10 | 2,850,359 | 1,588,674 | **1.79x** |
| 100 | 3,477,309 | 2,277,167 | **1.53x** |
| 1,000 | 2,775,285 | 1,722,145 | **1.61x** |
| 10,000 | 1,871,186 | 1,199,671 | **1.56x** |

Both engines peak at batch size 100. TidesDB's advantage is most pronounced at batch size 10 (1.79x). Very large batches (10,000) hurt both engines due to memory pressure and lock contention.

## Delete Performance

Delete operations in LSM-trees write tombstones, which must later be compacted away.

| Metric | TidesDB v7.4.0 | RocksDB v10.9.1 | Ratio |
|--------|----------------|-----------------|-------|
| **Throughput** | 3,023,002 ops/sec | 3,263,712 ops/sec | 0.93x (slightly slower) |
| **Avg Latency** | 2,385 μs | 2,449 μs | Similar |
| **Write Amp** | 0.18x | 0.28x | |

Delete performance is roughly equivalent, with RocksDB slightly faster on raw throughput but TidesDB showing lower write amplification.

## mimalloc vs Regular Allocator

I ran the same benchmarks with TidesDB using mimalloc (report #1, `-DTIDESDB_WITH_MIMALLOC=ON`) and the standard system allocator (report #2, `-DTIDESDB_WITH_MIMALLOC=OFF`):

| Workload | mimalloc (Report #1) | Regular Allocator (Report #2) | Difference |
|----------|----------------------|-------------------------------|------------|
| Sequential Write | 6,365,356 ops/sec | 7,115,164 ops/sec | Regular +11.8% |
| Random Write | 2,255,283 ops/sec | 2,522,416 ops/sec | Regular +11.8% |
| Mixed PUT | 2,655,514 ops/sec | 2,833,870 ops/sec | Regular +6.7% |
| Mixed GET | 1,478,610 ops/sec | 1,603,626 ops/sec | Regular +8.5% |
| Zipfian PUT | 3,050,739 ops/sec | 3,142,460 ops/sec | Regular +3.0% |
| Zipfian GET | 3,042,708 ops/sec | 3,161,078 ops/sec | Regular +3.9% |
| Large Value (4KB) | 323,680 ops/sec | 368,453 ops/sec | Regular +13.8% |
| Small Value (64B) | 1,827,301 ops/sec | 1,995,834 ops/sec | Regular +9.2% |
| Delete | 2,871,484 ops/sec | 3,023,002 ops/sec | Regular +5.3% |

<canvas id="allocatorChart" style="max-height: 400px;"></canvas>

<script>
new Chart(document.getElementById('allocatorChart'), {
  type: 'bar',
  data: {
    labels: ['Sequential Write', 'Random Write', 'Mixed PUT', 'Mixed GET', 'Large Value', 'Small Value'],
    datasets: [
      {
        label: 'mimalloc (Report #1)',
        data: [6365356, 2255283, 2655514, 1478610, 323680, 1827301],
        backgroundColor: 'rgba(59, 130, 246, 0.8)',
        borderColor: 'rgba(59, 130, 246, 1)',
        borderWidth: 1
      },
      {
        label: 'Regular Allocator (Report #2)',
        data: [7115164, 2522416, 2833870, 1603626, 368453, 1995834],
        backgroundColor: 'rgba(156, 163, 175, 0.8)',
        borderColor: 'rgba(156, 163, 175, 1)',
        borderWidth: 1
      }
    ]
  },
  options: {
    responsive: true,
    plugins: {
      title: { display: true, text: 'TidesDB: mimalloc vs Regular Allocator (ops/sec)' },
      legend: { position: 'top' }
    },
    scales: {
      y: { 
        beginAtZero: true,
        title: { display: true, text: 'Operations per Second' }
      }
    }
  }
});
</script>

The regular allocator shows higher numbers in this run. This could be due to system warm-up effects, caching, background processes, or other environmental factors between runs. The difference is likely not significant enough to draw conclusions about allocator performance without more controlled testing on an isolated system say.

**Key takeaways**
- TidesDB remains stable with both allocators
- Performance is consistent between runs with minor variations (5-14%)
- TidesDB shows no stability issues with either allocator (unlike RocksDB which crashed with jemalloc)

## Summary

### TidesDB v7.4.0 Advantages

**Write Performance**
- Sequential writes · **3.95x faster**
- Random writes · **1.61x faster**
- Large value writes · **3.01x faster**
- Write latency CV · **10-27x more stable**
- Max write latency · **20-100x lower**

**Read Performance**
- Iteration · **1.42x faster**
- Seek operations · **1.45-5.19x faster**
- Range queries · **1.15-1.25x faster**
- Hot-key GETs · **1.72x faster**
- GET p50/p99 latency · **1.3-1.7x lower** (even when throughput is similar)

**Efficiency**
- Space amplification · **0.08-0.10x vs 0.13-0.19x**
- Write amplification · Consistently lower

### RocksDB v10.9.1 Advantages
- Uniform random GET throughput · 1.59x higher ops/sec (but with higher latency percentiles)
- Mature ecosystem · Years of production hardening 

### Stability Note

During our benchmarking, RocksDB experienced crashes when using jemalloc as the allocator. This is not an isolated incident - in previous benchmark runs, RocksDB also crashed with ASAN (AddressSanitizer) enabled and even with the standard system allocator. TidesDB completed all benchmark runs without any crashes or stability issues across all allocator configurations.  This is common through my benchmarking experience with RocksDB.

TidesDB v7.4.0 demonstrates strong performance across both write and read workloads compared to RocksDB v10.9.1. 

Key findings:

- Writes · TidesDB is 1.6-4x faster with dramatically more stable latencies
- Reads · TidesDB wins on iteration (1.42x), seeks (up to 5.19x), range queries (1.15-1.25x), and hot-key GETs (1.72x). Even on uniform random GETs where RocksDB has higher throughput, TidesDB delivers better p50/p99 latencies
- Hot-key workloads · TidesDB dominates across all operations (1.7-5x faster)
- Efficiency · Consistently lower space and write amplification

For most workloads especially those with any write component, scan operations, or skewed access patterns - TidesDB offers advantages in both throughput and latency predictability.

- GitHub · https://github.com/tidesdb/tidesdb
- Design deep-dive · https://tidesdb.com/getting-started/how-does-tidesdb-work
- Benchmark tool · https://github.com/tidesdb/benchtool

Join the TidesDB Discord for more updates and discussions at https://discord.gg/tWEmjR66cy
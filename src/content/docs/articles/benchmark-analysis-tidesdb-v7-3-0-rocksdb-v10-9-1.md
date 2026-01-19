---
title: "TidesDB v7.3.0 & RocksDB v10.9.1 Benchmark Analysis"
description: "Comprehensive performance benchmarks comparing TidesDB v7.3.0 and RocksDB v10.9.1."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-hernan-nikolajezyk-311045087-15940540.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-hernan-nikolajezyk-311045087-15940540.jpg
---

<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/chartjs-chart-error-bars@4.4.0/build/index.umd.min.js"></script>

<div class="article-image">

![TidesDB v7.3.0 & RocksDB v10.9.1 Benchmark Analysis](/pexels-hernan-nikolajezyk-311045087-15940540.jpg)

</div>


*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on January 19th, 2026*

Following the recent v7.3.0 release, I ran another benchtool run comparing TidesDB against RocksDB <a href="https://github.com/facebook/rocksdb/releases/tag/v10.9.1">v10.9.1</a>. This article presents detailed performance analysis of the run, which includes continued performance optimizations, stability improvements, and in this minor we've added a new method for backing up your database during runtime, you can read about that <a href="https://tidesdb.com/reference/c#backup">here</a>. Both engines are configured with _sync disabled_ to measure the absolute performance ceiling.


## Test Configuration

The test environment used 8 threads across various workloads with 16-byte keys and 100-byte values as the baseline configuration. Tests were conducted on the same hardware to ensure fair comparison.

**We recommend you benchmark your own use case to determine which storage engine is best for your needs!**

**Hardware**
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)
- Ubuntu 24.04 LTS

**Software Versions**
- **TidesDB v7.3.0**
- **RocksDB v10.9.1**
- GCC with -O3 optimization

**Default Test Configuration**
- **Sync Mode** · DISABLED (maximum performance)
- **Default Batch Size** · 1000 operations
- **Threads** · 8 concurrent threads
- **Key Size** · 16 bytes
- **Value Size** · 100 bytes

*Large Value tests use 256-byte keys with 4KB values; Small Value tests use 16-byte keys with 64-byte values.*

You can download the raw benchtool report <a href="/tidesdb730_rocksdb1091.txt" download>here</a>

You can find the **benchtool** source code <a href="https://github.com/tidesdb/benchtool" target="_blank">here</a> and run your own benchmarks!

## Performance Overview

<div class="chart-container" style="max-width: 1000px; margin: 40px auto;">
  <canvas id="throughputChart"></canvas>
</div>

<script>
(function() {
  const ctx = document.getElementById('throughputChart');
  if (!ctx) return;
  
  const isDarkMode = document.documentElement.classList.contains('dark') || 
                     window.matchMedia('(prefers-color-scheme: dark)').matches;
  const gridColor = isDarkMode ? 'rgba(255, 255, 255, 0.15)' : 'rgba(0, 0, 0, 0.1)';
  
  const workloads = [
    'Sequential Write',
    'Sequential Range (100)',
    'Zipfian Write',
    'Sequential Seek',
    'Range Query (100)',
    'Range Query (1000)',
    'Zipfian Mixed',
    'Large Value (4KB)',
    'Zipfian Seek',
    'Batch=10 Write',
    'Delete (batch=1000)',
    'Batch=100 Write',
    'Batch=10000 Write',
    'Batch=1000 Write'
  ];
  
  // TidesDB throughput in K ops/sec
  const tidesdbData = [6961.0, 509.8, 3129.8, 3486.0, 359.1, 46.9, 2940.8, 346.0, 3159.0, 2623.0, 2925.2, 3000.2, 1631.1, 2575.6];
  // RocksDB throughput in K ops/sec  
  const rocksdbData = [2267.0, 361.7, 1466.9, 1817.4, 284.4, 47.0, 1464.2, 180.6, 632.3, 1671.1, 3126.0, 2183.1, 1208.3, 1923.1];
  
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: workloads,
      datasets: [{
        label: 'TidesDB v7.3.0',
        data: tidesdbData,
        backgroundColor: 'rgba(174, 199, 232, 0.85)',
        borderColor: 'rgba(174, 199, 232, 1)',
        borderWidth: 2
      }, {
        label: 'RocksDB v10.9.1',
        data: rocksdbData,
        backgroundColor: 'rgba(255, 187, 120, 0.85)',
        borderColor: 'rgba(255, 187, 120, 1)',
        borderWidth: 2
      }]
    },
    options: {
      indexAxis: 'y',
      responsive: true,
      maintainAspectRatio: true,
      aspectRatio: 1.0,
      plugins: {
        title: {
          display: true,
          text: 'Throughput Comparison by Workload',
          font: {
            size: 20,
            weight: 'bold'
          },
          color: '#b4bfd8ff',
          padding: 20
        },
        legend: {
          display: true,
          position: 'top',
          labels: {
            font: {
              size: 14
            },
            color: '#88a0c7ff',
            padding: 20,
            usePointStyle: true,
            pointStyle: 'rect'
          }
        },
        tooltip: {
          callbacks: {
            label: function(context) {
              const value = context.parsed.x;
              if (value >= 1000) {
                return context.dataset.label + ': ' + (value / 1000).toFixed(2) + 'M ops/sec';
              }
              return context.dataset.label + ': ' + value.toFixed(1) + 'K ops/sec';
            }
          }
        }
      },
      scales: {
        x: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Throughput (K ops/sec)',
            font: {
              size: 14,
              weight: 'bold'
            },
            color: '#b4bfd8ff'
          },
          grid: {
            color: gridColor
          },
          ticks: {
            callback: function(value) {
              if (value >= 1000) {
                return (value / 1000).toFixed(1) + 'M';
              }
              return value;
            },
            color: '#b4bfd8ff'
          }
        },
        y: {
          grid: {
            color: gridColor
          },
          ticks: {
            font: {
              size: 12
            },
            color: '#b4bfd8ff'
          }
        }
      }
    }
  });
})();
</script>

<div class="chart-container" style="max-width: 1200px; margin: 60px auto;">
  <canvas id="ratioChart"></canvas>
</div>

<script>
(function() {
  const ctx = document.getElementById('ratioChart');
  if (!ctx) return;
  
  const isDarkMode = document.documentElement.classList.contains('dark') || 
                     window.matchMedia('(prefers-color-scheme: dark)').matches;
  const gridColor = isDarkMode ? 'rgba(255, 255, 255, 0.2)' : 'rgba(0, 0, 0, 0.1)';
  const baselineColor = isDarkMode ? 'rgba(255, 255, 255, 0.4)' : 'rgba(0, 0, 0, 0.3)';
  
  const workloads = [
    'Sequential Write',
    'Sequential Range (100)',
    'Zipfian Write',
    'Sequential Seek',
    'Range Query (100)',
    'Range Query (1000)',
    'Zipfian Mixed',
    'Large Value (4KB)',
    'Zipfian Seek',
    'Batch=10 Write',
    'Delete (batch=1000)',
    'Batch=100 Write',
    'Batch=10000 Write',
    'Batch=1000 Write',
    'Mixed Workload',
    'Random Seek',
    'Delete Batch=100',
    'Batch=1 Write',
    'Random Write',
    'Delete Batch=1',
    'Random Delete',
    'Random Read',
    'Small Value (64B)'
  ];
  
  const ratios = [3.07, 1.41, 2.13, 1.92, 1.26, 1.00, 2.01, 1.92, 5.00, 1.57, 0.94, 1.37, 1.35, 1.34, 1.33, 1.52, 1.26, 1.28, 1.25, 1.29, 1.01, 1.55, 1.18];
  
  const colors = ratios.map(r => r >= 1.5 ? 'rgba(46, 134, 171, 0.8)' : 
                                 r >= 1.2 ? 'rgba(106, 168, 199, 0.8)' : 
                                 'rgba(174, 199, 232, 0.8)');
  
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: workloads,
      datasets: [{
        label: 'TidesDB / RocksDB Speedup',
        data: ratios,
        backgroundColor: colors,
        borderColor: colors.map(c => c.replace('0.8', '1')),
        borderWidth: 2
      }]
    },
    options: {
      indexAxis: 'y',
      responsive: true,
      maintainAspectRatio: true,
      aspectRatio: 0.8,
      plugins: {
        title: {
          display: true,
          text: 'Performance Ratio (TidesDB / RocksDB)',
          font: {
            size: 20,
            weight: 'bold'
          },
          color: '#b4bfd8ff',
          padding: 20
        },
        legend: {
          display: false
        },
        tooltip: {
          callbacks: {
            label: function(context) {
              const value = context.parsed.x;
              if (value >= 1) {
                return value.toFixed(2) + 'x faster';
              }
              return (1 / value).toFixed(2) + 'x slower';
            }
          }
        }
      },
      scales: {
        x: {
          beginAtZero: true,
          max: 5.5,
          title: {
            display: true,
            text: 'Speedup Ratio (higher is better)',
            font: {
              size: 14,
              weight: 'bold'
            },
            color: '#b4bfd8ff'
          },
          grid: {
            color: gridColor
          },
          ticks: {
            callback: function(value) {
              return value.toFixed(1) + 'x';
            },
            color: '#b4bfd8ff'
          }
        },
        y: {
          grid: {
            color: gridColor
          },
          ticks: {
            font: {
              size: 11
            },
            color: '#b4bfd8ff'
          }
        }
      }
    }
  });
})();
</script>

TidesDB v7.3.0 leads in most workloads, with ratios ranging from **0.94x (slower)** to **5.00x faster** across 23 different workloads. The biggest gaps show up in sequential operations and Zipfian (hot key) patterns, while long range scans and batch=1000 deletes are closer or favor RocksDB.

## Sequential Write Performance

10M write operations, 8 threads, batch size 1000:
- **TidesDB** · 6,961,016 ops/sec
- **RocksDB** · 2,266,978 ops/sec
- **Advantage** · **3.07x faster**

Average latency · 1,077μs vs 3,528μs (3.3x better)  
p99 latency · 1,851μs vs 4,346μs (2.3x better)  
Max latency · 5,477μs vs 235,143μs (43x better!)

<div class="chart-container" style="max-width: 800px; margin: 40px auto;">
  <canvas id="seqWriteChart"></canvas>
</div>

<script>
(function() {
  const ctx = document.getElementById('seqWriteChart');
  if (!ctx) return;
  
  const isDarkMode = document.documentElement.classList.contains('dark') || 
                     window.matchMedia('(prefers-color-scheme: dark)').matches;
  const gridColor = isDarkMode ? 'rgba(255, 255, 255, 0.15)' : 'rgba(0, 0, 0, 0.1)';
  
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['TidesDB v7.3.0', 'RocksDB v10.9.1'],
      datasets: [{
        label: 'Sequential Write Throughput',
        data: [6961.0, 2267.0],
        backgroundColor: ['rgba(174, 199, 232, 0.8)', 'rgba(255, 187, 120, 0.8)'],
        borderColor: ['rgba(174, 199, 232, 1)', 'rgba(255, 187, 120, 1)'],
        borderWidth: 2
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'Sequential Write Throughput (K ops/sec)',
          font: { size: 16, weight: 'bold' },
          color: '#b4bfd8ff'
        },
        legend: { display: false }
      },
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Throughput (K ops/sec)',
            font: { size: 12 },
            color: '#b4bfd8ff'
          },
          grid: { color: gridColor },
          ticks: { color: '#b4bfd8ff' }
        },
        x: {
          grid: { color: gridColor },
          ticks: { color: '#b4bfd8ff' }
        }
      }
    }
  });
})();
</script>

TidesDB's **3.07x sequential write advantage** represents one of the largest performance gaps in the entire run. The consistency story is even more impressive - TidesDB's coefficient of variation (27.82%) is nearly **10x better** than RocksDB's (273.48%), meaning dramatically more predictable performance.

Write amplification:
- **TidesDB** · 1.08x (25% better)
- **RocksDB** · 1.45x

Database size:
- **TidesDB** · 110.65 MB (42% smaller)
- **RocksDB** · 192.30 MB

Resource usage:
- Peak RSS · 2,494 MB vs 2,759 MB (10% less memory)
- Disk writes · 1,197 MB vs 1,604 MB (25% less I/O)
- CPU utilization · 507% vs 279%

The higher CPU utilization reflects TidesDB's lock-free algorithms trading CPU cycles for dramatically higher throughput and lower latency.

## Random Write Performance

10M random write operations, 8 threads, batch size 1000:
- **TidesDB** · 2,299,354 ops/sec
- **RocksDB** · 1,840,333 ops/sec
- **Advantage** · **1.25x faster**

Average latency · 3,169μs vs 4,345μs  
p99 latency · 6,239μs vs 6,042μs (comparable)  
Max latency · 8,824μs vs 125,312μs (14x better!)

The random write workload shows TidesDB's strength in handling unpredictable access patterns. While throughput is 25% higher, the real story is in tail latency - TidesDB's maximum latency of 8.8ms versus RocksDB's 125ms represents a **14x improvement** in worst-case scenarios.

Write amplification:
- **TidesDB** · 1.12x (15% better)
- **RocksDB** · 1.32x

Database size:
- **TidesDB** · 100.06 MB (14% smaller)
- **RocksDB** · 116.77 MB

Latency consistency (CV):
- **TidesDB** · 34.56%
- **RocksDB** · 128.81% (3.7x worse)

## Random Read Performance

10M random read operations, 8 threads:
- **TidesDB** · 2,533,182 ops/sec
- **RocksDB** · 1,632,814 ops/sec
- **Advantage** · **1.55x faster**

Average latency · 2.93μs vs 4.37μs  
p50 latency · 3μs vs 4μs  
p99 latency · 7μs vs 12μs  
Max latency · 1,004μs vs 650μs (RocksDB lower max)

Read operations show a 55% throughput advantage for TidesDB with lower average and p99 latencies, while RocksDB posts the lower maximum latency in this run.

Resource usage:
- Peak RSS · 1,703 MB vs 280 MB
- CPU utilization · 540% vs 529%

## Hot Key Performance (Zipfian Workloads)

Zipfian distributions simulate real-world access patterns where a small subset of keys receives the majority of traffic - think social media feeds, trending content, or cache workloads.

### Zipfian Write Performance

5M Zipfian write operations:
- **TidesDB** · 3,129,757 ops/sec
- **RocksDB** · 1,466,933 ops/sec
- **Advantage** · **2.13x faster**

Database size after Zipfian writes:
- **TidesDB** · 10.14 MB (85% smaller)
- **RocksDB** · 66.65 MB

TidesDB's compaction algorithm aggressively consolidates hot keys, resulting in dramatically smaller database sizes for skewed workloads.

### Zipfian Seek Performance

5M Zipfian seek operations:
- **TidesDB** · 3,159,001 ops/sec
- **RocksDB** · 632,349 ops/sec
- **Advantage** · **5.00x faster**

Average latency · 1.60μs vs 11.75μs (7.3x better)  
p99 latency · 4μs vs 28μs (7.0x better)

### Zipfian Mixed Workload

5M mixed operations (50% read, 50% write) with Zipfian distribution:
- **TidesDB** · 2,940,777 ops/sec (mixed)
- **RocksDB** · 1,464,212 ops/sec (mixed)
- **Advantage** · **2.01x faster**

The **2.01x advantage** on mixed Zipfian workloads demonstrates TidesDB's ability to handle real-world access patterns where hot keys dominate traffic. 

## Range Query Performance

Range queries test the engine's ability to efficiently scan contiguous key ranges - critical for analytical queries and batch processing.

### Range Scan (100 keys per query)

1M range queries, each scanning 100 keys:
- **TidesDB** · 359,142 ops/sec
- **RocksDB** · 284,423 ops/sec
- **Advantage** · **1.26x faster**

Average latency per query · 21.24μs vs 26.62μs  
p99 latency · 69μs vs 57μs (RocksDB lower p99)

### Range Scan (1000 keys per query)

500K range queries, each scanning 1000 keys:
- **TidesDB** · 46,902 ops/sec
- **RocksDB** · 47,044 ops/sec
- **Advantage** · **~1.00x (RocksDB slightly faster)**

Average latency per query · 158.93μs vs 168.56μs  
p99 latency · 358μs vs 328μs (RocksDB lower p99)

### Sequential Range Scan (100 keys)

1M sequential range queries:
- **TidesDB** · 509,784 ops/sec
- **RocksDB** · 361,681 ops/sec
- **Advantage** · **1.41x faster**

Average latency · 15.36μs vs 20.76μs (1.35x better)  
p99 latency · 43μs vs 54μs (1.3x better)

<div class="chart-container" style="max-width: 800px; margin: 40px auto;">
  <canvas id="rangeQueryChart"></canvas>
</div>

<script>
(function() {
  const ctx = document.getElementById('rangeQueryChart');
  if (!ctx) return;
  
  const isDarkMode = document.documentElement.classList.contains('dark') || 
                     window.matchMedia('(prefers-color-scheme: dark)').matches;
  const gridColor = isDarkMode ? 'rgba(255, 255, 255, 0.15)' : 'rgba(0, 0, 0, 0.1)';
  
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Range (100 keys)', 'Range (1000 keys)', 'Sequential Range'],
      datasets: [{
        label: 'TidesDB v7.3.0',
        data: [359.1, 46.9, 509.8],
        backgroundColor: 'rgba(174, 199, 232, 0.85)',
        borderColor: 'rgba(174, 199, 232, 1)',
        borderWidth: 2
      }, {
        label: 'RocksDB v10.9.1',
        data: [284.4, 47.0, 361.7],
        backgroundColor: 'rgba(255, 187, 120, 0.85)',
        borderColor: 'rgba(255, 187, 120, 1)',
        borderWidth: 2
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'Range Query Performance (K ops/sec)',
          font: { size: 16, weight: 'bold' },
          color: '#b4bfd8ff'
        },
        legend: {
          display: true,
          position: 'top',
          labels: {
            font: { size: 12 },
            color: '#88a0c7ff'
          }
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Throughput (K ops/sec)',
            font: { size: 12 },
            color: '#b4bfd8ff'
          },
          grid: { color: gridColor },
          ticks: { color: '#b4bfd8ff' }
        },
        x: {
          grid: { color: gridColor },
          ticks: { color: '#b4bfd8ff' }
        }
      }
    }
  });
})();
</script>

TidesDB's range query results span **~1.00-1.41x**, with parity on 1000-key scans and a 1.41x edge on sequential ranges.

## Seek Performance

Seek operations test the engine's ability to position iterators at specific keys - essential for ordered traversals and range query initialization.

### Random Seek

5M random seek operations:
- **TidesDB** · 1,219,184 ops/sec
- **RocksDB** · 799,664 ops/sec
- **Advantage** · **1.52x faster**

Average latency · 6.34μs vs 9.41μs  
p99 latency · 12μs vs 20μs

### Sequential Seek

5M sequential seek operations:
- **TidesDB** · 3,485,994 ops/sec
- **RocksDB** · 1,817,409 ops/sec
- **Advantage** · **1.92x faster**

Average latency · 2.00μs vs 3.22μs (1.6x better)  
p99 latency · 5μs vs 8μs (1.6x better)

The **1.92x sequential seek advantage** demonstrates TidesDB's efficient iterator positioning for ordered traversals.

## Delete Performance

Delete operations test removal efficiency across different batch sizes.

### Batched Deletes (batch=1000)

5M delete operations with batch size 1000:
- **TidesDB** · 2,925,229 ops/sec
- **RocksDB** · 3,125,985 ops/sec
- **Advantage** · **RocksDB 1.07x faster**

### Batched Deletes (batch=100)

5M delete operations with batch size 100:
- **TidesDB** · 3,076,527 ops/sec
- **RocksDB** · 2,445,948 ops/sec
- **Advantage** · **1.26x faster**

### Single Deletes (batch=1)

5M delete operations without batching:
- **TidesDB** · 1,154,056 ops/sec
- **RocksDB** · 896,797 ops/sec
- **Advantage** · **1.29x faster**

TidesDB leads at batch sizes 1 and 100, while RocksDB is slightly faster at batch size 1000. Larger batches still yield higher absolute throughput for both engines.

## Batch Size Impact

Testing write throughput across different batch sizes (10M operations):

| Batch Size | TidesDB | RocksDB | Ratio |
|------------|---------|---------|-------|
| 1 (unbatched) | 1,054.5K | 820.7K | **1.28x** |
| 10 | 2,623.0K | 1,671.1K | **1.57x** |
| 100 | 3,000.2K | 2,183.1K | **1.37x** |
| 1000 | 2,575.6K | 1,923.1K | **1.34x** |
| 10000 | 1,631.1K | 1,208.3K | **1.35x** |

<div class="chart-container" style="max-width: 800px; margin: 40px auto;">
  <canvas id="batchSizeChart"></canvas>
</div>

<script>
(function() {
  const ctx = document.getElementById('batchSizeChart');
  if (!ctx) return;
  
  const isDarkMode = document.documentElement.classList.contains('dark') || 
                     window.matchMedia('(prefers-color-scheme: dark)').matches;
  const gridColor = isDarkMode ? 'rgba(255, 255, 255, 0.15)' : 'rgba(0, 0, 0, 0.1)';
  
  new Chart(ctx, {
    type: 'line',
    data: {
      labels: ['1', '10', '100', '1000', '10000'],
      datasets: [{
        label: 'TidesDB v7.3.0',
        data: [1054.5, 2623.0, 3000.2, 2575.6, 1631.1],
        backgroundColor: 'rgba(174, 199, 232, 0.3)',
        borderColor: 'rgba(174, 199, 232, 1)',
        borderWidth: 3,
        fill: true,
        tension: 0.4
      }, {
        label: 'RocksDB v10.9.1',
        data: [820.7, 1671.1, 2183.1, 1923.1, 1208.3],
        backgroundColor: 'rgba(255, 187, 120, 0.3)',
        borderColor: 'rgba(255, 187, 120, 1)',
        borderWidth: 3,
        fill: true,
        tension: 0.4
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'Write Throughput vs Batch Size',
          font: { size: 16, weight: 'bold' },
          color: '#b4bfd8ff'
        },
        legend: {
          display: true,
          position: 'top',
          labels: {
            font: { size: 12 },
            color: '#88a0c7ff'
          }
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Throughput (K ops/sec)',
            font: { size: 12 },
            color: '#b4bfd8ff'
          },
          grid: { color: gridColor },
          ticks: { color: '#b4bfd8ff' }
        },
        x: {
          title: {
            display: true,
            text: 'Batch Size',
            font: { size: 12 },
            color: '#b4bfd8ff'
          },
          grid: { color: gridColor },
          ticks: { color: '#b4bfd8ff' }
        }
      }
    }
  });
})();
</script>

Both engines show optimal performance with batch sizes around 100-1000 operations. TidesDB maintains a **1.28-1.57x advantage** across all batch sizes, with the largest gap at batch size 10.

## Large Value Performance

1M write operations with 256-byte keys and 4KB values:
- **TidesDB** · 345,954 ops/sec
- **RocksDB** · 180,574 ops/sec
- **Advantage** · **1.92x faster**

Average latency · 22,794μs vs 44,213μs (1.9x better)  
p99 latency · 36,633μs vs 371,716μs (10.2x better)

<div class="chart-container" style="max-width: 800px; margin: 40px auto;">
  <canvas id="largeValueChart"></canvas>
</div>

<script>
(function() {
  const ctx = document.getElementById('largeValueChart');
  if (!ctx) return;
  
  const isDarkMode = document.documentElement.classList.contains('dark') || 
                     window.matchMedia('(prefers-color-scheme: dark)').matches;
  const gridColor = isDarkMode ? 'rgba(255, 255, 255, 0.15)' : 'rgba(0, 0, 0, 0.1)';
  
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['TidesDB v7.3.0', 'RocksDB v10.9.1'],
      datasets: [{
        label: 'Large Value Write Throughput',
        data: [346.0, 180.6],
        backgroundColor: ['rgba(174, 199, 232, 0.8)', 'rgba(255, 187, 120, 0.8)'],
        borderColor: ['rgba(174, 199, 232, 1)', 'rgba(255, 187, 120, 1)'],
        borderWidth: 2
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'Large Value (4KB) Write Throughput (K ops/sec)',
          font: { size: 16, weight: 'bold' },
          color: '#b4bfd8ff'
        },
        legend: { display: false }
      },
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Throughput (K ops/sec)',
            font: { size: 12 },
            color: '#b4bfd8ff'
          },
          grid: { color: gridColor },
          ticks: { color: '#b4bfd8ff' }
        },
        x: {
          grid: { color: gridColor },
          ticks: { color: '#b4bfd8ff' }
        }
      }
    }
  });
})();
</script>

The **1.92x advantage** on large values demonstrates TidesDB's efficient handling of substantial payloads. The p99 latency advantage of **10.2x** highlights a major tail-latency gap on large values.

Write amplification:
- **TidesDB** · 1.05x (15% better)
- **RocksDB** · 1.23x

Database size:
- **TidesDB** · 302.05 MB (13% smaller)
- **RocksDB** · 346.80 MB

TidesDB's key-value separation architecture maintains smaller on-disk size here while delivering nearly 2x throughput on large values.

## Small Value Performance

50M write operations with 16-byte keys and 64-byte values:
- **TidesDB** · 1,779,111 ops/sec
- **RocksDB** · 1,508,031 ops/sec
- **Advantage** · **1.18x faster**

Average latency · 4,276μs vs 5,304μs  
p99 latency · 8,505μs vs 5,553μs (RocksDB lower p99)

Write amplification:
- **TidesDB** · 1.18x (21% better)
- **RocksDB** · 1.50x

Database size:
- **TidesDB** · 521.80 MB (7% smaller)
- **RocksDB** · 560.86 MB

On small values, TidesDB delivers better throughput and lower write amplification, while RocksDB shows lower p99 latency on this workload.

## Iteration Performance

Full database iteration speeds after various workloads provide insight into scan efficiency:

### Write Workloads
- Sequential write (10M keys) · 8.09M vs 4.73M (**1.71x faster**)
- Random write (10M keys) · 3.01M vs 3.94M (0.76x slower)
- Zipfian write (5M keys) · 3.69M vs 1.93M (**1.92x faster**)

### Mixed Workloads
- 50/50 mixed (5M keys) · 2.75M vs 4.63M (0.59x slower)
- Zipfian mixed (5M keys) · 3.68M vs 1.92M (**1.92x faster**)

### Delete Workloads
- Batched delete (batch=1000) · 2.68M vs 0.00 (RocksDB reports 0 keys after delete; iteration not comparable)

TidesDB shows strong iteration performance on sequential and Zipfian workloads. The **1.92x Zipfian iteration advantage** demonstrates how consolidation of hot keys improves scan performance on skewed access patterns.

## Resource Usage

### Memory Consumption (Peak RSS)

TidesDB's memory usage patterns reflect its performance-optimized design:
- 10M sequential write · 2,494 MB vs 2,759 MB (10% less)
- 10M random write · 2,486 MB vs 2,744 MB (9% less)
- 1M large values · 3,328 MB vs 1,203 MB (176% more)
- 50M small values · 8,539 MB vs 8,773 MB (3% less)
- 10M random read · 1,703 MB vs 280 MB (6.1x more)

The higher memory usage on large values reflects TidesDB's value separation architecture, which keeps larger payloads readily accessible for optimal performance.

### Disk I/O

Disk writes (MB written):
- 10M sequential · 1,197 MB vs 1,604 MB (**25% less**)
- 10M random · 1,241 MB vs 1,462 MB (**15% less**)
- 1M large values · 4,346 MB vs 5,086 MB (**15% less**)
- 50M small values · 4,520 MB vs 5,706 MB (**21% less**)

TidesDB consistently writes **15-25% less data to disk**, reducing SSD wear and improving throughput.

### CPU Utilization

TidesDB shows higher CPU utilization in most workloads:
- Sequential writes · 507% vs 279% (1.82x higher)
- Random writes · 551% vs 297% (1.85x higher)
- Random reads · 540% vs 529% (1.02x higher)
- Large values · 687% vs 256% (2.68x higher)

The higher CPU usage reflects TidesDB's lock-free algorithms trading CPU cycles for reduced lock contention. On highly parallel workloads with available CPU cores, this trade-off delivers substantially higher throughput.

## Tail Latency · Where TidesDB Truly Shines

One of the most striking differences between TidesDB and RocksDB is tail latency behavior. While average throughput tells part of the story, maximum latencies reveal how each engine handles worst-case scenarios - critical for applications requiring predictable performance.

**Maximum Latency Comparison (lower is better)**

| Workload | TidesDB Max | RocksDB Max | TidesDB Advantage |
|----------|-------------|-------------|-------------------|
| Sequential Write | 5,477 μs | 235,143 μs | **43x better** |
| Random Write | 8,824 μs | 125,312 μs | **14x better** |
| Random Read | 1,004 μs | 650 μs | **RocksDB 1.5x lower** |
| Large Value (4KB) | 62,763 μs | 642,450 μs | **10x better** |
| Small Value (64B) | 133,782 μs | 1,651,710 μs | **12x better** |
| Zipfian Seek | 643 μs | 1,030 μs | **1.6x better** |
| Sequential Seek | 943 μs | 2,606 μs | **2.8x better** |

<div class="chart-container" style="max-width: 900px; margin: 40px auto;">
  <canvas id="tailLatencyChart"></canvas>
</div>

<script>
(function() {
  const ctx = document.getElementById('tailLatencyChart');
  if (!ctx) return;
  
  const isDarkMode = document.documentElement.classList.contains('dark') || 
                     window.matchMedia('(prefers-color-scheme: dark)').matches;
  const gridColor = isDarkMode ? 'rgba(255, 255, 255, 0.15)' : 'rgba(0, 0, 0, 0.1)';
  
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Seq Write', 'Random Write', 'Random Read', 'Large Value', 'Zipfian Seek', 'Seq Seek'],
      datasets: [{
        label: 'TidesDB v7.3.0 (ms)',
        data: [5.477, 8.824, 1.004, 62.763, 0.643, 0.943],
        backgroundColor: 'rgba(174, 199, 232, 0.85)',
        borderColor: 'rgba(174, 199, 232, 1)',
        borderWidth: 2
      }, {
        label: 'RocksDB v10.9.1 (ms)',
        data: [235.143, 125.312, 0.650, 642.450, 1.030, 2.606],
        backgroundColor: 'rgba(255, 187, 120, 0.85)',
        borderColor: 'rgba(255, 187, 120, 1)',
        borderWidth: 2
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'Maximum Latency Comparison (ms, log scale)',
          font: { size: 16, weight: 'bold' },
          color: '#b4bfd8ff'
        },
        legend: {
          display: true,
          position: 'top',
          labels: {
            font: { size: 12 },
            color: '#88a0c7ff'
          }
        },
        tooltip: {
          callbacks: {
            label: function(context) {
              return context.dataset.label + ': ' + context.parsed.y.toFixed(3) + ' ms';
            }
          }
        }
      },
      scales: {
        y: {
          type: 'logarithmic',
          title: {
            display: true,
            text: 'Max Latency (ms, log scale)',
            font: { size: 12 },
            color: '#b4bfd8ff'
          },
          grid: { color: gridColor },
          ticks: { 
            color: '#b4bfd8ff',
            callback: function(value) {
              if (value === 1 || value === 10 || value === 100 || value === 1000) {
                return value + ' ms';
              }
              return '';
            }
          }
        },
        x: {
          grid: { color: gridColor },
          ticks: { 
            color: '#b4bfd8ff',
            font: { size: 10 }
          }
        }
      }
    }
  });
})();
</script>

RocksDB's maximum latencies exceed 100ms on heavy write workloads (sequential writes, large values, small values), while TidesDB keeps worst-case latencies dramatically lower there. For sequential writes, RocksDB's 235ms max latency versus TidesDB's 5.5ms represents a **43x improvement** - the largest tail latency gap in the benchmarks.

**Latency Consistency (Coefficient of Variation - lower is better)**

| Workload | TidesDB CV | RocksDB CV | TidesDB Advantage |
|----------|------------|------------|-------------------|
| Sequential Write | 27.82% | 273.48% | **9.8x more consistent** |
| Random Write | 34.56% | 128.81% | **3.7x more consistent** |
| Random Read | 160.77% | 54.28% | **RocksDB 3.0x more consistent** |
| Zipfian Seek | 159.59% | 55.11% | **RocksDB 2.9x more consistent** |

Write-heavy workloads show tighter distributions for TidesDB in this run, while read/seek workloads show higher variance for TidesDB. The write-path consistency likely benefits from:
- Lock-free data structures that reduce blocking on concurrent operations
- Predictable background compaction that avoids sudden I/O storms
- CPU-forward design that reduces disk-induced latency spikes

For write-heavy, latency-sensitive applications like real-time analytics, gaming backends, or financial systems, this predictability is often more valuable than raw throughput.

## Summary

TidesDB 7 (v7.3.0) demonstrates quite substantial performance advantages over RocksDB 10 (v10.9.1) across the vast majority of workloads tested:

**Write Performance**
- **3.07x faster** sequential writes
- **1.25x faster** random writes  
- **1.92x faster** large value (4KB) writes
- **2.13x faster** Zipfian writes
- Consistent 1.28-1.57x advantages across all batch sizes

**Read Performance**
- **1.55x faster** point lookups
- **1.52x faster** random seeks
- **1.92x faster** sequential seeks

**Range Query Performance**
- **1.26x faster** range queries (100 keys)
- **~parity** on range queries (1000 keys)
- **1.41x faster** sequential range scans

**Hot Key Performance**
- **2.13x faster** Zipfian writes
- **5.00x faster** Zipfian seeks
- **2.01x faster** Zipfian mixed workloads
- **1.92x faster** Zipfian iteration
- **Up to 85% smaller** databases for hot key workloads

**Resource Efficiency**
- **14-25% less** disk I/O on write-heavy workloads
- **15-25% lower** write amplification on most write workloads
- **7-85% smaller** databases depending on workload

**Latency Consistency**
- Write workloads show tighter latency distributions (up to 9.8x more consistent)
- **Up to 43x better** maximum latencies on write-heavy workloads

TidesDB has been showing itself as a true high-performance alternative to RocksDB, particularly for CPU-rich deployments where throughput and write-path latency consistency are paramount. The engine leads most of the 23 workloads, with performance ratios ranging from **0.94x (slower)** to **5.00x faster**, tail latency improvements up to **43x** on write-heavy workloads, lower write amplification on most write tests, and smaller databases in most cases.  

I hope you take the time to try out TidesDB!

*Thanks for reading!*

---

- GitHub · https://github.com/tidesdb/tidesdb
- Design deep-dive · https://tidesdb.com/getting-started/how-does-tidesdb-work
- Benchmark tool · https://github.com/tidesdb/benchtool

Join the TidesDB Discord for more updates and discussions at https://discord.gg/tWEmjR66cy

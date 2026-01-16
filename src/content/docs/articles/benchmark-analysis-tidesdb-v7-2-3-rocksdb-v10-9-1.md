---
title: "TidesDB v7.2.3 & RocksDB v10.9.1 Benchmark Analysis"
description: "Comprehensive performance benchmarks comparing TidesDB v7.2.3 and RocksDB v10.9.1."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-wendywei-1662597.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-wendywei-1662597.jpg
---

<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/chartjs-chart-error-bars@4.4.0/build/index.umd.min.js"></script>

<div class="article-image">

![TidesDB v7.2.3 & RocksDB v10.9.1 Benchmark Analysis](/pexels-wendywei-1662597.jpg)

</div>


*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on January 15th, 2026*

Following the recent v7.2.3 release, I ran another comprehensive benchmark suite comparing TidesDB against RocksDB <a href="https://github.com/facebook/rocksdb/releases/tag/v10.9.1">v10.9.1</a>. This article presents detailed performance analysis of TidesDB <a href="https://github.com/tidesdb/tidesdb/releases/tag/v7.2.3">v7.2.3</a>, which includes additional performance optimizations and stability improvements. Both engines are configured with _sync disabled_ to measure the absolute performance ceiling.


## Test Configuration

The test environment used 8 threads across various workloads with 16-byte keys and 100-byte values as the baseline configuration. Tests were conducted on the same hardware to ensure fair comparison.

**We recommend you benchmark your own use case to determine which storage engine is best for your needs!**

**Hardware**
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)
- Ubuntu 24.04 LTS

**Software Versions**
- **TidesDB v7.2.3**
- **RocksDB v10.9.1**
- GCC with -O3 optimization

**Default Test Configuration**
- **Sync Mode** · DISABLED (maximum performance)
- **Default Batch Size** · 1000 operations
- **Threads** · 8 concurrent threads
- **Key Size** · 16 bytes
- **Value Size** · 100 bytes

*Large Value tests use 256-byte keys with 4KB values; Small Value tests use 16-byte keys with 64-byte values.*

You can download the raw benchtool report <a href="/tidesdb723_rocksdb1091.txt" download>here</a>

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
    'Zipfian Seek',
    'Random Seek',
    'Random Read',
    'Delete (batch=1000)',
    'Random Write',
    'Batch=10 Write',
    'Mixed (GET)',
    'Sequential Seek',
    'Batch=100 Write',
    'Small Value (64B)',
    'Range Query (100)',
    'Large Value (4KB)',
    'Batch=1 Write'
  ];
  
  // TidesDB throughput in K ops/sec
  const tidesdbData = [7147.6, 3235.1, 1365.4, 2923.0, 2883.7, 2425.2, 2644.8, 1477.3, 1727.2, 2974.1, 1817.5, 471.8, 301.2, 1028.3];
  // RocksDB throughput in K ops/sec  
  const rocksdbData = [2272.8, 619.1, 916.7, 1361.5, 3092.4, 1434.1, 1554.9, 1353.6, 1818.7, 2026.8, 1412.9, 443.2, 140.3, 851.9];
  
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: workloads,
      datasets: [{
        label: 'TidesDB v7.2.3',
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
    'Zipfian Seek',
    'Sequential Write',
    'Large Value (4KB)',
    'Random Write',
    'Batch=10 Write',
    'Random Read',
    'Random Seek',
    'Batch=100 Write',
    'Small Value (64B)',
    'Batch=1 Write',
    'Mixed (GET)',
    'Range Query (100)',
    'Sequential Seek',
    'Delete (batch=1000)'
  ];
  
  const ratios = [5.22, 3.14, 2.15, 1.69, 1.70, 2.15, 1.49, 1.47, 1.29, 1.21, 1.09, 1.06, 0.95, 0.93];
  
  const colors = ratios.map(r => r >= 1 ? 'rgba(174, 199, 232, 0.8)' : 'rgba(255, 187, 120, 0.8)');
  const borderColors = ratios.map(r => r >= 1 ? 'rgba(174, 199, 232, 1)' : 'rgba(255, 187, 120, 1)');
  
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: workloads,
      datasets: [{
        label: 'TidesDB / RocksDB Ratio',
        data: ratios,
        backgroundColor: colors,
        borderColor: borderColors,
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
              if (value > 1) {
                return 'TidesDB ' + value.toFixed(2) + 'x faster';
              } else {
                return 'RocksDB ' + (1/value).toFixed(2) + 'x faster';
              }
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
            text: 'Throughput Ratio',
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
              size: 12
            },
            color: '#b4bfd8ff'
          }
        }
      }
    }
  });
  
  // Add baseline annotation
  const chart = Chart.getChart(ctx);
  if (chart) {
    chart.options.plugins.annotation = {
      annotations: {
        line1: {
          type: 'line',
          xMin: 1,
          xMax: 1,
          borderColor: baselineColor,
          borderWidth: 2,
          borderDash: [5, 5],
          label: {
            display: true,
            content: 'Equal Performance',
            position: 'end'
          }
        }
      }
    };
  }
})();
</script>

## Sequential Write Performance

The first test measures pure sequential write throughput with 10M operations and batch size of 1000.

**Results**

| Engine | Throughput (ops/sec) | Duration (sec) | Avg Latency (μs) | p99 Latency (μs) | Max Latency (μs) | CV (%) |
|--------|---------------------|----------------|------------------|------------------|------------------|---------|
| TidesDB | 7,147,575 | 1.399 | 1,028 | 1,798 | 4,019 | 26.25 |
| RocksDB | 2,272,751 | 4.400 | 3,519 | 4,848 | 364,824 | 348.92 |
| **Ratio** | **3.14x** | | | | | |

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
      labels: ['TidesDB v7.2.3', 'RocksDB v10.9.1'],
      datasets: [{
        label: 'Sequential Write Throughput',
        data: [7147.6, 2272.8],
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
        legend: { display: false },
        tooltip: {
          callbacks: {
            label: function(context) {
              return (context.parsed.y / 1000).toFixed(2) + 'M ops/sec';
            }
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
          ticks: {
            callback: function(value) {
              if (value >= 1000) return (value / 1000).toFixed(1) + 'M';
              return value;
            },
            color: '#b4bfd8ff'
          }
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

TidesDB achieves 3.14x higher throughput with dramatically better tail latencies. RocksDB's maximum latency of 364ms versus TidesDB's 4ms reveals vastly different consistency profiles. The coefficient of variation tells the story: TidesDB at 26.25% versus RocksDB's 348.92%. This means RocksDB exhibits highly unpredictable performance with occasional extreme outliers.

Write amplification comparison:
- **TidesDB** · 1.08x
- **RocksDB** · 1.43x

TidesDB's 32% lower write amplification matters significantly for write-heavy workloads where every byte written translates to storage wear and I/O overhead.

Database sizes after 10M writes:
- **TidesDB** · 110.66 MB
- **RocksDB** · 207.93 MB

TidesDB achieves **47% smaller database size**, demonstrating superior space efficiency.

## Random Write Performance

Random writes are significantly harder than sequential writes. Here's 10M random write operations with batch size of 1000:

**Results**

| Engine | Throughput (ops/sec) | Avg Latency (μs) | p99 Latency (μs) | Max Latency (μs) | CV (%) |
|--------|---------------------|------------------|------------------|------------------|--------|
| TidesDB | 2,425,226 | 3,006 | 6,160 | 7,356 | 39.26 |
| RocksDB | 1,434,122 | 5,577 | 6,641 | 1,200,202 | 630.40 |
| **Ratio** | **1.69x** | | | | |

<div class="chart-container" style="max-width: 800px; margin: 40px auto;">
  <canvas id="randWriteChart"></canvas>
</div>

<script>
(function() {
  const ctx = document.getElementById('randWriteChart');
  if (!ctx) return;
  
  const isDarkMode = document.documentElement.classList.contains('dark') || 
                     window.matchMedia('(prefers-color-scheme: dark)').matches;
  const gridColor = isDarkMode ? 'rgba(255, 255, 255, 0.15)' : 'rgba(0, 0, 0, 0.1)';
  
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['TidesDB v7.2.3', 'RocksDB v10.9.1'],
      datasets: [{
        label: 'Random Write Throughput',
        data: [2425.2, 1434.1],
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
          text: 'Random Write Throughput (K ops/sec)',
          font: { size: 16, weight: 'bold' },
          color: '#b4bfd8ff'
        },
        legend: { display: false },
        tooltip: {
          callbacks: {
            label: function(context) {
              return (context.parsed.y / 1000).toFixed(2) + 'M ops/sec';
            }
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
          ticks: {
            callback: function(value) {
              if (value >= 1000) return (value / 1000).toFixed(1) + 'M';
              return value;
            },
            color: '#b4bfd8ff'
          }
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

The gap narrows to 1.69x but TidesDB still dominates. More interesting is the latency distribution - RocksDB hits **1.2 seconds** on the max latency while TidesDB stays under 8ms. That 630% coefficient of variation for RocksDB indicates wildly unpredictable performance with severe tail latency spikes.

Write amplification:
- **TidesDB** · 1.12x
- **RocksDB** · 1.32x

Database size:
- **TidesDB** · 90.29 MB (smaller)
- **RocksDB** · 116.55 MB

## Random Read Performance

10M random read operations from a pre-populated database:

**Results**

| Engine | Throughput (ops/sec) | Avg Latency (μs) | p50 (μs) | p95 (μs) | p99 (μs) | Max (μs) |
|--------|---------------------|------------------|----------|----------|----------|----------|
| TidesDB | 2,923,033 | 2.53 | 2.00 | 4.00 | 5.00 | 913 |
| RocksDB | 1,361,479 | 5.54 | 5.00 | 10.00 | 14.00 | 4,049 |
| **Ratio** | **2.15x** | | | | | |

<div class="chart-container" style="max-width: 900px; margin: 40px auto;">
  <canvas id="readLatencyChart"></canvas>
</div>

<script>
(function() {
  const ctx = document.getElementById('readLatencyChart');
  if (!ctx) return;
  
  const isDarkMode = document.documentElement.classList.contains('dark') || 
                     window.matchMedia('(prefers-color-scheme: dark)').matches;
  const gridColor = isDarkMode ? 'rgba(255, 255, 255, 0.15)' : 'rgba(0, 0, 0, 0.1)';
  
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['p50', 'p95', 'p99', 'Average', 'Max'],
      datasets: [{
        label: 'TidesDB v7.2.3',
        data: [2.00, 4.00, 5.00, 2.53, 913],
        backgroundColor: 'rgba(174, 199, 232, 0.8)',
        borderColor: 'rgba(174, 199, 232, 1)',
        borderWidth: 2
      }, {
        label: 'RocksDB v10.9.1',
        data: [5.00, 10.00, 14.00, 5.54, 4049],
        backgroundColor: 'rgba(255, 187, 120, 0.8)',
        borderColor: 'rgba(255, 187, 120, 1)',
        borderWidth: 2
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'Random Read Latency Distribution (μs)',
          font: { size: 16, weight: 'bold' },
          color: '#b4bfd8ff'
        },
        legend: {
          display: true,
          position: 'top',
          labels: { color: '#88a0c7ff', font: { size: 12 } }
        },
        tooltip: {
          callbacks: {
            label: function(context) {
              return context.dataset.label + ': ' + context.parsed.y.toFixed(2) + 'μs';
            }
          }
        }
      },
      scales: {
        y: {
          type: 'logarithmic',
          title: {
            display: true,
            text: 'Latency (μs, log scale)',
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

TidesDB delivers **2.15x higher throughput** with **sub-microsecond p50 latency** (2μs vs 5μs). The consistency is remarkable - TidesDB's p99 latency of 5μs means 99% of reads complete in under 5 microseconds. RocksDB's maximum latency of 4ms versus TidesDB's 913μs shows 4.4x better tail behavior.

This performance comes from TidesDB's optimized block cache and efficient skip list implementation with early termination in the read path.

## Seek Performance (Block Index Effectiveness)

Seek operations test the efficiency of block index lookups. These benchmarks measure how quickly the engine can position an iterator at a specific key.

### Random Seek

5M random seek operations:
- **TidesDB** · 1,365,406 ops/sec
- **RocksDB** · 916,721 ops/sec
- **Advantage** · **1.49x faster**

Average latency · 5.41μs vs 7.69μs

### Sequential Seek

5M sequential seek operations:
- **TidesDB** · 1,727,162 ops/sec
- **RocksDB** · 1,818,731 ops/sec
- **Advantage** · 0.95x (RocksDB 1.05x faster)

RocksDB shows a _slight_ edge on sequential seeks, likely due to its level-based organization benefiting sequential access patterns.

### Zipfian Seek (Hot Keys)

5M seek operations with Zipfian distribution (~660K unique keys):
- **TidesDB** · 3,235,109 ops/sec
- **RocksDB** · 619,098 ops/sec
- **Advantage** · **5.22x faster**

Average latency · 1.39μs vs 11.97μs

<div class="chart-container" style="max-width: 900px; margin: 40px auto;">
  <canvas id="seekChart"></canvas>
</div>

<script>
(function() {
  const ctx = document.getElementById('seekChart');
  if (!ctx) return;
  
  const isDarkMode = document.documentElement.classList.contains('dark') || 
                     window.matchMedia('(prefers-color-scheme: dark)').matches;
  const gridColor = isDarkMode ? 'rgba(255, 255, 255, 0.15)' : 'rgba(0, 0, 0, 0.1)';
  
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Random Seek', 'Sequential Seek', 'Zipfian Seek'],
      datasets: [{
        label: 'TidesDB v7.2.3',
        data: [1365.4, 1727.2, 3235.1],
        backgroundColor: 'rgba(174, 199, 232, 0.8)',
        borderColor: 'rgba(174, 199, 232, 1)',
        borderWidth: 2
      }, {
        label: 'RocksDB v10.9.1',
        data: [916.7, 1818.7, 619.1],
        backgroundColor: 'rgba(255, 187, 120, 0.8)',
        borderColor: 'rgba(255, 187, 120, 1)',
        borderWidth: 2
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'Seek Performance Comparison (K ops/sec)',
          font: { size: 16, weight: 'bold' },
          color: '#b4bfd8ff'
        },
        legend: {
          display: true,
          position: 'top',
          labels: { color: '#88a0c7ff', font: { size: 12 } }
        },
        tooltip: {
          callbacks: {
            label: function(context) {
              return context.dataset.label + ': ' + (context.parsed.y / 1000).toFixed(2) + 'M ops/sec';
            }
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
          ticks: {
            callback: function(value) {
              if (value >= 1000) return (value / 1000).toFixed(1) + 'M';
              return value;
            },
            color: '#b4bfd8ff'
          }
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

The **5.22x advantage on Zipfian seeks** is the largest performance gap in all benchmarks. Hot keys consolidated into fewer SSTables by TidesDB's Spooky compaction means fewer file seeks and dramatically better cache hit rates. Each seek operation uses the block index to jump directly to the appropriate SSTable block, and TidesDB's aggressive compaction of hot keys makes this extraordinarily efficient.

The Zipfian mixed workload (50/50 read/write with hot keys) shows similarly dominant results:
- **PUT** · 3,117,438 vs 1,523,813 ops/sec (**2.05x faster**)
- **GET** · 2,910,674 vs 1,799,383 ops/sec (**1.62x faster**)
- **Database size** · 10.21 MB vs 65.39 MB (**84% smaller!**)

Database sizes after Zipfian workload:
- **TidesDB** · 10.24 MB
- **RocksDB** · 37.37 MB

TidesDB achieves **73% smaller database** by consolidating hot keys. This dramatic space efficiency comes from Spooky compaction's ability to recognize and merge frequently-accessed keys into optimally-sized SSTables.

## Mixed Workload (50/50 Read/Write)

5M total operations (2.5M reads, 2.5M writes) with random keys:

**Write Performance**
- **TidesDB** · 2,608,626 ops/sec
- **RocksDB** · 2,037,379 ops/sec
- **Advantage** · 1.28x faster

**Read Performance**
- **TidesDB** · 1,477,318 ops/sec
- **RocksDB** · 1,353,572 ops/sec
- **Advantage** · 1.09x faster

Read latency breakdown
- Average · 4.93μs vs 5.39μs
- p99 · 16μs vs 15μs
- Max · 3,769μs vs 4,030μs

TidesDB shows faster throughput on both reads and writes in this balanced workload, demonstrating strong performance across mixed access patterns. The coefficient of variation for reads is 91.30% vs 67.32%, showing RocksDB has tighter consistency in this particular workload, though TidesDB still maintains competitive tail latencies.

## Delete Performance

### Batched Deletes (batch=1000)

5M delete operations in batches of 1000:
- **TidesDB** · 2,883,676 ops/sec
- **RocksDB** · 3,092,427 ops/sec
- **Advantage** · 0.93x (RocksDB 1.07x faster)

Average latency · 2,640μs vs 2,586μs

Write amplification:
- **TidesDB** · 0.18x
- **RocksDB** · 0.29x

Both engines perform similarly since deletes are tombstone writes. RocksDB shows a slight edge in throughput, but TidesDB's **38% lower write amplification** demonstrates more efficient tombstone compaction.

### Unbatched Deletes (batch=1)

5M individual delete operations:
- **TidesDB** · 1,142,446 ops/sec
- **RocksDB** · 917,000 ops/sec
- **Advantage** · **1.25x faster**

Average latency · 6.76μs vs 8.59μs

Without batching, TidesDB's lock-free architecture provides clearer advantages with 25% higher throughput.

<div class="chart-container" style="max-width: 800px; margin: 40px auto;">
  <canvas id="deleteChart"></canvas>
</div>

<script>
(function() {
  const ctx = document.getElementById('deleteChart');
  if (!ctx) return;
  
  const isDarkMode = document.documentElement.classList.contains('dark') || 
                     window.matchMedia('(prefers-color-scheme: dark)').matches;
  const gridColor = isDarkMode ? 'rgba(255, 255, 255, 0.15)' : 'rgba(0, 0, 0, 0.1)';
  
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Batch=1', 'Batch=100', 'Batch=1000'],
      datasets: [{
        label: 'TidesDB v7.2.3',
        data: [1142.4, 2715.4, 2883.7],
        backgroundColor: 'rgba(174, 199, 232, 0.8)',
        borderColor: 'rgba(174, 199, 232, 1)',
        borderWidth: 2
      }, {
        label: 'RocksDB v10.9.1',
        data: [917.0, 2489.2, 3092.4],
        backgroundColor: 'rgba(255, 187, 120, 0.8)',
        borderColor: 'rgba(255, 187, 120, 1)',
        borderWidth: 2
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'Delete Performance by Batch Size (K ops/sec)',
          font: { size: 16, weight: 'bold' },
          color: '#b4bfd8ff'
        },
        legend: {
          display: true,
          position: 'top',
          labels: { color: '#88a0c7ff', font: { size: 12 } }
        },
        tooltip: {
          callbacks: {
            label: function(context) {
              return context.dataset.label + ': ' + (context.parsed.y / 1000).toFixed(2) + 'M ops/sec';
            }
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
          ticks: {
            callback: function(value) {
              if (value >= 1000) return (value / 1000).toFixed(1) + 'M';
              return value;
            },
            color: '#b4bfd8ff'
          }
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

## Range Queries

### 100-Key Range Scans

1M range queries, each returning 100 consecutive keys:

**Sequential Keys**
- **TidesDB** · 471,836 ops/sec
- **RocksDB** · 443,209 ops/sec
- **Advantage** · **1.06x faster**

Average latency · 16.20μs vs 17.65μs

**Random Keys**
- **TidesDB** · 366,062 ops/sec
- **RocksDB** · 298,534 ops/sec
- **Advantage** · **1.23x faster**

Average latency · 20.17μs vs 26.33μs

### 1000-Key Range Scans

500K range queries, each returning 1000 consecutive keys:
- **TidesDB** · 50,022 ops/sec
- **RocksDB** · 47,349 ops/sec
- **Advantage** · **1.06x faster**

Average latency · 156.57μs vs 165.47μs

<div class="chart-container" style="max-width: 800px; margin: 40px auto;">
  <canvas id="rangeChart"></canvas>
</div>

<script>
(function() {
  const ctx = document.getElementById('rangeChart');
  if (!ctx) return;
  
  const isDarkMode = document.documentElement.classList.contains('dark') || 
                     window.matchMedia('(prefers-color-scheme: dark)').matches;
  const gridColor = isDarkMode ? 'rgba(255, 255, 255, 0.15)' : 'rgba(0, 0, 0, 0.1)';
  
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['100 Keys (Sequential)', '100 Keys (Random)', '1000 Keys'],
      datasets: [{
        label: 'TidesDB v7.2.3',
        data: [471.8, 366.1, 50.0],
        backgroundColor: 'rgba(174, 199, 232, 0.8)',
        borderColor: 'rgba(174, 199, 232, 1)',
        borderWidth: 2
      }, {
        label: 'RocksDB v10.9.1',
        data: [443.2, 298.5, 47.3],
        backgroundColor: 'rgba(255, 187, 120, 0.8)',
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
          labels: { color: '#88a0c7ff', font: { size: 12 } }
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
          ticks: { color: '#b4bfd8ff', font: { size: 10 } }
        }
      }
    }
  });
})();
</script>

TidesDB shows consistent advantages across range queries of different sizes, with particularly strong performance on random range scans (1.23x faster). The improved skip list iterator in v7.2.3 contributes to these results.

## Batch Size Impact

Testing 10M write operations with varying batch sizes:

| Batch Size | TidesDB (ops/sec) | RocksDB (ops/sec) | Ratio |
|------------|-------------------|-------------------|-------|
| 1 (no batch) | 1,028,337 | 851,915 | **1.21x** |
| 10 | 2,644,832 | 1,554,934 | **1.70x** |
| 100 | 2,974,076 | 2,026,814 | **1.47x** |
| 1000 | 2,425,226 | 1,434,122 | **1.69x** |

<div class="chart-container" style="max-width: 900px; margin: 40px auto;">
  <canvas id="batchChart"></canvas>
</div>

<script>
(function() {
  const ctx = document.getElementById('batchChart');
  if (!ctx) return;
  
  const isDarkMode = document.documentElement.classList.contains('dark') || 
                     window.matchMedia('(prefers-color-scheme: dark)').matches;
  const gridColor = isDarkMode ? 'rgba(255, 255, 255, 0.15)' : 'rgba(0, 0, 0, 0.1)';
  
  new Chart(ctx, {
    type: 'line',
    data: {
      labels: ['1', '10', '100', '1000'],
      datasets: [{
        label: 'TidesDB v7.2.3',
        data: [1028.3, 2644.8, 2974.1, 2425.2],
        borderColor: 'rgba(174, 199, 232, 1)',
        backgroundColor: 'rgba(174, 199, 232, 0.2)',
        borderWidth: 3,
        tension: 0.1,
        fill: true
      }, {
        label: 'RocksDB v10.9.1',
        data: [851.9, 1554.9, 2026.8, 1434.1],
        borderColor: 'rgba(255, 187, 120, 1)',
        backgroundColor: 'rgba(255, 187, 120, 0.2)',
        borderWidth: 3,
        tension: 0.1,
        fill: true
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
          labels: { color: '#88a0c7ff', font: { size: 12 } }
        },
        tooltip: {
          callbacks: {
            label: function(context) {
              return context.dataset.label + ': ' + (context.parsed.y / 1000).toFixed(2) + 'M ops/sec';
            }
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
          ticks: {
            callback: function(value) {
              if (value >= 1000) return (value / 1000).toFixed(1) + 'M';
              return value;
            },
            color: '#b4bfd8ff'
          }
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

TidesDB **outperforms RocksDB across all batch sizes**, with advantages ranging from 1.21x to 1.70x. The largest gap appears at batch size 10, where TidesDB's optimized batch write path shows its strength.

Average latency patterns:
- Batch=1 · 7.44μs vs 9.10μs (TidesDB **18% better**)
- Batch=10 · 28.94μs vs 51.35μs (TidesDB **44% better**)
- Batch=100 · 261.53μs vs 394.56μs (TidesDB **34% better**)
- Batch=1000 · 3,006μs vs 5,577μs (TidesDB **46% better**)

The consistency advantage is even more pronounced. Coefficient of variation comparison:
- Batch=1 · 565.61% vs 1182.35%
- Batch=10 · 188.90% vs 3905.97%
- Batch=100 · 125.16% vs 1017.94%
- Batch=1000 · 39.26% vs 630.40%

RocksDB shows extreme variability at smaller batch sizes with CV exceeding 1000%, while TidesDB maintains much tighter distributions.

## Large Value Performance

1M write operations with 256-byte keys and 4KB values:
- **TidesDB** · 301,211 ops/sec
- **RocksDB** · 140,257 ops/sec
- **Advantage** · **2.15x faster**

Average latency · 23,958μs vs 56,938μs  
p99 latency · 59,775μs vs 603,365μs (10x better!)

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
      labels: ['TidesDB v7.2.3', 'RocksDB v10.9.1'],
      datasets: [{
        label: 'Large Value Write Throughput',
        data: [301.2, 140.3],
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

The 2.15x advantage on large values is impressive. More striking is the tail latency difference - RocksDB's p99 hitting 603ms versus TidesDB's 60ms represents a **10x improvement**. The coefficient of variation tells the consistency story: 32.41% vs 183.81%.

Write amplification:
- **TidesDB** · 1.05x
- **RocksDB** · 1.21x

Database size:
- **TidesDB** · 302.03 MB (13% smaller)
- **RocksDB** · 346.71 MB

TidesDB's key-value separation architecture excels with larger values, keeping keys in SSTables while storing values efficiently.

## Small Value Performance

50M write operations with 16-byte keys and 64-byte values:
- **TidesDB** · 1,817,450 ops/sec
- **RocksDB** · 1,412,926 ops/sec
- **Advantage** · **1.29x faster**

Average latency · 4,297μs vs 5,662μs  
Max latency · 266ms vs 1,863ms (7x better!)

Write amplification:
- **TidesDB** · 1.19x
- **RocksDB** · 1.53x

Database size:
- **TidesDB** · 514.18 MB (12% larger)
- **RocksDB** · 459.50 MB

On small values, TidesDB trades slightly higher space usage for better throughput and dramatically better write amplification (29% lower).

## Iteration Performance

Full database iteration speeds after various workloads:

### Write Workloads
- Sequential write (10M keys) · 8.03M vs 5.18M (**1.55x faster**)
- Random write (10M keys) · 3.03M vs 3.99M (0.76x slower)
- Zipfian write (658K keys) · 3.65M vs 0.95M (**3.86x faster**)

### Read Workloads
- Random read (10M keys) · 8.25M vs 5.81M (**1.42x faster**)

### Mixed Workloads
- 50/50 mixed (5M keys) · 2.98M vs 4.52M (0.66x slower)

TidesDB shows exceptional iteration performance on sequential and Zipfian workloads. The **3.86x advantage on Zipfian iteration** demonstrates how Spooky compaction's aggressive consolidation of hot keys dramatically improves scan performance.

## Resource Usage

### Memory Consumption (Peak RSS)

TidesDB uses **more memory** in most scenarios, which aligns with its transient, memory-optimized design:
- 10M sequential write · 2,478 MB vs 2,748 MB (10% less)
- 10M random write · 2,486 MB vs 2,713 MB (8% less)
- 1M large values · 3,393 MB vs 1,210 MB (180% more)
- 50M small values · 8,911 MB vs 8,483 MB (5% more)
- 10M random read · 1,690 MB vs 294 MB (475% more)

The high memory usage on reads reflects TidesDB's aggressive caching strategy for maximum read performance.

### Disk I/O

Disk writes (MB written):
- 10M sequential · 1,200 MB vs 1,585 MB (**24% less**)
- 10M random · 1,236 MB vs 1,462 MB (**15% less**)
- 1M large values · 4,363 MB vs 5,011 MB (**13% less**)
- 50M small values · 4,531 MB vs 5,831 MB (**22% less**)

TidesDB consistently writes **13-24% less data to disk**, reducing SSD wear and improving throughput.

### CPU Utilization

TidesDB shows higher CPU utilization in most workloads:
- Sequential writes · 501% vs 281% (1.78x higher)
- Random writes · 540% vs 277% (1.95x higher)
- Random reads · 530% vs 648% (0.82x lower)

The higher CPU usage reflects TidesDB's lock-free algorithms trading CPU cycles for reduced lock contention. On highly parallel workloads with available CPU cores, this trade-off delivers higher throughput.

## Tail Latency · Where TidesDB Truly Shines

One of the most striking differences between TidesDB and RocksDB is **tail latency behavior**. While average throughput tells part of the story, maximum latencies reveal how each engine handles worst-case scenarios - critical for applications requiring predictable performance.

**Maximum Latency Comparison (lower is better)**

| Workload | TidesDB Max | RocksDB Max | TidesDB Advantage |
|----------|-------------|-------------|-------------------|
| Sequential Write | 4,019 μs | 364,824 μs | **91x better** |
| Random Write | 7,356 μs | 1,200,202 μs | **163x better** |
| Batch=10 Write | 32,301 μs | 436,487 μs | **14x better** |
| Batch=100 Write | 42,867 μs | 298,039 μs | **7x better** |
| Small Value (64B) | 266,008 μs | 1,863,272 μs | **7x better** |
| Large Value (4KB) | 107,425 μs | 848,767 μs | **8x better** |

RocksDB's maximum latencies frequently exceed 1 second, while TidesDB keeps worst-case latencies under 300ms in all tested scenarios. For random writes, RocksDB's 1.2-second max latency versus TidesDB's 7ms represents a **163x improvement** - the largest tail latency gap in all benchmarks.

This consistency comes from TidesDB's architecture:
- Lock-free data structures eliminate blocking on concurrent operations
- Predictable and background compaction avoids sudden I/O storms
- Memory and CPU optimized design reduces disk-induced latency spikes

For latency-sensitive applications like real-time analytics, gaming backends, or financial systems, this predictability is often more valuable than raw throughput.

## Summary

TidesDB v7.2.3 demonstrates absolutely **substantial** performance advantages over RocksDB v10.9.1 across the majority of workloads tested:

**Write Performance**
- **3.14x faster** sequential writes
- **1.69x faster** random writes  
- **2.15x faster** large value (4KB) writes
- Consistent 1.21-1.70x advantages across all batch sizes

**Read Performance**
- **2.15x faster** point lookups
- **1.49x faster** random seeks
- Sub-microsecond p50 latency (2μs)

**Hot Key Excellence**
- **5.22x faster** Zipfian seeks (largest advantage across all benchmarks)
- **3.86x faster** Zipfian iteration
- **73% smaller** databases for hot key workloads

**Resource Efficiency**
- **13-32% lower** write amplification
- **13-24% less** disk I/O
- **5-47% smaller** databases for most workloads

**Latency Consistency**
- Dramatically tighter latency distributions (CV 26-630% better)
- **10x better** p99 latencies on large values
- **Up to 163x better** maximum latencies (random writes: 7ms vs 1.2 seconds)
- No extreme tail latency spikes across all workloads

**Where RocksDB Leads**
- Batched deletes (1.07x faster)
- Sequential seeks (1.05x faster)
- Memory efficiency (3-6x less RAM in some workloads)
- Some iteration workloads (random writes, mixed)

The choice between engines depends on your workload characteristics and constraints. TidesDB excels at:
- **Write-heavy workloads** requiring high throughput
- **Hot key patterns** (social feeds, caching, analytics)
- **Point lookup** and **seek operations**
- Scenarios where **latency consistency** is critical
- Applications that can **trade transient memory for performance**

RocksDB remains competitive for:
- **Memory-constrained** environments
- Workloads favoring **sequential access patterns**
- Applications requiring **minimal resource footprint**

The v7.2.3 release solidifies TidesDB's position as a high-performance alternative to RocksDB, particularly for transient, memory-rich deployments where throughput and latency consistency are paramount.

*Thanks for reading!*

---

- GitHub · https://github.com/tidesdb/tidesdb
- Design deep-dive · https://tidesdb.com/getting-started/how-does-tidesdb-work
- Benchmark tool · https://github.com/tidesdb/benchtool

Join the TidesDB Discord for more updates and discussions at https://discord.gg/tWEmjR66cy
---
title: "TidesDB 7 vs RocksDB 10 Under Sync Mode"
description: "Comprehensive performance benchmarks comparing TidesDB v7.1.0 and RocksDB v10.7.5 with durable writes enabled."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-eliat-3579203-5985116.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-eliat-3579203-5985116.jpg
---

<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>

<div class="article-image">

![TidesDB 7 vs RocksDB 10 Under Sync Mode](/pexels-eliat-3579203-5985116.jpg)

</div>


*by Alex Gaetano Padula*

*published on January 8th, 2026*

A question that comes up often I see online and in the community is, "How do these engines like TidesDB or RocksDB perform under full sync?", thus in this article we will compare TidesDB against RocksDB with full sync mode enabled, essentially testing durable writes that guarantee data persistence on disk. This represents a more critical benchmark for production systems where data loss is unacceptable.

Unlike our previous benchmarks with sync disabled, these tests measure real-world performance under the constraint of durability. Every write operation must reach stable storage before acknowledging completion. This creates a fundamentally different performance profile where I/O characteristics dominate over CPU efficiency.

## Test Configuration

All benchmarks were executed with _sync mode enabled_ to measure performance under durable write guarantees. The test environment used 8 threads across various workloads with 16-byte keys and 100-byte values as the baseline configuration. Tests were conducted on the same hardware to ensure fair comparison.

**We recommend you benchmark your own use case to determine which storage engine is best for your needs!**

**Hardware**
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)
- Ubuntu 24.04 LTS

**Software Versions**
- **TidesDB v7.1.0**
- **RocksDB v10.7.5**
- GCC with -O3 optimization

**Test Configuration**
- **Sync Mode** · ENABLED (durable writes)
- **Default Batch Size** · 100 operations
- **Threads** · 8 concurrent threads
- **Key Size** · 16 bytes (unless specified)
- **Value Size** · 100 bytes (unless specified)

You can download the raw benchtool report <a href="/benchmark_results_synced_tdb710_rdb1075.txt" download>here</a>

You can find the **benchtool** source code <a href="https://github.com/tidesdb/benchtool" target="_blank">here</a> and run your own benchmarks!

## Performance Overview

<div style="max-width: 900px; margin: 40px auto;">
  <canvas id="radarChart"></canvas>
</div>

<script>
(function() {
  const ctx = document.getElementById('radarChart');
  if (!ctx) return;
  
  const isDarkMode = document.documentElement.classList.contains('dark') || 
                     window.matchMedia('(prefers-color-scheme: dark)').matches;
  const gridColor = isDarkMode ? 'rgba(255, 255, 255, 0.2)' : 'rgba(0, 0, 0, 0.1)';
  
  new Chart(ctx, {
    type: 'radar',
    data: {
      labels: [
        'Sequential Write',
        'Random Write',
        'Random Read',
        'Large Value Write',
        'Small Value Write',
        'Random Seek',
        'Range Query',
        'Batch Write (1000)'
      ],
      datasets: [{
        label: 'TidesDB v7.1.0',
        data: [239.0, 215.8, 3460, 58.2, 218.6, 4410, 259.2, 532.0],
        backgroundColor: 'rgba(59, 130, 246, 0.2)',
        borderColor: 'rgba(59, 130, 246, 1)',
        borderWidth: 3,
        pointBackgroundColor: 'rgba(59, 130, 246, 1)',
        pointBorderColor: '#fff',
        pointHoverBackgroundColor: '#fff',
        pointHoverBorderColor: 'rgba(59, 130, 246, 1)',
        pointRadius: 5,
        pointHoverRadius: 7
      }, {
        label: 'RocksDB v10.7.5',
        data: [267.4, 176.3, 3220, 18.7, 180.1, 2750, 215.7, 308.9],
        backgroundColor: 'rgba(239, 68, 68, 0.2)',
        borderColor: 'rgba(239, 68, 68, 1)',
        borderWidth: 3,
        pointBackgroundColor: 'rgba(239, 68, 68, 1)',
        pointBorderColor: '#fff',
        pointHoverBackgroundColor: '#fff',
        pointHoverBorderColor: 'rgba(239, 68, 68, 1)',
        pointRadius: 5,
        pointHoverRadius: 7
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: true,
      aspectRatio: 1.2,
      plugins: {
        title: {
          display: true,
          text: 'Performance Profile Comparison (K ops/sec)',
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
            pointStyle: 'circle'
          }
        },
        tooltip: {
          callbacks: {
            label: function(context) {
              let label = context.dataset.label || '';
              if (label) {
                label += ': ';
              }
              const value = context.parsed.r;
              if (value >= 1000) {
                label += (value / 1000).toFixed(2) + 'M ops/sec';
              } else {
                label += value.toFixed(1) + 'K ops/sec';
              }
              return label;
            }
          }
        }
      },
      scales: {
        r: {
          beginAtZero: true,
          grid: {
            color: gridColor
          },
          angleLines: {
            color: gridColor
          },
          ticks: {
            stepSize: 1000,
            callback: function(value) {
              if (value >= 1000) {
                return (value / 1000).toFixed(0) + 'M';
              }
              return value + 'K';
            },
            font: {
              size: 11
            },
            //color: '#b4bfd8ff'
          },
          pointLabels: {
            font: {
              size: 12,
              weight: '600'
            },
            color: '#b4bfd8ff'
          }
        }
      }
    }
  });
})();
</script>

<div style="max-width: 1200px; margin: 60px auto;">
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
    'Large Value (4KB)',
    'Random Seek',
    'Batch=1000 Write',
    'Random Write',
    'Small Value (64B)',
    'Range Query (100)',
    'Random Read',
    'Mixed Read',
    'Zipfian Read',
    'Sequential Write',
    'Delete',
    'Mixed Write',
    'Zipfian Write'
  ];
  
  const ratios = [
    3.11,  // Large Value
    1.60,  // Random Seek
    1.72,  // Batch 1000
    1.22,  // Random Write
    1.21,  // Small Value
    1.20,  // Range Query
    1.07,  // Random Read
    1.22,  // Mixed Read
    1.13,  // Zipfian Read
    0.89,  // Sequential Write
    0.89,  // Delete
    0.82,  // Mixed Write
    0.85   // Zipfian Write
  ];
  
  const colors = ratios.map(r => 
    r >= 1.5 ? 'rgba(34, 197, 94, 0.8)' :    // Strong green
    r >= 1.1 ? 'rgba(59, 130, 246, 0.8)' :   // Blue
    r >= 0.95 ? 'rgba(156, 163, 175, 0.8)' : // Gray (tie)
    'rgba(239, 68, 68, 0.8)'                 // Red (RocksDB wins)
  );
  
  const borderColors = ratios.map(r => 
    r >= 1.5 ? 'rgba(34, 197, 94, 1)' :
    r >= 1.1 ? 'rgba(59, 130, 246, 1)' :
    r >= 0.95 ? 'rgba(156, 163, 175, 1)' :
    'rgba(239, 68, 68, 1)'
  );
  
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: workloads,
      datasets: [{
        label: 'TidesDB / RocksDB Performance Ratio',
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
      aspectRatio: 1.5,
      plugins: {
        title: {
          display: true,
          text: 'TidesDB Performance Advantage (Ratio > 1.0 = TidesDB Faster)',
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
              const ratio = context.parsed.x;
              if (ratio >= 1.0) {
                return `TidesDB ${ratio.toFixed(2)}x faster`;
              } else {
                return `RocksDB ${(1/ratio).toFixed(2)}x faster`;
              }
            }
          }
        }
      },
      scales: {
        x: {
          beginAtZero: false,
          min: 0.5,
          max: 3.5,
          title: {
            display: true,
            text: 'Performance Ratio (TidesDB / RocksDB)',
            font: {
              size: 14,
              weight: 'bold'
            },
            color: '#b4bfd8ff'
          },
          grid: {
            color: function(context) {
              if (context.tick.value === 1.0) {
                return baselineColor;
              }
              return gridColor;
            },
            lineWidth: function(context) {
              if (context.tick.value === 1.0) {
                return 2;
              }
              return 1;
            }
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
          title: {
            display: true,
            text: 'Workload Type',
            font: {
              size: 14,
              weight: 'bold'
            },
            color: '#b4bfd8ff'
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

<div style="max-width: 450px; margin: 60px auto;">
  <canvas id="summaryChart"></canvas>
</div>

<div style="max-width: 450px; margin: 60px auto;">
  <canvas id="spaceComparisonChart"></canvas>
</div>

<script>
(function() {
  const ctx = document.getElementById('summaryChart');
  if (!ctx) return;
  
  new Chart(ctx, {
    type: 'doughnut',
    data: {
      labels: ['TidesDB Wins', 'RocksDB Wins', 'Tie'],
      datasets: [{
        data: [9, 4, 0],
        backgroundColor: [
          'rgba(34, 197, 94, 0.8)',
          'rgba(239, 68, 68, 0.8)',
          'rgba(156, 163, 175, 0.8)'
        ],
        borderColor: [
          'rgba(34, 197, 94, 1)',
          'rgba(239, 68, 68, 1)',
          'rgba(156, 163, 175, 1)'
        ],
        borderWidth: 3
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: true,
      aspectRatio: 1,
      plugins: {
        title: {
          display: true,
          text: 'Overall Performance Summary',
          font: {
            size: 18,
            weight: 'bold'
          },
          color: '#b4bfd8ff',
          padding: {
            top: 10,
            bottom: 20
          }
        },
        legend: {
          display: true,
          position: 'bottom',
          align: 'center',
          labels: {
            font: {
              size: 13
            },
            color: '#b4bfd8ff',
            padding: 15,
            boxWidth: 15,
            boxHeight: 15,
            generateLabels: function(chart) {
              const data = chart.data;
              return data.labels.map((label, i) => ({
                text: `${label}: ${data.datasets[0].data[i]} workloads`,
                fillStyle: data.datasets[0].backgroundColor[i],
                strokeStyle: data.datasets[0].borderColor[i],
                lineWidth: 2,
                hidden: false,
                index: i,
                fontColor: '#b4bfd8ff'
              }));
            }
          }
        },
        tooltip: {
          callbacks: {
            label: function(context) {
              const total = context.dataset.data.reduce((a, b) => a + b, 0);
              const percentage = ((context.parsed / total) * 100).toFixed(1);
              return `${context.label}: ${context.parsed} (${percentage}%)`;
            }
          }
        }
      }
    }
  });
})();
</script>

<script>
(function() {
  const ctx = document.getElementById('spaceComparisonChart');
  if (!ctx) return;
  
  new Chart(ctx, {
    type: 'doughnut',
    data: {
      labels: ['TidesDB Avg DB Size', 'RocksDB Avg DB Size'],
      datasets: [{
        data: [1, 10],
        backgroundColor: [
          'rgba(34, 197, 94, 0.8)',
          'rgba(251, 146, 60, 0.8)'
        ],
        borderColor: [
          'rgba(34, 197, 94, 1)',
          'rgba(251, 146, 60, 1)'
        ],
        borderWidth: 3
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: true,
      aspectRatio: 1,
      plugins: {
        title: {
          display: true,
          text: 'Space Efficiency (10x Advantage)',
          font: {
            size: 18,
            weight: 'bold'
          },
          color: '#b4bfd8ff',
          padding: {
            top: 10,
            bottom: 20
          }
        },
        legend: {
          display: true,
          position: 'bottom',
          align: 'center',
          labels: {
            font: {
              size: 13
            },
            color: '#b4bfd8ff',
            padding: 15,
            boxWidth: 15,
            boxHeight: 15
          }
        },
        tooltip: {
          callbacks: {
            label: function(context) {
              if (context.dataIndex === 0) {
                return 'TidesDB · 0.10x space amplification';
              } else {
                return 'RocksDB · 1.03x space amplification';
              }
            }
          }
        }
      }
    }
  });
})();
</script>

<div style="max-width: 1200px; margin: 60px auto;">
  <canvas id="mixedChart"></canvas>
</div>

<script>
(function() {
  const ctx = document.getElementById('mixedChart');
  if (!ctx) return;
  
  const isDarkMode = document.documentElement.classList.contains('dark') || 
                     window.matchMedia('(prefers-color-scheme: dark)').matches;
  const gridColor = isDarkMode ? 'rgba(255, 255, 255, 0.2)' : 'rgba(0, 0, 0, 0.1)';
  
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Sequential', 'Random', 'Large Value', 'Small Value', 'Batch=1000'],
      datasets: [{
        type: 'bar',
        label: 'TidesDB Throughput (K ops/sec)',
        data: [239.0, 215.8, 58.2, 218.6, 532.0],
        backgroundColor: 'rgba(59, 130, 246, 0.7)',
        borderColor: 'rgba(59, 130, 246, 1)',
        borderWidth: 2,
        yAxisID: 'y'
      }, {
        type: 'bar',
        label: 'RocksDB Throughput (K ops/sec)',
        data: [267.4, 176.3, 18.7, 180.1, 308.9],
        backgroundColor: 'rgba(239, 68, 68, 0.7)',
        borderColor: 'rgba(239, 68, 68, 1)',
        borderWidth: 2,
        yAxisID: 'y'
      }, {
        type: 'line',
        label: 'TidesDB p99 Latency (μs)',
        data: [4304, 8366, 18165, 7712, null],
        borderColor: 'rgba(168, 85, 247, 1)',
        backgroundColor: 'rgba(168, 85, 247, 0.1)',
        borderWidth: 3,
        pointRadius: 6,
        pointHoverRadius: 8,
        yAxisID: 'y1',
        tension: 0.3
      }, {
        type: 'line',
        label: 'RocksDB p99 Latency (μs)',
        data: [4165, 7980, 54921, 7980, null],
        borderColor: 'rgba(236, 72, 153, 1)',
        backgroundColor: 'rgba(236, 72, 153, 0.1)',
        borderWidth: 3,
        pointRadius: 6,
        pointHoverRadius: 8,
        yAxisID: 'y1',
        tension: 0.3
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: true,
      aspectRatio: 2,
      interaction: {
        mode: 'index',
        intersect: false
      },
      plugins: {
        title: {
          display: true,
          text: 'Write Performance · Throughput vs Latency Trade-offs',
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
              size: 12
            },
            color: '#b4bfd8ff',
            padding: 15,
            usePointStyle: true
          }
        },
        tooltip: {
          callbacks: {
            label: function(context) {
              let label = context.dataset.label || '';
              if (label) {
                label += ': ';
              }
              if (context.dataset.type === 'line') {
                label += context.parsed.y ? context.parsed.y.toLocaleString() + 'μs' : 'N/A';
              } else {
                label += context.parsed.y.toFixed(1) + 'K ops/sec';
              }
              return label;
            }
          }
        }
      },
      scales: {
        y: {
          type: 'linear',
          display: true,
          position: 'left',
          grid: {
            color: gridColor
          },
          title: {
            display: true,
            text: 'Throughput (K ops/sec)',
            font: {
              size: 14,
              weight: 'bold'
            },
            color: '#b4bfd8ff'
          },
          ticks: {
            callback: function(value) {
              return value.toFixed(0) + 'K';
            },
            color: '#b4bfd8ff'
          }
        },
        y1: {
          type: 'logarithmic',
          display: true,
          position: 'right',
          title: {
            display: true,
            text: 'p99 Latency (μs, log scale)',
            font: {
              size: 14,
              weight: 'bold'
            },
            color: '#b4bfd8ff'
          },
          grid: {
            drawOnChartArea: false
          },
          ticks: {
            callback: function(value) {
              return value.toLocaleString() + 'μs';
            },
            color: '#b4bfd8ff'
          }
        },
        x: {
          grid: {
            color: gridColor
          },
          title: {
            display: true,
            text: 'Write Workload Type',
            font: {
              size: 14,
              weight: 'bold'
            },
            color: '#b4bfd8ff'
          },
          ticks: {
            color: '#b4bfd8ff'
          }
        }
      }
    }
  });
})();
</script>

### Key Insights from Charts

**TidesDB Advantages**
- **1.22x faster** · random writes (215.8K vs 176.3K ops/sec)
- **3.11x faster** · large value writes (58.2K vs 18.7K ops/sec)
- **1.60x faster** · random seeks (4.41M vs 2.75M ops/sec)
- **10x better** · space efficiency on average (0.10x vs 1.03x amplification)
- **1.72x faster** · at batch size 1000 (532K vs 308.9K ops/sec)
- **6x faster** · Zipfian iteration (6.36M vs 1.06M ops/sec)

**RocksDB Advantages**
- **1.12x faster** · sequential writes (267.4K vs 239.0K ops/sec)
- **1.22x faster** · mixed workload writes (206.4K vs 169.0K ops/sec)
- **1.13x faster** · deletes (199.9K vs 177.5K ops/sec)
- **1.61x better** · at batch size 1 (4.04K vs 2.50K ops/sec)

## Sequential Write Performance

Sequential writes under sync mode showed RocksDB with a clear advantage: 267.4K ops/sec versus TidesDB's 239.0K ops/sec (0.89x slower for TidesDB). The latency distribution revealed the cost of durability: TidesDB achieved p50 of 2695μs and p99 of 4304μs, while RocksDB showed similar characteristics at p50 of 2745μs and p99 of 4165μs.

The performance gap is notable but not dramatic. With sync enabled, both engines become I/O bound rather than CPU bound. The key difference lies in how efficiently each engine batches writes to minimize fsync overhead. TidesDB's batch size of 100 created 418ms of total operation time versus RocksDB's 374ms - an 11% difference that directly translates to the throughput gap.

Write amplification favored TidesDB slightly (1.20x vs 1.11x), but the real story is in space amplification: TidesDB at 0.10x versus RocksDB at 1.03x - a **10x space advantage**. TidesDB produced a 1.13 MB database versus RocksDB's 11.39 MB. Under sync mode, TidesDB's adaptive and rather aggressive compaction and efficient compact SSTable formats become critical advantages.

Resource utilization showed interesting patterns. TidesDB consumed 38.9% CPU versus RocksDB's 45.8%, indicating both engines spent most time waiting on I/O. Memory footprint favored TidesDB (43.88 MB vs 55.61 MB), with dramatically lower VMS (594 MB vs 1235 MB).

## Random Write Performance

Random writes are the traditional weak point for LSM-trees, but TidesDB performed well under sync mode: 215.8K ops/sec versus RocksDB's 176.3K ops/sec - a **1.22x advantage**. This mirrors the async mode results where TidesDB also led by 1.18x.

The latency distribution revealed TidesDB's superior consistency: p50 of 2849μs and p99 of 8366μs, with coefficient of variation (CV) of 42.96%. RocksDB showed higher variation in its latency profile under sync mode, suggesting less predictable write completion times.

The durability constraint fundamentally changes the performance equation. TidesDB's write path is optimized for batch commits, and the default batch size of 100 operations allows it to amortize fsync overhead more effectively than RocksDB. CPU utilization supported this: TidesDB at 44.2% versus RocksDB's 35.3%, indicating TidesDB spent more time processing batches and less time blocked on I/O.

Space amplification remained TidesDB's strength (0.10x vs 1.03x), producing a 1.09 MB database versus RocksDB's 11.39 MB. Write amplification was comparable (1.20x vs 1.11x), showing both engines handle random writes efficiently at the logical level.

## Random Read Performance

Point lookups showed TidesDB at 3.46M ops/sec versus RocksDB at 3.22M ops/sec (1.07x faster). The latency numbers are exceptional for both engines: TidesDB achieved p50 of 2μs and p99 of 3μs, while RocksDB showed p50 of 1μs and p99 of 14μs.

The latency distribution is revealing. TidesDB showed higher coefficient of variation (730.14% vs 137.09%), indicating more variability in read latencies. RocksDB's tighter distribution suggests more consistent cache behavior, but TidesDB's higher median throughput indicates better overall read path efficiency.

Memory usage diverged significantly. TidesDB peaked at 39.34 MB RSS versus RocksDB's 27.41 MB during reads. The VMS difference was more dramatic (594 MB vs 1231 MB), but this is virtual memory allocation rather than physical usage. CPU utilization was extreme for both engines (453.3% for TidesDB vs 417.7% for RocksDB), showing effective multi-core parallelization.

Database size after compaction favored TidesDB (1.09 MB vs 1.62 MB), indicating better compression and space efficiency. The iteration performance showed TidesDB at 7.70M ops/sec versus RocksDB's 7.39M ops/sec, a modest advantage.

## Mixed Workload Performance

The 50/50 read/write mix revealed interesting trade-offs. TidesDB writes performed at 169.0K ops/sec versus RocksDB's 206.4K ops/sec (0.82x slower), but reads showed TidesDB at 7.05M ops/sec versus RocksDB's 5.80M ops/sec (1.22x faster).

This divergence is expected under mixed workloads with sync enabled. RocksDB's write path handles concurrent operations more smoothly when durability is enforced, likely due to better internal queueing and batch management. TidesDB's write latency showed p50 of 3684μs versus RocksDB's 3185μs, supporting this interpretation.

However, TidesDB's read performance advantage is striking. The 1.22x throughput gain with p50 latency of 1μs versus RocksDB's 2μs suggests TidesDB's read path suffers less interference from concurrent writes. This is valuable in production systems where read latency predictability matters.

Resource utilization showed TidesDB at 47.6% CPU versus RocksDB's 62.0%, with lower memory footprint (30.88 MB vs 38.07 MB). Space amplification remained TidesDB's strength (0.10x vs 1.03x), producing a 0.54 MB database versus RocksDB's 5.72 MB.

## Zipfian Workload Performance

Zipfian distributions simulate real-world access patterns where a small subset of keys receives most operations. This is where architectural decisions reveal themselves most clearly.

For write-only Zipfian patterns, TidesDB achieved 181.8K ops/sec versus RocksDB's 214.8K ops/sec (0.85x slower). The modest disadvantage under writes reversed completely for iteration: TidesDB at 5.41M ops/sec versus RocksDB's 1.08M ops/sec - a 5.01x advantage. With only 4,609 unique keys, TidesDB's compaction strategy excels at consolidating hot key updates.

The mixed Zipfian workload showed even better results for TidesDB. Writes achieved 164.0K ops/sec versus RocksDB's 102.7K ops/sec (1.60x faster), reads at 4.06M ops/sec versus RocksDB's 3.59M ops/sec (1.13x faster), and iteration at 6.36M ops/sec versus RocksDB's 1.06M ops/sec (6.00x faster).

These results validate TidesDB's design for hot key scenarios. When key space is concentrated, TidesDB's compaction merges overlapping ranges aggressively and efficiently, reducing read amplification dramatically. Database sizes confirm this: TidesDB at 0.07 MB versus RocksDB at 5.72 MB - an **81x space advantage**.

CPU utilization was lower for TidesDB (52.1% vs 52.3%), but the throughput advantage suggests better per-operation efficiency when locality is high. Write amplification remained comparable (1.20x vs 1.11x), while space amplification showed TidesDB at 0.01x versus RocksDB's 1.03x.

## Delete Performance

Delete operations showed RocksDB at 199.9K ops/sec versus TidesDB's 177.5K ops/sec (0.89x slower for TidesDB). The latency distribution was mixed: TidesDB had better p50 (3064μs vs 3176μs), but RocksDB had significantly better p99 (8392μs vs 33,255μs).

The p99 latency outlier for TidesDB suggests occasional write stalls during delete-heavy workloads under sync mode. This is likely due to compaction triggering during delete operations, creating temporary throughput degradation. The coefficient of variation supports this (106.32% for TidesDB vs 52.29% for RocksDB).

Write amplification for deletes showed TidesDB at 0.38x versus RocksDB's 0.23x, indicating RocksDB wrote fewer bytes per delete operation. This seems counterintuitive given the throughput disadvantage, but it reflects TidesDB's delete tombstone handling - fewer immediate writes with deferred compaction cleanup.

Database size after deletes showed TidesDB at 0.89 MB versus RocksDB's 1.71 MB, suggesting TidesDB's compaction eventually reclaims more space from tombstones. Memory usage was comparable (25.45 MB vs 22.86 MB RSS).

## Large Value Performance (4KB)

Large value writes with 256-byte keys and 4KB values showed TidesDB dominating: 58.2K ops/sec versus RocksDB's 18.7K ops/sec - a 3.11x advantage. This is an exceptional result under sync mode where I/O patterns matter most.

The latency distribution confirmed TidesDB's superiority: p50 of 13,080μs and p99 of 18,165μs versus RocksDB's p50 of 15,961μs and p99 of 54,921μs. TidesDB showed much lower variation (CV of 18.68% vs 131.86%), indicating more predictable large write completion.

With large values, batch efficiency becomes critical. TidesDB's ability to group large value writes into efficient disk operations created a 3x throughput advantage. CPU utilization reflected this: TidesDB at 128.1% versus RocksDB's 40.2%, showing TidesDB maximized I/O parallelism while RocksDB remained blocked.

Write amplification was nearly perfect for both engines (1.00x vs 1.01x), but space amplification favored TidesDB (0.07x vs 1.00x). TidesDB produced a 3.04 MB database versus RocksDB's 41.60 MB - a **13.7x space advantage** that becomes critical when storing large values at scale.

Iteration performance showed TidesDB at 1.80M ops/sec versus RocksDB's 4.30M ops/sec (0.42x slower). This suggests RocksDB's SSTable format is more efficient for sequential scans of large values, despite worse write performance.

## Small Value Performance (64B)

Small value writes with 64-byte values showed TidesDB at 218.6K ops/sec versus RocksDB's 180.1K ops/sec (1.21x faster). This confirms TidesDB's write advantage persists across value sizes under sync mode.

Latency remained competitive: TidesDB p50 of 2745μs and p99 of 7712μs versus RocksDB's p50 of 3050μs and p99 of 7980μs. The coefficient of variation was similar (45.31% vs 48.73%), indicating comparable consistency.

Write amplification was slightly higher for TidesDB (1.32x vs 1.16x) with small values, suggesting the overhead of TidesDB's SSTable format is more pronounced when values are smaller. Space amplification remained favorable (0.14x vs 1.04x), producing a 1.10 MB database versus RocksDB's 7.96 MB.

CPU utilization was moderate (41.7% vs 38.5%), showing both engines remained I/O bound even with smaller values. Memory usage favored TidesDB (40.75 MB vs 52.79 MB RSS).

## Batch Size Impact

Testing different batch sizes revealed how sync mode performance scales with batching efficiency.

Batch Size 1 (unbatched) · TidesDB achieved 2.50K ops/sec versus RocksDB's 4.04K ops/sec (0.62x slower). This is the worst-case scenario where every operation requires an fsync. The latency showed TidesDB p50 of 2188μs versus RocksDB's 1698μs, indicating RocksDB's fsync implementation is more efficient.

Write amplification was extreme for both engines (27.05x for TidesDB vs 7.61x for RocksDB), but TidesDB suffered more. With no batching, TidesDB wrote 29.92 MB for 10K operations versus RocksDB's 8.42 MB - a **3.6x write amplification disadvantage**.

Batch Size 10 · TidesDB at 26.1K ops/sec versus RocksDB's 33.6K ops/sec (0.78x slower). Performance improved 10x from batch=1, but RocksDB maintained its advantage. Write amplification decreased to 3.09x versus RocksDB's 1.77x.

Batch Size 100 · TidesDB at 176.0K ops/sec versus RocksDB's 174.1K ops/sec (1.01x faster). This is the crossover point where TidesDB's batch optimization matched RocksDB. Write amplification normalized to 1.18x versus 1.12x.

Batch Size 1000 · TidesDB at 532.0K ops/sec versus RocksDB's 308.9K ops/sec (1.72x faster). At large batch sizes, TidesDB dominated completely. The latency distribution favored TidesDB: p50 of 9544μs versus RocksDB's 16,735μs. Write amplification was minimal (1.07x vs 1.05x).

The batch size results reveal TidesDB's design philosophy: optimize for batched operations at the expense of single-operation efficiency. In production systems with write-ahead logging and group commits, batch sizes of 100-1000 are common, making TidesDB's architecture advantageous.

## Delete Batch Size Impact

Delete operations showed similar batch size sensitivity.

Batch Size 1 · TidesDB at 3.08K ops/sec versus RocksDB's 3.64K ops/sec (0.85x slower). Write amplification was extreme (32.71x vs 6.52x), showing TidesDB's tombstone mechanism is inefficient without batching.

Batch Size 100 · TidesDB at 215.3K ops/sec versus RocksDB's 218.8K ops/sec (0.98x, essentially tied). Write amplification improved dramatically (0.40x vs 0.25x).

Batch Size 1000 · TidesDB at 845.8K ops/sec versus RocksDB's 790.8K ops/sec (1.07x faster). At maximum batch size, TidesDB's delete path outperformed RocksDB. Write amplification was minimal (0.20x vs 0.17x).

The delete batch results mirror the write pattern · TidesDB requires batching to achieve competitive performance. For applications with high delete rates and low batch sizes, RocksDB may be preferable.

## Seek Performance

Seek operations test the efficiency of iterator creation and block index traversal.

Random Seek · TidesDB achieved 4.41M ops/sec versus RocksDB's 2.75M ops/sec - a 1.60x advantage. The latency distribution showed TidesDB p50 of 1μs and p99 of 2μs versus RocksDB's p50 of 2μs and p99 of 19μs.

This is a dramatic win for TidesDB. The v7.x series includes iterator caching optimizations that avoid rebuilding block indices on every seek. CPU utilization was high (400.6% vs 475.9%), showing effective parallelization.

Sequential Seek · TidesDB at 5.47M ops/sec versus RocksDB's 5.87M ops/sec (0.93x slower). The advantage reversed for sequential access patterns, likely due to RocksDB's optimized sequential iterator implementation. Latency was comparable: TidesDB p50 of 1μs versus RocksDB's 1μs.

Zipfian Seek · TidesDB at 3.21M ops/sec versus RocksDB's 3.03M ops/sec (1.06x faster). With hot key access patterns, TidesDB's caching advantages returned. The smaller key space (4,551 unique keys) allowed TidesDB to cache more effectively.

## Range Query Performance

Range scans of 100 keys showed TidesDB at 259.2K ops/sec versus RocksDB's 215.7K ops/sec (1.20x faster). The latency distribution was similar: TidesDB p50 of 12μs and p99 of 68μs versus RocksDB's p50 of 14μs and p99 of 43μs.

CPU utilization was extreme (514.9% vs 433.4%), showing both engines effectively parallelized range scans across threads. Memory usage remained modest (22.52 MB vs 16.06 MB RSS).

Range scans of 1000 keys showed TidesDB at 36.7K ops/sec versus RocksDB's 36.2K ops/sec (1.01x, essentially tied). As range size increased, the performance gap narrowed. Latency was comparable: TidesDB p50 of 136μs versus RocksDB's 126μs, with p99 of 382μs versus 349μs.

Sequential Range Queries · TidesDB at 281.1K ops/sec versus RocksDB's 373.1K ops/sec (0.75x slower). RocksDB's advantage in sequential access patterns persisted for range queries. This suggests RocksDB's SSTable format is better optimized for sequential value retrieval when key order matches storage order.

## CPU Efficiency

TidesDB showed lower CPU utilization across most workloads (38-50%) versus RocksDB (35-62%), but this reflects I/O-bound behavior under sync mode rather than computational efficiency. The key metric is operations per CPU-second.

Calculating operations per CPU-second (total ops / [user time + system time]):
- Sequential writes · TidesDB 1,423K ops/CPU-sec vs RocksDB 1,516K ops/CPU-sec
- Random writes · TidesDB 1,013K ops/CPU-sec vs RocksDB 860K ops/CPU-sec
- Random reads · TidesDB 16,226K ops/CPU-sec vs RocksDB 15,561K ops/CPU-sec

For random operations, TidesDB achieved better per-CPU efficiency. For sequential writes, RocksDB maintained a slight edge. The difference is modest, suggesting both engines have well-optimized code paths under sync mode.

## Memory Footprint

Memory usage patterns showed TidesDB with generally lower RSS:
- Sequential writes · TidesDB 43.88 MB vs RocksDB 55.61 MB (0.79x)
- Random writes · TidesDB 44.00 MB vs RocksDB 55.63 MB (0.79x)
- Random reads · TidesDB 39.34 MB vs RocksDB 27.41 MB (1.43x)

TidesDB's write workloads consumed 20% less memory, while read workloads consumed 43% more. This trade-off reflects TidesDB's aggressive block index caching - memory for read speed!

Virtual memory allocation showed dramatic differences (TidesDB ~594 MB vs RocksDB ~1235 MB), but this is address space reservation rather than physical memory usage. For production deployments, RSS is the critical metric.

## Iteration Performance

Full iteration throughput showed mixed results, with TidesDB excelling in Zipfian workloads:
- Sequential writes · 7.06M ops/sec vs 9.81M ops/sec (0.72x)
- Random writes · 5.54M ops/sec vs 7.12M ops/sec (0.78x)
- Random reads · 7.70M ops/sec vs 7.39M ops/sec (1.04x)
- Zipfian writes · 5.41M ops/sec vs 1.08M ops/sec (5.01x)
- Zipfian mixed · 6.36M ops/sec vs 1.06M ops/sec (6.00x)

The Zipfian results are particularly striking. When iterating over a small key space with high update frequency, TidesDB's compaction strategy provides massive advantages by consolidating hot keys into fewer SSTables. 

## Space Amplification

TidesDB consistently achieved superior space amplification:
- Sequential writes · 0.10x vs 1.03x
- Random writes · 0.10x vs 1.03x
- Large values · 0.07x vs 1.00x
- Small values · 0.14x vs 1.04x
- Zipfian workloads · 0.01x vs 1.03x

On average, TidesDB databases were 10x smaller than RocksDB equivalents. This is a critical advantage for production systems where storage costs and I/O amplification matter.

## Write Amplification

Write amplification showed RocksDB with a slight advantage in most cases:
- Sequential writes · 1.20x vs 1.11x
- Random writes · 1.20x vs 1.11x
- Large values · 1.00x vs 1.01x (tied)
- Small values · 1.32x vs 1.16x

## How We Achieve These Numbers

### 10x Space Efficiency · Key-Value Separation

TidesDB uses a **split storage architecture** with separate `.klog` (keys + metadata) and `.vlog` (large values) files. This WiscKey-inspired design dramatically reduces write amplification during compaction since only keys are rewritten.

```c
struct tidesdb_sstable_t {
    char *klog_path;           /* keys + metadata */
    char *vlog_path;           /* large values stored separately */
    uint64_t klog_size;
    uint64_t vlog_size;
    bloom_filter_t *bloom_filter;
    tidesdb_block_index_t *block_indexes;
    ...
};
```

Values exceeding `klog_value_threshold` (default 512 bytes) are stored in the vlog with only a pointer in the klog, reducing compaction I/O by 10-100x for large values.

### Batch Write Optimization · WAL Serialization

TidesDB batches all operations *within a single transaction* into one WAL write, amortizing fsync overhead. Each commit is durable immediately - there's no cross-transaction buffering:

```c
/* all ops in txn serialized into single WAL block */
uint8_t *wal_batch = tidesdb_txn_serialize_wal(txn, cf, &wal_size);
block_manager_block_t *wal_block = block_manager_block_create(wal_size, wal_batch);
block_manager_block_write(wal, wal_block);  /* one I/O + fsync for N ops */
```

At batch size 1000 (1000 puts per transaction), TidesDB achieves **1.72x** throughput vs RocksDB because one fsync covers 1000 operations instead of 1.

### Lock-Free Clock Cache · O(1) Block Lookups

TidesDB's clock cache is fully lock-free using atomic CAS operations. Partitioned by key hash across CPU cores, each partition has its own hash index for O(1) lookups:

```c
/* partition selection via bitmask - no locks */
size_t hash_to_partition(cache, key, key_len) {
    uint64_t hash = XXH3_64bits(key, key_len);
    return hash & cache->partition_mask;  /* power-of-2 partitions */
}

/* lock-free entry claiming via CAS */
atomic_compare_exchange_strong(&entry->state, &expected, ENTRY_DELETING);
```

Multiple threads read/write different partitions simultaneously with zero contention. This enables the **1.6x random seek advantage**.

### Lock-Free Skip List · MVCC with CAS

The memtable skip list uses atomic CAS for version chain updates, allowing concurrent reads and writes without locks:

```c
/* lock-free version insertion */
static int skip_list_insert_version_cas(versions_ptr, new_version, seq, list) {
    do {
        old_head = atomic_load_explicit(versions_ptr, memory_order_acquire);
        atomic_store_explicit(&new_version->next, old_head, memory_order_relaxed);
    } while (!atomic_compare_exchange_weak_explicit(versions_ptr, &old_head, new_version,
                                                     memory_order_release, memory_order_acquire));
}
```

Readers traverse without blocking writers. Thread-local xorshift64* RNG avoids contention on level generation.

### Block Manager · Atomic Space Allocation + pwrite

The block manager uses atomic fetch-add for file offset allocation, enabling parallel writes without locks:

```c
/* atomically allocate space - multiple threads can write simultaneously */
int64_t offset = atomic_fetch_add(&bm->current_file_size, total_size);

/* pwrite is thread-safe - writes to different offsets in parallel */
pwrite(bm->fd, write_buffer, total_size, offset);
```

This means 8 threads can write 8 different blocks to the same file concurrently - each gets a unique offset atomically, then writes in parallel. Combined with stack buffers for small blocks (avoiding malloc), this explains the **3x large value write advantage**.

### Spooky · Adaptive Level Targeting

TidesDB implements the "Spooky" compaction algorithm with three merge strategies and dynamic capacity adaptation:

```c
/* spooky algo 2: find smallest level q where capacity < cumulative size */
for (int q = 1; q <= X && q < num_levels; q++) {
    size_t cumulative_size = 0;
    for (int i = 0; i <= q; i++)
        cumulative_size += cf->levels[i]->current_size;
    
    if (level_q_capacity < cumulative_size) {
        target_lvl = q;  /* merge to this level */
        break;
    }
}

/* three merge strategies based on trigger condition */
if (l1_sstable_count >= l1_threshold)
    tidesdb_dividing_merge(cf, X);  /* L1 accumulation triggers dividing merge */
else if (target_lvl < X)
    tidesdb_partitioned_merge(cf, target_lvl, X);  /* before X triggers partitioned merge */
else
    tidesdb_full_preemptive_merge(cf, target_lvl, target_lvl + 1);  /* at/beyond X triggers full preemptive */
```

Dynamic Capacity Adaptation (DCA) · adjusts level capacities based on actual data distribution:

```c
/* C[i] = N_L / T^(L-i) where N_L = largest level size, T = size ratio */
for (int i = 0; i < num_levels - 1; i++) {
    size_t new_capacity = N_L / pow(level_size_ratio, num_levels - i);
    atomic_store(&cf->levels[i]->capacity, new_capacity);
}
```

This explains the 5-6x Zipfian iteration advantage: hot keys are aggressively merged into fewer SSTables, and DCA prevents over-provisioning empty levels.

### Async Flush Pipeline · Decoupled Write Path

Memtable flushes are queued to background workers, allowing writes to continue immediately:

```c
/* enqueue flush work - returns immediately */
queue_enqueue(cf->db->flush_queue, work);

/* background worker processes asynchronously */
tidesdb_flush_work_t *work = queue_dequeue_wait(db->flush_queue);
tidesdb_sstable_write_from_memtable(db, sst, memtable);
block_manager_escalate_fsync(bms.klog_bm);  /* sync only after batch complete */
```

This pipeline enables the 3x large value write advantage by overlapping CPU work with I/O.

### Graceful Shutdown · Zero Data Loss

TidesDB guarantees no data loss on close by waiting for all background work to complete:

```c
int tidesdb_close(tidesdb_t *db) {
    /* 1. flush all active memtables with retry + backoff */
    for (each cf) {
        while (retry_count < TDB_MAX_FFLUSH_RETRY_ATTEMPTS) {
            if (tidesdb_flush_memtable_internal(cf, 0, 1) == TDB_SUCCESS) break;
            usleep(TDB_FLUSH_RETRY_BACKOFF_US * retry_count);  /* linear backoff */
        }
    }
    
    /* 2. wait for flush queue to drain */
    while (queue_size(db->flush_queue) > 0 || any_cf_is_flushing) {
        usleep(TDB_CLOSE_TXN_WAIT_SLEEP_US);
    }
    
    /* 3. wait for in-progress compactions */
    while (any_cf_is_compacting) {
        usleep(TDB_CLOSE_TXN_WAIT_SLEEP_US);
    }
    
    /* 4. signal and join all worker threads */
    atomic_store(&db->flush_queue->shutdown, 1);
    pthread_cond_broadcast(&db->flush_queue->not_empty);
    for (each thread) pthread_join(thread, NULL);
}
```

Even if flush fails after retries, data remains in WAL and is recovered on next open. This ensures durability without sacrificing performance during normal operation.

## Summary

The latest minor has shown clear advantages over RocksDB.  The choice is really up to the application, but TidesDB is a solid choice for _most_ workloads.


---

*Thanks for reading!*
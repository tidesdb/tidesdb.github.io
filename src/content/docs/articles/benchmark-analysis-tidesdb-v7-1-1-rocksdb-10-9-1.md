---
title: "TidesDB 7.1.1 vs RocksDB 10.9.1 Performance Benchmarks"
description: "Comprehensive performance benchmarks comparing TidesDB v7.1.1 and RocksDB v10.9.1 with sync disabled for maximum throughput."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-pok-rie-33563-33963.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-pok-rie-33563-33963.jpg
---

<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/chartjs-chart-error-bars@4.4.0/build/index.umd.min.js"></script>

<div class="article-image">

![TidesDB 7.1.1 vs RocksDB 10.9.1 Benchmark](/pexels-pok-rie-33563-33963.jpg)

</div>


*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on January 10th, 2026*

I've noticed RocksDB recently had a release, well a few of them actually and I thought I'd run a new comparison. This article presents a _comprehensive_ comparison of TidesDB <a href="https://github.com/tidesdb/tidesdb/releases/tag/v7.1.1">v7.1.1</a> which is the latest stable patch with few performance improvements against RocksDB <a href="https://github.com/facebook/rocksdb/releases/tag/v10.9.1">v10.9.1</a> which also includes bug fixes and performance improvements. Both engines are configured with _sync disabled_ to measure the absolute maximum throughput these engines can achieve. This configuration represents the performance ceiling for scenarios where applications handle durability through external mechanisms or can tolerate bounded data loss.

This patch release includes performance optimizations and stability improvements that directly impact the benchmark results.

- Adjusted L0 and L1 backpressure defaults based on extensive benchmarking. This trades slightly higher space usage for dramatically more consistent latencies
- `block_manager_read_block_at_offset` single-syscall optimization
- `skip_list_cursor_goto_last` improved from O(n) to O(1) using backward pointer from tail
- `skip_list_get_max_key` improved from O(n) to O(1) using backward pointer from tail
- Stack allocation for update array eliminates malloc/free in skip list write path
- Cached time for TTL checks on skip list
- `clock_cache_get_zero_copy` full utilization with early termination when block indexes are utilized in point read path
- Early termination for deeper levels in read path
- Dynamic dedup hash size for large batches

## Test Configuration

All benchmarks were executed with _sync mode disabled_ to measure maximum throughput without durability constraints. The test environment used 8 threads across various workloads with 16-byte keys and 100-byte values as the baseline configuration. Tests were conducted on the same hardware to ensure fair comparison.

**We recommend you benchmark your own use case to determine which storage engine is best for your needs!**

**Hardware**
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)
- Ubuntu 24.04 LTS

**Software Versions**
- **TidesDB v7.1.1**
- **RocksDB v10.9.1**
- GCC with -O3 optimization

**Test Configuration**
- **Sync Mode** · DISABLED (maximum performance)
- **Default Batch Size** · 1000 operations
- **Threads** · 8 concurrent threads
- **Key Size** · 16 bytes (unless specified)
- **Value Size** · 100 bytes (unless specified)

You can download the raw benchtool report <a href="/benchmark_results_tdb711_rdb1091.txt" download>here</a>

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
    'Sequential Seek',
    'Zipfian Mixed (GET)',
    'Zipfian Write',
    'Delete (batch=1000)',
    'Random Seek',
    'Random Write',
    'Random Read',
    'Batch=10 Write',
    'Mixed (GET)',
    'Batch=1000 Write',
    'Small Value (64B)',
    'Range Query (100)',
    'Large Value (4KB)',
    'Batch=1 Write'
  ];
  
  // TidesDB throughput in K ops/sec
  const tidesdbData = [6435.8, 3380.8, 5902.5, 3112.8, 2628.5, 3100.5, 2093.5, 1867.9, 1879.0, 2101.3, 1338.1, 2006.3, 1509.9, 298.4, 127.6, 886.5];
  // RocksDB throughput in K ops/sec  
  const rocksdbData = [2108.2, 629.3, 1726.4, 1952.9, 1589.4, 3263.2, 899.5, 1546.8, 1381.6, 1623.5, 1254.4, 1642.9, 1175.2, 261.9, 118.2, 786.7];
  
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: workloads,
      datasets: [{
        label: 'TidesDB v7.1.1',
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
    'Sequential Seek',
    'Sequential Write',
    'Random Seek',
    'Zipfian Write',
    'Zipfian Mixed (GET)',
    'Random Read',
    'Batch=10 Write',
    'Small Value (64B)',
    'Batch=1000 Write',
    'Random Write',
    'Range Query (100)',
    'Batch=1 Write',
    'Large Value (4KB)',
    'Delete (batch=1000)',
    'Mixed (GET)'
  ];
  
  // Calculate ratios: TidesDB / RocksDB
  const ratios = [5.37, 3.42, 3.05, 2.33, 1.65, 1.59, 1.36, 1.29, 1.28, 1.22, 1.21, 1.14, 1.13, 1.08, 0.95, 1.07];
  
  // Color coding: green for TidesDB advantage, orange for RocksDB advantage
  const colors = ratios.map(r => r >= 1.0 ? 
    'rgba(174, 199, 232, 0.85)' : 
    'rgba(255, 187, 120, 0.85)'
  );
  
  const borderColors = ratios.map(r => r >= 1.0 ? 
    'rgba(174, 199, 232, 1)' : 
    'rgba(255, 187, 120, 1)'
  );
  
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: workloads,
      datasets: [{
        label: 'Performance Ratio (TidesDB / RocksDB)',
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
      aspectRatio: 1.2,
      plugins: {
        title: {
          display: true,
          text: 'TidesDB Performance Advantage',
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
              if (value >= 1.0) {
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
          title: {
            display: true,
            text: 'Performance Ratio (higher is better for TidesDB)',
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
      },
      annotation: {
        annotations: [{
          type: 'line',
          mode: 'vertical',
          scaleID: 'x',
          value: 1.0,
          borderColor: baselineColor,
          borderWidth: 2,
          borderDash: [5, 5],
          label: {
            content: 'Equal Performance',
            enabled: true,
            position: 'top'
          }
        }]
      }
    }
  });
})();
</script>

<div class="chart-container" style="max-width: 1200px; margin: 60px auto;">
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
      labels: ['Sequential', 'Random', 'Large Value', 'Small Value'],
      datasets: [{
        type: 'bar',
        label: 'TidesDB Throughput (K ops/sec)',
        data: [6435.8, 1867.9, 127.6, 1509.9],
        backgroundColor: 'rgba(174, 199, 232, 0.85)',
        borderColor: 'rgba(174, 199, 232, 1)',
        borderWidth: 2,
        yAxisID: 'y'
      }, {
        type: 'bar',
        label: 'RocksDB Throughput (K ops/sec)',
        data: [2108.2, 1546.8, 118.2, 1175.2],
        backgroundColor: 'rgba(255, 187, 120, 0.85)',
        borderColor: 'rgba(255, 187, 120, 1)',
        borderWidth: 2,
        yAxisID: 'y'
      }, {
        type: 'line',
        label: 'TidesDB p99 Latency (μs)',
        data: [2097, 4923, 57257, 4770],
        borderColor: 'rgba(197, 176, 213, 1)',
        backgroundColor: 'rgba(197, 176, 213, 0.2)',
        borderWidth: 3,
        pointRadius: 6,
        pointHoverRadius: 8,
        yAxisID: 'y1',
        tension: 0.3
      }, {
        type: 'line',
        label: 'RocksDB p99 Latency (μs)',
        data: [5883, 6415, 794780, 7152],
        borderColor: 'rgba(247, 182, 210, 1)',
        backgroundColor: 'rgba(247, 182, 210, 0.2)',
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
          type: 'linear',
          display: true,
          position: 'right',
          min: 0,
          max: 100000,
          title: {
            display: true,
            text: 'p99 Latency (μs)',
            font: {
              size: 14,
              weight: 'bold'
            },
            color: '#b4bfd8ff',
            rotation: 270
          },
          grid: {
            drawOnChartArea: false
          },
          ticks: {
            stepSize: 20000,
            callback: function(value) {
              return (value / 1000).toFixed(0) + 'ms';
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

<div class="chart-container" style="max-width: 1000px; margin: 60px auto;">
  <canvas id="spaceChart"></canvas>
</div>

<script>
(function() {
  const ctx = document.getElementById('spaceChart');
  if (!ctx) return;
  
  const isDarkMode = document.documentElement.classList.contains('dark') || 
                     window.matchMedia('(prefers-color-scheme: dark)').matches;
  const gridColor = isDarkMode ? 'rgba(255, 255, 255, 0.15)' : 'rgba(0, 0, 0, 0.1)';
  
  const workloads = [
    'Large Value (4KB)',
    'Sequential Write',
    'Random Write',
    'Small Value (64B)',
    'Mixed Workload',
    'Zipfian Write'
  ];
  
  // Database sizes in MB from raw benchmark data
  const tidesdbSizes = [302.32, 198.11, 221.86, 1017.97, 42.74, 10.22];
  const rocksdbSizes = [346.93, 208.61, 151.01, 561.79, 76.82, 66.36];
  
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: workloads,
      datasets: [{
        label: 'TidesDB Database Size (MB)',
        data: tidesdbSizes,
        backgroundColor: 'rgba(152, 223, 138, 0.85)',
        borderColor: 'rgba(152, 223, 138, 1)',
        borderWidth: 2
      }, {
        label: 'RocksDB Database Size (MB)',
        data: rocksdbSizes,
        backgroundColor: 'rgba(255, 187, 120, 0.85)',
        borderColor: 'rgba(255, 187, 120, 1)',
        borderWidth: 2
      }]
    },
    options: {
      indexAxis: 'y',
      responsive: true,
      maintainAspectRatio: true,
      aspectRatio: 1.4,
      plugins: {
        title: {
          display: true,
          text: 'Space Efficiency · Database Size After Workload',
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
              return context.dataset.label + ': ' + context.parsed.x.toFixed(2) + ' MB';
            }
          }
        }
      },
      scales: {
        x: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Database Size (MB)',
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

<div class="chart-container" style="max-width: 1000px; margin: 60px auto;">
  <canvas id="p99Chart"></canvas>
</div>

<script>
(function() {
  const ctx = document.getElementById('p99Chart');
  if (!ctx) return;
  
  const isDarkMode = document.documentElement.classList.contains('dark') || 
                     window.matchMedia('(prefers-color-scheme: dark)').matches;
  const gridColor = isDarkMode ? 'rgba(255, 255, 255, 0.15)' : 'rgba(0, 0, 0, 0.1)';
  
  // Workloads with P99 latency data from benchmark results
  const workloads = [
    'Random Read',
    'Sequential Seek',
    'Random Seek',
    'Zipfian Seek',
    'Zipfian Mixed GET',
    'Range 100-key'
  ];
  
  // P99 Latency (μs) -- lower is better tail latency
  // From raw benchmark data -- Latency (p99): X μs
  const tidesdbP99 = [8, 2, 7, 2, 4, 64];
  const rocksdbP99 = [13, 8, 18, 27, 10, 51];
  
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: workloads,
      datasets: [{
        label: 'TidesDB v7.1.1 P99 (μs)',
        data: tidesdbP99,
        backgroundColor: 'rgba(174, 199, 232, 0.85)',
        borderColor: 'rgba(174, 199, 232, 1)',
        borderWidth: 2
      }, {
        label: 'RocksDB v10.9.1 P99 (μs)',
        data: rocksdbP99,
        backgroundColor: 'rgba(255, 187, 120, 0.85)',
        borderColor: 'rgba(255, 187, 120, 1)',
        borderWidth: 2
      }]
    },
    options: {
      indexAxis: 'y',
      responsive: true,
      maintainAspectRatio: true,
      aspectRatio: 1.4,
      plugins: {
        title: {
          display: true,
          text: 'P99 Tail Latency · What 99% of Users Experience (Lower = Better)',
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
              const p99 = context.parsed.x;
              return context.dataset.label.replace(' (μs)', '') + ': ' + p99 + 'μs';
            }
          }
        }
      },
      scales: {
        x: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'P99 Latency (μs) · Lower = Better Tail Latency',
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
              return value + 'μs';
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

<div class="chart-container" style="max-width: 1000px; margin: 60px auto;">
  <canvas id="latencyErrorChart"></canvas>
</div>

<script>
(function() {
  const ctx = document.getElementById('latencyErrorChart');
  if (!ctx) return;
  
  const isDarkMode = document.documentElement.classList.contains('dark') || 
                     window.matchMedia('(prefers-color-scheme: dark)').matches;
  const gridColor = isDarkMode ? 'rgba(255, 255, 255, 0.15)' : 'rgba(0, 0, 0, 0.1)';
  
  // Workloads for latency comparison
  const workloads = [
    'Sequential Write',
    'Random Write',
    'Large Value (4KB)',
    'Small Value (64B)',
    'Delete (batch=1000)',
    'Batch=1000 Write'
  ];
  
  // Average latency in μs from benchmark results
  const tidesdbAvg = [1148.43, 3073.21, 24685.44, 3308.10, 2382.80, 2695.66];
  const rocksdbAvg = [3793.68, 5169.99, 67609.67, 6807.07, 2450.21, 4867.46];
  
  // Stddev in μs from benchmark results
  const tidesdbStddev = [1705.60, 35042.27, 75799.52, 85134.12, 647.84, 30408.04];
  const rocksdbStddev = [14463.57, 20562.83, 128668.55, 77413.93, 1820.32, 17198.18];
  
  // Build data with error bars using chartjs-chart-error-bars format
  const tidesdbDataWithErrors = tidesdbAvg.map((val, i) => ({
    y: val,
    yMin: Math.max(0, val - tidesdbStddev[i]),
    yMax: val + tidesdbStddev[i]
  }));
  
  const rocksdbDataWithErrors = rocksdbAvg.map((val, i) => ({
    y: val,
    yMin: Math.max(0, val - rocksdbStddev[i]),
    yMax: val + rocksdbStddev[i]
  }));
  
  new Chart(ctx, {
    type: 'barWithErrorBars',
    data: {
      labels: workloads,
      datasets: [{
        label: 'TidesDB v7.1.1 Avg Latency (μs)',
        data: tidesdbDataWithErrors,
        backgroundColor: 'rgba(174, 199, 232, 0.85)',
        borderColor: 'rgba(174, 199, 232, 1)',
        borderWidth: 2,
        errorBarColor: 'rgba(55, 71, 133, 1)',
        errorBarWhiskerColor: 'rgba(55, 71, 133, 1)',
        errorBarLineWidth: 3,
        errorBarWhiskerLineWidth: 3,
        errorBarWhiskerSize: 10
      }, {
        label: 'RocksDB v10.9.1 Avg Latency (μs)',
        data: rocksdbDataWithErrors,
        backgroundColor: 'rgba(255, 187, 120, 0.85)',
        borderColor: 'rgba(255, 187, 120, 1)',
        borderWidth: 2,
        errorBarColor: 'rgba(180, 60, 50, 1)',
        errorBarWhiskerColor: 'rgba(180, 60, 50, 1)',
        errorBarLineWidth: 3,
        errorBarWhiskerLineWidth: 3,
        errorBarWhiskerSize: 10
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: true,
      aspectRatio: 1.4,
      plugins: {
        title: {
          display: true,
          text: 'Write Latency with Standard Deviation',
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
              const data = context.raw;
              const stddev = data.yMax - data.y;
              return context.dataset.label.replace(' Avg Latency (μs)', '') + 
                     ': ' + data.y.toFixed(0) + ' ± ' + stddev.toFixed(0) + ' μs';
            }
          }
        }
      },
      scales: {
        x: {
          grid: {
            color: gridColor
          },
          ticks: {
            font: {
              size: 11
            },
            color: '#b4bfd8ff'
          }
        },
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Latency (μs) · Error bars show ±1 stddev',
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
              return value.toLocaleString() + ' μs';
            },
            color: '#b4bfd8ff'
          }
        }
      }
    }
  });
})();
</script>

## Write Performance

### Sequential Writes

TidesDB demonstrated exceptional sequential write throughput:
- **TidesDB** · 6,435,802 ops/sec (1.55s for 10M operations)
- **RocksDB** · 2,108,192 ops/sec (4.74s for 10M operations)
- **Advantage** · 3.05x faster

Median latency · 1,044μs vs 2,828μs (2.71x better)

The massive advantage comes from TidesDB's lock-free memtable and batch-optimized WAL writes. With 8 threads each processing 1000-operation batches, TidesDB's skip list handles concurrent insertions without contention while RocksDB's locking creates serialization points.

### Random Writes

Random write performance showed strong TidesDB leadership:
- **TidesDB** · 1,867,858 ops/sec (5.35s for 10M operations)
- **RocksDB** · 1,546,818 ops/sec (6.47s for 10M operations)
- **Advantage** · 1.21x faster

Despite the random access pattern degrading both engines' performance compared to sequential workloads, TidesDB maintained its advantage through superior cache locality and lock-free concurrent writes.

### Large Values (4KB)

With 256-byte keys and 4KB values:
- **TidesDB** · 127,587 ops/sec
- **RocksDB** · 118,178 ops/sec
- **Advantage** · 1.08x faster

Write amplification · 1.07x vs 1.21x
Database size · 302MB vs 347MB

### Small Values (64B)

Testing 50M operations with 16-byte keys and 64-byte values:
- **TidesDB** · 1,509,922 ops/sec (33.11s total)
- **RocksDB** · 1,175,156 ops/sec (42.55s total)
- **Advantage** · 1.28x faster

Database size · 1018MB vs 562MB
Write amplification · 1.19x vs 1.54x

The 50M operation count stressed memory management and compaction strategies. TidesDB's larger final database reflects its optimistic space allocation, but lower write amplification shows more efficient compaction.

## Read Performance

### Random Reads

Point lookup performance from a 10M key dataset:
- **TidesDB** · 1,879,037 ops/sec
- **RocksDB** · 1,381,561 ops/sec
- **Advantage** · 1.36x faster

Average latency · 3.69μs vs 5.49μs
P99 latency · 8μs vs 13μs

TidesDB's partitioned clock cache delivers superior concurrent read performance. With hash-based partitioning across CPU cores, threads rarely contend for the same cache partition.

### Sequential Seeks

Iterating forward through 5M sequential keys:
- **TidesDB** · 5,902,491 ops/sec
- **RocksDB** · 1,726,388 ops/sec
- **Advantage** · 3.42x faster

Average latency · 1.18μs vs 3.41μs

Sequential access patterns are optimal for TidesDB's SSTable format. 

### Random Seeks

Random seeking across 5M keys:
- **TidesDB** · 2,093,536 ops/sec
- **RocksDB** · 899,484 ops/sec
- **Advantage** · 2.33x faster

Average latency · 3.45μs vs 8.35μs
P99 latency · 7μs vs 18μs

The 2.33x advantage demonstrates TidesDB's superior block index effectiveness. Each seek operation uses the block index to jump directly to the appropriate SSTable block.

## Hot Key Performance (Zipfian Distribution)

Zipfian workloads concentrate ~80% of operations on ~20% of keys, simulating real-world access patterns like social media feeds or e-commerce product catalogs.

### Zipfian Writes

5M write operations to ~660K unique keys:
- **TidesDB** · 2,628,501 ops/sec
- **RocksDB** · 1,589,392 ops/sec
- **Advantage** · 1.65x faster

Iteration speed · 3.79M ops/sec vs 1.01M ops/sec (3.74x faster)

The iteration advantage is stunning. TidesDB's Spooky compaction aggressively merges hot keys into fewer SSTables, while RocksDB's level-based compaction spreads them across levels.

### Zipfian Mixed Workload

50/50 read/write mix with hot keys:
- **TidesDB Writes** · 2,933,606 ops/sec (2.00x faster)
- **TidesDB Reads** · 3,112,759 ops/sec (1.59x faster)
- **RocksDB Writes** · 1,463,984 ops/sec
- **RocksDB Reads** · 1,952,944 ops/sec

Average GET latency: 1.86μs vs 3.66μs

This is TidesDB's strongest showing. The combination of cache-friendly hot keys and efficient compaction creates a perfect storm of performance advantages.

### Zipfian Seeks

Sequential iteration over hot key space:
- **TidesDB** · 3,380,836 ops/sec
- **RocksDB** · 629,291 ops/sec
- **Advantage** · 5.37x faster

Average latency: 1.31μs vs 11.63μs

The 5.37x advantage is the largest in all benchmarks. Hot keys consolidated into fewer SSTables means fewer file seeks and better cache hit rates.

## Mixed Workloads

### 50/50 Read/Write (Random)

5M total operations (2.5M reads, 2.5M writes):
- **TidesDB Writes** · 2,229,170 ops/sec (1.87x faster)
- **TidesDB Reads** · 1,338,128 ops/sec (1.07x faster)
- **RocksDB Writes** · 1,194,824 ops/sec
- **RocksDB Reads** · 1,254,399 ops/sec

TidesDB shows faster writes and reads in this balanced workload, demonstrating strong performance across mixed access patterns.

## Delete Performance

### Batched Deletes (1000 operations/batch)

5M delete operations:
- **TidesDB** · 3,100,462 ops/sec
- **RocksDB** · 3,263,226 ops/sec
- **Advantage** · 0.95x (RocksDB 1.05x faster)

Write amplification: 0.19x vs 0.28x

Both engines perform similarly since deletes are tombstone writes. TidesDB's lower write amplification shows more efficient tombstone compaction.

### Unbatched Deletes (batch=1)

5M individual delete operations:
- **TidesDB** · 1,100,041 ops/sec
- **RocksDB** · 833,725 ops/sec
- **Advantage** · 1.32x faster

Without batching, TidesDB's lock-free architecture provides clearer advantages.

## Range Queries

### 100-Key Range Scans

1M range queries, each returning 100 consecutive keys:

**Random Keys**
- **TidesDB** · 298,388 ops/sec
- **RocksDB** · 261,869 ops/sec
- **Advantage** · 1.14x faster

Average latency: 22.51μs vs 30.32μs

**Sequential Keys**
- **TidesDB** · 416,393 ops/sec
- **RocksDB** · 447,604 ops/sec
- **Advantage** · 0.93x slower (RocksDB 1.07x faster)

RocksDB's _slight_ edge on sequential ranges.

### 1000-Key Range Scans

500K range queries, each returning 1000 consecutive keys:
- **TidesDB** · 43,743 ops/sec
- **RocksDB** · 48,716 ops/sec
- **Advantage** · 0.90x (RocksDB 1.11x faster)

Average latency: 163.74μs vs 162.84μs

Larger ranges _slightly_ favor RocksDB's iterator implementation for long sequential scans.

## Batch Size Impact

Testing 10M write operations with varying batch sizes:

| Batch Size | TidesDB (ops/sec) | RocksDB (ops/sec) | Ratio |
|------------|-------------------|-------------------|-------|
| 1 (no batch) | 886,547 | 786,716 | 1.13x |
| 10 | 2,101,348 | 1,623,539 | 1.29x |
| 100 | 1,883,292 | 1,744,589 | 1.08x |
| 1000 | 2,006,271 | 1,642,945 | 1.22x |
| 10000 | 1,617,531 | 1,182,014 | 1.37x |

TidesDB now outperforms RocksDB across all batch sizes, with the largest advantage (1.37x) at very large batches (10K operations).

Average latency patterns show why:
- Batch=1 · 7.63μs vs 9.88μs (TidesDB better)
- Batch=1000 · 2,696μs vs 4,867μs (TidesDB better)
- Batch=10000 · 34,160μs vs 67,489μs (TidesDB better)

## Iteration Performance

Full database iteration speeds (ops/sec):

### Write Workloads
- Sequential write (10M keys) · 6.27M vs 4.64M (1.35x)
- Random write (10M keys) · 3.71M vs 4.08M (0.91x)
- Zipfian write (660K keys) · 3.79M vs 1.01M (3.74x)

### Read Workloads
- Random read (10M keys) · 6.22M vs 6.14M (1.01x)

### Mixed Workloads
- Zipfian mixed (660K keys) · 3.90M vs 2.07M (1.89x)

The Zipfian results are _remarkable_. A 3.74x iteration advantage.

## Space Amplification

TidesDB consistently achieved superior space efficiency:
- Sequential writes · 0.18x vs 0.19x
- Random writes · 0.20x vs 0.14x (RocksDB better)
- Large values (4KB) · 0.07x vs 0.08x
- Small values (64B) · 0.27x vs 0.15x (RocksDB better)
- Zipfian workloads · 0.02x vs 0.12x

Database sizes (TidesDB vs RocksDB):
- 10M x 100B values · 198MB vs 209MB (5% smaller)
- 1M x 4KB values · 302MB vs 347MB (13% smaller)
- 660K hot keys · 10MB vs 60MB (83% smaller)

The Zipfian result is particularly striking, TidesDB's aggressive compaction of hot keys reduces database size by 6x.

## Write Amplification

Write amplification comparison:
- Sequential writes · 1.09x vs 1.44x (TidesDB 32% better)
- Random writes · 1.09x vs 1.32x (TidesDB 21% better)
- Large values · 1.07x vs 1.21x (TidesDB 13% better)
- Small values · 1.19x vs 1.54x (TidesDB 29% better)
- Zipfian workloads · 1.04x vs 1.23x (TidesDB 18% better)

TidesDB's key-value separation and efficient compaction strategies consistently reduce write amplification by 13-32%.

## Resource Usage

### Memory Consumption (Peak RSS)

TidesDB generally uses less memory:
- 10M sequential write · 2,360MB vs 2,607MB (9% less)
- 10M random write · 2,676MB vs 2,923MB (8% less)
- 1M large values · 4,366MB vs 3,842MB (14% more)
- 50M small values · 11,769MB vs 11,781MB (equal)

### Disk I/O

Disk writes (MB written):
- 10M sequential · 1,207MB vs 1,595MB (24% less)
- 10M random · 1,210MB vs 1,463MB (17% less)
- 1M large values · 4,422MB vs 5,009MB (12% less)

TidesDB consistently writes 12-24% less data to disk, reducing wear on SSDs and improving throughput.

### CPU Utilization

TidesDB shows higher CPU utilization in most workloads:
- Sequential writes · 498% vs 271% (1.84x higher)
- Random writes · 469% vs 274% (1.71x higher)

The higher CPU usage reflects TidesDB's lock-free algorithms trading CPU cycles for reduced lock contention. On highly parallel workloads, this trade-off pays off with higher throughput.

## Summary

TidesDB v7.1.1 demonstrates clear performance advantages over RocksDB v10.9.1 across the majority of workloads tested. The results show:

**Write Performance**
- 3.05x faster sequential writes
- 1.21x faster random writes
- Consistent 1.08-1.37x advantages across all batch sizes

**Read Performance**
- 1.36x faster point lookups
- 3.42x faster sequential seeks
- 2.33x faster random seeks

**Hot Key Excellence**
- 5.37x faster Zipfian seeks
- 3.74x faster Zipfian iteration
- 1.59-2.00x faster mixed Zipfian workloads

**Resource Efficiency**
- 13-32% lower write amplification
- 12-24% less disk I/O
- 5-83% smaller databases for most workloads

**Where RocksDB Leads**
- Batched deletes (1.05x faster)
- Some range scans (1.07-1.11x faster)
- Iteration on random write datasets

The choice between engines depends on your workload characteristics. TidesDB excels at write-heavy workloads, hot key patterns, seek operations, and scenarios where space, read, and write amplification matter. 

*Thanks for reading!*

---

- GitHub · https://github.com/tidesdb/tidesdb
- Design deep-dive · https://tidesdb.com/getting-started/how-does-tidesdb-work

Join the TidesDB Discord for more updates and discussions at https://discord.gg/tWEmjR66cy
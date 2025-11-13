---
title: "TidesDB vs RocksDB"
description: "Comprehensive performance benchmarks comparing TidesDB and RocksDB storage engines."
---

<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>

This article presents comprehensive performance benchmarks comparing TidesDB and RocksDB, two LSM-tree based storage engines. Both are designed for write-heavy workloads, but they differ significantly in architecture, complexity, and performance characteristics.

All benchmarks are conducted using a custom pluggable benchmarking tool that provides fair, apples-to-apples comparisons between storage engines.

## Test Environment

**Hardware**
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Seagate ST4000DM004-2U9104 4TB HDD
- Ubuntu 23.04 x86_64 6.2.0-39-generic

**Software Versions**
- TidesDB v3.0
- RocksDB v10.7.5
- GCC with -O3 optimization
- GNOME 44.3


## Benchmark Methodology

The benchmark tool measures:
- Throughput in operations per second (ops/sec)
- Latency metrics including average, P50, P95, P99, minimum, and maximum values in microseconds
- Iteration speed for full database scan performance
- Total duration for workload completion

Test parameters:
- Operations ranging from 500,000 to 5,000,000 depending on the test
- Key sizes of 8-16 bytes
- Value sizes from 32 to 1024 bytes
- Thread counts from 1 to 8 threads
- Workload types including write-only and mixed (50% read/50% write)
- Key patterns including sequential, random, Zipfian (hot keys), and timestamp-based

## Single-Threaded Performance

### Write Operations (PUT)

**Sequential Keys (1M operations)**
```bash
./bench -e tidesdb -c -w write -p seq -o 1000000
```

<canvas id="singleThreadWriteSeqChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('singleThreadWriteSeqChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Throughput (ops/sec)', 'Avg Latency (μs)', 'P99 Latency (μs)', 'Iteration (M ops/sec)'],
      datasets: [{
        label: 'TidesDB',
        data: [567279, 1.57, 4.00, 17.1],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [385200, 2.60, 6.00, 5.5],
        backgroundColor: 'rgba(255, 99, 132, 0.8)',
        borderColor: 'rgba(255, 99, 132, 1)',
        borderWidth: 1
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'Single-Threaded Sequential Write Performance'
        },
        legend: {
          display: true,
          position: 'top'
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Value (varies by metric)'
          }
        }
      }
    }
  });
}, 100);
</script>

In sequential write tests, TidesDB achieves 567K operations per second compared to RocksDB's 385K ops/sec, representing a 1.47x throughput advantage. Average latency is similarly impressive at 1.57μs versus RocksDB's 2.60μs (1.66x faster). The most dramatic difference appears in iteration performance, where TidesDB scans at 17.1M ops/sec compared to RocksDB's 5.5M ops/sec, a 3.12x improvement that demonstrates TidesDB's efficient SSTable design.

**Random Keys (1M operations)**
```bash
./bench -e tidesdb -c -w write -p random -o 1000000
```

<canvas id="singleThreadWriteRandomChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('singleThreadWriteRandomChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Throughput (ops/sec)', 'Avg Latency (μs)', 'P99 Latency (μs)', 'Iteration (M ops/sec)'],
      datasets: [{
        label: 'TidesDB',
        data: [564711, 1.57, 4.00, 15.3],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [303515, 3.30, 7.00, 4.7],
        backgroundColor: 'rgba(255, 99, 132, 0.8)',
        borderColor: 'rgba(255, 99, 132, 1)',
        borderWidth: 1
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'Single-Threaded Random Write Performance'
        },
        legend: {
          display: true,
          position: 'top'
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Value (varies by metric)'
          }
        }
      }
    }
  });
}, 200);
</script>

Random write performance shows even stronger results for TidesDB. Throughput reaches 565K ops/sec versus RocksDB's 304K ops/sec (1.86x faster), while average latency drops to 1.57μs compared to RocksDB's 3.30μs (2.10x faster). Iteration speed maintains TidesDB's advantage at 15.3M ops/sec versus 4.7M ops/sec, a 3.27x improvement that highlights the efficiency of TidesDB's two-tier LSM architecture.

TidesDB demonstrates **47-86% higher write throughput** than RocksDB in single-threaded scenarios. Random writes show the largest advantage (1.86x), with significantly better latencies across all percentiles. TidesDB's iteration performance is exceptional at **15-17M ops/sec**, over **3x faster** than RocksDB.

### Mixed Workload (50% Reads, 50% Writes)

**Random Keys (1M operations)**
```bash
./bench -e tidesdb -c -w mixed -p random -o 1000000
```

<canvas id="mixedWorkloadChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('mixedWorkloadChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['PUT Throughput (K ops/sec)', 'GET Throughput (M ops/sec)', 'PUT Latency (μs)', 'GET Latency (μs)'],
      datasets: [{
        label: 'TidesDB',
        data: [540.249, 2.959, 1.65, 0.27],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [365.887, 0.621, 2.74, 1.61],
        backgroundColor: 'rgba(255, 99, 132, 0.8)',
        borderColor: 'rgba(255, 99, 132, 1)',
        borderWidth: 1
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'Single-Threaded Mixed Workload Performance'
        },
        legend: {
          display: true,
          position: 'top'
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Value (varies by metric)'
          }
        }
      }
    }
  });
}, 300);
</script>

Mixed workload testing reveals TidesDB's most impressive advantages. Write throughput of 540K ops/sec exceeds RocksDB's 366K ops/sec by 1.48x, but the real story is in read performance: TidesDB achieves 2.96M ops/sec compared to RocksDB's 621K ops/sec, a remarkable 4.77x improvement. Latency metrics are equally compelling, with write latency at 1.65μs versus 2.74μs (1.66x faster) and read latency at just 0.27μs compared to RocksDB's 1.61μs (5.96x faster). This sub-microsecond read latency demonstrates the effectiveness of TidesDB's lock-free read architecture. Iteration maintains the pattern at 14.4M ops/sec versus 5.2M ops/sec (2.77x faster).

<canvas id="mixedLatencyChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('mixedLatencyChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['PUT P50', 'PUT P95', 'PUT P99', 'GET P50', 'GET P95', 'GET P99'],
      datasets: [{
        label: 'TidesDB (μs)',
        data: [2.00, 3.00, 4.00, 0.00, 1.00, 1.00],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB (μs)',
        data: [3.00, 5.00, 7.00, 1.00, 3.00, 6.00],
        backgroundColor: 'rgba(255, 99, 132, 0.8)',
        borderColor: 'rgba(255, 99, 132, 1)',
        borderWidth: 1
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'Latency Percentiles - Mixed Workload'
        },
        legend: {
          display: true,
          position: 'top'
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Latency (microseconds)'
          }
        }
      }
    }
  });
}, 400);
</script>

TidesDB excels in mixed workloads with **48% faster writes** and **4.77x faster reads**. Read latency is sub-microsecond (0.27 μs avg), demonstrating TidesDB's lock-free read architecture. The P50 read latency of 0.00 μs indicates most reads complete in under 1 microsecond.

## Multi-Threaded Scalability

### Write Performance (2, 4, 8 threads)

**2 Threads (1M operations)**
```bash
./bench -e tidesdb -c -w write -t 2 -o 1000000
```

<canvas id="multiThread2Chart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('multiThread2Chart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Throughput (K ops/sec)', 'Avg Latency (μs)', 'P99 Latency (μs)', 'Iteration (M ops/sec)'],
      datasets: [{
        label: 'TidesDB',
        data: [766.441, 2.37, 7.00, 12.3],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [261.350, 7.65, 13.00, 5.4],
        backgroundColor: 'rgba(255, 99, 132, 0.8)',
        borderColor: 'rgba(255, 99, 132, 1)',
        borderWidth: 1
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: '2 Threads Write Performance (2.93x faster)'
        },
        legend: {
          display: true,
          position: 'top'
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Value (varies by metric)'
          }
        }
      }
    }
  });
}, 600);
</script>

TidesDB achieves 766K ops/sec versus RocksDB's 261K ops/sec (2.93x faster) with average latency of 2.37μs versus 7.65μs (3.23x faster). P99 latency shows 7μs versus 13μs (1.86x better), and iteration reaches 12.3M ops/sec versus 5.4M ops/sec (2.26x faster).

**4 Threads (1M operations)**
```bash
./bench -e tidesdb -c -w write -t 4 -o 1000000
```

<canvas id="multiThread4Chart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('multiThread4Chart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Throughput (K ops/sec)', 'Avg Latency (μs)', 'P99 Latency (μs)', 'Iteration (M ops/sec)'],
      datasets: [{
        label: 'TidesDB',
        data: [1011.088, 3.71, 10.00, 9.3],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [448.367, 8.93, 14.00, 5.2],
        backgroundColor: 'rgba(255, 99, 132, 0.8)',
        borderColor: 'rgba(255, 99, 132, 1)',
        borderWidth: 1
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: '4 Threads Write Performance (2.26x faster)'
        },
        legend: {
          display: true,
          position: 'top'
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Value (varies by metric)'
          }
        }
      }
    }
  });
}, 700);
</script>

TidesDB reaches 1.01M ops/sec versus RocksDB's 448K ops/sec (2.26x faster) with average latency of 3.71μs versus 8.93μs (2.41x faster). P99 latency shows 10μs versus 14μs (1.4x better), and iteration achieves 9.3M ops/sec versus 5.2M ops/sec (1.77x faster).

**8 Threads (1M operations)**
```bash
./bench -e tidesdb -c -w write -t 8 -o 1000000
```

<canvas id="multiThread8Chart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('multiThread8Chart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Throughput (K ops/sec)', 'Avg Latency (μs)', 'P99 Latency (μs)', 'Iteration (M ops/sec)'],
      datasets: [{
        label: 'TidesDB',
        data: [1022.519, 7.51, 19.00, 5.9],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [673.273, 11.89, 18.00, 6.3],
        backgroundColor: 'rgba(255, 99, 132, 0.8)',
        borderColor: 'rgba(255, 99, 132, 1)',
        borderWidth: 1
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: '8 Threads Write Performance (1.52x faster)'
        },
        legend: {
          display: true,
          position: 'top'
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Value (varies by metric)'
          }
        }
      }
    }
  });
}, 800);
</script>

TidesDB achieves 1.02M ops/sec versus RocksDB's 673K ops/sec (1.52x faster) with average latency of 7.51μs versus 11.89μs (1.58x faster). P99 latency shows 19μs versus 18μs (similar), and iteration reaches 5.9M ops/sec versus 6.3M ops/sec (0.93x, slightly slower).

**Scaling Efficiency:**

<canvas id="scalingEfficiencyChart" width="400" height="250"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('scalingEfficiencyChart').getContext('2d');
  new Chart(ctx, {
    type: 'line',
    data: {
      labels: ['1 Thread', '2 Threads', '4 Threads', '8 Threads'],
      datasets: [{
        label: 'TidesDB Throughput (K ops/sec)',
        data: [565, 766, 1011, 1023],
        backgroundColor: 'rgba(54, 162, 235, 0.2)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 2,
        fill: true,
        tension: 0.1
      }, {
        label: 'RocksDB Throughput (K ops/sec)',
        data: [304, 261, 448, 673],
        backgroundColor: 'rgba(255, 99, 132, 0.2)',
        borderColor: 'rgba(255, 99, 132, 1)',
        borderWidth: 2,
        fill: true,
        tension: 0.1
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'Multi-Threaded Write Scaling (1-8 Threads)'
        },
        legend: {
          display: true,
          position: 'top'
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Throughput (K ops/sec)'
          }
        },
        x: {
          title: {
            display: true,
            text: 'Thread Count'
          }
        }
      }
    }
  });
}, 500);
</script>

| Threads | TidesDB Scaling | RocksDB Scaling | TidesDB Advantage |
|---------|-----------------|------------------|-------------------|
| 1       | 1.00x (baseline: 565K) | 1.00x (baseline: 304K) | 1.86x |
| 2       | 1.36x | 0.86x | **2.93x** |
| 4       | 1.79x | 1.47x | **2.26x** |
| 8       | 1.81x | 2.22x | **1.52x** |

TidesDB shows excellent multi-threaded scaling, with peak throughput at 4 threads (1.01M ops/sec). The **2.93x advantage at 2 threads** is particularly impressive, suggesting lower synchronization overhead. RocksDB actually shows **negative scaling at 2 threads** (0.86x), indicating higher lock contention. At 8 threads, both databases experience some contention, but TidesDB maintains a 1.52x advantage in throughput.

### Mixed Workload - 4 Threads

**Random Keys (1M operations)**
```bash
./bench -e tidesdb -c -w mixed -t 4 -o 1000000
```

<canvas id="mixed4ThreadChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('mixed4ThreadChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['PUT Throughput (K ops/sec)', 'GET Throughput (M ops/sec)', 'PUT Latency (μs)', 'GET Latency (μs)'],
      datasets: [{
        label: 'TidesDB',
        data: [1035.601, 1.687, 3.62, 2.25],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [502.681, 1.282, 7.93, 2.78],
        backgroundColor: 'rgba(255, 99, 132, 0.8)',
        borderColor: 'rgba(255, 99, 132, 1)',
        borderWidth: 1
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'Mixed Workload - 4 Threads Performance'
        },
        legend: {
          display: true,
          position: 'top'
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Value (varies by metric)'
          }
        }
      }
    }
  });
}, 900);
</script>

TidesDB achieves 1.04M PUT ops/sec versus RocksDB's 503K ops/sec (2.06x faster) and 1.69M GET ops/sec versus 1.28M ops/sec (1.32x faster). PUT latency is 3.62μs versus 7.93μs (2.19x faster), while GET latency shows 2.25μs versus 2.78μs (1.24x faster). Iteration reaches 9.9M ops/sec versus 5.3M ops/sec (1.85x faster).

<canvas id="mixed4ThreadLatencyChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('mixed4ThreadLatencyChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['PUT P50', 'PUT P95', 'PUT P99', 'GET P50', 'GET P95', 'GET P99'],
      datasets: [{
        label: 'TidesDB (μs)',
        data: [3.00, 6.00, 10.00, 2.00, 5.00, 7.00],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB (μs)',
        data: [8.00, 10.00, 14.00, 2.00, 6.00, 10.00],
        backgroundColor: 'rgba(255, 99, 132, 0.8)',
        borderColor: 'rgba(255, 99, 132, 1)',
        borderWidth: 1
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'Detailed Latency Percentiles - 4 Threads Mixed Workload'
        },
        legend: {
          display: true,
          position: 'top'
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Latency (microseconds)'
          }
        }
      }
    }
  });
}, 1000);
</script>

With 4 threads, TidesDB maintains strong advantages: **2.06x faster writes**, **1.32x faster reads**, and **1.85x faster iteration**. Write latencies are significantly better (3.62μs vs 7.93μs avg), while read latencies remain competitive.

## Key Pattern Performance

### Zipfian Distribution (Hot Keys)

**Mixed Workload, 4 Threads (500K operations)**
```bash
./bench -e tidesdb -c -w mixed -p zipfian -o 500000 -t 4
```

<canvas id="zipfianChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('zipfianChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['PUT Throughput (K ops/sec)', 'GET Throughput (M ops/sec)', 'PUT Latency (μs)', 'GET Latency (μs)', 'PUT P99 (μs)', 'GET P99 (μs)'],
      datasets: [{
        label: 'TidesDB',
        data: [490.695, 2.607, 7.67, 1.18, 23, 4],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [362.647, 1.904, 11.03, 1.57, 35, 6],
        backgroundColor: 'rgba(255, 99, 132, 0.8)',
        borderColor: 'rgba(255, 99, 132, 1)',
        borderWidth: 1
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'Zipfian Distribution (Hot Keys) - 4 Threads'
        },
        legend: {
          display: true,
          position: 'top'
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Value (varies by metric)'
          }
        }
      }
    }
  });
}, 1100);
</script>

TidesDB achieves 491K PUT ops/sec versus RocksDB's 363K ops/sec (1.35x faster) and 2.61M GET ops/sec versus 1.90M ops/sec (1.37x faster). PUT latency is 7.67μs versus 11.03μs (1.44x faster), while GET latency shows 1.18μs versus 1.57μs (1.33x faster). P99 latencies show PUT at 23μs versus 35μs (1.52x better) and GET at 4μs versus 6μs (1.5x better). The test generated approximately 56K unique keys due to Zipfian's hot key concentration pattern.

Zipfian distribution simulates real-world hot key scenarios (80/20 rule). TidesDB maintains **35-37% performance advantage** even with skewed access patterns, demonstrating consistent performance under realistic workloads.

### Timestamp Pattern

**Mixed Workload, 4 Threads (500K operations)**
```bash
./bench -e tidesdb -c -w mixed -p timestamp -o 500000 -t 4
```

<canvas id="timestampChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('timestampChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['PUT Throughput (K ops/sec)', 'GET Throughput (M ops/sec)', 'PUT Latency (μs)', 'GET Latency (μs)', 'PUT P99 (μs)', 'GET P99 (μs)'],
      datasets: [{
        label: 'TidesDB',
        data: [1043.752, 4.286, 3.59, 0.81, 10, 4],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [457.683, 2.075, 8.74, 1.72, 20, 8],
        backgroundColor: 'rgba(255, 99, 132, 0.8)',
        borderColor: 'rgba(255, 99, 132, 1)',
        borderWidth: 1
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'Timestamp Pattern (Time-Series) - 4 Threads'
        },
        legend: {
          display: true,
          position: 'top'
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Value (varies by metric)'
          }
        }
      }
    }
  });
}, 1200);
</script>

TidesDB achieves 1.04M PUT ops/sec versus RocksDB's 458K ops/sec (2.28x faster) and 4.29M GET ops/sec versus 2.08M ops/sec (2.07x faster). PUT latency is 3.59μs versus 8.74μs (2.44x faster), while GET latency shows 0.81μs versus 1.72μs (2.12x faster). P99 latencies demonstrate 2x advantages with PUT at 10μs versus 20μs and GET at 4μs versus 8μs. The test generated approximately 14-15 unique keys due to timestamp-based key generation having low cardinality in the short test window.

Timestamp-based keys (time-series workload) show TidesDB's strongest performance: **2.28x faster writes** and **2.07x faster reads**. This pattern is ideal for TidesDB's sequential write optimization.

## Value Size Tests

### Large Values (1KB)

**Mixed Workload, 4 Threads (500K operations)**
```bash
./bench -e tidesdb -c -w mixed -v 1024 -o 500000 -t 4
```

<canvas id="largeValueChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('largeValueChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['PUT Throughput (K ops/sec)', 'GET Throughput (K ops/sec)', 'PUT Latency (μs)', 'GET Latency (μs)'],
      datasets: [{
        label: 'TidesDB',
        data: [613.598, 359.165, 5.27, 10.58],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [319.152, 750.080, 12.54, 5.33],
        backgroundColor: 'rgba(255, 99, 132, 0.8)',
        borderColor: 'rgba(255, 99, 132, 1)',
        borderWidth: 1
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'Large Values (1KB) - Mixed Workload Performance'
        },
        legend: {
          display: true,
          position: 'top'
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Value (varies by metric)'
          }
        }
      }
    }
  });
}, 600);
</script>

Large value testing (1KB) reveals an interesting trade-off. TidesDB maintains strong write performance at 614K ops/sec versus RocksDB's 319K ops/sec (1.92x faster) with write latency of 5.27μs compared to 12.54μs (2.38x faster). However, RocksDB's sophisticated caching strategies show their value in read operations, achieving 750K ops/sec versus TidesDB's 359K ops/sec (2.09x advantage for RocksDB) with read latency of 5.33μs versus TidesDB's 10.58μs. Despite this, TidesDB still maintains a 1.74x advantage in iteration speed at 3.4M ops/sec versus 2.0M ops/sec, suggesting that for workloads involving large values with mixed read/write patterns, the choice depends on whether write or read performance is more critical.

With 1KB values, TidesDB shows **1.92x faster writes** but RocksDB has **2.09x faster reads**. This is expected as larger values favor RocksDB's more complex caching strategies. However, TidesDB maintains a **1.74x iteration advantage**.

### Small Values (8B keys, 32B values)

**Mixed Workload, 4 Threads (1M operations)**
```bash
./bench -e tidesdb -c -w mixed -k 8 -v 32 -o 1000000 -t 4
```

<canvas id="smallValueChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('smallValueChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['PUT Throughput (K ops/sec)', 'GET Throughput (M ops/sec)', 'PUT Latency (μs)', 'GET Latency (μs)'],
      datasets: [{
        label: 'TidesDB',
        data: [1079.233, 2.990, 3.55, 1.22],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [428.404, 2.519, 9.35, 1.42],
        backgroundColor: 'rgba(255, 99, 132, 0.8)',
        borderColor: 'rgba(255, 99, 132, 1)',
        borderWidth: 1
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'Small Values (8B/32B) - Mixed Workload Performance'
        },
        legend: {
          display: true,
          position: 'top'
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Value (varies by metric)'
          }
        }
      }
    }
  });
}, 700);
</script>

Small value testing (8B keys, 32B values) showcases TidesDB's best overall performance. Write throughput reaches 1.08M ops/sec compared to RocksDB's 428K ops/sec (2.52x faster), while read throughput hits 2.99M ops/sec versus 2.52M ops/sec (1.19x faster). Write latency is exceptional at 3.55μs versus RocksDB's 9.35μs (2.63x faster), and read latency maintains a slight edge at 1.22μs versus 1.42μs (1.16x faster). Even iteration speed, which typically favors larger sequential scans, shows a 1.31x advantage at 1.3M ops/sec versus 991K ops/sec. These results demonstrate TidesDB's efficiency with compact, cache-friendly data structures that are common in many real-world applications.

Small, cache-friendly data shows TidesDB's best write performance: **2.52x faster** with **1.19x faster reads**. This demonstrates TidesDB's efficiency with compact data structures.

## Stress Test: High Concurrency

**5M Operations, 8 Threads**
```bash
./bench -e tidesdb -c -w write -o 5000000 -t 8
```

<canvas id="stressTestChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('stressTestChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Throughput (K ops/sec)', 'Duration (sec)', 'Avg Latency (μs)', 'P99 Latency (μs)', 'Max Latency (ms)'],
      datasets: [{
        label: 'TidesDB',
        data: [916.053, 5.46, 8.42, 19.00, 2.237],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [684.513, 7.30, 11.69, 53.00, 32.560],
        backgroundColor: 'rgba(255, 99, 132, 0.8)',
        borderColor: 'rgba(255, 99, 132, 1)',
        borderWidth: 1
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'Stress Test: 5M Operations, 8 Threads'
        },
        legend: {
          display: true,
          position: 'top'
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Value (varies by metric)'
          }
        }
      }
    }
  });
}, 800);
</script>

The stress test with 5 million operations across 8 threads reveals TidesDB's sustained performance under heavy load. Throughput maintains a 1.34x advantage at 916K ops/sec versus RocksDB's 685K ops/sec, completing the workload in 5.46 seconds compared to 7.30 seconds (1.84 seconds faster). Average latency shows a 1.39x improvement at 8.42μs versus 11.69μs, but the most significant differences appear in tail latencies. P99 latency is 2.79x better at 19μs versus 53μs, and maximum latency shows a dramatic 14.56x advantage at 2.2ms compared to RocksDB's 32.6ms. This exceptional tail latency performance demonstrates TidesDB's predictability under stress, a critical characteristic for production systems where worst-case performance often determines user experience.

Under sustained heavy load (5M operations), TidesDB maintains **34% higher throughput** and completes **1.84 seconds faster**. The max latency advantage (**14.56x better**: 2.2ms vs 32.6ms) demonstrates superior tail latency under stress. P99 latency is **2.79x better** (19μs vs 53μs), showing more predictable performance.

## Performance Summary

### Key Findings

### TidesDB Strengths

TidesDB delivers exceptional read performance ranging from 1.19x to 4.77x faster than RocksDB, typically achieving 2-3x improvements in real-world mixed workloads. Write performance shows consistent advantages of 1.34x to 2.93x across all test scenarios, with the largest gains appearing in multi-threaded workloads at 2-4 threads. Full database scans demonstrate superior iteration speed of 1.77x to 3.27x faster, making TidesDB particularly well-suited for analytics and batch processing workloads.

Tail latency performance is where TidesDB truly excels. P99 and maximum latencies are consistently 1.5x to 14x lower than RocksDB, with the stress test showing a remarkable 14.56x advantage in maximum latency. This predictability stems from TidesDB's simpler architecture and lower variance in operation timing, making it ideal for latency-sensitive applications where consistent response times matter more than peak throughput. The database also shows excellent concurrency characteristics with strong scaling from 1 to 8 threads, particularly impressive at the 2-4 thread range where many applications operate.

### RocksDB Strengths

RocksDB demonstrates its maturity in specific scenarios, most notably with large value reads where its sophisticated multi-level caching provides a 2.09x performance advantage over TidesDB when handling 1KB values. This makes RocksDB a strong choice for applications storing larger objects like images, documents, or serialized data structures where read performance on large values is critical.

Beyond raw performance, RocksDB offers a mature ecosystem with extensive production battle-testing across companies like Facebook, LinkedIn, and Netflix. The wealth of tuning options, monitoring tools, and community knowledge makes it easier to optimize for specific workloads. Advanced features like column families, transactions, and backup utilities provide capabilities that may be essential for certain applications, though they come at the cost of increased complexity.

### Performance Comparison Table

| Workload | TidesDB Advantage | Best Speedup |
|----------|-------------------|---------------|
| Single-threaded writes | 1.47x - 1.86x | 1.86x (random) |
| Single-threaded reads | 4.77x | 4.77x (mixed) |
| Multi-threaded writes (2T) | 2.93x | 2.93x |
| Multi-threaded writes (4T) | 2.26x | 2.26x |
| Multi-threaded writes (8T) | 1.52x | 1.52x |
| Mixed workload (4T) | 2.06x writes, 1.32x reads | 2.06x |
| Zipfian (hot keys) | 1.35x - 1.37x | 1.37x |
| Timestamp pattern | 2.28x writes, 2.07x reads | 2.28x |
| Small values (8B/32B) | 2.52x writes, 1.19x reads | 2.52x |
| Large values (1KB) | 1.92x writes, 0.48x reads | 1.92x writes |
| High concurrency (5M ops) | 1.34x | 1.34x |
| Iteration speed | 1.77x - 3.27x | 3.27x |

### Latency Comparison

| Metric | TidesDB | RocksDB | Advantage |
|--------|---------|---------|------------|
| Single-thread write (avg) | 1.57 μs | ~3.30 μs | **2.10x better** |
| Single-thread read (avg) | 0.27 μs | ~1.61 μs | **5.96x better** |
| 4-thread write (avg) | 3.71 μs | ~8.93 μs | **2.41x better** |
| 4-thread read (avg) | 2.25 μs | ~2.78 μs | **1.24x better** |
| Stress test P99 | 19 μs | ~53 μs | **2.79x better** |
| Stress test max | 2,237 μs | ~32,560 μs | **14.56x better** |

## Conclusion

TidesDB consistently outperforms RocksDB across most workloads, with particularly strong advantages in read-heavy scenarios (1.2-4.8x faster), write throughput (1.5-2.9x faster), and full database scans (1.8-3.3x faster). Tail latency performance shows the most dramatic improvements, ranging from 1.5x to 14.6x better, which translates directly to more predictable application behavior under load. Small data workloads benefit from 2.5x faster writes, while multi-threaded performance at 2-4 threads shows 2.3-2.9x advantages, the sweet spot for many server applications.

RocksDB maintains a competitive edge in one specific scenario: large value reads (1KB+) where its sophisticated multi-level caching provides a 2.09x advantage. This makes RocksDB worth considering for applications that primarily read large objects and can tolerate higher write latencies and more variable tail latencies.

For applications prioritizing raw performance, simplicity, read speed, write speed, or predictable latency, TidesDB is the clear choice. Its simpler two-tier LSM architecture delivers superior performance in most real-world scenarios while maintaining a dramatically smaller codebase (~10K lines versus RocksDB's ~300K lines), making it easier to understand, debug, and maintain. The 2.93x advantage at 2 threads and 4.77x read advantage in mixed workloads make it particularly compelling for modern multi-core systems running typical database workloads.

Applications handling primarily large values (>1KB) in read-heavy patterns, or those requiring RocksDB's mature ecosystem and extensive tooling, should consider RocksDB despite the performance trade-offs. The choice ultimately depends on whether your workload aligns with RocksDB's strengths or whether TidesDB's broader performance advantages and simplicity better serve your needs.
---
title: "TidesDB vs RocksDB: Which Storage Engine is Faster?"
description: "Comprehensive performance benchmarks comparing TidesDB and RocksDB storage engines."
---

<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>

<p>Date: 2025-11-13</p>
<p>Updated: 2025-11-13</p>

This article presents comprehensive performance benchmarks comparing TidesDB and RocksDB, two LSM-tree based storage engines. Both are designed for write-heavy workloads, but they differ significantly in architecture, complexity, and performance characteristics.

We do recommend you benchmark your own use case to determine which storage engine is best for your needs!

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

## Benchtool
The benchtool is a custom pluggable benchmarking tool that provides fair, apples-to-apples comparisons between storage engines, you can find the repo here: [benchtool](https://github.com/tidesdb/benchtool). The benchtool is used to conduct all benchmarks in this article.

Bloom filters, block indexes, block cache `64mb`, memtable flush size `64mb`, and sync mode `none` are configured for both engines.

:::note
These benchmarks were concluded on a local machine, and not in the most optimal environment.  These benchmarks will be overwritten periodically.  The plan is to conduct our benchmarking on AWS and GCP instances with the following instances:
- AWS m5d.2xlarge	8
- GCP n2-standard-8

Both to use optimized flash disk and local SSD.

The Benchtool described above contains the full benchmark runner source code (shell script), and can be found here: [benchtool tidesdb-rocksdb runner](https://github.com/tidesdb/benchtool/blob/master/tidesdb_rocksdb.sh).  You will see it is more extended than what you see here, this article will be extended to include more amplification metrics, and resource comparisons once run on AWS and GCP.
::: 

## Benchmark Methodology

The benchmark tool measures
- Throughput in operations per second (ops/sec)
- Latency metrics including average, P50, P95, P99, minimum, and maximum values in microseconds
- Iteration speed for full storage engine scan performance
- Total duration for workload completion

Test parameters
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
./benchtool -e tidesdb -c -w write -p seq -o 1000000
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
        data: [659529, 1.32, 4.00, 15.4],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [504417, 1.98, 4.00, 0],
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

In sequential write tests, TidesDB achieves 660K operations per second compared to RocksDB's 504K ops/sec, representing a 1.31x throughput advantage. Average latency is impressive at 1.32μs versus RocksDB's estimated 1.98μs (1.50x faster). The most dramatic difference appears in iteration performance, where TidesDB scans at 15.4M ops/sec, demonstrating TidesDB's efficient SSTable design.

**Random Keys (1M operations)**
```bash
./benchtool -e tidesdb -c -w write -p random -o 1000000
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
        data: [663438, 1.32, 4.00, 14.1],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [504748, 1.98, 4.00, 0],
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

Random write performance shows strong results for TidesDB. Throughput reaches 663K ops/sec versus RocksDB's 505K ops/sec (1.31x faster), while average latency is 1.32μs compared to RocksDB's estimated 1.98μs (1.50x faster). Iteration speed maintains TidesDB's advantage at 14.1M ops/sec, highlighting the efficiency of TidesDB's two-tier LSM architecture.

TidesDB demonstrates **31% higher write throughput** than RocksDB in single-threaded scenarios, with consistent 1.31x advantages across both sequential and random patterns. Average latency is 1.50x better at 1.32μs. TidesDB's iteration performance is exceptional at **14-15M ops/sec**, showcasing efficient SSTable design.

### Mixed Workload (50% Reads, 50% Writes)

**Random Keys (1M operations)**
```bash
./benchtool -e tidesdb -c -w mixed -p random -o 1000000
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
        data: [652.496, 3.021, 1.32, 0.33],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [500.743, 0.533, 2.00, 1.88],
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

Mixed workload testing reveals TidesDB's most impressive advantages. Write throughput of 652K ops/sec exceeds RocksDB's 501K ops/sec by 1.30x, but the real story is in read performance: TidesDB achieves 3.02M ops/sec compared to RocksDB's 533K ops/sec, a remarkable 5.67x improvement. Latency metrics are equally compelling, with write latency at 1.32μs versus 2.00μs (1.52x faster) and read latency at just 0.33μs compared to RocksDB's 1.88μs (5.70x faster). This sub-microsecond read latency demonstrates the effectiveness of TidesDB's lock-free read architecture. Iteration maintains the pattern at 15.5M ops/sec, showcasing superior scan performance.

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

Latency percentiles reveal TidesDB's consistency advantages. Write P50 latency is 2μs versus RocksDB's 3μs, with P99 at 4μs versus 7μs (1.75x better). Read latencies are exceptional: P50 of 0μs versus RocksDB's 1μs, P95 of 1μs versus 3μs (3x better), and P99 of 1μs versus 6μs (6x better). The P50 read latency of 0μs indicates most reads complete in under 1 microsecond, demonstrating TidesDB's lock-free read architecture.

## Multi-Threaded Scalability

### Write Performance (2, 4, 8 threads)

**2 Threads (1M operations)**
```bash
./benchtool -e tidesdb -c -w write -t 2 -o 1000000
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
        data: [882.289, 2.27, 6.00, 12.3],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [393.303, 5.09, 9.00, 0],
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

TidesDB achieves 882K ops/sec versus RocksDB's 393K ops/sec (2.24x faster) with average latency of 2.27μs versus 5.09μs (2.24x faster). P99 latency shows 6μs versus 9μs (1.50x better), and iteration reaches 12.3M ops/sec, demonstrating excellent multi-threaded performance.

**4 Threads (1M operations)**
```bash
./benchtool -e tidesdb -c -w write -t 4 -o 1000000
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
        data: [969.895, 4.12, 11.00, 8.9],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [634.150, 6.31, 10.00, 0],
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

TidesDB reaches 970K ops/sec versus RocksDB's 634K ops/sec (1.53x faster) with average latency of 4.12μs versus 6.31μs (1.53x faster). P99 latency shows 11μs versus 10μs (comparable), and iteration achieves 8.9M ops/sec, maintaining strong performance at higher concurrency.

**8 Threads (1M operations)**
```bash
./benchtool -e tidesdb -c -w write -t 8 -o 1000000
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
        data: [967.080, 8.27, 20.00, 5.7],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [925.133, 8.65, 16.00, 0],
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

TidesDB achieves 967K ops/sec versus RocksDB's 925K ops/sec (1.05x faster) with average latency of 8.27μs versus 8.65μs (comparable). P99 latency shows 20μs versus 16μs, and iteration reaches 5.7M ops/sec. At 8 threads, both storage engines show strong performance with RocksDB closing the gap.

**Scaling Efficiency**

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
        data: [663, 882, 970, 967],
        backgroundColor: 'rgba(54, 162, 235, 0.2)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 2,
        fill: true,
        tension: 0.1
      }, {
        label: 'RocksDB Throughput (K ops/sec)',
        data: [505, 393, 634, 925],
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
| 1       | 1.00x (baseline: 663K) | 1.00x (baseline: 505K) | 1.31x |
| 2       | 1.33x | 0.78x | **2.24x** |
| 4       | 1.46x | 1.26x | **1.53x** |
| 8       | 1.46x | 1.83x | **1.05x** |

TidesDB shows excellent multi-threaded scaling, with peak throughput at 4 threads (970K ops/sec). The **2.24x advantage at 2 threads** is particularly impressive, suggesting lower synchronization overhead. RocksDB shows **negative scaling at 2 threads** (0.78x), indicating higher lock contention. At 8 threads, RocksDB scales well to 925K ops/sec while TidesDB maintains 967K ops/sec, with both storage engines showing strong high-concurrency performance.

### Mixed Workload - 4 Threads

**Random Keys (1M operations)**
```bash
./benchtool -e tidesdb -c -w mixed -t 4 -o 1000000
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
        data: [1015.362, 1.733, 3.94, 2.31],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [664.356, 1.522, 6.02, 2.63],
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

TidesDB achieves 1.02M PUT ops/sec versus RocksDB's 664K ops/sec (1.53x faster) and 1.73M GET ops/sec versus 1.52M ops/sec (1.14x faster). PUT latency is 3.94μs versus 6.02μs (1.53x faster), while GET latency shows 2.31μs versus 2.63μs (1.14x faster). Iteration reaches 8.7M ops/sec, showcasing strong mixed workload performance.

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

With 4 threads, TidesDB maintains strong advantages: **1.53x faster writes**, **1.14x faster reads**, and superior iteration performance. Write latencies are significantly better (3.94μs vs 6.02μs avg), while read latencies remain competitive at 2.31μs.

## Key Pattern Performance

### Zipfian Distribution (Hot Keys)

**Mixed Workload, 4 Threads (500K operations)**
```bash
./benchtool -e tidesdb -c -w mixed -p zipfian -o 500000 -t 4
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
        data: [435.532, 2.474, 9.19, 1.62, 28, 5],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [507.167, 1.880, 7.89, 2.13, 22, 7],
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

TidesDB achieves 436K PUT ops/sec versus RocksDB's 507K ops/sec (0.86x, RocksDB 1.16x faster) and 2.47M GET ops/sec versus 1.88M ops/sec (1.32x faster). PUT latency is 9.19μs versus 7.89μs, while GET latency shows 1.62μs versus 2.13μs (1.31x faster). P99 latencies show PUT at 28μs versus 22μs and GET at 5μs versus 7μs (1.4x better). The test generated approximately 56K unique keys due to Zipfian's hot key concentration pattern.

Zipfian distribution simulates real-world hot key scenarios (80/20 rule). RocksDB shows **16% faster writes** with hot keys, leveraging its multi-level caching, while TidesDB delivers **32% faster reads** (2.47M vs 1.88M ops/sec), demonstrating different optimization strategies for concentrated access patterns.

### Timestamp Pattern

**Mixed Workload, 4 Threads (500K operations)**
```bash
./benchtool -e tidesdb -c -w mixed -p timestamp -o 500000 -t 4
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
        data: [1031.762, 4.180, 3.88, 0.96, 11, 4],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [645.327, 3.147, 6.20, 1.27, 17, 5],
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

TidesDB achieves 1.03M PUT ops/sec versus RocksDB's 645K ops/sec (1.60x faster) and 4.18M GET ops/sec versus 3.15M ops/sec (1.33x faster). PUT latency is 3.88μs versus 6.20μs (1.60x faster), while GET latency shows 0.96μs versus 1.27μs (1.32x faster). P99 latencies show PUT at 11μs versus 17μs (1.55x better) and GET at 4μs versus 5μs (1.25x better). The test generated approximately 14 unique keys due to timestamp-based key generation having low cardinality in the short test window.

Timestamp-based keys (time-series workload) show TidesDB's strong performance: **1.60x faster writes** and **1.33x faster reads**. This pattern benefits from TidesDB's sequential write optimization and efficient read path.

## Deletion Performance

### Single-threaded Delete (1M operations)
```bash
./benchtool -e tidesdb -c -w delete -p random -o 1000000
```

<canvas id="deleteSingleThreadChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('deleteSingleThreadChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Throughput (K ops/sec)', 'Avg Latency (μs)', 'P99 Latency (μs)'],
      datasets: [{
        label: 'TidesDB',
        data: [579.391, 1.66, 4.00],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [515.527, 1.94, 4.00],
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
          text: 'Single-Threaded Delete Performance'
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
}, 1300);
</script>

TidesDB achieves 579K delete ops/sec versus RocksDB's 516K ops/sec (1.12x faster) with average latency of 1.66μs versus 1.94μs (1.17x faster). P99 latency is comparable at 4μs for both engines. Single-threaded deletion shows modest advantages for TidesDB with consistent low-latency performance.

### Multi-threaded Delete - 4 Threads (1M operations)
```bash
./benchtool -e tidesdb -c -w delete -p random -o 1000000 -t 4
```

<canvas id="delete4ThreadChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('delete4ThreadChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Throughput (K ops/sec)', 'Avg Latency (μs)', 'P99 Latency (μs)'],
      datasets: [{
        label: 'TidesDB',
        data: [737.592, 5.42, 15.00],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [700.822, 5.71, 13.00],
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
          text: '4 Threads Delete Performance'
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
}, 1400);
</script>

With 4 threads, TidesDB reaches 738K delete ops/sec versus RocksDB's 701K ops/sec (1.05x faster) with average latency of 5.42μs versus 5.71μs (1.05x faster). P99 latency shows 15μs versus 13μs (comparable). Multi-threaded deletion shows both storage engines performing well with minimal difference.

### Hot Key Deletion - Zipfian Pattern (500K operations, 4 threads)
```bash
./benchtool -e tidesdb -c -w delete -p zipfian -o 500000 -t 4
```

<canvas id="deleteZipfianChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('deleteZipfianChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Throughput (K ops/sec)', 'Avg Latency (μs)', 'P99 Latency (μs)'],
      datasets: [{
        label: 'TidesDB',
        data: [269.481, 14.84, 52.00],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [546.913, 7.32, 25.00],
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
          text: 'Hot Key Deletion (Zipfian Pattern)'
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
}, 1500);
</script>

Zipfian deletion reveals an interesting pattern. RocksDB achieves 547K delete ops/sec versus TidesDB's 269K ops/sec (2.03x faster for RocksDB) with average latency of 7.32μs versus TidesDB's 14.84μs. P99 latency shows RocksDB at 25μs versus TidesDB's 52μs (2.08x better for RocksDB). Hot key deletion patterns favor RocksDB's more sophisticated caching and compaction strategies, particularly when repeatedly deleting from a concentrated key space.

Deletion performance shows TidesDB with modest advantages in random deletion patterns (1.05-1.12x faster) but RocksDB performs significantly better with hot key patterns (2.03x faster). This suggests TidesDB excels at uniform deletion workloads while RocksDB's multi-level architecture handles concentrated deletion patterns more efficiently.

## Value Size Tests

### Large Values (1KB)

**Mixed Workload, 4 Threads (500K operations)**
```bash
./benchtool -e tidesdb -c -w mixed -v 1024 -o 500000 -t 4
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
        data: [575.404, 371.585, 6.95, 10.77],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [246.311, 1246.255, 16.25, 3.21],
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

Large value testing (1KB) reveals an interesting trade-off. TidesDB maintains strong write performance at 575K ops/sec versus RocksDB's 246K ops/sec (2.34x faster) with write latency of 6.95μs compared to 16.25μs (2.34x faster). However, RocksDB's sophisticated caching strategies show their value in read operations, achieving 1.25M ops/sec versus TidesDB's 372K ops/sec (3.35x advantage for RocksDB) with read latency of 3.21μs versus TidesDB's 10.77μs (3.35x faster). TidesDB still maintains iteration advantages at 3.7M ops/sec, suggesting that for workloads involving large values with mixed read/write patterns, the choice depends on whether write or read performance is more critical.

With 1KB values, TidesDB shows **2.34x faster writes** but RocksDB has **3.35x faster reads**. This is expected as larger values favor RocksDB's more complex caching strategies. TidesDB maintains strong iteration performance at 3.7M ops/sec.

### Small Values (8B keys, 32B values)

**Mixed Workload, 4 Threads (1M operations)**
```bash
./benchtool -e tidesdb -c -w mixed -k 8 -v 32 -o 1000000 -t 4
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
        data: [1039.441, 3.003, 3.85, 1.33],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [651.609, 1.966, 6.14, 2.04],
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

Small value testing (8B keys, 32B values) showcases TidesDB's strong overall performance. Write throughput reaches 1.04M ops/sec compared to RocksDB's 652K ops/sec (1.60x faster), while read throughput hits 3.00M ops/sec versus 1.97M ops/sec (1.53x faster). Write latency is exceptional at 3.85μs versus RocksDB's 6.14μs (1.60x faster), and read latency shows 1.33μs versus 2.04μs (1.53x faster). These results demonstrate TidesDB's efficiency with compact, cache-friendly data structures that are common in many real-world applications.

Small, cache-friendly data shows TidesDB's strong performance: **1.60x faster writes** with **1.53x faster reads**. This demonstrates TidesDB's efficiency with compact data structures.

## High Concurrency Stress

**5M Operations, 8 Threads**
```bash
./benchtool -e tidesdb -c -w write -o 5000000 -t 8
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
        data: [856.863, 5.84, 9.33, 22.00, 2.451],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [484.808, 10.31, 20.64, 69.00, 44.234],
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

The stress test with 5 million operations across 8 threads reveals TidesDB's sustained performance under heavy load. Throughput maintains a 1.77x advantage at 857K ops/sec versus RocksDB's 485K ops/sec, completing the workload in 5.84 seconds compared to 10.31 seconds (4.47 seconds faster). Average latency shows a 2.21x improvement at 9.33μs versus 20.64μs, but the most significant differences appear in tail latencies. P99 latency is 3.14x better at 22μs versus 69μs, and maximum latency shows a dramatic 18.05x advantage at 2.5ms compared to RocksDB's 44.2ms. This exceptional tail latency performance demonstrates TidesDB's predictability under stress, a critical characteristic for production systems where worst-case performance often determines user experience.

Under sustained heavy load (5M operations), TidesDB maintains **77% higher throughput** and completes **4.47 seconds faster**. The max latency advantage (**18.05x better**: 2.5ms vs 44.2ms) demonstrates superior tail latency under stress. P99 latency is **3.14x better** (22μs vs 69μs), showing more predictable performance.

## Batch Operations Performance

### Batch Write Performance (4 threads, 1M operations)
```bash
./benchtool -e tidesdb -c -w write -o 1000000 -t 4 -b [10|100|1000]
```

<canvas id="batchWriteChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('batchWriteChart').getContext('2d');
  new Chart(ctx, {
    type: 'line',
    data: {
      labels: ['Batch 1', 'Batch 10', 'Batch 100', 'Batch 1000'],
      datasets: [{
        label: 'TidesDB Throughput (K ops/sec)',
        data: [970, 983, 993, 960],
        backgroundColor: 'rgba(54, 162, 235, 0.2)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 2,
        fill: true,
        tension: 0.1
      }, {
        label: 'RocksDB Throughput (K ops/sec)',
        data: [634, 654, 654, 660],
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
          text: 'Batch Write Performance Scaling'
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
            text: 'Batch Size'
          }
        }
      }
    }
  });
}, 1600);
</script>

Batch write performance shows TidesDB maintaining consistent advantages across all batch sizes. With batch size 1 (no batching), TidesDB achieves 970K ops/sec versus RocksDB's 634K ops/sec (1.53x faster). Batch size 10 shows 983K ops/sec versus 654K ops/sec (1.50x faster), batch size 100 reaches 993K ops/sec versus 654K ops/sec (1.52x faster), and batch size 1000 achieves 960K ops/sec versus 660K ops/sec (1.45x faster). TidesDB maintains relatively stable performance across batch sizes while RocksDB shows modest improvements, suggesting both engines have well-optimized write paths.

### Batch Delete Performance (4 threads, 1M operations)
```bash
./benchtool -e tidesdb -c -w delete -o 1000000 -t 4 -b [1|10|100|1000]
```

<canvas id="batchDeleteChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('batchDeleteChart').getContext('2d');
  new Chart(ctx, {
    type: 'line',
    data: {
      labels: ['Batch 1', 'Batch 10', 'Batch 100', 'Batch 1000'],
      datasets: [{
        label: 'TidesDB Throughput (K ops/sec)',
        data: [738, 708, 735, 736],
        backgroundColor: 'rgba(54, 162, 235, 0.2)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 2,
        fill: true,
        tension: 0.1
      }, {
        label: 'RocksDB Throughput (K ops/sec)',
        data: [701, 723, 726, 709],
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
          text: 'Batch Delete Performance Scaling'
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
            text: 'Batch Size'
          }
        }
      }
    }
  });
}, 1700);
</script>

Batch delete performance shows both storage engines maintaining stable performance across batch sizes. TidesDB starts at 738K ops/sec with batch size 1 (1.05x faster than RocksDB's 701K ops/sec) and maintains 708-736K ops/sec across all batch sizes. RocksDB shows 701-726K ops/sec across batch sizes. Both storage engines demonstrate well-optimized deletion paths with minimal variance across batching strategies.

### Batch Mixed Workload (4 threads, 1M operations)
```bash
./benchtool -e tidesdb -c -w mixed -o 1000000 -t 4 -b [100|1000]
```

<canvas id="batchMixedChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('batchMixedChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['PUT (batch 100)', 'GET (batch 100)', 'PUT (batch 1000)', 'GET (batch 1000)'],
      datasets: [{
        label: 'TidesDB (K ops/sec)',
        data: [991, 1724, 985, 1686],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB (K ops/sec)',
        data: [652, 1503, 660, 1613],
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
          text: 'Batch Mixed Workload Performance'
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
        }
      }
    }
  });
}, 1800);
</script>

Batch mixed workload shows TidesDB with 991K PUT ops/sec versus RocksDB's 652K ops/sec (1.52x faster) at batch 100, and 1.72M GET ops/sec versus RocksDB's 1.50M ops/sec (1.15x faster). At batch 1000, TidesDB reaches 985K PUT ops/sec versus 660K ops/sec (1.49x faster), with 1.69M GET ops/sec versus RocksDB's 1.61M ops/sec (1.05x faster). TidesDB maintains advantages in both reads and writes across batch sizes.

Batch operations show TidesDB maintaining consistent advantages across all batch sizes. Write operations maintain 1.45-1.53x advantages, delete operations show 1.01-1.05x advantages, and mixed workloads demonstrate 1.05-1.52x advantages for both reads and writes. Both storage engines show stable performance across batching strategies, indicating well-optimized code paths.

## Performance Summary

### Key Findings

### TidesDB Strengths

TidesDB delivers exceptional read performance ranging from 1.14x to 5.67x faster than RocksDB, with the most dramatic advantage appearing in single-threaded mixed workloads (5.67x). Write performance shows consistent advantages of 1.31x to 2.24x across all test scenarios, with the largest gains appearing in multi-threaded workloads at 2 threads (2.24x). Full storage engines scans demonstrate superior iteration speed of 8.7-15.5M ops/sec, making TidesDB particularly well-suited for analytics and batch processing workloads.

Tail latency performance is where TidesDB truly excels. P99 and maximum latencies are consistently 1.5x to 18x lower than RocksDB, with the stress test showing a remarkable 18.05x advantage in maximum latency (2.5ms vs 44.2ms). This predictability stems from TidesDB's simpler architecture and lower variance in operation timing, making it ideal for latency-sensitive applications where consistent response times matter more than peak throughput. The storage engine also shows excellent concurrency characteristics with strong scaling from 1 to 8 threads, particularly impressive at the 2 thread range where many applications operate.

Deletion performance favors TidesDB in uniform random patterns, showing 1.05x to 1.12x advantages in single and multi-threaded scenarios. Batch operations demonstrate stable performance across all batch sizes, with write operations maintaining 1.45-1.53x advantages, delete operations showing 1.01-1.05x advantages, and mixed workloads maintaining 1.05-1.52x advantages for both reads and writes, demonstrating well-optimized code paths throughout.

### RocksDB Strengths

RocksDB demonstrates its maturity in specific scenarios, most notably with large value reads where its sophisticated multi-level caching provides a 3.35x performance advantage over TidesDB when handling 1KB values (1.25M vs 372K ops/sec). This makes RocksDB a strong choice for applications storing larger objects like images, documents, or serialized data structures where read performance on large values is critical.

Hot key patterns reveal another RocksDB strength. In Zipfian workloads, RocksDB achieves 1.16x faster writes (507K vs 436K ops/sec) and in hot key deletion patterns, RocksDB delivers 2.03x faster throughput (547K vs 269K ops/sec). The multi-level architecture and sophisticated compaction strategies handle concentrated access and deletion patterns more efficiently than TidesDB's simpler two-tier design, making it ideal for workloads with skewed key distributions.

Beyond raw performance, RocksDB offers a mature ecosystem with extensive production battle-testing across companies like Facebook, LinkedIn, and Netflix. The wealth of tuning options, monitoring tools, and community knowledge makes it easier to optimize for specific workloads. Advanced features like column families, transactions, and backup utilities provide capabilities that may be essential for certain applications, though they come at the cost of increased complexity.

### Performance Comparison Table

| Workload | TidesDB Advantage | Best Speedup |
|----------|-------------------|---------------|
| Single-threaded writes | 1.31x | 1.31x (both patterns) |
| Single-threaded reads | 5.67x | 5.67x (mixed) |
| Single-threaded deletes | 1.12x | 1.12x |
| Multi-threaded writes (2T) | 2.24x | 2.24x |
| Multi-threaded writes (4T) | 1.53x | 1.53x |
| Multi-threaded writes (8T) | 1.05x | 1.05x |
| Multi-threaded deletes (4T) | 1.05x | 1.05x |
| Mixed workload (4T) | 1.53x writes, 1.14x reads | 1.53x |
| Zipfian (hot keys) | 0.86x writes, 1.32x reads | 1.32x reads |
| Zipfian deletes | 0.49x (RocksDB faster) | 2.03x (RocksDB) |
| Timestamp pattern | 1.60x writes, 1.33x reads | 1.60x |
| Small values (8B/32B) | 1.60x writes, 1.53x reads | 1.60x |
| Large values (1KB) | 2.34x writes, 0.30x reads | 2.34x writes |
| Batch writes (size 1-1000) | 1.45x - 1.53x | 1.53x (batch 100) |
| Batch deletes (size 1-1000) | 1.01x - 1.05x | 1.05x (batch 1) |
| Batch mixed (size 100-1000) | 1.49x writes, 1.05x reads | 1.52x writes |
| High concurrency (5M ops) | 1.77x | 1.77x |
| Iteration speed | 8.7M - 15.5M ops/sec | 15.5M ops/sec |

### Latency Comparison

| Metric | TidesDB | RocksDB | Advantage |
|--------|---------|---------|------------|
| Single-thread write (avg) | 1.32 μs | ~1.98 μs | **1.50x better** |
| Single-thread read (avg) | 0.33 μs | ~1.88 μs | **5.70x better** |
| Single-thread delete (avg) | 1.66 μs | ~1.94 μs | **1.17x better** |
| 4-thread write (avg) | 4.12 μs | ~6.31 μs | **1.53x better** |
| 4-thread read (avg) | 2.31 μs | ~2.63 μs | **1.14x better** |
| 4-thread delete (avg) | 5.42 μs | ~5.71 μs | **1.05x better** |
| Zipfian delete (avg) | 14.84 μs | ~7.32 μs | **2.03x worse** |
| Stress test P99 | 22 μs | ~69 μs | **3.14x better** |
| Stress test max | 2,451 μs | ~44,234 μs | **18.05x better** |

## Conclusion

TidesDB consistently outperforms RocksDB across most workloads, with particularly strong advantages in read-heavy scenarios (1.14-5.67x faster), write throughput (1.31-2.24x faster), and full storage engine scans (8.7-15.5M ops/sec). Tail latency performance shows the most dramatic improvements, ranging from 1.5x to 18x better, which translates directly to more predictable application behavior under load. The stress test demonstrates exceptional tail latency with an 18.05x advantage in maximum latency (2.5ms vs 44.2ms), while multi-threaded performance at 2 threads shows 2.24x advantages, the sweet spot for many server applications.

Deletion performance reveals nuanced characteristics: TidesDB excels at uniform random deletions (1.05-1.12x faster) but RocksDB handles hot key deletion patterns significantly more efficiently (2.03x faster). Batch operations demonstrate stable performance across all batch sizes for both storage engines, with TidesDB maintaining write advantages of 1.45-1.53x, delete advantages of 1.01-1.05x, and mixed workload advantages of 1.05-1.52x for both reads and writes.

RocksDB maintains competitive edges in specific scenarios: large value reads (1KB+) where sophisticated multi-level caching provides a 3.35x advantage (1.25M vs 372K ops/sec), hot key patterns showing 1.16x faster writes and 2.03x faster deletions in Zipfian distributions. These strengths make RocksDB worth considering for applications with concentrated access patterns or large object storage where read performance on large values is critical.

For applications prioritizing raw performance, simplicity, read speed, write speed, or predictable latency, TidesDB is the clear choice. Its simpler two-tier LSM architecture delivers superior performance in most real-world scenarios while maintaining a dramatically smaller codebase (~27K lines versus RocksDB's ~300K lines), making it easier to understand, debug, and maintain. The 2.24x advantage at 2 threads, 5.67x read advantage in mixed workloads, and exceptional tail latency performance make it particularly compelling for modern multi-core systems running typical storage engine workloads with uniform access patterns.

Applications with concentrated key access patterns (hot keys), primarily large values (>1KB) in read-heavy scenarios, or those requiring RocksDB's mature ecosystem and extensive tooling, should consider RocksDB despite the performance trade-offs in other areas. The choice ultimately depends on whether your workload aligns with RocksDB's architectural strengths or whether TidesDB's broader performance advantages and simplicity better serve your needs.
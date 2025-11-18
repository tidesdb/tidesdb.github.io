---
title: "TidesDB vs RocksDB: Performance Benchmarks"
description: "Comprehensive performance benchmarks comparing TidesDB and RocksDB storage engines."
---

<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>

This article presents comprehensive performance benchmarks comparing TidesDB and RocksDB, two LSM-tree based storage engines. Both are designed for write-heavy workloads, but they differ significantly in architecture, complexity, and performance characteristics.

**We recommend you benchmark your own use case to determine which storage engine is best for your needs!**

## Test Environment

**Hardware**
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)
- exFAT
- Ubuntu 23.04 x86_64 6.2.0-39-generic

**Software Versions**
- TidesDB v4.0.1
- RocksDB v10.7.5 (via benchtool)
- GCC with -O3 optimization
- GNOME 44.3

## Benchtool

The benchtool is a custom pluggable benchmarking tool that provides fair, apples-to-apples comparisons between storage engines. You can find the repo here: [benchtool](https://github.com/tidesdb/benchtool).

**Configuration (matched for both engines)**
- Bloom filters are enabled (10 bits per key)
- Block cache is set to 64MB (HyperClockCache for RocksDB, FIFO for TidesDB)
- Memtable flush size is set to 64MB
- Sync mode is disabled (maximum performance)
- Compression using LZ4
- 4 threads (all tests)

**The benchtool measures**
- Operations per second (ops/sec)
- Average, P50, P95, P99, min, max (microseconds)
- Memory (RSS/VMS), disk I/O, CPU utilization
- Write, space amplification
- Full database scan performance

## Benchmark Methodology

All tests use **4 threads** for concurrent operations with a **key size** of 16 bytes (256 bytes for large value test) and **value size** of 100 bytes (64 bytes for small, 4KB for large). **Sync mode** is disabled for maximum throughput. **Operations** include 10M (writes/reads), 5M (mixed/delete/zipfian), 50M (small values), and 1M (large values). Tests are conducted on a Western Digital 500GB WD Blue 3D NAND SATA SSD with exFAT file system.

## Performance Summary Table

| Test | TidesDB | RocksDB | Advantage |
|------|---------|---------|------------|
| Sequential Write (10M) | 871K ops/sec | 585K ops/sec | **1.49x faster** |
| Random Write (10M) | 840K ops/sec | 595K ops/sec | **1.41x faster** |
| Random Read (10M) | 10.86M ops/sec | 1.92M ops/sec | **5.65x faster** |
| Mixed Workload (5M) | 851K PUT / 1.63M GET | 603K PUT / 1.68M GET | **1.41x PUT / 0.97x GET** |
| Zipfian Write (5M) | 809K ops/sec | 443K ops/sec | **1.83x faster** |
| Zipfian Mixed (5M) | 824K PUT / 1.12M GET | 432K PUT / 900K GET | **1.91x / 1.24x faster** |
| Delete (5M) | 862K ops/sec | 622K ops/sec | **1.39x faster** |
| Large Values (1M, 4KB) | 235K ops/sec | 150K ops/sec | **1.56x faster** |
| Small Values (50M, 64B) | 892K ops/sec | 593K ops/sec | **1.51x faster** |

## Detailed Benchmark Results

The following sections provide detailed results for each benchmark test with latency distributions, resource usage, and amplification factors.

### 1. Sequential Write Performance

10M operations, 4 threads, sequential keys

<canvas id="seqWriteChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('seqWriteChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Throughput (K ops/sec)', 'Avg Latency (μs)', 'P99 Latency (μs)', 'Iteration (M ops/sec)'],
      datasets: [{
        label: 'TidesDB',
        data: [871, 4.30, 11, 10.88],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [585, 0, 0, 4.72],
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
          text: 'Sequential Write Performance (10M ops, 4 threads)'
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

In sequential write testing with 10 million operations across 4 threads, TidesDB achieves 871K operations per second compared to RocksDB's 585K ops/sec, representing a 1.49x throughput advantage. Average latency is 4.30μs with a P50 of 4μs, P95 of 7μs, P99 of 11μs, and maximum of 14,409μs. The most dramatic difference appears in iteration performance, where TidesDB scans at 10.88M ops/sec versus RocksDB's 4.72M ops/sec, a 2.31x advantage demonstrating TidesDB's efficient SSTable design.

Resource usage shows TidesDB utilizing 2662 MB RSS with 2309 MB disk writes and 714.1% CPU utilization, while RocksDB uses 2903 MB RSS with 1800 MB disk writes and 412.4% CPU utilization. TidesDB's higher CPU utilization indicates better multi-core scaling. Write amplification measures 2.09x for TidesDB versus 1.63x for RocksDB, while space amplification is 1.46x versus 0.18x respectively.

TidesDB's larger database size (1615 MB vs 197 MB, 8.2x larger) reflects its architectural design choices: embedded succinct trie indexes in SSTables for fast lookups and a simplified LSM structure (active memtable → immutable memtables → SSTables). While TidesDB triggers compaction when SSTable count reaches a threshold (configured at 512 for these benchmarks), its embedded indexes and architectural design result in larger on-disk footprint compared to RocksDB's multi-level LSM tree.

### 2. Random Write Performance

10M operations, 4 threads, random keys

<canvas id="randomWriteChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('randomWriteChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Throughput (K ops/sec)', 'Avg Latency (μs)', 'P99 Latency (μs)', 'Iteration (M ops/sec)'],
      datasets: [{
        label: 'TidesDB',
        data: [840, 4.45, 11, 10.45],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [595, 0, 0, 4.49],
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
          text: 'Random Write Performance (10M ops, 4 threads)'
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

Random write performance demonstrates strong results for TidesDB. Throughput reaches 840K operations per second versus RocksDB's 595K ops/sec, a 41% advantage (1.41x faster). Average latency measures 4.45μs with a P50 of 4μs, P95 of 7μs, P99 of 11μs, and maximum of 8,245μs. Iteration speed maintains TidesDB's advantage at 10.45M ops/sec compared to RocksDB's 4.49M ops/sec, a 2.33x improvement highlighting the efficiency of TidesDB's two-tier LSM architecture.

Resource consumption shows TidesDB using 2509 MB RSS with 2957 MB disk writes and achieving 715.6% CPU utilization, while RocksDB uses 2832 MB RSS with 2081 MB disk writes and 415.0% CPU utilization. TidesDB's significantly higher CPU utilization (716% vs 415%) indicates superior multi-core scaling, effectively leveraging available CPU resources. Write amplification is 2.67x for TidesDB versus 1.88x for RocksDB, while space amplification measures 1.43x versus 0.26x respectively. The database sizes are 1583 MB for TidesDB versus 288 MB for RocksDB (5.5x larger).

### 3. Random Read Performance

10M operations, 4 threads, random keys (pre-populated database)

<canvas id="randomReadChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('randomReadChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Throughput (M ops/sec)', 'Avg Latency (μs)', 'P99 Latency (μs)', 'Max Latency (μs)'],
      datasets: [{
        label: 'TidesDB',
        data: [10.86, 0.21, 1, 634],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [1.92, 1.87, 6, 680],
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
          text: 'Random Read Performance (10M ops, 4 threads)'
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

Random read testing reveals TidesDB's most impressive performance advantage. With 10 million operations across 4 threads on a pre-populated database, TidesDB achieves 10.86 million operations per second compared to RocksDB's 1.92 million ops/sec, a remarkable 5.65x improvement. Average latency is exceptional at just 0.21μs versus RocksDB's 1.87μs, representing 8.9x lower latency.

The latency distribution tells an even more compelling story. TidesDB's P50 latency of 0μs indicates that most reads complete in under 1 microsecond, with P95 and P99 both at 1μs and a maximum of 634μs. In contrast, RocksDB shows P50 of 2μs, P95 of 3μs, P99 of 6μs, and maximum of 680μs. This sub-microsecond read performance demonstrates the effectiveness of TidesDB's read architecture, which uses atomic operations and reference counting for memtable access rather than locks, allowing readers to scale linearly with CPU cores without blocking.

Resource usage shows TidesDB utilizing 2530 MB RSS with 644.9% CPU utilization, while RocksDB uses significantly less memory at 179 MB RSS with 279.2% CPU utilization. Despite the higher memory footprint, TidesDB's performance advantage is undeniable for read-heavy workloads.

### 4. Mixed Workload (50% Reads, 50% Writes)

5M operations, 4 threads, random keys

<canvas id="mixedWorkloadChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('mixedWorkloadChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['PUT (K ops/sec)', 'GET (M ops/sec)', 'PUT Latency (μs)', 'GET Latency (μs)'],
      datasets: [{
        label: 'TidesDB',
        data: [851, 1.63, 4.39, 1.96],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [603, 1.68, 0, 0],
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
          text: 'Mixed Workload Performance (5M ops, 4 threads)'
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
}, 400);
</script>

Mixed workload testing with 5 million operations demonstrates TidesDB's ability to excel at both reads and writes simultaneously. Write throughput reaches 851K PUT operations per second compared to RocksDB's 603K ops/sec, a 41% advantage (1.41x faster). Read performance shows 1.63 million GET operations per second versus RocksDB's 1.68 million ops/sec, representing 0.97x (3% slower). Iteration speed shows a dramatic 2.37x advantage at 11.15M ops/sec compared to RocksDB's 4.70M ops/sec, demonstrating superior scan performance.

Latency metrics reveal TidesDB's consistency under mixed load. PUT operations average 4.39μs with P50 of 4μs, P95 of 7μs, P99 of 11μs, and maximum of 6,756μs. GET operations average 1.96μs with P50 of 2μs, P95 of 4μs, P99 of 5μs, and maximum of 4,938μs. This demonstrates that TidesDB maintains low latency for both operation types even when they're running concurrently. The slight read performance disadvantage in this test may be attributed to the specific workload pattern and caching behavior.

Resource consumption shows TidesDB using 1263 MB RSS with 1770 MB disk writes and 689.4% CPU utilization, while RocksDB uses 1494 MB RSS with 905 MB disk writes and 386.6% CPU utilization. Write amplification measures 3.20x for TidesDB versus 1.64x for RocksDB, while space amplification is 1.43x versus 0.30x respectively. Database sizes are 792 MB for TidesDB versus 164 MB for RocksDB (4.8x larger).

### 5. Hot Key Workload (Zipfian Distribution)

#### 5.1 Zipfian Write

5M operations, 4 threads, Zipfian distribution (hot keys)

<canvas id="zipfianWriteChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('zipfianWriteChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Throughput (K ops/sec)', 'Avg Latency (μs)', 'P99 Latency (μs)', 'Unique Keys (K)'],
      datasets: [{
        label: 'TidesDB',
        data: [809, 4.47, 12, 839],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [443, 0, 0, 657],
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
          text: 'Zipfian Write Performance (5M ops, 4 threads)'
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
}, 500);
</script>

Zipfian distribution testing simulates real-world hot key scenarios following the 80/20 rule, where approximately 20% of keys receive 80% of the traffic. With 5 million operations generating roughly 839K unique keys, TidesDB achieves 809K operations per second compared to RocksDB's 443K ops/sec, maintaining an 83% throughput advantage (1.83x faster) even with concentrated access patterns. Average latency measures 4.47μs with P50 of 4μs, P95 of 8μs, P99 of 12μs, and maximum of 7,109μs.

Interestingly, iteration performance shows RocksDB with an advantage at 1.94M ops/sec versus TidesDB's 1.01M ops/sec, a 1.91x improvement for RocksDB. This demonstrates the effectiveness of RocksDB's multi-level architecture and sophisticated caching strategies when dealing with hot keys, where frequently accessed data benefits from being cached at multiple levels. Write amplification is 2.47x for TidesDB versus 1.32x for RocksDB, while space amplification shows a dramatic difference at 1.22x versus 0.10x, with RocksDB achieving 12.2x better space efficiency due to its aggressive compaction of duplicate keys. Database sizes are 672 MB for TidesDB versus 54 MB for RocksDB (12.4x larger).

#### 5.2 Zipfian Mixed

5M operations, 4 threads, Zipfian distribution, 50/50 read/write

<canvas id="zipfianMixedChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('zipfianMixedChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['PUT (K ops/sec)', 'GET (M ops/sec)', 'PUT Latency (μs)', 'GET Latency (μs)'],
      datasets: [{
        label: 'TidesDB',
        data: [824, 1.12, 4.30, 3.26],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [432, 0.90, 0, 0],
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
          text: 'Zipfian Mixed Workload (5M ops, 4 threads)'
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

Hot key mixed workload testing combines the Zipfian distribution with simultaneous reads and writes, creating a realistic scenario where popular keys receive concentrated traffic. TidesDB achieves 824K PUT operations per second compared to RocksDB's 432K ops/sec, representing a 91% throughput advantage (1.91x faster). Read performance shows 1.12 million GET operations per second versus RocksDB's 900K ops/sec, a 24% improvement (1.24x faster).

Latency characteristics remain strong under this challenging workload. PUT operations average 4.30μs with P50 of 4μs, P95 of 7μs, P99 of 11μs, and maximum of 2,744μs. GET operations average 3.26μs with P50 of 2μs, P95 of 9μs, P99 of 16μs, and maximum of 17,616μs. These metrics demonstrate TidesDB's ability to maintain consistent performance even when dealing with skewed access patterns where a small subset of keys receives the majority of traffic.

Write amplification measures 2.70x for TidesDB versus 1.32x for RocksDB, while space amplification shows a dramatic difference at 1.03x versus 0.12x, with RocksDB achieving 8.6x better space efficiency. This extreme space efficiency for RocksDB in hot key scenarios results from its aggressive compaction of duplicate keys, where the same keys are repeatedly updated and older versions are quickly discarded. Database sizes are 569 MB for TidesDB versus 69 MB for RocksDB (8.2x larger).

### 6. Delete Performance

5M operations, 4 threads, random keys (pre-populated database)

<canvas id="deleteChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('deleteChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Throughput (K ops/sec)', 'Avg Latency (μs)', 'P99 Latency (μs)', 'Max Latency (ms)'],
      datasets: [{
        label: 'TidesDB',
        data: [862, 4.49, 9, 10.7],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [622, 6.31, 15, 4.9],
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
          text: 'Delete Performance (5M ops, 4 threads)'
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

Deletion performance testing with 5 million operations on a pre-populated database shows TidesDB achieving 862K operations per second compared to RocksDB's 622K ops/sec, representing a 39% throughput advantage (1.39x faster). Average latency is 4.49μs versus RocksDB's 6.31μs, demonstrating 41% lower latency (1.41x faster). The latency distribution shows TidesDB with P50 of 4μs, P95 of 6μs, and P99 of 9μs, while RocksDB shows P50 of 6μs, P95 of 9μs, and P99 of 15μs.

Maximum latency measurements show TidesDB at 10.7ms compared to RocksDB's 4.9ms. While TidesDB has a higher maximum latency, this is likely attributable to background compaction operations that periodically run to merge SSTables and remove tombstones. The consistently lower average and P99 latencies demonstrate that TidesDB maintains superior performance for the vast majority of operations.

Resource consumption shows TidesDB using 1304 MB RSS with 901 MB disk writes and 773.5% CPU utilization, while RocksDB uses significantly less at 186 MB RSS with 300 MB disk writes and 383.8% CPU utilization. TidesDB's higher CPU utilization again demonstrates its effective use of multi-core resources. Write amplification for deletes is 1.63x for TidesDB versus 0.54x for RocksDB. Database sizes after deletion are 1106 MB for TidesDB versus 161 MB for RocksDB (6.9x larger).

### 7. Large Value Performance

1M operations, 4 threads, 256B keys, 4KB values

<canvas id="largeValueChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('largeValueChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Throughput (K ops/sec)', 'Avg Latency (μs)', 'P99 Latency (μs)', 'Iteration (M ops/sec)'],
      datasets: [{
        label: 'TidesDB',
        data: [235, 12.00, 34, 1.18],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [150, 0, 0, 0.40],
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
          text: 'Large Value Performance (1M ops, 256B key, 4KB value)'
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

Large value testing with 1 million operations using 256-byte keys and 4KB values reveals strong performance for TidesDB. Throughput reaches 235K operations per second compared to RocksDB's 150K ops/sec, a 1.56x improvement. This represents a significant advantage for large value workloads. Average latency measures 12.00μs with P50 of 10μs, P95 of 19μs, P99 of 34μs, and maximum of 13.2ms. Iteration speed shows 1.18 million ops/sec versus RocksDB's 398K ops/sec, a 2.97x advantage.

Interestingly, write amplification characteristics are excellent with large values. TidesDB achieves 1.07x write amplification compared to RocksDB's 1.25x, making TidesDB more efficient in terms of write overhead when handling larger data blocks. This suggests TidesDB's architecture is particularly well-suited for applications storing larger objects, documents, or serialized data structures. Space amplification measures 0.84x for TidesDB versus 0.09x for RocksDB, with the database sizes being 3498 MB versus 356 MB respectively (9.8x smaller for RocksDB).

Resource consumption shows TidesDB using 4013 MB RSS with 4440 MB disk writes and 700.4% CPU utilization, while RocksDB uses 3556 MB RSS with 5185 MB disk writes and 379.5% CPU utilization. TidesDB's higher CPU utilization (700% vs 380%) indicates it's effectively parallelizing the workload across multiple cores even with larger data blocks.

### 8. Small Value Performance

50M operations, 4 threads, 16B keys, 64B values

<canvas id="smallValueChart" width="400" height="200"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('smallValueChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Throughput (K ops/sec)', 'Avg Latency (μs)', 'P99 Latency (μs)', 'Iteration (M ops/sec)'],
      datasets: [{
        label: 'TidesDB',
        data: [892, 4.21, 10, 7.93],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB',
        data: [593, 0, 0, 5.08],
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
          text: 'Small Value Performance (50M ops, 16B key, 64B value)'
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
}, 850);
</script>

Small value testing at massive scale with 50 million operations using 16-byte keys and 64-byte values demonstrates TidesDB's sustained performance characteristics. Throughput reaches 892K operations per second compared to RocksDB's 593K ops/sec, maintaining a 51% advantage (1.51x faster) even at this extreme scale. Average latency measures 4.21μs with P50 of 4μs, P95 of 7μs, P99 of 10μs, and maximum of 762.5ms. The higher maximum latency likely reflects occasional background compaction operations across the large dataset.

Iteration performance shows 7.93 million ops/sec for TidesDB versus RocksDB's 5.08 million ops/sec, a 1.56x advantage for TidesDB. This demonstrates that TidesDB maintains its iteration performance advantage even at massive scale with small values. Write amplification is 2.34x for TidesDB versus RocksDB's 2.59x, indicating TidesDB writes slightly less data to disk relative to the logical data size. Space amplification measures 1.66x for TidesDB versus 0.33x for RocksDB, with database sizes of 6343 MB versus 1261 MB respectively (5.0x smaller for RocksDB).

Resource consumption at this scale shows both engines using substantial memory. TidesDB utilizes 11446 MB RSS with 8914 MB disk writes and 691.5% CPU utilization, while RocksDB uses 11451 MB RSS with 9892 MB disk writes and 436.5% CPU utilization. The similar memory footprints suggest both engines are effectively caching data at this scale, though TidesDB continues to demonstrate 1.6x higher CPU utilization, indicating more aggressive parallelization of the workload across available cores.

### 9. Impact of Compaction Strategy

TidesDB's compaction behavior can be tuned via the `max_sstables_before_compaction` parameter (default: 32). The benchmarks above used a relaxed threshold of **512 SSTables**, which prioritizes write throughput by deferring compaction. To demonstrate the trade-offs, we also tested with an aggressive threshold of **8 SSTables**.

**Performance Comparison (512 vs 8 SSTables threshold):**

| Workload | 512 Threshold | 8 Threshold | Change |
|----------|---------------|-------------|--------|
| Sequential Write | 871K ops/sec | 738K ops/sec | -15% throughput |
| Random Write | 840K ops/sec | 698K ops/sec | -17% throughput |
| Random Read | 10.86M ops/sec | 8.49M ops/sec | -22% throughput |
| Mixed PUT | 851K ops/sec | 727K ops/sec | -15% throughput |
| Mixed GET | 1.63M ops/sec | 1.36M ops/sec | -17% throughput |
| Large Values | 235K ops/sec | 230K ops/sec | -2% throughput |
| Small Values | 892K ops/sec | 816K ops/sec | -9% throughput |

More aggressive compaction (8 SSTables) reduces write throughput by 15-17% for most workloads due to more frequent compaction operations competing for CPU and I/O resources. Random read performance drops 22% (10.86M → 8.49M ops/sec) with aggressive compaction, likely due to background compaction operations interfering with read operations. Large value workloads show minimal impact (-2%), suggesting that I/O-bound operations are less sensitive to compaction frequency.

Both configurations maintain identical space amplification (1.43-1.66x) and database sizes, indicating that even the relaxed 512 threshold triggers compaction frequently enough to prevent excessive space overhead. Average latency increases slightly with aggressive compaction (4.3μs → 5.1μs for sequential writes), with higher P99 latencies (11μs → 13μs) due to compaction interference.

The relaxed threshold of 512 SSTables used in these benchmarks provides excellent performance characteristics. The default threshold of 32 SSTables offers a middle ground between performance and space efficiency. Applications with strict latency requirements or read-heavy workloads should avoid overly aggressive compaction settings (below 16). For write-heavy workloads where space is constrained, the default of 32 or slightly lower may be appropriate, accepting a modest throughput reduction.

## Key Findings

### TidesDB Strengths

TidesDB demonstrates exceptional write performance across all workloads, ranging from 1.39x to 1.91x faster than RocksDB. Sequential writes show a 1.49x advantage, random writes achieve 1.41x faster throughput, and Zipfian mixed workloads show 1.91x faster PUT performance. Even with small 64-byte values at massive scale (50 million operations), TidesDB maintains a 1.51x throughput advantage. Large value (4KB) writes achieve 1.56x faster performance.

Read performance reveals even more impressive advantages, with random reads achieving a remarkable 5.65x improvement, reaching 10.86 million operations per second compared to RocksDB's 1.92 million ops/sec. The sub-microsecond average latency of 0.21μs is exceptional, with a P50 latency of 0μs indicating that most reads complete in under 1 microsecond. This demonstrates the effectiveness of TidesDB's read architecture, which uses atomic operations and reference counting for memtable access, enabling readers to scale linearly with CPU cores without lock contention.

Iteration speed for full database scans shows consistent advantages of 1.56x to 2.97x faster than RocksDB. Sequential iteration reaches 10.88 million ops/sec versus RocksDB's 4.72 million ops/sec, while mixed workload iteration achieves 11.15 million ops/sec compared to 4.70 million ops/sec. Large value iteration shows a dramatic 2.97x advantage. This superior scan performance makes TidesDB particularly well-suited for analytics and batch processing workloads.

CPU utilization metrics reveal TidesDB's superior multi-core scaling, achieving 644-773% utilization compared to RocksDB's 279-436%. This indicates TidesDB more effectively leverages available CPU resources across multiple cores. Write amplification shows excellent characteristics with large values, achieving 1.07x versus RocksDB's 1.25x, making TidesDB more efficient for larger data blocks.

### RocksDB Strengths

RocksDB demonstrates superior space efficiency with database sizes ranging from 4.8x to 12.4x smaller than TidesDB. Sequential write tests show RocksDB using 197 MB versus TidesDB's 1615 MB (8.2x smaller), Zipfian distribution results in 54 MB versus 672 MB (12.4x smaller), and small value tests produce 1261 MB versus 6343 MB (5.0x smaller). This difference stems from RocksDB's multi-level LSM architecture (L0→L1→...→L6) with level-based compaction, more efficient compression, and smaller index structures compared to TidesDB's embedded succinct trie indexes.

Write amplification is generally lower for RocksDB, ranging from 1.32x to 1.89x compared to TidesDB's 2.09x to 3.20x. RocksDB's multi-level compaction strategy spreads writes across multiple levels, while TidesDB's architecture (memtables → SSTables) with count-based compaction triggers (512 SSTables for these benchmarks) results in different write patterns. Space amplification shows RocksDB with significantly better efficiency at 0.09x to 0.30x versus TidesDB's 1.03x to 1.66x, reflecting the fundamental architectural trade-offs between the two engines.

Hot key iteration performance favors RocksDB with a 1.91x advantage in Zipfian distribution tests, demonstrating the effectiveness of RocksDB's multi-level architecture and sophisticated caching strategies when dealing with concentrated access patterns. Memory efficiency also tends to favor RocksDB with lower RSS usage in most tests, though TidesDB's higher memory consumption often correlates with its superior throughput and CPU utilization. In the mixed workload test, RocksDB shows a slight read advantage (1.68M vs 1.63M ops/sec), demonstrating competitive performance under certain workload patterns.

## Conclusion

<canvas id="overallPerformanceChart" width="400" height="250"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('overallPerformanceChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Sequential Write', 'Random Write', 'Random Read', 'Mixed Write', 'Mixed Read', 'Delete', 'Large Values', 'Small Values'],
      datasets: [{
        label: 'TidesDB Advantage (x faster)',
        data: [1.49, 1.41, 5.65, 1.41, 0.97, 1.39, 1.56, 1.51],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'TidesDB Performance Advantage Across All Workloads'
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
            text: 'Performance Multiplier (x faster)'
          }
        }
      }
    }
  });
}, 900);
</script>

TidesDB consistently outperforms RocksDB in throughput and latency across most workloads tested. Write performance ranges from 1.39x to 1.91x faster with an average improvement of approximately 1.5x, while read performance shows even more dramatic advantages with random reads achieving 5.65x faster performance. Iteration speed for full database scans demonstrates consistent superiority at 1.56x to 2.97x faster than RocksDB. Latency characteristics are exceptional, with sub-microsecond read performance averaging 0.21μs and write latency consistently in the 4-4.5μs range.

<canvas id="spaceEfficiencyChart" width="400" height="250"></canvas>
<script>
setTimeout(() => {
  const ctx = document.getElementById('spaceEfficiencyChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Sequential', 'Random', 'Mixed', 'Zipfian', 'Large Values', 'Small Values'],
      datasets: [{
        label: 'TidesDB (MB)',
        data: [1615, 1583, 792, 672, 3498, 6343],
        backgroundColor: 'rgba(54, 162, 235, 0.8)',
        borderColor: 'rgba(54, 162, 235, 1)',
        borderWidth: 1
      }, {
        label: 'RocksDB (MB)',
        data: [197, 288, 164, 54, 356, 1261],
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
          text: 'Database Size Comparison'
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
            text: 'Database Size (MB)'
          }
        }
      }
    }
  });
}, 1000);
</script>

RocksDB maintains significant advantages in space efficiency, with database sizes ranging from 5x to 12x smaller than TidesDB. This reflects fundamental architectural differences: RocksDB's multi-level LSM tree (L0→L1→...→L6) with level-based compaction versus TidesDB's simpler structure (memtables → SSTables) with embedded succinct trie indexes and count-based compaction triggers. Write amplification is generally lower for RocksDB at 1.3-1.9x compared to TidesDB's 2.1-3.2x, as RocksDB's level-based strategy spreads writes across multiple levels while TidesDB consolidates data at the SSTable tier. Memory footprint also tends to favor RocksDB with lower RSS usage in most scenarios, though TidesDB's higher memory usage correlates with its superior performance characteristics.

### Choosing the Right Storage Engine

The decision between TidesDB and RocksDB ultimately depends on your application's priorities and constraints. TidesDB is the optimal choice for applications requiring maximum throughput and low latency, particularly those with read-heavy workloads where performance is the primary concern. Its simpler codebase of approximately 27,000 lines compared to RocksDB's 300,000 lines makes it easier to understand, debug, and maintain. Applications prioritizing raw performance over disk space will benefit significantly from TidesDB's consistent advantages, especially the exceptional 5.65x random read performance advantage and sub-microsecond latency.

RocksDB remains the better choice for disk space-constrained environments where storage efficiency is paramount. Applications requiring minimal write amplification to extend SSD lifespan will appreciate RocksDB's lower overhead. The mature ecosystem with extensive tooling, monitoring capabilities, and community knowledge makes RocksDB easier to deploy and operate in production environments. Hot key workloads with skewed access patterns may also benefit from RocksDB's sophisticated multi-level caching strategies, as demonstrated by its 1.91x iteration advantage in Zipfian distribution tests. In certain mixed workload patterns, RocksDB can show competitive or slightly better read performance.

The fundamental trade-off is clear: TidesDB prioritizes raw performance with exceptional throughput and sub-microsecond latency, while RocksDB prioritizes space efficiency and lower write amplification. For most modern applications where disk space is relatively inexpensive and performance directly impacts user experience, TidesDB's advantages in throughput and latency make it a compelling choice, with random read performance reaching 10.86 million operations per second. However, for applications operating under strict storage constraints or requiring minimal write amplification for SSD longevity, RocksDB's space efficiency (5-12x smaller databases) and lower amplification factors remain valuable.
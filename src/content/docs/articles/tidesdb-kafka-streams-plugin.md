---
title: "TidesDB for Kafka Streams - Drop-in RocksDB Replacement"
description: "Introducing the TidesDB Kafka Streams plugin - a drop-in replacement for RocksDB that delivers better throughput, lower latency, and reduced storage footprint."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-mareesettons-4719352.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-mareesettons-4719352.jpg
---

<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>

<div class="article-image">

![TidesDB for Kafka Streams](/pexels-mareesettons-4719352.jpg)

</div>

*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on January 26th, 2026*

Kafka Streams is powerful. The default state store, RocksDB, is battle-tested. But what if you could do better?

Today we've dropped the TidesDB Kafka Streams plugin - a drop-in replacement for RocksDB that brings TidesDB's lock-free and adaptive architecture to your streaming applications.

## Why Switch?

The benchmarks speak for themselves. Across 8 different workload types, TidesDB outperforms RocksDB rather consistently.

<div style="max-width: 800px; margin: 2rem auto;">
  <canvas id="benchmarkChart"></canvas>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
  const ctx = document.getElementById('benchmarkChart').getContext('2d');
  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: [
        'Sequential Writes (100K)',
        'Random Writes (100K)',
        'Sequential Reads (100K)',
        'Random Reads (100K)',
        'Mixed Workload (50K)',
        'Range Scans (10K)',
        'Bulk Writes (50K)',
        'Updates (50K)'
      ],
      datasets: [
        {
          label: 'TidesDB (ms)',
          data: [91, 88, 5, 7, 52, 0.5, 49, 49],
          backgroundColor: 'rgba(59, 130, 246, 0.8)',
          borderColor: 'rgba(59, 130, 246, 1)',
          borderWidth: 1
        },
        {
          label: 'RocksDB (ms)',
          data: [188, 186, 8, 13, 106, 1, 99, 101],
          backgroundColor: 'rgba(239, 68, 68, 0.8)',
          borderColor: 'rgba(239, 68, 68, 1)',
          borderWidth: 1
        }
      ]
    },
    options: {
      responsive: true,
      plugins: {
        title: {
          display: true,
          text: 'TidesDB vs RocksDB - Kafka Streams Benchmarks',
          font: { size: 16 }
        },
        legend: {
          position: 'top'
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: 'Time (ms)'
          }
        },
        x: {
          ticks: {
            maxRotation: 45,
            minRotation: 45
          }
        }
      }
    }
  });
});
</script>

Full benchmark data available in Github repository <a href="https://github.com/tidesdb/tidesdb-kafka" target="_blank">here</a>.

## How Easy Is It?

Three lines of code. That's it.

**Before (RocksDB)**
```java
StreamsBuilder builder = new StreamsBuilder();
KTable<String, Long> counts = source
    .groupBy((key, value) -> value)
    .count();
```

**After (TidesDB)**
```java
StreamsBuilder builder = new StreamsBuilder();
KTable<String, Long> counts = source
    .groupBy((key, value) -> value)
    .count(Materialized.as(new TidesDBStoreSupplier("counts-store")));
```

Import `TidesDBStoreSupplier`, pass it to `Materialized.as()`, done.

## Installation

```bash
git clone https://github.com/tidesdb/tidesdb-kafka.git
cd tidesdb-kafka
./install.sh
./run.sh # Test, benchmark, generate charts, etc
```

The install script handles everything - building TidesDB, the JNI bindings, and installing the plugin to your local Maven repository.

## What You Get

- 2x faster writes -- TidesDB's lock-free block manager eliminates write contention
- Lower latency -- No locks means no waiting
- Better compression -- TidesDB's columnar storage reduces disk footprint
- Same API -- Full `KeyValueStore` interface compatibility

The same architectural advantages that make TidesDB fast on modest hardware translate directly to Kafka Streams. Your state stores benefit from lock-free concurrency, atomic operations, and efficient storage layout.

## Try It

Run the benchmarks yourself:

```bash
:~/tidesdb-kafka$ ./run.sh
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
░░       TidesDB Kafka Streams -- Test Runner       ░░
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

Usage: ./run.sh [options]

Options:
  -t, --tests        Run unit tests
  -b, --benchmarks   Run benchmarks
  -c, --charts       Generate charts from benchmark data
  -a, --all          Run everything
  -h, --help         Show this help message
```

The numbers don't lie. Give it a try.

*Thanks for reading!*

---

**Links**
- GitHub · https://github.com/tidesdb/tidesdb-kafka
- TidesDB Core · https://github.com/tidesdb/tidesdb
- Benchmark Charts · https://github.com/tidesdb/tidesdb-kafka/tree/master/benchmarks/charts

Join the TidesDB Discord for more updates and discussions at https://discord.gg/tWEmjR66cy

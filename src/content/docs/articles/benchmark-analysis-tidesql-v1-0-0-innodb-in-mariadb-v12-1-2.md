---
title: "Benchmark Analysis on TidesDB (TideSQL v1.0.0) & InnoDB in MariaDB v12.1.2"
description: "Benchmark analysis comparing TidesDB (TideSQL v1.0.0) and InnoDB in MariaDB v12.1.2"
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-erwan-grey-33203471-27056104.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-erwan-grey-33203471-27056104.jpg
---

<div class="article-image">

![Benchmark Analysis on TidesDB & InnoDB in MariaDB v12.1.2](/pexels-erwan-grey-33203471-27056104.jpg)

</div>

*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on Feb 1st, 2026*

Hey everyone, today <a href="https://github.com/tidesdb/tidesql">TideSQL v1.0.0</a> was released; the first major release of the pluggable <a href="https://mariadb.org">MariaDB</a> engine built on TidesDB!

Of course I had to do some benchmarks and in this article I'll share the results of my analysis comparing TidesDB with <a href="https://en.wikipedia.org/wiki/InnoDB">InnoDB</a> in MariaDB v12.1.2.

**Environment**
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)
- Ubuntu 23.04 x86_64 6.2.0-39-generic
- TidesDB v7.4.4
- GCC (glibc)


The scripts used for benchmarking can be found in the <a href="https://github.com/tidesdb/tidesql/tree/master/bench">bench</a> directory of the TideSQL repository.  The 2 scripts ran were `run_benchmark_procedures.sh` and `run_benchmark_extended.sh`.

I would honestly benchmark your workload before making any decisions, but I hope this gives you some insight into the performance characteristics of TidesDB and InnoDB. Also consider TidesDB's plugin engine is still in it's early stages and there is **a lot of room for improvement**.

With that said, let's dive into the results.

## Sequential INSERT

![Sequential INSERT](/benchmark-analysis-tidesdb-innodb-in-mariadb-v12-1-2-feb1-2026/fig1.png)

First up is sequential inserts. These tests heavily favor an engine that can turn ordered writes into append-friendly I/O, and TidesDB does exactly that. InnoDB's B-tree maintenance and secondary index costs show up clearly here. A 5x+ gap is large enough to be architectural, not accidental.

## Batch INSERT

![Batch INSERT](/benchmark-analysis-tidesdb-innodb-in-mariadb-v12-1-2-feb1-2026/fig2.png)

In the batch insert test, InnoDB is slightly faster, but the margin is small—about 7%. Given the broader results, this looks less like a structural advantage and more like a workload-specific effect of how batching interacts with InnoDB's write path. The result doesn't contradict TidesDB's strength on sequential and low-concurrency inserts; it just shows that once inserts are grouped and amortized, InnoDB's overhead matters less. This is a case where the difference exists, but it's not decisive.

## Random READ

![Random READ](/benchmark-analysis-tidesdb-innodb-in-mariadb-v12-1-2-feb1-2026/fig3.png)

Random reads strongly favor InnoDB when TidesDB block cache isn't warmed up, which isn't surprising. This workload rewards mature buffer pool behavior, optimized B-tree traversal, and years of tuning for OLTP read paths. TidesDB pays a clear penalty here though this can potentially change in long running large data scenarios.

## Random UPDATE

![Random UPDATE](/benchmark-analysis-tidesdb-innodb-in-mariadb-v12-1-2-feb1-2026/fig4.png)

For random updates, the two engines land in roughly the same neighborhood. InnoDB is slightly ahead, but the difference is small relative to the total cost of doing random updates at all. Though I think this is MariaDB's bottleneck and not TidesDB's.  Something we need to work on on either side.

## Sequential READ

![Sequential READ](/benchmark-analysis-tidesdb-innodb-in-mariadb-v12-1-2-feb1-2026/fig5.png)

Sequential reads go back to favoring InnoDB, which makes sense given it's a b-tree based storage engine optimized for sequential access patterns.

## Sequential UPDATE

![Sequential UPDATE](/benchmark-analysis-tidesdb-innodb-in-mariadb-v12-1-2-feb1-2026/fig6.png)

Sequential updates slightly favor TidesDB. The margin isn't huge, but it's consistent with the sequential insert result.

## Zipfian READ

![Zipfian READ](/benchmark-analysis-tidesdb-innodb-in-mariadb-v12-1-2-feb1-2026/fig7.png)

Zipfian reads reward InnoDB in this benchmark until TidesDB's block cache warms up at which point both engines perform similarly potentially.

## Zipfian UPDATE

![Zipfian UPDATE](/benchmark-analysis-tidesdb-innodb-in-mariadb-v12-1-2-feb1-2026/fig8.png)

Zipfian updates narrow the gap. InnoDB still wins, but _not by much_. 

## Table size (MB)

![Table size (MB)](/benchmark-analysis-tidesdb-innodb-in-mariadb-v12-1-2-feb1-2026/fig9.png)

This plot shows a large and meaningful gap. InnoDB uses roughly 12 MB to store about 1.3 MB of logical data, while TidesDB uses about 2.4 MB for the same payload 

That's not noise and it's not tuning; it's a consequence of structure. InnoDB pays for B-trees, pages, free space, and metadata. If storage footprint matters, this result alone is hard to ignore.

## P95 latency – INSERT

![P95 latency – INSERT](/benchmark-analysis-tidesdb-innodb-in-mariadb-v12-1-2-feb1-2026/fig10.png)

At the 95th percentile, TidesDB inserts are dramatically more predictable. InnoDB shows a long tail, with occasional stalls that push p95 close to 0.4 ms, while TidesDB stays well under 0.1 ms 


## P95 latency – SELECT

![P95 latency – SELECT](/benchmark-analysis-tidesdb-innodb-in-mariadb-v12-1-2-feb1-2026/fig11.png)

For reads, the situation reverses. InnoDB's p95 SELECT latency is significantly lower, while TidesDB shows both higher average and worse tail latency obviously.

## P95 latency – UPDATE

![P95 latency – UPDATE](/benchmark-analysis-tidesdb-innodb-in-mariadb-v12-1-2-feb1-2026/fig12.png)

Updates land somewhere in between. TidesDB again has tighter tail latency, while InnoDB shows more variance and higher p95 

This suggests that once a write is accepted, TidesDB can process it with fewer surprises, while InnoDB's complexity creates more opportunities for stalls. Still, the absolute differences are small enough that workload shape will matter more than raw numbers.

## INSERT scaling vs threads

![INSERT scaling vs threads](/benchmark-analysis-tidesdb-innodb-in-mariadb-v12-1-2-feb1-2026/fig13.png)

This is something I need to investigate and maybe run longer benchmarks, TidesDB scales linearly and is mostly lock-free, so this is an odd result.  I think there are potential things I need to optimize further in the TideSQL plugin, or discuss with the MariaDB team about potential improvements. It could also be a limitation of the benchmark script itself that I need to address.

## Space amplification

![Space amplification](/benchmark-analysis-tidesdb-innodb-in-mariadb-v12-1-2-feb1-2026/fig14.png)

Space amplification summarizes what the size chart already hinted at. InnoDB uses ~9.7x the logical data size, while TidesDB uses ~1.9x 

This is one of those metrics that doesn't matter until it suddenly matters a lot - on SSD cost, cache residency, and backup time. 

## Summary

Taken together, the two benchmark runs tell a consistent and fairly clean story:

InnoDB is rather optimized for reads, mixed workloads, and concurrency in these benchmarks. It scales well with threads, delivers lower read latency, and handles skew and randomness gracefully. The cost is higher space usage, more write amplification, and less predictable write latency.

TidesDB is optimized for write efficiency and compactness. It shines on sequential inserts, has tight write latency distributions, and uses far less disk space. The trade-off is weaker read performance.

The important takeaway is that these differences are structural, not tuning artifacts. You're seeing design choices expressed as numbers.

That's it for now!

*Thanks for reading!*

---

To download the raw benchmark data, click [here](/benchmark-analysis-tidesdb-innodb-in-mariadb-v12-1-2-feb1-2026/benchmark-data.zip).


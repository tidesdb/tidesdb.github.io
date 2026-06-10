---
title: "sysbench Analysis on TideSQL v4.5.6 & InnoDB in MariaDB v11.8.6"
description: "sysbench small cache/buffer, many tables analysis on TideSQL v4.5.6 & InnoDB in MariaDB v11.8.6"
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-lindsay-macnevin-17121675-6421224.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-lindsay-macnevin-17121675-6421224.jpg
---

<div class="article-image">

![sysbench Analysis on TideSQL v4.5.6 & InnoDB in MariaDB v11.8.6](/pexels-lindsay-macnevin-17121675-6421224.jpg)

</div>

*by <a target="_blank" href="https://alexpadula.com">Alex Gaetano Padula</a>*
 
*published on June 10th, 2026*


In this short article I'll be going over my recent small cache/buffer sysbench analysis on TideSQL v4.5.6 and InnoDB in MariaDB v11.8.6.

You can find configurations for MariaDB here on the *gist* I created: <a target="_blank"  href="https://gist.github.com/guycipher/90528c3af85b17139cdf2675048fe9ba">https://gist.github.com/guycipher/90528c3af85b17139cdf2675048fe9ba</a>

My environment for analysis:
- Intel Core i7-11700K, 8 cores and 16 threads, at 3.6GHz
- 46.8 GiB DDR4
- Ubuntu 23.03, Linux 6.2.0 x86_64
- WD Blue WDS500G2B0A, a consumer SATA SSD, ext4, 159 GiB volume
- gcc 12.3.0, linked against jemalloc 
- TidesDB <a target="_blank" href="https://github.com/tidesdb/tidesdb/releases/tag/v9.3.6">v9.3.6</a>

Few things to start.

- On the four write workloads TidesDB is 9x to 51x the throughput of InnoDB and has 11x to 97x lower p95 latency. None of this is subtle.
- On point-select InnoDB is faster on throughput (18.6k vs 16.9k TPS, ~10% ahead) but TidesDB still has the lower tail (0.55 ms vs 1.25 ms p95). So even the one workload InnoDB "wins" it wins narrowly and only on the mean.
- The interesting result is not that an LSM beats a B-tree on writes, that is expected. It is how much, and that the read regression is small.
- Caveat up front, this is one machine, one config, uniform-random access, 120 s runs. 

The harness (`sysbench_compare.sh`) runs each engine sequentially, thus prepare >> 60 s warmup (discarded) >> 3 measured runs of 120 s >> drop. It reports the *median* of the 3 runs.

- 16 tables x 5M rows = 80M rows, roughly 18 GB on InnoDB.
- 16 threads, `--rand-type=uniform` (spread across the whole dataset, so this is disk/IO-bound, not a cache-resident microbenchmark).
- Both engines run the same `--mysql-ignore-errors=1213,1205,1062,1020,2013` list, so a write-write conflict, lock-wait, or backpressure stall *restarts* the transaction on either engine rather than aborting the run. The harness counts how often that happens.


So let's get into the results shall we.

Median of 3 x 120 s runs. TPS speedup is TidesDB/InnoDB; p95 improvement is InnoDB/TidesDB (>1 favors TidesDB on both).

| Workload | InnoDB TPS | TidesDB TPS | TPS ratio | InnoDB p95 (ms) | TidesDB p95 (ms) | p95 ratio |
|---|--:|--:|--:|--:|--:|--:|
| Point Select | 18,646 | 16,861 | **0.90x** | 1.25 | 0.55 | 2.3x |
| Read/Write | 141 | 1,674 | **11.8x** | 397.39 | 17.63 | 22.5x |
| Update (Index) | 684 | 34,775 | **50.9x** | 77.19 | 0.80 | 96.5x |
| Update (Non-Index) | 1,597 | 29,736 | **18.6x** | 28.16 | 0.95 | 29.6x |
| Insert | 3,564 | 33,804 | **9.5x** | 12.98 | 1.18 | 11.0x |
| Delete | 879 | 13,224 | **15.0x** | 41.10 | 2.22 | 18.5x |

![Throughput](/sysbench-tidesql-v4-5-6-innodb-mariadb-v11-8-6-tidesdb-v9.3.6/fig1_throughput_tps.png)
![p95 latency](/sysbench-tidesql-v4-5-6-innodb-mariadb-v11-8-6-tidesdb-v9.3.6/fig2_p95_latency.png)
![Speedup ratios](/sysbench-tidesql-v4-5-6-innodb-mariadb-v11-8-6-tidesdb-v9.3.6/fig3_speedup.png)

InnoDB does update-in-place on a B-tree; at 18 GB with uniform access most updates touch a page that isn't in the buffer pool, so each write is a read-modify-write against the disk. That is exactly what the read_write run shows, it starts near 2.3k TPS while the working set is partly warm, then sags to ~1.4k as it goes IO-bound, with p95 walking out to ~400 ms. The LSM appends and defers the merge, so the same workload stays in the 1.6k–2.0k TPS band with p95 under 20 ms. Update-index is the extreme case at 51x because a secondary-index update on a B-tree is two pessimistic page writes and on an LSM is two appends.

Point-select is the honest column. This is the workload where InnoDB's B-tree should be at its best in that a read-only lookup is one index descent with no merge to pay for, and InnoDB wins it, by ~10% on throughput. TidesDB gives back some read throughput (the LSM may probe several levels and a bloom filter per lookup) but its p95 is still lower. I would not oversell the point-select p95 win, both are sub-millisecond and at that scale the difference is noise-adjacent, but the throughput gap is real and in InnoDB's favor. An LSM is not free on reads, and the table shows the price.

Watch the tails, not just the medians. The TidesDB insert run is not a flat line, one 10 s window dropped from ~83k TPS to ~8.5k, and the per-run max latency hit ~3.5 s. That is a graduated stall, throughput is high and smooth until a queue fills, and or memtable flush or compaction backs up, and then a few transactions eat the bill. The p95 stays good (1.18 ms) because the stall is rare, but a p99.9 or max-latency column would be less flattering, and a sustained multi-hour run that lets compaction debt accumulate is the real test of whether that 33k insert TPS holds. 


For write-heavy OLTP against a dataset that doesn't fit in cache, TidesDB is in a different performance class than InnoDB, and it gives up very little on reads to get there. Though per usual, please benchmark your workload and get your own numbers.

That's all for now, to find the raw data and scripts used you can find that zip here: <a href="/sysbench-tidesql-v4-5-6-innodb-mariadb-v11-8-6-tidesdb-v9.3.6/sysbench-tidesql-v4-5-6-innodb-mariadb-v11-8-6-tidesdb-v9.3.6.zip">sysbench-tidesql-v4-5-6-innodb-mariadb-v11-8-6-tidesdb-v9.3.6.zip</a> (sha256: cdec3cd74343424b55f1ed832b2030434339f1e325e2e7a6cec715e1cabbd455)
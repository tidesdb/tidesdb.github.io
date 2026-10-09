---
title: "Large TPC-C Analysis with MySQL v26.7.0 on InnoDB and TidesDB"
description: "TPC-C analysis using HammerDB on 4000 warehouses and VU sweep from 4 to 1024 on MySQL v26.7.0 on InnoDB and TidesDB."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-alexn-34164215.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-alexn-34164215.jpg
---

<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>

<div class="article-image">

![Large TPC-C Analysis with MySQL v26.7.0 on InnoDB and TidesDB](/pexels-alexn-34164215.jpg)
<a target="_blank" href="https://www.instagram.com/alex.ning.photography">Alex Ning</a>
</div>

*by <a target="_blank" href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on October 9th, 2026*

<a target="_blank" href="https://en.wikipedia.org/wiki/Log-structured_merge-tree">Log-structured</a> engines have a familiar reputation. They're fast on writes and slower on reads and I think it's overdue for a rethink.

With TidesDB now available in <a target="_blank" href="https://www.mysql.com/">MySQL</a> through <a target="_blank" href="https://github.com/tidesdb/tidesql-mysql">TideSQL</a>, I wanted to share that this reputation isn't always true through the most demanding OLTP benchmark I know, TPROC-C, <a target="_blank" href="https://hammerdb.com">HammerDB</a>'s derivative of <a target="_blank" href="https://www.tpc.org/tpcc/">TPC-C</a>. It's a heavy mix of reads, writes and contention, and it's the same workload behind much of TidesDB's profiling and optimization work.

TidesDB isn't the LSM that reputation describes. TidesDB is designed from first principles and is a hybrid, in that each SSTable utilizes key value seperation by default and it's key log's are B+tree's carrying an auxiliary footer with detailed meta and a partitioned bloom filter, so most levels are ruled out before they're touched. Values of 1 KiB by default and up go to a shared value log, so compaction moves keys and never values (more in <a target="_blank" target="_blank" href="https://tidesdb.com/articles/keys-and-values-dont-always-belong-together/">keys and values don't always belong together</a>).. What's left is read amplification. A key can live at more than one level within a table/column family, and a read has to find the current copy. That's the one tax log-structured systems pay, and compaction keeps it small.



This is a large benchmark so I loaded 4,000 warehouses per engine and swept the virtual user (VU) count, which is like the concurrency level, from 4 to 1,024.

Here's the server environment:
- Intel i9-13900, 24 threads online, 8 P-core (5.3-5.6 GHz) + 16 E-core (4.2 GHz)
- the 8 P-cores isolated for the run
- Ubuntu 24.04.4 LTS (6.8.0-136-generic)
- 125.5 GiB DDR5, no ECC
- NVMe Micron 7450, xfs, separate from the OS disk
- gcc 13.3.0
- glibc
- MySQL v26.7.0, TidesDB v10.1.1, TideSQL v2.0.0, HammerDB 6

My configurations are inspired by ([mariaio.cnf](https://hammerdb.com/ci-config/mariaio.cnf)) and ([mysqlio.cnf](https://hammerdb.com/ci-config/mysqlio.cnf)) which are recommendations from HammerDB.

Each engine is configured based on research for peak throughput on NVMe with 64 GB for caching/buffering, isolation level RR (repeatable read), compression and binlogging off. 

Every run restores from a copy taken straight after the build and drops the page cache before starting.  Ten minutes of rampup, twenty minutes measured, and three runs at each engine's peak with a median.

HammerDB partitions the order tables above 200 warehouses, and <a target="_blank" href="https://dev.mysql.com/doc/refman/8.0/en/upgrading-from-previous-series.html">MySQL 8</a> and up dropped the generic partitioning layer, so partitioning is only available to an engine that implements it natively.  InnoDB does, TidesDB does not.  Both engines therefore run unpartitioned.

It is easy to read a TPC-C result as a write benchmark but it is not one.  8% of it is read-only outright.  The other 92% is read-modify-write, and most of the work inside it is point lookups by primary key.


A write to TidesDB is an append. InnoDB finds a page, modifies it, and writes it back through the doublewrite buffer with redo on top. In the sysbench runs from the <a target="_blank" href="/articles/tidesdb-now-available-for-mysql/">TideSQL for MySQL release</a>, that gave TidesDB 5.4x on update index, 4.6x on write only and 6.0x on delete, with 17x to 47x fewer bytes reaching the device per operation. TPROC-C won't show you that gap.

TidesDB is optimistic and takes no row locks, so conflicts surface at commit as a retryable failure rather than as lock waits. HammerDB doesn't retry. Every error against TidesDB is a transaction that did its work and was refused at commit, which an application would simply retry.

The 4,000-warehouse build took InnoDB 6,193 seconds and 374 GiB, and TidesDB 8,464 seconds and 306 GiB. InnoDB loads faster, and TidesDB stores the same data in 68 GiB less.

![Schema build time](/large-tpc-c-analysis-with-mysql-v26-7-0-on-innodb-and-tidesdb/build_time.png)

TidesDB leads at every point. Both engines peak at 32 VU, where TidesDB's median of three runs is 159,587 NOPM against InnoDB's 126,121, about 1.27x.

![TPROC-C throughput vs concurrency](/large-tpc-c-analysis-with-mysql-v26-7-0-on-innodb-and-tidesdb/nopm_vs_vu.png)

![Peak TPROC-C throughput](/large-tpc-c-analysis-with-mysql-v26-7-0-on-innodb-and-tidesdb/peak_nopm.png)

![All transactions vs concurrency](/large-tpc-c-analysis-with-mysql-v26-7-0-on-innodb-and-tidesdb/tpm_vs_vu.png)

Neither engine falls over past its peak. TidesDB keeps 88% of its peak out at 1,024 VU and InnoDB keeps 97% of its own, but from a lower peak, so TidesDB is still 15% ahead at the top of the sweep.

For latency at peak TidesDB's new order p99 is 13.46ms against InnoDB's 36.38ms, about a third. The gap narrows as concurrency climbs and past 512 VU it reverses. At 1,024 VU InnoDB's tail is better, 555.93 ms against 621.88 ms.

![New order p99 vs concurrency](/large-tpc-c-analysis-with-mysql-v26-7-0-on-innodb-and-tidesdb/neworder_p99_vs_vu.png)

The median tells you the same thing.

![New order p50 vs concurrency](/large-tpc-c-analysis-with-mysql-v26-7-0-on-innodb-and-tidesdb/neworder_p50_vs_vu.png)

Watching a single run second by second shows TidesDB sits higher for most of the run and drops every so often, most likely backpressure while flushes and compaction do their work in the background. InnoDB is flatter and lower though still rather sporadic. 

![Throughput over time at 32 VU](/large-tpc-c-analysis-with-mysql-v26-7-0-on-innodb-and-tidesdb/throughput_over_time.png)

![Timeline for InnoDB](/large-tpc-c-analysis-with-mysql-v26-7-0-on-innodb-and-tidesdb/timeline_innodb.png)
![Timeline for TidesDB](/large-tpc-c-analysis-with-mysql-v26-7-0-on-innodb-and-tidesdb/timeline_tidesdb.png)

Here are the bytes each engine wrote to the device per transaction, from `/proc/diskstats`.

| VU | TidesDB | InnoDB | InnoDB / TidesDB |
|---:|---:|---:|---:|
| 16 | 48.7 KiB | 188.2 KiB | 3.9x |
| 32 | 45.3 KiB | 192.2 KiB | 4.2x |
| 64 | 44.8 KiB | 192.0 KiB | 4.3x |
| 128 | 47.3 KiB | 191.6 KiB | 4.1x |
| 256 | 49.2 KiB | 190.4 KiB | 3.9x |
| 512 | 49.6 KiB | 189.1 KiB | 3.8x |
| 1024 | 48.6 KiB | 187.2 KiB | 3.8x |

From 16 VU up TidesDB writes about 48 KiB and InnoDB about 190 KiB, so 4x fewer bytes while doing 27% more work.

![Errors vs concurrency](/large-tpc-c-analysis-with-mysql-v26-7-0-on-innodb-and-tidesdb/errors_vs_vu.png)

The errors are TidesDB's and InnoDB has none. Across the whole sweep TidesDB discarded 42,591 transactions out of 51.4 million, 0.083%, rising from nothing below 64 VU to 0.334% at 1,024. Those are optimistic conflicts caught at commit, HammerDB doesn't retry them they go uncounted. InnoDB takes row locks and waits instead, which is why its number is zero.

For closing TidesDB ran 27% more new orders per minute at peak, led at every concurrency level from 4 to 1,024 virtual users, answered at about a third of InnoDB's tail latency through the middle of the range, wrote 4x fewer bytes to the device per transaction, and held the same 4,000 warehouses in 68 GiB less space with compression turned off.

That's a log-structured engine on a read-dominated OLTP benchmark, on the same server, with the same memory, at the same isolation level. The reputation needed the rethink.

Thank you for reading.

-- 

For article data, figures, reproducible scripts: <a href="/large-tpc-c-analysis-with-mysql-v26-7-0-on-innodb-and-tidesdb/tpcc-mysql-4000wh.zip">tpcc-mysql-4000wh.zip (sha256: 35f5eb5deb9dba5c447e3b3bf425a322a89e614eb873d3753744d4b40cebae07)</a>
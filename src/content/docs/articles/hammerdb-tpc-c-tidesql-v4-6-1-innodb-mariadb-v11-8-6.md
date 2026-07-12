---
title: "HammerDB TPC-C TideSQL v4.6.1 & InnoDB Analysis in MariaDB v11.8.6"
description: "Benchmark analysis comparing TideSQL v4.6.1 utilizing HammerDB 6 TPROC-C."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-szafran-37745380.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-szafran-37745380.jpg
---

<div class="article-image">

![HammerDB TPC-C TideSQL v4.6.1 & InnoDB Analysis in MariaDB v11.8.6](/pexels-szafran-37745380.jpg)

</div>

*by <a target="_blank" href="https://alexpadula.com">Alex Gaetano Padula</a>*
 
*published on July 12th, 2026*
 
In this article I will be going over <a href="https://hammerdb.com">HammerDB</a> TPROC-C results on TideSQL and InnoDB in MariaDB on a dedicated large server.

*TPROC-C is a derivative of TPC-C*

Environment
- TidesDB v9.3.13
- TideSQL v4.6.1
- MariaDB v11.8.6

Server
- Intel Xeon Silver 4116 @ 2.10 GHz (Skylake-SP)
- 125 GiB DDR4 2666 MT/s
- Ubuntu 24.04.3 LTS
- NVMe Micron 7300 MTFDHBE960TDF 

![Latency](/hammerdb-tpc-c-tidesql-v4-6-1-innodb-mariadb-v11-8-6/fig_latency.png)
![Throughput](/hammerdb-tpc-c-tidesql-v4-6-1-innodb-mariadb-v11-8-6/fig_throughput.png)
![TPM](/hammerdb-tpc-c-tidesql-v4-6-1-innodb-mariadb-v11-8-6/fig_tpm_timeseries.png)

The workload is 800 warehouses, 150 virtual users, a 5 minute rampup and a 30 minute measurement window, on a. I kept the engines at parity where it matters. Both get a 32 GB cache, which is the InnoDB buffer pool on one side and the TidesDB block cache on the other. Both run at READ-COMMITTED, both relax durability (InnoDB with innodb_flush_log_at_trx_commit=0 and doublewrite off,
TidesDB with sync mode NONE), neither uses compression, the binlog is off, and both link jemalloc and TidesDB was built using PGO. 

TidesDB did better than InnoDB on both throughput and response time. It sustained 96,484 NOPM against InnoDB's 80,832, which is about 19 percent more, and the same margin holds on TPM. Latency was lower across the whole distribution and not just on average.
Median New-Order response was 33 ms against 50 ms and the p99 tail was 149 ms against 200 ms, so TidesDB was about 33 percent faster at the median and about 26 percent faster at the tail, which is not what I would expect from an LSM where compaction usually shows
up first in the tail. The throughput over time curves explain the shape. InnoDB spikes while cold and then flattens onto a plateau near 190k TPM, while TidesDB holds a higher band from roughly 230k to 330k with more variance and a slow downward drift, both of which are background compaction. One caveat is worth stating up front. TidesDB went into this run carrying a compaction backlog from the build, since the schema check stalled a little bit, so its steady state is probably a little better than what I measured. This is also a single concurrency point at 150 users and not a curve, so it says nothing yet about where the two engines cross.

In summary TidesDB ran about 19 percent more new orders per minute than InnoDB and was lower on latency at every percentile I looked at. 

That's all for this one.

*Thank you for reading*

--

Files: 
- <a href="/hammerdb-tpc-c-tidesql-v4-6-1-innodb-mariadb-v11-8-6/results.zip">results.zip (935a165666f078f2c80a79a47fc119ecf20ca455d6aeb6713c532f33dd78c2b1)</a>
- <a href="/hammerdb-tpc-c-tidesql-v4-6-1-innodb-mariadb-v11-8-6/innodb.my.cnf">innodb.my.cnf (25960238cd2ea59fdd9de6e982576c4297bd60a0b28b9a4de9fb9f2558e6485f)</a>
- <a href="/hammerdb-tpc-c-tidesql-v4-6-1-innodb-mariadb-v11-8-6/tidesdb.my.cnf">tidesdb.my.cnf (d36509e94537d7dc36549547a5465c03e0d58e85a3114bd96fe988d44a718c46)</a>
- <a href="/hammerdb-tpc-c-tidesql-v4-6-1-innodb-mariadb-v11-8-6/tprocc_800wh_150vu.tcl">tprocc_800wh_150vu.tcl</a>
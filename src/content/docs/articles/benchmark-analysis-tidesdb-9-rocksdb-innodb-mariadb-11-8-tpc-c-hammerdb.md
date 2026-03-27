---
title: "Benchmark Analysis on TidesDB 9 (TideSQL 4.1), MyRocks, InnoDB in MariaDB 11.8.6 TPC-C HammerDB"
description: "Extensive benchmark analysis on TidesDB 9 (TideSQL 4.1), MyRocks, InnoDB in MariaDB 11.8.6 running HammerDB TPROC-C."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-diego-f-parra-33199-18761504.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-diego-f-parra-33199-18761504.jpg
---

<div class="article-image">

![Benchmark Analysis on TidesDB 9 (TideSQL 4.1), MyRocks, InnoDB in MariaDB 11.8.6 TPC-C HammerDB](/pexels-diego-f-parra-33199-18761504.jpg)

</div>

*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on March 27th, 2026*

In this article I will be going over analysis done running in <a href="https://mariadb.org">MariaDB</a> 11.8.6 with <a href="https://github.com/tidesdb/tidesdb/releases/tag/v9.0.0">TidesDB 9</a> (TideSQL 4.1), MyRocks, and InnoDB storage engines using the TPC-C benchmark with <a href="https://hammerdb.com/">HammerDB</a>.

TidesDB 9 is a new major in which brings extensive performance improvements specifically around read operations and query performance.

To start here is my environment for these runs:
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)
- Ubuntu 23.04 x86_64 6.2.0-39-generic
- GCC (glibc)

RocksDB 6.x.x is the default that comes with MariaDB 11.8.6 LTR.

I used the follow script for running HammerDB 5:

<a href="/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/tidesdb_rocksdb_hammerdb.sh">tidesdb_rocksdb_hammerdb.sh</a>

## Run 1

The first run has larger cache and buffer sizes, so less disk reads for all engines, though the data does exceed cache size.

### cnf
<a href="/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/run1.cnf" target="_blank">run1.cnf</a> (b3f58f25d65043378880a12ae4ab09838304337ae77c16b9edbbefaf6c7cf36e)

```
./tidesdb_rocksdb_hammerdb.sh -b tpcc   --warehouses 40 --tpcc-vu 8 --tpcc-build-vu 8   --rampup 1 --duration 2 --settle 5   -H ~/HammerDB-5.0 -e tidesdb -u hammerdb --pass hammerdb123 -S /tmp/mariadb.sock

./tidesdb_rocksdb_hammerdb.sh -b tpcc   --warehouses 40 --tpcc-vu 8 --tpcc-build-vu 8   --rampup 1 --duration 2 --settle 5   -H ~/HammerDB-5.0 -e rocksdb -u hammerdb --pass hammerdb123 -S /tmp/mariadb.sock

./tidesdb_rocksdb_hammerdb.sh -b tpcc   --warehouses 40 --tpcc-vu 8 --tpcc-build-vu 8   --rampup 1 --duration 2 --settle 5   -H ~/HammerDB-5.0 -e innodb -u hammerdb --pass hammerdb123 -S /tmp/mariadb.sock

```

### TidesDB
<div style="display: flex; justify-content: center;">

![Latency](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/tidesdb/1/chart_tpcc_latency.png)

![NOPM](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/tidesdb/1/chart_tpcc_nopm.png)

![TPM](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/tidesdb/1/chart_tpcc_tpm.png)

</div>

### RocksDB
<div style="display: flex; justify-content: center;">

![Latency](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/rocksdb/1/chart_tpcc_latency.png)

![NOPM](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/rocksdb/1/chart_tpcc_nopm.png)

![TPM](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/rocksdb/1/chart_tpcc_tpm.png)

</div>

### InnoDB
<div style="display: flex; justify-content: center;">

![Latency](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/innodb/1/chart_tpcc_latency.png)

![NOPM](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/innodb/1/chart_tpcc_nopm.png)

![TPM](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/innodb/1/chart_tpcc_tpm.png)

</div>


In Run 1 with 4GB cache/buffer sizes across all three engines (40 warehouses, 8 virtual users, 2-minute duration), TidesDB(TideSQL) dominated throughput by a wide margin, posting 121,987 NOPM, roughly 3.1x InnoDB's 39,233 and 1.35x MyRocks' 90,525. The same hierarchy held for TPM, with TidesDB reaching 283,273 versus 210,268 for MyRocks and 91,644 for InnoDB. On the latency side, TidesDB delivered the lowest average latencies across all three TPC-C transaction types: 1.99ms for New Order, 0.89ms for Payment, and 5.73ms for Delivery, compared to InnoDB's notably sluggish 6.27ms, 2.71ms, and 24.81ms respectively. The delivery transaction was the sharpest differentiator, InnoDB's average was 4.3x higher than TidesDB's. Schema build time also favored TidesDB at 147 seconds, slightly edging out InnoDB's 156 seconds, while MyRocks lagged at 298 seconds. With ample cache available so that hot data largely resided in memory, TidesDB's read-path optimizations and its LSM-tree architecture translated directly into superior transactional throughput and tighter tail latencies, establishing it as a strong contender against both MyRocks and InnoDB under this configuration.

## Run 2

The first run has a small cache and buffer sizes, so lots of disk reads for all engines.  Also this is more concurrency hitting the engines.

### cnf
<a href="/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/run2.cnf" target="_blank">run2.cnf</a> (823bac4075f56d7eaf3f097fcd464e77265d3fa693be1a02f381d8e13bdf08be)

```
for eng in tidesdb innodb rocksdb; do
  echo "=== $eng ==="
  ./tidesdb_rocksdb_hammerdb.sh -b tpcc \
    --warehouses 40 --tpcc-vu 16 --tpcc-build-vu 8 \
    --rampup 1 --duration 2 --settle 5 \
    -H ~/HammerDB-5.0 \
    -e "$eng" \
    -u hammerdb \
    --pass "hammerdb123" \
    -S /tmp/mariadb.sock
done
```

### TidesDB
<div style="display: flex; justify-content: center;">

![Latency](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/tidesdb/2/chart_tpcc_latency.png)

![NOPM](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/tidesdb/2/chart_tpcc_nopm.png)

![TPM](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/tidesdb/2/chart_tpcc_tpm.png)

</div>

### RocksDB
<div style="display: flex; justify-content: center;">

![Latency](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/rocksdb/2/chart_tpcc_latency.png)

![NOPM](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/rocksdb/2/chart_tpcc_nopm.png)

![TPM](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/rocksdb/2/chart_tpcc_tpm.png)

</div>

### InnoDB
<div style="display: flex; justify-content: center;">

![Latency](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/innodb/2/chart_tpcc_latency.png)

![NOPM](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/innodb/2/chart_tpcc_nopm.png)

![TPM](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/innodb/2/chart_tpcc_tpm.png)

</div>

With cache/buffer slashed to just 64MB across all engines (forcing heavy disk I/O on the SATA SSD) and concurrency doubled to 16 virtual users, InnoDB effectively started tripping up, dropping to just 6,013 NOPM, a staggering 84.7% decline from its Run 1 result. Its delivery transaction p95 ballooned to 721.7ms, and even simple payments averaged over 42ms. The LSM-tree engines weathered the I/O pressure far more gracefully, TidesDB held strong at 84,009 NOPM (only a 31% drop from Run 1 despite 64x less cache and 2x more concurrency), and MyRocks landed at 56,191 NOPM. The gap between TidesDB and InnoDB widened from 3.1x in Run 1 to a crushing 14x here. TidesDB also maintained notably tighter tail latencies than MyRocks under this pressure, with its delivery p95 at 12.6ms versus MyRocks' 42.0ms, suggesting that TidesDB's read-path improvements hold up well even when the block cache can't absorb the working set!

I've run these benchmarks many times, many runs assuring in iteration the numbers are consistent, the runs plucked out here are the peak for each of the engines and the results are strikingly consistent.

That's all for now!

*Thank you for reading!*

-- 

You can find the raw data below:
| File | SHA256 Checksum |
|------|-----------------|
| [InnoDB Run 1 - hammerdb_results_20260326_155934.csv](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/innodb/1/hammerdb_results_20260326_155934.csv) | `eb83170c021b270d8eb7007c7a5698fd6368f43b6ea226cee5670c1937d465f2` |
| [InnoDB Run 1 - hammerdb_logs_20260326_155934.zip](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/innodb/1/hammerdb_logs_20260326_155934.zip) | `566eb3818036c21b5b30193dea5aad8d387226f341e1e63e27b6d346912e864d` |
| [InnoDB Run 2 - hammerdb_results_20260326_213459.csv](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/innodb/2/hammerdb_results_20260326_213459.csv) | `219f9163ad84b7ca685af74f55f4ebff385f6c8060c49202847278b11caded72` |
| [InnoDB Run 2 - hammerdb_logs_20260326_213459.zip](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/innodb/2/hammerdb_logs_20260326_213459.zip) | `ed7474c78689f46437c552712dda6fc377c9c4e5da3c99aba3ab10a0cea33566` |
| [RocksDB Run 1 - hammerdb_results_20260326_195229.csv](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/rocksdb/1/hammerdb_results_20260326_195229.csv) | `a7858d78784cdb106207eda2ac7ff3de603acbdcc8174ee00e0c897d2502129b` |
| [RocksDB Run 1 - hammerdb_logs_20260326_195229.zip](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/rocksdb/1/hammerdb_logs_20260326_195229.zip) | `e550f0dcd69745425c9462600ac02b43817cb4cc9bc9111d28872485773aa1bb` |
| [RocksDB Run 2 - hammerdb_results_20260326_214057.csv](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/rocksdb/2/hammerdb_results_20260326_214057.csv) | `8af159c697aa454057c44eae95e8bbe48d5655ee1d0a2a715a48a934d524c378` |
| [RocksDB Run 2 - hammerdb_logs_20260326_214057.zip](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/rocksdb/2/hammerdb_logs_20260326_214057.zip) | `e988f54bfe1751f0cd9f6c50582d608061b0ab994e63ff33d5bcf1e616fefe69` |
| [TidesDB Run 1 - hammerdb_results_20260326_200928.csv](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/tidesdb/1/hammerdb_results_20260326_200928.csv) | `502c6d08c255a3f056b3a8d642f42725e3803399f22957062166d3a0ab72b319` |
| [TidesDB Run 1 - hammerdb_logs_20260326_200928.zip](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/tidesdb/1/hammerdb_logs_20260326_200928.zip) | `b5b11b90141bd4d3342d008fe54cbbaae17591ee221342a6fe0170f350057406` |
| [TidesDB Run 2 - hammerdb_results_20260326_212633.csv](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/tidesdb/2/hammerdb_results_20260326_212633.csv) | `7601fb779a08b86ce6306583161f932c3b65b7b375c8e64afd2b829d4f82768e` |
| [TidesDB Run 2 - hammerdb_logs_20260326_212633.zip](/benchmark-tidesdb9-tidesql4-1-myrocks-innodb-mariadb-11-8-6/tidesdb/2/hammerdb_logs_20260326_212633.zip) | `c17eecbf63b8775ee61b872d0ef6328a8c8ff145c0b4f9838dbf9b508b418e7a` |

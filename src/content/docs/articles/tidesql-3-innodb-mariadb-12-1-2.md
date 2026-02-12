---
title: "Benchmark Analysis on TideSQL 3 and InnoDB within MariaDB 12.1.2"
description: "Deep benchmark analysis on TideSQL 3 (TidesDB Plugin) and InnoDB within MariaDB 12.1.2 across multiple OLTP workloads"
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-stephen-leonardi-587681991-18353601.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-stephen-leonardi-587681991-18353601.jpg
---

<div class="article-image">

![Benchmark Analysis on TideSQL 3 and InnoDB within MariaDB 12.1.2](/pexels-stephen-leonardi-587681991-18353601.jpg)

</div>

*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on February 11th, 2026*

I've been deep at work on the <a href="https://mariadb.org">MariaDB</a> plugin engine that's powered by TidesDB.  I've scrapped a couple early versions as the complexity and initial ideas weren't working out as I expected.  After a few weeks, lots of code, refactoring, and continuous benchmarking the results are looking really good.  You can go deep on the design of the plugin <a href="/reference/tidesql">here</a>.  In these benchmarks I used a new benchmark tool that utilizes sysbench in the background, it's written in shell and its called <a href="https://github.com/tidesdb/sqlbench">sqlbench</a>.  

I ran the tool with the following:
```bash
DATA_DIR=/media/agpmastersystem/c794105c-0cd9-4be9-8369-ee6d6e707d68/home/db-bench \
TABLE_SIZES="100000" \
TABLES=1 \
THREAD_COUNTS="8" \
TIME=60 \
WARMUP=10 \
ENGINES="TidesDB InnoDB" \
TIDESDB_SYNC_MODE=0 \
TIDESDB_COMPRESSION=LZ4 \
INNODB_FLUSH=0 \
./sqlbench.sh
```

Both engines are using REPEATABLE READ isolation level which are the defaults for both and both engines are using their defaults, but SYNC off.

My environment:
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)
- Ubuntu 23.04 x86_64 6.2.0-39-generic
- TidesDB v8.2.4 installed w/ (TideSQL 3)
- GCC (glibc)


**oltp_point_select**
![oltp_point_select](/analysis-tidesql-3-innodb-mariadb-12-1-2/oltp_point_select_tps_qps.png)

TidesDB looks to pull ahead of InnoDB on pure point lookups.  The caching layers and linear scaling capabilities are really showing here.

**oltp_read_only**
![oltp_read_only](/analysis-tidesql-3-innodb-mariadb-12-1-2/oltp_read_only_tps_qps.png)

TidesDB again leads InnoDB in read-only transactional workloads for this smaller dataset.

**oltp_write_only**
![oltp_write_only](/analysis-tidesql-3-innodb-mariadb-12-1-2/oltp_write_only_tps_qps.png)

TidesDB shows a clear advantage in write-only workloads.  LSM-tree engines are designed to optimize sequential writes and reduce random I/O amplification.  InnoDB's BTree structure incurs more random page modifications.

**oltp_read_write**
![oltp_read_write](/analysis-tidesql-3-innodb-mariadb-12-1-2/oltp_read_write_tps_qps.png)

In mixed workloads, TidesDB seems to maintain a consistent performance edge.  I'm gonna assume because of the latency reduction across multiple workloads.

**oltp_insert**
![oltp_insert](/analysis-tidesql-3-innodb-mariadb-12-1-2/oltp_insert_tps_qps.png)

This is expected as TidesDB is LSM-tree based.

**oltp_update_index**
![oltp_update_index](/analysis-tidesql-3-innodb-mariadb-12-1-2/oltp_update_index_tps_qps.png)

Indexed updates heavily favor TidesDB. Updates in LSM engines are effectively write operations (new versions appended), whereas InnoDB must modify indexed BTree pages in place. 

**oltp_update_non_index**

![oltp_update_non_index](/analysis-tidesql-3-innodb-mariadb-12-1-2/oltp_update_non_index_tps_qps.png)

TidesDB pulls ahead of InnoDB here as well.

**oltp_delete**
![oltp_delete](/analysis-tidesql-3-innodb-mariadb-12-1-2/oltp_delete_tps_qps.png)

Deletes look to strongly favor TidesDB in MariaDB.  This is because in an LSM tree, deletes are tombstones appended to the log and skip list, while InnoDB must modify index pages and potentially cause page merges. 

**space usage for point lookups**
![space usage for point lookups](/analysis-tidesql-3-innodb-mariadb-12-1-2/point_lookup_space_letter_plot.png)

In this workload, TidesDB uses less space than InnoDB but this can vary depending on your workload so do your own testing based on your needs.  TidesDB in the sysbench data used quite a bit of space in some cases but mainly because of unrealistically high updates.


Overall the plugin engine is shaping up well.  

If you have a chance, I hope you give TideSQL a dive.

*Thanks for reading!*

-- 

You can find raw results below.

| File | Checksum |
|------|----------|
| <a href="/analysis-tidesql-3-innodb-mariadb-12-1-2/results.zip" download>results.zip</a> | `aa7f755c787ece8b961b786c6af6dfd58f4e3a51f88f9fa22476f70217872dc1` |
---
title: "sysbench Read-Write Analysis TideSQL v4.5.6, MyRocks, InnoDB in MariaDB v11.8.6"
description: "Large sysbench read-write analysis on dedicated server comparing TidesDB(TideSQL), RocksDB(MyRocks), and InnoDB in MariaDB v11.8.6"
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
 
*published on June 15th, 2026*

I ran a large read-write benchmark on my dedicated server and today I'll be sharing that analysis.  I utilized sysbench and its read-write workload.

Environment:
- Intel Silver 4116
-	128GB DDR4
- 960GB NVMe Micron 7300 PRO (no-raid)
- Ubuntu 24.04 64

I ran 6 tables at 6m rows each at a total of 36m rows with --rand-type sweep (uniform + pareto + special) so a nice mix.


```
cd /root
mkdir -p ~/sbsweep_tidesdb && sysbench oltp_read_write --db-driver=mysql --mysql-socket=/tmp/mariadb.sock --mysql-user=root
--mysql-password=pw --mysql-db=sbtest --mysql_storage_engine=tidesdb --tables=8 --table_size=6000000 --threads=8 prepare
>/dev/null 2>&1 && for rt in uniform pareto special; do sysbench oltp_read_write --db-driver=mysql
--mysql-socket=/tmp/mariadb.sock --mysql-user=root --mysql-password=pw --mysql-db=sbtest --tables=8 --table_size=6000000
--threads=24 --time=30 --report-interval=1 --rand-type=$rt run 2>&1 | tee ~/sbsweep_tidesdb/oltp_rw.$rt.txt | awk '/^\[/{for(
i=1;i<=NF;i++){if($i=="tps:")t=$(i+1);if($i=="qps:")q=$(i+1);if($i=="(ms,95%):")l=$(i+1)};e=$2;gsub(/s/,"",e);print
e"\t"t"\t"q"\t"l}' > ~/sbsweep_tidesdb/oltp_rw.$rt.tsv; done && sysbench oltp_read_write --db-driver=mysql
--mysql-socket=/tmp/mariadb.sock --mysql-user=root --mysql-password=pw --mysql-db=sbtest --tables=8 --table_size=100000
cleanup >/dev/null 2>&1
echo "=== exit: $? ==="
echo "=== files in results dir ==="; ls -la ~/sbsweep_tidesdb/
echo "=== sample TSV (special) — cols: elapsed_s  tps  qps  lat95ms ==="; head -5 ~/sbsweep_tidesdb/oltp_rw.special.tsv
```


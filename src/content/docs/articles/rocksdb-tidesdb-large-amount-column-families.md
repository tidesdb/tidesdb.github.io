---
title: "Large Amount of Column Families with RocksDB and TidesDB"
description: "Comparisons of large amount of column families with RocksDB and TidesDB"
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-cottonbro-6333743.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-cottonbro-6333743.jpg
---

<div class="article-image">

![Large Amount of Column Families with RocksDB and TidesDB](/pexels-cottonbro-6333743.jpg)

</div>

*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on February 5th, 2026*

Just scouring the internet during some researching I was doing, I came a known issue with RocksDB when performing operations across many column families.

See: <a href="https://github.com/facebook/rocksdb/issues/5117">RocksDB issue #5117</a>

The plot was created by modifying the Java program at
<a href="https://github.com/grove/bugs-and-regressions/tree/master">https://github.com/grove/bugs-and-regressions/tree/master</a>
to compare RocksDB against TidesDB.

**Environment**
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)
- Ubuntu 23.04 x86_64 6.2.0-39-generic
- TidesDB v8.1.2 
- <a href="https://rocksdb.org/">RocksDB</a> v10.10.1 
- GCC (glibc)

![Large Amount of Column Families with RocksDB and TidesDB](/large-n-cfs-rocksdb-tidesdb/result.png)
![Large Amount of Column Families with RocksDB and TidesDB Scaling](/large-n-cfs-rocksdb-tidesdb/scaling-result.png)

This is running on the latest version of TidesDB and RocksDB.  Thus the issue from many years ago still lingers in RocksDB.  

TidesDB shows strong performance when working across a large number of column families. This is something I rely on heavily in the MariaDB pluggable engine, TideSQL, where column families are used extensively. In a relational system, I store metadata, indexes, and more using this approach.
Building a pluggable storage engine has not been easy.

MySQL and now <a href="https://mariadb.org">MariaDB</a> provide a wonderful interface to work with. It is intuitive to get started and then expand on what you learn while wiring things together.

I like to think of it as tying an engine to a car or a plane. There are many wires, connections, processes, and safety considerations, and I enjoy it.

I look forward to seeing what you build with TidesDB!

---

Code for comparison:

<a href="https://github.com/tidesdb/multi-cf-rocksdb-comparison/tree/update-comparison">multi-cf-rocksdb-comparison</a>

Raw data:

<a href="/large-n-cfs-rocksdb-tidesdb/scaling_results.csv">Results</a>

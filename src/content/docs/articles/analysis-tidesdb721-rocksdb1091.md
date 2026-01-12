---
title: "Benchmark Analysis of TidesDB 7.2.1 vs RocksDB 10.9.1"
description: "Examining the performance of TidesDB 7.2.1 vs RocksDB 10.9.1"
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-thuruchen-pillay-725736313-35554784.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-thuruchen-pillay-725736313-35554784.jpg
---

<div class="article-image">

![Benchmark Analysis of TidesDB 7.2.1 vs RocksDB 10.9.1](/pexels-thuruchen-pillay-725736313-35554784.jpg)

</div>

*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*January 11th, 2026*

Lot's of benchmarking the past few days, especially yesterday into today, optimizing for lower latency, better throughput, and more stable performance.

This new patch of TidesDB has shown superior and stable performance over RocksDB 10.9.1.  We can see this in the graphs below.  If you want to find the raw CSV data, you can find it [here](/tdb721-rdb1091-20260111_201323.csv).


**Hardware**
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)
- Ubuntu 23.04 x86_64 6.2.0-39-generic

**Software Versions**
- TidesDB v7.2.1
- RocksDB v10.9.1


<img src="/tidesdb721-rocksdb1091-0001.png" alt="TidesDB 7.2.1 vs RocksDB 10.9.1" />

<img src="/tidesdb721-rocksdb1091-0002.png" alt="TidesDB 7.2.1 vs RocksDB 10.9.1" />

<img src="/tidesdb721-rocksdb1091-0003.png" alt="TidesDB 7.2.1 vs RocksDB 10.9.1" />

<img src="/tidesdb721-rocksdb1091-0004.png" alt="TidesDB 7.2.1 vs RocksDB 10.9.1" />

<img src="/tidesdb721-rocksdb1091-0005.png" alt="TidesDB 7.2.1 vs RocksDB 10.9.1" />

<img src="/tidesdb721-rocksdb1091-0006.png" alt="TidesDB 7.2.1 vs RocksDB 10.9.1" />

<img src="/tidesdb721-rocksdb1091-0007.png" alt="TidesDB 7.2.1 vs RocksDB 10.9.1" />

<img src="/tidesdb721-rocksdb1091-0008.png" alt="TidesDB 7.2.1 vs RocksDB 10.9.1" />

<img src="/tidesdb721-rocksdb1091-0009.png" alt="TidesDB 7.2.1 vs RocksDB 10.9.1" />


View more about the release [here](https://github.com/tidesdb/tidesdb/releases/tag/v7.2.1).


*Thanks for reading!*

---

**Links**
- GitHub · https://github.com/tidesdb/tidesdb
- Design deep-dive · https://tidesdb.com/getting-started/how-does-tidesdb-work
- Admintool · https://github.com/tidesdb/admintool
- Discord · https://discord.gg/tWEmjR66cy
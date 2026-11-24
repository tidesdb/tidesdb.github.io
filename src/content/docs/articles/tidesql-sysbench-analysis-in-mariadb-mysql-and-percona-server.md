---
title: "TideSQL Sysbench Analysis in MariaDB, MySQL and Percona Server"
description: "Comparing how TidesDB's TideSQL performs in 3 different servers (MariaDB, MySQL, and Percona Server) utilizing sysbench."
unlisted: true
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-mavicair2tw-15328458.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-mavicair2tw-15328458.jpg
---

<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>

<div class="article-image">

![Merging Only What Overlaps](/pexels-mavicair2tw-15328458.jpg)
<a target="_blank" href="https://www.instagram.com/mavicair2tw">William Chen</a>
</div>

*by <a target="_blank" href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on TBD, 2026*

I wanted to compare how TidesDB compares in the 3 different server's the storage engine is available in:
- <a target="_blank" href="">MariaDB</a>
- <a target="_blank" href="">MySQL</a>
- <a target="_blank" href="">Percona Server</a>

All 3 integrations share their own similarilities but the foundation is the same thus the performance differences at default configuration shows us really which server is faster in the default case. 

I'm running this analysis on the server below:
- Intel i9-13900
- Ubuntu 24.04.4 LTS (6.8.0-136-generic)
- 125.5 GiB DDR5, no ECC
- NVMe Micron 7450, xfs, separate from the OS disk
- gcc 13.3.0
- glibc
- TidesDB v10.2.0, TideSQL v5.1.0, MariaDB v11.8.6, MySQL v26.7, Percona Server v8.0.0


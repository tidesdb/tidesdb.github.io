---
title: "TidesDB v7.2.2 vs RocksDB v10.9.1 Latency Analysis"
description: "Analysis of TidesDB v7.2.2 vs RocksDB v10.9.1 Latency"
---

*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*January 13th, 2026*

What's been getting to me lately is the latency and rather high CV in TidesDB v7.2.1 in a few benchmarks so I decided to do something about it.
I firstly started by tracing what could be the cause of the latency and high CV.

What I found was there were 2 main causes of the latency:
1. Skip List
2. Clock Cache

Perfing both components I found that we could utilize inline comparisons in skip list, also we could utilize prefetching.  I also thought the same regarding the clock cache.  I implemented these optimizations we went down nearly 75% of the latency for both components.

This translated to very performance improvements, across the board.

With that said you can find our benchtool results in the graphs below and the raw benchmark data below.

<img width="100%" src="/1b4f4ae9-16cd-411e-b523-5da04ab63304.png">
<img width="100%" src="/5d229368-597b-4dc9-ac09-affa33e838bd.png">
<img width="100%" src="/7d7d094f-ac85-47b4-af25-f89bba2c6560.png">
<img width="100%" src="/07f52c4b-be2e-4c18-8fbb-d265cedc158f.png">
<img width="100%" src="/37aa8a1f-8ee4-4be1-8ebd-28d851a55f4b.png">
<img width="100%" src="/5007c6da-fdc9-4570-acd3-d909921cbe28.png">
<img width="100%" src="/986629d4-89a1-41c7-9aa9-bbdcd3a2de37.png">

Download raw CSV data <a href="rocksdb_tidesdb_20260113_041457.csv">here</a>.

---

*Thanks for reading!*
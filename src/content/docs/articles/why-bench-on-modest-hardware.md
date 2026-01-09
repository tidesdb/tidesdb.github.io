---
title: "Why We Benchmark on Modest Hardware"
description: "Learn why TidesDB benchmarks on consumer-grade hardware instead of high-end systems, and how our lock-free architecture scales linearly with better CPUs and storage."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-erod-photos-1023772446-23439696.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-erod-photos-1023772446-23439696.jpg
---

<div class="article-image">

![Why We Benchmark on Modest Hardware](/pexels-erod-photos-1023772446-23439696.jpg)

</div>

*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on January 9th, 2026*

If you have been following the TidesDB benchmarks published regularly, you may have noticed the hardware we use.

**Hardware**
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)
- Ubuntu 24.04 LTS

Across all benchmarks you'll see the same hardware. We use identical hardware to ensure fair comparison. So why use modest hardware? The reason is rather simple, we want to establish a baseline.

TidesDB is multiplatform, with CI testing across 15+ platform configurations including Linux, macOS, Windows (MSVC and MinGW), FreeBSD, OpenBSD, NetBSD, DragonFlyBSD, OmniOS (Illumos), and PowerPC. By benchmarking on modest hardware, we can show how the system performs relative to the industry standard RocksDB under constrained conditions. If TidesDB performs well on modest hardware, it will perform even better on modern hardware. This has been demonstrated across our benchmarks consistently.


The question that naturally follows is "Why does TidesDB scale so well when you throw better hardware at it?" The answer lies in the architecture. TidesDB's core data structures are designed from the ground up for lock-free concurrency, which means performance scales linearly as you add CPU cores and faster storage.

Consider the block manager. When multiple threads need to write data to disk, traditional systems use locks to coordinate access. One thread writes while others wait. TidesDB takes a different approach. The block manager uses atomic space allocation combined with `pwrite` for concurrent, append-only writes. Each thread atomically reserves its slice of the file using a single CPU instruction, then writes independently to its reserved offset. Readers use `pread` and never block writers. There are no locks, no waiting, no contention. Eight threads can write eight different blocks to the same file simultaneously, each getting a unique offset atomically, then writing in parallel.

The same philosophy extends to the in-memory skip list. Traditional skip lists use locks to protect insertions. TidesDB's skip list uses compare-and-swap (CAS) operations for lock-free insertions. Multiple writers can insert keys concurrently without acquiring locks. Version chains use CAS loops to atomically prepend new versions. Even the random number generator for level selection is thread-local, avoiding any shared state. This means write throughput scales directly with the number of cores performing insertions.

The result is a system with no central bottlenecks. On a SATA SSD with 8 cores, you're bottlenecked by disk I/O, not by the database. Move to NVMe with 32 cores, and TidesDB's lock-free design lets you saturate that faster storage. Each additional core contributes directly to throughput because there are no locks waiting to be acquired, no threads blocking other threads.

This is why we benchmark on lower-grade hardware. If TidesDB can outperform RocksDB on a SATA SSD, imagine what happens when you remove that I/O constraint. The architecture is ready for it. As always, benchmark for your own use case on your own hardware to determine what storage system is best for you.


*Thanks for reading!*

---

**Links**
- GitHub · https://github.com/tidesdb/tidesdb
- Design deep-dive · https://tidesdb.com/getting-started/how-does-tidesdb-work

Join the TidesDB Discord for more updates and discussions at https://discord.gg/tWEmjR66cy

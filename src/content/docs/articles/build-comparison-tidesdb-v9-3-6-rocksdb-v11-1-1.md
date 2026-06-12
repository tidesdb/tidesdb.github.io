---
title: "Build Comparison TidesDB v9.3.6 & RocksDB v11.1.1"
description: "Timing the core library build for TidesDB v9.3.6 and RocksDB v11.1.1 on the same machine, with notes on method, fairness, and the usual caveats."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-mikhail-nilov-8431039.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-mikhail-nilov-8431039.jpg
---

<div class="article-image">

![Build Comparison TidesDB v9.3.6 & RocksDB v11.1.1](/pexels-mikhail-nilov-8431039.jpg)

</div>

*by <a target="_blank" href="https://alexpadula.com">Alex Gaetano Padula</a>*
 
*published on June 11th, 2026*


A small head-to-head analysis on TidesDB and RocksDB build times.


- On this hardware and for these versions, TidesDB v9.3.6 compiles its core static library about 25X faster than RocksDB v11.1.1. The medians are 5.4s and 134.5s.
- This is mostly a statement about code size and language. TidesDB is a smaller C library. RocksDB is a larger C++ library. It is not a statement about runtime performance.
- Build time still matters. It sets your edit and compile loop, your CI bill, and how long a new contributor waits for a first successful build. It says nothing about reads, writes, or space.

```
date            : 2026-06-12 01:12:27 UTC
host kernel     : Linux 6.2.0-39-generic x86_64
cpu cores       : 16
memory          : 46Gi
cmake           : cmake version 3.25.1
generator       : Ninja
ninja           : 1.11.1
cc              : cc (Ubuntu 12.3.0-1ubuntu1~23.04) 12.3.0
cxx             : c++ (Ubuntu 12.3.0-1ubuntu1~23.04) 12.3.0
build type      : Release
parallel jobs   : 16
runs (median)   : 3
tidesdb tag     : v9.3.6
rocksdb tag     : v11.1.1
scope           : core static library target only (tidesdb / rocksdb)
```

```
Intel Core i7-11700K, 8 cores and 16 threads, at 3.6GHz
46.8 GiB DDR4
Ubuntu 23.03, Linux 6.2.0 x86_64
WD Blue WDS500G2B0A, a consumer SATA SSD, ext4, 159 GiB volume
gcc 12.3.0, linked against jemalloc
TidesDB v9.3.6, RocksDB v11.1.1
```


Median of 3 runs.
```
project,run,seconds
tidesdb,1,5.387
tidesdb,2,5.429
tidesdb,3,5.425
rocksdb,1,132.374
rocksdb,2,134.515
rocksdb,3,134.838
```

![Build Comparison TidesDB v9.3.6 & RocksDB v11.1.1](/build-comparison-tidesdb-v9-3-6-rocksdb-v11-1-1/build_comparison.png)

*What I measured*

I time one thing, the wall clock to compile the core library and nothing else. I do not time the clone. I do not time the configure step. I run cmake with a single build target, the library, so the test suites, tools, and benchmark binaries are never compiled.

A few choices keep this honest.

Scope is the library target only. The stock build of each project compiles different extra things, so the default build of one is not the same work as the default build of the other. TidesDB builds its unit tests by default. RocksDB builds db_bench, ldb, sst_dump, and the tools by default, and it disables its own unit tests in a release build. If I timed the default of each I would be timing test compilation against tool compilation, which is not a fair trade. Building only the library asks both projects the same question.

Static library for both. TidesDB defaults to a shared library and RocksDB recommends the static library. I force static on both sides so the final link is the same kind of step. Compilation dominates either way, so this is a small effect, but I would rather remove it than argue about it.

Release for both. RocksDB's cmake defaults to a debug build if you do not ask for anything. I set Release on both so the comparison is optimized build against optimized build.

Everything else is held equal. All 16 cores for both, the same Ninja generator for both, a fresh build tree on every run so nothing is incremental, and the median of 3 runs.

One thing I did not equalize is compiler flags. Each project keeps the flags it ships. RocksDB compiles with -march=native out of the box. TidesDB does not. That is part of what building it the way it ships actually means, so I left it alone.

*The stock RocksDB build does not compile on gcc 12.3*

Worth stating on its own. The default RocksDB build fails on gcc 12.3. RocksDB sets -Werror by default, FAIL_ON_WARNINGS is ON, and gcc 12 emits a spurious -Wrestrict inside options_type.h that stops the build. I set FAIL_ON_WARNINGS=OFF to get a build at all. That flag does not change what is compiled or the optimization level, so it does not move the timing, and it happens to make the two builds more alike, because TidesDB does not turn warnings into errors by default. I call it out because the upstream release not building on a common compiler without an extra flag is itself a small result.

**Results**

The medians were 5.425s for TidesDB and 134.515s for RocksDB, so RocksDB took about 24.8X longer to build its core library. The runs were tight. TidesDB stayed within about 40ms across three runs and RocksDB within about 2.5s. I would not read anything into the third digit.

There is one wrinkle I will share because it is the whole reason I run more than once. The first TidesDB build on this box, cold, took 73s. Every warm run after that landed near 5.4s. That is a greater than 10X swing on identical inputs, and it is almost certainly cold caches and CPU contention rather than anything about the code. A single build time is close to meaningless. You want a warm machine, a few runs, and the median.

**Caveats**

The usual disclaimer applies. I am measuring build time, not engine performance. Nothing here touches throughput, latency, space amplification, or write amplification. A 25X build time gap is exactly what you expect when you compile a small C library against a large C++ library, and the large library is buying features and maturity that the small one does not have yet.

A few more things to keep in mind.

This is the all cores number. RocksDB has hundreds of translation units and parallelizes well across 16 cores, so building with -j16 flatters it. If you build single threaded with JOBS=1 the gap gets larger, because then you are measuring total compile work rather than wall clock on a wide machine. TidesDB barely moves single threaded. RocksDB grows a lot.

The numbers are specific to these two versions, this compiler, and this hardware. A different gcc, a newer RocksDB, or a machine with a different core count will move them.

I chose library only scope and forced static linking on purpose. If you want the time to a usable checkout for each project, build the default targets instead, accept that they are not the same work, and report that as its own thing.

**Reproduce it**

The script clones both at pinned tags, builds each library three times from a clean tree, prints the median, and renders the chart. For the single threaded total work numbers, run it with JOBS=1. To pin different releases, set TIDESDB_TAG and ROCKSDB_TAG.

That's all for now.

--

Data:
- <a href="build-comparison-tidesdb-v9-3-6-rocksdb-v11-1-1/build_times.csv">build_times.csv</a>

Scripts:
- <a href="/build-comparison-tidesdb-v9-3-6-rocksdb-v11-1-1/benchmark.sh">benchmark.sh</a>
- <a href="/build-comparison-tidesdb-v9-3-6-rocksdb-v11-1-1/plot.py">plot.py</a>
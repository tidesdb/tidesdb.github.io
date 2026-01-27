---
title: "Building Reliable and Safe Systems"
description: "How TidesDB's testing infrastructure ensures correctness across 15+ platforms, 5 architectures, and 8,700+ tests on every commit."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-ann-h-45017-3482441.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-ann-h-45017-3482441.jpg
---

<div class="article-image">

![Building Reliable and Safe Systems](/pexels-ann-h-45017-3482441.jpg)

</div>

*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on January 27th, 2026*

When you look at TidesDB's CI status, you see many green checkmarks on Github. What you don't see is that each of those checkmarks represents over 300 tests running. That's (300*29) 8,700+ tests on every single commit, across 15+ platforms, 5 architectures, and 3 different memory allocators.

## The Challenge of Cross-Platform Correctness

Storage engines are fundamentally different from most software. When you write a web application or a game, bugs are annoying but recoverable, you can restart the server, reload the page, try again. When a storage engine has a bug, you lose data. Transactions that were committed vanish. Databases become corrupted. Recovery fails. The system that promised durability betrays that promise.

The difficulty compounds when you need to work across platforms. Atomic operations behave differently on x86 versus ARM versus PowerPC. Thread scheduling varies between Linux and Windows. File system semantics differ across BSD variants. Integer sizes change between 32-bit and 64-bit architectures. Endianness matters when data needs to be portable. What works perfectly on Ubuntu x64 might silently corrupt data on FreeBSD x86 or fail catastrophically on Windows MSVC.

This is why most databases stick to a handful of platforms. Supporting one platform thoroughly is hard enough. Supporting fifteen is exponentially harder.

## What Gets Tested

Every commit to TidesDB triggers 30 independent CI workflows. Let me break down what that actually means.

**Platform Coverage**
- Linux (x64, x86, PowerPC 32-bit, RISC-V 64-bit)
- FreeBSD 15.0 x64
- NetBSD 10.1 x64
- OpenBSD 7.8 x64
- DragonFlyBSD 6.4.2 x64
- OmniOS r151048 (Illumos/Solaris)
- Windows MSVC (x64, x86)
- Windows MinGW (x64, x86)
- macOS (x64, x86, PowerPC G5 running 10.6.8)

**Memory Allocator Variants**
- System default allocator
- mimalloc (Microsoft's high-performance allocator)
- tcmalloc (Google's thread-caching allocator)

_Over time, I plan more allocator variants, not pluggable because I like verifying and testing each allocator variant before making accessible to users_

**Sanitizer Coverage**
- AddressSanitizer (ASan) - Detects memory errors: use-after-free, buffer overflows, memory leaks, heap corruption
- UndefinedBehaviorSanitizer (UBSan) - Catches undefined behavior: signed integer overflow, invalid shifts, null pointer dereference, unaligned memory access
- Enabled on all Linux, macOS, BSD, and Illumos builds
- MSVC builds use strict warning levels instead (ASan support can be unstable on Windows)
- Every commit runs through sanitizers across multiple platforms catching memory safety issues before they reach production


**Cross-Platform Portability Verification**
- Create database on Linux x64
- Verify it works correctly on Windows MSVC x64, Windows MSVC x86, Windows MinGW x64, Windows MinGW x86, macOS x64, macOS x86, and Linux x86
- Proves file format is truly portable across architectures and operating systems

Each workflow runs the complete test suite with unit tests for every component (block manager, skip list, bloom filter, clock cache, buffer, queue, manifest), integration tests for the full database lifecycle (CRUD operations, transactions at all five isolation levels, persistence, WAL recovery, compaction strategies), concurrency tests (race conditions, concurrent reads and writes, atomic operations), edge case tests (corruption handling, crash recovery, memory exhaustion), and stress tests (sustained load, memory pressure, disk space constraints).

## The Measure of Platform Capability and Portability

Most databases test on three platforms
- Linux x64
- Windows x64
- macOS x64

Some systems add ARM. Very few test on BSD variants or Illumos. Almost none test on PowerPC or RISC-V. Even fewer test cross-platform portability by creating a database on one architecture and reading it on another.

TidesDB tests on all of them. Not because people demand it (most will deploy on Linux x64), but because thorough testing across diverse platforms catches bugs that would otherwise slip through. The big-endian PowerPC test catches serialization bugs. The 32-bit x86 test catches integer overflow issues. The RISC-V test catches alignment problems. The BSD tests catch POSIX compliance issues. The Windows tests catch platform abstraction bugs.

Each platform adds confidence. Each architecture proves correctness. 

## Building Systems You Can Trust

Storage engines must be reliable. When you commit a transaction, it must be durable. When you read a key, you must get the correct value. When the system crashes, recovery must succeed. These aren't nice-to-haves. They're fundamental requirements.

Testing is how you ensure reliability. Not casual testing. Not "works on my machine" testing. Comprehensive, rigorous, automated testing across every platform, every architecture, every scenario where the system might be deployed.

This is what it takes to build systems you can trust with data that cannot be lost.

*Thanks for reading!*

---

- GitHub · https://github.com/tidesdb/tidesdb
- Design deep-dive · https://tidesdb.com/getting-started/how-does-tidesdb-work
- View CI status · https://github.com/tidesdb/tidesdb/actions

Join the TidesDB Discord for more updates and discussions at https://discord.gg/tWEmjR66cy
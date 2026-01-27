---
title: "Building Reliable and Safe Systems"
description: "How TidesDB's testing infrastructure ensures correctness across 15+ platforms, 5 architectures, and 8,700+ tests on every commit."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-alexapopovich-9510503.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-alexapopovich-9510503.jpg
---

<div class="article-image">

![Building Reliable and Safe Systems](/pexels-alexapopovich-9510503.jpg)

</div>

*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on January 27th, 2026*

When you look at TidesDB's CI status, you see 30 green checkmarks. What you don't see is that each of those checkmarks represents over 300 tests running. That's 8,700+ tests on every single commit, across 15+ platforms, 5 architectures, and 3 different memory allocators.

This isn't just about passing tests. It's about building systems that you can trust with data that cannot be lost.

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

**Cross-Platform Portability Verification**
- Create database on Linux x64
- Verify it works correctly on Windows MSVC x64, Windows MSVC x86, Windows MinGW x64, Windows MinGW x86, macOS x64, macOS x86, and Linux x86
- Proves file format is truly portable across architectures and operating systems

Each workflow runs the complete test suite: unit tests for every component (block manager, skip list, bloom filter, clock cache, buffer, queue, manifest), integration tests for the full database lifecycle (CRUD operations, transactions at all five isolation levels, persistence, WAL recovery, compaction strategies), concurrency tests (race conditions, concurrent reads and writes, atomic operations), edge case tests (corruption handling, crash recovery, memory exhaustion), and stress tests (sustained load, memory pressure, disk space constraints).

## Why This Matters

Consider the block manager. It uses `pread` and `pwrite` for position-independent I/O, enabling lock-free concurrent access. On Linux, these are native syscalls. On Windows, they map to `ReadFile` and `WriteFile` with `OVERLAPPED` structures. On some BSD variants, they're implemented differently. The abstraction layer in `compat.h` handles these differences, but we need to verify the abstraction is correct on every platform.

Or consider atomic operations. TidesDB's skip list uses compare-and-swap (CAS) loops for lock-free insertions. On x86, CAS is `lock cmpxchg`. On ARM, it's `ldrex`/`strex`. On PowerPC, it's `lwarx`/`stwcx`. The C11 `stdatomic.h` header provides a unified interface, but memory ordering semantics (acquire, release, relaxed) must be correct on every architecture or the skip list could corrupt data under concurrent access. Testing on all five architectures ensures correctness.

The PowerPC G5 test is particularly important. It's a big-endian architecture from 2003. If the serialization format works correctly on big-endian PowerPC and little-endian x86, it works everywhere. The cross-platform portability tests verify this explicitly - create a database with little-endian x86 integers, read it back on big-endian PowerPC, confirm values match. This catches serialization bugs that could silently corrupt data.

## The Cost of Rigor

Running 8,700+ tests across 30 configurations on every commit isn't cheap. CI minutes cost money. Build times add up. Maintaining test infrastructure across fifteen platforms requires understanding the quirks of each operating system, each compiler, each architecture. Setting up cross-compilation for PowerPC. Managing vcpkg binary caches for Windows. Installing compression libraries on every BSD variant. Configuring QEMU for emulated architectures.

But the alternative is worse. A bug that corrupts data on DragonFlyBSD but not Linux would be nearly impossible to debug in production. A race condition that only manifests on ARM under high load would cause data loss for some users while working perfectly in testing. An endianness bug that breaks portability would prevent migrating databases between architectures.

The rigor catches these issues before they reach users. Every green checkmark is confidence that the code works correctly, not just on the developer's laptop, but on every platform where someone might deploy it.

## The Architecture Advantage

TidesDB's lock-free architecture makes this testing feasible. Because there are no true hot locks, there are no deadlock scenarios to test really. Because atomic operations are primitives with well-defined semantics, testing their correctness is straightforward - either the CAS succeeds or it retries. Because the design avoids shared mutable state, race conditions are localized to specific data structures rather than spreading through the entire codebase.

This is by design. Lock-free algorithms are harder to implement initially, but easier to test and reason about once they're correct. A mutex-based skip list has combinatorial interactions between lock acquisition order, thread scheduling, and timing. A CAS-based skip list either succeeds atomically or retries. The state space is simpler.

The same principle applies to the block manager, the cache, the queues, the reference counting. Lock-free by default means testable by default.

## What This Enables

When every commit passes 8,700+ tests across fifteen platforms, you can refactor with confidence. Want to optimize the skip list level selection? Change it, push, wait for CI. If all 8,700+ tests pass, the optimization is safe. Want to experiment with a different compaction strategy? Try it. The tests will catch correctness issues.

This enables rapid iteration. TidesDB has gone through seven major versions in two years, with each version bringing significant architectural improvements. Version 4 had basic LSM-tree implementation. Version 6 added seek and range query optimization. Version 7 introduced Spooky compaction with Dynamic Capacity Adaptation, full lock-free concurrency, and improved crash recovery. Each change was validated by thousands of tests across diverse platforms.

The testing infrastructure is what makes this pace possible. Without it, each change would require manual testing on multiple platforms, regression checks, careful code review. With it, the CI system provides immediate feedback on correctness.

## The Standard We Set

Most databases test on three platforms
- Linux x64
- Windows x64
- macOS x64. 

Some add ARM. Very few test on BSD variants or Illumos. Almost none test on PowerPC or RISC-V. Even fewer test cross-platform portability by creating a database on one architecture and reading it on another.

TidesDB tests on all of them. Not because users demand it (most will deploy on Linux x64), but because thorough testing across diverse platforms catches bugs that would otherwise slip through. The big-endian PowerPC test catches serialization bugs. The 32-bit x86 test catches integer overflow issues. The RISC-V test catches alignment problems. The BSD tests catch POSIX compliance issues. The Windows tests catch platform abstraction bugs.

Each platform adds confidence. Each architecture proves correctness. Each green checkmark is a promise kept: this code works, everywhere, every time.

## Building Systems You Can Trust

Storage engines must be reliable. When you commit a transaction, it must be durable. When you read a key, you must get the correct value. When the system crashes, recovery must succeed. These aren't nice-to-haves. They're fundamental requirements.

Testing is how you ensure reliability. Not casual testing. Not "works on my machine" testing. Comprehensive, rigorous, automated testing across every platform, every architecture, every scenario where the system might be deployed.

8,700+ tests on every commit. Fifteen platforms. Five architectures. Three allocators. Cross-platform portability verification. Race condition detection. Crash recovery validation. Edge case handling. Stress testing under load.

This is what it takes to build systems you can trust with data that cannot be lost.

*Thanks for reading!*

---

- GitHub · https://github.com/tidesdb/tidesdb
- Design deep-dive · https://tidesdb.com/getting-started/how-does-tidesdb-work
- View CI status · https://github.com/tidesdb/tidesdb/actions

Join the TidesDB Discord for more updates and discussions at https://discord.gg/tWEmjR66cy
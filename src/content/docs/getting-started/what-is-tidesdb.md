---
title: What is TidesDB?
description: A high level description of what TidesDB is.
---

TidesDB is a fast, light-weight and efficient embeddable key-value storage engine library written in C. Built on a log-structured merge-tree (LSM-tree) architecture, it provides a foundational library for building database systems or can be used directly as a standalone key-value or column store.

## Key Characteristics

TidesDB is designed for direct integration into applications. It handles keys and values as raw byte sequences without 
size restrictions (up to system memory limits), giving you full control over 
serialization. Optimized for write-heavy workloads, it maintains efficient 
reads through bloom filters, block indices, and compaction.

## Core Features

- Lock-free skip list memtables with RCU memory management, epoch-based garbage collection, and atomic operations. Readers never block and scale linearly with CPU cores, while writers use lightweight mutex serialization per column family.
- ACID transactions that are atomic, consistent, isolated, and durable across multiple column families. Point reads use READ COMMITTED isolation, iterators use snapshot isolation with reference counting.
- Column families provide isolated key-value stores, each with independent configuration, memtables, SSTables, and write-ahead logs.
- Bidirectional iterators support forward and backward traversal with heap-based merge-sort across memtables and SSTables. Lock-free iteration with reference counting prevents premature deletion during concurrent operations.
- Efficient seek operations using O(log n) skip list positioning and optional succinct trie block indexes with LOUDS encoding for direct key-to-block-number mapping in SSTables.
- Durability through write-ahead log (WAL) with automatic recovery on startup that reconstructs memtables from persisted logs.
- Automatic background compaction when SSTable count reaches configured threshold, or manual parallel compaction via API. Compaction removes tombstones and expired TTL entries.
- Optional bloom filters provide probabilistic key existence checks to reduce disk reads. Configurable false positive rate per column family.
- Optional compression using Snappy, LZ4, or ZSTD for both SSTables and WAL entries. Configurable per column family.
- TTL (time-to-live) support for key-value pairs with automatic expiration. Expired entries are skipped during reads and removed during compaction.
- Custom comparators allow registration of user-defined key comparison functions. Built-in comparators include memcmp, string, and numeric.
- Memory optimizations include arena-based allocation for skip list nodes and inline storage for small keys/values (≤24 bytes) to reduce malloc overhead and pointer indirection.
- Two-tier caching system with block-level LRU cache for frequently accessed data and configurable file handle cache to limit open file descriptors.
- Shared thread pools for background flush and compaction operations with configurable thread counts at the storage engine level.
- Two sync modes: TDB_SYNC_NONE for maximum performance (OS-managed flushing) and TDB_SYNC_FULL for maximum durability (fsync on every write).
- Cross-platform support for Linux, macOS, and Windows on both 32-bit and 64-bit architectures with platform abstraction layer.
- Clean C API that returns 0 on success and negative error codes on failure for straightforward error handling.
- Full file portability with explicit little-endian serialization throughout; database files can be copied between any platform (x86, ARM, RISC-V) and architecture (32-bit, 64-bit) without conversion.

## Community

Join the [TidesDB Discord Community](https://discord.gg/tWEmjR66cy) to ask questions, work on development, and discuss the future of TidesDB.

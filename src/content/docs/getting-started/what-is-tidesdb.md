---
title: What is TidesDB?
description: A high level description of what TidesDB is.
---

TidesDB is a fast and efficient embedded key-value storage engine library written in C. Built on a log-structured merge-tree (LSM-tree) architecture, it provides a foundational library for building database systems or can be used directly as a standalone key-value or column store.

## Key Characteristics

TidesDB is an embeddable storage library designed for direct integration 
into applications. It handles keys and values as raw byte sequences without 
size restrictions (up to system memory limits), giving you full control over 
serialization. Optimized for write-heavy workloads, it maintains efficient 
reads through bloom filters, block indices, and compaction.

## Core Features

- ACID transactions that are atomic, consistent, isolated (read committed), and durable. Transactions support multiple operations across column families. Writers are serialized per column family ensuring atomicity, while COW provides consistency for concurrent readers.
- Writers don't block readers. Readers never block other readers. Background operations will not affect active transactions.
- Isolated key-value stores. Each column family has its own configuration, memtables, sstables, and write ahead logs.
- Bidirectional iterators that allow you to iterate forward and backward over key-value pairs with heap-based merge-sort across memtable and sstables. Effective seek operations with O(log n) skip list positioning and SBHA(Sorted Binary Hash Array) positioning(if enabled) in sstables. Reference counting prevents premature deletion during iteration.
- Durability through WAL (write ahead log). Automatic recovery on startup reconstructs memtables from WALs.
- Optional automatic background compaction when sstable count reaches configured max per column family. You can also trigger manual compactions through the API, parallelized or not.
- Optional bloom filters to reduce disk reads by checking key existence before reading sstables. Configurable false positive rate.
- Optional compression via Snappy, LZ4, or ZSTD for sstables and WAL entries. Configurable per column family.
- Optional TTL (time-to-live) for key-value pairs. Expired entries automatically skipped during reads.
- Optional custom comparators. You can register custom key comparison functions. Built-in comparators include memcmp, string, numeric.
- Two sync modes NONE (fastest), FULL (most durable, slowest).
- Per-column-family configuration includes memtable size, compaction settings, compression, bloom filters, sync mode, and more.
- Clean, easy-to-use C API. Returns 0 on success, -n on error.
- Cross-platform support for Linux, macOS, and Windows with platform abstraction layer.
- Optional use of sorted binary hash array (SBHA). Allows for fast sstable lookups. Direct key-to-block offset mapping without full sstable scans.
- Efficient deletion through tombstone markers. Removed during compactions.
- Configurable LRU cache for open file handles. Limits system resources while maintaining performance. Set `max_open_file_handles` to control cache size (0 = disabled).
- Storage engine thread pools for background flush and compaction with configurable thread counts.


## Community

Join the [TidesDB Discord Community](https://discord.gg/tWEmjR66cy) to ask questions, work on development, and discuss the future of TidesDB.

## Cross-Platform Support

TidesDB supports 32-bit and 64-bit Linux, macOS, and Windows with a platform abstraction layer for consistent behavior across operating systems. 
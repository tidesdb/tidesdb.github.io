---
title: What is TidesDB?
description: A high level description of what TidesDB is.
---

TidesDB is a fast and efficient embedded key-value storage engine library written in C. Built on a log-structured merge-tree (LSM-tree) architecture, it provides a foundational library for building database systems or can be used directly as a standalone key-value or column store.

## Key Characteristics

**Embedded Storage Engine** TidesDB is not a full-featured database server but rather a library that can be embedded directly into your application. This design provides maximum flexibility and minimal overhead.

**Raw Byte Storage** Keys and values in TidesDB are raw sequences of bytes with no predetermined size restrictions, giving you complete control over data serialization.

**LSM-Tree Architecture** Optimized for write-heavy workloads while maintaining efficient read performance through intelligent data organization and compaction strategies.

## Core Features

- **ACID Transactions** Full transactional support with atomic commits and automatic rollback on failure
- **Column Families** Isolated key-value stores with independent configuration and optimization
- **Concurrent Access** Readers don't block readers, writers don't block readers (MVCC-style snapshots)
- **Write-Ahead Log (WAL)** Ensures durability with automatic crash recovery
- **Compression** Support for Snappy, LZ4, and ZSTD compression algorithms
- **TTL Support** Automatic expiration of key-value pairs based on time-to-live
- **Bloom Filters** Reduce disk I/O by quickly filtering non-existent keys
- **Custom Comparators** Register custom key comparison functions for specialized sorting
- **Parallel Compaction** Multi-threaded SSTable merging for improved performance
- **Bidirectional Iterators** Efficient forward and backward traversal with merge-sort across data sources

## Community

Join the [TidesDB Discord Community](https://discord.gg/tWEmjR66cy) to ask questions, work on development, and discuss the future of TidesDB.

## Cross-Platform Support

TidesDB supports Linux, macOS, and Windows with a platform abstraction layer for consistent behavior across operating systems.
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

## Language Bindings

TidesDB can be accessed through FFI bindings for multiple programming languages, making it accessible to a wide range of developers and use cases.

Available bindings include:
- **C++** - [tidesdb-cpp](https://github.com/tidesdb/tidesdb-cpp)
- **Go** - [tidesdb-go](https://github.com/tidesdb/tidesdb-go)
- **Java** - [tidesdb-java](https://github.com/tidesdb/tidesdb-java)
- **Python** - [tidesdb-python](https://github.com/tidesdb/tidesdb-python)
- **Rust** - [tidesdb-rust](https://github.com/tidesdb/tidesdb-rust)
- **Lua** - [tidesdb-lua](https://github.com/tidesdb/tidesdb-lua)
- **C#** - [tidesdb-csharp](https://github.com/tidesdb/tidesdb-csharp)
- **JavaScript/Node.js** - [tidesdb-js](https://github.com/tidesdb/tidesdb-js)
- **Zig** - [tidesdb-zig](https://github.com/tidesdb/tidesdb-zig)

And many more including Scala, Objective-C, PHP, Perl, Ruby, Swift, Haskell, D, Kotlin, Julia, R, Dart, Nim, OCaml, F#, Erlang, and Elixir.

## Development Status

TidesDB is actively developed and maintained. The project is working towards TidesDB 1.0 as the first stable major release.

## Community

Join the [TidesDB Discord Community](https://discord.gg/tWEmjR66cy) to ask questions, work on development, and discuss the future of TidesDB.

## Cross-Platform Support

TidesDB supports Linux, macOS, and Windows with a platform abstraction layer for consistent behavior across operating systems.
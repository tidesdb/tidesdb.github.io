---
title: What is TidesDB?
description: A high level description of what TidesDB is.
---

TidesDB is a fast, light-weight and efficient embeddable key-value storage engine library written in C. Built on a log-structured merge-tree (LSM-tree) architecture, it provides a foundational library for building database systems or can be used directly as a standalone key-value or column store.

## Key Characteristics

TidesDB is designed for direct integration into applications. It handles keys and values as raw byte sequences without 
size restrictions (up to system memory limits), giving you full control over 
serialization. Optimized for write-heavy workloads, it maintains efficient 
reads through bloom filters, caching, block indices, and compaction.

## Core Features

- ACID transactions with MVCC supporting 5 isolation levels: `READ_UNCOMMITTED`, `READ_COMMITTED`, `REPEATABLE_READ`, `SNAPSHOT`, and `SERIALIZABLE`. Serializable isolation uses SSI (Serializable Snapshot Isolation) with read-write conflict detection to prevent all anomalies including write-skew. Transactions support savepoints for partial rollback and read-your-own-writes semantics.
- Multi-column family transactions with atomic all-or-nothing semantics. Each CF's WAL receives transaction operations with the same global commit sequence number, ensuring atomicity through sequence-based ordering.
- Column families provide isolated key-value stores with independent configuration (memtable size, compression, bloom filters, compaction parameters). Runtime configuration updates without restart.
- Bidirectional iterators with heap-based merge-sort across memtables and SSTables. Snapshot isolation ensures consistent iteration during concurrent writes and compactions.  Prefix seek is supported.
- Hybrid and adaptive compaction with three modes: full preemptive merge (minimize space amplification), dividing merge (create partition boundaries), and partitioned merge (minimize write amplification). Dynamic Capacity Adjustment (DCA) automatically scales level capacities based on data size. Dynamic level management adds/removes levels on demand.
- Automatic crash recovery reconstructs memtables from write-ahead log (WAL) files on startup. WAL entries are replayed into skip lists and queued for flush to disk.
- Optional bloom filters (configurable false positive rate) reduce disk reads for absent keys. Built during SSTable creation and persisted in metadata.
- Key-value separation (WiscKey-style) with configurable threshold. Small values stored inline in klog, large values in vlog with offset reference. Reduces write amplification during compaction.
- TTL support for automatic key-value expiration. Expired entries skipped during reads and removed during compaction.
- Custom comparators with 6 built-in comparators: memcmp, lexicographic, uint64, int64, reverse, case_insensitive. Used consistently across skip lists, SSTables, and compaction.
- Lock-free block manager using `pread`/`pwrite` for concurrent I/O. Reference-counted blocks with atomic operations. xxHash32 checksums for integrity. Supports up to 4GB blocks with partial reads.
- Two-tier caching
  - File handle cache with LRU eviction (default 512 open SSTables). Background reaper closes oldest unused files.
  - Block cache using partitioned CLOCK eviction. Caches deserialized klog blocks with zero-copy API and reference bit protection.
- Background thread pools for flush and compaction (default 2 threads each). Work queues distribute tasks. Compaction auto-triggers when Level 1 reaches (default 4) files.
- Three sync modes · `TDB_SYNC_NONE` (OS-managed), `TDB_SYNC_FULL` (fsync every write), `TDB_SYNC_INTERVAL` (periodic sync). Structural operations always enforce durability.
- Compression support · LZ4,LZ4-FAST, Zstd, Snappy (configurable per column family). Applied to klog and vlog blocks, not WAL.
- Block indexes for fast seeks. Sample every Nth block (configurable ratio, default 1 = every block) storing prefix boundaries and file positions for binary search.
- Cross-platform · Linux, macOS, Windows, BSD variants, Solaris/Illumos on x86, ARM, RISC-V, PowerPC (32-bit and 64-bit). Comprehensive platform abstraction layer.
- File portability · Little-endian serialization throughout. Database files work across any platform/architecture without conversion.
- Clean C API · Returns `TDB_SUCCESS` (0) on success, negative error codes on failure (`TDB_ERR_MEMORY`, `TDB_ERR_INVALID_ARGS`, `TDB_ERR_NOT_FOUND`, `TDB_ERR_IO`, `TDB_ERR_CORRUPTION`, `TDB_ERR_CONFLICT`, etc.). Configurable debug logging with 6 levels: `TDB_LOG_DEBUG` (most verbose), `TDB_LOG_INFO`, `TDB_LOG_WARN`, `TDB_LOG_ERROR`, `TDB_LOG_FATAL`, and `TDB_LOG_NONE` (disable). Log level set via `tidesdb_config_t` at database open. Timestamped log output to stderr with file/line information.
- Optional <a href="https://github.com/microsoft/mimalloc">mimalloc</a>, <a href="https://google.github.io/tcmalloc/overview.html">tcmalloc</a> support
- Optional hybrid B-tree + LSM-tree which can be configured per column family
- Ability to clone column families
- Easy pluggable custom allocator support

## Community

Join the [TidesDB Discord Community](https://discord.gg/tWEmjR66cy) to ask questions, work on development, and discuss the future of TidesDB.

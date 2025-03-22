---
title: How does TidesDB work?
description: A high level description of how TidesDB works.
---

## 1. Introduction
TidesDB is a fast, efficient key-value storage engine library implemented in C, designed around the log-structured merge-tree (LSM-tree) paradigm. 

Rather than being a full-featured database management system, TidesDB serves as a foundational library that developers can use to build database systems or utilize directly as a standalone key-value or column store.

Here we explore the inner workings of TidesDB, its architecture, core components, and operational mechanisms.

## 2. Theoretical Foundation
### 2.1 Origins and Concept
The Log-Structured Merge-tree was first introduced by Patrick O'Neil, Edward Cheng, Dieter Gawlick, and Elizabeth O'Neil in their 1996 paper. The fundamental insight of the LSM-tree is to optimize write operations by using a multi-tier storage structure that defers and batches disk writes.

### 2.2 Basic LSM-tree Structure
An LSM-tree typically consists of multiple components:

- In-memory buffers (memtables) that accept writes
- Immutable on-disk files (SSTables - Sorted String Tables)
- Processes that merge SSTables to reduce storage overhead and improve read performance

This structure allows for efficient writes by initially storing data in memory and then periodically flushing to disk in larger batches, reducing the I/O overhead associated with random writes.

## 3. TidesDB Architecture
### 3.1 Overview
TidesDB implements a two-level LSM-tree architecture.

- **Memory level**: Stores recently written key-value pairs in sorted order using a skip list data structure
- **Disk level**: Contains multiple SSTables, with newer tables taking precedence over older ones

This design choice differs from other implementations like RocksDB and LevelDB, which use a multi-level approach with specific level-based compaction strategies.

### 3.2 Column Families
A distinctive aspect of TidesDB is its organization around column families. Each column family:

- Operates as an independent key-value store
- Has its own dedicated memtable and set of SSTables
- Can be configured with different parameters for flush thresholds, compression settings, etc.
- Uses read-write locks to allow concurrent reads but single-writer access

This design allows for domain-specific optimization and isolation between different types of data stored in the same database.

![](/column-family-board.png)

## 4. Core Components and Mechanisms
### 4.1 Memtable
The memtable is an in-memory data structure that serves as the first landing point for all write operations. Key features include:

- **Skip List Implementation**: TidesDB employs a skip list data structure to efficiently maintain key-value pairs in sorted order. The implementation performs byte-by-byte lexicographical comparison to establish the sorting order of keys, ensuring consistent and predictable data organization in memory. This comparison algorithm applies to retrieval and merge comparisons as well system-wide. 
- **Configurable Parameters**: Maximum level and probability can be tuned
- **Size Threshold**: When the memtable reaches a configurable size threshold, it is flushed to disk as an SSTable

### 4.2 SSTables (Sorted String Tables)
SSTables are the immutable on-disk components of TidesDB. Their design includes:

- **Block-Based Structure**: Each SSTable consists of multiple blocks containing sorted key-value pairs
- **Block Indices**: Optionally maintained indices that allow direct access to specific blocks without scanning the entire file
- **Min-Max Key Range**: Each SSTable stores the minimum and maximum keys it contains to optimize range queries. This block lives at block 0
- **Immutability**: Once written, SSTables are never modified (only eventually merged or deleted)

![](/sst-block-format-board.png)

### 4.3 Write-Ahead Log (WAL)
For durability, TidesDB implements a write-ahead logging mechanism:

- All writes are first recorded in the WAL before being applied to the memtable
- On system restart, the WAL is replayed to reconstruct the memtable state
- WAL entries can be optionally compressed using Snappy, LZ4, or ZSTD

### 4.4 Bloom Filters
To optimize read operations, TidesDB employs Bloom filters:

- Probabilistic data structures that quickly determine if a key might exist in an SSTable
- Helps avoid unnecessary disk I/O by filtering out SSTables that definitely don't contain a key
- Configurable per column family to balance memory usage against read performance
- Lives at block 1 after min-max block within an SSTable

## 5. Data Operations
### 5.1 Write Path
When a key-value pair is written to TidesDB:

1. The operation is recorded in the WAL
2. The key-value pair is inserted into the memtable
3. If the memtable size exceeds the flush threshold:

- The column family will block momentarily
- The memtable is flushed to disk (sorted run) as an SSTable
- The corresponding WAL is truncated
- The memtable is cleared for new writes


### 5.2 Read Path
When reading a key from TidesDB:

1. First, the memtable is checked for the key
2. If not found, SSTables are checked in reverse chronological order (newest to oldest)
3. For each SSTable:

- The Bloom filter is consulted to determine if the key might exist
- If the Bloom filter indicates the key might exist, the block index is used to locate the potential block
- The block is read and searched for the key


4. The search stops when the key is found or all SSTables have been checked

### 5.3 Range Queries
TidesDB supports efficient range queries:

1. SSTables are filtered based on their min-max key ranges
2. Only SSTables that potentially contain keys in the requested range are scanned
3. Results from multiple SSTables are merged to provide a consistent view

### 5.4 Transactions
TidesDB provides ACID transaction support at the column family level:

- Transactions use a simple write-lock mechanism
- Multiple operations can be grouped atomically
- On commit, all operations are applied or rolled back together
- Transactions block other threads from accessing the column family until completion

### 6. Compaction Strategies
TidesDB implements two distinct compaction strategies:
## 6.1 Manual Multi-Threaded Parallel Compaction

- Pairs and merges SSTables from oldest to newest
- Runs with a configurable number of threads, each handling one pair
- Reduces the number of SSTables by approximately half in each run
- Removes tombstones and expired TTL entries

### 6.2 Background Incremental Merge Compaction

- Runs in the background at configurable intervals
- Triggers when the number of SSTables exceeds a threshold
- Merges pairs incrementally rather than all at once
- Blocks less than manual compaction
- Continues until system shutdown

![](/sst-pair-merge-board.png)

### 6.3 Compaction Mechanics
During compaction:

1. SSTables are paired (typically oldest with second-oldest)
2. Pairs are merged into new SSTables 
3. For each key, only the newest version is retained
4. Tombstones (deletion markers) and expired TTL entries are purged
5. Original SSTables are deleted after successful merge
6. If a merge is interrupted, the system will clean up after on restart. Interruption does not corrupt.

![](/sst-pair-merge-tombstone-board.png)

## 7. Performance Optimizations
### 7.1 Block Indices
TidesDB employs block indices to optimize read performance:

- Each SSTable contains a final block with a sorted binary hash array (SBHA)
- This structure allows direct access to the block containing a specific key
- Significantly reduces I/O by avoiding full SSTable scans

### 7.2 Compression
TidesDB supports multiple compression algorithms:

- **Snappy** Emphasizes speed over compression ratio
- **LZ4** Balanced approach with good speed and reasonable compression
- **ZSTD** Higher compression ratio at the cost of some performance

Compression can be applied to both SSTable entries and WAL entries.

### 7.3 Configurable Parameters
TidesDB allows fine-tuning through various configurable parameters:

- Memtable flush thresholds
- Skip list configuration
- Bloom filter usage
- Compression settings
- Compaction trigger thresholds
- Block Indices (Build with`TDB_BLOCK_INDICES=0`)
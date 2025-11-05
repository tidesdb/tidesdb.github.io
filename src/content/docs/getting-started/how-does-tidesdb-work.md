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
An LSM-tree typically consists of multiple components

- In-memory buffers (memtables) that accept writes
- Immutable on-disk files (SSTables - Sorted String Tables)
- Processes that merge SSTables to reduce storage overhead and improve read performance

This structure allows for efficient writes by initially storing data in memory and then periodically flushing to disk in larger batches, reducing the I/O overhead associated with random writes.

## 3. TidesDB Architecture
### 3.1 Overview
TidesDB implements a two-level LSM-tree architecture.

- **Memory level** Stores recently written key-value pairs in sorted order using a skip list data structure
- **Disk level** Contains multiple SSTables, with newer tables taking precedence over older ones

This design choice differs from other implementations like RocksDB and LevelDB, which use a multi-level approach with specific level-based compaction strategies.

### 3.2 Column Families
A distinctive aspect of TidesDB is its organization around column families. Each column family

- Operates as an independent key-value store
- Has its own dedicated memtable and set of SSTables
- Can be configured with different parameters for flush thresholds, compression settings, etc.
- Uses read-write locks to allow concurrent reads but single-writer access

This design allows for domain-specific optimization and isolation between different types of data stored in the same database.

## 4. Core Components and Mechanisms
### 4.1 Memtable
The memtable is an in-memory data structure that serves as the first landing point for all write operations. Key features include

- **Skip List Implementation** TidesDB employs a lock-free skip list data structure to efficiently maintain key-value pairs in sorted order. The skip list uses atomic operations for concurrent reads while writers acquire an exclusive lock.
- **Custom Comparators** Each column family can register a custom key comparison function (memcmp, string, numeric, or user-defined). The comparator determines sort order across the entire system - memtable, SSTables, and iterators all use the same comparison logic for consistency.
- **Configurable Parameters** Maximum level and probability can be tuned per column family
- **Size Threshold** When the memtable reaches a configurable size threshold, it is flushed to disk as an SSTable
- **Atomic Operations** Uses `_Atomic` types for thread-safe size tracking and version management

### 4.2 SSTables (Sorted String Tables)
SSTables are the immutable on-disk components of TidesDB. Their design includes

- **Block-Based Structure** Each SSTable consists of multiple blocks containing sorted key-value pairs
- **Block Indices** Optionally maintained indices that allow direct access to specific blocks without scanning the entire file
- **Min-Max Key Range** Each SSTable stores the minimum and maximum keys it contains to optimize range queries. This block lives at block 0
- **Immutability** Once written, SSTables are never modified (only eventually merged or deleted)

### 4.3 Write-Ahead Log (WAL)
For durability, TidesDB implements a write-ahead logging mechanism with a rotating WAL system tied to memtable lifecycle.

#### 4.3.1 WAL File Naming and Lifecycle

**File Format** `wal_<memtable_id>.log`
- Examples: `wal_0.log`, `wal_1.log`, `wal_2.log`
- Each memtable has its own dedicated WAL file
- WAL ID matches the memtable ID (monotonically increasing counter)
- **Multiple WAL files can exist simultaneously** - one for active memtable, others for memtables in flush queue
- WAL files are deleted only after memtable is successfully flushed to SSTable AND freed

#### 4.3.2 WAL Rotation Process

TidesDB uses a rotating WAL system that works as follows

1. **Initial State** Active Memtable (ID: 0) → `wal_0.log`
2. **Memtable Fills Up** When size >= `memtable_flush_size`, rotation is triggered
3. **Rotation Occurs**
   - New Active Memtable (ID: 1) → `wal_1.log` (new WAL created)
   - Immutable Memtable (ID: 0) → `wal_0.log` (queued for flush)
4. **Background Flush** Memtable (ID: 0) writes to `sstable_0.sst` while `wal_0.log` still exists
5. **Flush Complete** `wal_0.log` is deleted after memtable is freed
6. **Concurrent Operations** Multiple memtables can be in flush queue, each with its own WAL file

#### 4.3.3 WAL Features

- All writes (including deletes/tombstones) are first recorded in the WAL before being applied to the memtable
- WAL entries can be optionally compressed using Snappy, LZ4, or ZSTD
- Each column family maintains its own independent WAL files
- Automatic recovery on database startup reconstructs memtables from WALs

#### 4.3.4 Recovery Process

On database startup, TidesDB automatically recovers from WAL files

1. Scans column family directory for `wal_*.log` files
2. Sorts WAL files by ID (oldest to newest)
3. Replays each WAL file into a new memtable
4. Reconstructs in-memory state from persisted WAL entries
5. Continues normal operation with recovered data

**What Gets Recovered**
- All committed transactions that were written to WAL
- Uncommitted transactions are discarded (not in WAL)
- Memtables that were being flushed when crash occurred

### 4.4 Bloom Filters
To optimize read operations, TidesDB employs Bloom filters

- Probabilistic data structures that quickly determine if a key might exist in an SSTable
- Helps avoid unnecessary disk I/O by filtering out SSTables that definitely don't contain a key
- Configurable per column family to balance memory usage against read performance
- Lives at block 1 after min-max block within an SSTable

## 5. Data Operations
### 5.1 Write Path
When a key-value pair is written to TidesDB

1. The operation is recorded in the WAL
2. The key-value pair is inserted into the memtable
3. If the memtable size exceeds the flush threshold

- The column family will block momentarily
- The memtable is flushed to disk (sorted run) as an SSTable
- The corresponding WAL is truncated
- The memtable is cleared for new writes


### 5.2 Read Path
When reading a key from TidesDB

1. First, the memtable is checked for the key
2. If not found, SSTables are checked in reverse chronological order (newest to oldest)
3. For each SSTable

- The Bloom filter is consulted to determine if the key might exist
- If the Bloom filter indicates the key might exist, the block index is used to locate the potential block
- The block is read and searched for the key


4. The search stops when the key is found or all SSTables have been checked

### 5.3 Transactions
TidesDB provides ACID transaction support with multi-column-family capabilities

- **Read and Write Transactions** Separate `tidesdb_txn_begin()` for writes and `tidesdb_txn_begin_read()` for read-only transactions
- **Multi-Column-Family** A single transaction can operate across multiple column families atomically
- **Isolation Level** Read Committed isolation - read transactions see a consistent snapshot via COW and don't block writers
- **Atomic Commit/Rollback** All operations succeed together or automatically rollback on failure
- **Read-Your-Own-Writes** Within a transaction, you can read uncommitted changes before commit
- **Writer Locks** Write transactions acquire exclusive locks per column family, but only during commit
- **No Error Structs** Simple integer return codes (0 = success, -1 = error)

### 6. Compaction Strategies
TidesDB implements two distinct compaction strategies

### 6.1 Parallel Compaction (Manual or Automatic)

- **Semaphore-Based Thread Pool** Uses POSIX semaphores to limit concurrent thread count
- **Configurable Threads** Set `compaction_threads` in column family config (default 4)
- **Pair-Based Merging** Pairs SSTables from oldest to newest, each thread handles one pair
- **Automatic Routing** If `compaction_threads > 0`, `tidesdb_compact()` automatically uses parallel compaction
- **Reduces SSTable Count** Approximately halves the number of SSTables in each run
- **Removes Tombstones** Purges deletion markers and expired TTL entries during merge
- **Minimum Requirement** Needs at least 2 SSTables to trigger compaction

### 6.2 Background Compaction

- **Automatic Trigger** Runs when SSTable count reaches `max_sstables_before_compaction` threshold
- **Background Thread** Operates independently without blocking application operations
- **Configurable** Enable with `enable_background_compaction = 1` in column family config
- **Incremental** Merges pairs incrementally rather than all at once
- **Continues Until Shutdown** Monitors and compacts throughout the database lifecycle

### 6.3 Compaction Mechanics
During compaction

1. SSTables are paired (typically oldest with second-oldest)
2. Pairs are merged into new SSTables 
3. For each key, only the newest version is retained
4. Tombstones (deletion markers) and expired TTL entries are purged
5. Original SSTables are deleted after successful merge
6. If a merge is interrupted, the system will clean up after on restart. Interruption does not corrupt.

## 7. Performance Optimizations
### 7.1 Block Indices
TidesDB employs block indices to optimize read performance

- Each SSTable contains a final block with a sorted binary hash array (SBHA)
- This structure allows direct access to the block containing a specific key
- Significantly reduces I/O by avoiding full SSTable scans

### 7.2 Compression
TidesDB supports multiple compression algorithms

- **Snappy** Emphasizes speed over compression ratio
- **LZ4** Balanced approach with good speed and reasonable compression
- **ZSTD** Higher compression ratio at the cost of some performance

Compression can be applied to both SSTable entries and WAL entries.

### 7.3 Sync Modes

TidesDB provides three sync modes to balance durability and performance

- **TDB_SYNC_NONE** Fastest, least durable (OS handles flushing to disk)
- **TDB_SYNC_BACKGROUND** Balanced approach (fsync every N milliseconds in background thread)
- **TDB_SYNC_FULL** Most durable (fsync on every write operation)

The sync mode can be configured per column family, allowing different durability guarantees for different data types.

### 7.4 Configurable Parameters

TidesDB allows fine-tuning through various configurable parameters

- Memtable flush thresholds
- Skip list configuration (max level and probability)
- Bloom filter usage and false positive rate
- Compression settings (algorithm selection)
- Compaction trigger thresholds and thread count
- Sync mode and interval
- Debug logging
- SBHA (Sorted Binary Hash Array) usage

## 8. Concurrency and Thread Safety

TidesDB is designed for great concurrency with minimal blocking through a reader-writer lock model.

### 8.1 Reader-Writer Locks

Each column family has its own reader-writer lock

- **Multiple readers can read concurrently** No blocking between readers accessing the same column family
- **Writers don't block readers** Read operations can proceed while writes are in progress
- **Writers block other writers** Only one write transaction per column family at a time

### 8.2 Transaction Isolation

- **Read transactions** Acquire read locks and see a consistent snapshot of data via COW
- **Write transactions** Acquire write locks on commit, ensuring atomic updates
- **Read Committed isolation** Read transactions don't see uncommitted changes from other transactions
- **Read-your-own-writes** Within a transaction, uncommitted changes are visible

### 8.3 Optimal Use Cases

This concurrency model makes TidesDB particularly well-suited for

- **Read-heavy workloads** Unlimited concurrent readers with no contention
- **Mixed read/write workloads** Readers never wait for writers to complete
- **Multi-column-family applications** Different column families can be written to concurrently

## 9. Directory Structure and File Organization

TidesDB organizes data on disk with a clear directory hierarchy. Understanding this structure is essential for backup, monitoring, and debugging.

### 9.1 Database Directory Layout

Each TidesDB database has a root directory containing subdirectories for each column family

```
mydb/
├── my_cf/
│   ├── wal_1.log
│   ├── sstable_0.sst
│   ├── sstable_1.sst
│   └── sstable_2.sst
├── users/
│   ├── wal_0.log
│   └── sstable_0.sst
└── sessions/
    └── wal_0.log
```

### 9.2 File Naming Conventions

#### Write-Ahead Log (WAL) Files
- **Format** `wal_<memtable_id>.log`
- **Examples** `wal_0.log`, `wal_1.log`, `wal_2.log`
- **Purpose** Durability - records all writes before they're applied to memtable
- **Lifecycle**
  - Created when a new memtable is created (on database open or rotation)
  - Each memtable has its own dedicated WAL file
  - WAL ID matches the memtable ID (monotonically increasing counter)
  - Multiple WAL files can exist simultaneously (one for active memtable, others for memtables in flush queue)
  - Deleted only after memtable is successfully flushed to SSTable AND freed
  - Automatically recovered on database restart if flush didn't complete

#### SSTable Files
- **Format** `sstable_<sstable_id>.sst`
- **Examples** `sstable_0.sst`, `sstable_1.sst`, `sstable_2.sst`
- **Purpose** Persistent storage of flushed memtables
- **Lifecycle**
  - Created when memtable is flushed (when size exceeds `memtable_flush_size`)
  - SSTable ID is monotonically increasing per column family
  - Merged during compaction (old SSTables deleted, new merged SSTable created)
  - Contains sorted key-value pairs with bloom filter and index metadata

### 9.3 WAL Rotation and Memtable Lifecycle Example

This example demonstrates how WAL files are created, rotated, and deleted:

**1. Initial State**
```
Active Memtable (ID: 0) → wal_0.log
```

**2. Memtable Fills Up** (size >= `memtable_flush_size`)
```
Active Memtable (ID: 0) → wal_0.log  [FULL - triggers rotation]
```

**3. Rotation Occurs**
```
New Active Memtable (ID: 1) → wal_1.log  [new WAL created]
Immutable Memtable (ID: 0) → wal_0.log  [queued for flush]
```

**4. Background Flush (Async)**
```
Active Memtable (ID: 1) → wal_1.log
Flushing: Memtable (ID: 0) → sstable_0.sst  [writing to disk]
wal_0.log  [still exists - flush in progress]
```

**5. Flush Complete**
```
Active Memtable (ID: 1) → wal_1.log
SSTable: sstable_0.sst  [persisted]
wal_0.log  [DELETED - memtable freed after flush]
```

**6. Next Rotation (Before Previous Flush Completes)**
```
New Active Memtable (ID: 2) → wal_2.log  [new active]
Immutable Memtable (ID: 1) → wal_1.log  [queued for flush]
Flushing: Memtable (ID: 0) → sstable_0.sst  [still flushing]
wal_0.log  [still exists - flush not complete]
```

**7. After All Flushes Complete**
```
Active Memtable (ID: 2) → wal_2.log
SSTable: sstable_0.sst
SSTable: sstable_1.sst
wal_0.log, wal_1.log  [DELETED - both flushes complete]
```

### 9.4 Directory Management

**Creating a column family** creates a new subdirectory
```c
tidesdb_create_column_family(db, "my_cf", &cf_config);
// Creates mydb/my_cf/ directory with initial wal_0.log
```

**Dropping a column family** removes the entire subdirectory
```c
tidesdb_drop_column_family(db, "my_cf");
// Deletes mydb/my_cf/ directory and all contents (WALs, SSTables)
```

### 9.5 Monitoring Disk Usage

Useful commands for monitoring TidesDB storage

```bash
# Check total database size
du -sh mydb/

# Check per-column-family size
du -sh mydb/*/

# Count WAL files (should be 1-2 per CF normally)
find mydb/ -name "wal_*.log" | wc -l

# Count SSTable files
find mydb/ -name "sstable_*.sst" | wc -l

# List largest SSTables
find mydb/ -name "sstable_*.sst" -exec ls -lh {} \; | sort -k5 -hr | head -10
```

### 9.6 Best Practices

**Disk Space Monitoring**
- Monitor WAL file count - typically 1-3 per column family (1 active + 1-2 in flush queue)
- Many WAL files (>5) may indicate flush backlog, slow I/O, or configuration issue
- Monitor SSTable count - triggers compaction at `max_sstables_before_compaction`
- Set appropriate `memtable_flush_size` based on write patterns and flush speed

**Backup Strategy**
```bash
# Stop writes, flush all memtables, then backup
# In your application:
tidesdb_flush_memtable(cf);  # Force flush before backup

# Then backup:
tar -czf mydb_backup.tar.gz mydb/
```

**Performance Tuning**
- Larger `memtable_flush_size` = fewer, larger SSTables = less compaction
- Smaller `memtable_flush_size` = more, smaller SSTables = more compaction
- Adjust `max_sstables_before_compaction` based on read/write ratio
- Use `enable_background_compaction` for automatic maintenance

## 10. Error Handling

TidesDB v1 uses simple integer return codes for error handling

- `0` (TDB_SUCCESS) indicates successful operation
- Negative values indicate specific error conditions
- Error codes include memory allocation failures, I/O errors, corruption detection, lock failures, and more
- Detailed error codes allow for precise error handling in production systems

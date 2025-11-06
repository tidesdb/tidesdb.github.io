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
- Immutable on-disk files (SSTables are Sorted String Tables)
- Processes that merge SSTables to reduce storage overhead and improve read performance

This structure allows for efficient writes by initially storing data in memory and then periodically flushing to disk in larger batches, reducing the I/O overhead associated with random writes.


## 3. TidesDB Architecture

![Architecture Diagram](../../../assets/img2.png)


### 3.1 Overview
TidesDB uses a two-tiered storage architecture: a memory level that stores 
recently written key-value pairs in sorted order using a skip list data 
structure, and a disk level containing multiple SSTables. When reading data, 
newer tables take precedence over older ones, ensuring the most recent 
version of a key is always retrieved.

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
The memtable is an in-memory data structure that serves as the first landing 
point for all write operations. TidesDB implements the memtable as a lock-free 
skip list, using atomic operations for concurrent reads while writers acquire 
an exclusive lock to maintain sorted key-value pairs. Each column family can 
register a custom key comparison function (memcmp, string, numeric, or 
user-defined) that determines sort order consistently across the entire 
system--memtable, SSTables, and iterators all use the same comparison logic. 
The skip list's maximum level and probability parameters are configurable per 
column family, allowing tuning for specific workloads. When the memtable 
reaches a configurable size threshold, it is atomically flushed to disk as an 
SSTable, with atomic types ensuring thread-safe size tracking and version 
management throughout the process.

### 4.2 Block Manager Format

The block manager is TidesDB's low-level storage abstraction that manages both WAL files and SSTable files. All persistent data is stored using the block manager format.

#### File Structure

Every block manager file (WAL or SSTable) has the following structure

```
[File Header is 12 bytes]
[Block 0]
[Block 1]
[Block 2]
...
[Block N]
```

#### File Header (12 bytes)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 3 bytes | Magic | `0x544442` ("TDB" in hex) |
| 3 | 1 byte | Version | Block manager version (currently 1) |
| 4 | 4 bytes | Block Size | Default block size for this file |
| 8 | 4 bytes | Padding | Reserved for future use |

#### Block Format

Each block has the following structure

```
[Block Size is 8 bytes (uint64_t)]
[SHA1 Checksum is 20 bytes]
[Inline Data is a variable, up to block_size]
[Overflow Offset is 8 bytes (uint64_t)]
[Overflow Data is a variable, if size > block_size]
```

**Block Header (36 bytes minimum)**
- **Block Size** (8 bytes) - Total size of the data (inline + overflow)
- **SHA1 Checksum** (20 bytes) - Integrity check for the entire block data
- **Inline Data** (variable) - First portion of data, up to `block_size` bytes
- **Overflow Offset** (8 bytes) - File offset to overflow data (0 if no overflow)

**Overflow Handling**
- If data size ≤ `block_size` (default 32KB) All data stored inline, overflow offset = 0
- If data size > `block_size` First 32KB inline, remainder at overflow offset
- Overflow data written immediately after main block
- Allows efficient storage of both small and large blocks

#### Block Write Process

1. Compute SHA1 checksum of entire data
2. Determine inline size (min of data size and block_size)
3. Calculate remaining overflow size
4. **Build main block buffer**
   - Block size (8 bytes)
   - SHA1 checksum (20 bytes)
   - Inline data (up to 32KB)
   - Overflow offset (8 bytes, initially 0)
5. Write main block atomically using `pwrite()`
6. **If overflow exists**
   - Write overflow data at end of file
   - Update overflow offset in main block
7. Optionally fsync based on sync mode

#### Block Read Process

1. Read block size (8 bytes)
2. Read SHA1 checksum (20 bytes)
3. Calculate inline size
4. Read inline data
5. Read overflow offset (8 bytes)
6. **If overflow offset > 0**
   - Seek to overflow offset
   - Read remaining data
7. Concatenate inline + overflow data
8. Verify SHA1 checksum
9. Return block if valid

#### Integrity and Recovery
TidesDB implements multiple layers of data integrity protection. All block 
reads verify SHA1 checksums to detect corruption, while writes use `pwrite()` 
for atomic block-level updates. During startup, the system validates the last 
block's integrity--if corruption is detected, the file is automatically 
truncated to the last known-good block. This approach ensures crash safety by 
guaranteeing that incomplete or corrupted writes are identified and cleaned up 
during recovery.

#### Cursor Operations

The block manager provides cursor-based sequential access for efficient data 
traversal. Cursors support forward iteration via `cursor_next()` and backward 
iteration through `cursor_prev()`, which scans from the beginning to locate 
the previous block. Random access is available through `cursor_goto(pos)`, 
allowing jumps to specific file offsets. Each cursor maintains its current 
position and block size, with boundary checking methods like `at_first()`, 
`at_last()`, `has_next()`, and `has_prev()` to prevent out-of-bounds access.

#### Sync Modes

- **TDB_SYNC_NONE** - No explicit fsync, relies on OS page cache (fastest)
- **TDB_SYNC_FULL** - Fsync after every block write (most durable)
- Configurable per file (WAL and SSTable can have different modes)

#### Thread Safety

- **Write mutex** - Serializes all write operations to prevent corruption
- **Concurrent reads** - Multiple readers can read simultaneously using `pread()`
- **Atomic operations** - All writes use `pwrite()` for atomicity

### 4.3 SSTables (Sorted String Tables)
SSTables serve as TidesDB's immutable on-disk storage layer. Internally, each 
SSTable is organized into multiple blocks containing sorted key-value pairs. 
To accelerate lookups, every SSTable maintains its minimum and maximum keys, 
allowing the system to quickly determine if a key might exist within it. 
Optional block indices provide direct access to specific blocks, eliminating 
the need to scan entire files. The immutable nature of SSTables--once written, 
they are never modified, only merged or deleted--ensures data consistency and 
enables lock-free concurrent reads.

#### SSTable Block Layout

SSTables use the block manager format with a specific block ordering

```
[File Header is 12 bytes - Block Manager Header]
[Block 0: KV Pair 1]
[Block 1: KV Pair 2]
[Block 2: KV Pair 3]
...
[Block N-3: KV Pair N]
[Block N-2: Bloom Filter]
[Block N-1: Index (SBHA)]
[Block N: Metadata]
```

**Block Order (from first to last)**
1. **Data Blocks** - Key-value pairs in sorted order (blocks 0 to N-3)
2. **Bloom Filter Block** - Serialized bloom filter (block N-2)
3. **Index Block** - Sorted Binary Hash Array (SBHA) for direct lookups (block N-1)
4. **Metadata Block** - Min/max keys and entry count (block N, last block)

#### Data Block Format (KV Pairs)

Each data block contains a single key-value pair

```
[KV Header is 24 bytes]
[Key is variable]
[Value is variable]
```

**KV Pair Header (24 bytes)**
```c
typedef struct {
    uint8_t version;        // Format version (currently 1)
    uint8_t flags;          // TDB_KV_FLAG_TOMBSTONE (0x01) for deletes
    uint32_t key_size;      // Key size in bytes
    uint32_t value_size;    // Value size in bytes
    int64_t ttl;            // Unix timestamp for expiration (-1 = no expiration)
} tidesdb_kv_pair_header_t;
```

**Compression**
- If `compressed = 1` in column family config, entire block is compressed
- Compression applied to [Header + Key + Value] as a unit
- Supports Snappy, LZ4, or ZSTD algorithms
- Decompression happens on read before parsing header

#### Bloom Filter Block

Stored as second-to-last block (N-2)
- Serialized bloom filter data structure
- Used to quickly determine if a key might exist in the SSTable
- Avoids unnecessary disk I/O for non-existent keys
- False positive rate configurable per column family (default 1%)

#### Index Block (SBHA)

Stored as third-to-last block (N-1)
- Sorted Binary Hash Array (SBHA) mapping keys to block offsets
- Enables direct block access without scanning
- Format `[key_hash] -> [file_offset]`
- Only used if `use_sbha = 1` in column family config
- If disabled, falls back to linear scan through data blocks

#### Metadata Block

Stored as last block (N)

```
[Magic is 4 bytes (0x5353544D = "SSTM")]
[Num Entries is 8 bytes (uint64_t)]
[Min Key Size is 4 bytes (uint32_t)]
[Min Key is a variable]
[Max Key Size is 4 bytes (uint32_t)]
[Max Key is a variable]
```

**Purpose**
- Magic number identifies this as a metadata block
- Min/max keys to optimize key look up
- Num entries tracks total KV pairs in SSTable
- Loaded first during SSTable recovery (cursor starts at last block)

#### SSTable Write Process

1. Iterate through memtable in sorted order
2. **For each KV pair**
   - Build KV header + key + value
   - Optionally compress
   - Write as data block (blocks 0, 1, 2, ...)
   - Add key to bloom filter
   - Add key->offset mapping to index
   - Track min/max keys
3. Serialize and write bloom filter (block N-2)
4. Serialize and write index (block N-1)
5. Build and write metadata block (block N)

#### SSTable Read Process

1. **Load SSTable** (recovery)
   - Open block manager file
   - Seek to last block (metadata)
   - Read and parse metadata (min/max keys, entry count)
   - Read previous block (index)
   - Read previous block (bloom filter)

2. **Lookup Key**
   - Check bloom filter (quick rejection)
   - If SBHA enabled a lookup offset in index, read specific block
   - If SBHA disabled a linear scan through data blocks
   - Decompress block if needed
   - Parse KV header and extract value
   - Check TTL expiration
   - Return value or tombstone marker

### 4.4 Write-Ahead Log (WAL)
For durability, TidesDB implements a write-ahead logging mechanism with a rotating WAL system tied to memtable lifecycle.

#### 4.4.1 WAL File Naming and Lifecycle

File Format: `wal_<memtable_id>.log`
- I.e. `wal_0.log`, `wal_1.log`, `wal_2.log`
- Each memtable has its own dedicated WAL file
- WAL ID matches the memtable ID (monotonically increasing counter)
- **Multiple WAL files can exist simultaneously** - one for active memtable, others for memtables in flush queue
- WAL files are deleted only after memtable is successfully flushed to SSTable AND freed

#### 4.4.2 WAL Rotation Process

TidesDB uses a rotating WAL system that works as follows

1. **Initial State** Active Memtable (ID 0) → `wal_0.log`
2. **Memtable Fills Up** When size >= `memtable_flush_size`, rotation is triggered
3. **Rotation Occurs**
   - New Active Memtable (ID 1) → `wal_1.log` (new WAL created)
   - Immutable Memtable (ID 0) → `wal_0.log` (queued for flush)
4. **Background Flush** Memtable (ID 0) writes to `sstable_0.sst` while `wal_0.log` still exists
5. **Flush Complete** `wal_0.log` is deleted after memtable is freed
6. **Concurrent Operations** Multiple memtables can be in flush queue, each with its own WAL file

#### 4.4.3 WAL Features

- All writes (including deletes/tombstones) are first recorded in the WAL before being applied to the memtable
- WAL entries can be optionally compressed using Snappy, LZ4, or ZSTD
- Each column family maintains its own independent WAL files
- Automatic recovery on database startup reconstructs memtables from WALs

#### 4.4.4 Recovery Process

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

**SSTable Recovery Ordering**
- SSTables are discovered by reading the column family directory
- Directory order is filesystem-dependent and non-deterministic
- **SSTables are sorted by ID after loading** to ensure correct read semantics
- This guarantees newest-to-oldest ordering for read path (searches from end of array backwards)
- Without sorting, stale data could be returned if newer SSTables load before older ones

### 4.5 Bloom Filters
To optimize read operations, TidesDB employs Bloom filters--probabilistic data 
structures that quickly determine if a key might exist in an SSTable. By 
filtering out SSTables that definitely don't contain a key, Bloom filters help 
avoid unnecessary disk I/O. Each Bloom filter is configurable per column 
family to balance memory usage against read performance and is stored at block 
1 within the SSTable, immediately following the min-max key block.

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
TidesDB provides ACID transaction support with multi-column-family 
capabilities. Transactions are initiated through `tidesdb_txn_begin()` for 
writes or `tidesdb_txn_begin_read()` for read-only operations, with a single 
transaction capable of operating atomically across multiple column families. 
The system implements read committed isolation, where read transactions see a 
consistent snapshot via copy-on-write without blocking writers. Write 
transactions acquire exclusive locks per column family only during commit, 
ensuring atomicity--all operations succeed together or automatically rollback 
on failure. Transactions support read-your-own-writes semantics, allowing 
uncommitted changes to be read before commit. The API uses simple integer 
return codes (0 for success, -1 for error) rather than complex error 
structures.

### 6. Compaction Strategies
TidesDB implements two distinct compaction strategies

### 6.1 Parallel Compaction

TidesDB implements parallel compaction using a semaphore-based thread pool to 
reduce SSTable count, remove tombstones, and purge expired TTL entries. The 
number of concurrent threads is configurable via `compaction_threads` in the 
column family config (default 4). Compaction pairs SSTables from oldest to 
newest, with each thread processing one pair, approximately halving the 
SSTable count per run. When `compaction_threads > 0`, `tidesdb_compact()` 
automatically uses parallel execution. At least 2 SSTables are required to 
trigger compaction.

### 6.2 Background Compaction

Background compaction provides automatic, hands-free SSTable management. 
Enabled via `enable_background_compaction = 1` in the column family 
configuration, it automatically triggers when the SSTable count reaches 
`max_sstables_before_compaction`. A dedicated background thread operates 
independently without blocking application operations, merging SSTable pairs 
incrementally throughout the database lifecycle until shutdown.

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

TidesDB provides two sync modes to balance durability and performance

- **TDB_SYNC_NONE** Fastest, least durable (OS handles flushing to disk via page cache)
- **TDB_SYNC_FULL** Most durable (fsync on every write operation)

The sync mode can be configured per column family, allowing different durability guarantees for different data types.

### 7.4 Configurable Parameters

TidesDB allows fine-tuning through various configurable parameters

- Memtable flush thresholds
- Skip list configuration (max level and probability)
- Bloom filter usage and false positive rate
- Compression settings (algorithm selection)
- Compaction trigger thresholds and thread count
- Sync mode (TDB_SYNC_NONE or TDB_SYNC_FULL)
- Debug logging
- SBHA (Sorted Binary Hash Array) usage
- Thread pool sizes (flush and compaction)

### 7.5 Thread Pool Architecture

For efficient resource management, TidesDB employs shared thread pools at the 
database level. Rather than maintaining separate pools per column family, all 
column families share common flush and compaction thread pools configured 
during database initialization. Operations are submitted as tasks to these 
pools, enabling non-blocking execution--application threads can continue 
processing while flush and compaction work proceeds in the background. This 
architecture minimizes resource overhead and provides consistent, predictable 
performance across the entire database.

**Configuration**
```c
tidesdb_config_t config = {
    .db_path = "./mydb",
    .num_flush_threads = 4,      /* 4 threads for flush operations */
    .num_compaction_threads = 8  /* 8 threads for compaction */
};
```

**Benefits**
- Resource efficiency - one set of threads serves all column families
- Better thread utilization across workloads
- Simpler configuration - set once at database level
- Scalability - easily tune for available CPU cores

**Default values**
- `num_flush_threads` - Default is 2 `TDB_DEFAULT_THREAD_POOL_SIZE` (I/O bound, usually 2-4 sufficient)
- `num_compaction_threads` - Default is 2 `TDB_DEFAULT_THREAD_POOL_SIZE` (CPU bound, can be higher 4-16)

## 8. Concurrency and Thread Safety

TidesDB is designed for great concurrency with minimal blocking through a reader-writer lock model.

### 8.1 Reader-Writer Locks

Each column family uses a reader-writer lock to enable efficient concurrent 
access. Multiple readers can access the same column family simultaneously 
without blocking each other, and read operations can proceed even while writes 
are in progress. However, writers acquire exclusive access, allowing only one 
write transaction per column family at a time to ensure data consistency.

### 8.2 Transaction Isolation

TidesDB implements read committed isolation with read-your-own-writes 
semantics. Read transactions acquire read locks and see a consistent snapshot 
of committed data through copy-on-write, ensuring they never observe 
uncommitted changes from other transactions. Write transactions acquire write 
locks only during commit to ensure atomic updates. Within a single 
transaction, uncommitted changes are immediately visible, allowing operations 
to read their own writes before commit.

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
│   ├── config.cfc         # Persisted column family configuration
│   ├── wal_1.log
│   ├── sstable_0.sst
│   ├── sstable_1.sst
│   └── sstable_2.sst
├── users/
│   ├── config.cfc
│   ├── wal_0.log
│   └── sstable_0.sst
└── sessions/
    ├── config.cfc
    └── wal_0.log
```

### 9.2 File Naming Conventions

#### Write-Ahead Log (WAL) Files
Write-Ahead Log (WAL) files follow the naming convention `wal_<memtable_id>.log` 
(e.g., `wal_0.log`, `wal_1.log`) and provide durability by recording all 
writes before they're applied to the memtable. Each memtable has its own 
dedicated WAL file with a matching ID based on a monotonically increasing 
counter. WAL files are created when a new memtable is created--either on 
database open or during memtable rotation--and multiple WAL files can exist 
simultaneously: one for the active memtable and others for memtables in the 
flush queue. A WAL file is deleted only after its corresponding memtable is 
successfully flushed to an SSTable and freed from memory. If a flush doesn't 
complete before shutdown, the WAL is automatically recovered on the next 
database restart, replaying operations to restore consistency.

#### SSTable Files
SSTable files follow the naming convention `sstable_<sstable_id>.sst` (e.g., 
`sstable_0.sst`, `sstable_1.sst`) and provide persistent storage for flushed 
memtables. An SSTable is created when a memtable exceeds the 
`memtable_flush_size` threshold, with IDs assigned using a monotonically 
increasing counter per column family. Each SSTable contains sorted key-value 
pairs along with bloom filter and index metadata for efficient lookups. During 
compaction, old SSTables are merged into new consolidated files, and the 
original SSTables are deleted after the merge completes successfully.

### 9.3 WAL Rotation and Memtable Lifecycle Example

This example demonstrates how WAL files are created, rotated, and deleted

**1. Initial State**
```
Active Memtable (ID 0) → wal_0.log
```

**2. Memtable Fills Up** (size >= `memtable_flush_size`)
```
Active Memtable (ID 0) → wal_0.log  [FULL - triggers rotation]
```

**3. Rotation Occurs**
```
New Active Memtable (ID 1) → wal_1.log  [new WAL created]
Immutable Memtable (ID 0) → wal_0.log  [queued for flush]
```

**4. Background Flush (Async)**
```
Active Memtable (ID 1) → wal_1.log
Flushing Memtable (ID 0) → sstable_0.sst  [writing to disk]
wal_0.log  [still exists - flush in progress]
```

**5. Flush Complete**
```
Active Memtable (ID 1) → wal_1.log
sstable_0.sst  [persisted]
wal_0.log  [DELETED - memtable freed after flush]
```

**6. Next Rotation (Before Previous Flush Completes)**
```
New Active Memtable (ID 2) → wal_2.log  [new active]
Immutable Memtable (ID 1) → wal_1.log  [queued for flush]
Flushing Memtable (ID 0) → sstable_0.sst  [still flushing]
wal_0.log  [still exists - flush not complete]
```

**7. After All Flushes Complete**
```
Active Memtable (ID 2) → wal_2.log
SSTable sstable_0.sst
SSTable sstable_1.sst
wal_0.log, wal_1.log  [DELETED means both flushes complete]
```

### 9.4 Directory Management

**Creating a column family** creates a new subdirectory
```c
tidesdb_create_column_family(db, "my_cf", &cf_config);
// Creates mydb/my_cf/ directory with
//   - initial wal_0.log (for active memtable)
//   - config.cfc (persisted configuration)
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
# In your application
tidesdb_flush_memtable(cf);  # Force flush before backup

# Then backup
tar -czf mydb_backup.tar.gz mydb/
```

**Performance Tuning**
- Larger `memtable_flush_size` = fewer, larger SSTables = less compaction
- Smaller `memtable_flush_size` = more, smaller SSTables = more compaction
- Adjust `max_sstables_before_compaction` based on read/write ratio
- Use `enable_background_compaction` for automatic maintenance

## 10. Error Handling

TidesDB 1 uses simple integer return codes for error handling

- `0` (TDB_SUCCESS) indicates successful operation
- Negative values indicate specific error conditions
- Error codes include memory allocation failures, I/O errors, corruption detection, lock failures, and more
- Detailed error codes allow for precise error handling in production systems

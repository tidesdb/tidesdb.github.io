---
title: How does TidesDB work?
description: A high level description of how TidesDB works.
---

## 1. Introduction
Here we explore the inner workings of TidesDB, its architecture, core components, and operational mechanisms.

## 2. Theoretical Foundation
### 2.1 Origins and Concept
The Log-Structured Merge-tree was first introduced by Patrick O'Neil, Edward Cheng, Dieter Gawlick, and Elizabeth O'Neil in their 1996 paper. The fundamental insight of the LSM-tree is to optimize write operations by using a multi-tier storage structure that defers and batches disk writes.

### 2.2 Basic LSM-tree Structure
An LSM-tree typically consists of several components:

- In-memory buffers (memtables) that accept writes
- Immutable on-disk files (SSTables are Sorted String Tables)
- Processes that merge SSTables to reduce storage overhead and improve read performance

This structure allows for efficient writes by initially storing data in memory and then periodically flushing to disk in larger batches, reducing the I/O overhead associated with random writes.


## 3. TidesDB Architecture

### 3.1 Overview

TidesDB implements a Log-Structured Merge-tree storage engine with a multi-level architecture designed for high-throughput concurrent operations. The system organizes data through a hierarchical structure consisting of volatile memory components, persistent write-ahead logs, and tiered immutable disk storage, with all operations coordinated through lock-free atomic primitives and carefully synchronized background worker threads.

At the storage engine level, TidesDB maintains a central database instance (`tidesdb_t`) that coordinates multiple independent column families, each functioning as an isolated key-value namespace with dedicated storage structures and configurable operational parameters. The database instance manages shared infrastructure including engine-level thread pools for flush and compaction operations, a background reaper thread that closes unused SSTable file handles when the open file limit is reached, an optional lock-free global block cache for decompressed klog and vlog blocks, and recovery synchronization primitives that ensure crash-safe initialization. Column families are organized in a dynamically resizable array protected by a reader-writer lock (`cf_list_lock`), enabling concurrent read access to the column family list while serializing structural modifications during column family creation and deletion operations.

Each column family (`tidesdb_column_family_t`) maintains its own independent LSM-tree structure consisting of three primary storage tiers. The memory tier contains an active memtable implemented as a lock-free skip list with atomic reference counting, paired with a dedicated write-ahead log (WAL) file stored in the column family directory for durability. When the active memtable reaches a configurable size threshold, it transitions to an immutable state and is enqueued in the immutable memtable queue while a new active memtable is atomically swapped into place. The disk tier organizes SSTables into multiple levels using a fixed-size array with atomic pointers. TidesDB uses 1-based level numbering in filenames (L1, L2, L3...) but 0-based array indexing internally (levels[0], levels[1], levels[2]...). Level 1 (stored in levels[0]) is the first disk level where recently flushed SSTables land in arbitrary order with overlapping key ranges. Subsequent levels maintain sorted, non-overlapping key ranges with exponentially increasing capacity determined by a configurable size ratio. Level operations use atomic operations and per-CF flags (is_flushing, is_compacting) for coordination without locks. This multi-level organization enables efficient range queries and predictable compaction behavior as data ages through the storage hierarchy.

Background operations are coordinated through engine-level thread pools rather than per-column-family threads, providing superior resource utilization and consistent performance characteristics across the entire database instance. The flush thread pool processes memtable-to-SSTable flush operations submitted from any column family, while the compaction thread pool handles SSTable merge operations across all levels. Worker threads in both pools execute a blocking dequeue pattern, waiting efficiently on task queues until work arrives, then processing tasks to completion before returning to the wait state. This architecture decouples application write operations from background I/O, enabling sustained write throughput independent of disk performance while maintaining bounded memory usage through flow control mechanisms.

Crash recovery and initialization follow a strictly ordered sequence designed to prevent race conditions between recovery operations and background worker threads. During database open, the system first creates background worker threads for flush and compaction operations, but these threads immediately block on a recovery condition variable before processing any work. Database recovery then proceeds with exclusive access to all data structures: scanning the database directory for column family subdirectories, reconstructing column family metadata from persisted configuration files, discovering WAL files and SSTables, and loading SSTable metadata (min/max keys, bloom filters, block indices) into memory. For each WAL file discovered, the system replays entries into a new memtable using the skip list's version chain mechanism, then enqueues the recovered memtable as immutable for background flush. After all column families are recovered, the system signals the recovery condition variable, unblocking worker threads to begin processing the queued flush tasks asynchronously. Recovered memtables remain accessible for reads while being flushed in the background, with the immutable memtable queue serving as a searchable tier in the read path. This design guarantees that all persisted data is accessible and all data structures are consistent before background operations commence, ensuring correctness in the presence of crashes, incomplete writes, or corrupted data files.

The read path implements a multi-tier search strategy that prioritizes recent data over historical data, ensuring that the most current version of any key is always retrieved. Queries first examine the active memtable using lock-free atomic operations, then proceed through immutable memtables in the flush queue in reverse chronological order, and finally search SSTables within each level from newest to oldest. SSTable lookups employ multiple optimization techniques including min/max key range filtering to skip irrelevant files, probabilistic bloom filter checks to avoid disk I/O for non-existent keys, and optional compact block indices that enable direct block access without linear scanning. This hierarchical search pattern, combined with atomic reference counting on all data structures, enables lock-free concurrent reads that scale linearly with CPU core count while maintaining strong consistency guarantees and read-your-own-writes semantics within transactions.

### 3.2 Column Families

TidesDB organizes data into column families, a design pattern that provides namespace isolation and enables independent configuration of storage and operational parameters for different data domains within a single database instance. Each column family (`tidesdb_column_family_t`) functions as a logically independent LSM-tree with its own complete storage hierarchy, from volatile memory structures through persistent disk storage, while sharing the underlying engine infrastructure for resource efficiency.

<div class="architecture-diagram">

![Column Families](../../../assets/img3.png)

</div>

A column family maintains complete storage isolation through dedicated data structures at each tier of the LSM hierarchy. The memory tier consists of an atomically-swapped active memtable pointer, a monotonically increasing memtable generation counter (ensuring each memtable has a unique identifier) for versioning, an active WAL file handle, and a queue of immutable memtables awaiting flush. The active memtable pointer is swapped atomically using compare-and-swap operations on the `active_memtable` field, while the immutable memtable is added to the flush queue to ensure correct ordering during recovery. The disk tier organizes SSTables into a dynamically allocated array of levels, with each level protected by a reader-writer lock that enables concurrent reads while serializing structural modifications during compaction. Sequence number generation occurs independently per column family through atomic increment operations, ensuring that transaction ordering within a column family remains consistent while allowing concurrent operations across different column families to proceed without coordination overhead.

Configuration parameters are specified per column family (CF) at creation time and persisted to disk in INI format within the column family's directory. These parameters control fundamental operational characteristics including memtable flush thresholds that determine memory-to-disk transition points, skip list structural parameters (maximum level and probability) that affect search performance, compression algorithms and settings that balance CPU utilization against storage efficiency, bloom filter configuration including false positive rates, block index enablement for direct block access, sync mode (`TDB_SYNC_NONE`, `TDB_SYNC_INTERVAL`, `TDB_SYNC_FULL` - see Section 4.4 for details) with configurable sync interval in microseconds for interval mode, and compaction policies including automatic background compaction triggers and thread allocation. Many parameters including sync mode and sync interval can be updated at runtime and persisted back to disk, allowing operational tuning without database restart. Once a column family is created, certain parameters such as the key comparator function become immutable for the lifetime of the column family, ensuring consistent sort order across all storage tiers and preventing data corruption from comparator changes.

Concurrency control within a column family employs a lock-free approach using atomic operations and flags. The active memtable skip list uses lock-free Compare-And-Swap (CAS) operations for all insertions and lookups, enabling unlimited concurrent readers and writers without contention. Structural operations that modify the storage hierarchy use atomic flags: the `is_flushing` flag serializes memtable rotation and flush queue modifications, while the `is_compacting` flag serializes compaction operations. Both flags use atomic CAS to ensure only one structural operation of each type runs at a time per column family. SSTable arrays in levels use atomic pointers with acquire/release memory ordering, allowing concurrent reads to safely access the hierarchy while compaction atomically updates level structures. This design ensures that common-case operations (reads and writes) proceed without blocking while maintaining correctness during structural changes through careful atomic operations and memory ordering.

Column families enable domain-specific optimization strategies within a single database instance. High-throughput write-heavy workloads can configure large memtable sizes and aggressive compression to maximize write batching and minimize disk I/O. Read-heavy workloads can enable bloom filters and block indices to accelerate lookups at the cost of additional storage overhead. Temporary or cache-like data can disable durability features (TDB_SYNC_NONE) and use minimal compression for maximum performance, production workloads can use periodic background syncing (TDB_SYNC_INTERVAL) with configurable sync intervals to balance performance and bounded data loss, while critical persistent data can enable full synchronous writes (TDB_SYNC_FULL) and strong compression for maximum reliability. The TDB_SYNC_INTERVAL mode is particularly valuable for production systems, allowing applications to configure acceptable data loss windows (e.g., 1 second) while maintaining high write throughput through a single shared background sync thread that monitors all interval-mode column families. This flexibility allows applications to co-locate diverse data types with different performance and durability requirements within a single storage engine instance, simplifying operational management while maintaining optimal performance characteristics for each data domain.

## 4. Core Components and Mechanisms
### 4.1 Memtable
<div class="architecture-diagram">

![Memtable](../../../assets/img4.png)

</div>

The memtable is the first landing point for all column family write operations. TidesDB implements the memtable using a lock-free skip list with atomic operations and a versioning strategy for exceptional read performance. When a key is updated, a new version is prepended to the version list for that key, but reads always return the newest version (head of the list), implementing **last-write-wins** semantics. This allows concurrent reads and writes without blocking.

**Lock-Free Concurrency Model**

Readers never acquire locks, never block, and scale linearly with CPU cores. Writers perform lock-free atomic operations on the skip list structure using CAS (Compare-And-Swap) instructions. Readers don't block writers, and writers don't block readers. All read operations use atomic pointer loads with acquire memory ordering for correct synchronization. Flush and compaction operations use atomic flags (`is_flushing` and `is_compacting`) with CAS to serialize structural changes without blocking skip list operations.

**Memory Management**

- Skip list nodes are allocated individually using `malloc()` for each node
- Keys are always allocated separately and stored as pointers in nodes
- Values are allocated separately and stored in version structures
- Each key can have multiple versions linked in a list, with the newest version at the head
- Reads always return the newest version (last-write-wins semantics)
- Individual nodes are never freed during normal operation; they remain allocated until the entire skip list is destroyed (via `skip_list_free` or `skip_list_clear`)
- The skip list structure itself uses atomic reference counting to prevent premature destruction during concurrent access

**Custom Comparators**

Each column family can register a custom key comparison function (memcmp, string, numeric, or user-defined) that determines sort order consistently across the entire system--memtable, SSTables, block indexes, and iterators all use the same comparison logic.  Once a comparator is registered, it cannot be changed for the duration of the column family's lifecycle.

**Configuration and Lifecycle**

The skip list's flush threshold (`write_buffer_size`), maximum level, and probability parameters are configurable per column family. When the memtable reaches the size threshold, it becomes immutable and is queued for flushing while a new active memtable is created. The immutable memtable is flushed to disk as an SSTable (klog and vlog files) by a background thread pool, with reference counting ensuring the memtable isn't freed until all readers complete and the flush finishes. Each memtable is paired with a WAL (Write-Ahead Log) for durability and recovery. When a memtable is in the flush queue and immutable it is still accessible for reading. Because the memtable has a WAL associated with it, you will see a WAL file (e.g., wal_4.log) until the flush is complete. If a crash occurs, the memtable's WAL is replayed using skip list version chains to reconstruct the memtable state, then the recovered memtable is enqueued as immutable for background flush.


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

#### File Header (8 bytes)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 3 bytes | Magic | `0x544442` ("TDB" in hex) |
| 3 | 1 byte | Version | Block manager version (currently 6) |
| 4 | 4 bytes | Padding | Reserved for future use |


#### Block Format

Each block has the following structure

```
[Block Size - 4 bytes (uint32_t)]
[xxHash32 Checksum - 4 bytes]
[Data - variable size]
[Footer Size - 4 bytes (uint32_t, duplicate of block size)]
[Footer Magic - 4 bytes (`0x42445442` "BTDB")]
```

**Block Header (8 bytes)**

The block header consists of the block size (4 bytes, uint32_t) representing the size of the data payload, and an xxHash32 checksum (4 bytes) for integrity checking the block data. The uint32_t size field supports blocks up to 4GB, which is sufficient since TidesDB uses key-value separation and doesn't store massive values in single blocks.

**Block Footer (8 bytes)**

The block footer provides fast validation without reading the entire block. It contains a duplicate of the block size (4 bytes) and a magic number `0x42445442` ("BTDB" reversed, 4 bytes). During recovery and validation, the system can quickly verify block integrity by checking if the footer size matches the header size and the magic is correct.

#### Block Write Process

The write process begins by computing the xxHash32 checksum of the data. The block buffer is constructed with the block size (4 bytes), xxHash32 checksum (4 bytes), the data payload, footer size (4 bytes, duplicate of block size), and footer magic (4 bytes, `0x42445442`). The complete block is written atomically using `pwrite()` at the current file offset. The file size is updated atomically using atomic compare-and-swap operations. Finally, fsync is optionally performed based on the sync mode (BLOCK_MANAGER_SYNC_NONE or BLOCK_MANAGER_SYNC_FULL).

#### Block Read Process

The read process reads the block size (4 bytes) and xxHash32 checksum (4 bytes) from the block header. It then reads the data payload of the specified size. After reading the data, it reads the footer (8 bytes) containing the footer size and footer magic. The system verifies that the footer size matches the header size and the footer magic equals `0x42445442`. The xxHash32 checksum is verified against the data. If all validations pass, the block data is returned; otherwise an error is returned indicating corruption.

#### Integrity and Recovery

TidesDB implements multiple layers of data integrity protection with different strategies for different file types. All block reads verify xxHash32 checksums to detect corruption, while writes use `pwrite()` for atomic block-level updates.

**Validation Modes**

During startup, the system validates file integrity using two modes:

- **Strict mode (SSTables)** · SSTable files (klog and vlog) are validated in strict mode where any corruption causes the file to be rejected entirely. Since SSTables are immutable and created atomically during flush/compaction, partial writes should never occur. If corruption is detected, the SSTable is considered invalid and recovery fails, preventing silent data loss.

- **Permissive mode (WAL files)** · Write-ahead log files are validated in permissive mode where corruption triggers automatic truncation to the last valid block. Since WAL files are append-only and may contain partial writes from crashes, the system scans forward through all blocks, validates each block's footer magic and size consistency, and truncates the file to remove any incomplete trailing blocks. This ensures crash safety by recovering all complete transactions while discarding partial writes.

This dual-mode approach balances data integrity (strict for immutable data) with crash recovery (permissive for append-only logs), guaranteeing that incomplete or corrupted writes are identified and handled appropriately during recovery.

#### Cursor Operations

The block manager provides cursor-based sequential access for efficient data 
traversal. Cursors support forward iteration via `cursor_next()` and backward 
iteration through `cursor_prev()`, which scans from the beginning to locate 
the previous block. Random access is available through `cursor_goto(pos)`, 
allowing jumps to specific file offsets. Each cursor maintains its current 
position and block size, with boundary checking methods like `at_first()`, 
`at_last()`, `has_next()`, and `has_prev()` to prevent out-of-bounds access.

#### Sync Modes

TidesDB provides three sync modes to balance durability and performance:

**TDB_SYNC_NONE** provides the fastest performance with no explicit fsync, relying entirely on the OS page cache for eventual persistence. This mode offers maximum throughput but provides no durability guarantees—data may be lost on crash.

**TDB_SYNC_INTERVAL** offers balanced performance with periodic background syncing. A single background sync thread monitors all column families configured with interval mode, performing fsync at configurable microsecond intervals (e.g., every 1 second). This bounds potential data loss to the sync interval window while maintaining good write throughput. The background thread sleeps between sync cycles and wakes up to fsync all dirty file descriptors for interval-mode column families.

**TDB_SYNC_FULL** offers maximum durability by performing fsync/fdatasync after every block write operation. This guarantees data persistence at the cost of write performance.

Regardless of the configured sync mode, TidesDB always enforces fsync for structural operations (memtable flush, compaction, WAL rotation) to ensure database consistency. The sync mode is configurable per column family and applies to both WAL and SSTable files.

#### Thread Safety

Block manager operations use a write mutex to serialize all write operations, preventing corruption. Concurrent reads are supported with multiple readers able to read simultaneously using `pread()`. All writes use `pwrite()` for atomic operations.

#### Lock-Free Clock Cache

TidesDB implements an optional lock-free clock cache at the engine level to reduce disk I/O for frequently accessed data blocks. This cache is **global and shared across all column families**, configured via the `block_cache_size` setting in the database configuration. The shared design enables efficient memory utilization and cross-CF cache hits when the same blocks are accessed by different column families.

**Cache Architecture**

The clock cache uses a partitioned design with lock-free atomic operations for concurrent access without mutexes. The cache is divided into multiple partitions (typically 4-128 based on CPU count) to reduce contention, with each partition maintaining its own circular array of slots and a hash index for O(1) lookups. Each cache entry includes the decompressed block data, size, and an atomic reference bit for the CLOCK algorithm's second-chance eviction policy. Cache keys are composite identifiers combining column family name, SSTable filename, and block position, enabling fine-grained caching across the entire database while preventing collisions between different CFs.

**CLOCK Eviction Algorithm**

The CLOCK algorithm provides approximate LRU behavior with better concurrency characteristics. Each entry has a reference bit that is set to 1 when accessed. When eviction is needed, a clock hand sweeps through the circular array: if an entry's reference bit is 1, it's cleared to 0 (second chance); if the bit is already 0, the entry is evicted. This provides similar hit rates to LRU while avoiding the timestamp updates and sorting overhead that would create contention in a highly concurrent environment.

**Cache Operations**

After reading a block from disk and decompressing it, the system attempts to add it to the cache using atomic operations. The cache key is hashed to select a partition, then the partition's hash index is probed using linear probing to find an empty slot or trigger eviction. If cache space is available, the block is inserted with its reference bit set to 1. If the partition is full, the CLOCK eviction policy sweeps through slots to find a victim. All cache operations use atomic CAS to prevent race conditions during concurrent access from multiple column families.

Before reading from disk, the cache is checked using the composite key. On cache hit, the block's reference bit is atomically set to 1 to mark it as recently used, and a copy of the cached block is returned immediately (no disk I/O). On cache miss, the block is read from disk, decompressed, and added to the cache if space permits. The CLOCK policy ensures frequently accessed blocks remain in cache while cold data is automatically evicted, with the global cache naturally prioritizing hot data across all column families.

When a partition reaches capacity, the CLOCK eviction algorithm sweeps through entries with a clock hand, giving each entry a second chance before eviction. The eviction callback atomically decrements the size counter and frees the block's memory. This lock-free design with partitioned structure enables concurrent cache access from multiple threads and column families without contention, maximizing throughput for read-heavy workloads.

**Configuration Example**

```c
tidesdb_config_t config = {
    .db_path = "./mydb",
    .block_cache_size = 1024 * 1024 * 1024,  /* 1GB global cache shared across all CFs */
    .max_open_sstables = 128,
    .num_flush_threads = 2,
    .num_compaction_threads = 2
};
tidesdb_t *db;
tidesdb_open(&db, &config);
```

**Performance Benefits**

- Hot blocks (frequently accessed) stay in memory, eliminating disk reads
- Cache hits provide sub-microsecond access vs milliseconds for disk I/O
- During compaction, recently written blocks are cached, speeding up merge operations
- Sequential scans benefit from cached blocks in the read path

**Cache Sizing Guidelines**

- Small datasets (<100MB) · Set cache to 10-20% of total dataset size across all CFs
- Large datasets (>1GB) · Set cache to 5-10% or based on working set size
- Read-heavy workloads · Larger cache (64-256MB+) provides better hit rates
- Write-heavy workloads · Smaller cache (16-32MB) since data is less frequently re-read
- Multi-CF workloads · Size based on combined working set of all active CFs
- Disable caching · Set `block_cache_size = 0` to disable (no memory overhead)

**Monitoring Cache Effectiveness**

While TidesDB doesn't expose cache hit/miss metrics directly, you can infer effectiveness by monitoring I/O patterns (fewer disk reads indicate good cache performance) and adjusting cache size based on workload (increase if reads are slow, decrease if memory is constrained).


### 4.3 SSTables (Sorted String Tables)

SSTables serve as TidesDB's immutable on-disk storage layer, implementing a key-value separation architecture where keys and values are stored in distinct files. Each SSTable consists of two block manager files: a klog (key log) containing sorted keys with metadata and small inline values, and a vlog (value log) containing large values referenced by offset from the klog. This separation enables efficient key-only operations such as bloom filter construction, block index building, and range scans without loading large values into memory. The immutable nature of SSTables--once written, they are never modified, only merged or deleted--ensures data consistency and enables lock-free concurrent reads.

**File Naming and Level Organization**

SSTable files use two naming conventions depending on the compaction strategy:

- **Non-partitioned format** · `L<level>_<id>.klog` and `L<level>_<id>.vlog` for SSTables created by full preemptive merge or dividing merge. Example: `L1_0.klog` and `L1_0.vlog` represent the first SSTable at level 1.

- **Partitioned format** · `L<level>P<partition>_<id>.klog` and `L<level>P<partition>_<id>.vlog` for SSTables created by partitioned merge. Example: `L3P0_42.klog` represents SSTable ID 42 in partition 0 of level 3.

The level number in filenames is 1-based (L1, L2, L3...) while the internal array indexing is 0-based (levels[0], levels[1], levels[2]...). Level 1 files (L1_*.klog) are stored in `levels[0]`, level 2 files (L2_*.klog or L2P*_*.klog) in `levels[1]`, and so on. The ID is a monotonically increasing counter per column family. During recovery, the system parses both formats using pattern matching: first attempting the partitioned format `L{level}P{partition}_{id}.klog`, then falling back to non-partitioned `L{level}_{id}.klog`. This dual naming scheme enables efficient level-based compaction while supporting partitioned merge strategies that create multiple non-overlapping SSTables per level.

**Reference Counting and Lifecycle**

SSTables use atomic reference counting to manage their lifecycle safely. When an SSTable is accessed (by a read operation, iterator, or compaction), its reference count is incremented via `tidesdb_sstable_ref`. When the operation completes, the reference is released via `tidesdb_sstable_unref`. Only when the reference count reaches zero is the SSTable actually freed from memory and its file handles closed. This prevents use-after-free bugs during concurrent operations like compaction (which may delete SSTables) and reads (which may still be accessing them). The reference counting mechanism integrates with the SSTable cache, ensuring that cached SSTables remain valid while in use.

**SSTable File Handle Management**

The storage engine uses a background reaper thread to manage SSTable file handles and prevent file descriptor exhaustion. The system is configured via `max_open_sstables` (default 100). When an SSTable is accessed, its block managers (klog and vlog) are opened if not already open, and the `last_access_time` is updated atomically. The SSTable metadata structure remains in memory with its reference count tracking active users.

The reaper thread runs continuously in the background, waking every 100ms to check if the number of open SSTables exceeds the configured limit. When the limit is reached, the reaper:

1. Scans all column families to collect SSTable candidates
2. Filters for SSTables with `refcount == 1` (not actively in use) and open file handles
3. Sorts candidates by `last_access_time` (oldest first)
4. Closes 25% of the oldest SSTables by closing their block manager file handles
5. Updates the global `num_open_sstables` counter

This lazy eviction strategy keeps frequently accessed SSTables open while automatically closing cold SSTables when needed. SSTables can be reopened on-demand when accessed again, with the reaper ensuring the system never exceeds the file descriptor limit.

#### SSTable Block Layout

SSTables use the block manager format with key-value separation across two files:

**Klog File (L<level>_<id>.klog) - Keys and Metadata**
```
[File Header - 12 bytes Block Manager Header]
[Block 0: Klog Block with N entries]
[Block 1: Klog Block with M entries]
...
[Block K: Last Klog Block]
[Bloom Filter Block] (optional)
[Index Block] (optional)
[Metadata Block] (always last)
```

**Vlog File (L<level>_<id>.vlog) - Large Values**
```
[File Header - 12 bytes Block Manager Header]
[Block 0: Vlog Block with N values]
[Block 1: Vlog Block with M values]
...
[Block V: Last Vlog Block]
```

**Klog Block Order (from first to last)**
1. Data Blocks: Klog blocks containing multiple key entries in sorted order, with inline values below threshold or vlog offsets for large values
2. Bloom Filter Block (optional): Only written if `enable_bloom_filter = 1`
3. Index Block (optional): Only written if `enable_block_indexes = 1`
4. Metadata Block (required): Always the last block, contains min/max keys, entry count, and file offsets

**Value Threshold and Separation**

Values smaller than or equal to `value_threshold` (default 1KB) are stored inline within klog entries, enabling single-file access for small key-value pairs. Values exceeding the threshold are written to the vlog file, with the klog entry storing only the vlog offset. This separation optimizes for the common case where most values are small while efficiently handling large values without bloating the klog. During recovery, the system reads backwards from the klog end: metadata (last), then index (if present), then bloom filter (if present), establishing the data end offset before loading entries.

#### Klog Block Format

Each klog block contains multiple key entries with a header specifying the count:

```
[Num Entries - 4 bytes (uint32_t)]
[Block Size - 4 bytes (uint32_t)]
[Entry 0: Klog Entry Header + Key + Inline Value (if present)]
[Entry 1: Klog Entry Header + Key + Inline Value (if present)]
...
[Entry N-1: Klog Entry Header + Key + Inline Value (if present)]
```

**Klog Entry Header (33 bytes)**
```c
typedef struct {
    uint8_t flags;          // Entry flags (tombstone, ttl, vlog, delta_seq) - 1 byte
    uint32_t key_size;      // Key size in bytes - 4 bytes
    uint32_t value_size;    // Actual value size in bytes - 4 bytes
    int64_t ttl;            // Unix timestamp for expiration (-1 = no expiration) - 8 bytes
    uint64_t seq;           // Sequence number for ordering and MVCC - 8 bytes
    uint64_t vlog_offset;   // Offset in vlog file (0 if value is inline) - 8 bytes
} tidesdb_klog_entry_t;  // Total: 1+4+4+8+8+8 = 33 bytes
```

**Entry Layout**

Each entry consists of the 33-byte header, followed by the key data, followed by the value data if inline (when `value_size <= value_threshold` and `vlog_offset == 0`). For large values, only the header and key are stored in the klog, with `vlog_offset` pointing to the value's location in the vlog file. This structure enables efficient key-only scans for operations like bloom filter checks and block index construction without loading large values.

**Vlog Block Format**

Vlog blocks contain multiple values referenced by klog entries:

```
[Num Values - 4 bytes (uint32_t)]
[Block Size - 4 bytes (uint32_t)]
[Value 0 Size - 4 bytes (uint32_t)]
[Value 0 Data - variable]
[Value 1 Size - 4 bytes (uint32_t)]
[Value 1 Data - variable]
...
```

**Compression**
- If compression is enabled in column family config, entire klog and vlog blocks are compressed independently
- Compression applied to the complete block (header + all entries) as a unit
- Supports Snappy, LZ4, or ZSTD algorithms (configured via `compression_algorithm`)
- Decompression happens on read before parsing block header and entries
- Default is enabled with LZ4 algorithm for balanced performance

#### Bloom Filter Block

<div class="architecture-diagram">

![Bloom Filter](../../../assets/img7.png)

</div>

Written after all data blocks (if enabled)
- Serialized bloom filter data structure
- Used to quickly determine if a key might exist in the SSTable
- Avoids unnecessary disk I/O for non-existent keys
- False positive rate configurable per column family (default 1%)
- Only written if `enable_bloom_filter = 1` in column family config
- Loaded third-to-last when reading backwards during SSTable recovery

#### Index Block (Compact Block Index)

TidesDB implements a compact block index that stores min/max key prefixes and file positions for fast block lookups in SSTables. The index uses a simple array-based structure optimized for space efficiency and lookup speed.

**Structure**

The block index consists of three parallel arrays:
- **min_key_prefixes** · Array of minimum key prefixes (configurable length, default 16 bytes)
- **max_key_prefixes** · Array of maximum key prefixes (configurable length, default 16 bytes)  
- **file_positions** · Array of uint64_t file offsets for each block
- **count** · Number of blocks indexed
- **prefix_len** · Length of key prefix stored (configurable via `block_index_prefix_len`)

**Sampling Strategy**

During SSTable creation, the index samples blocks at a configurable ratio (default 1:16 via `index_sample_ratio`). For every Nth block, the index stores the minimum and maximum key prefixes along with the block's file position. This sparse indexing reduces memory overhead while maintaining fast lookup performance.

**Serialization Format**

The index is serialized with space-efficient encoding:
```
[Count - 4 bytes (uint32_t)]
[Prefix Length - 1 byte (uint8_t)]
[File Positions - varint encoded with delta compression]
[Min Key Prefixes - count × prefix_len bytes]
[Max Key Prefixes - count × prefix_len bytes]
```

File positions use delta encoding with varint compression: the first position is stored as-is, subsequent positions store the delta from the previous position. This typically achieves 50-70% compression for sequential file positions.

**Lookup Process**

When searching for a key, `compact_block_index_find_predecessor()` performs a binary search through the index arrays:

1. Binary search the min_key_prefixes array using prefix comparison
2. Find the largest indexed block where min_prefix ≤ target_key
3. Return the file position for that block
4. Position cursor at the returned file offset
5. Scan forward through blocks until key is found or exceeded

The prefix comparison uses the configured comparator function, ensuring consistent ordering with the rest of the system. Prefix length is configurable (default 16 bytes) to balance index size vs. search precision.

**Performance Characteristics**

- **Lookup time** · O(log n) binary search + O(sample_ratio) block scans
- **Space overhead** · ~(2 × prefix_len + 8) bytes per sampled block
- **Example** · 1M entries, sample ratio 16, prefix_len 16 → ~2.5MB index
- **Construction** · O(1) memory, single pass during SSTable write

This approach provides excellent lookup performance with minimal memory overhead, avoiding the complexity of trie structures while maintaining fast block access for large SSTables.

#### Metadata Block

Always written as the last block in the file

```
[Magic is 4 bytes (0x5353544D = "SSTM")]
[Num Entries is 8 bytes (uint64_t)]
[Min Key Size is 4 bytes (uint32_t)]
[Min Key is variable]
[Max Key Size is 4 bytes (uint32_t)]
[Max Key is variable]
```

**Purpose**
- Magic number (0x5353544D = "SSTM") identifies this as a valid SSTable metadata block
- Min/max keys enable range-based SSTable filtering during reads
- Num entries tracks total KV pairs in SSTable (used to know when to stop reading data blocks)
- Always loaded first during SSTable recovery using `cursor_goto_last()` to read from end of file

#### SSTable Write Process

1. Create SSTable file and initialize bloom filter and compact block index (if enabled)
2. Iterate through memtable in sorted order using skip list cursor
3. **For each KV pair**
   - Build KV header (33 bytes) + key + value
   - Optionally compress the entire block
   - Write as data block and record the file position
   - Add key to bloom filter (if enabled)
   - If sampled (block_num % index_sample_ratio == 0): add min/max key prefixes and file position to block index
   - Track min/max keys for metadata
4. Serialize and write bloom filter block (if enabled)
5. Serialize and write compact block index block (if enabled) with varint-compressed file positions
6. Build and write metadata block with magic number, entry count, and min/max keys

#### SSTable Read Process

1. **Load SSTable** (recovery or first access)
   - SSTable structure already exists in memory (loaded during recovery or compaction)
   - If block managers are closed: open klog and vlog block manager files on-demand
   - Update `last_access_time` atomically for reaper tracking
   - Increment reference count via `tidesdb_sstable_ref`
   - Metadata, bloom filter, and block index are already loaded in memory from recovery
   - Block managers remain open for subsequent accesses until reaper closes them

2. **Lookup Key**
   - Increment SSTable reference count via `tidesdb_sstable_ref`
   - Ensure klog and vlog block managers are open (open on-demand if closed)
   - Update `last_access_time` atomically
   - Check if key is within min/max range using configured comparator (quick rejection)
   - Check bloom filter if enabled (probabilistic rejection)
   - If block indexes enabled: query compact block index for file position
     - Binary search min_key_prefixes to find predecessor block
     - Position cursor directly at the returned file offset
     - Read klog block at that position
   - If block indexes disabled: linear scan through klog data blocks from beginning
   - Decompress klog block if compression is enabled
   - Parse klog block header (num_entries, block_size)
   - Iterate through entries in the block:
     - Parse klog entry header (33 bytes): flags, key_size, value_size, ttl, seq, vlog_offset
     - Compare entry key with search key using comparator
     - If match found:
       - Check TTL expiration (return NOT_FOUND if expired)
       - Check tombstone flag (return NOT_FOUND if deleted)
       - If vlog_offset == 0: value is inline in klog, return it
       - If vlog_offset > 0: read value from vlog file at offset, decompress if needed, return it
   - Release SSTable reference (decrement reference count)
   - Return value or TDB_ERR_NOT_FOUND if not present

SSTable structures remain in memory throughout the database lifetime. Block managers are kept open for frequently accessed SSTables and closed by the reaper thread when the `max_open_sstables` limit is reached, prioritizing eviction of the least recently accessed files.

### 4.4 Write-Ahead Log (WAL)
For durability, TidesDB implements a write-ahead logging mechanism with a rotating WAL system tied to memtable lifecycle.

#### 4.4.1 WAL File Naming and Lifecycle
<div class="architecture-diagram">

   ![WAL/Memtable Lifecycle](../../../assets/img9.png)
   
</div>

File Format: `wal_<memtable_id>.log`

WAL files follow the naming pattern `wal_0.log`, `wal_1.log`, `wal_2.log`, etc. Each memtable has its own dedicated WAL file, with the WAL ID matching the memtable ID (a monotonically increasing counter). Multiple WAL files can exist simultaneously - one for the active memtable and others for memtables in the flush queue. WAL files are deleted only after the memtable is successfully flushed to an SSTable and freed.

#### 4.4.2 WAL Rotation Process

TidesDB uses a rotating WAL system that works as follows:

Initially, the active memtable (ID 0) uses `wal_0.log`. When the memtable size reaches `write_buffer_size`, rotation is triggered. During rotation, a new active memtable (ID 1) is created with `wal_1.log`, while the immutable memtable (ID 0) with `wal_0.log` is added to the immutable memtable queue. A flush task is submitted to the flush thread pool. The background flush thread writes memtable (ID 0) to `L1_0.klog` and `L1_0.vlog` while `wal_0.log` still exists. Once the flush completes successfully, the memtable is dequeued from the immutable queue, its reference count drops to zero, and both the memtable and `wal_0.log` are freed/deleted. Multiple memtables can be in the flush queue concurrently, each with its own WAL file and reference count.

#### 4.4.3 WAL Features and Sequence Numbers

All writes (including deletes/tombstones) are first recorded in the WAL before being applied to the memtable. Each column family maintains its own independent WAL files, and automatic recovery on startup reconstructs memtables from WALs. WAL entries are stored **uncompressed** for fast writes and recovery.

**Sequence Numbers for Ordering**

Each WAL entry is assigned a monotonically increasing sequence number via `atomic_fetch_add(&cf->next_wal_seq, 1)`. This provides lock-free ordering guarantees:

- Multiple transactions can commit concurrently without locks
- Each operation gets a unique sequence number atomically
- Sequence numbers ensure deterministic ordering even with concurrent writes
- During WAL recovery, entries are sorted by sequence number before replay
- This guarantees last-write-wins consistency is preserved across crashes

The sequence number is stored in the 33-byte klog entry header (8 bytes at offset 17, after flags+key_size+value_size+ttl) and used during recovery to replay operations in the correct order, ensuring the memtable state matches the commit order regardless of how WAL entries were physically written to disk.

#### 4.4.4 Recovery Process

On startup, TidesDB automatically recovers from WAL files:

The system scans the column family directory for `wal_*.log` files and sorts them by ID (oldest to newest). It then replays each WAL file into a new memtable, reconstructing the in-memory state from persisted WAL entries before continuing normal operation with the recovered data.

**What Gets Recovered**

All committed transactions that were written to WAL are recovered. During recovery:

1. WAL entries are read from disk in physical order
2. Each entry is inserted into the skip list memtable using `skip_list_put_with_seq()` with its sequence number
3. The skip list maintains version chains for each key, with all versions sorted by sequence number
4. When multiple versions of the same key exist, the skip list returns the version with the highest sequence number
5. This ensures last-write-wins consistency is preserved

Uncommitted transactions are never written to the WAL and therefore are not recovered. The skip list's version chain mechanism ensures that even if concurrent writes caused WAL entries to be physically written out of order, the correct logical ordering is maintained through sequence numbers. During reads, the skip list automatically returns the newest version (highest sequence number) for each key.

**SSTable Recovery via Manifest**

SSTables are discovered by loading the MANIFEST file from each column family directory. The MANIFEST contains a list of all active SSTables with their level, ID, entry count, and size. This provides several benefits:

1. **Deterministic recovery** - SSTables are loaded in the exact order they were written, not filesystem-dependent order
2. **Faster startup** - No need to scan directories or parse filenames to discover SSTables
3. **Consistency** - Only SSTables that were successfully flushed/compacted are listed in the MANIFEST
4. **Orphan detection** - SSTable files not in the MANIFEST can be safely deleted (incomplete writes)

During recovery, each SSTable entry from the MANIFEST is loaded into the appropriate level array. The MANIFEST also tracks the next SSTable ID sequence, ensuring new SSTables continue with monotonically increasing IDs after restart.

### 4.5 Sequence Number Limits

TidesDB uses 64-bit unsigned integers (`uint64_t`) for all sequence numbers, including transaction sequence numbers (`global_seq`), SSTable IDs (`next_sstable_id`), and manifest sequence tracking. These sequence numbers are monotonically increasing and **never reset** during normal database operation.

**Practical Limits**

The maximum value for a 64-bit unsigned integer is 18,446,744,073,709,551,615 (2^64 - 1). At various operation rates:

- 1,000 operations/second · 584 million years to overflow
- 10,000 operations/second · 58 million years to overflow  
- 1 million operations/second · 584,942 years to overflow
- 1 billion operations/second · 584 years to overflow

For any realistic workload, sequence number overflow is not a practical concern. The database would accumulate petabytes of data and run for geological timescales before approaching the limit.

**Design Rationale**

This approach follows industry best practices used by modern databases like RocksDB, LevelDB, MySQL/InnoDB, and modern PostgreSQL. Using 64-bit sequence numbers eliminates the wraparound problems that plagued earlier systems with 32-bit counters, which required complex vacuum operations and could cause production outages.

TidesDB does not implement wraparound protection or sequence number reset mechanisms. The 64-bit space is sufficiently large that such complexity is unnecessary and would only add overhead without practical benefit.

## 5. Data Operations

### 5.1 Write Path
When a key-value pair is written to TidesDB (via `tidesdb_txn_commit()`):

1. **Acquire active memtable** · Lock-free CAS retry loop to safely acquire a reference to the current active memtable
2. **Assign sequence number** · Atomically increment the WAL sequence counter via `atomic_fetch_add()`
3. **Write to WAL** · Record the operation in the active memtable's WAL using lock-free block manager write
4. **Write to skip list** · Insert the key-value pair into the skip list using lock-free atomic CAS operations
5. **Check flush threshold** · If memtable size exceeds `write_buffer_size`, attempt to set `is_flushing` flag via atomic CAS
6. **Trigger rotation** (if CAS succeeds and size still exceeds threshold):
   - Create a new active memtable with a new WAL file
   - Atomically swap the active memtable pointer
   - Add the immutable memtable to the flush queue
   - Submit flush task to the flush thread pool
   - Clear `is_flushing` flag
7. **Background flush** · Flush thread writes immutable memtable to klog and vlog files (L<level>_<id>.klog and L<level>_<id>.vlog), then deletes WAL and frees memtable
8. **Concurrent writes** · Multiple transactions can write concurrently without blocking (lock-free)


### 5.2 Read Path

When reading a key from TidesDB:

1. Check active memtable for the key
2. Check immutable memtables in the flush queue (newest to oldest)
3. Check SSTables in reverse chronological order (newest to oldest)
   - For each SSTable, perform the lookup process described in Section 4.3 (min/max range check, bloom filter, block index or linear scan, decompression, TTL/tombstone validation)
4. Return the value when found, or `TDB_ERR_NOT_FOUND` if not present in any source

This multi-tier search ensures the most recent version of a key is always retrieved, with newer sources taking precedence over older ones.

### 5.3 Transactions

TidesDB provides transaction support with multi-column-family capabilities and configurable isolation levels. Transactions are initiated through `tidesdb_txn_begin()` or `tidesdb_txn_begin_with_isolation()`, with a single transaction capable of operating across multiple column families atomically. The system implements MVCC (Multi-Version Concurrency Control) with five isolation levels: READ UNCOMMITTED, READ COMMITTED, REPEATABLE READ, SNAPSHOT ISOLATION, and SERIALIZABLE (see Section 8.3 for detailed semantics). Iterators acquire atomic references on both memtables and SSTables, creating consistent point-in-time snapshots unaffected by concurrent compaction or writes.

**Global Sequence Numbering**

All transactions use a single global sequence counter (`db->global_seq`) regardless of whether they touch one or multiple column families. This unified sequencing simplifies the implementation and ensures total ordering of all transactions across the database. The sequence number is assigned during commit via `atomic_fetch_add(&db->global_seq, 1)` after conflict detection passes, ensuring no sequence numbers are wasted on aborted transactions.

**Multi-CF Transaction Metadata**

For transactions spanning multiple column families (`txn->num_cfs > 1`), each participating CF's WAL includes metadata written before the transaction's operations:

```
[num_participant_cfs - 1 byte]
[checksum - 8 bytes (XXH64)]
[CF names - num_cfs × TDB_MAX_CF_NAME_LEN bytes]
[... transaction operations ...]
```

The metadata header contains:
1. **Number of participant CFs** - Count of column families in the transaction
2. **Checksum** - XXH64 hash of (num_cfs + all CF names) for integrity validation
3. **CF names** - Null-terminated names of all participating CFs

During recovery, the system scans all WALs to build a transaction tracker, then validates that each multi-CF transaction appears in all expected column families before applying it. This ensures that incomplete transactions (where some CFs committed but others crashed before writing) are discarded, maintaining true atomicity without requiring two-phase commit or coordinator locks.

**Lock-Free Write Path**

Write transactions use a completely lock-free commit path with atomic operations:

1. Transaction operations are buffered in memory during `tidesdb_txn_put()` and `tidesdb_txn_delete()`
2. On `tidesdb_txn_commit()`, conflict detection runs based on isolation level
3. After passing conflict detection, a global sequence is assigned via `atomic_fetch_add(&db->global_seq, 1)`
4. The sequence is marked as "in-progress" in the commit status tracker
5. For each participating CF:
   - If multi-CF (`num_cfs > 1`): Write metadata header (num_cfs, checksum, CF names) to WAL
   - Write all operations for that CF to its WAL using lock-free group commit
   - Insert operations into the CF's active memtable using lock-free skip list CAS
6. Mark the sequence as "committed" in the commit status tracker (makes transaction visible)
7. No locks are held during commit - multiple transactions can commit concurrently

**Atomicity Guarantees**

Single-CF transactions are atomic by virtue of WAL durability and the commit status tracker - either the entire transaction is written to the WAL and marked committed, or it's discarded during recovery. Multi-CF transactions achieve atomicity through metadata-based validation during recovery:

1. **During commit** · Each participating CF's WAL receives the complete metadata header listing all participant CFs
2. **During recovery** · The system scans all WALs and builds a transaction tracker mapping sequence numbers to CF names
3. **Validation** · For each multi-CF transaction (identified by metadata header), the system verifies all expected CFs have that sequence
4. **Application** · Only complete transactions (present in all expected CFs) are applied to memtables
5. **Discard** · Incomplete transactions (missing from one or more CFs due to crash) are discarded from all CFs

This provides true all-or-nothing semantics without distributed coordination overhead. If a crash occurs after some CFs have written but before others complete, the incomplete transaction is detected during recovery and discarded from all CFs, maintaining atomicity across column families.

**Isolation Guarantees**

Read transactions don't block writers and writers don't block readers. Transactions support read-your-own-writes semantics, allowing uncommitted changes to be read before commit. Multi-CF transactions maintain consistent snapshots across all participating column families, with each CF's snapshot captured at transaction begin time. The API uses simple integer return codes (0 for success, negative for errors) rather than complex error structures.

**Savepoints**

TidesDB supports savepoints for partial rollback within transactions. Savepoints capture the transaction state at a specific point, allowing operations after the savepoint to be discarded without aborting the entire transaction. This enables complex multi-step operations with conditional rollback logic.

Implementation · Savepoints are created via `tidesdb_txn_savepoint(txn, name)` and store a deep copy of the transaction's operation buffer at that point. Each savepoint maintains:

1. **Operation snapshot** · Deep copies of all transaction operations (`txn->ops`) including keys and values up to the savepoint
2. **Column family references** · Pointers to the same CF array as the parent transaction
3. **Transaction metadata** · Copies of `txn_id`, `snapshot_seq`, and `commit_seq`
4. **Named storage** · Savepoints stored in `txn->savepoints[]` with names in `txn->savepoint_names[]`

When `tidesdb_txn_rollback_to_savepoint(txn, name)` is called, the system:

1. Locates the savepoint by name in the transaction's savepoint array
2. Frees all operations added after the savepoint (keys and values from index `savepoint->num_ops` to `txn->num_ops`)
3. Resets `txn->num_ops` to the savepoint's operation count
4. Frees the savepoint itself and its name
5. Shifts remaining savepoints down in the array (removes this savepoint and all created after it)

Savepoints can be updated by creating a new savepoint with the same name, which replaces the previous savepoint. Multiple savepoints can exist simultaneously, enabling nested rollback points. All savepoints are automatically freed when the transaction commits or rolls back. This mechanism is particularly useful for implementing complex business logic with conditional error handling, such as batch operations where individual failures should not abort the entire batch.

## 6. Compaction Policies

TidesDB implements the **Spooky algorithm** (Dayan et al., 2018), a generalized LSM-tree compaction strategy that balances write amplification, read amplification, and space amplification through adaptive merge operations. The system employs three distinct merge techniques--full preemptive merge, dividing merge, and partitioned merge--selected dynamically based on a configurable dividing level X. This approach provides tunable performance characteristics by adjusting the dividing level offset, enabling optimization for read-heavy, write-heavy, or balanced workloads without changing the core algorithm.

### 6.1 Multi-Level Architecture and Capacity Management

The compaction system organizes SSTables into a hierarchy of levels numbered from 0 to N-1, where each level maintains a capacity constraint that grows exponentially with level number. Level 0 serves as the landing zone for newly flushed memtables and contains SSTables in arbitrary chronological order without key range constraints. Subsequent levels (1 through N-1) maintain sorted, non-overlapping key ranges within each level, enabling efficient binary search during read operations. Level capacity is calculated as `base_capacity * (size_ratio ^ level_number)`, where `base_capacity` defaults to the memtable flush threshold and `size_ratio` (typically 10) determines the exponential growth rate. This geometric progression ensures that each level can accommodate all data from previous levels while maintaining bounded space amplification.

When Level 0 reaches capacity, the system dynamically creates Level 1 if it doesn't exist, triggering the first compaction operation. As data ages through the hierarchy, levels are added on-demand when lower levels reach capacity, with the maximum number of levels determined by total dataset size and configured capacity parameters. The system tracks both current size (sum of all SSTable sizes in bytes) and capacity (maximum allowed size) for each level, using these metrics to make compaction decisions. A level is considered full when `current_size >= capacity`, triggering merge operations that consolidate data into higher levels while removing obsolete versions, tombstones, and expired TTL entries.

### 6.2 Dividing Level and Merge Strategy Selection

Compaction decisions are governed by a dividing level X, calculated as `X = num_levels - 1 - dividing_level_offset`, where `dividing_level_offset` (default 1, configurable per column family) controls the aggressiveness of compaction. For example, with 5 levels and offset=1, X = 5 - 1 - 1 = 3. The dividing level partitions the storage hierarchy into two regions: levels 0 through X-1 contain recently written data subject to frequent merges, while levels X+1 through N-1 contain stable historical data that undergoes less frequent consolidation. This partitioning strategy balances write amplification (cost of rewriting data during compaction) against read amplification (number of levels to search during queries) by concentrating merge activity in the upper levels where data turnover is highest.

The system implements **Spooky Algorithm 2** to select merge strategies. Before compaction begins, the active memtable is flushed to ensure all data is in SSTables. The algorithm then finds the smallest level q (1 ≤ q ≤ X) where `capacity_q < cumulative_size(0...q)`, meaning level q cannot accommodate the merge of all data from levels 0 through q. This becomes the target level:

- If `target < X`: Perform **full preemptive merge** of levels 0 to target
- If `target == X`: Perform **dividing merge** into level X
- If no suitable level found: Default to dividing merge at X

After the primary merge, if level X is full (`size_X >= capacity_X`), the algorithm applies the same logic to find the smallest level z (X+1 ≤ z ≤ num_levels) where `capacity_z < cumulative_size(X...z)`, then performs a **partitioned merge** from X to z. This two-phase approach ensures data flows efficiently through the hierarchy.

### 6.3 Full Preemptive Merge

Full preemptive merge consolidates all data from levels 0 through q into level q, where q < X. This operation is selected when an upper level has sufficient capacity to absorb all data from levels above it, enabling aggressive consolidation that reduces the number of levels requiring search during read operations. The merge process creates a multi-way merge iterator that simultaneously scans all SSTables in the source levels, producing a sorted stream of key-value pairs with duplicates resolved by selecting the newest version based on sequence numbers. Tombstones and expired TTL entries are purged during the merge, reclaiming storage space and improving read performance by eliminating obsolete data from the storage hierarchy.

The output of a full preemptive merge consists of one or more new SSTables written to the target level q, with each output SSTable sized to match the configured SSTable size target. Source SSTables from levels 0 through q are deleted atomically after the merge completes successfully, using temporary file naming and atomic rename operations to ensure crash safety. This merge strategy provides optimal read performance by minimizing the number of levels containing data, at the cost of higher write amplification since data is rewritten multiple times as it moves through the hierarchy. The strategy is most effective for workloads with high update rates and frequent key overwrites, where aggressive consolidation quickly eliminates obsolete versions.

### 6.4 Dividing Merge

Dividing merge operates at level X, consolidating all data from levels 0 through X into level X. This operation is selected when no upper level has sufficient capacity for a full preemptive merge, indicating that data must be pushed deeper into the hierarchy. The merge algorithm follows the same multi-way merge pattern as full preemptive merge, creating sorted output SSTables while purging tombstones and expired entries. However, dividing merge plays a critical role in the overall compaction strategy by serving as the primary mechanism for moving data from the frequently-modified upper levels into the stable lower levels.

After a dividing merge completes, the system recalculates level statistics and evaluates whether additional levels must be created to accommodate the merged data. If level X reaches capacity after the merge, a new level X+1 is created with capacity calculated as `capacity_X * size_ratio`, providing space for future compactions. This dynamic level creation ensures that the storage hierarchy grows organically with dataset size, maintaining bounded space amplification while avoiding premature level creation that would waste memory and increase read amplification. The dividing merge strategy balances write amplification and read amplification by concentrating merge activity at a single level rather than rewriting data through every level in the hierarchy.

### 6.5 Partitioned Merge

Partitioned merge operates on levels X+1 through N-1, consolidating data within individual levels to maintain key range organization and capacity constraints in the lower hierarchy. This operation is triggered when a level below the dividing level exceeds its capacity, indicating that data must be reorganized to maintain the sorted, non-overlapping key range invariant. Unlike full preemptive and dividing merges which consolidate multiple levels, partitioned merge operates within a single level, selecting overlapping SSTables and merging them into new SSTables with optimized key range boundaries.

The partitioned merge algorithm identifies a subset of SSTables within the target level whose key ranges overlap. It creates a merge iterator over this subset while leaving non-overlapping SSTables untouched. This selective approach minimizes write amplification by rewriting only the data that requires reorganization, rather than rewriting the entire level. The merge produces multiple output SSTables (one per partition), each identified by a partition number in the filename. For example, a partitioned merge at level 3 creating three partitions might produce `L3P0_10.klog`, `L3P1_11.klog`, and `L3P2_12.klog` with their corresponding vlog files, where P0, P1, P2 indicate partition numbers and 10, 11, 12 are sequential IDs from the monotonic counter. Each output SSTable maintains non-overlapping key ranges within the level, enabling efficient binary search during read operations. The merge purges tombstones and expired TTL entries, reclaiming storage space while maintaining the sorted key range invariant required for efficient range queries and point lookups in the lower levels of the storage hierarchy.

### 6.6 Background Compaction and Thread Pool Coordination

Compaction operations execute asynchronously through the engine-level compaction thread pool, decoupling merge activity from application write operations and enabling sustained write throughput independent of compaction performance. The system automatically triggers compaction using **Spooky's α (alpha) parameter** when Level 0 reaches the file count threshold (`TDB_L0_FILE_NUM_COMPACTION_TRIGGER`, default 4 SSTables) or when Level 0 exceeds its capacity by size. This dual-trigger mechanism prevents L0 explosion with small write buffers while maintaining predictable compaction behavior. After each memtable flush, the system checks L0's SSTable count and size, submitting a compaction task to the thread pool if either threshold is exceeded. Background compaction threads execute a blocking dequeue pattern, waiting efficiently on the compaction queue until work arrives, then processing compaction tasks to completion before returning to the wait state.

Each compaction task is protected by a per-column-family atomic flag (`is_compacting`) that serializes merge operations within a single column family while allowing concurrent compaction across different column families. The flag is checked using atomic compare-and-swap, enabling the system to skip redundant compaction attempts when a merge is already in progress. This non-blocking approach prevents queue buildup and resource exhaustion during periods of high write activity, while ensuring that compaction makes forward progress whenever resources are available. The file count trigger (α = 4) is a system-wide constant derived from the Spooky paper, balancing read amplification (number of L0 files to search) against write amplification (frequency of compaction).

### 6.7 Dynamic Capacity Adaptation (DCA)

After each compaction operation completes, TidesDB automatically applies Dynamic Capacity Adaptation (DCA) to recalibrate level capacities based on the actual data distribution in the storage hierarchy. This adaptive mechanism ensures that level capacities remain proportional to the actual dataset size, preventing capacity imbalances that could trigger unnecessary compactions or allow levels to grow beyond their intended bounds.

#### The Capacity Recalibration Formula

DCA updates the capacity of each level (except the largest) using the formula:

```
C_i = N_L / T^(L-i)
```

Where
- `C_i` = new capacity for level i
- `N_L` = current data size at the largest level L
- `T` = level size ratio (default 10)
- `L` = total number of levels
- `i` = level number (0 to L-2)

This formula ensures that level capacities maintain the geometric progression `C_0 : C_1 : C_2 : ... = 1 : T : T² : ...` while anchoring to the actual size of the largest level rather than theoretical maximums.

#### Why DCA Matters

**Problem Without DCA**

In a static capacity system, if the largest level contains 100GB of data but its capacity is set to 1TB, all upper level capacities would be calculated from that 1TB ceiling. This creates two issues:
1. Upper levels have unnecessarily large capacities, delaying compaction triggers
2. More levels than necessary exist in the hierarchy, increasing read amplification

**Solution With DCA**

By recalibrating capacities based on `N_L` (actual size) rather than `C_L` (theoretical capacity), DCA ensures that:
- Level capacities reflect real data distribution
- Compaction triggers fire at appropriate thresholds
- The hierarchy maintains optimal depth for the current dataset size
- Space amplification remains bounded even as data grows or shrinks

#### Execution Timing

DCA is invoked at the end of every compaction operation via `tidesdb_apply_dca()`, after all merge operations complete but before releasing the `is_compacting` flag. This timing ensures that:
- Capacity updates reflect the post-compaction state
- No concurrent compactions can observe inconsistent capacities
- The next compaction decision uses accurate capacity information

#### Adaptive Behavior Example

Consider a 4-level hierarchy with `T=10` and `N_L=100GB`:

**Before DCA (static capacities)**
- L0: 10GB capacity
- L1: 100GB capacity  
- L2: 1TB capacity
- L3: 10TB capacity (but only 100GB actual data)

**After DCA (adaptive capacities)**
- L0: 100MB capacity (100GB / 10³)
- L1: 1GB capacity (100GB / 10²)
- L2: 10GB capacity (100GB / 10¹)
- L3: 100GB capacity (unchanged, largest level)

The adapted capacities are 100x smaller, triggering compactions more aggressively in upper levels and preventing unnecessary level creation. As the dataset grows and `N_L` increases, DCA automatically scales all capacities proportionally.

#### Multi-Cycle Evolution Example

To illustrate how DCA adapts over time, consider a realistic workload where data grows through multiple compaction cycles. Starting with `T=10` (size ratio) and `write_buffer_size=64MB`:

**Initial State (After First Flush)**
```
L0: size=64MB,   capacity=64MB   (just flushed from memtable)
L1: (doesn't exist yet)
```

**Cycle 1 · L0 Fills, Creates L1**

After 10 more flushes, L0 reaches capacity:
```
Before Compaction:
L0: size=640MB,  capacity=640MB  (10 SSTables)
L1: (created)    capacity=640MB  (T × L0 capacity)

Compaction: Full preemptive merge L0 → L1

After Compaction:
L0: size=0MB,    capacity=64MB   (reset)
L1: size=640MB,  capacity=640MB  (merged data)

DCA Applied:
N_L = 640MB (largest level size)
C_0 = 640MB / 10¹ = 64MB   ✓ (matches write_buffer_size)
C_1 = 640MB / 10⁰ = 640MB  ✓ (unchanged, largest level)
```

**Cycle 2 · L0 and L1 Fill, Creates L2**

After 100 more flushes (10 compactions of L0 → L1):
```
Before Compaction:
L0: size=640MB,  capacity=64MB   (needs compaction)
L1: size=6.4GB,  capacity=640MB  (exceeded capacity!)
L2: (created)    capacity=6.4GB  (T × L1 capacity)

Compaction: Full preemptive merge L0+L1 → L2

After Compaction:
L0: size=0MB,    capacity=64MB
L1: size=0MB,    capacity=640MB
L2: size=6.4GB,  capacity=6.4GB

DCA Applied:
N_L = 6.4GB (largest level size)
C_0 = 6.4GB / 10² = 64MB    ✓ (stable)
C_1 = 6.4GB / 10¹ = 640MB   ✓ (stable)
C_2 = 6.4GB / 10⁰ = 6.4GB   ✓ (unchanged, largest level)
```

**Cycle 3 · Dataset Grows to 64GB**

After 1,000 total flushes:
```
Before Compaction:
L0: size=640MB,  capacity=64MB
L1: size=6.4GB,  capacity=640MB
L2: size=64GB,   capacity=6.4GB  (exceeded!)
L3: (created)    capacity=64GB

Compaction: Partitioned merge L2 → L3

After Compaction:
L0: size=640MB,  capacity=64MB
L1: size=6.4GB,  capacity=640MB
L2: size=0GB,    capacity=6.4GB
L3: size=64GB,   capacity=64GB

DCA Applied:
N_L = 64GB (largest level size)
C_0 = 64GB / 10³ = 64MB     ✓ (stable)
C_1 = 64GB / 10² = 640MB    ✓ (stable)
C_2 = 64GB / 10¹ = 6.4GB    ✓ (stable)
C_3 = 64GB / 10⁰ = 64GB     ✓ (unchanged, largest level)
```

**Cycle 4 · Dataset Grows to 200GB (Asymmetric Growth)**

After continued writes, L3 grows but not to full 640GB capacity:
```
Before Compaction:
L0: size=640MB,  capacity=64MB
L1: size=6.4GB,  capacity=640MB
L2: size=32GB,   capacity=6.4GB  (exceeded)
L3: size=200GB,  capacity=64GB   (exceeded)
L4: (created)    capacity=640GB

Compaction: Partitioned merge L2+L3 → L4

After Compaction:
L0: size=640MB,  capacity=64MB
L1: size=6.4GB,  capacity=640MB
L2: size=0GB,    capacity=6.4GB
L3: size=0GB,    capacity=64GB
L4: size=200GB,  capacity=640GB

DCA Applied (Key Adaptation!):
N_L = 200GB (actual largest level size, not capacity)
C_0 = 200GB / 10⁴ = 20MB    ← Decreased from 64MB!
C_1 = 200GB / 10³ = 200MB   ← Decreased from 640MB!
C_2 = 200GB / 10² = 2GB     ← Decreased from 6.4GB!
C_3 = 200GB / 10¹ = 20GB    ← Decreased from 64GB!
C_4 = 200GB / 10⁰ = 200GB   ✓ (unchanged, largest level)
```

**Key Insight from Cycle 4**

DCA adapted all capacities **downward** because the largest level only contains 200GB, not the theoretical 640GB capacity. This prevents:
- X  Upper levels having unnecessarily large capacities
- X  Delayed compaction triggers
- X  Excessive read amplification (too many levels)
- X  Wasted space in the hierarchy

Instead, capacities now reflect **actual data distribution**, ensuring optimal compaction behavior.

**Cycle 5 · Dataset Continues Growing to 500GB**

After more writes
```
Before Compaction:
L0: size=200MB,  capacity=20MB   (needs compaction)
L1: size=2GB,    capacity=200MB  (needs compaction)
L2: size=20GB,   capacity=2GB    (needs compaction)
L3: size=100GB,  capacity=20GB   (needs compaction)
L4: size=500GB,  capacity=200GB  (exceeded)
L5: (created)    capacity=2TB

Compaction: Multiple merges cascade through levels

After Compaction:
L0: size=0MB,    capacity=20MB
L1: size=0MB,    capacity=200MB
L2: size=0MB,    capacity=2GB
L3: size=0MB,    capacity=20GB
L4: size=0GB,    capacity=200GB
L5: size=500GB,  capacity=2TB

DCA Applied (Scales Up!):
N_L = 500GB (largest level grew)
C_0 = 500GB / 10⁵ = 50MB    ← Increased from 20MB
C_1 = 500GB / 10⁴ = 500MB   ← Increased from 200MB
C_2 = 500GB / 10³ = 5GB     ← Increased from 2GB
C_3 = 500GB / 10² = 50GB    ← Increased from 20GB
C_4 = 500GB / 10¹ = 500GB   ← Increased from 200GB
C_5 = 500GB / 10⁰ = 500GB   ✓ (unchanged, largest level)
```

**Summary of DCA Evolution**

| Cycle | N_L (Largest) | C_0 | C_1 | C_2 | C_3 | C_4 | C_5 | Behavior |
|-------|---------------|-----|-----|-----|-----|-----|-----|----------|
| 1 | 640MB | 64MB | 640MB | - | - | - | - | Initial |
| 2 | 6.4GB | 64MB | 640MB | 6.4GB | - | - | - | Stable growth |
| 3 | 64GB | 64MB | 640MB | 6.4GB | 64GB | - | - | Stable growth |
| 4 | 200GB | 20MB ↓ | 200MB ↓ | 2GB ↓ | 20GB ↓ | 200GB | - | **Adapted down** |
| 5 | 500GB | 50MB ↑ | 500MB ↑ | 5GB ↑ | 50GB ↑ | 500GB ↑ | 500GB | **Adapted up** |

**What This Shows**

1. **Automatic Scaling** · Capacities adjust both up and down based on actual data size
2. **Proportional Relationships** · The `1:10:100:1000` ratio is maintained across all cycles
3. **No Manual Tuning** · Works correctly from 640MB to 500GB+ without configuration changes
4. **Prevents Imbalance** · Cycle 4 shows DCA correcting for asymmetric growth
5. **Optimal Compaction** · Each level triggers compaction at the right threshold

This dynamic adaptation is why TidesDB maintains consistent performance across workloads with varying dataset sizes, from gigabytes to terabytes, without requiring manual capacity tuning that would be necessary in static LSM implementations.

#### Stability Guarantees

DCA includes safeguards to prevent capacity thrashing:
- If the calculated new capacity is zero but the old capacity was non-zero, the old capacity is retained
- The largest level's capacity is never modified by DCA
- Capacity updates are atomic (protected by `levels_lock` write lock)
- DCA only runs when `num_levels >= 2` (no adaptation needed for single-level systems)

This adaptive approach allows TidesDB to maintain optimal compaction behavior across workloads with varying dataset sizes, from gigabytes to terabytes, without manual capacity tuning or configuration changes.

### 6.8 Compaction Mechanics Summary

During compaction, SSTables are merged using the Spooky algorithm strategies (full preemptive, dividing, or partitioned merge). For each key, only the newest version is retained based on sequence numbers, while tombstones (deletion markers) and expired TTL entries are purged. Original SSTables are marked for deletion and removed after their reference count reaches zero, ensuring active reads complete safely. The system automatically adds new levels when the largest level exceeds capacity, and removes empty levels when no pending work exists (no flushes in progress and L0 is empty). After each compaction, Dynamic Capacity Adaptation recalibrates level capacities to maintain optimal hierarchy proportions based on actual data distribution in the largest level.

## 7. Performance Optimizations
### 7.1 Block Indices

TidesDB employs a space-efficient sparse indexing architecture to achieve fast random access to blocks in SSTables.

#### Compact Block Index (Layer 1 · Sparse Index)

Each SSTable optionally contains a compact block index stored as the second-to-last block in the klog file. The index uses a simple array-based structure with min/max key prefixes for fast binary search:

**Structure**
- **min_key_prefixes** · Array of minimum key prefixes (default 16 bytes each)
- **max_key_prefixes** · Array of maximum key prefixes (default 16 bytes each)
- **file_positions** · Array of uint64_t file offsets
- **count** · Number of sampled blocks
- **prefix_len** · Configurable prefix length (default 16 bytes)

**Space Efficiency**
- Approximately (2 × prefix_len + 8) bytes per sampled block
- 1 million entries, sample ratio 16, prefix_len 16 → ~2.5MB index size
- Compare to full block index: 32 bytes per block → ~32MB for 1M blocks
- **~13x smaller** with sampling while maintaining fast lookups

**Construction**
During SSTable creation, blocks are sampled at a configurable ratio (default 1:16 via `index_sample_ratio`). For each sampled block, the index stores the minimum and maximum key prefixes along with the block's file position. Construction is O(1) memory with a single pass during SSTable write.

**Lookup Process**
When searching for a key, `compact_block_index_find_predecessor()` performs a binary search through the min_key_prefixes array using prefix comparison. It returns the file position of the largest indexed block where min_prefix ≤ target_key. The cursor is then positioned directly at that file offset, avoiding sequential scanning through earlier blocks.

#### Lookup Workflow

The complete lookup process for a key in an SSTable:

1. **Min/Max Range Check**
   - Compare key against SSTable's min_key and max_key
   - Skip SSTable if key is outside range

2. **Bloom Filter Check** (if enabled)
   - Probabilistic test for key existence
   - Skip SSTable if bloom filter returns negative

3. **Block Index Lookup** (if enabled)
   - Binary search min_key_prefixes array (O(log n))
   - Find predecessor block where min_prefix ≤ target_key
   - Returns file position (e.g., offset 52,428,800)
   - ~2.5MB index for 1M entries (sample ratio 16)

4. **Direct Seek**
   - Position cursor at file offset from block index
   - Or scan sequentially from beginning if no block index

5. **Block Read and Scan**
   - Read block at cursor position (one disk I/O)
   - Decompress if compression enabled
   - Scan entries in block for exact key match
   - Return value or continue to next block

**Performance Characteristics**
- With block index: O(log n) binary search + O(sample_ratio) block scans
- Without block index: O(num_blocks) linear scan
- Bloom filter eliminates ~99% of unnecessary lookups for non-existent keys

#### Graceful Degradation

The system is designed with fallback mechanisms:
- If compact block index is disabled · linear scan through klog blocks from beginning (still works)
- If bloom filter is disabled · check every SSTable (higher I/O but correct)
- If compression is disabled · larger files but faster reads (no decompression overhead)

This approach ensures that TidesDB maintains correctness even when optimizations are disabled, while achieving excellent performance when all features are enabled.

### 7.2 Compression

TidesDB supports multiple compression algorithms for SSTable data: Snappy emphasizes speed over compression ratio, LZ4 provides a balanced approach with good speed and reasonable compression, and ZSTD offers a higher compression ratio at the cost of some performance. Compression is applied only to SSTable entries (data blocks) to reduce disk usage and I/O. WAL entries remain uncompressed for fast writes and recovery.

### 7.3 Sync Modes

TidesDB provides three sync modes to balance durability and performance:

**TDB_SYNC_NONE** is fastest but least durable, relying entirely on the OS page cache to eventually flush data to disk. No explicit fsync calls are made for user data writes, maximizing throughput at the cost of potential data loss on system crash.

**TDB_SYNC_INTERVAL** provides a balanced approach with periodic background syncing. This mode uses a single database-level background thread that monitors all column families configured with interval mode. The thread sleeps for the configured interval (specified in microseconds via `sync_interval_us`), then wakes up to perform fsync on all dirty file descriptors for interval-mode column families. This bounds potential data loss to at most one sync interval window while maintaining good write performance. For example, with a 1-second interval, at most 1 second of writes could be lost on crash.

**TDB_SYNC_FULL** is most durable, performing fsync/fdatasync after every write operation. This guarantees immediate persistence of all writes but significantly impacts write throughput due to the synchronous nature of fsync.

The sync mode can be configured per column family, allowing different durability guarantees for different data types. Critically, regardless of the configured sync mode, TidesDB always enforces fsync for structural operations including memtable flush to SSTable, SSTable compaction and merging, and WAL rotation. This two-tier durability strategy ensures database structural integrity while allowing flexible durability policies for user data.

### 7.4 Configurable Parameters

TidesDB allows fine-tuning through various configurable parameters including memtable flush thresholds, skip list configuration (max level and probability), bloom filter usage and false positive rate, compression settings (algorithm selection), compaction trigger thresholds and thread count, sync mode (TDB_SYNC_NONE, TDB_SYNC_INTERVAL, or TDB_SYNC_FULL), sync interval in microseconds (for TDB_SYNC_INTERVAL mode), debug logging, compact block index usage, and thread pool sizes (flush and compaction).

### 7.5 Thread Pool Architecture

For efficient resource management, TidesDB employs shared thread pools at the 
storage engine level. Rather than maintaining separate pools per column family, all 
column families share common flush and compaction thread pools configured 
during the TidesDB instance initialization. Operations are submitted as tasks to these 
pools, enabling non-blocking execution--application threads can continue 
processing while flush and compaction work proceeds in the background. This 
architecture minimizes resource overhead and provides consistent, predictable 
performance across the entire storage engine instance.

**Configuration**
```c
tidesdb_config_t config = {
    .db_path = "./mydb",
    .num_flush_threads = 4,      /* 4 threads for flush operations */
    .num_compaction_threads = 8  /* 8 threads for compaction */
};
```

**Thread Pool Implementation**

Each thread pool consists of worker threads that wait on a task queue. When a 
task is submitted (flush or compaction), it's added to the appropriate queue 
and a worker thread picks it up. The flush pool handles memtable-to-SSTable 
flush operations, while the compaction pool handles SSTable merge operations. 
Worker threads use `queue_dequeue_wait()` to block efficiently when no tasks 
are available, waking immediately when work arrives.

**Benefits**

One set of threads serves all column families providing resource efficiency, with better thread utilization across workloads. Configuration is simpler since it's set once at the storage engine level, and the system is easily scalable to tune for available CPU cores. The queue-based design prevents thread creation overhead and enables graceful shutdown.

**Default values**

The `num_flush_threads` defaults to 2 (TDB_DEFAULT_THREAD_POOL_SIZE) and is I/O bound, so 2-4 is usually sufficient. The `num_compaction_threads` also defaults to 2 (TDB_DEFAULT_THREAD_POOL_SIZE) but is CPU bound, so it can be set higher (4-16).

## 8. Concurrency and Thread Safety

TidesDB is designed for exceptional concurrency with lock-free skip list operations and mutex-based coordination for structural changes.

### 8.1 Lock-Free Skip List Operations

TidesDB's skip list memtables use lock-free operations with atomic CAS instructions 
and a versioning strategy with last-write-wins semantics. Readers never acquire locks, 
never block, and scale linearly with CPU cores. All read operations use atomic pointer 
loads with acquire memory ordering for correct synchronization. Writers perform lock-free 
atomic operations on the skip list structure using Compare-And-Swap (CAS) instructions. 
Readers don't block writers, and writers don't block readers. Nodes are only freed when 
the entire skip list is destroyed, preventing use-after-free during concurrent access.

### 8.2 Column Family Coordination

Each column family uses lock-free atomic flags for coordinating structural operations:

- `is_flushing` · Atomic flag serializing memtable rotation and flush operations
- `is_compacting` · Atomic flag serializing compaction operations
- `cf_list_lock` · Reader-writer lock at database level for column family lifecycle (create/drop)

These atomic flags use compare-and-swap (CAS) operations to coordinate structural changes without blocking lock-free skip list operations. Multiple threads can read and write to the skip list concurrently while flush and compaction operations safely modify the underlying storage structures using atomic operations.

**Memtable Rotation** · Uses atomic CAS on `is_flushing` flag. If rotation is already in progress, subsequent attempts skip and return immediately. The active memtable pointer is swapped atomically, and immutable memtables are added to a queue.

**Compaction** · Uses atomic CAS on `is_compacting` flag. If compaction is already running, subsequent triggers skip. SSTable arrays in levels use atomic pointers (`_Atomic(tidesdb_sstable_t **)`) with atomic loads and stores for safe concurrent access.

**Level Operations** · All level metadata (capacity, current_size, num_sstables) uses atomic operations with appropriate memory ordering (acquire/release) to ensure visibility across threads without locks.

### 8.3 Transaction Isolation

TidesDB implements multi-version concurrency control (MVCC) using sequence numbers to provide configurable isolation levels without locking readers. Each write operation is assigned a monotonically increasing sequence number via atomic increment, establishing a total ordering of all committed operations. Transactions capture a snapshot sequence number at begin time, enabling consistent reads across multiple operations while concurrent writes proceed without blocking. The system supports five isolation levels, each providing different trade-offs between consistency guarantees and concurrency.

**Isolation Levels · Implementation Details**

**READ UNCOMMITTED (Level 0)**

Implementation: `skip_list_get_with_seq()` is called with `snapshot_seq = UINT64_MAX`, which bypasses all version filtering and returns the latest version regardless of commit status.

```c
if (snapshot_seq == UINT64_MAX) {
    // Read uncommitted: see all versions, use latest
    if (version == NULL) return -1;
}
```

No transaction registration, no read/write set tracking, no conflict detection. Provides maximum concurrency with zero coordination overhead. Suitable for analytics workloads where approximate results are acceptable.

**READ COMMITTED (Level 1)**

Implementation: Each read operation captures a fresh snapshot by loading `atomic_load(&cf->commit_seq)` at read time. The snapshot refreshes on every `tidesdb_txn_get()` call.

```c
if (txn->isolation_level == TDB_ISOLATION_READ_COMMITTED) {
    // Refresh snapshot on each read
    cf_snapshot = atomic_load_explicit(&cf->commit_seq, memory_order_acquire);
}
```

Reads filter versions using `skip_list_get_with_seq()` with the per-read snapshot, ensuring only committed data is visible. No read set tracking, no write conflict detection beyond basic write-write conflicts. Default isolation level for most workloads.

**REPEATABLE READ (Level 2)**

Implementation: Snapshot captured once at transaction begin via `tidesdb_txn_add_cf_internal()`, stored in `txn->cf_snapshots[cf_idx]`. All subsequent reads use this fixed snapshot.

```c
if (txn->isolation_level == TDB_ISOLATION_REPEATABLE_READ) {
    // Use consistent snapshot from transaction start
    cf_snapshot = txn->cf_snapshots[cf_idx];
}
```

Transaction registers in the column family's active transaction buffer (`cf->active_txn_buffer`) to enable conflict detection. At commit time, the system performs two checks:

1. **Read-set validation**: For each key in `txn->read_keys[]`, check if `found_seq > key_read_seq`. If true, another transaction modified the key after we read it → abort with `TDB_ERR_CONFLICT`.

2. **Write-write conflict detection**: For each key in `txn->write_keys[]`, check if `found_seq > cf_snapshot`. If true, another transaction committed a write to the same key → abort with `TDB_ERR_CONFLICT`.

Prevents lost updates but allows phantom reads in range scans.

**SNAPSHOT ISOLATION (Level 3)**

Implementation: Identical to REPEATABLE READ with enhanced write conflict detection. Uses the same snapshot capture, read-set tracking, and write-write conflict checks.

```c
if (txn->isolation_level == TDB_ISOLATION_SNAPSHOT) {
    // Track reads for conflict detection
    tidesdb_txn_add_to_read_set(txn, cf, key, key_size, found_seq);
}
```

The key difference is semantic: SNAPSHOT isolation explicitly guarantees first-committer-wins semantics for overlapping write sets, making it suitable for workloads with high contention on specific keys. The implementation is the same as REPEATABLE READ in TidesDB's current design.

**SERIALIZABLE (Level 4) · SSI Implementation**

Implementation: Full Serializable Snapshot Isolation (SSI) with read-write antidependency detection. Extends SNAPSHOT isolation with an additional check at commit time.

At transaction begin, registers in `cf->active_txn_buffer` with isolation level stored:
```c
tidesdb_txn_register(cf, txn->txn_id, cf_snapshot, 
                     TDB_ISOLATION_SERIALIZABLE, &txn_slot);
```

During reads, tracks every key accessed in the read set:
```c
txn->read_keys[txn->read_set_count] = malloc(key_size);
memcpy(txn->read_keys[txn->read_set_count], key, key_size);
txn->read_seqs[txn->read_set_count] = found_seq;
txn->read_cfs[txn->read_set_count] = cf;
txn->read_set_count++;
```

At commit time, performs the **SSI antidependency check**

```c
if (txn->isolation_level == TDB_ISOLATION_SERIALIZABLE) {
    // Check each CF's active transaction buffer
    for (int cf_idx = 0; cf_idx < txn->num_cfs; cf_idx++) {
        ssi_check_ctx_t ctx = {.txn = txn, .conflict_found = 0};
        buffer_foreach(cf->active_txn_buffer, check_rw_conflict, &ctx);
        
        if (ctx.conflict_found) {
            return TDB_ERR_CONFLICT;  // Abort to prevent write-skew
        }
    }
}
```

The `check_rw_conflict()` callback scans all active SERIALIZABLE transactions:

```c
static void check_rw_conflict(uint32_t id, void *data, void *ctx) {
    tidesdb_txn_entry_t *active = (tidesdb_txn_entry_t *)data;
    
    // Skip ourselves
    if (active->txn_id == check_ctx->txn->txn_id) return;
    
    // Check if active transaction's snapshot overlaps with our writes
    // If they started before we commit and we're writing keys,
    // we have a potential rw-conflict (they might have read data
    // we're about to overwrite)
    for (int cf_idx = 0; cf_idx < check_ctx->txn->num_cfs; cf_idx++) {
        if (active->snapshot_seq <= check_ctx->txn->cf_snapshots[cf_idx]) {
            // Abort to prevent potential write-skew
            check_ctx->conflict_found = 1;
            return;
        }
    }
}
```

**Key Insight** · This detects **dangerous structures** in the serialization graph. If transaction T1 (committing) is writing keys, and transaction T2 (active) has a snapshot from before T1 started, then T2 might have read old values of keys T1 is writing. This creates a read-write antidependency (T2 →rw T1), which combined with a write-read dependency (T1 →wr T2) would form a cycle, violating serializability. By aborting T1, we prevent the cycle.

This is a **conservative** SSI implementation: it may abort transactions that wouldn't actually cause anomalies (false positives), but it never allows non-serializable executions (no false negatives). The overhead is proportional to the number of active SERIALIZABLE transactions, not all transactions, making it practical for mixed workloads.

**MVCC Implementation**

Sequence numbers are assigned atomically during WAL writes via atomic_fetch_add, providing lock-free ordering guarantees. Each key-value pair stores its sequence number in the 33-byte klog entry header, enabling efficient filtering during reads. Tombstones are versioned identically to regular writes, ensuring that deletions are visible only to transactions with appropriate snapshot sequences. During compaction, the system retains only the newest version of each key, purging older versions and tombstones to reclaim storage space.

**Read-Your-Own-Writes**

All isolation levels support read-your-own-writes semantics within a single transaction. Uncommitted operations are buffered in the transaction's write set and checked before searching persistent storage. When tidesdb_txn_get is called, the system first scans the transaction's buffered operations in reverse order, returning the buffered value if found. Only if the key is not in the write set does the system search the memtable and SSTables. This ensures that applications can read their own uncommitted changes, enabling dependent operations within a transaction.

**Lock-Free Transaction Commits**

Write transactions use lock-free atomic operations throughout their lifecycle, enabling unlimited concurrent commits without blocking. During commit, each buffered operation is written to the WAL and skip list using atomic CAS operations, with sequence numbers assigned atomically. Memtable references are acquired using lock-free CAS retry loops, ensuring that memtable rotation does not block transaction commits. Multiple write transactions can commit concurrently to the same column family, with the skip list's lock-free insertion algorithm resolving contention without mutexes. This design enables linear scalability of write throughput with CPU core count.

**Lock-Free Buffer for Transaction Tracking**

TidesDB implements a general-purpose lock-free circular buffer data structure (buffer.h/buffer.c) used for concurrent slot management with atomic operations. Each buffer slot maintains an atomic state (FREE, ACQUIRED, OCCUPIED, RELEASING), atomic generation counter for ABA prevention, and atomic data pointer. Slot acquisition uses atomic CAS with exponential backoff, while release operations atomically transition slots back to FREE state with generation increment. The buffer supports optional eviction callbacks, foreach iteration over occupied slots, and configurable retry parameters for acquisition under contention.

**Active Transaction Buffer for SERIALIZABLE Isolation**

For SERIALIZABLE isolation, each column family maintains an active transaction buffer (`cf->active_txn_buffer`) using the lock-free buffer implementation to track all currently active SERIALIZABLE transactions. The buffer is initialized with a default capacity of `TDB_DEFAULT_ACTIVE_TXN_BUFFER_SIZE` slots, each capable of holding a `tidesdb_txn_entry_t` structure.

**Transaction Registration**

When a SERIALIZABLE transaction begins and first accesses a column family, it registers via `tidesdb_txn_register()`:

```c
tidesdb_txn_entry_t *entry = malloc(sizeof(tidesdb_txn_entry_t));
entry->txn_id = txn_id;
entry->snapshot_seq = snapshot_seq;
entry->isolation = TDB_ISOLATION_SERIALIZABLE;
entry->buffer_slot_id = BUFFER_INVALID_ID;
entry->generation = 0;

if (buffer_acquire(cf->active_txn_buffer, entry, slot_id) != 0) {
    // Buffer exhausted - fail transaction to preserve correctness
    free(entry);
    return -1;
}

// Store slot ID and generation for validation
entry->buffer_slot_id = *slot_id;
buffer_get_generation(cf->active_txn_buffer, *slot_id, &entry->generation);
```

The `buffer_acquire()` call performs an atomic CAS operation to find a FREE slot and transition it to ACQUIRED state. If all slots are occupied (buffer exhausted), the transaction fails immediately rather than compromising SERIALIZABLE guarantees. This is a critical design choice: SSI correctness requires tracking all active SERIALIZABLE transactions, so buffer exhaustion must be treated as a hard error.

**Lock-Free Buffer Slot States**

Each buffer slot transitions through atomic states:
```
FREE → ACQUIRED → OCCUPIED → RELEASING → FREE
```

- **FREE** · Slot available for acquisition
- **ACQUIRED** · Thread has claimed slot, writing data
- **OCCUPIED** · Data written, slot visible to readers
- **RELEASING** · Slot being freed, not visible to new readers

State transitions use atomic CAS operations with exponential backoff under contention. The generation counter increments on each FREE → ACQUIRED transition, preventing ABA problems where a slot ID is reused between validation and access.

**SSI Antidependency Check**

During commit, the system scans all active SERIALIZABLE transactions using `buffer_foreach()`:

```c
ssi_check_ctx_t ctx = {.txn = txn, .conflict_found = 0};
buffer_foreach(cf->active_txn_buffer, check_rw_conflict, &ctx);

if (ctx.conflict_found) {
    return TDB_ERR_CONFLICT;
}
```

The `buffer_foreach()` function iterates over all OCCUPIED slots, calling the `check_rw_conflict()` callback for each active transaction. The callback checks if any active transaction has a snapshot that overlaps with the committing transaction's write set, detecting dangerous structures in the serialization graph.

**Key Implementation Detail** · The foreach iteration is **lock-free** and **wait-free**. It reads slot states atomically and skips slots that transition to RELEASING during iteration. This means conflict detection never blocks, even if transactions are concurrently registering or unregistering.

**Transaction Unregistration**

After commit or abort, the transaction unregisters via `tidesdb_txn_unregister()`:

```c
if (!cf || !cf->active_txn_buffer || slot_id == BUFFER_INVALID_ID) return;
buffer_release(cf->active_txn_buffer, slot_id);
```

The `buffer_release()` call atomically transitions the slot from OCCUPIED → RELEASING → FREE, incrementing the generation counter. An optional eviction callback (`txn_entry_evict`) is invoked to free the `tidesdb_txn_entry_t` structure, ensuring no memory leaks.

**Generation Counter ABA Prevention**

Consider this scenario without generation counters:
1. Transaction T1 acquires slot 5, stores pointer P1
2. T1 commits, releases slot 5
3. Transaction T2 acquires slot 5, stores pointer P2
4. Concurrent thread still holds slot ID 5, dereferences → **use-after-free of P1**

With generation counters:
1. T1 acquires slot 5 (generation 10), stores P1
2. T1 commits, releases slot 5 (generation increments to 11)
3. T2 acquires slot 5 (generation 11), stores P2
4. Concurrent thread validates: slot 5, generation 10 ≠ 11 → **detects stale reference, skips**

This enables safe concurrent access without locking the entire buffer.

**Performance Characteristics**

- **Registration** · O(1) amortized, O(slots) worst-case if buffer is nearly full
- **Conflict Check** · O(active_serializable_txns), not O(all_txns)
- **Unregistration** · O(1) atomic release
- **Memory** · Fixed-size buffer, no dynamic allocation per transaction
- **Contention** · Exponential backoff on CAS failures, scales well to 100+ concurrent SERIALIZABLE transactions

The buffer size is configurable via `TDB_DEFAULT_ACTIVE_TXN_BUFFER_SIZE`. If your workload has many long-running SERIALIZABLE transactions, increase this value to prevent buffer exhaustion. For workloads with mostly READ_COMMITTED or SNAPSHOT transactions, the buffer overhead is minimal since only SERIALIZABLE transactions register.

This design enables full SERIALIZABLE isolation without global locks, with overhead proportional only to the number of active SERIALIZABLE transactions. Mixed workloads (e.g., 95% READ_COMMITTED, 5% SERIALIZABLE) pay minimal cost, making SERIALIZABLE practical for critical operations without sacrificing overall system throughput.

### 8.4 Optimal Use Cases

This concurrency model makes TidesDB particularly well-suited for:

- Read-heavy workloads with unlimited concurrent readers and no contention
- Mixed read/write workloads where readers never wait for writers to complete
- Multi-column-family applications where different column families can be written to concurrently

## 9. Directory Structure and File Organization

TidesDB organizes data on disk with a clear directory hierarchy. Understanding this structure is essential for backup, monitoring, and debugging.

### 9.1 Directory Layout

Each TidesDB instance has a root directory containing subdirectories for each column family:

```
mydb/
├── my_cf/
│   ├── MANIFEST
│   ├── config.cfc        
│   ├── wal_1.log
│   ├── L1_0.klog
│   ├── L1_0.vlog
│   ├── L1_1.klog
│   ├── L1_1.vlog
│   ├── L2_0.klog
│   ├── L2_0.vlog
│   ├── L3P0_2.klog
│   ├── L3P0_2.vlog
│   ├── L3P1_3.klog
│   └── L3P1_3.vlog
├── users/
│   ├── MANIFEST
│   ├── config.cfc
│   ├── wal_0.log
│   ├── L1_0.klog
│   └── L1_0.vlog
└── sessions/
    ├── MANIFEST
    ├── config.cfc
    └── wal_0.log
```

Each column family directory contains:
- **MANIFEST** - Tracks all active SSTables (level, ID, entry count, size) and the next SSTable ID sequence
- **config.cfc** - INI format configuration file with column family settings
- **wal_*.log** - Write-ahead log files for crash recovery
- **L<level>_<id>.klog** - SSTable key log files containing sorted keys and metadata
- **L<level>_<id>.vlog** - SSTable value log files containing large values

The MANIFEST file is updated atomically (write temp + rename) after each flush and compaction to maintain a consistent view of which SSTables exist. During recovery, the MANIFEST is loaded first to determine which SSTables should be opened, avoiding filesystem directory scans.

### 9.2 File Naming Conventions

#### Write-Ahead Log (WAL) Files

WAL files follow the naming pattern `wal_<memtable_id>.log` (e.g., `wal_0.log`, `wal_1.log`). Each memtable has its own dedicated WAL file with a matching ID. WAL files are deleted only after the corresponding memtable is successfully flushed to an SSTable. See Section 4.4 for detailed WAL lifecycle and rotation mechanics.

#### SSTable Files

SSTable files follow the naming convention `L<level>_<id>.klog` and `L<level>_<id>.vlog` for standard SSTables, or `L<level>P<partition>_<id>.klog` and `L<level>P<partition>_<id>.vlog` for partitioned SSTables created during partitioned merge operations. Examples include `L1_0.klog`, `L1_0.vlog` (standard), `L2_1.klog`, `L2_1.vlog` (standard), and `L3P0_5.klog`, `L3P0_5.vlog` (partitioned). The level number (1-based in filenames) indicates the LSM tree level, the optional partition number identifies which partition within a partitioned merge, and the id is a monotonically increasing counter per column family. An SSTable is created when a memtable exceeds the `write_buffer_size` threshold, with the initial flush writing to level 1 (`L1_<id>`). Each klog file contains sorted key entries with bloom filter and index metadata for efficient lookups, while the vlog file contains large values referenced by offset from the klog. During compaction, SSTables from multiple levels are merged into new consolidated files at higher levels, with partitioned merges creating multiple output files per operation (e.g., `L3P0_*`, `L3P1_*`, `L3P2_*`). Original SSTables are deleted after the merge completes successfully. During recovery, the system parses the level and optional partition number from filenames and maps `L<N>` files to `levels[N-1]` in the in-memory array, ensuring correct placement in the LSM hierarchy.

#### MANIFEST File

The MANIFEST file tracks all active SSTables for a column family and is the source of truth for recovery. It uses a simple text-based format with direct file rewriting for efficient updates.

**File Format**

The MANIFEST is stored as a plain text file with the following structure:

```
<version>
<sequence>
<level>,<id>,<num_entries>,<size_bytes>
<level>,<id>,<num_entries>,<size_bytes>
...
```

- **Line 1** · Manifest format version (currently 6)
- **Line 2** · Global sequence number for the column family
- **Remaining lines** · One SSTable entry per line in CSV format
  - `level`: LSM tree level (0-based)
  - `id`: Unique SSTable identifier
  - `num_entries`: Number of key-value pairs in the SSTable
  - `size_bytes`: Total size of the SSTable in bytes

**Example**
```
6
12345
1,100,1000,65536
1,101,1500,98304
2,200,5000,262144
```

**Thread-Safe Updates**

The MANIFEST is updated after each flush and compaction using a reader-writer lock (`pthread_rwlock_t`) for thread safety:
1. **Acquire write lock** to serialize concurrent updates
2. **Close** existing file pointer
3. **Open** file in write mode (truncates existing content)
4. **Write** version, sequence, and all SSTable entries
5. **Flush and fsync** to ensure durability
6. **Reopen** file in read mode for efficient future reads
7. **Release write lock**

This provides several benefits:
- **Simple format** · Human-readable text for easy debugging and inspection
- **Efficient updates** · Direct file rewriting without temporary files
- **Thread-safe** · Reader-writer lock allows concurrent reads during queries
- **Crash-safe** · Fsync ensures durability before returning success
- **Fast access** · File kept open for the lifetime of the column family

**API**

The manifest uses intuitive open/close semantics:
- `tidesdb_manifest_open(path)`: Opens or creates a manifest file
- `tidesdb_manifest_add_sstable()`: Adds or updates an SSTable entry (thread-safe)
- `tidesdb_manifest_remove_sstable()`: Removes an SSTable entry (thread-safe)
- `tidesdb_manifest_has_sstable()`: Checks if an SSTable exists (thread-safe read)
- `tidesdb_manifest_commit(path)`: Writes manifest to disk atomically
- `tidesdb_manifest_close()`: Closes file and frees resources

**Recovery**

During recovery:
1. **Open** manifest file (creates empty manifest if doesn't exist)
2. **Parse** text format to load SSTable metadata
3. **Verify** each SSTable file exists on disk
4. **Load** SSTable metadata (min/max keys, bloom filters, indices) into memory
5. **Keep** manifest file open for efficient runtime updates

The simple text format makes manifest corruption easy to detect and debug, while the direct rewriting approach ensures the manifest always reflects the current state without accumulating historical data.

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
Flushing Memtable (ID 0) → L1_0.klog + L1_0.vlog  [writing to disk]
wal_0.log  [still exists - flush in progress]
```

**5. Flush Complete**
```
Active Memtable (ID 1) → wal_1.log
L1_0.klog + L1_0.vlog  [persisted to level 1]
wal_0.log  [DELETED - memtable freed after flush]
```

**6. Next Rotation (Before Previous Flush Completes)**
```
New Active Memtable (ID 2) → wal_2.log  [new active]
Immutable Memtable (ID 1) → wal_1.log  [queued for flush]
Flushing Memtable (ID 0) → L1_0.klog + L1_0.vlog  [still flushing]
wal_0.log  [still exists - flush not complete]
```

**7. After All Flushes Complete**
```
Active Memtable (ID 2) → wal_2.log
SSTable L1_0.klog + L1_0.vlog
SSTable L1_1.klog + L1_1.vlog
wal_0.log, wal_1.log  [DELETED means both flushes complete]
```

### 9.4 Directory Management

Creating a column family creates a new subdirectory:
```c
tidesdb_create_column_family(db, "my_cf", &cf_config);
// Creates mydb/my_cf/ directory with
//   - initial wal_0.log (for active memtable)
//   - config.cfc (persisted configuration)
```

Dropping a column family removes the entire subdirectory:
```c
tidesdb_drop_column_family(db, "my_cf");
// Deletes mydb/my_cf/ directory and all contents (WALs, SSTables)
```

### 9.5 Monitoring Disk Usage

Useful commands for monitoring TidesDB storage:

```bash
# Check total size
du -sh mydb/

# Check per-column-family size
du -sh mydb/*/

# Count WAL files (should be 1-2 per CF normally)
find mydb/ -name "wal_*.log" | wc -l

# Count SSTable klog files (each SSTable has both .klog and .vlog)
find mydb/ -name "*.klog" | wc -l

# Count SSTables by level (includes both standard and partitioned)
find mydb/ -name "L1*.klog" | wc -l  # Level 1 (all)
find mydb/ -name "L2*.klog" | wc -l  # Level 2 (all)

# Count only partitioned SSTables
find mydb/ -name "*P*.klog" | wc -l

# List largest klog files
find mydb/ -name "*.klog" -exec ls -lh {} \; | sort -k5 -hr | head -10

# List largest vlog files
find mydb/ -name "*.vlog" -exec ls -lh {} \; | sort -k5 -hr | head -10

# Show SSTable distribution across levels
for level in 1 2 3 4 5; do
  count=$(find mydb/ -name "L${level}_*.klog" | wc -l)
  echo "Level $level: $count SSTables"
done
```

### 9.6 Best Practices

**Disk Space Monitoring**

Monitor WAL file count, which is typically 1-3 per column family (1 active + 1-2 in flush queue). Many WAL files (>5) may indicate a flush backlog, slow I/O, or configuration issue. Monitor L0 SSTable count as it triggers compaction at the system-wide threshold (`TDB_L0_FILE_NUM_COMPACTION_TRIGGER`, fixed at 4 files). Set appropriate `write_buffer_size` based on write patterns and flush speed.

**Backup Strategy**
```bash
# Stop writes, flush all memtables, then backup
# In your application
tidesdb_flush_memtable(cf);  # Force flush before backup

# Then backup
tar -czf mydb_backup.tar.gz mydb/
```

### 9.7 System Constants

TidesDB uses several system-wide constants (defined in `tidesdb.c`) that control compaction, flush, and backpressure behavior. These are not configurable per column family but are tuned based on the Spooky algorithm and production testing.

#### Compaction Triggers (Spooky Parameters)

```c
/* α (alpha) - trigger compaction */
TDB_L0_FILE_NUM_COMPACTION_TRIGGER = 4

/* β (beta) - slow down writes */
TDB_L0_SLOWDOWN_WRITES_TRIGGER = 20
TDB_L0_SLOWDOWN_WRITES_DELAY_US = 20000  // 20ms delay

/* γ (gamma) - stop writes (emergency) */
TDB_L0_STOP_WRITES_TRIGGER = 36
TDB_L0_STOP_WRITES_DELAY_US = 100000     // 100ms delay
```

These implement the Spooky algorithm's write throttling:
- **α = 4 files** · Normal operation, trigger background compaction
- **β = 20 files** · Write slowdown, add 20ms delay per write to apply backpressure
- **γ = 36 files** · Write stall, add 100ms delay per write (emergency mode)

#### L0 Capacity Backpressure

```c
TDB_BACKPRESSURE_THRESHOLD_L0_FULL = 100      // 100% full
TDB_BACKPRESSURE_THRESHOLD_L0_CRITICAL = 98   // 98% full
TDB_BACKPRESSURE_THRESHOLD_L0_HIGH = 95       // 95% full
TDB_BACKPRESSURE_THRESHOLD_L0_MODERATE = 90   // 90% full

TDB_BACKPRESSURE_DELAY_EMERGENCY_US = 50000   // 50ms
TDB_BACKPRESSURE_DELAY_CRITICAL_US = 10000    // 10ms
TDB_BACKPRESSURE_DELAY_HIGH_US = 5000         // 5ms
TDB_BACKPRESSURE_DELAY_MODERATE_US = 1000     // 1ms
```

When L0 reaches capacity thresholds, writes are delayed to prevent overwhelming the compaction system.

#### Immutable Memtable Queue Backpressure

```c
TDB_BACKPRESSURE_IMMUTABLE_EMERGENCY = 10          // 10 pending flushes
TDB_BACKPRESSURE_IMMUTABLE_CRITICAL = 6           // 6 pending flushes
TDB_BACKPRESSURE_IMMUTABLE_MODERATE = 3           // 3 pending flushes

TDB_BACKPRESSURE_IMMUTABLE_EMERGENCY_DELAY_US = 20000  // 20ms
TDB_BACKPRESSURE_IMMUTABLE_CRITICAL_DELAY_US = 5000    // 5ms
TDB_BACKPRESSURE_IMMUTABLE_MODERATE_DELAY_US = 1000    // 1ms
```

When the immutable memtable queue grows (flush backlog), writes are delayed to allow flush threads to catch up.

#### Compaction and Flush Timing

```c
TDB_COMPACTION_FLUSH_WAIT_SLEEP_US = 10000         // 10ms between checks
TDB_COMPACTION_FLUSH_WAIT_MAX_ATTEMPTS = 100       // Max 1 second wait
TDB_CLOSE_TXN_WAIT_MAX_MS = 5000                   // 5 second timeout
TDB_CLOSE_FLUSH_WAIT_MAX_MS = 10000                // 10 second timeout
TDB_FLUSH_RETRY_BACKOFF_US = 100000                // 100ms retry backoff
TDB_MAX_FFLUSH_RETRY_ATTEMPTS = 5                  // Max flush retries
```

These control timing for compaction coordination, graceful shutdown, and flush retry logic.

#### SSTable Reaper

```c
TDB_SSTABLE_REAPER_SLEEP_US = 100000              // 100ms wake interval
TDB_SSTABLE_REAPER_EVICT_RATIO = 0.25             // Evict 25% when triggered
```

The reaper thread wakes every 100ms to check if `num_open_sstables >= max_open_sstables`, then closes 25% of the least recently accessed SSTables.

**Performance Tuning**

Larger `write_buffer_size` results in fewer, larger SSTables with less compaction, while smaller `write_buffer_size` creates more, smaller SSTables with more compaction. The L0 file count trigger (`TDB_L0_FILE_NUM_COMPACTION_TRIGGER = 4`) is a fixed system constant derived from the Spooky algorithm and cannot be configured per column family. To reduce read amplification, decrease `write_buffer_size` to trigger more frequent flushes and compaction. To reduce write amplification, increase `write_buffer_size` to batch more writes before flushing.

## 10. Error Handling

TidesDB uses simple integer return codes for error handling. A return value of `0` (TDB_SUCCESS) indicates a successful operation, while negative values indicate specific error conditions. Error codes include memory allocation failures, I/O errors, corruption detection, lock failures, and more, allowing for precise error handling in production systems.

For a complete list of error codes and their meanings, see the [Error Codes Reference](../../reference/error-codes).

## 11. Memory Management
TidesDB validates key-value pair sizes to prevent out-of-memory conditions. If a key-value pair exceeds `TDB_MEMORY_PERCENTAGE` (60% of available system memory), TidesDB returns a `TDB_ERR_MEMORY_LIMIT` error. However, a minimum threshold of `TDB_MIN_KEY_VALUE_SIZE` (1MB) is enforced, ensuring that even on systems with low available memory, key-value pairs up to 1MB are always allowed. This prevents premature errors on 32-bit systems or memory-constrained environments. On startup, TidesDB populates `available_memory` and `total_memory` internally, which are members of the `tidesdb_t` struct, and uses these values to calculate the maximum allowed key-value size as `max(available_memory * 0.6, 1MB)`.  

## 12. Cross-Platform Portability

TidesDB is designed for maximum portability across operating systems, architectures, and compilers. All platform-specific code is isolated in `compat.h`, providing a unified abstraction layer that enables TidesDB to run identically on diverse platforms.

### 12.1 Supported Platforms

TidesDB officially supports and is continuously tested on:

**Operating Systems**
- Linux (Ubuntu, Debian, RHEL, etc.)
- macOS (Intel and Apple Silicon)
- Windows (MSVC and MinGW)

**Architectures**
- x86 (32-bit)
- x64 (64-bit)
- ARM (32-bit and 64-bit)
- RISC-V (experimental)

**Compilers**
- GCC (Linux, MinGW)
- Clang (macOS, Linux)
- MSVC (Windows)

### 12.2 Platform Abstraction Layer

The `compat.h` header provides cross-platform abstractions for system-specific functionality:

**File System Operations**
- `PATH_SEPARATOR` Platform-specific path separator (`\` on Windows, `/` on POSIX)
- Path parsing functions handle both separators for true cross-platform portability, enabling databases created on Linux to be read on Windows and vice versa
- `mkdir()` Unified directory creation (handles different signatures on Windows vs POSIX)
- `pread()`/`pwrite()` Atomic positioned I/O (implemented via OVERLAPPED on Windows)
- `fsync()`/`fdatasync()` Data synchronization (uses `FlushFileBuffers()` on Windows)

**Threading Primitives**
- `pthread_*` POSIX threads (native on Linux/macOS, pthreads-win32 on MSVC, native on MinGW)
- `sem_t` Semaphores (native POSIX on Linux, `dispatch_semaphore_t` on macOS, Windows semaphores on MSVC/MinGW)
- Atomic operations: C11 `stdatomic.h` on modern compilers, Windows Interlocked functions on older MSVC

**Time Functions**
- `clock_gettime()` High-resolution time (implemented via `GetSystemTimeAsFileTime()` on Windows)
- `tdb_localtime()` Thread-safe time conversion (handles `localtime_r` vs `localtime_s` parameter order differences)

**String and Memory**
- `tdb_strdup()` String duplication (`_strdup` on MSVC, `strdup` on POSIX)
- `SIZE_MAX` Maximum size_t value (fallback `((size_t)-1)` for older compilers)

**Compiler-Specific Optimizations**
- `PREFETCH_READ()`/`PREFETCH_WRITE()` CPU cache prefetch hints (`__builtin_prefetch` on GCC/Clang, `_mm_prefetch` on MSVC)
- `ATOMIC_ALIGN(n)` Atomic variable alignment (`__declspec(align(n))` on MSVC, `__attribute__((aligned(n)))` on GCC/Clang)
- `UNUSED` Unused variable attribute for static functions

### 12.3 Endianness and File Portability

All multi-byte integers use explicit little-endian encoding throughout TidesDB via `encode_uint32_le()`, `encode_uint64_le()`, `encode_int64_le()`, and corresponding decode functions. These functions perform bit-shifting and masking to ensure consistent byte order regardless of the host architecture's native endianness. This guarantees that database files are fully portable-files created on a big-endian ARM system can be copied to a little-endian x86 system and read without any conversion or compatibility issues. The same database files work identically across x86, ARM, RISC-V, 32-bit, 64-bit, little-endian, and big-endian systems.

### 12.4 Continuous Integration Testing

TidesDB uses GitHub Actions to continuously test all supported platforms on every commit

- Linux x64 and x86 · Native builds with GCC
- macOS x64 and x86 · Native builds with Clang (Intel and Rosetta 2)
- Windows MSVC x64 and x86 · Native builds with Microsoft Visual C++
- Windows MinGW x64 and x86 · Cross-platform builds with GCC on Windows

Additionally, a portability test creates a database on Linux x64 and verifies it can be read correctly on all other platforms (Windows MSVC/MinGW x86/x64, macOS x86/x64, Linux x86), ensuring true cross-platform file compatibility.

### 12.5 Build System

TidesDB uses CMake for cross-platform builds with platform-specific dependency management.
- Linux/macOS · System package managers (apt, brew) for compression libraries (zstd, lz4, snappy)
- Windows · vcpkg for dependency management

## 13 Further Reading
- O'Neil, P., Cheng, E., Gawlick, D., & O'Neil, E. (1996). "The Log-Structured Merge-Tree (LSM-Tree)" Acta Informatica
- Lu, L., Pillai, T. S., Arpaci-Dusseau, A. C., & Arpaci-Dusseau, R. H. (2016). "WiscKey: Separating Keys from Values in SSD-conscious Storage" FAST '16
- Dayan, N. (2022). "Spooky: Granulating LSM-Tree Compactions Correctly" VLDB 2022
- Bernstein, P. A., & Goodman, N. (1983). "Multiversion Concurrency Control—Theory and Algorithms" ACM TODS
- Cahill, M. J., Röhm, U., & Fekete, A. D. (2008). "Serializable Isolation for Snapshot Databases" SIGMOD '08
- Michael, M. M., & Scott, M. L. (1996). "Simple, Fast, and Practical Non-Blocking and Blocking Concurrent Queue Algorithms" PODC '96
- Boehm, H.-J., & Adve, S. V. (2008). "Foundations of the C++ Concurrency Memory Model" PLDI '08
- Pugh, W. (1990). "Skip Lists: A Probabilistic Alternative to Balanced Trees" Communications of the ACM
- Jacobson, G. (1989). "Space-efficient Static Trees and Graphs" FOCS '89
- Bloom, B. H. (1970). "Space/Time Trade-offs in Hash Coding with Allowable Errors" Communications of the ACM
- Prabhakaran, V., Bairavasundaram, L. N., Agrawal, N., Gunawi, H. S., Arpaci-Dusseau, A. C., & Arpaci-Dusseau, R. H. (2005). "IRON File Systems" SOSP '05
- Gray, J., & Reuter, A. (1993). "Transaction Processing: Concepts and Techniques" Morgan Kaufmann
- Mohan, C., Haderle, D., Lindsay, B., Pirahesh, H., & Schwarz, P. (1992). "ARIES: A Transaction Recovery Method Supporting Fine-Granularity Locking and Partial Rollbacks Using Write-Ahead Logging" ACM TODS
- Tanenbaum, A. S. (1987). "Operating Systems: Design and Implementation" Prentice Hall
- Hanson, D. R. (1990). "Fast Allocation and Deallocation of Memory Based on Object Lifetimes" Software: Practice and Experience
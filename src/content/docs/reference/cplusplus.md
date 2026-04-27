---
title: TidesDB C++ API Reference
description: C++ API reference for TidesDB
---

<div class="no-print">

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/cplusplus.md).

<hr/>

</div>

## Getting Started

### Prerequisites

You **must** have the TidesDB shared C library installed on your system. You can find the installation instructions [here](/reference/building/#_top).

### Installation

```bash
git clone https://github.com/tidesdb/tidesdb-cpp.git
cd tidesdb-cpp
cmake -S . -B build
cmake --build build
sudo cmake --install build
```

### Custom Installation Paths

If you installed TidesDB to a non-standard location, you can specify custom paths:

```bash
cmake -S . -B build -DCMAKE_PREFIX_PATH=/custom/path
cmake --build build
```

## Usage

### Opening and Closing a Database

```cpp
#include <tidesdb/tidesdb.hpp>
#include <iostream>

int main() {
    tidesdb::Config config;
    config.dbPath = "./mydb";
    config.numFlushThreads = 2;                               // Flush thread pool size (default: 2)
    config.numCompactionThreads = 2;                          // Compaction thread pool size (default: 2)
    config.logLevel = tidesdb::LogLevel::Info;                // Log level (default: Info)
    config.blockCacheSize = 64 * 1024 * 1024;                 // 64MB global block cache (default: 64MB)
    config.maxOpenSSTables = 256;                             // Max cached SSTable structures (default: 256)
    config.maxMemoryUsage = 0;                                // Global memory limit in bytes (default: 0 = auto, 50% of system RAM)
    config.logToFile = false;                                 // Write logs to file instead of stderr (default: false)
    config.logTruncationAt = 24 * 1024 * 1024;                // Log file truncation size (default: 24MB), 0 = no truncation
    config.unifiedMemtable = false;                           // Enable unified memtable mode (default: false = per-CF memtables)
    config.unifiedMemtableWriteBufferSize = 0;                // Unified memtable write buffer size (0 = auto)
    config.unifiedMemtableSkipListMaxLevel = 0;               // Skip list max level for unified memtable (0 = default 12)
    config.unifiedMemtableSkipListProbability = 0;            // Skip list probability (0 = default 0.25)
    config.unifiedMemtableSyncMode = tidesdb::SyncMode::None; // Sync mode for unified WAL
    config.unifiedMemtableSyncIntervalUs = 0;                 // Sync interval for unified WAL in microseconds
    config.maxConcurrentFlushes = 0;                          // Cap on in-flight memtable flushes across all CFs (0 = library default)
    config.objectStore = nullptr;                             // Pluggable object store connector (nullptr = local only)
    config.objectStoreConfig = std::nullopt;                  // Object store behavior config (nullopt = defaults)

    try {
        tidesdb::TidesDB db(config);
        std::cout << "Database opened successfully" << std::endl;
        } catch (const tidesdb::Exception& e) {
        std::cerr << "Failed to open database: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
```

**Using default configuration**

Use `TidesDB::defaultConfig()` to get a configuration with sensible defaults, then override specific fields as needed. The defaults are pulled from the underlying C library, so values such as `maxConcurrentFlushes` and the unified-memtable settings track the engine's defaults automatically -- if you previously hardcoded these values when overriding fields, re-test after upgrading.

```cpp
auto config = tidesdb::TidesDB::defaultConfig();
config.dbPath = "./mydb";
config.logLevel = tidesdb::LogLevel::Warn;  // Override: only warnings and errors

tidesdb::TidesDB db(config);
```

:::note[maxConcurrentFlushes]
`maxConcurrentFlushes` is a global semaphore on the number of in-flight memtable flushes across all column families. It bounds total transient memory and work-queue depth when many column families flush at once. Leave it at `0` to inherit the library default (recommended), or lower it on memory-constrained hosts to throttle peak flush concurrency.
:::

### Logging

TidesDB provides structured logging with multiple severity levels.

**Log Levels**
- `LogLevel::Debug` · Detailed diagnostic information
- `LogLevel::Info` · General informational messages (default)
- `LogLevel::Warn` · Warning messages for potential issues
- `LogLevel::Error` · Error messages for failures
- `LogLevel::Fatal` · Critical errors that may cause shutdown
- `LogLevel::None` · Disable all logging

**Configure at startup**
```cpp
tidesdb::Config config;
config.dbPath = "./mydb";
config.logLevel = tidesdb::LogLevel::Debug;  // Enable debug logging

tidesdb::TidesDB db(config);
```

**Production configuration**
```cpp
tidesdb::Config config;
config.dbPath = "./mydb";
config.logLevel = tidesdb::LogLevel::Warn;  // Only warnings and errors

tidesdb::TidesDB db(config);
```

**Output format**
Logs are written to **stderr** by default with timestamps:
```
[HH:MM:SS.mmm] [LEVEL] filename:line: message
```

**Log to file**

Enable `logToFile` to write logs to a `LOG` file in the database directory instead of stderr:

```cpp
tidesdb::Config config;
config.dbPath = "./mydb";
config.logLevel = tidesdb::LogLevel::Debug;
config.logToFile = true;  // Write to ./mydb/LOG instead of stderr

tidesdb::TidesDB db(config);
// Logs are now written to ./mydb/LOG
```

The log file is opened in append mode and uses line buffering for real-time logging. If the log file cannot be opened, logging falls back to default.

### Creating and Dropping Column Families

Column families are isolated key-value stores with independent configuration.

```cpp
auto cfConfig = tidesdb::ColumnFamilyConfig::defaultConfig();
db.createColumnFamily("my_cf", cfConfig);

auto cfConfig = tidesdb::ColumnFamilyConfig::defaultConfig();
cfConfig.writeBufferSize = 128 * 1024 * 1024;
cfConfig.levelSizeRatio = 10;
cfConfig.minLevels = 5;
cfConfig.compressionAlgorithm = tidesdb::CompressionAlgorithm::LZ4;
cfConfig.enableBloomFilter = true;
cfConfig.bloomFPR = 0.01;
cfConfig.enableBlockIndexes = true;
cfConfig.syncMode = tidesdb::SyncMode::Interval;
cfConfig.syncIntervalUs = 128000;
cfConfig.defaultIsolationLevel = tidesdb::IsolationLevel::ReadCommitted;
cfConfig.tombstoneDensityTrigger = 0.0;     // Per-SSTable tombstone density above which compaction escalates (0.0 = disabled, range 0.0 to 1.0)
cfConfig.tombstoneDensityMinEntries = 1024; // Minimum entry count for an SSTable to be considered by the density trigger
cfConfig.useBtree = false;  // Use block-based format (default), set true for B+tree klog format

db.createColumnFamily("my_cf", cfConfig);

db.dropColumnFamily("my_cf");

// Delete by handle (faster when you already hold a handle, avoids name lookup)
auto cf2 = db.getColumnFamily("another_cf");
db.deleteColumnFamily(cf2);
```

### CRUD Operations

All operations in TidesDB are performed through transactions for ACID guarantees.

#### Writing Data

```cpp
auto cf = db.getColumnFamily("my_cf");

auto txn = db.beginTransaction();
txn.put(cf, "key", "value", -1);
txn.commit();
```

#### Writing with TTL

```cpp
#include <ctime>

auto cf = db.getColumnFamily("my_cf");

auto txn = db.beginTransaction();

auto ttl = std::time(nullptr) + 10;

txn.put(cf, "temp_key", "temp_value", ttl);
txn.commit();
```

**TTL Examples**
```cpp
auto ttl = static_cast<std::time_t>(-1);

auto ttl = std::time(nullptr) + (5 * 60);

auto ttl = std::time(nullptr) + (60 * 60);

auto ttl = static_cast<std::time_t>(1735689599);
```

#### Reading Data

```cpp
auto cf = db.getColumnFamily("my_cf");

auto txn = db.beginTransaction();
auto value = txn.get(cf, "key");
std::string valueStr(value.begin(), value.end());
std::cout << "Value: " << valueStr << std::endl;
```

#### Deleting Data

```cpp
auto cf = db.getColumnFamily("my_cf");

auto txn = db.beginTransaction();
txn.del(cf, "key");
txn.commit();
```

#### Single Delete

`singleDelete` emits a single-delete tombstone. When the tombstone meets exactly one prior put for the same key during compaction, both records are dropped, so the tombstone does not persist past its matching put. Use it only when the caller guarantees at most one put precedes the delete; otherwise prefer `del`.

```cpp
auto cf = db.getColumnFamily("my_cf");

auto txn = db.beginTransaction();
txn.singleDelete(cf, "key");
txn.commit();
```

#### Multi-Operation Transactions

```cpp
auto cf = db.getColumnFamily("my_cf");

auto txn = db.beginTransaction();

txn.put(cf, "key1", "value1", -1);
txn.put(cf, "key2", "value2", -1);
txn.del(cf, "old_key");

txn.commit();
```

#### Transaction Rollback

```cpp
auto cf = db.getColumnFamily("my_cf");

auto txn = db.beginTransaction();
txn.put(cf, "key", "value", -1);

// Discard all operations
txn.rollback();
```

### Iterating Over Data

Iterators provide efficient bidirectional traversal over key-value pairs.

#### Forward Iteration

```cpp
auto cf = db.getColumnFamily("my_cf");

auto txn = db.beginTransaction();
auto iter = txn.newIterator(cf);

iter.seekToFirst();

while (iter.valid()) {
    auto key = iter.key();
    auto value = iter.value();

    std::string keyStr(key.begin(), key.end());
    std::string valueStr(value.begin(), value.end());

    std::cout << "Key: " << keyStr << ", Value: " << valueStr << std::endl;

    iter.next();
}
```

#### Backward Iteration

```cpp
auto cf = db.getColumnFamily("my_cf");

auto txn = db.beginTransaction();
auto iter = txn.newIterator(cf);

iter.seekToLast();

while (iter.valid()) {
    auto key = iter.key();
    auto value = iter.value();
    iter.prev();
}
```

#### Seeking

**How Seek Works**

**With Block Indexes Enabled** (`enableBlockIndexes = true`):
- Uses compact block index with parallel arrays (min/max key prefixes and file positions)
- Binary search through sampled keys at configurable ratio (default 1:1 via `indexSampleRatio`, meaning every block is indexed)
- Jumps directly to the target block using the file position
- Scans forward from that block to find the exact key
- **Performance** · O(log n) binary search + O(k) entries per block scan

Block indexes provide dramatic speedup for large SSTables at the cost of ~2-5% storage overhead for the compact index structure.

**`seek(key)`** · Positions iterator at the first key >= target key

```cpp
auto iter = txn.newIterator(cf);

iter.seek("user:1000");

// Iterator is now positioned at "user:1000" or the next key after it
if (iter.valid()) {
    auto key = iter.key();
    std::string keyStr(key.begin(), key.end());
    std::cout << "Found: " << keyStr << std::endl;
}
```

**`seekForPrev(key)`** · Positions iterator at the last key <= target key

```cpp
auto iter = txn.newIterator(cf);

iter.seekForPrev("user:2000");

// Iterator is now positioned at "user:2000" or the previous key before it
while (iter.valid()) {
    // Iterate backwards from this point
    iter.prev();
}
```

#### Prefix Seeking

Since `seek` positions the iterator at the first key >= target, you can use a prefix as the seek target to efficiently scan all keys sharing that prefix:

```cpp
auto iter = txn.newIterator(cf);

std::string prefix = "user:";
iter.seek(prefix);

while (iter.valid()) {
    auto key = iter.key();
    std::string keyStr(key.begin(), key.end());

    // Stop when keys no longer match prefix
    if (keyStr.substr(0, prefix.size()) != prefix) break;

    auto value = iter.value();
    std::string valueStr(value.begin(), value.end());
    std::cout << "Found: " << keyStr << " = " << valueStr << std::endl;

    iter.next();
}
```

This pattern works across both memtables and SSTables. When block indexes are enabled, the seek operation uses binary search to jump directly to the relevant block, making prefix scans efficient even on large datasets.

#### Combined Key-Value Fetch

`keyValue()` retrieves both key and value in a single call, which can be more efficient than separate `key()` and `value()` calls.

```cpp
auto iter = txn.newIterator(cf);
iter.seekToFirst();

while (iter.valid()) {
    auto [key, value] = iter.keyValue();
    std::string keyStr(key.begin(), key.end());
    std::string valueStr(value.begin(), value.end());

    std::cout << keyStr << " = " << valueStr << std::endl;
    iter.next();
}
```

### Getting Column Family Statistics

Retrieve detailed statistics about a column family.

```cpp
auto cf = db.getColumnFamily("my_cf");

auto stats = cf.getStats();

std::cout << "Number of Levels: " << stats.numLevels << std::endl;
std::cout << "Memtable Size: " << stats.memtableSize << " bytes" << std::endl;
std::cout << "Total Keys: " << stats.totalKeys << std::endl;
std::cout << "Total Data Size: " << stats.totalDataSize << " bytes" << std::endl;
std::cout << "Average Key Size: " << stats.avgKeySize << " bytes" << std::endl;
std::cout << "Average Value Size: " << stats.avgValueSize << " bytes" << std::endl;
std::cout << "Read Amplification: " << stats.readAmp << std::endl;
std::cout << "Cache Hit Rate: " << stats.hitRate << std::endl;

// B+tree stats (only populated if useBtree=true)
if (stats.useBtree) {
    std::cout << "B+tree Total Nodes: " << stats.btreeTotalNodes << std::endl;
    std::cout << "B+tree Max Height: " << stats.btreeMaxHeight << std::endl;
    std::cout << "B+tree Avg Height: " << stats.btreeAvgHeight << std::endl;
}

// Tombstone density observability
std::cout << "Total Tombstones: " << stats.totalTombstones << std::endl;
std::cout << "Tombstone Ratio: " << (stats.tombstoneRatio * 100.0) << "%" << std::endl;
std::cout << "Max SSTable Density: " << stats.maxSstDensity << std::endl;
if (stats.maxSstDensityLevel != 0) {
    std::cout << "Max SSTable Density Level: " << stats.maxSstDensityLevel << std::endl;
}

// Per-level statistics
for (int i = 0; i < stats.numLevels; ++i) {
    std::cout << "Level " << (i + 1) << ": "
              << stats.levelNumSSTables[i] << " SSTables, "
              << stats.levelSizes[i] << " bytes, "
              << stats.levelKeyCounts[i] << " keys, "
              << stats.levelTombstoneCounts[i] << " tombstones" << std::endl;
}

if (stats.config.has_value()) {
    std::cout << "Write Buffer Size: " << stats.config->writeBufferSize << std::endl;
    std::cout << "Compression: " << static_cast<int>(stats.config->compressionAlgorithm) << std::endl;
    std::cout << "Bloom Filter: " << (stats.config->enableBloomFilter ? "enabled" : "disabled") << std::endl;
}
```

**Statistics Fields**
- `numLevels` · Number of LSM levels
- `memtableSize` · Current memtable size in bytes
- `levelSizes` · Total bytes per level
- `levelNumSSTables` · Number of SSTables per level
- `totalKeys` · Total number of keys across memtable and all SSTables
- `totalDataSize` · Total data size (klog + vlog) across all SSTables
- `avgKeySize` · Average key size in bytes
- `avgValueSize` · Average value size in bytes
- `levelKeyCounts` · Number of keys per level
- `readAmp` · Read amplification (point lookup cost multiplier)
- `hitRate` · Cache hit rate (0.0 if cache disabled)
- `useBtree` · Whether column family uses B+tree klog format
- `btreeTotalNodes` · Total B+tree nodes across all SSTables (only if `useBtree=true`)
- `btreeMaxHeight` · Maximum tree height across all SSTables (only if `useBtree=true`)
- `btreeAvgHeight` · Average tree height across all SSTables (only if `useBtree=true`)
- `totalTombstones` · Sum of tombstone counts across all SSTables in the column family
- `tombstoneRatio` · `totalTombstones / totalKeys` (0.0 to 1.0, 0.0 if `totalKeys` is 0)
- `levelTombstoneCounts` · Per-level tombstone counts (parallels `levelKeyCounts`)
- `maxSstDensity` · Worst per-SSTable tombstone density observed in the CF (0.0 to 1.0)
- `maxSstDensityLevel` · 1-based level index where `maxSstDensity` was observed (0 if none)
- `config` · Column family configuration (optional)

### Database-Level Statistics

Get aggregate statistics across the entire database instance.

```cpp
auto dbStats = db.getDbStats();

std::cout << "Column families: " << dbStats.numColumnFamilies << std::endl;
std::cout << "Total memory: " << dbStats.totalMemory << " bytes" << std::endl;
std::cout << "Available memory: " << dbStats.availableMemory << " bytes" << std::endl;
std::cout << "Resolved memory limit: " << dbStats.resolvedMemoryLimit << " bytes" << std::endl;
std::cout << "Memory pressure level: " << dbStats.memoryPressureLevel << std::endl;
std::cout << "Global sequence: " << dbStats.globalSeq << std::endl;
std::cout << "Flush queue: " << dbStats.flushQueueSize << " pending" << std::endl;
std::cout << "Compaction queue: " << dbStats.compactionQueueSize << " pending" << std::endl;
std::cout << "Total SSTables: " << dbStats.totalSstableCount << std::endl;
std::cout << "Total data size: " << dbStats.totalDataSizeBytes << " bytes" << std::endl;
std::cout << "Open SSTable handles: " << dbStats.numOpenSstables << std::endl;
std::cout << "In-flight txn memory: " << dbStats.txnMemoryBytes << " bytes" << std::endl;
std::cout << "Immutable memtables: " << dbStats.totalImmutableCount << std::endl;
std::cout << "Memtable bytes: " << dbStats.totalMemtableBytes << std::endl;

// Unified memtable fields
std::cout << "Unified memtable enabled: " << dbStats.unifiedMemtableEnabled << std::endl;
std::cout << "Unified memtable bytes: " << dbStats.unifiedMemtableBytes << std::endl;
std::cout << "Unified immutable count: " << dbStats.unifiedImmutableCount << std::endl;
std::cout << "Unified is flushing: " << dbStats.unifiedIsFlushing << std::endl;
std::cout << "Unified WAL generation: " << dbStats.unifiedWalGeneration << std::endl;

// Object store fields
std::cout << "Object store enabled: " << dbStats.objectStoreEnabled << std::endl;
if (dbStats.objectStoreEnabled) {
    std::cout << "Object store connector: " << dbStats.objectStoreConnector << std::endl;
    std::cout << "Local cache bytes used: " << dbStats.localCacheBytesUsed << std::endl;
    std::cout << "Upload queue depth: " << dbStats.uploadQueueDepth << std::endl;
    std::cout << "Total uploads: " << dbStats.totalUploads << std::endl;
}
std::cout << "Replica mode: " << dbStats.replicaMode << std::endl;
```

**Database statistics fields**
- `numColumnFamilies` · Number of column families
- `totalMemory` · System total memory
- `availableMemory` · System available memory at open time
- `resolvedMemoryLimit` · Resolved memory limit (auto or configured)
- `memoryPressureLevel` · Current memory pressure (0=normal, 1=elevated, 2=high, 3=critical)
- `flushPendingCount` · Number of pending flush operations (queued + in-flight)
- `totalMemtableBytes` · Total bytes in active memtables across all CFs
- `totalImmutableCount` · Total immutable memtables across all CFs
- `totalSstableCount` · Total SSTables across all CFs and levels
- `totalDataSizeBytes` · Total data size (klog + vlog) across all CFs
- `numOpenSstables` · Number of currently open SSTable file handles
- `globalSeq` · Current global sequence number
- `txnMemoryBytes` · Bytes held by in-flight transactions
- `compactionQueueSize` · Number of pending compaction tasks
- `flushQueueSize` · Number of pending flush tasks in queue
- `unifiedMemtableEnabled` · Whether unified memtable mode is active
- `unifiedMemtableBytes` · Bytes in unified active memtable
- `unifiedImmutableCount` · Number of unified immutable memtables
- `unifiedIsFlushing` · Whether unified memtable is currently flushing/rotating
- `unifiedNextCfIndex` · Next CF index to be assigned in unified mode
- `unifiedWalGeneration` · Current unified WAL generation counter
- `objectStoreEnabled` · Whether object store mode is active
- `objectStoreConnector` · Connector name ("s3", "gcs", "fs", etc.)
- `localCacheBytesUsed` · Current local file cache usage in bytes
- `localCacheBytesMax` · Configured maximum local cache size in bytes
- `localCacheNumFiles` · Number of files tracked in local cache
- `lastUploadedGeneration` · Highest WAL generation confirmed uploaded
- `uploadQueueDepth` · Number of pending upload jobs in the queue
- `totalUploads` · Lifetime count of objects uploaded to object store
- `totalUploadFailures` · Lifetime count of permanently failed uploads
- `replicaMode` · Whether running in read-only replica mode

Unlike `getStats()` (which heap-allocates internally), `getDbStats()` fills a stack-allocated struct. No free is needed.

### Listing Column Families

```cpp
auto cfList = db.listColumnFamilies();

std::cout << "Available column families:" << std::endl;
for (const auto& name : cfList) {
    std::cout << "  - " << name << std::endl;
}
```

### Renaming a Column Family

Atomically rename a column family and its underlying directory.

```cpp
db.renameColumnFamily("old_name", "new_name");
```

**Behavior**
- Waits for any in-progress flush or compaction to complete
- Atomically renames the column family directory on disk
- Updates all internal paths (SSTables, manifest, config)
- Thread-safe with proper locking

### Cloning a Column Family

Create a complete copy of an existing column family with a new name. The clone contains all the data from the source at the time of cloning.

```cpp
db.cloneColumnFamily("source_cf", "cloned_cf");

// Both column families now exist independently
auto original = db.getColumnFamily("source_cf");
auto clone = db.getColumnFamily("cloned_cf");
```

**Behavior**
- Flushes the source column family's memtable to ensure all data is on disk
- Waits for any in-progress flush or compaction to complete
- Copies all SSTable files (`.klog` and `.vlog`) to the new directory
- Copies manifest and configuration files
- The clone is completely independent -- modifications to one do not affect the other

**Use cases**
- Testing · Create a copy of production data for testing without affecting the original
- Branching · Create a snapshot of data before making experimental changes
- Migration · Clone data before schema or configuration changes
- Backup verification · Clone and verify data integrity without modifying the source

### Compaction

#### Manual Compaction

```cpp
auto cf = db.getColumnFamily("my_cf");

cf.compact();
```

#### Targeted Range Compaction

`compactRange` runs a synchronous compaction over a specific key range. Only SSTables whose minimum and maximum keys overlap the requested range participate in the merge, so the work and I/O are bounded to the affected portion of the LSM tree rather than the whole column family.

```cpp
auto cf = db.getColumnFamily("my_cf");

std::vector<std::uint8_t> start{'t','e','n','a','n','t','_','4','2',':'};
std::vector<std::uint8_t> end{'t','e','n','a','n','t','_','4','2',';'};

cf.compactRange(start, end);
```

Pass `std::nullopt` for either endpoint to leave that side unbounded:

```cpp
using OptKey = std::optional<std::vector<std::uint8_t>>;

// Compact everything from `start` upward
cf.compactRange(OptKey{start}, OptKey{});

// Compact everything below `end`
cf.compactRange(OptKey{}, OptKey{end});
```

A `string_view` overload is also provided for the common case of textual keys:

```cpp
using OptSV = std::optional<std::string_view>;

cf.compactRange(OptSV{std::string_view{"tenant_42:"}},
                OptSV{std::string_view{"tenant_42;"}});
```

**When to use**

- Bulk reclaim after a large range delete, where waiting for natural compaction would leave tombstones and obsolete versions on disk
- Tenant eviction or sliding-window expiration that does not fit TTL semantics
- Post-import cleanup of a known key range loaded with `put` followed by `del`
- Operational counterpart to the automatic tombstone density trigger when an operator wants reclaim now rather than at the next natural threshold crossing

**Behavior**

- Synchronous, blocks the caller until the merge commits or fails
- Does not enqueue work onto the compaction thread pool, the calling thread does the work
- Selects only SSTables whose key range overlaps the requested range using the column family's comparator, SSTables outside the range are not touched
- Applies the same emit-loop logic as background compactions (tombstone reclamation rules, single-delete pair cancellation, sequence-based deduplication, value recompression)
- Output SSTables are committed to the manifest atomically and old inputs are marked for deletion

**Return values**

- Returns normally on success
- Throws `tidesdb::Exception` with `ErrorCode::InvalidArgs` if both endpoints are `std::nullopt` (use `compact()` for full CF compaction)
- Throws `tidesdb::Exception` with `ErrorCode::Locked` if another compaction is running for the column family
- Throws `tidesdb::Exception` with standard I/O and memory error codes if the merge cannot complete

#### Manual Memtable Flush

```cpp
auto cf = db.getColumnFamily("my_cf");

cf.flushMemtable(); 
```

#### Checking Flush/Compaction Status

Check if a column family currently has flush or compaction operations in progress.

```cpp
auto cf = db.getColumnFamily("my_cf");

if (cf.isFlushing()) {
    std::cout << "Flush in progress" << std::endl;
}

if (cf.isCompacting()) {
    std::cout << "Compaction in progress" << std::endl;
}
```

**Use cases**
- Graceful shutdown · Wait for background operations to complete before closing
- Maintenance windows · Check if operations are running before triggering manual compaction
- Monitoring · Track background operation status for observability

#### Purge Column Family

`purge()` forces a synchronous flush and aggressive compaction for a single column family. Unlike `flushMemtable()` and `compact()` (which are non-blocking), purge blocks until all flush and compaction I/O is complete.

```cpp
auto cf = db.getColumnFamily("my_cf");

cf.purge();
// All data is now flushed to SSTables and compacted
```

**Behavior**
1. Waits for any in-progress flush to complete
2. Force-flushes the active memtable (even if below threshold)
3. Waits for flush I/O to fully complete
4. Waits for any in-progress compaction to complete
5. Triggers synchronous compaction inline (bypasses the compaction queue)
6. Waits for any queued compaction to drain

**When to use**
- Before backup or checkpoint · Ensure all data is on disk and compacted
- After bulk deletes · Reclaim space immediately by compacting away tombstones
- Manual maintenance · Force a clean state during a maintenance window
- Pre-shutdown · Ensure all pending work is complete before closing

#### Purge Database

`purge()` on the database forces a synchronous flush and aggressive compaction for **all** column families, then drains both the global flush and compaction queues.

```cpp
db.purge();
// All CFs flushed and compacted, all queues drained
```

**Behavior**
1. Calls `purge()` on each column family
2. Drains the global flush queue (waits for queue size and pending count to reach 0)
3. Drains the global compaction queue (waits for queue size to reach 0)

:::tip[Purge vs Manual Flush + Compact]
`flushMemtable()` and `compact()` are non-blocking, they enqueue work and return immediately. `ColumnFamily::purge()` and `TidesDB::purge()` are synchronous, they block until all work is complete. Use purge when you need a guarantee that all data is on disk and compacted before proceeding.
:::

### Promote Replica to Primary

Switch a read-only replica database to primary (read-write) mode.

```cpp
db.promoteToPrimary();
```

**Behavior**
- Only valid when the database was opened in replica mode (via object store configuration)
- Transitions the database from read-only to read-write mode
- Throws `ErrorCode::InvalidArgs` if the database is not a replica

### Unified Memtable Mode

Enable a single shared memtable across all column families for reduced memory overhead and simplified WAL management.

```cpp
tidesdb::Config config;
config.dbPath = "./mydb";
config.unifiedMemtable = true;
config.unifiedMemtableWriteBufferSize = 64 * 1024 * 1024;  // 64MB unified buffer
config.unifiedMemtableSkipListMaxLevel = 12;
config.unifiedMemtableSkipListProbability = 0.25f;
config.unifiedMemtableSyncMode = tidesdb::SyncMode::Interval;
config.unifiedMemtableSyncIntervalUs = 128000;

tidesdb::TidesDB db(config);
```

**Configuration fields**
- `unifiedMemtable` · Enable unified memtable mode (default: false = per-CF memtables)
- `unifiedMemtableWriteBufferSize` · Write buffer size for unified memtable (0 = auto)
- `unifiedMemtableSkipListMaxLevel` · Skip list max level (0 = default 12)
- `unifiedMemtableSkipListProbability` · Skip list probability (0 = default 0.25)
- `unifiedMemtableSyncMode` · Sync mode for unified WAL (default: `SyncMode::None`)
- `unifiedMemtableSyncIntervalUs` · Sync interval for unified WAL in microseconds (default: 0)

### Updating Runtime Configuration

Update runtime-safe configuration settings without restarting the database.

```cpp
auto cf = db.getColumnFamily("my_cf");

auto newConfig = tidesdb::ColumnFamilyConfig::defaultConfig();
newConfig.writeBufferSize = 256 * 1024 * 1024;  
newConfig.skipListMaxLevel = 16;
newConfig.bloomFPR = 0.001;  // 0.1% false positive rate

bool persistToDisk = true;  // Save to config.ini
cf.updateRuntimeConfig(newConfig, persistToDisk);
```

**Updatable settings** (all applied by `updateRuntimeConfig`):
- `writeBufferSize` · Memtable flush threshold
- `skipListMaxLevel` · Skip list level for **new** memtables
- `skipListProbability` · Skip list probability for **new** memtables
- `bloomFPR` · False positive rate for **new** SSTables
- `enableBloomFilter` · Enable/disable bloom filters for **new** SSTables
- `enableBlockIndexes` · Enable/disable block indexes for **new** SSTables
- `blockIndexPrefixLen` · Block index prefix length for **new** SSTables
- `indexSampleRatio` · Index sampling ratio for **new** SSTables
- `compressionAlgorithm` · Compression for **new** SSTables (existing SSTables retain their original compression)
- `klogValueThreshold` · Value log threshold for **new** writes
- `syncMode` · Durability mode. Also updates the active WAL's sync mode immediately
- `syncIntervalUs` · Sync interval in microseconds (only used when syncMode is `SyncMode::Interval`)
- `levelSizeRatio` · LSM level sizing (DCA recalculates capacities dynamically)
- `minLevels` · Minimum LSM levels
- `dividingLevelOffset` · Compaction dividing level offset
- `l1FileCountTrigger` · L1 file count compaction trigger
- `l0QueueStallThreshold` · Backpressure stall threshold
- `defaultIsolationLevel` · Default transaction isolation level
- `minDiskSpace` · Minimum disk space required
- `commitHookFn` / `commitHookCtx` · Commit hook callback and context

**Non-updatable settings** (not modified by this function):
- `comparatorName` · Cannot change sort order after creation (would corrupt key ordering in existing SSTables)
- `useBtree` · Cannot change klog format after creation (existing SSTables use the original format)

Changes apply immediately to new operations. Existing SSTables and memtables retain their original settings. The update operation is thread-safe.

### Commit Hook (Change Data Capture)

`ColumnFamily::setCommitHook` registers a callback that fires synchronously after every transaction commit on a column family. The hook receives the full batch of committed operations atomically, enabling real-time change data capture without WAL parsing or external log consumers.

```cpp
auto cf = db.getColumnFamily("my_cf");

// Define a commit hook
auto myHook = [](const tidesdb_commit_op_t* ops, int num_ops,
                 uint64_t commit_seq, void* ctx) -> int {
    for (int i = 0; i < num_ops; ++i) {
        std::string key(reinterpret_cast<const char*>(ops[i].key), ops[i].key_size);
        if (ops[i].is_delete) {
            std::cout << "[" << commit_seq << "] DELETE " << key << std::endl;
        } else {
            std::string value(reinterpret_cast<const char*>(ops[i].value), ops[i].value_size);
            std::cout << "[" << commit_seq << "] PUT " << key << " = " << value << std::endl;
        }
    }
    return 0;
};

// Attach hook at runtime
cf.setCommitHook(myHook, nullptr);

// Normal writes now trigger the hook automatically
auto txn = db.beginTransaction();
txn.put(cf, "user:1", "Alice", -1);
txn.commit();  // myHook fires here

// Detach hook
cf.clearCommitHook();
```

**Setting hook via config at creation time**

```cpp
auto cfConfig = tidesdb::ColumnFamilyConfig::defaultConfig();
cfConfig.commitHookFn = myHook;
cfConfig.commitHookCtx = nullptr;

db.createColumnFamily("replicated_cf", cfConfig);
```

**Callback signature**

```cpp
int (*tidesdb_commit_hook_fn)(const tidesdb_commit_op_t* ops, int num_ops,
                               uint64_t commit_seq, void* ctx);
```

The callback returns `0` on success. A non-zero return is logged as a warning but does not roll back the commit.

**Operation struct fields** (`tidesdb_commit_op_t`)
- `key` / `key_size` · Key bytes (valid only during callback)
- `value` / `value_size` · Value bytes (`NULL` / `0` for deletes, valid only during callback)
- `ttl` · Time-to-live for the entry
- `is_delete` · `1` for delete, `0` for put

**Behavior**
- The hook fires after WAL write, memtable apply, and commit status marking are complete - data is fully durable before the callback runs
- Hook failure (non-zero return) is logged but does not affect the commit result
- Each column family has its own independent hook; a multi-CF transaction fires the hook once per CF with only that CF's operations
- `commit_seq` is monotonically increasing across commits and can be used as a replication cursor
- Pointers in `tidesdb_commit_op_t` are valid only during the callback invocation - copy any data you need to retain
- The hook executes synchronously on the committing thread; keep the callback fast to avoid stalling writers
- Setting the hook to `NULL` via `clearCommitHook()` disables it immediately with no restart required

**Use cases**
- Replication · Ship committed batches to replicas in commit order
- Event streaming · Publish mutations to Kafka, NATS, or any message broker
- Secondary indexing · Maintain a reverse index or materialized view
- Audit logging · Record every mutation with key, value, TTL, and sequence number
- Debugging · Attach a temporary hook in production to inspect live writes

The `commitHookFn` and `commitHookCtx` config fields are not persisted to `config.ini`. After a database restart, hooks must be re-registered by the application. This is by design - function pointers cannot be serialized.

### Backup

Create an on-disk snapshot of an open database without blocking normal reads/writes.

```cpp
db.backup("./mydb_backup");
```

**Behavior**
- Requires `dir` to be a non-existent directory or an empty directory
- Does not copy the `LOCK` file, so the backup can be opened normally
- Two-phase copy approach:
  - Copies immutable files first (SSTables listed in the manifest plus metadata/config files)
  - Forces memtable flushes, waits for flush/compaction queues to drain, then copies remaining files
- Database stays open and usable during backup

### Checkpoint

Create a lightweight, near-instant snapshot of an open database using hard links instead of copying SSTable data.

```cpp
db.checkpoint("./mydb_checkpoint");
```

**Behavior**
- Requires `dir` to be a non-existent directory or an empty directory
- For each column family:
  - Flushes the active memtable so all data is in SSTables
  - Halts compactions to ensure a consistent view of live SSTable files
  - Hard links all SSTable files (`.klog` and `.vlog`) into the checkpoint directory
  - Copies small metadata files (manifest, config) into the checkpoint directory
  - Resumes compactions
- Falls back to file copy if hard linking fails (e.g., cross-filesystem)
- Database stays open and usable during checkpoint

**Checkpoint vs Backup**

| | `backup` | `checkpoint` |
|--|---|---|
| Speed | Copies every SSTable byte-by-byte | Near-instant (hard links, O(1) per file) |
| Disk usage | Full independent copy | No extra disk until compaction removes old SSTables |
| Portability | Can be moved to another filesystem or machine | Same filesystem only (hard link requirement) |
| Use case | Archival, disaster recovery, remote shipping | Fast local snapshots, point-in-time reads, streaming backups |

**Notes**
- The checkpoint can be opened as a normal TidesDB database with `TidesDB(config)`
- Hard-linked files share storage with the live database. Deleting the original database does not affect the checkpoint (hard link semantics)

### Block Cache Statistics

Get statistics for the global block cache (shared across all column families).

```cpp
auto cacheStats = db.getCacheStats();

if (cacheStats.enabled) {
    std::cout << "Cache enabled: yes" << std::endl;
    std::cout << "Total entries: " << cacheStats.totalEntries << std::endl;
    std::cout << "Total bytes: " << cacheStats.totalBytes << std::endl;
    std::cout << "Hits: " << cacheStats.hits << std::endl;
    std::cout << "Misses: " << cacheStats.misses << std::endl;
    std::cout << "Hit rate: " << (cacheStats.hitRate * 100.0) << "%" << std::endl;
    std::cout << "Partitions: " << cacheStats.numPartitions << std::endl;
} else {
    std::cout << "Cache disabled (block_cache_size = 0)" << std::endl;
}
```

**Cache statistics fields**
- `enabled` · Whether block cache is active
- `totalEntries` · Number of cached blocks
- `totalBytes` · Total memory used by cached blocks
- `hits` · Number of cache hits
- `misses` · Number of cache misses
- `hitRate` · Hit rate as a decimal (0.0 to 1.0)
- `numPartitions` · Number of cache partitions

### Range Cost Estimation

Estimate the computational cost of iterating between two keys in a column family. The returned value is an opaque double - meaningful only for comparison with other values from the same function. It uses only in-memory metadata and performs no disk I/O.

```cpp
auto cf = db.getColumnFamily("my_cf");

double costA = cf.rangeCost("user:0000", "user:0999");
double costB = cf.rangeCost("user:1000", "user:1099");

if (costA < costB) {
    std::cout << "Range A is cheaper to iterate" << std::endl;
}
```

Key order does not matter - the function normalizes the range so `keyA > keyB` produces the same result as `keyB > keyA`.

**How it works**
- With block indexes enabled · Uses O(log B) binary search per overlapping SSTable to estimate block span
- Without block indexes · Falls back to byte-level key interpolation against SSTable min/max keys
- B+tree SSTables (`useBtree=true`) · Uses key interpolation against tree node counts, plus tree height as a seek cost
- Compressed SSTables receive a 1.5× weight multiplier for decompression overhead
- Each overlapping SSTable adds a small fixed cost for merge-heap operations
- The active memtable's entry count contributes a small in-memory cost

**Use cases**
- Query planning · Compare candidate key ranges to find the cheapest one to scan
- Load balancing · Distribute range scan work across threads by estimating per-range cost
- Adaptive prefetching · Decide how aggressively to prefetch based on range size
- Monitoring · Track how data distribution changes across key ranges over time

A cost of 0.0 means no overlapping SSTables or memtable entries were found for the range.

### Sync Modes

Control the durability vs performance tradeoff with three sync modes.

```cpp
auto cfConfig = tidesdb::ColumnFamilyConfig::defaultConfig();

// Fastest, least durable (OS handles flushing)
cfConfig.syncMode = tidesdb::SyncMode::None;

// Balanced performance with periodic background syncing
cfConfig.syncMode = tidesdb::SyncMode::Interval;
cfConfig.syncIntervalUs = 128000;  // Sync every 128ms (default)

// Most durable (fsync on every write)
cfConfig.syncMode = tidesdb::SyncMode::Full;

db.createColumnFamily("my_cf", cfConfig);
```

**Sync Mode Details**

- **`SyncMode::None`** · No explicit sync, relies on OS page cache (fastest, least durable)
    - Best for · Maximum throughput, acceptable data loss on crash
    - Use case · Caches, temporary data, reproducible workloads

- **`SyncMode::Interval`** · Periodic background syncing at configurable intervals (balanced)
    - Best for · Production workloads requiring good performance with bounded data loss
    - Use case · Most applications, configurable durability window
    - Single background sync thread monitors all column families using interval mode
    - Structural operations (flush, compaction, WAL rotation) always enforce durability
    - At most `syncIntervalUs` worth of data at risk on crash

- **`SyncMode::Full`** · Fsync on every write operation (slowest, most durable)
    - Best for · Critical data requiring maximum durability
    - Use case · Financial transactions, audit logs, critical metadata

**Sync Interval Examples**

```cpp
// Sync every 100ms (good for low-latency requirements)
cfConfig.syncMode = tidesdb::SyncMode::Interval;
cfConfig.syncIntervalUs = 100000;

// Sync every 128ms (default)
cfConfig.syncMode = tidesdb::SyncMode::Interval;
cfConfig.syncIntervalUs = 128000;

// Sync every 1 second (higher throughput, more data at risk)
cfConfig.syncMode = tidesdb::SyncMode::Interval;
cfConfig.syncIntervalUs = 1000000;
```

Regardless of sync mode, TidesDB **always** enforces durability for structural operations: memtable flush to SSTable, SSTable compaction and merging, WAL rotation, and column family metadata updates.

### Manual WAL Sync

`syncWal()` forces an immediate fsync of the active write-ahead log for a column family. This is useful for explicit durability control when using `SyncMode::None` or `SyncMode::Interval`.

```cpp
auto cf = db.getColumnFamily("my_cf");

// Force WAL durability after a batch of writes
cf.syncWal();
```

**When to use**
- Application-controlled durability · Sync the WAL at specific points (e.g., after a batch of related writes) when using `SyncMode::None` or `SyncMode::Interval`
- Pre-checkpoint · Ensure all buffered WAL data is on disk before taking a checkpoint
- Graceful shutdown · Flush WAL buffers before closing the database
- Critical writes · Force durability for specific high-value writes without using `SyncMode::Full` for all writes

**Behavior**
- Acquires a reference to the active memtable to safely access its WAL
- Calls `fdatasync` on the WAL file descriptor
- Thread-safe -- can be called concurrently from multiple threads
- If the memtable rotates during the call, retries with the new active memtable

## Object Store Mode

Object store mode allows TidesDB to store SSTables in a remote object store (S3, MinIO, GCS, or any S3-compatible service) while using local disk as a cache. This separates compute from storage and enables cold start recovery from the remote store. Object store mode requires unified memtable mode and is automatically enforced when a connector is set.

### Enabling Object Store Mode (Filesystem Connector)

```cpp
#include <tidesdb/tidesdb.hpp>

// create a filesystem connector (for testing and local replication)
tidesdb_objstore_t* store = tidesdb_objstore_fs_create("/mnt/nfs/tidesdb-objects");

auto osCfg = tidesdb::ObjectStoreConfig::defaultConfig();

tidesdb::Config config;
config.dbPath = "./mydb";
config.objectStore = store;
config.objectStoreConfig = osCfg;

tidesdb::TidesDB db(config);

// use the database normally -- SSTables are uploaded after flush
```

### Enabling Object Store Mode (S3/MinIO Connector)

Build with `-DTIDESDB_WITH_S3=ON` to enable the S3 connector. This requires libcurl and OpenSSL.

```cpp
#include <tidesdb/tidesdb.hpp>

tidesdb_objstore_t* s3 = tidesdb_objstore_s3_create(
    "s3.amazonaws.com",                         // endpoint
    "my-tidesdb-bucket",                        // bucket
    "production/db1/",                          // key prefix (or nullptr)
    "AKIAIOSFODNN7EXAMPLE",                     // access key
    "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", // secret key
    "us-east-1",                                // region
    1,                                          // use_ssl (HTTPS)
    0                                           // use_path_style (0 for AWS, 1 for MinIO)
);

auto osCfg = tidesdb::ObjectStoreConfig::defaultConfig();
osCfg.localCacheMaxBytes = 512 * 1024 * 1024; // 512MB local cache
osCfg.maxConcurrentUploads = 8;

tidesdb::Config config;
config.dbPath = "./mydb";
config.objectStore = s3;
config.objectStoreConfig = osCfg;

tidesdb::TidesDB db(config);
```

### MinIO Example

```cpp
tidesdb_objstore_t* minio = tidesdb_objstore_s3_create(
    "localhost:9000",   // MinIO endpoint
    "tidesdb-bucket",   // bucket
    nullptr,            // no key prefix
    "minioadmin",       // access key
    "minioadmin",       // secret key
    nullptr,            // region (nullptr for MinIO)
    0,                  // no SSL for local dev
    1                   // path-style URLs (required for MinIO)
);
```

### Object Store Configuration

Use `ObjectStoreConfig::defaultConfig()` for sensible defaults, then override fields as needed.

**Configuration fields**
- `localCachePath` · Local directory for cached SSTable files (empty = use db_path)
- `localCacheMaxBytes` · Maximum local cache size in bytes (0 = unlimited)
- `cacheOnRead` · Cache downloaded files locally (default: true)
- `cacheOnWrite` · Keep local copy after upload (default: true)
- `maxConcurrentUploads` · Number of parallel upload threads (default: 4)
- `maxConcurrentDownloads` · Number of parallel download threads (default: 8)
- `multipartThreshold` · Use multipart upload above this size (default: 64MB)
- `multipartPartSize` · Chunk size for multipart uploads (default: 8MB)
- `syncManifestToObject` · Upload MANIFEST after each compaction (default: true)
- `replicateWal` · Upload closed WAL segments for replication (default: true)
- `walUploadSync` · false = background WAL upload, true = block flush until uploaded (default: false)
- `walSyncThresholdBytes` · Sync active WAL to object store when it grows by this many bytes (default: 1MB, 0 = off)
- `walSyncOnCommit` · Upload WAL after every txn commit for RPO=0 replication (default: false)
- `replicaMode` · Enable read-only replica mode (default: false)
- `replicaSyncIntervalUs` · MANIFEST poll interval for replica sync in microseconds (default: 5s)
- `replicaReplayWal` · Replay WAL from object store for near-real-time reads on replicas (default: true)

### Per-CF Object Store Tuning

Column family configurations include two object store tuning fields.

- `objectLazyCompaction` · 1 to compact less aggressively for remote storage (default: 0)
- `objectPrefetchCompaction` · 1 to download all inputs before compaction merge (default: 1)

### Object Store Statistics

`getDbStats()` includes object store fields when a connector is active.

```cpp
auto dbStats = db.getDbStats();

if (dbStats.objectStoreEnabled) {
    std::cout << "Connector: " << dbStats.objectStoreConnector << std::endl;
    std::cout << "Total uploads: " << dbStats.totalUploads << std::endl;
    std::cout << "Upload failures: " << dbStats.totalUploadFailures << std::endl;
    std::cout << "Upload queue depth: " << dbStats.uploadQueueDepth << std::endl;
    std::cout << "Local cache: " << dbStats.localCacheBytesUsed
              << " / " << dbStats.localCacheBytesMax << " bytes" << std::endl;
}
```

### Cold Start Recovery

When the local database directory is empty but a connector is configured, TidesDB automatically discovers column families from the object store during recovery. It downloads MANIFEST and config files in parallel (one thread per CF), reconstructs the SSTable inventory, and fetches SSTable data on demand as queries arrive.

```cpp
// delete all local state, then reopen with the same connector
tidesdb::Config config;
config.dbPath = "./mydb";
config.objectStore = s3;
config.objectStoreConfig = osCfg;

tidesdb::TidesDB db(config);

// all data is available -- SSTables are fetched from the object store on demand
auto cf = db.getColumnFamily("my_cf");
```

### How It Works

- Object store mode requires unified memtable mode. Setting `objectStore` on the config automatically enables `unifiedMemtable`
- After each flush, SSTables are uploaded via an asynchronous upload pipeline with retry (3 attempts with exponential backoff) and post-upload verification
- Point lookups on remote SSTables fetch just the single needed klog block (~64KB) via one HTTP range request, cached in the clock cache for subsequent reads
- Iterators prefetch all needed SSTable files in parallel at creation time using bounded threads (`maxConcurrentDownloads`, default 8)
- A hash-indexed LRU local file cache manages disk usage, evicting least-recently-used SSTable file pairs when `localCacheMaxBytes` is set
- The MANIFEST is uploaded asynchronously after each flush and compaction for cold start recovery
- The reaper thread periodically syncs the active WAL based on write volume (`walSyncThresholdBytes`, default 1MB)

The S3 connector requires libcurl and OpenSSL. Enable it with `-DTIDESDB_WITH_S3=ON` during CMake configuration. The filesystem connector is always available.

## Replica Mode

Replica mode enables read-only nodes that follow a primary through the object store. The primary handles all writes while replicas poll for MANIFEST updates and replay WAL segments for near-real-time reads.

### Enabling Replica Mode

```cpp
auto osCfg = tidesdb::ObjectStoreConfig::defaultConfig();
osCfg.replicaMode = true;
osCfg.replicaSyncIntervalUs = 1000000; // 1 second sync interval
osCfg.replicaReplayWal = true;         // replay WAL for fresh reads

tidesdb::Config config;
config.dbPath = "./mydb_replica";
config.objectStore = s3; // same bucket as the primary
config.objectStoreConfig = osCfg;

tidesdb::TidesDB db(config);

// reads work normally
auto txn = db.beginTransaction();
auto cf = db.getColumnFamily("my_cf");
auto value = txn.get(cf, "key");

// writes are rejected with ErrorCode::Readonly
```

### Sync-on-Commit WAL (Primary Side)

For tighter replication lag, enable sync-on-commit on the primary so every committed write is uploaded to the object store immediately.

```cpp
auto osCfg = tidesdb::ObjectStoreConfig::defaultConfig();
osCfg.walSyncOnCommit = true; // RPO = 0, every commit is durable in S3

// replica sees committed data within one replicaSyncIntervalUs
```

### Promoting a Replica to Primary

When the primary fails, promote a replica to accept writes.

```cpp
// external health check detects primary is down
db.promoteToPrimary();

// now writes are accepted
auto txn = db.beginTransaction();
auto cf = db.getColumnFamily("my_cf");
txn.put(cf, "key", "value", -1);
txn.commit();
```

`promoteToPrimary()` performs a final MANIFEST sync and WAL replay, creates a local WAL for crash recovery, and atomically switches to primary mode. Throws `ErrorCode::InvalidArgs` if the node is already a primary.

### How Replica Sync Works

- The reaper thread polls the remote MANIFEST for each CF every `replicaSyncIntervalUs`
- New SSTables from the primary's flushes and compactions are added to the replica's levels
- SSTables compacted away on the primary are removed from the replica's levels
- When `replicaReplayWal` is enabled, the latest WAL is downloaded and replayed into the memtable for near-real-time reads
- WAL replay is idempotent using sequence numbers so entries already present are skipped
- SSTable data is not downloaded during sync -- it is fetched on demand via range_get for point lookups or prefetch for iterators

### Compression Algorithms

TidesDB supports multiple compression algorithms:

```cpp
auto cfConfig = tidesdb::ColumnFamilyConfig::defaultConfig();

cfConfig.compressionAlgorithm = tidesdb::CompressionAlgorithm::None;     // No compression
cfConfig.compressionAlgorithm = tidesdb::CompressionAlgorithm::LZ4;      // LZ4 standard (default)
cfConfig.compressionAlgorithm = tidesdb::CompressionAlgorithm::LZ4Fast;  // LZ4 fast mode
cfConfig.compressionAlgorithm = tidesdb::CompressionAlgorithm::Zstd;     // Zstandard
#ifndef __sun
cfConfig.compressionAlgorithm = tidesdb::CompressionAlgorithm::Snappy;   // Snappy (not available on SunOS)
#endif

db.createColumnFamily("my_cf", cfConfig);
```

**Choosing a Compression Algorithm**

| Workload | Recommended Algorithm | Rationale |
|----------|----------------------|-----------|
| General purpose | `CompressionAlgorithm::LZ4` | Best balance of speed and compression |
| Write-heavy | `CompressionAlgorithm::LZ4Fast` | Minimize CPU overhead on writes |
| Storage-constrained | `CompressionAlgorithm::Zstd` | Maximum compression ratio |
| Read-heavy | `CompressionAlgorithm::Zstd` | Reduce I/O bandwidth, decompression is fast |
| Pre-compressed data | `CompressionAlgorithm::None` | Avoid double compression overhead |
| CPU-constrained | `CompressionAlgorithm::None` or `LZ4Fast` | Minimize CPU usage |

Compression algorithm can be changed at runtime via `updateRuntimeConfig`, but the change only affects **new** SSTables. Existing SSTables retain their original compression and are decompressed correctly during reads. Different column families can use different compression algorithms.

### B+tree KLog Format (Optional)

Column families can optionally use a B+tree structure for the key log instead of the default block-based format. The B+tree klog format offers faster point lookups through O(log N) tree traversal rather than linear block scanning.

```cpp
auto cfConfig = tidesdb::ColumnFamilyConfig::defaultConfig();
cfConfig.useBtree = true;  // Enable B+tree klog format

db.createColumnFamily("btree_cf", cfConfig);
```

**Characteristics**
- Point lookups · O(log N) tree traversal with binary search at each node
- Range scans · Doubly-linked leaf nodes enable efficient bidirectional iteration
- Immutable · Tree is bulk-loaded from sorted memtable data during flush
- Compression · Nodes compress independently using the same algorithms (LZ4, LZ4-FAST, Zstd)
- Large values · Values exceeding `klogValueThreshold` are stored in vlog, same as block-based format
- Bloom filter · Works identically - checked before tree traversal

**When to use B+tree klog format**
- Read-heavy workloads with frequent point lookups
- Workloads where read latency is more important than write throughput
- Large SSTables where block scanning becomes expensive

**Tradeoffs**
- Slightly higher write amplification during flush (building tree structure)
- Larger metadata overhead per node compared to block-based format
- Block-based format may be faster for sequential scans of entire SSTables

Important · `useBtree` **cannot be changed** after column family creation. Different column families can use different formats.

## Error Handling

The C++ wrapper uses exceptions for error handling. All errors throw `tidesdb::Exception`.

```cpp
try {
    auto cf = db.getColumnFamily("my_cf");

    auto txn = db.beginTransaction();
    txn.put(cf, "key", "value", -1);
    txn.commit();
} catch (const tidesdb::Exception& e) {
    std::cerr << "Error: " << e.what() << std::endl;
    std::cerr << "Code: " << static_cast<int>(e.code()) << std::endl;
}
```

**Error Codes**
- `ErrorCode::Success` (0) · Operation successful
- `ErrorCode::Memory` (-1) · Memory allocation failed
- `ErrorCode::InvalidArgs` (-2) · Invalid arguments
- `ErrorCode::NotFound` (-3) · Key not found
- `ErrorCode::IO` (-4) · I/O error
- `ErrorCode::Corruption` (-5) · Data corruption
- `ErrorCode::Exists` (-6) · Resource already exists
- `ErrorCode::Conflict` (-7) · Transaction conflict
- `ErrorCode::TooLarge` (-8) · Key or value too large
- `ErrorCode::MemoryLimit` (-9) · Memory limit exceeded
- `ErrorCode::InvalidDB` (-10) · Invalid database handle
- `ErrorCode::Unknown` (-11) · Unknown error
- `ErrorCode::Locked` (-12) · Database is locked
- `ErrorCode::Readonly` (-13) · Database is read-only

**Error categories**
- `ErrorCode::Corruption` indicates data integrity issues requiring immediate attention
- `ErrorCode::Conflict` indicates transaction conflicts (retry may succeed)
- `ErrorCode::Memory`, `ErrorCode::MemoryLimit`, `ErrorCode::TooLarge` indicate resource constraints
- `ErrorCode::NotFound`, `ErrorCode::Exists` are normal operational conditions, not failures

## Complete Example

```cpp
#include <tidesdb/tidesdb.hpp>
#include <iostream>
#include <ctime>

int main() {
    try {
        tidesdb::Config config;
        config.dbPath = "./example_db";
        config.numFlushThreads = 1;
        config.numCompactionThreads = 1;
        config.logLevel = tidesdb::LogLevel::Info;
        config.blockCacheSize = 64 * 1024 * 1024;
        config.maxOpenSSTables = 256;

        tidesdb::TidesDB db(config);

        auto cfConfig = tidesdb::ColumnFamilyConfig::defaultConfig();
        cfConfig.writeBufferSize = 64 * 1024 * 1024;
        cfConfig.compressionAlgorithm = tidesdb::CompressionAlgorithm::LZ4;
        cfConfig.enableBloomFilter = true;
        cfConfig.bloomFPR = 0.01;
        cfConfig.syncMode = tidesdb::SyncMode::Interval;
        cfConfig.syncIntervalUs = 128000;

        db.createColumnFamily("users", cfConfig);

        auto cf = db.getColumnFamily("users");

        {
            auto txn = db.beginTransaction();
            txn.put(cf, "user:1", "Alice", -1);
            txn.put(cf, "user:2", "Bob", -1);

            auto ttl = std::time(nullptr) + 30;
            txn.put(cf, "session:abc", "temp_data", ttl);

            txn.commit();
        }

        {
            auto txn = db.beginTransaction();
            auto value = txn.get(cf, "user:1");
            std::string valueStr(value.begin(), value.end());
            std::cout << "user:1 = " << valueStr << std::endl;
        }

        {
            auto txn = db.beginTransaction();
            auto iter = txn.newIterator(cf);

            std::cout << "\nAll entries:" << std::endl;
            iter.seekToFirst();
            while (iter.valid()) {
                auto key = iter.key();
                auto value = iter.value();
                std::string keyStr(key.begin(), key.end());
                std::string valueStr(value.begin(), value.end());
                std::cout << "  " << keyStr << " = " << valueStr << std::endl;
                iter.next();
            }
        }

        auto stats = cf.getStats();
        std::cout << "\nColumn Family Statistics:" << std::endl;
        std::cout << "  Number of Levels: " << stats.numLevels << std::endl;
        std::cout << "  Memtable Size: " << stats.memtableSize << " bytes" << std::endl;
        std::cout << "  Uses B+tree: " << (stats.useBtree ? "yes" : "no") << std::endl;

        db.dropColumnFamily("users");

    } catch (const tidesdb::Exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
```

## Isolation Levels

TidesDB supports five MVCC isolation levels:

```cpp
auto txn = db.beginTransaction(tidesdb::IsolationLevel::ReadCommitted);
txn.commit();
```

**Available Isolation Levels**
- `IsolationLevel::ReadUncommitted` · Sees all data including uncommitted changes
- `IsolationLevel::ReadCommitted` · Sees only committed data (default)
- `IsolationLevel::RepeatableRead` · Consistent snapshot, phantom reads possible
- `IsolationLevel::Snapshot` · Write-write conflict detection
- `IsolationLevel::Serializable` · Full read-write conflict detection (SSI)

## Savepoints

Savepoints allow partial rollback within a transaction:

```cpp
auto txn = db.beginTransaction();

txn.put(cf, "key1", "value1", -1);

txn.savepoint("sp1");
txn.put(cf, "key2", "value2", -1);

txn.rollbackToSavepoint("sp1");

txn.releaseSavepoint("sp1");

txn.commit();
```

**Savepoint API**
- `savepoint(name)` · Create a savepoint
- `rollbackToSavepoint(name)` · Rollback to savepoint
- `releaseSavepoint(name)` · Release savepoint without rolling back

**Savepoint behavior**
- Savepoints capture the transaction state at a specific point
- Rolling back to a savepoint discards all operations after that savepoint
- Releasing a savepoint frees its resources without rolling back
- Multiple savepoints can be created with different names
- Creating a savepoint with an existing name updates that savepoint
- Savepoints are automatically freed when the transaction commits or rolls back

## Transaction Reset

`Transaction::reset` resets a committed or aborted transaction for reuse with a new isolation level. This avoids the overhead of freeing and reallocating transaction resources in hot loops.

```cpp
auto cf = db.getColumnFamily("my_cf");

auto txn = db.beginTransaction();

txn.put(cf, "key1", "value1", -1);
txn.commit();

txn.reset(tidesdb::IsolationLevel::ReadCommitted);

txn.put(cf, "key2", "value2", -1);
txn.commit();
```

**Behavior**
- The transaction must be committed or aborted before reset; resetting an active transaction throws an exception
- Internal buffers are retained to avoid reallocation
- A fresh transaction ID and snapshot sequence are assigned based on the new isolation level
- The isolation level can be changed on each reset (e.g., `ReadCommitted` to `RepeatableRead`)

**When to use**
- Batch processing · Reuse a single transaction across many commit cycles in a loop
- Connection pooling · Reset a transaction for a new request without reallocation
- High-throughput ingestion · Reduce malloc/free overhead in tight write loops

**Reset after rollback**

```cpp
auto txn = db.beginTransaction();

txn.put(cf, "key", "value", -1);
txn.rollback();

txn.reset(tidesdb::IsolationLevel::ReadCommitted);
txn.put(cf, "new_key", "new_value", -1);
txn.commit();
```

## Multi-Column-Family Transactions

TidesDB supports atomic transactions across multiple column families with true all-or-nothing semantics.

```cpp
auto usersCf = db.getColumnFamily("users");
auto ordersCf = db.getColumnFamily("orders");

auto txn = db.beginTransaction();

txn.put(usersCf, "user:1000", "John Doe", -1);

txn.put(ordersCf, "order:5000", "user:1000|product:A", -1);

txn.commit();
```

**Multi-CF guarantees**
- Either all CFs commit or none do (atomic)
- Automatically detected when operations span multiple CFs
- Uses global sequence numbers for atomic ordering

## Default Configuration

Get default configurations for database and column families.

```cpp
auto defaultDbConfig = tidesdb::TidesDB::defaultConfig();
defaultDbConfig.dbPath = "./mydb";
tidesdb::TidesDB db(defaultDbConfig);

auto defaultCfConfig = tidesdb::ColumnFamilyConfig::defaultConfig();
db.createColumnFamily("my_cf", defaultCfConfig);
```

`defaultConfig()` (both DB and CF variants) now mirrors the underlying C library defaults rather than duplicating constants in the binding. Fields like `maxConcurrentFlushes`, `tombstoneDensityMinEntries`, and the unified-memtable settings track the engine automatically. If you previously relied on hardcoded defaults when overriding only some fields, re-test after upgrading.

## Configuration Persistence

Load and save column family configuration from/to INI files.

```cpp
auto config = tidesdb::ColumnFamilyConfig::loadFromIni("config.ini", "my_cf");
db.createColumnFamily("my_cf", config);

auto cfConfig = tidesdb::ColumnFamilyConfig::defaultConfig();
cfConfig.writeBufferSize = 128 * 1024 * 1024;
tidesdb::ColumnFamilyConfig::saveToIni("config.ini", "my_cf", cfConfig);
```

## Custom Comparators

Register custom comparators for controlling key sort order.

```cpp
int myReverseCompare(const uint8_t* key1, size_t key1_size,
                     const uint8_t* key2, size_t key2_size, void* ctx) {
    (void)ctx;
    int result = memcmp(key1, key2, std::min(key1_size, key2_size));
    if (result == 0) {
        return (key1_size < key2_size) ? 1 : (key1_size > key2_size) ? -1 : 0;
    }
    return -result;  // Reverse order
}

db.registerComparator("reverse", myReverseCompare);

auto cfConfig = tidesdb::ColumnFamilyConfig::defaultConfig();
cfConfig.comparatorName = "reverse";
db.createColumnFamily("reverse_cf", cfConfig);
```

**Built-in comparators**
- `"memcmp"` (default) · Binary byte-by-byte comparison
- `"lexicographic"` · Null-terminated string comparison
- `"uint64"` · Unsigned 64-bit integer comparison
- `"int64"` · Signed 64-bit integer comparison
- `"reverse"` · Reverse binary comparison
- `"case_insensitive"` · Case-insensitive ASCII comparison

:::caution[Important]
Once a comparator is set for a column family, it **cannot be changed** without corrupting data.
:::

### Retrieving a Registered Comparator

Use `getComparator` to retrieve a previously registered comparator by name:

```cpp
tidesdb_comparator_fn fn = nullptr;
void* ctx = nullptr;

db.getComparator("timestamp_desc", &fn, &ctx);
// fn and ctx are now populated
```

**Use cases**
- Validation · Check if a comparator is registered before creating a column family
- Debugging · Verify comparator registration during development
- Dynamic configuration · Query available comparators at runtime

## Thread Pools

TidesDB uses separate thread pools for flush and compaction operations. Understanding the parallelism model is important for optimal configuration.

**Parallelism semantics**
- Cross-CF parallelism · Multiple flush/compaction workers CAN process different column families in parallel
- Within-CF serialization · A single column family can only have one flush and one compaction running at any time (enforced by atomic `isFlushing` and `isCompacting` flags)
- No intra-CF memtable parallelism · Even if a CF has multiple immutable memtables queued, they are flushed sequentially

**Thread pool sizing guidance**
- Single column family · Set `numFlushThreads = 1` and `numCompactionThreads = 1`. Additional threads provide no benefit since only one operation per CF can run at a time
- Multiple column families · Set thread counts up to the number of column families for maximum parallelism. With N column families and M workers (where M ≤ N), throughput scales linearly

**Configuration**
```cpp
tidesdb::Config config;
config.dbPath = "./mydb";
config.numFlushThreads = 2;                     // Flush thread pool size (default: 2)
config.numCompactionThreads = 2;                // Compaction thread pool size (default: 2)
config.blockCacheSize = 64 * 1024 * 1024;       // 64MB global block cache (default: 64MB)
config.maxOpenSSTables = 256;                   // LRU cache for SSTable objects (default: 256, each has 2 FDs)

tidesdb::TidesDB db(config);
```

`maxOpenSSTables` is a **storage-engine-level** configuration, not a column family configuration. It controls the LRU cache size for SSTable structures. Each SSTable uses 2 file descriptors (klog + vlog), so 256 SSTables = 512 file descriptors.

## Testing

```bash
cmake -S . -B build -DTIDESDB_CPP_BUILD_TESTS=ON
cmake --build build

cd build
ctest --output-on-failure

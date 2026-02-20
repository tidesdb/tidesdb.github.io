---
title: TidesDB C++ API Reference
description: C++ API reference for TidesDB
---

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/cplusplus.md).

<hr/>

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
    config.numFlushThreads = 2;
    config.numCompactionThreads = 2;
    config.logLevel = tidesdb::LogLevel::Info;
    config.blockCacheSize = 64 * 1024 * 1024;
    config.maxOpenSSTables = 256;

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
cfConfig.useBtree = false;  // Use block-based format (default), set true for B+tree klog format

db.createColumnFamily("my_cf", cfConfig);

db.dropColumnFamily("my_cf");
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

#### Multi-Operation Transactions

```cpp
auto cf = db.getColumnFamily("my_cf");

auto txn = db.beginTransaction();

txn.put(cf, "key1", "value1", -1);
txn.put(cf, "key2", "value2", -1);
txn.del(cf, "old_key");

txn.commit();
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

```cpp
auto iter = txn.newIterator(cf);

iter.seek("user:1000");

iter.seekForPrev("user:2000");
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

// Per-level statistics
for (int i = 0; i < stats.numLevels; ++i) {
    std::cout << "Level " << i << ": "
              << stats.levelNumSSTables[i] << " SSTables, "
              << stats.levelSizes[i] << " bytes, "
              << stats.levelKeyCounts[i] << " keys" << std::endl;
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
- `config` · Column family configuration (optional)

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

**Updatable settings** (safe to change at runtime):
- `writeBufferSize` · Memtable flush threshold
- `skipListMaxLevel` · Skip list level for new memtables
- `skipListProbability` · Skip list probability for new memtables
- `bloomFPR` · False positive rate for new SSTables
- `indexSampleRatio` · Index sampling ratio for new SSTables
- `syncMode` · Durability mode
- `syncIntervalUs` · Sync interval in microseconds

**Non-updatable settings** (would corrupt existing data):
- `compressionAlgorithm`, `enableBlockIndexes`, `enableBloomFilter`, `comparatorName`, `levelSizeRatio`, `klogValueThreshold`, `minLevels`, `dividingLevelOffset`, `blockIndexPrefixLen`, `l1FileCountTrigger`, `l0QueueStallThreshold`, `useBtree`

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

Estimate the computational cost of iterating between two keys in a column family. The returned value is an opaque double — meaningful only for comparison with other values from the same function. It uses only in-memory metadata and performs no disk I/O.

```cpp
auto cf = db.getColumnFamily("my_cf");

double costA = cf.rangeCost("user:0000", "user:0999");
double costB = cf.rangeCost("user:1000", "user:1099");

if (costA < costB) {
    std::cout << "Range A is cheaper to iterate" << std::endl;
}
```

**Key order does not matter** — the function normalizes the range so `keyA > keyB` produces the same result as `keyB > keyA`.

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

Control the durability vs performance tradeoff.

```cpp
auto cfConfig = tidesdb::ColumnFamilyConfig::defaultConfig();

cfConfig.syncMode = tidesdb::SyncMode::None;

cfConfig.syncMode = tidesdb::SyncMode::Interval;
cfConfig.syncIntervalUs = 128000;  // Sync every 128ms

cfConfig.syncMode = tidesdb::SyncMode::Full;

db.createColumnFamily("my_cf", cfConfig);
```

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

## Testing

```bash
cmake -S . -B build -DTIDESDB_CPP_BUILD_TESTS=ON
cmake --build build

cd build
ctest --output-on-failure

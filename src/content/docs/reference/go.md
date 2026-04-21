---
title: TidesDB GO API Reference
description: GO API reference for TidesDB
---

<div class="no-print">

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/go.md).

<hr/>

</div>

## Getting Started

### Prerequisites

You **must** have the TidesDB shared C library installed on your system.  You can find the installation instructions [here](/reference/building/#_top).

### Installation

```bash
go get github.com/tidesdb/tidesdb-go
```

### Custom Installation Paths

If you installed TidesDB to a non-standard location, you can specify custom paths using CGO environment variables:

```bash
# Set custom include and library paths
export CGO_CFLAGS="-I/custom/path/include"
export CGO_LDFLAGS="-L/custom/path/lib -ltidesdb"

# Then install/build
go get github.com/tidesdb/tidesdb-go
```

**Custom prefix installation**
```bash
# Install TidesDB to custom location
cd tidesdb
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/opt/tidesdb
cmake --build build
sudo cmake --install build

# Configure Go to use custom location
export CGO_CFLAGS="-I/opt/tidesdb/include"
export CGO_LDFLAGS="-L/opt/tidesdb/lib -ltidesdb"
export LD_LIBRARY_PATH="/opt/tidesdb/lib:$LD_LIBRARY_PATH"  # Linux
# or
export DYLD_LIBRARY_PATH="/opt/tidesdb/lib:$DYLD_LIBRARY_PATH"  # macOS

go get github.com/tidesdb/tidesdb-go
```

## Initialization

TidesDB supports **optional** explicit initialization. If not called, TidesDB auto-initializes with the system allocator on the first `Open`.

```go
// Initialize TidesDB (optional - auto-initializes if not called)
err := tidesdb.Init()
if err != nil {
    log.Fatal(err)
}

// ... use TidesDB ...

// Finalize after all operations are complete (optional)
tidesdb.Finalize()
```

:::note[Auto-initialization]
If `Init()` is not called, TidesDB will auto-initialize with the system allocator on the first call to `Open()`.
:::

## Usage

### Opening and Closing a Database

```go
package main

import (
    "fmt"
    "log"
    
    tidesdb "github.com/tidesdb/tidesdb-go"
)

func main() {
    config := tidesdb.Config{
        DBPath:               "./mydb",
        NumFlushThreads:      2,
        NumCompactionThreads: 2,
        LogLevel:             tidesdb.LogInfo,
        BlockCacheSize:       64 * 1024 * 1024,
        MaxOpenSSTables:      256,
        MaxMemoryUsage:       0,                    // Global memory limit in bytes (0 = auto, 80% of system RAM)
        LogToFile:            false,                // Write logs to file instead of stderr
        LogTruncationAt:      24 * 1024 * 1024,     // Log file truncation size (24MB default)
        ObjectStore:          nil,                  // Object store connector (nil = local only)
        ObjectStoreConfig:    nil,                  // Object store behavior config (nil = defaults)
    }
    
    db, err := tidesdb.Open(config)
    if err != nil {
        log.Fatal(err)
    }
    defer db.Close()
    
    fmt.Println("Database opened successfully")
}
```

### Default Configuration

Use `DefaultConfig()` to get a configuration with sensible defaults, then override specific fields as needed:

```go
config := tidesdb.DefaultConfig()
config.DBPath = "./mydb"
config.LogLevel = tidesdb.LogWarn  // Override: only warnings and errors

db, err := tidesdb.Open(config)
if err != nil {
    log.Fatal(err)
}
defer db.Close()
```

### Backup

Create an on-disk snapshot of an open database without blocking normal reads/writes.

```go
err := db.Backup("./mydb_backup")
if err != nil {
    log.Fatal(err)
}
```

**Behavior**
- Requires the backup directory to be non-existent or empty
- Does not copy the LOCK file, so the backup can be opened normally
- Database stays open and usable during backup
- The backup represents the database state after the final flush/compaction drain

### Checkpoint

Create a lightweight, near-instant snapshot of an open database using hard links instead of copying SSTable data.

```go
err := db.Checkpoint("./mydb_checkpoint")
if err != nil {
    log.Fatal(err)
}
```

**Behavior**
- Requires the checkpoint directory to be non-existent or empty
- For each column family:
  - Flushes the active memtable so all data is in SSTables
  - Halts compactions to ensure a consistent view of live SSTable files
  - Hard links all SSTable files (`.klog` and `.vlog`) into the checkpoint directory
  - Copies small metadata files (manifest, config) into the checkpoint directory
  - Resumes compactions
- Falls back to file copy if hard linking fails (e.g., cross-filesystem)
- Database stays open and usable during checkpoint
- The checkpoint can be opened as a normal TidesDB database with `Open`

**Checkpoint vs Backup**

| | `Backup` | `Checkpoint` |
|--|---|---|
| Speed | Copies every SSTable byte-by-byte | Near-instant (hard links, O(1) per file) |
| Disk usage | Full independent copy | No extra disk until compaction removes old SSTables |
| Portability | Can be moved to another filesystem or machine | Same filesystem only (hard link requirement) |
| Use case | Archival, disaster recovery, remote shipping | Fast local snapshots, point-in-time reads, streaming backups |

**Notes**
- The checkpoint represents the database state at the point all memtables are flushed and compactions are halted
- Hard-linked files share storage with the live database. Deleting the original database does not affect the checkpoint (hard link semantics)

### Creating and Dropping Column Families

Column families are isolated key-value stores with independent configuration.

```go
cfConfig := tidesdb.DefaultColumnFamilyConfig()
err := db.CreateColumnFamily("my_cf", cfConfig)
if err != nil {
    log.Fatal(err)
}

// Create with custom configuration based on defaults
cfConfig := tidesdb.DefaultColumnFamilyConfig()

// You can modify the configuration as needed
cfConfig.WriteBufferSize = 128 * 1024 * 1024   
cfConfig.LevelSizeRatio = 10                    
cfConfig.MinLevels = 5                           
cfConfig.CompressionAlgorithm = tidesdb.LZ4Compression
cfConfig.EnableBloomFilter = true
cfConfig.BloomFPR = 0.01                        
cfConfig.EnableBlockIndexes = true
cfConfig.SyncMode = tidesdb.SyncInterval
cfConfig.SyncIntervalUs = 128000                  
cfConfig.DefaultIsolationLevel = tidesdb.IsolationReadCommitted
cfConfig.DividingLevelOffset = 2                   // Compaction dividing level offset
cfConfig.KlogValueThreshold = 512                  // Values > 512 bytes go to vlog
cfConfig.BlockIndexPrefixLen = 16                  // Block index prefix length
cfConfig.MinDiskSpace = 100 * 1024 * 1024          // Minimum disk space required (100MB)
cfConfig.L1FileCountTrigger = 4                    // L1 file count trigger for compaction
cfConfig.L0QueueStallThreshold = 20                // L0 queue stall threshold
cfConfig.UseBtree = 0                              // Use B+tree format for klog (0 = block-based)
cfConfig.ObjectLazyCompaction = 0                  // Less aggressive compaction in object store mode
cfConfig.ObjectPrefetchCompaction = 1              // Download all inputs before merge

err = db.CreateColumnFamily("my_cf", cfConfig)
if err != nil {
    log.Fatal(err)
}

err = db.DropColumnFamily("my_cf")
if err != nil {
    log.Fatal(err)
}
```

**Dropping by pointer** (faster when you already hold the `ColumnFamily` pointer, skips internal name lookup):

```go
cf, err := db.GetColumnFamily("my_cf")
if err != nil {
    log.Fatal(err)
}

err = db.DeleteColumnFamily(cf)
if err != nil {
    log.Fatal(err)
}
```

### Renaming a Column Family

Atomically rename a column family and its underlying directory. The operation waits for any in-progress flush or compaction to complete before renaming.

```go
err := db.RenameColumnFamily("old_name", "new_name")
if err != nil {
    log.Fatal(err)
}
```

### Cloning a Column Family

Create a complete copy of an existing column family with a new name. The clone contains all the data from the source at the time of cloning.

```go
err := db.CloneColumnFamily("source_cf", "cloned_cf")
if err != nil {
    log.Fatal(err)
}

// Both column families now exist independently
sourceCF, _ := db.GetColumnFamily("source_cf")
clonedCF, _ := db.GetColumnFamily("cloned_cf")
```

**Behavior**
- Flushes the source column family's memtable to ensure all data is on disk
- Waits for any in-progress flush or compaction to complete
- Copies all SSTable files to the new directory
- The clone is completely independent; modifications to one do not affect the other

**Use cases**
- Testing · Create a copy of production data for testing without affecting the original
- Branching · Create a snapshot of data before making experimental changes
- Migration · Clone data before schema or configuration changes
- Backup verification · Clone and verify data integrity without modifying the source

**Return values**
- `nil` · Clone completed successfully
- Error with `ErrNotFound` · Source column family doesn't exist
- Error with `ErrExists` · Destination column family already exists
- Error with `ErrInvalidArgs` · Invalid arguments (nil pointers or same source/destination name)
- Error with `ErrIO` · Failed to copy files or create directory

### CRUD Operations

All operations in TidesDB are performed through transactions for ACID guarantees.

#### Writing Data

```go
cf, err := db.GetColumnFamily("my_cf")
if err != nil {
    log.Fatal(err)
}

txn, err := db.BeginTxn()
if err != nil {
    log.Fatal(err)
}
defer txn.Free()

// Put a key-value pair (TTL -1 means no expiration)
err = txn.Put(cf, []byte("key"), []byte("value"), -1)
if err != nil {
    log.Fatal(err)
}

err = txn.Commit()
if err != nil {
    log.Fatal(err)
}
```

#### Writing with TTL

```go
import "time"

cf, err := db.GetColumnFamily("my_cf")
if err != nil {
    log.Fatal(err)
}

txn, err := db.BeginTxn()
if err != nil {
    log.Fatal(err)
}
defer txn.Free()

// Set expiration time (Unix timestamp)
ttl := time.Now().Add(10 * time.Second).Unix()

err = txn.Put(cf, []byte("temp_key"), []byte("temp_value"), ttl)
if err != nil {
    log.Fatal(err)
}

err = txn.Commit()
if err != nil {
    log.Fatal(err)
}
```

**TTL Examples**
```go
ttl := int64(-1)

// Expire in 5 minutes
ttl := time.Now().Add(5 * time.Minute).Unix()

// Expire in 1 hour
ttl := time.Now().Add(1 * time.Hour).Unix()

ttl := time.Date(2026, 12, 31, 23, 59, 59, 0, time.UTC).Unix()
```

#### Reading Data

```go
cf, err := db.GetColumnFamily("my_cf")
if err != nil {
    log.Fatal(err)
}

txn, err := db.BeginTxn()
if err != nil {
    log.Fatal(err)
}
defer txn.Free()

value, err := txn.Get(cf, []byte("key"))
if err != nil {
    log.Fatal(err)
}

fmt.Printf("Value: %s\n", value)
```

#### Deleting Data

```go
cf, err := db.GetColumnFamily("my_cf")
if err != nil {
    log.Fatal(err)
}

txn, err := db.BeginTxn()
if err != nil {
    log.Fatal(err)
}
defer txn.Free()

err = txn.Delete(cf, []byte("key"))
if err != nil {
    log.Fatal(err)
}

err = txn.Commit()
if err != nil {
    log.Fatal(err)
}
```

#### Multi-Operation Transactions

```go
cf, err := db.GetColumnFamily("my_cf")
if err != nil {
    log.Fatal(err)
}

txn, err := db.BeginTxn()
if err != nil {
    log.Fatal(err)
}
defer txn.Free()

// Multiple operations in one transaction, across column families as well
err = txn.Put(cf, []byte("key1"), []byte("value1"), -1)
if err != nil {
    txn.Rollback()
    log.Fatal(err)
}

err = txn.Put(cf, []byte("key2"), []byte("value2"), -1)
if err != nil {
    txn.Rollback()
    log.Fatal(err)
}

err = txn.Delete(cf, []byte("old_key"))
if err != nil {
    txn.Rollback()
    log.Fatal(err)
}

// Commit atomically -- all or nothing
err = txn.Commit()
if err != nil {
    log.Fatal(err)
}
```

### Iterating Over Data

Iterators provide efficient bidirectional traversal over key-value pairs.

#### Forward Iteration

```go
cf, err := db.GetColumnFamily("my_cf")
if err != nil {
    log.Fatal(err)
}

txn, err := db.BeginTxn()
if err != nil {
    log.Fatal(err)
}
defer txn.Free()

iter, err := txn.NewIterator(cf)
if err != nil {
    log.Fatal(err)
}
defer iter.Free()

iter.SeekToFirst()

for iter.Valid() {
    key, err := iter.Key()
    if err != nil {
        log.Fatal(err)
    }
    
    value, err := iter.Value()
    if err != nil {
        log.Fatal(err)
    }
    
    fmt.Printf("Key: %s, Value: %s\n", key, value)
    
    iter.Next()
}
```

#### Backward Iteration

```go
cf, err := db.GetColumnFamily("my_cf")
if err != nil {
    log.Fatal(err)
}

txn, err := db.BeginTxn()
if err != nil {
    log.Fatal(err)
}
defer txn.Free()

iter, err := txn.NewIterator(cf)
if err != nil {
    log.Fatal(err)
}
defer iter.Free()

iter.SeekToLast()

for iter.Valid() {
    key, err := iter.Key()
    if err != nil {
        log.Fatal(err)
    }
    
    value, err := iter.Value()
    if err != nil {
        log.Fatal(err)
    }
    
    fmt.Printf("Key: %s, Value: %s\n", key, value)
    
    iter.Prev()
}
```

#### Seek Operations

Seek to a specific key or key range without scanning from the beginning.

```go
iter, err := txn.NewIterator(cf)
if err != nil {
    log.Fatal(err)
}
defer iter.Free()

// Seek to first key >= target
err = iter.Seek([]byte("user:1000"))
if err != nil {
    log.Fatal(err)
}

if iter.Valid() {
    key, _ := iter.Key()
    fmt.Printf("Found: %s\n", key)
}

// Seek to last key <= target (for reverse iteration)
err = iter.SeekForPrev([]byte("user:2000"))
if err != nil {
    log.Fatal(err)
}

for iter.Valid() {
    key, _ := iter.Key()
    fmt.Printf("Reverse: %s\n", key)
    iter.Prev()
}
```

#### Prefix Seeking

```go
iter, err := txn.NewIterator(cf)
if err != nil {
    log.Fatal(err)
}
defer iter.Free()

prefix := []byte("user:")
err = iter.Seek(prefix)
if err != nil {
    log.Fatal(err)
}

for iter.Valid() {
    key, _ := iter.Key()
    
    // Stop when keys no longer match prefix
    if !bytes.HasPrefix(key, prefix) {
        break
    }
    
    value, _ := iter.Value()
    fmt.Printf("%s = %s\n", key, value)
    
    iter.Next()
}
```

#### Combined Key-Value Retrieval

`KeyValue` retrieves both the current key and value from the iterator in a single call. This is more efficient than calling `Key()` and `Value()` separately.

```go
iter, err := txn.NewIterator(cf)
if err != nil {
    log.Fatal(err)
}
defer iter.Free()

iter.SeekToFirst()

for iter.Valid() {
    key, value, err := iter.KeyValue()
    if err != nil {
        log.Fatal(err)
    }

    fmt.Printf("Key: %s, Value: %s\n", key, value)

    iter.Next()
}
```

### Getting Column Family Statistics

Retrieve detailed statistics about a column family.

```go
cf, err := db.GetColumnFamily("my_cf")
if err != nil {
    log.Fatal(err)
}

stats, err := cf.GetStats()
if err != nil {
    log.Fatal(err)
}

fmt.Printf("Number of Levels: %d\n", stats.NumLevels)
fmt.Printf("Memtable Size: %d bytes\n", stats.MemtableSize)
fmt.Printf("Total Keys: %d\n", stats.TotalKeys)
fmt.Printf("Total Data Size: %d bytes\n", stats.TotalDataSize)
fmt.Printf("Avg Key Size: %.2f bytes\n", stats.AvgKeySize)
fmt.Printf("Avg Value Size: %.2f bytes\n", stats.AvgValueSize)
fmt.Printf("Read Amplification: %.2f\n", stats.ReadAmp)
fmt.Printf("Hit Rate: %.2f%%\n", stats.HitRate * 100)

// B+tree statistics (only populated if UseBtree=1)
if stats.UseBtree {
    fmt.Printf("B+tree Total Nodes: %d\n", stats.BtreeTotalNodes)
    fmt.Printf("B+tree Max Height: %d\n", stats.BtreeMaxHeight)
    fmt.Printf("B+tree Avg Height: %.2f\n", stats.BtreeAvgHeight)
}

// Per-level statistics
for i := 0; i < stats.NumLevels; i++ {
    fmt.Printf("Level %d: %d SSTables, %d bytes, %d keys\n",
        i+1, stats.LevelNumSSTables[i], stats.LevelSizes[i], stats.LevelKeyCounts[i])
}

if stats.Config != nil {
    fmt.Printf("Write Buffer Size: %d\n", stats.Config.WriteBufferSize)
    fmt.Printf("Compression: %d\n", stats.Config.CompressionAlgorithm)
    fmt.Printf("Bloom Filter: %v\n", stats.Config.EnableBloomFilter)
    fmt.Printf("Sync Mode: %d\n", stats.Config.SyncMode)
    fmt.Printf("Use B+tree: %d\n", stats.Config.UseBtree)
}
```

**Stats Fields**
| Field | Type | Description |
|-------|------|-------------|
| `NumLevels` | `int` | Number of LSM levels |
| `MemtableSize` | `uint64` | Current memtable size in bytes |
| `LevelSizes` | `[]uint64` | Array of per-level total sizes |
| `LevelNumSSTables` | `[]int` | Array of per-level SSTable counts |
| `LevelKeyCounts` | `[]uint64` | Array of per-level key counts |
| `Config` | `*ColumnFamilyConfig` | Full column family configuration |
| `TotalKeys` | `uint64` | Total keys across memtable and all SSTables |
| `TotalDataSize` | `uint64` | Total data size (klog + vlog) in bytes |
| `AvgKeySize` | `float64` | Estimated average key size in bytes |
| `AvgValueSize` | `float64` | Estimated average value size in bytes |
| `ReadAmp` | `float64` | Read amplification factor |
| `HitRate` | `float64` | Block cache hit rate (0.0 to 1.0) |
| `UseBtree` | `bool` | Whether column family uses B+tree klog format |
| `BtreeTotalNodes` | `uint64` | Total B+tree nodes across all SSTables |
| `BtreeMaxHeight` | `uint32` | Maximum tree height across all SSTables |
| `BtreeAvgHeight` | `float64` | Average tree height across all SSTables |

### Getting Block Cache Statistics

Get statistics for the global block cache (shared across all column families).

```go
cacheStats, err := db.GetCacheStats()
if err != nil {
    log.Fatal(err)
}

if cacheStats.Enabled {
    fmt.Printf("Cache enabled: yes\n")
    fmt.Printf("Total entries: %d\n", cacheStats.TotalEntries)
    fmt.Printf("Total bytes: %.2f MB\n", float64(cacheStats.TotalBytes) / (1024.0 * 1024.0))
    fmt.Printf("Hits: %d\n", cacheStats.Hits)
    fmt.Printf("Misses: %d\n", cacheStats.Misses)
    fmt.Printf("Hit rate: %.1f%%\n", cacheStats.HitRate * 100.0)
    fmt.Printf("Partitions: %d\n", cacheStats.NumPartitions)
} else {
    fmt.Printf("Cache enabled: no (BlockCacheSize = 0)\n")
}
```

**CacheStats Fields**
| Field | Type | Description |
|-------|------|-------------|
| `Enabled` | `bool` | Whether block cache is active |
| `TotalEntries` | `uint64` | Number of cached blocks |
| `TotalBytes` | `uint64` | Total memory used by cached blocks |
| `Hits` | `uint64` | Number of cache hits |
| `Misses` | `uint64` | Number of cache misses |
| `HitRate` | `float64` | Hit rate as a decimal (0.0 to 1.0) |
| `NumPartitions` | `uint64` | Number of cache partitions |

### Database-Level Statistics

Get aggregate statistics across the entire database instance.

```go
dbStats, err := db.GetDbStats()
if err != nil {
    log.Fatal(err)
}

fmt.Printf("Column families: %d\n", dbStats.NumColumnFamilies)
fmt.Printf("Total memory: %d bytes\n", dbStats.TotalMemory)
fmt.Printf("Resolved memory limit: %d bytes\n", dbStats.ResolvedMemoryLimit)
fmt.Printf("Memory pressure level: %d\n", dbStats.MemoryPressureLevel)
fmt.Printf("Global sequence: %d\n", dbStats.GlobalSeq)
fmt.Printf("Flush queue: %d pending\n", dbStats.FlushQueueSize)
fmt.Printf("Compaction queue: %d pending\n", dbStats.CompactionQueueSize)
fmt.Printf("Total SSTables: %d\n", dbStats.TotalSstableCount)
fmt.Printf("Total data size: %d bytes\n", dbStats.TotalDataSizeBytes)
fmt.Printf("Open SSTable handles: %d\n", dbStats.NumOpenSstables)
fmt.Printf("In-flight txn memory: %d bytes\n", dbStats.TxnMemoryBytes)
fmt.Printf("Immutable memtables: %d\n", dbStats.TotalImmutableCount)
fmt.Printf("Memtable bytes: %d\n", dbStats.TotalMemtableBytes)
```

**DbStats Fields**
| Field | Type | Description |
|-------|------|-------------|
| `NumColumnFamilies` | `int` | Number of column families |
| `TotalMemory` | `uint64` | System total memory |
| `AvailableMemory` | `uint64` | System available memory at open time |
| `ResolvedMemoryLimit` | `uint64` | Resolved memory limit (auto or configured) |
| `MemoryPressureLevel` | `int` | Current memory pressure (0=normal, 1=elevated, 2=high, 3=critical) |
| `FlushPendingCount` | `int` | Number of pending flush operations (queued + in-flight) |
| `TotalMemtableBytes` | `int64` | Total bytes in active memtables across all CFs |
| `TotalImmutableCount` | `int` | Total immutable memtables across all CFs |
| `TotalSstableCount` | `int` | Total SSTables across all CFs and levels |
| `TotalDataSizeBytes` | `uint64` | Total data size (klog + vlog) across all CFs |
| `NumOpenSstables` | `int` | Number of currently open SSTable file handles |
| `GlobalSeq` | `uint64` | Current global sequence number |
| `TxnMemoryBytes` | `int64` | Bytes held by in-flight transactions |
| `CompactionQueueSize` | `uint64` | Number of pending compaction tasks |
| `FlushQueueSize` | `uint64` | Number of pending flush tasks in queue |
| `UnifiedMemtableEnabled` | `bool` | Whether unified memtable mode is active |
| `UnifiedMemtableBytes` | `int64` | Bytes in unified active memtable |
| `UnifiedImmutableCount` | `int` | Number of unified immutable memtables |
| `UnifiedIsFlushing` | `bool` | Whether unified memtable is currently flushing/rotating |
| `UnifiedNextCFIndex` | `uint32` | Next CF index to be assigned in unified mode |
| `UnifiedWalGeneration` | `uint64` | Current unified WAL generation counter |
| `ObjectStoreEnabled` | `bool` | Whether object store mode is active |
| `ObjectStoreConnector` | `string` | Connector name ("s3", "gcs", "fs", etc.) |
| `LocalCacheBytesUsed` | `uint64` | Current local file cache usage in bytes |
| `LocalCacheBytesMax` | `uint64` | Configured maximum local cache size in bytes |
| `LocalCacheNumFiles` | `int` | Number of files tracked in local cache |
| `LastUploadedGeneration` | `uint64` | Highest WAL generation confirmed uploaded |
| `UploadQueueDepth` | `uint64` | Number of pending upload jobs in the queue |
| `TotalUploads` | `uint64` | Lifetime count of objects uploaded to object store |
| `TotalUploadFailures` | `uint64` | Lifetime count of permanently failed uploads |
| `ReplicaMode` | `bool` | Whether running in read-only replica mode |

:::note[Stack Allocated]
Unlike `GetStats` (which heap-allocates), `GetDbStats` fills a caller-provided struct. No free is needed.
:::

### Range Cost Estimation

`RangeCost` estimates the computational cost of iterating between two keys in a column family. The returned value is an opaque double - meaningful only for comparison with other values from the same function. It uses only in-memory metadata and performs no disk I/O.

```go
cf, err := db.GetColumnFamily("my_cf")
if err != nil {
    log.Fatal(err)
}

costA, err := cf.RangeCost([]byte("user:0000"), []byte("user:0999"))
if err != nil {
    log.Fatal(err)
}

costB, err := cf.RangeCost([]byte("user:1000"), []byte("user:1099"))
if err != nil {
    log.Fatal(err)
}

if costA < costB {
    fmt.Println("Range A is cheaper to iterate")
}
```

**Behavior**
- Key order does not matter - the function normalizes the range so `keyA > keyB` produces the same result as `keyB > keyA`
- With block indexes enabled, uses O(log B) binary search per overlapping SSTable
- Without block indexes, falls back to byte-level key interpolation
- B+tree SSTables use key interpolation against tree node counts plus tree height as seek cost
- Compressed SSTables receive a 1.5× weight multiplier for decompression overhead
- A cost of 0.0 means no overlapping SSTables or memtable entries were found for the range

**Use cases**
- Query planning · Compare candidate key ranges to find the cheapest one to scan
- Load balancing · Distribute range scan work across goroutines by estimating per-range cost
- Adaptive prefetching · Decide how aggressively to prefetch based on range size
- Monitoring · Track how data distribution changes across key ranges over time

### Getting a Comparator

Retrieve a registered comparator by name. Returns whether the comparator is registered.

```go
found, err := db.GetComparator("memcmp")
if err != nil {
    log.Fatal(err)
}

if found {
    fmt.Println("Comparator 'memcmp' is registered")
}
```

**Built-in comparators** (automatically registered on database open):
- `"memcmp"` · Binary byte-by-byte comparison (default)
- `"lexicographic"` · Null-terminated string comparison
- `"uint64"` · Unsigned 64-bit integer comparison
- `"int64"` · Signed 64-bit integer comparison
- `"reverse"` · Reverse binary comparison
- `"case_insensitive"` · Case-insensitive ASCII comparison

**Use cases**
- Validation · Check if a comparator is registered before creating a column family
- Debugging · Verify comparator registration during development
- Dynamic configuration · Query available comparators at runtime

### Listing Column Families

```go
cfList, err := db.ListColumnFamilies()
if err != nil {
    log.Fatal(err)
}

fmt.Println("Available column families:")
for _, name := range cfList {
    fmt.Printf("  - %s\n", name)
}
```

### Compaction

#### Manual Compaction

```go
cf, err := db.GetColumnFamily("my_cf")
if err != nil {
    log.Fatal(err)
}

// Manually trigger compaction (queues compaction from L1+)
err = cf.Compact()
if err != nil {
    log.Printf("Compaction note: %v", err)
}
```

#### Manual Memtable Flush

```go
cf, err := db.GetColumnFamily("my_cf")
if err != nil {
    log.Fatal(err)
}

// Manually trigger memtable flush (queues memtable for sorted run to disk (L1))
err = cf.FlushMemtable()
if err != nil {
    log.Printf("Flush note: %v", err)
}
```

#### Checking Flush/Compaction Status

Check if a column family currently has flush or compaction operations in progress.

```go
cf, err := db.GetColumnFamily("my_cf")
if err != nil {
    log.Fatal(err)
}

// Check if flushing is in progress
if cf.IsFlushing() {
    fmt.Println("Flush in progress")
}

// Check if compaction is in progress
if cf.IsCompacting() {
    fmt.Println("Compaction in progress")
}
```

#### Purge Column Family

`PurgeCF` forces a synchronous flush and aggressive compaction for a single column family. Unlike `FlushMemtable` and `Compact` (which are non-blocking), `PurgeCF` blocks until all flush and compaction I/O is complete.

```go
cf, err := db.GetColumnFamily("my_cf")
if err != nil {
    log.Fatal(err)
}

err = cf.PurgeCF()
if err != nil {
    log.Fatal(err)
}
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

`Purge` forces a synchronous flush and aggressive compaction for **all** column families, then drains both the global flush and compaction queues.

```go
err := db.Purge()
if err != nil {
    log.Fatal(err)
}
// All CFs flushed and compacted, all queues drained
```

**Behavior**
1. Calls `PurgeCF` on each column family
2. Drains the global flush queue (waits for queue size and pending count to reach 0)
3. Drains the global compaction queue (waits for queue size to reach 0)

**Return values**
- `nil` if all column families purged successfully
- First non-nil error if any CF fails (continues processing remaining CFs)

:::tip[Purge vs Manual Flush + Compact]
`FlushMemtable` and `Compact` are non-blocking - they enqueue work and return immediately. `PurgeCF` and `Purge` are synchronous - they block until all work is complete. Use purge when you need a guarantee that all data is on disk and compacted before proceeding.
:::

### Updating Runtime Configuration

Update runtime-safe configuration settings for a column family. Changes apply to new operations only.

```go
cf, err := db.GetColumnFamily("my_cf")
if err != nil {
    log.Fatal(err)
}

newConfig := tidesdb.DefaultColumnFamilyConfig()
newConfig.WriteBufferSize = 256 * 1024 * 1024  
newConfig.SkipListMaxLevel = 16
newConfig.BloomFPR = 0.001                      // 0.1% false positive rate

err = cf.UpdateRuntimeConfig(newConfig, true)
if err != nil {
    log.Fatal(err)
}
```

**Updatable settings** (safe to change at runtime):
- `WriteBufferSize` · Memtable flush threshold
- `SkipListMaxLevel` · Skip list level for new memtables
- `SkipListProbability` · Skip list probability for new memtables
- `BloomFPR` · False positive rate for new SSTables
- `IndexSampleRatio` · Index sampling ratio for new SSTables
- `SyncMode` · Durability mode
- `SyncIntervalUs` · Sync interval in microseconds

### Commit Hook (Change Data Capture)

`SetCommitHook` registers a callback that fires synchronously after every transaction commit on a column family. The hook receives the full batch of committed operations atomically, enabling real-time change data capture without WAL parsing or external log consumers.

```go
cf, err := db.GetColumnFamily("my_cf")
if err != nil {
    log.Fatal(err)
}

err = cf.SetCommitHook(func(ops []tidesdb.CommitOp, commitSeq uint64) int {
    for _, op := range ops {
        if op.IsDelete {
            fmt.Printf("[seq=%d] DELETE key=%s\n", commitSeq, string(op.Key))
        } else {
            fmt.Printf("[seq=%d] PUT key=%s value=%s ttl=%d\n",
                commitSeq, string(op.Key), string(op.Value), op.TTL)
        }
    }
    return 0 // 0 = success; non-zero is logged as warning
})
if err != nil {
    log.Fatal(err)
}

// Normal writes now trigger the hook automatically
txn, _ := db.BeginTxn()
txn.Put(cf, []byte("user:1000"), []byte("John Doe"), -1)
txn.Commit() // hook fires here
txn.Free()

// Detach the hook
err = cf.ClearCommitHook()
if err != nil {
    log.Fatal(err)
}
```

**CommitOp fields**

| Field | Type | Description |
|-------|------|-------------|
| `Key` | `[]byte` | Key data (copied; safe to retain after callback returns) |
| `Value` | `[]byte` | Value data (`nil` for deletes; copied; safe to retain) |
| `TTL` | `int64` | Time-to-live Unix timestamp (0 = no expiry) |
| `IsDelete` | `bool` | `true` if this is a delete operation, `false` for put |

**Behavior**
- The hook fires after WAL write, memtable apply, and commit status marking are complete - the data is fully durable before the callback runs
- Hook failure (non-zero return) is logged but does not affect the commit result
- Each column family has its own independent hook; a multi-CF transaction fires the hook once per CF with only that CF's operations
- `commitSeq` is monotonically increasing across commits and can be used as a replication cursor
- Data in `CommitOp` is copied from C memory - safe to retain after the callback returns
- The hook executes synchronously on the committing goroutine; keep the callback fast to avoid stalling writers
- Setting the hook to `nil` or calling `ClearCommitHook` disables it immediately with no restart required
- Setting a new hook replaces any previously set hook for the same column family

**Use cases**
- Replication · Ship committed batches to replicas in commit order
- Event streaming · Publish mutations to Kafka, NATS, or any message broker
- Secondary indexing · Maintain a reverse index or materialized view
- Audit logging · Record every mutation with key, value, TTL, and sequence number
- Debugging · Attach a temporary hook in production to inspect live writes

:::note[Runtime-Only]
Commit hooks are not persisted across database restarts. After reopening the database, hooks must be re-registered by the application. This is by design - function pointers cannot be serialized.
:::

### Sync Modes

Control the durability vs performance tradeoff.

```go
cfConfig := tidesdb.DefaultColumnFamilyConfig()

// SyncNone -- Fastest, least durable (OS handles flushing on sorted runs and compaction to sync after completion)
cfConfig.SyncMode = tidesdb.SyncNone

// SyncInterval -- Balanced (periodic background syncing)
cfConfig.SyncMode = tidesdb.SyncInterval
cfConfig.SyncIntervalUs = 128000  // Sync every 128ms

// SyncFull -- Most durable (fsync on every write)
cfConfig.SyncMode = tidesdb.SyncFull

err := db.CreateColumnFamily("my_cf", cfConfig)
if err != nil {
    log.Fatal(err)
}
```

### Manual WAL Sync

`SyncWal` forces an immediate fsync of the active write-ahead log for a column family. This is useful for explicit durability control when using `SyncNone` or `SyncInterval` modes.

```go
cf, err := db.GetColumnFamily("my_cf")
if err != nil {
    log.Fatal(err)
}

// Force WAL durability after a batch of writes
err = cf.SyncWal()
if err != nil {
    log.Fatal(err)
}
```

**When to use**
- Application-controlled durability · Sync the WAL at specific points (e.g., after a batch of related writes) when using `SyncNone` or `SyncInterval`
- Pre-checkpoint · Ensure all buffered WAL data is on disk before taking a checkpoint
- Graceful shutdown · Flush WAL buffers before closing the database
- Critical writes · Force durability for specific high-value writes without using `SyncFull` for all writes

**Behavior**
- Acquires a reference to the active memtable to safely access its WAL
- Calls `fdatasync` on the WAL file descriptor
- Thread-safe - can be called concurrently from multiple goroutines
- If the memtable rotates during the call, retries with the new active memtable

:::tip[Structural Operations]
Regardless of sync mode, TidesDB **always** enforces durability for structural operations, memtable flush to SSTable, SSTable compaction and merging, WAL rotation, and column family metadata updates.
:::

### Compression Algorithms

TidesDB supports multiple compression algorithms:

```go
cfConfig := tidesdb.DefaultColumnFamilyConfig()

cfConfig.CompressionAlgorithm = tidesdb.NoCompression     
cfConfig.CompressionAlgorithm = tidesdb.SnappyCompression  
cfConfig.CompressionAlgorithm = tidesdb.LZ4Compression    
cfConfig.CompressionAlgorithm = tidesdb.LZ4FastCompression 
cfConfig.CompressionAlgorithm = tidesdb.ZstdCompression   

err := db.CreateColumnFamily("my_cf", cfConfig)
if err != nil {
    log.Fatal(err)
}
```

## Object Store

TidesDB supports pluggable object store backends for cloud-native storage. The Go binding exposes the filesystem-backed connector for testing and local replication.

### Object Store Backends

```go
tidesdb.BackendFS       // Filesystem-backed (for testing/local replication)
tidesdb.BackendS3       // S3-compatible object store
tidesdb.BackendUnknown  // Unknown backend
```

### Creating a Filesystem Object Store

```go
store, err := tidesdb.ObjStoreFsCreate("/path/to/object/root")
if err != nil {
    log.Fatal(err)
}

config := tidesdb.Config{
    DBPath:               "./mydb",
    NumFlushThreads:      2,
    NumCompactionThreads: 2,
    LogLevel:             tidesdb.LogInfo,
    BlockCacheSize:       64 * 1024 * 1024,
    MaxOpenSSTables:      256,
    ObjectStore:          store,
}

db, err := tidesdb.Open(config)
if err != nil {
    log.Fatal(err)
}
defer db.Close()
```

### Object Store Configuration

Use `ObjStoreDefaultConfig()` to get a configuration with sensible defaults, then override specific fields:

```go
objConfig := tidesdb.ObjStoreDefaultConfig()
objConfig.LocalCachePath = "/tmp/tidesdb-cache"
objConfig.LocalCacheMaxBytes = 1024 * 1024 * 1024  // 1GB local cache
objConfig.CacheOnRead = true
objConfig.CacheOnWrite = true
objConfig.MaxConcurrentUploads = 8
objConfig.MaxConcurrentDownloads = 16

config := tidesdb.Config{
    DBPath:            "./mydb",
    ObjectStore:       store,
    ObjectStoreConfig: &objConfig,
    // ... other fields ...
}
```

**ObjStoreConfig Fields**
| Field | Type | Description |
|-------|------|-------------|
| `LocalCachePath` | `string` | Local directory for cached SSTable files (empty = use db_path) |
| `LocalCacheMaxBytes` | `uint64` | Max local cache size in bytes (0 = unlimited) |
| `CacheOnRead` | `bool` | Cache downloaded files locally (default true) |
| `CacheOnWrite` | `bool` | Keep local copy after upload (default true) |
| `MaxConcurrentUploads` | `int` | Parallel upload threads (default 4) |
| `MaxConcurrentDownloads` | `int` | Parallel download threads (default 8) |
| `MultipartThreshold` | `uint64` | Use multipart upload above this size (default 64MB) |
| `MultipartPartSize` | `uint64` | Multipart chunk size (default 8MB) |
| `SyncManifestToObject` | `bool` | Upload MANIFEST after each compaction (default true) |
| `ReplicateWal` | `bool` | Upload closed WAL segments for recovery (default true) |
| `WalUploadSync` | `bool` | Block flush until WAL uploaded (default false) |
| `WalSyncThresholdBytes` | `uint64` | Sync active WAL when it grows by this many bytes (default 1MB, 0 = off) |
| `WalSyncOnCommit` | `bool` | Upload WAL after every txn commit for RPO=0 (default false) |
| `ReplicaMode` | `bool` | Enable read-only replica mode (default false) |
| `ReplicaSyncIntervalUs` | `uint64` | MANIFEST poll interval in microseconds (default 5000000) |
| `ReplicaReplayWal` | `bool` | Replay WAL for near-real-time reads on replicas (default true) |

### Per-CF Object Store Tuning

Column family configurations include three object store tuning fields.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `ObjectLazyCompaction` | `int` | `0` | 1 to compact less aggressively for remote storage |
| `ObjectPrefetchCompaction` | `int` | `1` | 1 to download all inputs before compaction merge |

### Object Store Statistics

`GetDbStats` includes object store fields when a connector is active.

```go
dbStats, err := db.GetDbStats()
if err != nil {
    log.Fatal(err)
}

if dbStats.ObjectStoreEnabled {
    fmt.Printf("Connector: %s\n", dbStats.ObjectStoreConnector)
    fmt.Printf("Total uploads: %d\n", dbStats.TotalUploads)
    fmt.Printf("Upload failures: %d\n", dbStats.TotalUploadFailures)
    fmt.Printf("Upload queue depth: %d\n", dbStats.UploadQueueDepth)
    fmt.Printf("Local cache: %d / %d bytes\n",
        dbStats.LocalCacheBytesUsed, dbStats.LocalCacheBytesMax)
}
```

### Cold Start Recovery

When the local database directory is empty but a connector is configured, TidesDB automatically discovers column families from the object store during recovery. It downloads MANIFEST and config files in parallel, reconstructs the SSTable inventory, and fetches SSTable data on demand as queries arrive.

```go
// delete all local state
os.RemoveAll("./mydb")

// reopen with the same connector -- cold start recovery
config := tidesdb.Config{
    DBPath:            "./mydb",
    ObjectStore:       store,
    ObjectStoreConfig: &objConfig,
}

db, err := tidesdb.Open(config)
if err != nil {
    log.Fatal(err)
}
defer db.Close()

// all data is available -- SSTables are fetched from the object store on demand
cf, err := db.GetColumnFamily("my_cf")
```

### How It Works

- Object store mode requires unified memtable mode. Setting `ObjectStore` on the config automatically enables `UnifiedMemtable`
- After each flush, SSTables are uploaded to the object store via an asynchronous upload pipeline with retry (3 attempts with exponential backoff) and post-upload verification (size check)
- Point lookups on frozen SSTables (not present locally) fetch just the single needed klog block (~64KB) via one HTTP range request using `range_get`, bypassing the full file download. The block is cached in the clock cache so subsequent reads are pure memory hits. If the value is in the vlog, a second range request fetches just that vlog block
- Iterators prefetch all needed SSTable files in parallel at creation time using bounded threads (`MaxConcurrentDownloads`, default 8), so sequential reads proceed at local disk speed
- A hash-indexed LRU local file cache manages disk usage, evicting least-recently-used SSTable file pairs (klog + vlog together) when `LocalCacheMaxBytes` is set
- The MANIFEST is uploaded asynchronously after each flush and compaction so cold start recovery can reconstruct the SSTable inventory without blocking the flush worker
- Compaction runs on local files. Input SSTables are downloaded if evicted, output SSTables are uploaded after the merge
- Upload failures are tracked in `TotalUploadFailures` on `DbStats` for operator monitoring

## Replica Mode

Replica mode enables read-only nodes that follow a primary through the object store. The primary handles all writes while replicas poll for MANIFEST updates and replay WAL segments for near-real-time reads.

### Enabling Replica Mode

```go
store, err := tidesdb.ObjStoreFsCreate("/path/to/shared/objects")
if err != nil {
    log.Fatal(err)
}

objConfig := tidesdb.ObjStoreDefaultConfig()
objConfig.ReplicaMode = true
objConfig.ReplicaSyncIntervalUs = 1000000  // 1 second sync interval
objConfig.ReplicaReplayWal = true          // replay WAL for fresh reads

config := tidesdb.Config{
    DBPath:            "./mydb_replica",
    ObjectStore:       store,  // same object store as the primary
    ObjectStoreConfig: &objConfig,
}

db, err := tidesdb.Open(config)
if err != nil {
    log.Fatal(err)
}
defer db.Close()

// reads work normally
txn, _ := db.BeginTxn()
value, _ := txn.Get(cf, []byte("key"))
txn.Free()

// writes are rejected with ErrReadonly
```

### Sync-on-Commit WAL (Primary Side)

For tighter replication lag, enable sync-on-commit on the primary so every committed write is uploaded to the object store immediately.

```go
objConfig := tidesdb.ObjStoreDefaultConfig()
objConfig.WalSyncOnCommit = true  // RPO = 0, every commit is durable in object store

// replica sees committed data within one ReplicaSyncIntervalUs
```

### Promoting a Replica to Primary

When the primary fails, promote a replica to accept writes.

```go
err := db.PromoteToPrimary()
if err != nil {
    log.Fatal(err)
}

// now writes are accepted
txn, _ := db.BeginTxn()
txn.Put(cf, []byte("key"), []byte("value"), -1)
txn.Commit()
txn.Free()
```

`PromoteToPrimary` performs a final MANIFEST sync and WAL replay, creates a local WAL for crash recovery, and atomically switches to primary mode. The function returns an error if the node is already a primary.

### How Replica Sync Works

- The reaper thread polls the remote MANIFEST for each CF every `ReplicaSyncIntervalUs`
- New SSTables from the primary's flushes and compactions are added to the replica's levels
- SSTables compacted away on the primary are removed from the replica's levels
- When `ReplicaReplayWal` is enabled, the latest WAL is downloaded and replayed into the memtable for near-real-time reads
- WAL replay is idempotent using sequence numbers so entries already present are skipped
- SSTable data is not downloaded during sync. It is fetched on demand via range_get for point lookups or prefetch for iterators

## Configuration Persistence (INI)

Column family configurations can be saved to and loaded from INI files.

### Save Configuration to INI

```go
cfConfig := tidesdb.DefaultColumnFamilyConfig()
cfConfig.WriteBufferSize = 128 * 1024 * 1024
cfConfig.CompressionAlgorithm = tidesdb.ZstdCompression

err := tidesdb.CfConfigSaveToIni("config.ini", "my_cf", cfConfig)
if err != nil {
    log.Fatal(err)
}
```

### Load Configuration from INI

```go
loaded, err := tidesdb.CfConfigLoadFromIni("config.ini", "my_cf")
if err != nil {
    log.Fatal(err)
}

err = db.CreateColumnFamily("my_cf", *loaded)
if err != nil {
    log.Fatal(err)
}
```

## Error Handling

```go
cf, err := db.GetColumnFamily("my_cf")
if err != nil {
    log.Fatal(err)
}

txn, err := db.BeginTxn()
if err != nil {
    log.Fatal(err)
}
defer txn.Free()

err = txn.Put(cf, []byte("key"), []byte("value"), -1)
if err != nil {
    // Errors include context and error codes
    fmt.Printf("Error: %v\n", err)
    
    // Example error message:
    // "failed to put key-value pair: memory allocation failed (code: -1)"
    
    txn.Rollback()
    return
}

err = txn.Commit()
if err != nil {
    log.Fatal(err)
}
```

**Error Codes**
- `ErrSuccess` (0) · Operation successful
- `ErrMemory` (-1) · Memory allocation failed
- `ErrInvalidArgs` (-2) · Invalid arguments
- `ErrNotFound` (-3) · Key not found
- `ErrIO` (-4) · I/O error
- `ErrCorruption` (-5) · Data corruption
- `ErrExists` (-6) · Resource already exists
- `ErrConflict` (-7) · Transaction conflict
- `ErrTooLarge` (-8) · Key or value too large
- `ErrMemoryLimit` (-9) · Memory limit exceeded
- `ErrInvalidDB` (-10) · Invalid database handle
- `ErrUnknown` (-11) · Unknown error
- `ErrLocked` (-12) · Database is locked
- `ErrReadonly` (-13) · Database is read-only (replica mode)

## Complete Example

```go
package main

import (
    "fmt"
    "log"
    "time"
    
    tidesdb "github.com/tidesdb/tidesdb-go"
)

func main() {
    config := tidesdb.Config{
        DBPath:               "./example_db",
        NumFlushThreads:      1,
        NumCompactionThreads: 1,
        LogLevel:             tidesdb.LogInfo,
        BlockCacheSize:       64 * 1024 * 1024,
        MaxOpenSSTables:      256,
    }
    
    db, err := tidesdb.Open(config)
    if err != nil {
        log.Fatal(err)
    }
    defer db.Close()
    
    cfConfig := tidesdb.DefaultColumnFamilyConfig()
    cfConfig.WriteBufferSize = 64 * 1024 * 1024
    cfConfig.CompressionAlgorithm = tidesdb.LZ4Compression
    cfConfig.EnableBloomFilter = true
    cfConfig.BloomFPR = 0.01
    cfConfig.SyncMode = tidesdb.SyncInterval
    cfConfig.SyncIntervalUs = 128000
    
    err = db.CreateColumnFamily("users", cfConfig)
    if err != nil {
        log.Fatal(err)
    }
    defer db.DropColumnFamily("users")
    
    cf, err := db.GetColumnFamily("users")
    if err != nil {
        log.Fatal(err)
    }
    
    txn, err := db.BeginTxn()
    if err != nil {
        log.Fatal(err)
    }
    
    err = txn.Put(cf, []byte("user:1"), []byte("Alice"), -1)
    if err != nil {
        txn.Rollback()
        log.Fatal(err)
    }
    
    err = txn.Put(cf, []byte("user:2"), []byte("Bob"), -1)
    if err != nil {
        txn.Rollback()
        log.Fatal(err)
    }

    ttl := time.Now().Add(30 * time.Second).Unix()
    err = txn.Put(cf, []byte("session:abc"), []byte("temp_data"), ttl)
    if err != nil {
        txn.Rollback()
        log.Fatal(err)
    }
    
    err = txn.Commit()
    if err != nil {
        log.Fatal(err)
    }
    txn.Free()
    
    readTxn, err := db.BeginTxn()
    if err != nil {
        log.Fatal(err)
    }
    defer readTxn.Free()
    
    value, err := readTxn.Get(cf, []byte("user:1"))
    if err != nil {
        log.Fatal(err)
    }
    fmt.Printf("user:1 = %s\n", value)
    
    iter, err := readTxn.NewIterator(cf)
    if err != nil {
        log.Fatal(err)
    }
    defer iter.Free()
    
    fmt.Println("\nAll entries:")
    iter.SeekToFirst()
    for iter.Valid() {
        key, _ := iter.Key()
        value, _ := iter.Value()
        fmt.Printf("  %s = %s\n", key, value)
        iter.Next()
    }
    
    stats, err := cf.GetStats()
    if err != nil {
        log.Fatal(err)
    }
    
    fmt.Printf("\nColumn Family Statistics:\n")
    fmt.Printf("  Number of Levels: %d\n", stats.NumLevels)
    fmt.Printf("  Memtable Size: %d bytes\n", stats.MemtableSize)
}
```

## Isolation Levels

TidesDB supports five MVCC isolation levels:

```go
txn, err := db.BeginTxnWithIsolation(tidesdb.IsolationReadCommitted)
if err != nil {
    log.Fatal(err)
}
defer txn.Free()
```

**Available Isolation Levels**
- `IsolationReadUncommitted` · Sees all data including uncommitted changes
- `IsolationReadCommitted` · Sees only committed data (default)
- `IsolationRepeatableRead` · Consistent snapshot, phantom reads possible
- `IsolationSnapshot` · Write-write conflict detection
- `IsolationSerializable` · Full read-write conflict detection (SSI)

## Savepoints

Savepoints allow partial rollback within a transaction:

```go
txn, err := db.BeginTxn()
if err != nil {
    log.Fatal(err)
}
defer txn.Free()

err = txn.Put(cf, []byte("key1"), []byte("value1"), -1)

err = txn.Savepoint("sp1")
err = txn.Put(cf, []byte("key2"), []byte("value2"), -1)

// Rollback to savepoint -- key2 is discarded, key1 remains
err = txn.RollbackToSavepoint("sp1")

// Or release savepoint without rolling back
err = txn.ReleaseSavepoint("sp1")

// Commit -- only key1 is written
err = txn.Commit()
```

**Savepoint API**
- `Savepoint(name string)` · Create a savepoint
- `RollbackToSavepoint(name string)` · Rollback to savepoint
- `ReleaseSavepoint(name string)` · Release savepoint without rolling back

## Transaction Reset

`Reset` resets a committed or aborted transaction for reuse with a new isolation level. This avoids the overhead of freeing and reallocating transaction resources in hot loops.

```go
txn, err := db.BeginTxn()
if err != nil {
    log.Fatal(err)
}

// First batch of work
err = txn.Put(cf, []byte("key1"), []byte("value1"), -1)
if err != nil {
    log.Fatal(err)
}
err = txn.Commit()
if err != nil {
    log.Fatal(err)
}

// Reset instead of Free + BeginTxn
err = txn.Reset(tidesdb.IsolationReadCommitted)
if err != nil {
    log.Fatal(err)
}

// Second batch of work using the same transaction
err = txn.Put(cf, []byte("key2"), []byte("value2"), -1)
if err != nil {
    log.Fatal(err)
}
err = txn.Commit()
if err != nil {
    log.Fatal(err)
}

// Free once when done
txn.Free()
```

**Behavior**
- The transaction must be committed or aborted before reset; resetting an active transaction returns an error
- Internal buffers are retained to avoid reallocation
- A fresh transaction ID and snapshot sequence are assigned based on the new isolation level
- The isolation level can be changed on each reset (e.g., `IsolationReadCommitted` -> `IsolationRepeatableRead`)

**When to use**
- Batch processing · Reuse a single transaction across many commit cycles in a loop
- Connection pooling · Reset a transaction for a new request without reallocation
- High-throughput ingestion · Reduce malloc/free overhead in tight write loops

**Reset vs Free + BeginTxn**

For a single transaction, `Reset` is functionally equivalent to calling `Free` followed by `BeginTxnWithIsolation`. The difference is performance, reset retains allocated buffers and avoids repeated allocation overhead. This matters most in loops that commit and restart thousands of transactions.

## B+tree KLog Format

Column families can optionally use a B+tree structure for the key log instead of the default block-based format.

```go
cfConfig := tidesdb.DefaultColumnFamilyConfig()
cfConfig.UseBtree = 1  // Enable B+tree klog format

err := db.CreateColumnFamily("btree_cf", cfConfig)
if err != nil {
    log.Fatal(err)
}
```

**Characteristics**
- Point lookups · O(log N) tree traversal with binary search at each node
- Range scans · Doubly-linked leaf nodes enable efficient bidirectional iteration
- Immutable · Tree is bulk-loaded from sorted memtable data during flush

**When to use B+tree klog format**
- Read-heavy workloads with frequent point lookups
- Workloads where read latency is more important than write throughput
- Large SSTables where block scanning becomes expensive

:::caution[Important]
`UseBtree` cannot be changed after column family creation.
:::

## Log Levels

TidesDB provides structured logging with multiple severity levels.

```go
config := tidesdb.Config{
    DBPath:   "./mydb",
    LogLevel: tidesdb.LogDebug,  
}
```

**Available Log Levels**
- `LogDebug` · Detailed diagnostic information
- `LogInfo` · General informational messages (default)
- `LogWarn` · Warning messages for potential issues
- `LogError` · Error messages for failures
- `LogFatal` · Critical errors that may cause shutdown
- `LogNone` · Disable all logging

**Log to file**
```go
config := tidesdb.Config{
    DBPath:          "./mydb",
    LogLevel:        tidesdb.LogDebug,
    LogToFile:       true,                    // Write to ./mydb/LOG instead of stderr
    LogTruncationAt: 24 * 1024 * 1024,        // Truncate log file at 24MB
}
```

## Testing

```bash
# Run all tests
go test -v

# Run specific test
go test -v -run TestOpenClose

# Run with race detector
go test -race -v

# Run B+tree test
go test -v -run TestBtreeColumnFamily

# Run clone column family test
go test -v -run TestCloneColumnFamily

# Run transaction reset test
go test -v -run TestTransactionReset

# Run checkpoint test
go test -v -run TestCheckpoint

# Run range cost estimation test
go test -v -run TestRangeCost

# Run delete column family by pointer test
go test -v -run TestDeleteColumnFamily

# Run commit hook (CDC) tests
go test -v -run TestCommitHook
go test -v -run TestCommitHookReplace
go test -v -run TestCommitHookClear

# Run backup test
go test -v -run TestBackup

# Run rename column family test
go test -v -run TestRenameColumnFamily

# Run update runtime config test
go test -v -run TestUpdateRuntimeConfig

# Run flush/compaction status test
go test -v -run TestIsFlushingIsCompacting

# Run get comparator test
go test -v -run TestGetComparator

# Run WAL sync test
go test -v -run TestSyncWal

# Run purge column family test
go test -v -run TestPurgeCF

# Run purge database test
go test -v -run TestPurge

# Run database-level stats test
go test -v -run TestGetDbStats

# Run iterator key-value test
go test -v -run TestIterKeyValue

# Run init/finalize test
go test -v -run TestInitFinalize

# Run object store config tests
go test -v -run TestObjStoreDefaultConfig
go test -v -run TestObjStoreFsCreate
go test -v -run TestObjStoreBackendConstants

# Run column family config object store fields test
go test -v -run TestColumnFamilyConfigObjectStoreFields

# Run db stats object store fields test
go test -v -run TestDbStatsObjectStoreFields

# Run INI config test
go test -v -run TestCfConfigIni

# Run error code readonly test
go test -v -run TestErrorCodeReadonly
```
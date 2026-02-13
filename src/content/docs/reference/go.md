---
title: TidesDB GO API Reference
description: GO API reference for TidesDB
---

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/go.md).

<hr/>

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
        LogToFile:            false,              // Write logs to file instead of stderr
        LogTruncationAt:      24 * 1024 * 1024,   // Log file truncation size (24MB default)
    }
    
    db, err := tidesdb.Open(config)
    if err != nil {
        log.Fatal(err)
    }
    defer db.Close()
    
    fmt.Println("Database opened successfully")
}
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
cfConfig.DividingLevelOffset = 2                  // Compaction dividing level offset
cfConfig.KlogValueThreshold = 512                 // Values > 512 bytes go to vlog
cfConfig.BlockIndexPrefixLen = 16                 // Block index prefix length
cfConfig.MinDiskSpace = 100 * 1024 * 1024         // Minimum disk space required (100MB)
cfConfig.L1FileCountTrigger = 4                   // L1 file count trigger for compaction
cfConfig.L0QueueStallThreshold = 20               // L0 queue stall threshold
cfConfig.UseBtree = 0                             // Use B+tree format for klog (0 = block-based)

err = db.CreateColumnFamily("my_cf", cfConfig)
if err != nil {
    log.Fatal(err)
}

err = db.DropColumnFamily("my_cf")
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
- The isolation level can be changed on each reset (e.g., `IsolationReadCommitted` → `IsolationRepeatableRead`)

**When to use**
- Batch processing · Reuse a single transaction across many commit cycles in a loop
- Connection pooling · Reset a transaction for a new request without reallocation
- High-throughput ingestion · Reduce malloc/free overhead in tight write loops

**Reset vs Free + BeginTxn**

For a single transaction, `Reset` is functionally equivalent to calling `Free` followed by `BeginTxnWithIsolation`. The difference is performance: reset retains allocated buffers and avoids repeated allocation overhead. This matters most in loops that commit and restart thousands of transactions.

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
```
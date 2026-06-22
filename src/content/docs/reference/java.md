---
title: TidesDB Java API Reference
description: Complete Java API reference for TidesDB
---

<div class="no-print">

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/java.md).

<hr/>

</div>

## Getting Started

### Prerequisites

You **must** have the TidesDB shared C library installed on your system.  You can find the installation instructions [here](/reference/building/#_top).

## Requirements

- Java 11 or higher
- Maven 3.6+
- TidesDB native library installed on the system

### Building the JNI Library

```bash
cd src/main/c
cmake -S . -B build
cmake --build build
sudo cmake --install build
```

### Adding to Your Project

**Maven**
```xml
<dependency>
    <groupId>com.tidesdb</groupId>
    <artifactId>tidesdb-java</artifactId>
    <version>0.8.2</version>
</dependency>
```

## Usage

### Opening and Closing a Database

```java
import com.tidesdb.*;

public class Example {
    public static void main(String[] args) throws TidesDBException {
        Config config = Config.builder("./mydb")
            .numFlushThreads(2)
            .numCompactionThreads(2)
            .logLevel(LogLevel.INFO)
            .blockCacheSize(64 * 1024 * 1024)
            .maxOpenSSTables(256)
            .maxMemoryUsage(0)
            .maxConcurrentFlushes(0)            // Cap on in-flight memtable flushes across all CFs (0 = library default)
            .unifiedMemtable(false)
            .build();
        
        try (TidesDB db = TidesDB.open(config)) {
            System.out.println("Database opened successfully");
        }
    }
}
```

`Config.defaultConfig()` returns a configuration with sensible defaults. The `maxConcurrentFlushes` default is sourced from the underlying C library via `tidesdb_default_config()`, so the binding tracks the engine's defaults automatically. If you previously hardcoded values such as `maxConcurrentFlushes`, re-test after upgrading.

:::note[maxConcurrentFlushes]
`maxConcurrentFlushes` is a global semaphore on the number of in-flight memtable flushes across all column families. It bounds total transient memory and work-queue depth when many column families flush at once. Leave it at `0` to inherit the library default (recommended), or lower it on memory-constrained hosts to throttle peak flush concurrency.
:::

#### Raising the Open-File Limit

`TidesDB.raiseOpenFileLimit(long)` raises this process's open-file ceiling so the database can keep more SSTables open. The engine sizes `maxOpenSSTables` to fit this ceiling at open time, so call it **before** `TidesDB.open()`. This is an explicit, opt-in operator action - TidesDB never raises the limit itself.

```java
// Raise the soft limit toward the hard limit before opening
long ceiling = TidesDB.raiseOpenFileLimit(65536);
System.out.println("Open-file ceiling now: " + ceiling);

try (TidesDB db = TidesDB.open(config)) {
    // engine can now keep more SSTables open
}
```

**Behavior**
- On POSIX systems (Linux, macOS, the BSDs, illumos) it raises the `RLIMIT_NOFILE` soft limit toward the hard limit; on Windows it raises the CRT stdio cap (max 8192)
- A failed or partial raise is non-fatal
- Passing a value `<= 0` just reports the current ceiling without changing it
- Returns the open-file ceiling in effect after the attempt

### Unified Memtable Mode

Enable unified memtable mode to share a single memtable and WAL across all column families. This reduces write amplification for workloads with many small column families.

```java
Config config = Config.builder("./mydb")
    .numFlushThreads(2)
    .numCompactionThreads(2)
    .logLevel(LogLevel.INFO)
    .blockCacheSize(64 * 1024 * 1024)
    .maxOpenSSTables(256)
    .unifiedMemtable(true)
    .unifiedMemtableWriteBufferSize(0)       // 0 = auto (64MB default)
    .unifiedMemtableSkipListMaxLevel(0)      // 0 = default (12)
    .unifiedMemtableSkipListProbability(0)   // 0 = default (0.25)
    .unifiedMemtableSyncMode(0)              // 0 = SYNC_NONE
    .unifiedMemtableSyncIntervalUs(0)        // 0 = default
    .build();

try (TidesDB db = TidesDB.open(config)) {
    // All column families share a single memtable
}
```

### Creating and Dropping Column Families

Column families are isolated key-value stores with independent configuration.

```java
// Create with default configuration
ColumnFamilyConfig cfConfig = ColumnFamilyConfig.defaultConfig();
db.createColumnFamily("my_cf", cfConfig);

// Create with custom configuration
ColumnFamilyConfig customConfig = ColumnFamilyConfig.builder()
    .writeBufferSize(128 * 1024 * 1024)
    .levelSizeRatio(10)
    .minLevels(5)
    .compressionAlgorithm(CompressionAlgorithm.LZ4_COMPRESSION)
    .enableBloomFilter(true)
    .bloomFPR(0.01)
    .enableBlockIndexes(true)
    .syncMode(SyncMode.SYNC_INTERVAL)
    .syncIntervalUs(128000)
    .defaultIsolationLevel(IsolationLevel.READ_COMMITTED)
    .tombstoneDensityTrigger(0.0)              // Per-SSTable tombstone density above which compaction escalates (0.0 = disabled, range 0.0 to 1.0)
    .tombstoneDensityMinEntries(1024)          // Minimum entry count for an SSTable to be considered by the density trigger
    .build();

db.createColumnFamily("custom_cf", customConfig);

db.dropColumnFamily("my_cf");

// Delete via column family handle (alternative to dropColumnFamily)
ColumnFamily cfToDelete = db.getColumnFamily("old_cf");
db.deleteColumnFamily(cfToDelete);

String[] cfNames = db.listColumnFamilies();
for (String name : cfNames) {
    System.out.println("Column family: " + name);
}
```

### Working with Transactions

#### Writing Data

```java
ColumnFamily cf = db.getColumnFamily("my_cf");

try (Transaction txn = db.beginTransaction()) {
    txn.put(cf, "key".getBytes(), "value".getBytes());
    txn.commit();
}
```

#### Writing with TTL

```java
import java.time.Instant;

ColumnFamily cf = db.getColumnFamily("my_cf");

try (Transaction txn = db.beginTransaction()) {
    long ttl = Instant.now().getEpochSecond() + 10;
    
    txn.put(cf, "temp_key".getBytes(), "temp_value".getBytes(), ttl);
    txn.commit();
}
```

**TTL Examples**
```java
long ttl = -1;

long ttl = Instant.now().getEpochSecond() + 5 * 60;

long ttl = Instant.now().getEpochSecond() + 60 * 60;

long ttl = LocalDateTime.of(2026, 12, 31, 23, 59, 59)
        .toEpochSecond(ZoneOffset.UTC);
```

#### Reading Data

```java
ColumnFamily cf = db.getColumnFamily("my_cf");

try (Transaction txn = db.beginTransaction()) {
    byte[] value = txn.get(cf, "key".getBytes());
    System.out.println("Value: " + new String(value));
}
```

#### Deleting Data

```java
ColumnFamily cf = db.getColumnFamily("my_cf");

try (Transaction txn = db.beginTransaction()) {
    txn.delete(cf, "key".getBytes());
    txn.commit();
}
```

#### Single-Delete

`txn.singleDelete` writes a tombstone with the same read semantics as `txn.delete`, but carries a caller-provided promise that lets compaction drop the put and the tombstone together as soon as both appear in the same merge input, rather than carrying the tombstone forward until it reaches the largest active level.

Between any two single-deletes on the same key, and between the start of the key's history and its first single-delete, the key has been put **at most once**. The engine does not and cannot verify this at runtime; violating the contract can leave older puts visible after the single-delete and is a bug in the caller.

This is the right choice for workloads that insert each key exactly once and then delete it exactly once (classic insert-benchmark patterns, secondary-index entries on columns that are never updated, log-style tables with scheduled purges). It is **not** safe for tables that issue repeated updates to the same key.

```java
ColumnFamily cf = db.getColumnFamily("my_cf");

try (Transaction txn = db.beginTransaction()) {
    txn.singleDelete(cf, "key".getBytes());
    txn.commit();
}
```

When in doubt, prefer `txn.delete`.

#### Transaction Rollback

```java
ColumnFamily cf = db.getColumnFamily("my_cf");

try (Transaction txn = db.beginTransaction()) {
    txn.put(cf, "key".getBytes(), "value".getBytes());
    
    txn.rollback();
}
```

#### Multi-Operation Transactions

```java
ColumnFamily cf = db.getColumnFamily("my_cf");

try (Transaction txn = db.beginTransaction()) {
    txn.put(cf, "key1".getBytes(), "value1".getBytes());
    txn.put(cf, "key2".getBytes(), "value2".getBytes());
    txn.delete(cf, "old_key".getBytes());
    
    txn.commit();
} catch (TidesDBException e) {
    throw e;
}
```

### Iterating Over Data

Iterators provide efficient bidirectional traversal over key-value pairs.

#### Forward Iteration

```java
ColumnFamily cf = db.getColumnFamily("my_cf");

try (Transaction txn = db.beginTransaction()) {
    try (TidesDBIterator iter = txn.newIterator(cf)) {
        iter.seekToFirst();
        
        while (iter.isValid()) {
            byte[] key = iter.key();
            byte[] value = iter.value();
            
            System.out.printf("Key: %s, Value: %s%n", 
                new String(key), new String(value));
            
            iter.next();
        }
    }
}
```

#### Backward Iteration

```java
ColumnFamily cf = db.getColumnFamily("my_cf");

try (Transaction txn = db.beginTransaction()) {
    try (TidesDBIterator iter = txn.newIterator(cf)) {
        iter.seekToLast();
        
        while (iter.isValid()) {
            byte[] key = iter.key();
            byte[] value = iter.value();
            
            System.out.printf("Key: %s, Value: %s%n", 
                new String(key), new String(value));
            
            iter.prev();
        }
    }
}
```

#### Combined Key-Value Retrieval

For better performance when you need both the key and value, use `keyValue()` which retrieves both in a single JNI call:

```java
try (TidesDBIterator iter = txn.newIterator(cf)) {
    iter.seekToFirst();

    while (iter.isValid()) {
        KeyValue kv = iter.keyValue();
        System.out.printf("Key: %s, Value: %s%n",
            new String(kv.getKey()), new String(kv.getValue()));

        iter.next();
    }
}
```

#### Seeking to a Specific Key

```java
try (TidesDBIterator iter = txn.newIterator(cf)) {
    iter.seek("prefix".getBytes());
    
    iter.seekForPrev("prefix".getBytes());
}
```

#### Prefix Seeking

Since `seek` positions the iterator at the first key >= target, you can use a prefix as the seek target to efficiently scan all keys sharing that prefix:

```java
ColumnFamily cf = db.getColumnFamily("my_cf");

try (Transaction txn = db.beginTransaction()) {
    try (TidesDBIterator iter = txn.newIterator(cf)) {
        byte[] prefix = "user:".getBytes();
        iter.seek(prefix);
        
        while (iter.isValid()) {
            byte[] key = iter.key();
            String keyStr = new String(key);
            
            if (!keyStr.startsWith("user:")) break;
            
            byte[] value = iter.value();
            System.out.printf("Key: %s, Value: %s%n", keyStr, new String(value));
            
            iter.next();
        }
    }
}
```

This pattern works across both memtables and SSTables. When block indexes are enabled, the seek operation uses binary search to jump directly to the relevant block, making prefix scans efficient even on large datasets.

### Getting Column Family Statistics

```java
ColumnFamily cf = db.getColumnFamily("my_cf");
Stats stats = cf.getStats();

System.out.println("Number of levels: " + stats.getNumLevels());
System.out.println("Memtable size: " + stats.getMemtableSize());
System.out.println("Total keys: " + stats.getTotalKeys());
System.out.println("Total data size: " + stats.getTotalDataSize());
System.out.println("Average key size: " + stats.getAvgKeySize());
System.out.println("Average value size: " + stats.getAvgValueSize());
System.out.println("Read amplification: " + stats.getReadAmp());
System.out.println("Hit rate: " + stats.getHitRate());

if (stats.isUseBtree()) {
    System.out.println("B+tree total nodes: " + stats.getBtreeTotalNodes());
    System.out.println("B+tree max height: " + stats.getBtreeMaxHeight());
    System.out.println("B+tree avg height: " + stats.getBtreeAvgHeight());
}

long[] levelSizes = stats.getLevelSizes();
int[] levelSSTables = stats.getLevelNumSSTables();
long[] levelKeyCounts = stats.getLevelKeyCounts();

// Tombstone density observability
System.out.println("Total tombstones: " + stats.getTotalTombstones());
System.out.printf("Tombstone ratio: %.2f%%%n", stats.getTombstoneRatio() * 100.0);
System.out.printf("Worst SSTable density: %.2f%% at level %d%n",
    stats.getMaxSstDensity() * 100.0, stats.getMaxSstDensityLevel());
long[] levelTombstoneCounts = stats.getLevelTombstoneCounts();
for (int i = 0; i < stats.getNumLevels(); i++) {
    System.out.printf("Level %d tombstones: %d%n", i + 1, levelTombstoneCounts[i]);
}
```

**Stats Fields**

| Field | Type | Description |
|-------|------|-------------|
| `numLevels` | int | Number of LSM levels |
| `memtableSize` | long | Current memtable size in bytes |
| `levelSizes` | long[] | Size of each level in bytes |
| `levelNumSSTables` | int[] | Number of SSTables at each level |
| `levelKeyCounts` | long[] | Number of keys per level |
| `totalKeys` | long | Total keys across memtable and all SSTables |
| `totalDataSize` | long | Total data size (klog + vlog) in bytes |
| `avgKeySize` | double | Average key size in bytes |
| `avgValueSize` | double | Average value size in bytes |
| `readAmp` | double | Read amplification (point lookup cost multiplier) |
| `hitRate` | double | Cache hit rate (0.0 if cache disabled) |
| `useBtree` | boolean | Whether column family uses B+tree klog format |
| `btreeTotalNodes` | long | Total B+tree nodes (only if useBtree=true) |
| `btreeMaxHeight` | int | Maximum B+tree height (only if useBtree=true) |
| `btreeAvgHeight` | double | Average B+tree height (only if useBtree=true) |
| `totalTombstones` | long | Total tombstones across every SSTable in the column family |
| `tombstoneRatio` | double | `totalTombstones / totalKeys` (0.0 if `totalKeys` is 0; range 0.0 to 1.0) |
| `levelTombstoneCounts` | long[] | Per-level tombstone counts (parallels `levelKeyCounts`) |
| `maxSstDensity` | double | Worst single-SSTable tombstone density observed (0.0 to 1.0) |
| `maxSstDensityLevel` | int | 1-based level index where the worst SSTable lives (0 if none) |
| `walBytesWritten` | long | Framed bytes appended to this CF's WAL (0 in unified mode; see `DbStats.uwalBytesWritten`) |
| `flushBytesWritten` | long | On-disk bytes this CF's flushes wrote to L0 SSTables |
| `compactionBytesWritten` | long | On-disk bytes this CF's compactions wrote |
| `compactionBytesRead` | long | On-disk bytes this CF's compactions read as input |
| `userBytesWritten` | long | Logical key+value bytes committed to this CF (write-amplification denominator) |
| `flushCount` | long | Flushed SSTables produced by this CF |
| `compactionCount` | long | Compaction output SSTables produced by this CF |
| `config` | ColumnFamilyConfig | Column family configuration |

:::note[Write amplification]
The `*BytesWritten`/`*BytesRead` and `*Count` fields are lifetime counters since the database was opened (on-disk framed bytes). A column family's write amplification is `(walBytesWritten + flushBytesWritten + compactionBytesWritten) / userBytesWritten`. In unified memtable mode `walBytesWritten` is 0 — the shared WAL volume is reported db-wide via `DbStats.uwalBytesWritten`.
:::

### Getting Cache Statistics

```java
CacheStats cacheStats = db.getCacheStats();

System.out.println("Cache enabled: " + cacheStats.isEnabled());
System.out.println("Total entries: " + cacheStats.getTotalEntries());
System.out.println("Hit rate: " + cacheStats.getHitRate());
```

### Getting Database-Level Statistics

Get aggregate statistics across the entire database instance.

```java
DbStats dbStats = db.getDbStats();

System.out.println("Column families: " + dbStats.getNumColumnFamilies());
System.out.println("Total memory: " + dbStats.getTotalMemory() + " bytes");
System.out.println("Resolved memory limit: " + dbStats.getResolvedMemoryLimit() + " bytes");
System.out.println("Memory pressure level: " + dbStats.getMemoryPressureLevel());
System.out.println("Global sequence: " + dbStats.getGlobalSeq());
System.out.println("Flush queue: " + dbStats.getFlushQueueSize() + " pending");
System.out.println("Compaction queue: " + dbStats.getCompactionQueueSize() + " pending");
System.out.println("Total SSTables: " + dbStats.getTotalSstableCount());
System.out.println("Total data size: " + dbStats.getTotalDataSizeBytes() + " bytes");
System.out.println("Open SSTable handles: " + dbStats.getNumOpenSstables());
System.out.println("In-flight txn memory: " + dbStats.getTxnMemoryBytes() + " bytes");
System.out.println("Immutable memtables: " + dbStats.getTotalImmutableCount());
System.out.println("Memtable bytes: " + dbStats.getTotalMemtableBytes());

// Unified memtable stats
System.out.println("Unified memtable enabled: " + dbStats.isUnifiedMemtableEnabled());
System.out.println("Unified memtable bytes: " + dbStats.getUnifiedMemtableBytes());
System.out.println("Unified immutable count: " + dbStats.getUnifiedImmutableCount());
System.out.println("Unified is flushing: " + dbStats.isUnifiedIsFlushing());
System.out.println("Unified WAL generation: " + dbStats.getUnifiedWalGeneration());

// Object store stats
System.out.println("Object store enabled: " + dbStats.isObjectStoreEnabled());
System.out.println("Object store connector: " + dbStats.getObjectStoreConnector());
System.out.println("Local cache used: " + dbStats.getLocalCacheBytesUsed() + " bytes");
System.out.println("Total uploads: " + dbStats.getTotalUploads());
System.out.println("Replica mode: " + dbStats.isReplicaMode());
```

**DbStats Fields**

| Field | Type | Description |
|-------|------|-------------|
| `numColumnFamilies` | int | Number of column families |
| `totalMemory` | long | System total memory |
| `availableMemory` | long | System available memory at open time |
| `resolvedMemoryLimit` | long | Resolved memory limit (auto or configured) |
| `memoryPressureLevel` | int | Current memory pressure (0=normal, 1=elevated, 2=high, 3=critical) |
| `flushPendingCount` | int | Number of pending flush operations (queued + in-flight) |
| `totalMemtableBytes` | long | Total bytes in active memtables across all CFs |
| `totalImmutableCount` | int | Total immutable memtables across all CFs |
| `totalSstableCount` | int | Total SSTables across all CFs and levels |
| `totalDataSizeBytes` | long | Total data size (klog + vlog) across all CFs |
| `numOpenSstables` | int | Number of currently open SSTable file handles |
| `globalSeq` | long | Current global sequence number |
| `txnMemoryBytes` | long | Bytes held by in-flight transactions |
| `compactionQueueSize` | long | Number of pending compaction tasks |
| `flushQueueSize` | long | Number of pending flush tasks in queue |
| `unifiedMemtableEnabled` | boolean | Whether unified memtable mode is active |
| `unifiedMemtableBytes` | long | Bytes in unified active memtable |
| `unifiedImmutableCount` | int | Number of unified immutable memtables |
| `unifiedIsFlushing` | boolean | Whether unified memtable is currently flushing |
| `unifiedNextCfIndex` | int | Next CF index to be assigned in unified mode |
| `unifiedWalGeneration` | long | Current unified WAL generation counter |
| `objectStoreEnabled` | boolean | Whether object store mode is active |
| `objectStoreConnector` | String | Connector name ("s3", "gcs", "fs", etc.) |
| `localCacheBytesUsed` | long | Current local file cache usage in bytes |
| `localCacheBytesMax` | long | Configured maximum local cache size in bytes |
| `localCacheNumFiles` | int | Number of files tracked in local cache |
| `lastUploadedGeneration` | long | Highest WAL generation confirmed uploaded |
| `uploadQueueDepth` | long | Number of pending upload jobs in the queue |
| `totalUploads` | long | Lifetime count of objects uploaded to object store |
| `totalUploadFailures` | long | Lifetime count of permanently failed uploads |
| `replicaMode` | boolean | Whether running in read-only replica mode |
| `primaryEpoch` | long | Object-store single-writer fencing: lease epoch this primary currently holds (0 when not a primary / no lease) |
| `seenEpoch` | long | Object-store single-writer fencing: highest lease epoch this node has observed |
| `uwalBytesWritten` | long | Framed bytes appended to the shared unified WAL (0 if unified mode off) |
| `walBytesWritten` | long | Per-CF WAL bytes summed across all column families |
| `flushBytesWritten` | long | Flush output bytes summed across all column families |
| `compactionBytesWritten` | long | Compaction output bytes summed across all column families |
| `compactionBytesRead` | long | Compaction input bytes summed across all column families |
| `userBytesWritten` | long | Logical committed bytes summed across all column families |
| `flushCount` | long | Flushed SSTables summed across all column families |
| `compactionCount` | long | Compaction output SSTables summed across all column families |

The database-wide write amplification is `(uwalBytesWritten + walBytesWritten + flushBytesWritten + compactionBytesWritten) / userBytesWritten`. All fields are lifetime counters (on-disk framed bytes) since the database was opened.

### Manual Compaction and Flush

```java
ColumnFamily cf = db.getColumnFamily("my_cf");

cf.compact();

cf.flushMemtable();

boolean flushing = cf.isFlushing();
boolean compacting = cf.isCompacting();
```

#### Targeted Range Compaction

`compactRange` runs a synchronous compaction over a specific key range. Only SSTables whose minimum and maximum keys overlap the requested range participate in the merge, so the work and I/O are bounded to the affected portion of the LSM tree rather than the whole column family.

```java
ColumnFamily cf = db.getColumnFamily("my_cf");

byte[] start = "tenant_42:".getBytes(StandardCharsets.UTF_8);
byte[] end   = "tenant_42;".getBytes(StandardCharsets.UTF_8);

cf.compactRange(start, end);
```

**When to use**

- Bulk reclaim after a large range delete, where waiting for natural compaction would leave tombstones and obsolete versions on disk
- Tenant eviction or sliding-window expiration that does not fit TTL semantics
- Post-import cleanup of a known key range loaded with `put` followed by `delete`
- Operational counterpart to the automatic tombstone density trigger when an operator wants reclaim now rather than at the next natural threshold crossing

**Behavior**

- Synchronous, blocks the caller until the merge commits or fails
- Does not enqueue work onto the compaction thread pool, the calling thread does the work
- A `null` or empty endpoint means unbounded on that side; both `null`/empty is rejected with `ERR_INVALID_ARGS` (use `compact()` for full CF compaction)
- Selects only SSTables whose key range overlaps the requested range using the column family's comparator, SSTables outside the range are not touched
- Applies the same emit-loop logic as background compactions (tombstone reclamation rules, single-delete pair cancellation, sequence-based deduplication, value recompression)
- Output SSTables are committed to the manifest atomically and old inputs are marked for deletion

**Return values**

- Returns normally on success
- Throws `TidesDBException` with `ERR_INVALID_ARGS` if both endpoints are null/empty
- Throws `TidesDBException` with `ERR_LOCKED` if another compaction is running for the column family
- Throws `TidesDBException` with standard I/O or memory error codes if the merge cannot complete

### Purge Column Family

Forces a synchronous flush and aggressive compaction for a single column family. Unlike `compact()` and `flushMemtable()` (which are non-blocking), purge blocks until all flush and compaction I/O is complete.

```java
ColumnFamily cf = db.getColumnFamily("my_cf");
cf.purge();
// All data is now flushed to SSTables and compacted
```

**When to use**
- Before backup or checkpoint · Ensure all data is on disk and compacted
- After bulk deletes · Reclaim space immediately by compacting away tombstones
- Manual maintenance · Force a clean state during a maintenance window
- Pre-shutdown · Ensure all pending work is complete before closing

### Purge Database

Forces a synchronous flush and aggressive compaction for **all** column families, then drains both the global flush and compaction queues.

```java
db.purge();
// All CFs flushed and compacted, all queues drained
```

:::tip[Purge vs Manual Flush + Compact]
`flushMemtable()` and `compact()` are non-blocking - they enqueue work and return immediately. `purge()` is synchronous - it blocks until all work is complete. Use purge when you need a guarantee that all data is on disk and compacted before proceeding.
:::

### Fast Shutdown (Cancel Background Work)

`cancelBackgroundWork()` cancels background compaction database-wide so a subsequent `close()` returns quickly. In-flight merges bail safely at their next checkpoint - their uncommitted output is discarded and the inputs are left intact, so no data is lost (recovery handles a mid-merge state the same way). Queued compaction is skipped. Flushes are unaffected, so durability is preserved. The call blocks (bounded) until compaction is idle.

```java
db.cancelBackgroundWork();
db.close();  // returns quickly without waiting for compaction to drain
```

**Behavior**
- The cancellation is sticky for the session and is reset on the next `open()`
- Intended to be called immediately before `close()` for a fast shutdown
- This is the opposite end of the spectrum from `Config.finishCompactionsOnClose(true)`, which instead lets in-flight compactions run to completion before `close()` returns

### Manual WAL Sync

Forces an immediate fsync of the active write-ahead log for a column family. Useful for explicit durability control when using `SYNC_NONE` or `SYNC_INTERVAL` modes.

```java
ColumnFamily cf = db.getColumnFamily("my_cf");
cf.syncWal();
```

**When to use**
- Application-controlled durability · Sync the WAL at specific points after a batch of writes
- Pre-checkpoint · Ensure all buffered WAL data is on disk before taking a checkpoint
- Graceful shutdown · Flush WAL buffers before closing the database
- Critical writes · Force durability for specific high-value writes without using `SYNC_FULL` for all writes

### Range Cost Estimation

Estimate the computational cost of iterating between two keys in a column family. The returned value is an opaque double - meaningful only for comparison with other values from the same method. Uses only in-memory metadata and performs no disk I/O.

```java
ColumnFamily cf = db.getColumnFamily("my_cf");

double costA = cf.rangeCost("user:0000".getBytes(), "user:0999".getBytes());
double costB = cf.rangeCost("user:1000".getBytes(), "user:1099".getBytes());

if (costA < costB) {
    System.out.println("Range A is cheaper to iterate");
}
```

Key order does not matter - the method normalizes the range so `keyA > keyB` produces the same result as `keyB > keyA`. A cost of 0.0 means no overlapping SSTables or memtable entries were found for the range.

**Use cases**
- Query planning · Compare candidate key ranges to find the cheapest one to scan
- Load balancing · Distribute range scan work across threads by estimating per-range cost
- Adaptive prefetching · Decide how aggressively to prefetch based on range size
- Monitoring · Track how data distribution changes across key ranges over time

### Updating Runtime Configuration

Update runtime-safe configuration settings for a column family:

```java
ColumnFamily cf = db.getColumnFamily("my_cf");

ColumnFamilyConfig newConfig = ColumnFamilyConfig.builder()
    .writeBufferSize(256 * 1024 * 1024)  
    .skipListMaxLevel(16)
    .bloomFPR(0.001)  
    .syncMode(SyncMode.SYNC_INTERVAL)
    .syncIntervalUs(100000)  
    .build();

cf.updateRuntimeConfig(newConfig, true);
```

**Updatable settings** (safe to change at runtime):
- `writeBufferSize` · Memtable flush threshold
- `skipListMaxLevel` · Skip list level for new memtables
- `skipListProbability` · Skip list probability for new memtables
- `bloomFPR` · False positive rate for new SSTables
- `indexSampleRatio` · Index sampling ratio for new SSTables
- `syncMode` · Durability mode
- `syncIntervalUs` · Sync interval in microseconds

### Saving and Loading Column Family Config (INI)

A `ColumnFamilyConfig` can be serialized to an INI file and read back. This is useful for templating column family settings, version-controlling configuration, or inspecting the on-disk `config.ini` files the engine writes for each column family.

```java
ColumnFamilyConfig cfConfig = ColumnFamilyConfig.builder()
    .writeBufferSize(96 * 1024 * 1024)
    .compressionAlgorithm(CompressionAlgorithm.ZSTD_COMPRESSION)
    .syncMode(SyncMode.SYNC_INTERVAL)
    .syncIntervalUs(250000)
    .tombstoneDensityTrigger(0.4)
    .useBtree(true)
    .build();

// Write the configuration under a named section
cfConfig.saveToIni("./cf_templates.ini", "analytics_cf");

// Read it back (fields absent from the section fall back to engine defaults)
ColumnFamilyConfig loaded = ColumnFamilyConfig.loadFromIni("./cf_templates.ini", "analytics_cf");

db.createColumnFamily("analytics_cf", loaded);
```

**Behavior**
- `saveToIni(iniFile, section)` is an instance method that writes this configuration under the given `[section]`. If the file exists it is overwritten, then fsynced.
- `loadFromIni(iniFile, section)` is a static factory that returns a new `ColumnFamilyConfig`. Fields missing from the section keep the engine defaults.
- Persisted fields: write buffer size, level ratios, value threshold, compression, bloom/index settings, sync mode and interval, skip-list parameters, default isolation level, compaction triggers, tombstone density settings, min disk space, B+tree and object-store flags, and the comparator name. Runtime-only fields (commit hooks) are not persisted.
- Both methods throw `TidesDBException` on I/O errors (for example, a missing file on load) and `IllegalArgumentException` for null/empty paths or section names.

### Commit Hook (Change Data Capture)

Register a callback that fires synchronously after every transaction commit on a column family. The hook receives the full batch of committed operations atomically, enabling real-time change data capture without WAL parsing.

```java
ColumnFamily cf = db.getColumnFamily("my_cf");

cf.setCommitHook((ops, commitSeq) -> {
    for (CommitOp op : ops) {
        if (op.isDelete()) {
            System.out.println("DELETE key=" + new String(op.getKey()));
        } else {
            System.out.println("PUT key=" + new String(op.getKey())
                + " value=" + new String(op.getValue()));
        }
    }
    System.out.println("Commit seq: " + commitSeq);
    return 0;
});

// Normal writes now trigger the hook automatically
try (Transaction txn = db.beginTransaction()) {
    txn.put(cf, "key1".getBytes(), "value1".getBytes());
    txn.commit();  // hook fires here
}

// Detach hook
cf.clearCommitHook();
```

The `CommitHook` functional interface receives a `CommitOp[]` array and a monotonic `commitSeq` number. Each `CommitOp` contains:
- `getKey()` · Key bytes
- `getValue()` · Value bytes (null for deletes)
- `getTtl()` · Time-to-live (-1 for no expiry)
- `isDelete()` · True if this is a delete operation

**Behavior**
- The hook fires after WAL write, memtable apply, and commit status marking - data is fully durable before the callback runs
- Hook failure (non-zero return) is logged but does not roll back the commit
- Each column family has its own independent hook; a multi-CF transaction fires the hook once per CF with only that CF's operations
- `commitSeq` is monotonically increasing and can be used as a replication cursor
- The hook executes synchronously on the committing thread - keep the callback fast to avoid stalling writers
- Hooks are runtime-only and not persisted. After a database restart, hooks must be re-registered by the application

**Use cases**
- Replication · Ship committed batches to replicas in commit order
- Event streaming · Publish mutations to Kafka, NATS, or any message broker
- Secondary indexing · Maintain a reverse index or materialized view
- Audit logging · Record every mutation with key, value, TTL, and sequence number
- Debugging · Attach a temporary hook in production to inspect live writes

### Multi-Column-Family Transactions

TidesDB supports atomic transactions across multiple column families with true all-or-nothing semantics.

```java
ColumnFamily usersCf = db.getColumnFamily("users");
ColumnFamily ordersCf = db.getColumnFamily("orders");

try (Transaction txn = db.beginTransaction()) {
    txn.put(usersCf, "user:1000".getBytes(), "John Doe".getBytes());
    txn.put(ordersCf, "order:5000".getBytes(), "user:1000|product:A".getBytes());
    
    txn.commit();
}
```

**Multi-CF guarantees**
- Either all CFs commit or none do (atomic)
- Automatically detected when operations span multiple CFs
- Uses global sequence numbers for atomic ordering
- Each CF's WAL receives operations with the same commit sequence number
- No two-phase commit or coordinator overhead

### Custom Comparators

TidesDB uses comparators to determine the sort order of keys. Once a comparator is set for a column family, it cannot be changed without corrupting data.

**Built-in Comparators**
- **`"memcmp"`** (default) · Binary byte-by-byte comparison
- **`"lexicographic"`** · Null-terminated string comparison
- **`"uint64"`** · Unsigned 64-bit integer comparison
- **`"int64"`** · Signed 64-bit integer comparison
- **`"reverse"`** · Reverse binary comparison (descending order)
- **`"case_insensitive"`** · Case-insensitive ASCII comparison

**Registering a Comparator**

```java
db.registerComparator("reverse", null);

ColumnFamilyConfig cfConfig = ColumnFamilyConfig.builder()
    .comparatorName("reverse")
    .build();

db.createColumnFamily("sorted_cf", cfConfig);
```

:::caution[Important]
Comparators must be registered before creating column families that use them. Once set, a comparator cannot be changed for a column family.
:::

### Database Backup

Create an on-disk snapshot without blocking normal reads/writes:

```java
db.backup("./mydb_backup");
```

### Database Checkpoint

Create a lightweight, near-instant snapshot of an open database using hard links instead of copying SSTable data:

```java
db.checkpoint("./mydb_checkpoint");
```

**Checkpoint vs Backup**

| | `backup()` | `checkpoint()` |
|--|---|---|
| Speed | Copies every SSTable byte-by-byte | Near-instant (hard links, O(1) per file) |
| Disk usage | Full independent copy | No extra disk until compaction removes old SSTables |
| Portability | Can be moved to another filesystem or machine | Same filesystem only (hard link requirement) |
| Use case | Archival, disaster recovery, remote shipping | Fast local snapshots, point-in-time reads, streaming backups |

**Behavior**
- Requires the directory to be non-existent or empty
- For each column family, flushes the active memtable, halts compactions, hard links all SSTable files, copies small metadata files, then resumes compactions
- Falls back to file copy if hard linking fails (e.g., cross-filesystem)
- Database stays open and usable during checkpoint
- The checkpoint can be opened as a normal TidesDB database with `TidesDB.open()`

## Object Store Mode

Object store mode allows TidesDB to store SSTables in a remote object store (S3, MinIO, GCS, or any S3-compatible service) while using local disk as a cache. This separates compute from storage and enables cold start recovery from the remote store. Object store mode requires unified memtable mode and is automatically enforced when a connector is set.

:::note[Connector availability]
The Java binding exposes two connectors: the **filesystem connector** (`objectStoreFsPath`), which mirrors objects as files under a directory (ideal for testing and NFS/shared-volume replication), and the **S3 connector** (`objectStoreS3Config`) for AWS S3, MinIO, GCS, and other S3-compatible services. The S3 connector requires a native library built with `-DTIDESDB_WITH_S3=ON`; call `TidesDB.isS3Available()` to probe support at runtime. When S3 is not compiled in, opening an S3-configured database throws a `TidesDBException` explaining that S3 support is missing.
:::

### Enabling Object Store Mode (Filesystem Connector)

```java
ObjectStoreConfig osConfig = ObjectStoreConfig.defaultConfig();

Config config = Config.builder("./mydb")
    .numFlushThreads(2)
    .numCompactionThreads(2)
    .logLevel(LogLevel.INFO)
    .blockCacheSize(64 * 1024 * 1024)
    .maxOpenSSTables(256)
    .objectStoreFsPath("/mnt/nfs/tidesdb-objects")
    .objectStoreConfig(osConfig)
    .build();

try (TidesDB db = TidesDB.open(config)) {
    // SSTables are uploaded after flush
}
```

### Enabling Object Store Mode (S3 Connector)

Back the database with an S3-compatible object store. `endpoint`, `bucket`, `accessKey`, and `secretKey` are required; the remaining fields default to secure, AWS-friendly values (HTTPS on, virtual-hosted URLs, TLS verification enabled). The S3 connector takes precedence over `objectStoreFsPath` when both are set, and composes with `ObjectStoreConfig` for cache, multipart, and WAL-replication tuning.

```java
// Probe support first (requires a core build with -DTIDESDB_WITH_S3=ON)
if (!TidesDB.isS3Available()) {
    throw new IllegalStateException("TidesDB native library was built without S3 support");
}

S3Config s3 = S3Config.builder()
    .endpoint("s3.amazonaws.com")
    .bucket("my-tidesdb-bucket")
    .prefix("production/db1/")     // optional
    .accessKey(System.getenv("AWS_ACCESS_KEY_ID"))
    .secretKey(System.getenv("AWS_SECRET_ACCESS_KEY"))
    .region("us-east-1")
    .build();

Config config = Config.builder("./mydb")
    .objectStoreS3Config(s3)
    .objectStoreConfig(ObjectStoreConfig.builder()
        .localCacheMaxBytes(1024L * 1024 * 1024)  // 1GB local cache
        .maxConcurrentUploads(8)
        .build())
    .build();

try (TidesDB db = TidesDB.open(config)) {
    // SSTables are uploaded to S3 after flush; local disk is used as a cache
}
```

For MinIO or another self-hosted S3 service, use path-style URLs and (for plain HTTP) disable SSL:

```java
S3Config minio = S3Config.builder()
    .endpoint("minio.local:9000")
    .bucket("tidesdb")
    .accessKey("minioadmin")
    .secretKey("minioadmin")
    .usePathStyle(true)   // MinIO requires path-style addressing
    .useSsl(false)        // plain HTTP; omit for HTTPS
    .build();
```

### Custom Object Store Configuration

```java
ObjectStoreConfig osConfig = ObjectStoreConfig.builder()
    .localCacheMaxBytes(512 * 1024 * 1024)  // 512MB local cache
    .maxConcurrentUploads(8)
    .maxConcurrentDownloads(16)
    .cacheOnRead(true)
    .cacheOnWrite(true)
    .syncManifestToObject(true)
    .replicateWal(true)
    .walSyncThresholdBytes(1048576)          // 1MB
    .build();

Config config = Config.builder("./mydb")
    .numFlushThreads(2)
    .numCompactionThreads(2)
    .logLevel(LogLevel.INFO)
    .objectStoreFsPath("/mnt/nfs/tidesdb-objects")
    .objectStoreConfig(osConfig)
    .build();

try (TidesDB db = TidesDB.open(config)) {
    // use the database normally
}
```

### Per-CF Object Store Tuning

Column family configurations include two object store tuning fields:

```java
ColumnFamilyConfig cfConfig = ColumnFamilyConfig.builder()
    .writeBufferSize(128 * 1024 * 1024)
    .compressionAlgorithm(CompressionAlgorithm.LZ4_COMPRESSION)
    .objectLazyCompaction(true)                // compact less aggressively
    .objectPrefetchCompaction(true)            // download all inputs before merge
    .build();

db.createColumnFamily("remote_cf", cfConfig);
```

### Object Store Statistics

`getDbStats()` includes object store fields when a connector is active:

```java
DbStats dbStats = db.getDbStats();

if (dbStats.isObjectStoreEnabled()) {
    System.out.println("Connector: " + dbStats.getObjectStoreConnector());
    System.out.println("Total uploads: " + dbStats.getTotalUploads());
    System.out.println("Upload failures: " + dbStats.getTotalUploadFailures());
    System.out.println("Upload queue depth: " + dbStats.getUploadQueueDepth());
    System.out.println("Local cache: " + dbStats.getLocalCacheBytesUsed()
        + " / " + dbStats.getLocalCacheBytesMax() + " bytes");
}
```

### Cold Start Recovery

When the local database directory is empty but a connector is configured, TidesDB automatically discovers column families from the object store during recovery.

```java
ObjectStoreConfig osConfig = ObjectStoreConfig.defaultConfig();

Config config = Config.builder("./mydb")
    .objectStoreFsPath("/mnt/nfs/tidesdb-objects")
    .objectStoreConfig(osConfig)
    .build();

try (TidesDB db = TidesDB.open(config)) {
    // all data is available -- SSTables are fetched on demand
    ColumnFamily cf = db.getColumnFamily("my_cf");
}
```

### How It Works

- Object store mode requires unified memtable mode. Setting `objectStoreFsPath` automatically enables `unifiedMemtable`
- After each flush, SSTables are uploaded via an asynchronous upload pipeline with retry and post-upload verification
- Point lookups on frozen SSTables fetch just the needed klog block via one HTTP range request
- Iterators prefetch all needed SSTable files in parallel at creation time
- A hash-indexed LRU local file cache manages disk usage when `localCacheMaxBytes` is set
- The MANIFEST is uploaded after each flush and compaction for cold start recovery
- Upload failures are tracked in `totalUploadFailures` on `DbStats`

### Replica Mode

Replica mode enables read-only nodes that follow a primary through the object store.

```java
ObjectStoreConfig osConfig = ObjectStoreConfig.builder()
    .replicaMode(true)
    .replicaSyncIntervalUs(1000000)  // 1 second sync interval
    .replicaReplayWal(true)          // replay WAL for fresh reads
    .build();

Config config = Config.builder("./mydb_replica")
    .objectStoreFsPath("/mnt/nfs/tidesdb-objects")  // same path as primary
    .objectStoreConfig(osConfig)
    .build();

try (TidesDB db = TidesDB.open(config)) {
    // reads work normally
    ColumnFamily cf = db.getColumnFamily("my_cf");
    try (Transaction txn = db.beginTransaction()) {
        byte[] value = txn.get(cf, "key".getBytes());
        // writes throw TidesDBException with ERR_READONLY
    }
}
```

### Sync-on-Commit WAL (Primary Side)

For tighter replication lag, enable sync-on-commit on the primary:

```java
ObjectStoreConfig osConfig = ObjectStoreConfig.builder()
    .walSyncOnCommit(true)  // RPO = 0, every commit is durable in object store
    .build();
// replica sees committed data within one replicaSyncIntervalUs
```

### Promote Replica to Primary

When the primary fails, promote a replica to accept writes:

```java
db.promoteToPrimary();
// now writes are accepted
```

### Renaming Column Families

Atomically rename a column family:

```java
db.renameColumnFamily("old_name", "new_name");
```

### Cloning Column Families

Create a complete copy of an existing column family with a new name. The clone is completely independent; modifications to one do not affect the other.

```java
db.cloneColumnFamily("source_cf", "cloned_cf");

ColumnFamily original = db.getColumnFamily("source_cf");
ColumnFamily clone = db.getColumnFamily("cloned_cf");
```

**Use cases**
- Testing · Create a copy of production data for testing without affecting the original
- Branching · Create a snapshot of data before making experimental changes
- Migration · Clone data before schema or configuration changes
- Backup verification · Clone and verify data integrity without modifying the source

### B+tree KLog Format (Optional)

Column families can optionally use a B+tree structure for the key log instead of the default block-based format. The B+tree klog format offers faster point lookups through O(log N) tree traversal.

```java
ColumnFamilyConfig btreeConfig = ColumnFamilyConfig.builder()
    .writeBufferSize(128 * 1024 * 1024)
    .compressionAlgorithm(CompressionAlgorithm.LZ4_COMPRESSION)
    .enableBloomFilter(true)
    .useBtree(true)  
    .build();

db.createColumnFamily("btree_cf", btreeConfig);

ColumnFamily cf = db.getColumnFamily("btree_cf");

try (Transaction txn = db.beginTransaction()) {
    txn.put(cf, "key".getBytes(), "value".getBytes());
    txn.commit();
}

Stats stats = cf.getStats();
if (stats.isUseBtree()) {
    System.out.println("B+tree nodes: " + stats.getBtreeTotalNodes());
    System.out.println("B+tree max height: " + stats.getBtreeMaxHeight());
    System.out.println("B+tree avg height: " + stats.getBtreeAvgHeight());
}
```

**When to use B+tree klog format**
- Read-heavy workloads with frequent point lookups
- Workloads where read latency is more important than write throughput
- Large SSTables where block scanning becomes expensive

**Tradeoffs**
- Slightly higher write amplification during flush
- Larger metadata overhead per node
- Block-based format may be faster for sequential scans

:::caution[Important]
`useBtree` cannot be changed after column family creation.
:::

### Transaction Isolation Levels

```java
try (Transaction txn = db.beginTransaction(IsolationLevel.SERIALIZABLE)) {
    txn.commit();
}
```

**Available Isolation Levels**
- `READ_UNCOMMITTED` · Sees all data including uncommitted changes
- `READ_COMMITTED` · Sees only committed data (default)
- `REPEATABLE_READ` · Consistent snapshot, phantom reads possible
- `SNAPSHOT` · Write-write conflict detection
- `SERIALIZABLE` · Full read-write conflict detection (SSI)

### Savepoints

Savepoints allow partial rollback within a transaction:

```java
try (Transaction txn = db.beginTransaction()) {
    txn.put(cf, "key1".getBytes(), "value1".getBytes());
    
    txn.savepoint("sp1");
    txn.put(cf, "key2".getBytes(), "value2".getBytes());
    
    txn.rollbackToSavepoint("sp1");
    
    txn.commit();
}
```

**Savepoint API**
- `savepoint(name)` · Create a savepoint
- `rollbackToSavepoint(name)` · Rollback to savepoint
- `releaseSavepoint(name)` · Release savepoint without rolling back

### Transaction Reset

`reset` resets a committed or aborted transaction for reuse with a new isolation level. This avoids the overhead of freeing and reallocating transaction resources in hot loops.

```java
ColumnFamily cf = db.getColumnFamily("my_cf");

Transaction txn = db.beginTransaction();
txn.put(cf, "key1".getBytes(), "value1".getBytes());
txn.commit();

txn.reset(IsolationLevel.READ_COMMITTED);

txn.put(cf, "key2".getBytes(), "value2".getBytes());
txn.commit();

txn.free();
```

**Behavior**
- The transaction must be committed or aborted before reset; resetting an active transaction throws `TidesDBException`
- Internal buffers are retained to avoid reallocation
- A fresh transaction ID and snapshot sequence are assigned based on the new isolation level
- The isolation level can be changed on each reset (e.g., `READ_COMMITTED` to `REPEATABLE_READ`)

**When to use**
- Batch processing · Reuse a single transaction across many commit cycles in a loop
- Connection pooling · Reset a transaction for a new request without reallocation
- High-throughput ingestion · Reduce allocation overhead in tight write loops

**Reset vs Free + Begin**

For a single transaction, `reset` is functionally equivalent to calling `free` followed by `beginTransaction`. The difference is performance, reset retains allocated buffers and avoids repeated allocation overhead. This matters most in loops that commit and restart thousands of transactions.

## Configuration Options

### Database Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dbPath` | String | - | Path to the database directory |
| `numFlushThreads` | int | 2 | Number of flush threads |
| `numCompactionThreads` | int | 2 | Number of compaction threads |
| `logLevel` | LogLevel | INFO | Logging level |
| `blockCacheSize` | long | 64MB | Block cache size in bytes |
| `maxOpenSSTables` | long | 256 | Maximum open SSTable files |
| `logToFile` | boolean | false | Write logs to file instead of stderr |
| `logTruncationAt` | long | 24MB | Log file truncation size (0 = no truncation) |
| `maxMemoryUsage` | long | 0 | Global memory limit in bytes (0 = auto, 50% of system RAM) |
| `unifiedMemtable` | boolean | false | Enable unified memtable mode (single memtable + WAL for all CFs) |
| `unifiedMemtableWriteBufferSize` | long | 0 | Unified memtable write buffer size (0 = auto, 64MB) |
| `unifiedMemtableSkipListMaxLevel` | int | 0 | Skip list max level for unified memtable (0 = default 12) |
| `unifiedMemtableSkipListProbability` | float | 0 | Skip list probability for unified memtable (0 = default 0.25) |
| `unifiedMemtableSyncMode` | int | 0 | Sync mode for unified WAL (0 = SYNC_NONE) |
| `unifiedMemtableSyncIntervalUs` | long | 0 | Sync interval for unified WAL in microseconds |
| `objectStoreFsPath` | String | null | Filesystem connector root directory (null = no object store) |
| `objectStoreConfig` | ObjectStoreConfig | null | Object store behavior configuration (null = use defaults) |
| `maxConcurrentFlushes` | int | 0 (library default) | Global semaphore on in-flight memtable flushes across all CFs (0 = library default) |
| `finishCompactionsOnClose` | boolean | false | Close behavior. `false` cancels in-flight compactions at their next checkpoint for a fast shutdown (no data is lost; recovery handles a mid-merge state). `true` lets in-flight compactions run to completion before `close()` returns |

### Object Store Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `localCachePath` | String | null | Local directory for cached SSTable files (null = use db_path) |
| `localCacheMaxBytes` | long | 0 | Maximum local cache size in bytes (0 = unlimited) |
| `cacheOnRead` | boolean | true | Cache downloaded files locally |
| `cacheOnWrite` | boolean | true | Keep local copy after upload |
| `maxConcurrentUploads` | int | 4 | Number of parallel upload threads |
| `maxConcurrentDownloads` | int | 8 | Number of parallel download threads |
| `multipartThreshold` | long | 64MB | Use multipart upload above this size |
| `multipartPartSize` | long | 8MB | Chunk size for multipart uploads |
| `syncManifestToObject` | boolean | true | Upload MANIFEST after each compaction |
| `replicateWal` | boolean | true | Upload closed WAL segments for replication |
| `walUploadSync` | boolean | false | false = background WAL upload, true = block flush until uploaded |
| `walSyncThresholdBytes` | long | 1MB | Sync active WAL when it grows by this many bytes (0 = disable) |
| `walSyncOnCommit` | boolean | false | Upload WAL after every txn commit for RPO=0 replication |
| `replicaMode` | boolean | false | Enable read-only replica mode |
| `replicaSyncIntervalUs` | long | 5000000 | MANIFEST poll interval for replica sync in microseconds |
| `replicaReplayWal` | boolean | true | Replay WAL from object store for near-real-time reads on replicas |

### S3 Connector Configuration

`S3Config` selects an S3-compatible backend (set via `Config.Builder.objectStoreS3Config`). Requires a native build with `-DTIDESDB_WITH_S3=ON`; probe with `TidesDB.isS3Available()`.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `endpoint` | String | — (required) | S3 endpoint, e.g. `s3.amazonaws.com` or `minio.local:9000` |
| `bucket` | String | — (required) | Bucket name |
| `prefix` | String | null | Key prefix, e.g. `production/db1/` |
| `accessKey` | String | — (required) | AWS access key ID |
| `secretKey` | String | — (required) | AWS secret access key |
| `region` | String | null | AWS region, e.g. `us-east-1`; null for MinIO/default |
| `useSsl` | boolean | true | HTTPS when true, HTTP when false |
| `usePathStyle` | boolean | false | Path-style URLs (MinIO) when true, virtual-hosted (AWS) when false |
| `tlsCaPath` | String | null | Custom CA bundle file path, or null for the system bundle |
| `tlsInsecureSkipVerify` | boolean | false | Disable TLS peer/host verification (test only, insecure) |
| `multipartThreshold` | long | 0 (library default) | Object size at/above which multipart upload is used |
| `multipartPartSize` | long | 0 (library default) | Multipart chunk size in bytes |

### Column Family Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `writeBufferSize` | long | 128MB | Memtable flush threshold |
| `levelSizeRatio` | long | 10 | Level size multiplier |
| `minLevels` | int | 5 | Minimum LSM levels |
| `dividingLevelOffset` | int | 2 | Compaction dividing level offset |
| `klogValueThreshold` | long | 512 | Values > threshold go to vlog |
| `compressionAlgorithm` | CompressionAlgorithm | LZ4_COMPRESSION | Compression algorithm |
| `enableBloomFilter` | boolean | true | Enable bloom filters |
| `bloomFPR` | double | 0.01 | Bloom filter false positive rate (1%) |
| `enableBlockIndexes` | boolean | true | Enable compact block indexes |
| `indexSampleRatio` | int | 1 | Sample every block for index |
| `blockIndexPrefixLen` | int | 16 | Block index prefix length |
| `syncMode` | SyncMode | SYNC_FULL | Sync mode for durability |
| `syncIntervalUs` | long | 1000000 | Sync interval (1 second, for SYNC_INTERVAL) |
| `comparatorName` | String | "" | Custom comparator name (empty = memcmp) |
| `skipListMaxLevel` | int | 12 | Skip list max level |
| `skipListProbability` | float | 0.25 | Skip list probability |
| `defaultIsolationLevel` | IsolationLevel | READ_COMMITTED | Default transaction isolation |
| `minDiskSpace` | long | 100MB | Minimum disk space required |
| `l1FileCountTrigger` | int | 4 | L1 file count trigger for compaction |
| `l0QueueStallThreshold` | int | 20 | L0 queue stall threshold |
| `tombstoneDensityTrigger` | double | 0.0 | Per-SSTable tombstone density above which compaction priority escalates (0.0 = disabled, range 0.0 to 1.0) |
| `tombstoneDensityMinEntries` | long | 1024 | Minimum entry count for an SSTable to be considered by the tombstone density trigger |
| `useBtree` | boolean | false | Use B+tree format for klog (faster point lookups) |
| `objectLazyCompaction` | boolean | false | Compact less aggressively for remote storage |
| `objectPrefetchCompaction` | boolean | true | Download all inputs before compaction merge |

### Compression Algorithms

| Algorithm | Value | Description |
|-----------|-------|-------------|
| `NO_COMPRESSION` | 0 | No compression |
| `SNAPPY_COMPRESSION` | 1 | Snappy compression |
| `LZ4_COMPRESSION` | 2 | LZ4 standard compression (default) |
| `ZSTD_COMPRESSION` | 3 | Zstandard compression (best ratio) |
| `LZ4_FAST_COMPRESSION` | 4 | LZ4 fast mode (higher throughput) |

### Sync Modes

| Mode | Description |
|------|-------------|
| `SYNC_NONE` | No explicit sync, relies on OS page cache (fastest) |
| `SYNC_FULL` | Fsync on every write (most durable) |
| `SYNC_INTERVAL` | Periodic background syncing at configurable intervals |

### Error Codes

| Code | Value | Description |
|------|-------|-------------|
| `ERR_SUCCESS` | 0 | Operation completed successfully |
| `ERR_MEMORY` | -1 | Memory allocation failed |
| `ERR_INVALID_ARGS` | -2 | Invalid arguments passed |
| `ERR_NOT_FOUND` | -3 | Key not found |
| `ERR_IO` | -4 | I/O operation failed |
| `ERR_CORRUPTION` | -5 | Data corruption detected |
| `ERR_EXISTS` | -6 | Resource already exists |
| `ERR_CONFLICT` | -7 | Transaction conflict detected |
| `ERR_TOO_LARGE` | -8 | Key or value size exceeds maximum |
| `ERR_MEMORY_LIMIT` | -9 | Memory limit exceeded |
| `ERR_INVALID_DB` | -10 | Database handle is invalid |
| `ERR_UNKNOWN` | -11 | Unknown error |
| `ERR_LOCKED` | -12 | Database is locked |
| `ERR_READONLY` | -13 | Database is read-only (replica mode) |
| `ERR_BUSY` | -14 | Resource is busy |

## Testing

```bash
# Run all tests
mvn test

# Run specific test
mvn test -Dtest=TidesDBTest#testOpenClose

# Run with verbose output
mvn test -X
```

## Building from Source

```bash
# Clone the repository
git clone https://github.com/tidesdb/tidesdb-java.git
cd tidesdb-java

# Build the JNI library
cd src/main/c
cmake -S . -B build
cmake --build build
sudo cmake --install build
cd ../../..

# Build the Java package
mvn clean package

# Install to local Maven repository
mvn install
```

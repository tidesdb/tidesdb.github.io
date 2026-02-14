---
title: TidesDB Java API Reference
description: Complete Java API reference for TidesDB
---

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/java.md).

<hr/>

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
    <version>0.3.0</version>
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
            .build();
        
        try (TidesDB db = TidesDB.open(config)) {
            System.out.println("Database opened successfully");
        }
    }
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
    .build();

db.createColumnFamily("custom_cf", customConfig);

db.dropColumnFamily("my_cf");

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

#### Seeking to a Specific Key

```java
try (TidesDBIterator iter = txn.newIterator(cf)) {
    iter.seek("prefix".getBytes());
    
    iter.seekForPrev("prefix".getBytes());
}
```

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
| `config` | ColumnFamilyConfig | Column family configuration |

### Getting Cache Statistics

```java
CacheStats cacheStats = db.getCacheStats();

System.out.println("Cache enabled: " + cacheStats.isEnabled());
System.out.println("Total entries: " + cacheStats.getTotalEntries());
System.out.println("Hit rate: " + cacheStats.getHitRate());
```

### Manual Compaction and Flush

```java
ColumnFamily cf = db.getColumnFamily("my_cf");

cf.compact();

cf.flushMemtable();

boolean flushing = cf.isFlushing();
boolean compacting = cf.isCompacting();
```

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
- For each column family: flushes the active memtable, halts compactions, hard links all SSTable files, copies small metadata files, then resumes compactions
- Falls back to file copy if hard linking fails (e.g., cross-filesystem)
- Database stays open and usable during checkpoint
- The checkpoint can be opened as a normal TidesDB database with `TidesDB.open()`

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

For a single transaction, `reset` is functionally equivalent to calling `free` followed by `beginTransaction`. The difference is performance: reset retains allocated buffers and avoids repeated allocation overhead. This matters most in loops that commit and restart thousands of transactions.

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
| `useBtree` | boolean | false | Use B+tree format for klog (faster point lookups) |

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

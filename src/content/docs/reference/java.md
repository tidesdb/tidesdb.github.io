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

**Maven:**
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

// Drop column family
db.dropColumnFamily("my_cf");

// List all column families
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
    // Put a key-value pair (no expiration)
    txn.put(cf, "key".getBytes(), "value".getBytes());
    txn.commit();
}
```

#### Writing with TTL

```java
import java.time.Instant;

ColumnFamily cf = db.getColumnFamily("my_cf");

try (Transaction txn = db.beginTransaction()) {
    // Set expiration time (Unix timestamp in seconds)
    long ttl = Instant.now().getEpochSecond() + 10; // Expire in 10 seconds
    
    txn.put(cf, "temp_key".getBytes(), "temp_value".getBytes(), ttl);
    txn.commit();
}
```

**TTL Examples:**
```java
// No expiration
long ttl = -1;

// Expire in 5 minutes
long ttl = Instant.now().getEpochSecond() + 300;

// Expire in 1 hour
long ttl = Instant.now().getEpochSecond() + 3600;

// Expire at specific time
long ttl = Instant.parse("2026-12-31T23:59:59Z").getEpochSecond();
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
    // Multiple operations in one transaction
    txn.put(cf, "key1".getBytes(), "value1".getBytes());
    txn.put(cf, "key2".getBytes(), "value2".getBytes());
    txn.delete(cf, "old_key".getBytes());
    
    // Commit atomically -- all or nothing
    txn.commit();
} catch (TidesDBException e) {
    // Transaction is automatically rolled back on exception
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
    // Seek to first key >= target
    iter.seek("prefix".getBytes());
    
    // Seek to last key <= target
    iter.seekForPrev("prefix".getBytes());
}
```

### Getting Column Family Statistics

```java
ColumnFamily cf = db.getColumnFamily("my_cf");
Stats stats = cf.getStats();

System.out.println("Number of levels: " + stats.getNumLevels());
System.out.println("Memtable size: " + stats.getMemtableSize());
```

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

// Trigger compaction
cf.compact();

// Flush memtable to disk
cf.flushMemtable();

// Check if operations are in progress
boolean flushing = cf.isFlushing();
boolean compacting = cf.isCompacting();
```

### Updating Runtime Configuration

Update runtime-safe configuration settings for a column family:

```java
ColumnFamily cf = db.getColumnFamily("my_cf");

ColumnFamilyConfig newConfig = ColumnFamilyConfig.builder()
    .writeBufferSize(256 * 1024 * 1024)  // 256MB
    .skipListMaxLevel(16)
    .bloomFPR(0.001)  // 0.1% false positive rate
    .syncMode(SyncMode.SYNC_INTERVAL)
    .syncIntervalUs(100000)  // 100ms
    .build();

// Update config and persist to disk
cf.updateRuntimeConfig(newConfig, true);
```

**Updatable settings** (safe to change at runtime):
- `writeBufferSize` - Memtable flush threshold
- `skipListMaxLevel` - Skip list level for new memtables
- `skipListProbability` - Skip list probability for new memtables
- `bloomFPR` - False positive rate for new SSTables
- `indexSampleRatio` - Index sampling ratio for new SSTables
- `syncMode` - Durability mode
- `syncIntervalUs` - Sync interval in microseconds

### Database Backup

Create an on-disk snapshot without blocking normal reads/writes:

```java
// Backup to a directory (must be non-existent or empty)
db.backup("./mydb_backup");
```

### Renaming Column Families

Atomically rename a column family:

```java
// Waits for any in-progress flush/compaction to complete
db.renameColumnFamily("old_name", "new_name");
```

### Transaction Isolation Levels

```java
// Begin transaction with specific isolation level
try (Transaction txn = db.beginTransaction(IsolationLevel.SERIALIZABLE)) {
    // Operations with serializable isolation
    txn.commit();
}
```

**Available Isolation Levels:**
- `READ_UNCOMMITTED` - Sees all data including uncommitted changes
- `READ_COMMITTED` - Sees only committed data (default)
- `REPEATABLE_READ` - Consistent snapshot, phantom reads possible
- `SNAPSHOT` - Write-write conflict detection
- `SERIALIZABLE` - Full read-write conflict detection (SSI)

### Savepoints

Savepoints allow partial rollback within a transaction:

```java
try (Transaction txn = db.beginTransaction()) {
    txn.put(cf, "key1".getBytes(), "value1".getBytes());
    
    // Create savepoint
    txn.savepoint("sp1");
    txn.put(cf, "key2".getBytes(), "value2".getBytes());
    
    // Rollback to savepoint -- key2 is discarded, key1 remains
    txn.rollbackToSavepoint("sp1");
    
    // Or release savepoint without rolling back
    // txn.releaseSavepoint("sp1");
    
    // Commit -- only key1 is written
    txn.commit();
}
```

**Savepoint API:**
- `savepoint(name)` - Create a savepoint
- `rollbackToSavepoint(name)` - Rollback to savepoint
- `releaseSavepoint(name)` - Release savepoint without rolling back

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

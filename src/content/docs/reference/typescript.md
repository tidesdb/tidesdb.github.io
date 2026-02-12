---
title: TidesDB TypeScript API Reference
description: TypeScript API reference for TidesDB
---

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/typescript.md).

<hr/>

## Getting Started

### Prerequisites

You **must** have the TidesDB shared C library installed on your system.  You can find the installation instructions [here](/reference/building/#_top).

### Installation

```bash
npm install git+https://github.com/tidesdb/tidesdb-node.git
```

Or clone and install locally:

```bash
git clone https://github.com/tidesdb/tidesdb-node.git
cd tidesdb-node
npm install
npm run build
npm link

# In your project directory
npm link tidesdb
```

### Custom Installation Paths

If you installed TidesDB to a non-standard location, you can specify custom paths using environment variables:

```bash
# Linux
export LD_LIBRARY_PATH="/custom/path/lib:$LD_LIBRARY_PATH"

# macOS
export DYLD_LIBRARY_PATH="/custom/path/lib:$DYLD_LIBRARY_PATH"

# Windows (add to PATH)
set PATH=C:\custom\path\bin;%PATH%
```

**Custom prefix installation**
```bash
# Install TidesDB to custom location
cd tidesdb
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/opt/tidesdb
cmake --build build
sudo cmake --install build

# Configure environment to use custom location
export LD_LIBRARY_PATH="/opt/tidesdb/lib:$LD_LIBRARY_PATH"  # Linux
# or
export DYLD_LIBRARY_PATH="/opt/tidesdb/lib:$DYLD_LIBRARY_PATH"  # macOS

npm install tidesdb
```

## Usage

### Opening and Closing a Database

```typescript
import { TidesDB, LogLevel } from 'tidesdb';

const db = TidesDB.open({
  dbPath: './mydb',
  numFlushThreads: 2,
  numCompactionThreads: 2,
  logLevel: LogLevel.Info,
  blockCacheSize: 64 * 1024 * 1024,
  maxOpenSSTables: 256,
  logToFile: false,           // Write logs to file instead of stderr
  logTruncationAt: 24 * 1024 * 1024,  // Log file truncation size (24MB), 0 = no truncation
});

console.log('Database opened successfully');

db.close();
```

### Creating and Dropping Column Families

Column families are isolated key-value stores with independent configuration.

```typescript
import { 
  TidesDB, 
  CompressionAlgorithm, 
  SyncMode, 
  IsolationLevel,
  defaultColumnFamilyConfig 
} from 'tidesdb';

db.createColumnFamily('my_cf');

db.createColumnFamily('my_cf', {
  writeBufferSize: 128 * 1024 * 1024,
  levelSizeRatio: 10,
  minLevels: 5,
  compressionAlgorithm: CompressionAlgorithm.Lz4Compression,
  enableBloomFilter: true,
  bloomFpr: 0.01,
  enableBlockIndexes: true,
  syncMode: SyncMode.Interval,
  syncIntervalUs: 128000,
  defaultIsolationLevel: IsolationLevel.ReadCommitted,
  useBtree: false,  // Use B+tree format for klog (default: false = block-based)
});

db.dropColumnFamily('my_cf');

db.renameColumnFamily('old_name', 'new_name');

db.cloneColumnFamily('source_cf', 'cloned_cf');
```

### CRUD Operations

All operations in TidesDB are performed through transactions for ACID guarantees.

#### Writing Data

```typescript
const cf = db.getColumnFamily('my_cf');

const txn = db.beginTransaction();

txn.put(cf, Buffer.from('key'), Buffer.from('value'), -1);

txn.commit();
txn.free();
```

#### Writing with TTL

```typescript
const cf = db.getColumnFamily('my_cf');

const txn = db.beginTransaction();

const ttl = Math.floor(Date.now() / 1000) + 10;

txn.put(cf, Buffer.from('temp_key'), Buffer.from('temp_value'), ttl);

txn.commit();
txn.free();
```

**TTL Examples**
```typescript
const ttl = -1;

const ttl = Math.floor(Date.now() / 1000) + 5 * 60;

const ttl = Math.floor(Date.now() / 1000) + 60 * 60;

const ttl = Math.floor(new Date('2026-12-31T23:59:59Z').getTime() / 1000);
```

#### Reading Data

```typescript
const cf = db.getColumnFamily('my_cf');

const txn = db.beginTransaction();

const value = txn.get(cf, Buffer.from('key'));
console.log(`Value: ${value.toString()}`);

txn.free();
```

#### Deleting Data

```typescript
const cf = db.getColumnFamily('my_cf');

const txn = db.beginTransaction();

txn.delete(cf, Buffer.from('key'));

txn.commit();
txn.free();
```

#### Multi-Operation Transactions

```typescript
const cf = db.getColumnFamily('my_cf');

const txn = db.beginTransaction();

try {
  txn.put(cf, Buffer.from('key1'), Buffer.from('value1'), -1);
  txn.put(cf, Buffer.from('key2'), Buffer.from('value2'), -1);
  txn.delete(cf, Buffer.from('old_key'));

  txn.commit();
} catch (err) {
  txn.rollback();
  throw err;
} finally {
  txn.free();
}
```

### Iterating Over Data

Iterators provide efficient bidirectional traversal over key-value pairs.

#### Forward Iteration

```typescript
const cf = db.getColumnFamily('my_cf');

const txn = db.beginTransaction();
const iter = txn.newIterator(cf);

iter.seekToFirst();

while (iter.isValid()) {
  const key = iter.key();
  const value = iter.value();
  
  console.log(`Key: ${key.toString()}, Value: ${value.toString()}`);
  
  iter.next();
}

iter.free();
txn.free();
```

#### Backward Iteration

```typescript
const cf = db.getColumnFamily('my_cf');

const txn = db.beginTransaction();
const iter = txn.newIterator(cf);

iter.seekToLast();

while (iter.isValid()) {
  const key = iter.key();
  const value = iter.value();
  
  console.log(`Key: ${key.toString()}, Value: ${value.toString()}`);
  
  iter.prev();
}

iter.free();
txn.free();
```

#### Seek to Specific Key

```typescript
const cf = db.getColumnFamily('my_cf');

const txn = db.beginTransaction();
const iter = txn.newIterator(cf);

iter.seek(Buffer.from('user:1000'));

if (iter.isValid()) {
  console.log(`Found: ${iter.key().toString()}`);
}

iter.free();
txn.free();
```

#### Seek for Previous

```typescript
const cf = db.getColumnFamily('my_cf');

const txn = db.beginTransaction();
const iter = txn.newIterator(cf);

iter.seekForPrev(Buffer.from('user:2000'));

while (iter.isValid()) {
  console.log(`Key: ${iter.key().toString()}`);
  iter.prev();
}

iter.free();
txn.free();
```

#### Prefix Scanning

```typescript
const cf = db.getColumnFamily('my_cf');

const txn = db.beginTransaction();
const iter = txn.newIterator(cf);

const prefix = 'user:';
iter.seek(Buffer.from(prefix));

while (iter.isValid()) {
  const key = iter.key().toString();
  
  if (!key.startsWith(prefix)) break;
  
  console.log(`Found: ${key}`);
  iter.next();
}

iter.free();
txn.free();
```

### Getting Column Family Statistics

Retrieve detailed statistics about a column family.

```typescript
const cf = db.getColumnFamily('my_cf');

const stats = cf.getStats();

console.log(`Number of Levels: ${stats.numLevels}`);
console.log(`Memtable Size: ${stats.memtableSize} bytes`);
console.log(`Total Keys: ${stats.totalKeys}`);
console.log(`Total Data Size: ${stats.totalDataSize} bytes`);
console.log(`Average Key Size: ${stats.avgKeySize} bytes`);
console.log(`Average Value Size: ${stats.avgValueSize} bytes`);
console.log(`Read Amplification: ${stats.readAmp}`);
console.log(`Cache Hit Rate: ${stats.hitRate}`);

for (let i = 0; i < stats.numLevels; i++) {
  console.log(`Level ${i + 1}: ${stats.levelNumSSTables[i]} SSTables, ${stats.levelSizes[i]} bytes, ${stats.levelKeyCounts[i]} keys`);
}

if (stats.useBtree) {
  console.log(`B+tree Total Nodes: ${stats.btreeTotalNodes}`);
  console.log(`B+tree Max Height: ${stats.btreeMaxHeight}`);
  console.log(`B+tree Avg Height: ${stats.btreeAvgHeight}`);
}

if (stats.config) {
  console.log(`Write Buffer Size: ${stats.config.writeBufferSize}`);
  console.log(`Compression: ${stats.config.compressionAlgorithm}`);
  console.log(`Bloom Filter: ${stats.config.enableBloomFilter}`);
  console.log(`Sync Mode: ${stats.config.syncMode}`);
}
```

### Listing Column Families

```typescript
const cfList = db.listColumnFamilies();

console.log('Available column families:');
for (const name of cfList) {
  console.log(`  - ${name}`);
}
```

### Backup

Create an on-disk backup of the database without blocking reads/writes.

```typescript
db.backup('./mydb_backup');
```

**Behavior**
- Requires the backup directory to be non-existent or empty
- Does not copy the `LOCK` file, so the backup can be opened normally
- Database stays open and usable during backup
- The backup represents the database state after all pending flushes complete

### Checkpoint

Create a lightweight, near-instant snapshot of the database using hard links instead of copying SSTable data.

```typescript
db.checkpoint('./mydb_checkpoint');
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

**Checkpoint vs Backup**

| | `backup()` | `checkpoint()` |
|--|---|---|
| Speed | Copies every SSTable byte-by-byte | Near-instant (hard links, O(1) per file) |
| Disk usage | Full independent copy | No extra disk until compaction removes old SSTables |
| Portability | Can be moved to another filesystem or machine | Same filesystem only (hard link requirement) |
| Use case | Archival, disaster recovery, remote shipping | Fast local snapshots, point-in-time reads, streaming backups |

**Notes**
- The checkpoint can be opened as a normal TidesDB database with `TidesDB.open()`
- Hard-linked files share storage with the live database. Deleting the original database does not affect the checkpoint

**Return values**
- Throws `TidesDBError` with `ErrorCode.ErrExists` if checkpoint directory is not empty
- Throws `TidesDBError` with `ErrorCode.ErrInvalidArgs` for invalid arguments

### Cloning a Column Family

Create a complete copy of an existing column family with a new name. The clone contains all the data from the source at the time of cloning and is completely independent.

```typescript
db.cloneColumnFamily('source_cf', 'cloned_cf');

const original = db.getColumnFamily('source_cf');
const clone = db.getColumnFamily('cloned_cf');
```

**Behavior**
- Flushes the source column family's memtable to ensure all data is on disk
- Waits for any in-progress flush or compaction to complete
- Copies all SSTable files to the new directory
- The clone is completely independent -- modifications to one do not affect the other

**Use cases**
- Testing · Create a copy of production data for testing without affecting the original
- Branching · Create a snapshot of data before making experimental changes
- Migration · Clone data before schema or configuration changes
- Backup verification · Clone and verify data integrity without modifying the source

**Return values**
- Throws `TidesDBError` with `ErrorCode.ErrNotFound` if source column family doesn't exist
- Throws `TidesDBError` with `ErrorCode.ErrExists` if destination column family already exists
- Throws `TidesDBError` with `ErrorCode.ErrInvalidArgs` for invalid arguments

### Compaction

#### Manual Compaction

```typescript
const cf = db.getColumnFamily('my_cf');

cf.compact();
```

#### Manual Memtable Flush

```typescript
const cf = db.getColumnFamily('my_cf');

cf.flushMemtable();
```

#### Checking Flush/Compaction Status

Check if a column family has background operations in progress.

```typescript
const cf = db.getColumnFamily('my_cf');

if (cf.isFlushing()) {
  console.log('Flush in progress');
}

if (cf.isCompacting()) {
  console.log('Compaction in progress');
}
```

**Use cases**
- Graceful shutdown · Wait for background operations to complete before closing
- Maintenance windows · Check if operations are running before triggering manual compaction
- Monitoring · Track background operation status for observability

### Updating Runtime Configuration

Update runtime-safe configuration settings. Changes apply to new operations only.

```typescript
const cf = db.getColumnFamily('my_cf');

// Update configuration (changes apply to new operations)
cf.updateRuntimeConfig({
  writeBufferSize: 256 * 1024 * 1024,  // 256MB
  skipListMaxLevel: 16,
  skipListProbability: 0.25,
  bloomFpr: 0.001,  // 0.1% false positive rate
  indexSampleRatio: 8,  // sample 1 in 8 keys
  syncMode: SyncMode.Interval,
  syncIntervalUs: 100000,  // 100ms
}, true);  // persist to disk (config.ini)
```

**Updatable settings** (safe to change at runtime):
- `writeBufferSize` · Memtable flush threshold
- `skipListMaxLevel` · Skip list level for new memtables
- `skipListProbability` · Skip list probability for new memtables
- `bloomFpr` · False positive rate for new SSTables
- `indexSampleRatio` · Index sampling ratio for new SSTables
- `syncMode` · Durability mode
- `syncIntervalUs` · Sync interval in microseconds

**Non-updatable settings** (would corrupt existing data):
- `compressionAlgorithm`, `enableBlockIndexes`, `enableBloomFilter`, `comparatorName`, `levelSizeRatio`, `klogValueThreshold`, `minLevels`, `dividingLevelOffset`, `blockIndexPrefixLen`, `l1FileCountTrigger`, `l0QueueStallThreshold`, `useBtree`

### Sync Modes

Control the durability vs performance tradeoff.

```typescript
import { SyncMode } from 'tidesdb';

// SyncNone -- Fastest, least durable (OS handles flushing)
db.createColumnFamily('fast_cf', {
  syncMode: SyncMode.None,
});

// SyncInterval -- Balanced (periodic background syncing)
db.createColumnFamily('balanced_cf', {
  syncMode: SyncMode.Interval,
  syncIntervalUs: 128000, // Sync every 128ms
});

// SyncFull -- Most durable (fsync on every write)
db.createColumnFamily('durable_cf', {
  syncMode: SyncMode.Full,
});
```

### Compression Algorithms

TidesDB supports multiple compression algorithms:

```typescript
import { CompressionAlgorithm } from 'tidesdb';

db.createColumnFamily('no_compress', {
  compressionAlgorithm: CompressionAlgorithm.NoCompression,
});

db.createColumnFamily('lz4_cf', {
  compressionAlgorithm: CompressionAlgorithm.Lz4Compression,
});

db.createColumnFamily('lz4_fast_cf', {
  compressionAlgorithm: CompressionAlgorithm.Lz4FastCompression,
});

db.createColumnFamily('zstd_cf', {
  compressionAlgorithm: CompressionAlgorithm.ZstdCompression,
});
```

### B+tree KLog Format (Optional)

Column families can optionally use a B+tree structure for the key log instead of the default block-based format. The B+tree klog format offers faster point lookups through O(log N) tree traversal.

```typescript
// Create column family with B+tree klog format
db.createColumnFamily('btree_cf', {
  useBtree: true,
  enableBloomFilter: true,
  bloomFpr: 0.01,
});

// Check if column family uses B+tree klog format
const cf = db.getColumnFamily('btree_cf');
const stats = cf.getStats();

console.log(`Uses B+tree: ${stats.useBtree}`);
if (stats.useBtree) {
  console.log(`B+tree Total Nodes: ${stats.btreeTotalNodes}`);
  console.log(`B+tree Max Height: ${stats.btreeMaxHeight}`);
  console.log(`B+tree Avg Height: ${stats.btreeAvgHeight}`);
}
```

**Characteristics**
- Point lookups · O(log N) tree traversal with binary search at each node
- Range scans · Doubly-linked leaf nodes enable efficient bidirectional iteration
- Immutable · Tree is bulk-loaded from sorted memtable data during flush
- Compression · Nodes compress independently using the same algorithms (LZ4, Zstd, etc.)

**When to use B+tree klog format**
- Read-heavy workloads with frequent point lookups
- Workloads where read latency is more important than write throughput
- Large SSTables where block scanning becomes expensive

**Important notes**
- `useBtree` **cannot be changed** after column family creation
- Different column families can use different formats

## Error Handling

```typescript
import { TidesDBError, ErrorCode } from 'tidesdb';

const cf = db.getColumnFamily('my_cf');

const txn = db.beginTransaction();

try {
  txn.put(cf, Buffer.from('key'), Buffer.from('value'), -1);
  txn.commit();
} catch (err) {
  if (err instanceof TidesDBError) {
    console.log(`Error code: ${err.code}`);
    console.log(`Error message: ${err.message}`);
    console.log(`Context: ${err.context}`);
    
    // Example error message:
    // "failed to put key-value pair: memory allocation failed"
  }
  
  txn.rollback();
} finally {
  txn.free();
}
```

**Error Codes**
- `ErrorCode.Success` (0) · Operation successful
- `ErrorCode.ErrMemory` (-1) · Memory allocation failed
- `ErrorCode.ErrInvalidArgs` (-2) · Invalid arguments
- `ErrorCode.ErrNotFound` (-3) · Key not found
- `ErrorCode.ErrIO` (-4) · I/O error
- `ErrorCode.ErrCorruption` (-5) · Data corruption
- `ErrorCode.ErrExists` (-6) · Resource already exists
- `ErrorCode.ErrConflict` (-7) · Transaction conflict
- `ErrorCode.ErrTooLarge` (-8) · Key or value too large
- `ErrorCode.ErrMemoryLimit` (-9) · Memory limit exceeded
- `ErrorCode.ErrInvalidDB` (-10) · Invalid database handle
- `ErrorCode.ErrUnknown` (-11) · Unknown error
- `ErrorCode.ErrLocked` (-12) · Database is locked

## Complete Example

```typescript
import { 
  TidesDB, 
  LogLevel, 
  CompressionAlgorithm, 
  SyncMode 
} from 'tidesdb';

function main() {
  const db = TidesDB.open({
    dbPath: './example_db',
    numFlushThreads: 1,
    numCompactionThreads: 1,
    logLevel: LogLevel.Info,
    blockCacheSize: 64 * 1024 * 1024,
    maxOpenSSTables: 256,
  });

  try {
    db.createColumnFamily('users', {
      writeBufferSize: 64 * 1024 * 1024,
      compressionAlgorithm: CompressionAlgorithm.Lz4Compression,
      enableBloomFilter: true,
      bloomFpr: 0.01,
      syncMode: SyncMode.Interval,
      syncIntervalUs: 128000,
    });

    const cf = db.getColumnFamily('users');

    const txn = db.beginTransaction();

    txn.put(cf, Buffer.from('user:1'), Buffer.from('Alice'), -1);
    txn.put(cf, Buffer.from('user:2'), Buffer.from('Bob'), -1);

    // Temporary session with 30 second TTL
    const ttl = Math.floor(Date.now() / 1000) + 30;
    txn.put(cf, Buffer.from('session:abc'), Buffer.from('temp_data'), ttl);

    txn.commit();
    txn.free();


    const readTxn = db.beginTransaction();

    const value = readTxn.get(cf, Buffer.from('user:1'));
    console.log(`user:1 = ${value.toString()}`);

    // Iterate over all entries
    const iter = readTxn.newIterator(cf);

    console.log('\nAll entries:');
    iter.seekToFirst();
    while (iter.isValid()) {
      const key = iter.key();
      const val = iter.value();
      console.log(`  ${key.toString()} = ${val.toString()}`);
      iter.next();
    }

    iter.free();
    readTxn.free();

    const stats = cf.getStats();

    console.log('\nColumn Family Statistics:');
    console.log(`  Number of Levels: ${stats.numLevels}`);
    console.log(`  Memtable Size: ${stats.memtableSize} bytes`);
    console.log(`  Total Keys: ${stats.totalKeys}`);
    console.log(`  Read Amplification: ${stats.readAmp}`);

    // Check background operation status
    console.log(`\nBackground Operations:`);
    console.log(`  Flushing: ${cf.isFlushing()}`);
    console.log(`  Compacting: ${cf.isCompacting()}`);

    // Create a backup
    db.backup('./example_db_backup');
    console.log('\nBackup created successfully');

    // Create a lightweight checkpoint (hard links, near-instant)
    db.checkpoint('./example_db_checkpoint');
    console.log('Checkpoint created successfully');

    // Cleanup
    db.dropColumnFamily('users');
  } finally {
    db.close();
  }
}

main();
```

## Isolation Levels

TidesDB supports five MVCC isolation levels:

```typescript
import { IsolationLevel } from 'tidesdb';

const txn = db.beginTransactionWithIsolation(IsolationLevel.ReadCommitted);

// ... perform operations

txn.commit();
txn.free();
```

**Available Isolation Levels**
- `IsolationLevel.ReadUncommitted` · Sees all data including uncommitted changes
- `IsolationLevel.ReadCommitted` · Sees only committed data (default)
- `IsolationLevel.RepeatableRead` · Consistent snapshot, phantom reads possible
- `IsolationLevel.Snapshot` · Write-write conflict detection
- `IsolationLevel.Serializable` · Full read-write conflict detection (SSI)

## Savepoints

Savepoints allow partial rollback within a transaction:

```typescript
const cf = db.getColumnFamily('my_cf');

const txn = db.beginTransaction();

txn.put(cf, Buffer.from('key1'), Buffer.from('value1'), -1);

txn.savepoint('sp1');
txn.put(cf, Buffer.from('key2'), Buffer.from('value2'), -1);

// Rollback to savepoint -- key2 is discarded, key1 remains
txn.rollbackToSavepoint('sp1');

// Commit -- only key1 is written
txn.commit();
txn.free();
```

## Transaction Reset

`txn.reset()` resets a committed or aborted transaction for reuse with a new isolation level. This avoids the overhead of freeing and reallocating transaction resources in hot loops.

```typescript
const cf = db.getColumnFamily('my_cf');

const txn = db.beginTransaction();

// First batch of work
txn.put(cf, Buffer.from('key1'), Buffer.from('value1'), -1);
txn.commit();

// Reset instead of free + beginTransaction
txn.reset(IsolationLevel.ReadCommitted);

// Second batch of work using the same transaction
txn.put(cf, Buffer.from('key2'), Buffer.from('value2'), -1);
txn.commit();

// Free once when done
txn.free();
```

**Behavior**
- The transaction must be committed or aborted before reset; resetting an active transaction throws an error
- Internal buffers are retained to avoid reallocation
- A fresh transaction ID and snapshot sequence are assigned based on the new isolation level
- The isolation level can be changed on each reset (e.g., `ReadCommitted` → `Serializable`)

**When to use**
- Batch processing · Reuse a single transaction across many commit cycles in a loop
- Connection pooling · Reset a transaction for a new request without reallocation
- High-throughput ingestion · Reduce allocation overhead in tight write loops

**Reset vs Free + Begin**

For a single transaction, `txn.reset()` is functionally equivalent to calling `txn.free()` followed by `db.beginTransactionWithIsolation()`. The difference is performance - reset retains allocated buffers and avoids repeated allocation overhead. This matters most in loops that commit and restart thousands of transactions.

## Cache Statistics

```typescript
const cacheStats = db.getCacheStats();

console.log(`Cache enabled: ${cacheStats.enabled}`);
console.log(`Total entries: ${cacheStats.totalEntries}`);
console.log(`Total bytes: ${(cacheStats.totalBytes / (1024 * 1024)).toFixed(2)} MB`);
console.log(`Hits: ${cacheStats.hits}`);
console.log(`Misses: ${cacheStats.misses}`);
console.log(`Hit rate: ${(cacheStats.hitRate * 100).toFixed(1)}%`);
console.log(`Partitions: ${cacheStats.numPartitions}`);
```

## Testing

```bash
npm install
npm run build

# Run all tests
npm test

# Run specific test
npm test -- --testNamePattern="put and get"
```

## TypeScript Types

The package exports all necessary types for full TypeScript support:

```typescript
import {
  // Main classes
  TidesDB,
  ColumnFamily,
  Transaction,
  Iterator,
  TidesDBError,
  
  // Configuration interfaces
  Config,
  ColumnFamilyConfig,
  Stats,
  CacheStats,
  
  // Enums
  CompressionAlgorithm,
  SyncMode,
  LogLevel,
  IsolationLevel,
  ErrorCode,
  
  // Helper functions
  defaultConfig,
  defaultColumnFamilyConfig,
  checkResult,
} from 'tidesdb';
```

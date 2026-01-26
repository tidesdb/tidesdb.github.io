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
npm install tidesdb
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
});

console.log('Database opened successfully');

// When done
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

// Create with default configuration
db.createColumnFamily('my_cf');

// Create with custom configuration
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
});

// Drop a column family
db.dropColumnFamily('my_cf');

// Rename a column family atomically
db.renameColumnFamily('old_name', 'new_name');
```

### CRUD Operations

All operations in TidesDB are performed through transactions for ACID guarantees.

#### Writing Data

```typescript
const cf = db.getColumnFamily('my_cf');

const txn = db.beginTransaction();

// Put a key-value pair (TTL -1 means no expiration)
txn.put(cf, Buffer.from('key'), Buffer.from('value'), -1);

txn.commit();
txn.free();
```

#### Writing with TTL

```typescript
const cf = db.getColumnFamily('my_cf');

const txn = db.beginTransaction();

// Set expiration time (Unix timestamp in seconds)
const ttl = Math.floor(Date.now() / 1000) + 10; // Expire in 10 seconds

txn.put(cf, Buffer.from('temp_key'), Buffer.from('temp_value'), ttl);

txn.commit();
txn.free();
```

**TTL Examples**
```typescript
// No expiration
const ttl = -1;

// Expire in 5 minutes
const ttl = Math.floor(Date.now() / 1000) + 5 * 60;

// Expire in 1 hour
const ttl = Math.floor(Date.now() / 1000) + 60 * 60;

// Expire at specific time
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
  // Multiple operations in one transaction, across column families as well
  txn.put(cf, Buffer.from('key1'), Buffer.from('value1'), -1);
  txn.put(cf, Buffer.from('key2'), Buffer.from('value2'), -1);
  txn.delete(cf, Buffer.from('old_key'));

  // Commit atomically -- all or nothing
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

// Seek to first key >= target
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

// Seek to last key <= target
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
  
  // Stop when keys no longer match prefix
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

// Per-level statistics
for (let i = 0; i < stats.numLevels; i++) {
  console.log(`Level ${i + 1}: ${stats.levelNumSSTables[i]} SSTables, ${stats.levelSizes[i]} bytes, ${stats.levelKeyCounts[i]} keys`);
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
// Backup to a directory (must be non-existent or empty)
db.backup('./mydb_backup');
```

**Behavior**
- Requires the backup directory to be non-existent or empty
- Does not copy the `LOCK` file, so the backup can be opened normally
- Database stays open and usable during backup
- The backup represents the database state after all pending flushes complete

### Compaction

#### Manual Compaction

```typescript
const cf = db.getColumnFamily('my_cf');

// Manually trigger compaction (queues compaction from L1+)
cf.compact();
```

#### Manual Memtable Flush

```typescript
const cf = db.getColumnFamily('my_cf');

// Manually trigger memtable flush (queues memtable for sorted run to disk (L1))
cf.flushMemtable();
```

#### Checking Flush/Compaction Status

Check if a column family has background operations in progress.

```typescript
const cf = db.getColumnFamily('my_cf');

// Check if flushing is in progress
if (cf.isFlushing()) {
  console.log('Flush in progress');
}

// Check if compaction is in progress
if (cf.isCompacting()) {
  console.log('Compaction in progress');
}
```

**Use cases**
- **Graceful shutdown** -- Wait for background operations to complete before closing
- **Maintenance windows** -- Check if operations are running before triggering manual compaction
- **Monitoring** -- Track background operation status for observability

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
- `writeBufferSize` -- Memtable flush threshold
- `skipListMaxLevel` -- Skip list level for new memtables
- `skipListProbability` -- Skip list probability for new memtables
- `bloomFpr` -- False positive rate for new SSTables
- `indexSampleRatio` -- Index sampling ratio for new SSTables
- `syncMode` -- Durability mode
- `syncIntervalUs` -- Sync interval in microseconds

**Non-updatable settings** (would corrupt existing data):
- `compressionAlgorithm`, `enableBlockIndexes`, `enableBloomFilter`, `comparatorName`, `levelSizeRatio`, `klogValueThreshold`, `minLevels`, `dividingLevelOffset`, `blockIndexPrefixLen`, `l1FileCountTrigger`, `l0QueueStallThreshold`

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
- `ErrorCode.Success` (0) -- Operation successful
- `ErrorCode.ErrMemory` (-1) -- Memory allocation failed
- `ErrorCode.ErrInvalidArgs` (-2) -- Invalid arguments
- `ErrorCode.ErrNotFound` (-3) -- Key not found
- `ErrorCode.ErrIO` (-4) -- I/O error
- `ErrorCode.ErrCorruption` (-5) -- Data corruption
- `ErrorCode.ErrExists` (-6) -- Resource already exists
- `ErrorCode.ErrConflict` (-7) -- Transaction conflict
- `ErrorCode.ErrTooLarge` (-8) -- Key or value too large
- `ErrorCode.ErrMemoryLimit` (-9) -- Memory limit exceeded
- `ErrorCode.ErrInvalidDB` (-10) -- Invalid database handle
- `ErrorCode.ErrUnknown` (-11) -- Unknown error
- `ErrorCode.ErrLocked` (-12) -- Database is locked

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

    // Write data
    const txn = db.beginTransaction();

    txn.put(cf, Buffer.from('user:1'), Buffer.from('Alice'), -1);
    txn.put(cf, Buffer.from('user:2'), Buffer.from('Bob'), -1);

    // Temporary session with 30 second TTL
    const ttl = Math.floor(Date.now() / 1000) + 30;
    txn.put(cf, Buffer.from('session:abc'), Buffer.from('temp_data'), ttl);

    txn.commit();
    txn.free();

    // Read data
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
- `IsolationLevel.ReadUncommitted` -- Sees all data including uncommitted changes
- `IsolationLevel.ReadCommitted` -- Sees only committed data (default)
- `IsolationLevel.RepeatableRead` -- Consistent snapshot, phantom reads possible
- `IsolationLevel.Snapshot` -- Write-write conflict detection
- `IsolationLevel.Serializable` -- Full read-write conflict detection (SSI)

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

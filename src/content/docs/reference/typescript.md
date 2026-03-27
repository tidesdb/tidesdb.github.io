---
title: TidesDB TypeScript API Reference
description: TypeScript API reference for TidesDB
---

<div class="no-print">

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/typescript.md).

<hr/>

</div>

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
export LD_LIBRARY_PATH="/opt/tidesdb/lib:$LD_LIBRARY_PATH"      # Linux
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
  maxMemoryUsage: 0,                  // Global memory limit in bytes (0 = auto, 50% of system RAM)
  logToFile: false,                   // Write logs to file instead of stderr
  logTruncationAt: 24 * 1024 * 1024,  // Log file truncation size (24MB), 0 = no truncation
  unifiedMemtable: false,             // Enable unified memtable mode
  unifiedMemtableWriteBufferSize: 0,  // Write buffer size (0 = auto)
  unifiedMemtableSkipListMaxLevel: 0, // Skip list max level (0 = default 12)
  unifiedMemtableSkipListProbability: 0, // Skip list probability (0 = default 0.25)
  unifiedMemtableSyncMode: SyncMode.None, // Sync mode for unified WAL
  unifiedMemtableSyncIntervalUs: 0,   // Sync interval for unified WAL (0 = default)
  // objectStoreFsPath: '/path/to/store',  // Enable object store mode (FS connector)
  // objectStoreConfig: { ... },           // Object store behavior config (optional)
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

// Delete by column family handle
const cfToDelete = db.getColumnFamily('my_cf');
db.deleteColumnFamily(cfToDelete);

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

#### Combined Key-Value Retrieval

Retrieve both the key and value in a single FFI call for better performance when you need both.

```typescript
const cf = db.getColumnFamily('my_cf');

const txn = db.beginTransaction();
const iter = txn.newIterator(cf);

iter.seekToFirst();

while (iter.isValid()) {
  const { key, value } = iter.keyValue();

  console.log(`Key: ${key.toString()}, Value: ${value.toString()}`);

  iter.next();
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
  writeBufferSize: 256 * 1024 * 1024,   
  skipListMaxLevel: 16,
  skipListProbability: 0.25,
  bloomFpr: 0.001,                      // 0.1% false positive rate
  indexSampleRatio: 8,                  // sample 1 in 8 keys
  syncMode: SyncMode.Interval,
  syncIntervalUs: 100000,               // 100ms
}, true);                               // persist to disk (config.ini)
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

### Range Cost Estimation

Estimate the computational cost of iterating between two keys in a column family. The returned value is an opaque double - meaningful only for comparison with other values from the same method. It uses only in-memory metadata and performs no disk I/O.

```typescript
const cf = db.getColumnFamily('my_cf');

const costA = cf.rangeCost(Buffer.from('user:0000'), Buffer.from('user:0999'));
const costB = cf.rangeCost(Buffer.from('user:1000'), Buffer.from('user:1099'));

if (costA < costB) {
  console.log('Range A is cheaper to iterate');
}
```

**Parameters**
- `keyA` · `Buffer` · First key (bound of range)
- `keyB` · `Buffer` · Second key (bound of range)

Returns · `number` · Estimated traversal cost (higher = more expensive)

**How it works**
- With block indexes enabled · Uses O(log B) binary search per overlapping SSTable to estimate block count
- Without block indexes · Falls back to byte-level key interpolation against SSTable min/max keys
- B+tree SSTables · Uses key interpolation against tree node counts, plus tree height as a seek cost
- Compressed SSTables receive a 1.5× weight multiplier to account for decompression overhead
- Each overlapping SSTable adds a small fixed cost for merge-heap operations
- The active memtable's entry count contributes a small in-memory cost

Key order does not matter - the method normalizes the range so `keyA > keyB` produces the same result as `keyB > keyA`.

**Use cases**
- Query planning · Compare candidate key ranges to find the cheapest one to scan
- Load balancing · Distribute range scan work across threads by estimating per-range cost
- Adaptive prefetching · Decide how aggressively to prefetch based on range size
- Monitoring · Track how data distribution changes across key ranges over time

:::note[Cost Values]
The returned cost is not an absolute measure (it does not represent milliseconds, bytes, or entry counts). It is a relative scalar - only meaningful when compared with other `rangeCost` results. A cost of 0 means no overlapping SSTables or memtable entries were found for the range.
:::

### Commit Hook (Change Data Capture)

`setCommitHook` registers an optional callback that fires synchronously after every transaction commit on a column family. The hook receives the full batch of committed operations atomically, enabling real-time change data capture without WAL parsing or external log consumers.

```typescript
import { CommitOp } from 'tidesdb';

const cf = db.getColumnFamily('my_cf');

// Attach a commit hook
cf.setCommitHook((ops: CommitOp[], commitSeq: number): number => {
  for (const op of ops) {
    if (op.isDelete) {
      console.log(`[${commitSeq}] DELETE key=${op.key.toString()}`);
    } else {
      console.log(`[${commitSeq}] PUT key=${op.key.toString()} value=${op.value!.toString()}`);
    }
  }
  return 0; // 0 = success
});

// Normal writes now trigger the hook automatically
const txn = db.beginTransaction();
txn.put(cf, Buffer.from('key1'), Buffer.from('value1'), -1);
txn.commit(); // hook fires here
txn.free();

// Detach the hook
cf.clearCommitHook();
```

**Parameters** (`setCommitHook`)
- `callback` · `CommitHookCallback` - Function invoked with `(ops, commitSeq)`. Return `0` on success; non-zero is logged as a warning but does not roll back the commit.

**CommitOp fields**
- `key` · `Buffer` - Key data
- `value` · `Buffer | null` - Value data (`null` for deletes)
- `ttl` · `number` - Time-to-live (Unix timestamp, `-1` = no expiry)
- `isDelete` · `boolean` - Whether this is a delete operation

**Behavior**
- The hook fires after WAL write, memtable apply, and commit status marking are complete - the data is fully durable before the callback runs
- Hook failure (non-zero return) is logged but does not affect the commit result
- Each column family has its own independent hook; a multi-CF transaction fires the hook once per CF with only that CF's operations
- `commitSeq` is monotonically increasing across commits and can be used as a replication cursor
- Data in `CommitOp` is copied and safe to retain beyond the callback
- The hook executes synchronously on the committing thread; keep the callback fast to avoid stalling writers
- Calling `clearCommitHook()` disables it immediately with no restart required

**Use cases**
- Replication · Ship committed batches to replicas in commit order
- Event streaming · Publish mutations to Kafka, NATS, or any message broker
- Secondary indexing · Maintain a reverse index or materialized view
- Audit logging · Record every mutation with key, value, TTL, and sequence number
- Debugging · Attach a temporary hook in production to inspect live writes

:::note[Runtime-Only]
Commit hooks are not persisted. After a database restart, hooks must be re-registered by the application. This is by design - function pointers cannot be serialized.
:::

### Manual WAL Sync

Force an immediate fsync of the active write-ahead log for a column family. This is useful for explicit durability control when using `SyncMode.None` or `SyncMode.Interval` modes.

```typescript
const cf = db.getColumnFamily('my_cf');

cf.syncWal();
```

**When to use**
- Application-controlled durability · Sync the WAL at specific points (e.g., after a batch of related writes) when using `SyncMode.None` or `SyncMode.Interval`
- Pre-checkpoint · Ensure all buffered WAL data is on disk before taking a checkpoint
- Graceful shutdown · Flush WAL buffers before closing the database
- Critical writes · Force durability for specific high-value writes without using `SyncMode.Full` for all writes

**Behavior**
- Acquires a reference to the active memtable to safely access its WAL
- Calls `fdatasync` on the WAL file descriptor
- Thread-safe - can be called concurrently from multiple threads
- If the memtable rotates during the call, retries with the new active memtable

**Return values**
- Throws `TidesDBError` with `ErrorCode.ErrInvalidArgs` if column family is invalid
- Throws `TidesDBError` with `ErrorCode.ErrIO` if the fsync operation fails

:::tip[Structural Operations]
Regardless of sync mode, TidesDB **always** enforces durability for structural operations:
- Memtable flush to SSTable
- SSTable compaction and merging
- WAL rotation
- Column family metadata updates
:::

### Database-Level Statistics

Get aggregate statistics across the entire database instance.

```typescript
const dbStats = db.getDbStats();

console.log(`Column families: ${dbStats.numColumnFamilies}`);
console.log(`Total memory: ${dbStats.totalMemory} bytes`);
console.log(`Resolved memory limit: ${dbStats.resolvedMemoryLimit} bytes`);
console.log(`Memory pressure level: ${dbStats.memoryPressureLevel}`);
console.log(`Global sequence: ${dbStats.globalSeq}`);
console.log(`Flush queue: ${dbStats.flushQueueSize} pending`);
console.log(`Compaction queue: ${dbStats.compactionQueueSize} pending`);
console.log(`Total SSTables: ${dbStats.totalSstableCount}`);
console.log(`Total data size: ${dbStats.totalDataSizeBytes} bytes`);
console.log(`Open SSTable handles: ${dbStats.numOpenSstables}`);
console.log(`In-flight txn memory: ${dbStats.txnMemoryBytes} bytes`);
console.log(`Immutable memtables: ${dbStats.totalImmutableCount}`);
console.log(`Memtable bytes: ${dbStats.totalMemtableBytes}`);
```

**Database statistics include**

| Field | Type | Description |
|-------|------|-------------|
| `numColumnFamilies` | `number` | Number of column families |
| `totalMemory` | `number` | System total memory |
| `availableMemory` | `number` | System available memory at open time |
| `resolvedMemoryLimit` | `number` | Resolved memory limit (auto or configured) |
| `memoryPressureLevel` | `number` | Current memory pressure (0=normal, 1=elevated, 2=high, 3=critical) |
| `flushPendingCount` | `number` | Number of pending flush operations (queued + in-flight) |
| `totalMemtableBytes` | `number` | Total bytes in active memtables across all CFs |
| `totalImmutableCount` | `number` | Total immutable memtables across all CFs |
| `totalSstableCount` | `number` | Total SSTables across all CFs and levels |
| `totalDataSizeBytes` | `number` | Total data size (klog + vlog) across all CFs |
| `numOpenSstables` | `number` | Number of currently open SSTable file handles |
| `globalSeq` | `number` | Current global sequence number |
| `txnMemoryBytes` | `number` | Bytes held by in-flight transactions |
| `compactionQueueSize` | `number` | Number of pending compaction tasks |
| `flushQueueSize` | `number` | Number of pending flush tasks in queue |
| `unifiedMemtableEnabled` | `boolean` | Whether unified memtable mode is active |
| `unifiedMemtableBytes` | `number` | Bytes in unified active memtable |
| `unifiedImmutableCount` | `number` | Number of unified immutable memtables |
| `unifiedIsFlushing` | `boolean` | Whether unified memtable is currently flushing/rotating |
| `unifiedNextCfIndex` | `number` | Next CF index to be assigned in unified mode |
| `unifiedWalGeneration` | `number` | Current unified WAL generation counter |
| `objectStoreEnabled` | `boolean` | Whether object store mode is active |
| `objectStoreConnector` | `string` | Object store connector name ("s3", "gcs", "fs", etc.) |
| `localCacheBytesUsed` | `number` | Current local file cache usage in bytes |
| `localCacheBytesMax` | `number` | Configured maximum local cache size in bytes |
| `localCacheNumFiles` | `number` | Number of files tracked in local cache |
| `lastUploadedGeneration` | `number` | Highest WAL generation confirmed uploaded |
| `uploadQueueDepth` | `number` | Number of pending upload jobs in the queue |
| `totalUploads` | `number` | Lifetime count of objects uploaded to object store |
| `totalUploadFailures` | `number` | Lifetime count of permanently failed uploads |
| `replicaMode` | `boolean` | Whether running in read-only replica mode |

:::note[Stack Allocated]
Unlike `cf.getStats()` (which heap-allocates), `db.getDbStats()` fills a caller-provided struct. No free is needed.
:::

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

db.createColumnFamily('snappy_cf', {
  compressionAlgorithm: CompressionAlgorithm.SnappyCompression,
});
```

:::note[Snappy Availability]
Snappy compression is not available on SunOS/Illumos/OmniOS platforms.
:::

### B+tree KLog Format (Optional)

Column families can optionally use a B+tree structure for the key log instead of the default block-based format. The B+tree klog format offers faster point lookups through O(log N) tree traversal.

```typescript
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

:::caution[Important]
`useBtree` **cannot be changed** after column family creation. Different column families can use different formats.
:::

### Unified Memtable Mode

In unified memtable mode, all column families share a single memtable and WAL, reducing write amplification and flush overhead for multi-CF workloads.

```typescript
import { TidesDB, SyncMode } from 'tidesdb';

const db = TidesDB.open({
  dbPath: './mydb',
  numFlushThreads: 2,
  numCompactionThreads: 2,
  unifiedMemtable: true,
  unifiedMemtableWriteBufferSize: 128 * 1024 * 1024,
  unifiedMemtableSkipListMaxLevel: 12,
  unifiedMemtableSkipListProbability: 0.25,
  unifiedMemtableSyncMode: SyncMode.Interval,
  unifiedMemtableSyncIntervalUs: 128000,
});

// Check unified memtable status via database stats
const stats = db.getDbStats();
console.log(`Unified memtable enabled: ${stats.unifiedMemtableEnabled}`);
console.log(`Unified memtable bytes: ${stats.unifiedMemtableBytes}`);
console.log(`Unified immutable count: ${stats.unifiedImmutableCount}`);
console.log(`Unified is flushing: ${stats.unifiedIsFlushing}`);
console.log(`Unified WAL generation: ${stats.unifiedWalGeneration}`);

db.close();
```

**Configuration**
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `unifiedMemtable` | `boolean` | `false` | Enable unified memtable mode |
| `unifiedMemtableWriteBufferSize` | `number` | `0` (auto) | Write buffer size for unified memtable |
| `unifiedMemtableSkipListMaxLevel` | `number` | `0` (default 12) | Skip list max level |
| `unifiedMemtableSkipListProbability` | `number` | `0` (default 0.25) | Skip list probability |
| `unifiedMemtableSyncMode` | `SyncMode` | `SyncMode.None` | Sync mode for unified WAL |
| `unifiedMemtableSyncIntervalUs` | `number` | `0` (default) | Sync interval in microseconds |

### Object Store Mode

Object store mode allows TidesDB to store SSTables in a remote object store (or local filesystem for testing) while using local disk as a cache. This separates compute from storage and enables cold start recovery. Object store mode requires unified memtable mode and is automatically enforced when a connector is set.

#### Enabling Object Store Mode (Filesystem Connector)

```typescript
import { TidesDB, LogLevel } from 'tidesdb';

const db = TidesDB.open({
  dbPath: './mydb',
  objectStoreFsPath: '/mnt/nfs/tidesdb-objects',
});

// Use the database normally -- SSTables are uploaded after flush

db.close();
```

#### Object Store with Custom Configuration

```typescript
import { TidesDB } from 'tidesdb';

const db = TidesDB.open({
  dbPath: './mydb',
  objectStoreFsPath: '/mnt/nfs/tidesdb-objects',
  objectStoreConfig: {
    localCacheMaxBytes: 512 * 1024 * 1024,  // 512MB local cache
    maxConcurrentUploads: 8,
    maxConcurrentDownloads: 16,
    cacheOnRead: true,
    cacheOnWrite: true,
    syncManifestToObject: true,
    replicateWal: true,
    walSyncThresholdBytes: 1048576,  // 1MB
  },
});

db.close();
```

#### Object Store Configuration Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `localCachePath` | `string \| null` | `null` (uses dbPath) | Local directory for cached SSTable files |
| `localCacheMaxBytes` | `number` | `0` (unlimited) | Maximum local cache size in bytes |
| `cacheOnRead` | `boolean` | `true` | Cache downloaded files locally |
| `cacheOnWrite` | `boolean` | `true` | Keep local copy after upload |
| `maxConcurrentUploads` | `number` | `4` | Number of parallel upload threads |
| `maxConcurrentDownloads` | `number` | `8` | Number of parallel download threads |
| `multipartThreshold` | `number` | `67108864` (64MB) | Use multipart upload above this size |
| `multipartPartSize` | `number` | `8388608` (8MB) | Chunk size for multipart uploads |
| `syncManifestToObject` | `boolean` | `true` | Upload MANIFEST after each compaction |
| `replicateWal` | `boolean` | `true` | Upload closed WAL segments for replication |
| `walUploadSync` | `boolean` | `false` | Block flush until WAL is uploaded |
| `walSyncThresholdBytes` | `number` | `1048576` (1MB) | Sync active WAL to object store when it grows by this many bytes (0 = off) |
| `walSyncOnCommit` | `boolean` | `false` | Upload WAL after every txn commit for RPO=0 replication |
| `replicaMode` | `boolean` | `false` | Enable read-only replica mode (writes return `ErrorCode.ErrReadonly`) |
| `replicaSyncIntervalUs` | `number` | `5000000` (5s) | MANIFEST poll interval for replica sync in microseconds |
| `replicaReplayWal` | `boolean` | `true` | Replay WAL from object store for near-real-time reads on replicas |

#### Per-CF Object Store Tuning

Column family configurations include three object store tuning fields.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `objectTargetFileSize` | `number` | `0` (auto) | Target SSTable size in object store mode |
| `objectLazyCompaction` | `boolean` | `false` | Compact less aggressively for remote storage |
| `objectPrefetchCompaction` | `boolean` | `true` | Download all inputs before compaction merge |

```typescript
db.createColumnFamily('remote_cf', {
  objectTargetFileSize: 256 * 1024 * 1024,  // 256MB
  objectLazyCompaction: true,
  objectPrefetchCompaction: true,
});
```

#### Cold Start Recovery

When the local database directory is empty but a connector is configured, TidesDB automatically discovers column families from the object store, downloads MANIFEST and config files in parallel, and fetches SSTable data on demand.

```typescript
// Reopen with the same connector -- cold start recovery
const db = TidesDB.open({
  dbPath: './mydb',
  objectStoreFsPath: '/mnt/nfs/tidesdb-objects',
});

// All data is available -- SSTables are fetched on demand
const cf = db.getColumnFamily('my_cf');
```

#### Replica Mode

Replica mode enables read-only nodes that follow a primary through the object store.

```typescript
// Open as a replica
const replica = TidesDB.open({
  dbPath: './mydb_replica',
  objectStoreFsPath: '/mnt/nfs/tidesdb-objects',  // Same store as primary
  objectStoreConfig: {
    replicaMode: true,
    replicaSyncIntervalUs: 1000000,  // 1 second sync interval
    replicaReplayWal: true,
  },
});

// Reads work normally
const cf = replica.getColumnFamily('my_cf');
const txn = replica.beginTransaction();
const value = txn.get(cf, Buffer.from('key'));
txn.free();

// Writes are rejected with ErrorCode.ErrReadonly
```

#### Sync-on-Commit WAL (Primary Side)

For tighter replication lag, enable sync-on-commit on the primary so every committed write is uploaded immediately.

```typescript
const primary = TidesDB.open({
  dbPath: './mydb',
  objectStoreFsPath: '/mnt/nfs/tidesdb-objects',
  objectStoreConfig: {
    walSyncOnCommit: true,  // RPO = 0, every commit is durable
  },
});
```

#### Object Store Statistics

Object store fields are included in database-level statistics when a connector is active.

```typescript
const stats = db.getDbStats();

if (stats.objectStoreEnabled) {
  console.log(`Connector: ${stats.objectStoreConnector}`);
  console.log(`Total uploads: ${stats.totalUploads}`);
  console.log(`Upload failures: ${stats.totalUploadFailures}`);
  console.log(`Upload queue depth: ${stats.uploadQueueDepth}`);
  console.log(`Local cache: ${stats.localCacheBytesUsed} / ${stats.localCacheBytesMax} bytes`);
  console.log(`Replica mode: ${stats.replicaMode}`);
}
```

:::note[S3/MinIO Connector]
The filesystem connector is always available. For S3/MinIO support, TidesDB must be built with `-DTIDESDB_WITH_S3=ON`. The S3 connector is not exposed through the TypeScript binding -- use the C API directly for S3 configuration.
:::

### Promote Replica to Primary

Switch a read-only replica database to primary mode.

```typescript
db.promoteToPrimary();
```

**Behavior**
- Only valid when the database was opened in replica mode
- Throws `TidesDBError` with `ErrorCode.ErrInvalidArgs` if the database is not a replica

### Delete Column Family by Handle

Delete a column family using its handle instead of its name.

```typescript
const cf = db.getColumnFamily('my_cf');
db.deleteColumnFamily(cf);
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
- `ErrorCode.ErrReadonly` (-13) · Database is read-only

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

Savepoints allow partial rollback within a transaction. You can create named savepoints and rollback to them without aborting the entire transaction.

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

**Savepoint API**
- `txn.savepoint('name')` · Create a savepoint
- `txn.rollbackToSavepoint('name')` · Rollback to savepoint
- `txn.releaseSavepoint('name')` · Release savepoint without rolling back

**Savepoint behavior**
- Savepoints capture the transaction state at a specific point
- Rolling back to a savepoint discards all operations after that savepoint
- Releasing a savepoint frees its resources without rolling back
- Multiple savepoints can be created with different names
- Creating a savepoint with an existing name updates that savepoint
- Savepoints are automatically freed when the transaction commits or rolls back

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

## Multi-Column-Family Transactions

TidesDB supports atomic transactions across multiple column families with true all-or-nothing semantics.

```typescript
const usersCf = db.getColumnFamily('users');
const ordersCf = db.getColumnFamily('orders');

const txn = db.beginTransaction();

txn.put(usersCf, Buffer.from('user:1000'), Buffer.from('John Doe'), -1);
txn.put(ordersCf, Buffer.from('order:5000'), Buffer.from('user:1000|product:A'), -1);

txn.commit();
txn.free();
```

**Multi-CF guarantees**
- Either all CFs commit or none do (atomic)
- Automatically detected when operations span multiple CFs
- Uses global sequence numbers for atomic ordering
- Each CF's WAL receives operations with the same commit sequence number
- No two-phase commit or coordinator overhead

## Custom Comparators

TidesDB uses comparators to determine the sort order of keys throughout the entire system, memtables, SSTables, block indexes, and iterators all use the same comparison logic. Once a comparator is set for a column family, it **cannot be changed** without corrupting data.

### Built-in Comparators

TidesDB provides six built-in comparators that are automatically registered on database open:

- **`"memcmp"` (default)** · Binary byte-by-byte comparison. Shorter key sorts first if bytes are equal.
- **`"lexicographic"`** · Null-terminated string comparison using `strcmp()`. Keys must be null-terminated.
- **`"uint64"`** · Unsigned 64-bit integer comparison. Interprets 8-byte keys as uint64 values. Falls back to memcmp if key size != 8.
- **`"int64"`** · Signed 64-bit integer comparison. Interprets 8-byte keys as int64 values. Falls back to memcmp if key size != 8.
- **`"reverse"`** · Reverse binary comparison. Sorts keys in descending order.
- **`"case_insensitive"`** · Case-insensitive ASCII comparison. Converts A-Z to a-z during comparison.

### Registering a Comparator

```typescript
// Register comparator after opening database but before creating CF
db.registerComparator('reverse');

db.createColumnFamily('sorted_cf', {
  comparatorName: 'reverse',
});
```

### Retrieving a Registered Comparator

Use `getComparator` to check whether a comparator is registered:

```typescript
if (db.getComparator('reverse')) {
  console.log('Comparator "reverse" is registered');
} else {
  console.log('Comparator not registered');
}
```

**Use cases**
- Validation · Check if a comparator is registered before creating a column family
- Debugging · Verify comparator registration during development
- Dynamic configuration · Query available comparators at runtime

:::caution[Important]
Comparators must be **registered before** creating column families that use them. Once set, a comparator **cannot be changed** for a column family. The same comparator is used across memtables, SSTables, block indexes, and iterators.
:::

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
  DbStats,
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

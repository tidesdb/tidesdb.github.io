---
title: TidesDB Python API Reference
description: Complete Python API reference for TidesDB
---

<div class="no-print">

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/python.md).

<hr/>

</div>

## Getting Started

### Prerequisites

You **must** have the TidesDB shared C library installed on your system.  You can find the installation instructions [here](/reference/building/#_top).

## Installation

Or install from source:

```bash
git clone https://github.com/tidesdb/tidesdb-python.git
cd tidesdb-python
pip install -e .
```

## Quick Start

```python
import tidesdb

db = tidesdb.TidesDB.open("./mydb")

config = tidesdb.default_column_family_config()
config.compression_algorithm = tidesdb.CompressionAlgorithm.LZ4_COMPRESSION
db.create_column_family("users", config)

cf = db.get_column_family("users")

with db.begin_txn() as txn:
    txn.put(cf, b"user:1", b"Alice")
    txn.put(cf, b"user:2", b"Bob")
    txn.commit()

with db.begin_txn() as txn:
    value = txn.get(cf, b"user:1")
    print(f"user:1 = {value.decode()}")

with db.begin_txn() as txn:
    with txn.new_iterator(cf) as it:
        it.seek_to_first()
        for key, value in it:
            print(f"{key.decode()} = {value.decode()}")

db.drop_column_family("users")
db.close()
```

## Usage

### Opening a Database

```python
import tidesdb

db = tidesdb.TidesDB.open("./mydb")

# With configuration
config = tidesdb.Config(
    db_path="./mydb",
    num_flush_threads=2,
    num_compaction_threads=2,
    log_level=tidesdb.LogLevel.LOG_INFO,
    block_cache_size=64 * 1024 * 1024,   # 64MB
    max_open_sstables=256,
    max_memory_usage=0,                  # Global memory limit in bytes (0 = auto, 50% of system RAM)
    log_to_file=False,                   # Write logs to file instead of stderr
    log_truncation_at=24 * 1024 * 1024,  # Log file truncation size (24MB)
    unified_memtable=False,              # Enable unified memtable mode
    unified_memtable_write_buffer_size=0,            # Unified memtable buffer size (0 = default)
    unified_memtable_skip_list_max_level=0,          # Unified memtable skip list max level
    unified_memtable_skip_list_probability=0.0,      # Unified memtable skip list probability
    unified_memtable_sync_mode=tidesdb.SyncMode.SYNC_NONE,  # Unified memtable WAL sync mode
    unified_memtable_sync_interval_us=0,             # Unified memtable sync interval in microseconds
    object_store=None,                               # Object store connector (from objstore_fs_create())
    object_store_config=None,                        # Object store behavior config (ObjStoreConfig)
)
db = tidesdb.TidesDB(config)

# Using context manager
with tidesdb.TidesDB.open("./mydb") as db:
    # ... use database
    pass  # automatically closed
```

### Column Families

```python
db.create_column_family("my_cf")

# Create with custom config
config = tidesdb.default_column_family_config()
config.write_buffer_size = 128 * 1024 * 1024  # 128MB
config.compression_algorithm = tidesdb.CompressionAlgorithm.ZSTD_COMPRESSION
config.enable_bloom_filter = True
config.bloom_fpr = 0.01
config.sync_mode = tidesdb.SyncMode.SYNC_INTERVAL
config.sync_interval_us = 128000  # 128ms
config.klog_value_threshold = 512  # Values > 512 bytes go to vlog
config.min_disk_space = 100 * 1024 * 1024  # 100MB minimum disk space
config.default_isolation_level = tidesdb.IsolationLevel.READ_COMMITTED
config.l1_file_count_trigger = 4  # L1 compaction trigger
config.l0_queue_stall_threshold = 20  # L0 backpressure threshold
db.create_column_family("my_cf", config)

cf = db.get_column_family("my_cf")

names = db.list_column_families()
print(names)

stats = cf.get_stats()
print(f"Levels: {stats.num_levels}, Memtable: {stats.memtable_size} bytes")
print(f"Total keys: {stats.total_keys}, Total data size: {stats.total_data_size} bytes")
print(f"Avg key size: {stats.avg_key_size:.2f}, Avg value size: {stats.avg_value_size:.2f}")
print(f"Read amplification: {stats.read_amp:.2f}, Hit rate: {stats.hit_rate:.2%}")
print(f"Keys per level: {stats.level_key_counts}")

# B+tree klog stats (only populated if use_btree=True)
if stats.use_btree:
    print(f"B+tree total nodes: {stats.btree_total_nodes}")
    print(f"B+tree max height: {stats.btree_max_height}")
    print(f"B+tree avg height: {stats.btree_avg_height:.2f}")

db.rename_column_family("my_cf", "new_cf")

db.drop_column_family("new_cf")

# Delete by pointer (skips name lookup, faster when you already have the handle)
cf = db.get_column_family("my_cf")
db.delete_column_family(cf)
```

### Cloning a Column Family

Create a complete copy of an existing column family with a new name. The clone contains all the data from the source at the time of cloning and is completely independent.

```python
# Clone an existing column family
db.clone_column_family("source_cf", "cloned_cf")

# Both column families now exist independently
source = db.get_column_family("source_cf")
clone = db.get_column_family("cloned_cf")

# Modifications to one do not affect the other
with db.begin_txn() as txn:
    txn.put(source, b"key", b"new_value")
    txn.commit()

with db.begin_txn() as txn:
    # clone still has the original value
    value = txn.get(clone, b"key")
```

**Use cases**
- Testing · Create a copy of production data for testing without affecting the original
- Branching · Create a snapshot of data before making experimental changes
- Migration · Clone data before schema or configuration changes
- Backup verification · Clone and verify data integrity without modifying the source

:::note[Clone vs Backup]
`clone_column_family` creates a new column family within the same database instance. For creating an external backup of the entire database, use `backup()` instead.
:::

### Transactions

```python
txn = db.begin_txn()

try:
    # Put key-value pairs (TTL -1 means no expiration)
    txn.put(cf, b"key1", b"value1", ttl=-1)
    txn.put(cf, b"key2", b"value2", ttl=-1)
    
    value = txn.get(cf, b"key1")
    
    txn.delete(cf, b"key2")
    
    txn.commit()
except tidesdb.TidesDBError as e:
    txn.rollback()
    raise
finally:
    txn.close()

# Using context manager (auto-rollback on exception, auto-close)
with db.begin_txn() as txn:
    txn.put(cf, b"key", b"value")
    txn.commit()
```

### Transaction Reset

`reset()` resets a committed or aborted transaction for reuse with a new isolation level. This avoids the overhead of freeing and reallocating transaction resources in hot loops.

```python
txn = db.begin_txn()

# First batch of work
txn.put(cf, b"key1", b"value1")
txn.commit()

# Reset instead of close + begin_txn
txn.reset(tidesdb.IsolationLevel.READ_COMMITTED)

# Second batch of work using the same transaction
txn.put(cf, b"key2", b"value2")
txn.commit()

# Free once when done
txn.close()
```

**Batch processing example**
```python
txn = db.begin_txn()

for batch in batches:
    for key, value in batch:
        txn.put(cf, key, value)
    txn.commit()
    txn.reset(tidesdb.IsolationLevel.READ_COMMITTED)

txn.close()
```

**Behavior**
- The transaction must be committed or rolled back before reset; resetting an active transaction raises `TidesDBError`
- Internal buffers are retained to avoid reallocation
- A fresh transaction ID and snapshot sequence are assigned
- The isolation level can be changed on each reset

**When to use**
- Batch processing · Reuse a single transaction across many commit cycles in a loop
- Connection pooling · Reset a transaction for a new request without reallocation
- High-throughput ingestion · Reduce allocation overhead in tight write loops

:::tip[Reset vs Close + Begin]
`txn.reset()` is functionally equivalent to `txn.close()` followed by `db.begin_txn()`. The difference is performance, reset retains allocated buffers and avoids repeated allocation overhead.
:::

### TTL (Time-To-Live)

```python
import time

# Set TTL as Unix timestamp (seconds since epoch)
ttl = int(time.time()) + 60  # Expires in 60 seconds

with db.begin_txn() as txn:
    txn.put(cf, b"temp_key", b"temp_value", ttl=ttl)
    txn.commit()
```

### Isolation Levels

```python
txn = db.begin_txn_with_isolation(tidesdb.IsolationLevel.SERIALIZABLE)

# Available levels
# -- READ_UNCOMMITTED        -- Sees all data including uncommitted changes
# -- READ_COMMITTED          -- Sees only committed data (default)
# -- REPEATABLE_READ         -- Consistent snapshot, phantom reads possible
# -- SNAPSHOT                -- Write-write conflict detection
# -- SERIALIZABLE            -- Full read-write conflict detection (SSI)
```

### Savepoints

```python
with db.begin_txn() as txn:
    txn.put(cf, b"key1", b"value1")
    
    txn.savepoint("sp1")
    
    txn.put(cf, b"key2", b"value2")
    
    # Rollback to savepoint (key2 discarded, key1 remains)
    txn.rollback_to_savepoint("sp1")
    
    # Or release savepoint without rollback
    # txn.release_savepoint("sp1")
    
    txn.commit()  # Only key1 is written
```

### Iterators

```python
with db.begin_txn() as txn:
    with txn.new_iterator(cf) as it:
        # Forward iteration
        it.seek_to_first()
        while it.valid():
            key = it.key()
            value = it.value()
            print(f"{key} = {value}")
            it.next()
        
        # Backward iteration
        it.seek_to_last()
        while it.valid():
            print(f"{it.key()} = {it.value()}")
            it.prev()
        
        # Seek to specific key
        it.seek(b"user:")  # First key >= "user:"
        it.seek_for_prev(b"user:z")  # Last key <= "user:z"

        # Combined key+value retrieval (more efficient than separate key()/value())
        it.seek_to_first()
        while it.valid():
            key, value = it.key_value()
            print(f"{key} = {value}")
            it.next()

        # Python iteration protocol (uses key_value() internally)
        it.seek_to_first()
        for key, value in it:
            print(f"{key} = {value}")
```

### Maintenance Operations

```python
# Manual compaction (queues compaction)
cf.compact()

# Manual memtable flush (sorted run to L1)
cf.flush_memtable()

# Check if flush/compaction is in progress
if cf.is_flushing():
    print("Flush in progress")
if cf.is_compacting():
    print("Compaction in progress")

# Get cache statistics
cache_stats = db.get_cache_stats()
print(f"Cache hits: {cache_stats.hits}, misses: {cache_stats.misses}")
print(f"Hit rate: {cache_stats.hit_rate:.2%}")
```

### Manual WAL Sync

`sync_wal()` forces an immediate fsync of the active write-ahead log for a column family. This is useful for explicit durability control when using `SYNC_NONE` or `SYNC_INTERVAL` modes.

```python
cf = db.get_column_family("my_cf")

# Force WAL durability after a batch of writes
cf.sync_wal()
```

**When to use**
- Application-controlled durability · Sync the WAL at specific points (e.g., after a batch of related writes) when using `SYNC_NONE` or `SYNC_INTERVAL`
- Pre-checkpoint · Ensure all buffered WAL data is on disk before taking a checkpoint
- Graceful shutdown · Flush WAL buffers before closing the database
- Critical writes · Force durability for specific high-value writes without using `SYNC_FULL` for all writes

:::tip[Structural Operations]
Regardless of sync mode, TidesDB **always** enforces durability for structural operations, memtable flush, SSTable compaction, WAL rotation, and column family metadata updates.
:::

### Purge Column Family

`purge()` forces a synchronous flush and aggressive compaction for a single column family. Unlike `flush_memtable()` and `compact()` (which are non-blocking), purge blocks until all flush and compaction I/O is complete.

```python
cf = db.get_column_family("my_cf")

cf.purge()
# All data is now flushed to SSTables and compacted
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

### Purge Database

`purge()` on the database forces a synchronous flush and aggressive compaction for **all** column families, then drains both the global flush and compaction queues.

```python
db.purge()
# All CFs flushed and compacted, all queues drained
```

**Behavior**
1. Calls purge on each column family
2. Drains the global flush queue (waits for queue size and pending count to reach 0)
3. Drains the global compaction queue (waits for queue size to reach 0)

:::tip[Purge vs Manual Flush + Compact]
`flush_memtable()` and `compact()` are non-blocking - they enqueue work and return immediately. `cf.purge()` and `db.purge()` are synchronous - they block until all work is complete. Use purge when you need a guarantee that all data is on disk and compacted before proceeding.
:::

### Database-Level Statistics

Get aggregate statistics across the entire database instance.

```python
db_stats = db.get_db_stats()
print(f"Column families: {db_stats.num_column_families}")
print(f"Total memory: {db_stats.total_memory} bytes")
print(f"Resolved memory limit: {db_stats.resolved_memory_limit} bytes")
print(f"Memory pressure level: {db_stats.memory_pressure_level}")
print(f"Global sequence: {db_stats.global_seq}")
print(f"Flush queue: {db_stats.flush_queue_size} pending")
print(f"Compaction queue: {db_stats.compaction_queue_size} pending")
print(f"Total SSTables: {db_stats.total_sstable_count}")
print(f"Total data size: {db_stats.total_data_size_bytes} bytes")
print(f"Open SSTable handles: {db_stats.num_open_sstables}")
print(f"In-flight txn memory: {db_stats.txn_memory_bytes} bytes")
print(f"Immutable memtables: {db_stats.total_immutable_count}")
print(f"Memtable bytes: {db_stats.total_memtable_bytes}")

# Unified memtable stats (when enabled)
if db_stats.unified_memtable_enabled:
    print(f"Unified memtable bytes: {db_stats.unified_memtable_bytes}")
    print(f"Unified immutable count: {db_stats.unified_immutable_count}")
    print(f"Unified is flushing: {db_stats.unified_is_flushing}")
    print(f"Unified WAL generation: {db_stats.unified_wal_generation}")

# Object store stats (when enabled)
if db_stats.object_store_enabled:
    print(f"Object store connector: {db_stats.object_store_connector}")
    print(f"Local cache: {db_stats.local_cache_bytes_used}/{db_stats.local_cache_bytes_max} bytes")
    print(f"Total uploads: {db_stats.total_uploads}")
    print(f"Replica mode: {db_stats.replica_mode}")
```

**Database statistics include**

| Field | Type | Description |
|-------|------|-------------|
| `num_column_families` | `int` | Number of column families |
| `total_memory` | `int` | System total memory |
| `available_memory` | `int` | System available memory at open time |
| `resolved_memory_limit` | `int` | Resolved memory limit (auto or configured) |
| `memory_pressure_level` | `int` | Current memory pressure (0=normal, 1=elevated, 2=high, 3=critical) |
| `flush_pending_count` | `int` | Number of pending flush operations (queued + in-flight) |
| `total_memtable_bytes` | `int` | Total bytes in active memtables across all CFs |
| `total_immutable_count` | `int` | Total immutable memtables across all CFs |
| `total_sstable_count` | `int` | Total SSTables across all CFs and levels |
| `total_data_size_bytes` | `int` | Total data size (klog + vlog) across all CFs |
| `num_open_sstables` | `int` | Number of currently open SSTable file handles |
| `global_seq` | `int` | Current global sequence number |
| `txn_memory_bytes` | `int` | Bytes held by in-flight transactions |
| `compaction_queue_size` | `int` | Number of pending compaction tasks |
| `flush_queue_size` | `int` | Number of pending flush tasks in queue |
| `unified_memtable_enabled` | `bool` | Whether unified memtable mode is active |
| `unified_memtable_bytes` | `int` | Bytes in the unified memtable |
| `unified_immutable_count` | `int` | Number of unified immutable memtables |
| `unified_is_flushing` | `bool` | Whether the unified memtable is flushing |
| `unified_next_cf_index` | `int` | Next column family index for unified memtable |
| `unified_wal_generation` | `int` | Current unified WAL generation number |
| `object_store_enabled` | `bool` | Whether object store mode is active |
| `object_store_connector` | `str` | Object store connector identifier |
| `local_cache_bytes_used` | `int` | Bytes used in local cache |
| `local_cache_bytes_max` | `int` | Maximum local cache size in bytes |
| `local_cache_num_files` | `int` | Number of files in local cache |
| `last_uploaded_generation` | `int` | Last uploaded WAL generation |
| `upload_queue_depth` | `int` | Pending uploads in queue |
| `total_uploads` | `int` | Total successful uploads |
| `total_upload_failures` | `int` | Total failed uploads |
| `replica_mode` | `bool` | Whether the database is in replica mode |

:::note[Stack Allocated]
Unlike `get_stats()` (which returns a heap-allocated struct), `get_db_stats()` fills a caller-provided struct. No manual free is needed - the Python binding handles this automatically.
:::

### Range Cost Estimation

`range_cost` estimates the computational cost of iterating between two keys in a column family. The returned value is an opaque double - meaningful only for comparison with other values from the same method. It uses only in-memory metadata and performs no disk I/O.

```python
cf = db.get_column_family("my_cf")

cost_a = cf.range_cost(b"user:0000", b"user:0999")
cost_b = cf.range_cost(b"user:1000", b"user:1099")

if cost_a < cost_b:
    print("Range A is cheaper to iterate")
```

**How it works**

The method walks all SSTable levels and uses in-memory metadata to estimate how many blocks and entries fall within the given key range:

- With block indexes enabled · Uses O(log B) binary search per overlapping SSTable to find the block slots containing each key bound
- Without block indexes · Falls back to byte-level key interpolation within the SSTable's min/max key range
- B+tree SSTables (`use_btree=True`) · Uses key interpolation against tree node counts, plus tree height as a seek cost
- Compression · Compressed SSTables receive a 1.5× weight multiplier to account for decompression overhead
- Merge overhead · Each overlapping SSTable adds a small fixed cost for merge-heap operations
- Memtable · The active memtable's entry count contributes a small in-memory cost

Key order does not matter - `range_cost(a, b)` produces the same result as `range_cost(b, a)`.

**Use cases**
- Query planning · Compare candidate key ranges to find the cheapest one to scan
- Load balancing · Distribute range scan work across threads by estimating per-range cost
- Adaptive prefetching · Decide how aggressively to prefetch based on range size
- Monitoring · Track how data distribution changes across key ranges over time

:::note[Cost Values]
The returned cost is not an absolute measure (it does not represent milliseconds, bytes, or entry counts). It is a relative scalar - only meaningful when compared with other `range_cost` results. A cost of 0.0 means no overlapping SSTables or memtable entries were found for the range.
:::

### Commit Hook (Change Data Capture)

`set_commit_hook` registers a callback that fires synchronously after every transaction commit on a column family. The hook receives the full batch of committed operations atomically, enabling real-time change data capture without WAL parsing or external log consumers.

```python
cf = db.get_column_family("my_cf")

def on_commit(ops: list[tidesdb.CommitOp], commit_seq: int) -> int:
    for op in ops:
        if op.is_delete:
            print(f"[seq={commit_seq}] DELETE key={op.key}")
        else:
            print(f"[seq={commit_seq}] PUT key={op.key} value={op.value} ttl={op.ttl}")
    return 0  # 0 = success

cf.set_commit_hook(on_commit)

# Normal writes now trigger the hook automatically
with db.begin_txn() as txn:
    txn.put(cf, b"user:1000", b"Alice")
    txn.put(cf, b"user:1001", b"Bob")
    txn.commit()   # on_commit fires here with both ops

# Disable the hook
cf.clear_commit_hook()
```

**CommitOp fields**

| Field | Type | Description |
|-------|------|-------------|
| `key` | `bytes` | Key data |
| `value` | `bytes \| None` | Value data (`None` for deletes) |
| `ttl` | `int` | Time-to-live as Unix timestamp (-1 = no expiry) |
| `is_delete` | `bool` | `True` if this is a delete operation |

**Callback signature**

```python
def callback(ops: list[tidesdb.CommitOp], commit_seq: int) -> int:
    ...
```

Return `0` on success. A non-zero return is logged as a warning but does **not** roll back the commit - the data is already durable before the callback runs.

**Behavior**
- The hook fires after WAL write, memtable apply, and commit status marking are complete
- Each column family has its own independent hook; a multi-CF transaction fires the hook once per CF with only that CF's operations
- `commit_seq` is monotonically increasing across commits and can be used as a replication cursor
- The hook executes synchronously on the committing thread - keep the callback fast to avoid stalling writers
- Python exceptions in the callback are caught internally and treated as non-zero return (logged, commit unaffected)
- Calling `clear_commit_hook()` disables it immediately with no restart required

**Use cases**
- Replication · Ship committed batches to replicas in commit order
- Event streaming · Publish mutations to Kafka, NATS, or any message broker
- Secondary indexing · Maintain a reverse index or materialized view
- Audit logging · Record every mutation with key, value, TTL, and sequence number
- Debugging · Attach a temporary hook in production to inspect live writes

:::note[Runtime-Only]
Commit hooks are not persisted to `config.ini`. After a database restart, hooks must be re-registered by the application. This is by design - function pointers cannot be serialized.
:::

### Backup

```python
# Create an on-disk snapshot without blocking reads/writes
db.backup("./mydb_backup")

# The backup directory must be non-existent or empty
# Backup can be opened as a normal database
with tidesdb.TidesDB.open("./mydb_backup") as backup_db:
    # ... read from backup
    pass
```

### Checkpoint

Create a lightweight, near-instant snapshot of the database using hard links instead of copying SSTable data.

```python
# Create a checkpoint (near-instant, uses hard links)
db.checkpoint("./mydb_checkpoint")

# The checkpoint directory must be non-existent or empty
# Checkpoint can be opened as a normal database
with tidesdb.TidesDB.open("./mydb_checkpoint") as checkpoint_db:
    # ... read from checkpoint
    pass
```

**Checkpoint vs Backup**

| | `backup()` | `checkpoint()` |
|--|---|---|
| Speed | Copies every SSTable byte-by-byte | Near-instant (hard links, O(1) per file) |
| Disk usage | Full independent copy | No extra disk until compaction removes old SSTables |
| Portability | Can be moved to another filesystem or machine | Same filesystem only (hard link requirement) |
| Use case | Archival, disaster recovery, remote shipping | Fast local snapshots, point-in-time reads, streaming backups |

**Behavior**
- Requires `checkpoint_dir` to be a non-existent directory or an empty directory
- For each column family, flushes the active memtable, halts compactions, hard links all SSTable files, copies small metadata files, then resumes compactions
- Falls back to file copy if hard linking fails (e.g., cross-filesystem)
- Database stays open and usable during checkpoint

:::note
Hard-linked files share storage with the live database. Deleting the original database does not affect the checkpoint (hard link semantics). The checkpoint can be opened as a normal TidesDB database.
:::

### Updating Runtime Configuration

```python
cf = db.get_column_family("my_cf")

# Update runtime-safe configuration settings
new_config = tidesdb.default_column_family_config()
new_config.write_buffer_size = 256 * 1024 * 1024  # 256MB
new_config.bloom_fpr = 0.001  # 0.1% false positive rate
new_config.sync_mode = tidesdb.SyncMode.SYNC_FULL

# persist_to_disk=True saves to config.ini (default)
cf.update_runtime_config(new_config, persist_to_disk=True)

# Updatable settings (safe to change at runtime):
# -- write_buffer_size     -- Memtable flush threshold
# -- skip_list_max_level   -- Skip list level for new memtables
# -- skip_list_probability -- Skip list probability for new memtables
# -- bloom_fpr             -- False positive rate for new SSTables
# -- index_sample_ratio    -- Index sampling ratio for new SSTables
# -- sync_mode             -- Durability mode
# -- sync_interval_us      -- Sync interval in microseconds

# Save config to custom INI file
tidesdb.save_config_to_ini("custom_config.ini", "my_cf", new_config)

# Load config from INI file
loaded_config = tidesdb.load_config_from_ini("custom_config.ini", "my_cf")
db.create_column_family("restored_cf", loaded_config)
```

### B+tree KLog Format (Optional)

Column families can optionally use a B+tree structure for the key log instead of the default block-based format. The B+tree klog format offers faster point lookups through O(log N) tree traversal.

```python
config = tidesdb.default_column_family_config()
config.use_btree = True  # Enable B+tree klog format

db.create_column_family("btree_cf", config)
```

**Characteristics**
- Point lookups · O(log N) tree traversal with binary search at each node
- Range scans · Doubly-linked leaf nodes enable efficient bidirectional iteration
- Immutable · Tree is bulk-loaded from sorted memtable data during flush
- Compression · Nodes compress independently using the same algorithms

**When to use B+tree klog format**
- Read-heavy workloads with frequent point lookups
- Workloads where read latency is more important than write throughput
- Large SSTables where block scanning becomes expensive

**Tradeoffs**
- Slightly higher write amplification during flush
- Larger metadata overhead per node
- Block-based format may be faster for sequential scans

:::note
`use_btree` **cannot be changed** after column family creation. Different column families can use different formats.
:::

### Compression Algorithms

```python
config = tidesdb.default_column_family_config()

# Available algorithms:
config.compression_algorithm = tidesdb.CompressionAlgorithm.NO_COMPRESSION
config.compression_algorithm = tidesdb.CompressionAlgorithm.SNAPPY_COMPRESSION
config.compression_algorithm = tidesdb.CompressionAlgorithm.LZ4_COMPRESSION
config.compression_algorithm = tidesdb.CompressionAlgorithm.LZ4_FAST_COMPRESSION
config.compression_algorithm = tidesdb.CompressionAlgorithm.ZSTD_COMPRESSION
```

### Sync Modes

```python
config = tidesdb.default_column_family_config()

# SYNC_NONE: Fastest, least durable (OS handles flushing)
config.sync_mode = tidesdb.SyncMode.SYNC_NONE

# SYNC_INTERVAL: Balanced (periodic background syncing)
config.sync_mode = tidesdb.SyncMode.SYNC_INTERVAL
config.sync_interval_us = 128000  # 128ms

# SYNC_FULL: Most durable (fsync on every write)
config.sync_mode = tidesdb.SyncMode.SYNC_FULL
```

### Log Levels

```python
import tidesdb

# Available log levels
config = tidesdb.Config(
    db_path="./mydb",
    log_level=tidesdb.LogLevel.LOG_DEBUG,    # Detailed diagnostic info
    # log_level=tidesdb.LogLevel.LOG_INFO,   # General info (default)
    # log_level=tidesdb.LogLevel.LOG_WARN,   # Warnings only
    # log_level=tidesdb.LogLevel.LOG_ERROR,  # Errors only
    # log_level=tidesdb.LogLevel.LOG_FATAL,  # Critical errors only
    # log_level=tidesdb.LogLevel.LOG_NONE,   # Disable logging
    log_to_file=True,                        # Write to ./mydb/LOG instead of stderr
    log_truncation_at=24 * 1024 * 1024,      # Truncate log file at 24MB (0 = no truncation)
)
```

### Column Family Configuration Reference

All available configuration options for column families:

```python
config = tidesdb.default_column_family_config()

# Memory and LSM structure
config.write_buffer_size = 64 * 1024 * 1024   # Memtable flush threshold (default: 64MB)
config.level_size_ratio = 10                  # Level size multiplier (default: 10)
config.min_levels = 5                         # Minimum LSM levels (default: 5)
config.dividing_level_offset = 2              # Compaction dividing level offset (default: 2)

# Skip list settings
config.skip_list_max_level = 12               # Skip list max level (default: 12)
config.skip_list_probability = 0.25           # Skip list probability (default: 0.25)

# Compression
config.compression_algorithm = tidesdb.CompressionAlgorithm.LZ4_COMPRESSION

# Bloom filter
config.enable_bloom_filter = True             # Enable bloom filters (default: True)
config.bloom_fpr = 0.01                       # 1% false positive rate (default: 0.01)

# Block indexes
config.enable_block_indexes = True            # Enable block indexes (default: True)
config.index_sample_ratio = 1                 # Sample every block (default: 1)
config.block_index_prefix_len = 16            # Block index prefix length (default: 16)

# Durability
config.sync_mode = tidesdb.SyncMode.SYNC_INTERVAL
config.sync_interval_us = 128000              # Sync interval in microseconds (default: 128ms)

# Key ordering
config.comparator_name = "memcmp"             # Comparator name (default: "memcmp")

# Value separation
config.klog_value_threshold = 512             # Values > threshold go to vlog (default: 512)

# Resource limits
config.min_disk_space = 100 * 1024 * 1024     # Minimum disk space required (default: 100MB)

# Transaction isolation
config.default_isolation_level = tidesdb.IsolationLevel.READ_COMMITTED

# Compaction triggers
config.l1_file_count_trigger = 4              # L1 file count trigger (default: 4)
config.l0_queue_stall_threshold = 20          # L0 queue stall threshold (default: 20)

# B+tree klog format (optional)
config.use_btree = False                      # Use B+tree klog format (default: False)

# Object store settings (for object store mode)
config.object_lazy_compaction = False         # Enable lazy compaction for object store
config.object_prefetch_compaction = True      # Prefetch data during compaction (default: True)
```

### Custom Comparators

TidesDB uses comparators to determine the sort order of keys. Built-in comparators are automatically registered:

- `"memcmp"` (default) · Binary byte-by-byte comparison
- `"lexicographic"` · Null-terminated string comparison
- `"uint64"` · Unsigned 64-bit integer comparison
- `"int64"` · Signed 64-bit integer comparison
- `"reverse"` · Reverse binary comparison
- `"case_insensitive"` · Case-insensitive ASCII comparison

```python
# Check if a comparator is registered
if db.get_comparator("memcmp"):
    print("memcmp comparator is registered")

# Use a built-in comparator
config = tidesdb.default_column_family_config()
config.comparator_name = "reverse"  # Descending order
db.create_column_family("reverse_cf", config)

# Register a custom comparator
def timestamp_desc_compare(key1: bytes, key2: bytes) -> int:
    """Compare 8-byte timestamps in descending order."""
    import struct
    if len(key1) != 8 or len(key2) != 8:
        # Fallback to memcmp for invalid sizes
        if key1 < key2:
            return -1
        elif key1 > key2:
            return 1
        return 0
    
    ts1 = struct.unpack("<Q", key1)[0]
    ts2 = struct.unpack("<Q", key2)[0]
    
    # Reverse order for newest-first
    if ts1 > ts2:
        return -1
    elif ts1 < ts2:
        return 1
    return 0

# Register before creating column families that use it
db.register_comparator("timestamp_desc", timestamp_desc_compare)

# Use the custom comparator
config = tidesdb.default_column_family_config()
config.comparator_name = "timestamp_desc"
db.create_column_family("events", config)
```

:::note
Comparators must be registered **before** creating column families that use them. Once set, a comparator **cannot be changed** for a column family.
:::

### Unified Memtable Mode

TidesDB supports a unified memtable mode where all column families share a single memtable and WAL. This can reduce write amplification and improve throughput for workloads that write to many column families simultaneously.

```python
# Open with unified memtable enabled
db = tidesdb.TidesDB.open(
    "./mydb",
    unified_memtable=True,
    unified_memtable_write_buffer_size=32 * 1024 * 1024,  # 32MB
    unified_memtable_skip_list_max_level=12,
    unified_memtable_skip_list_probability=0.25,
    unified_memtable_sync_mode=tidesdb.SyncMode.SYNC_INTERVAL,
    unified_memtable_sync_interval_us=128000,  # 128ms
)

# Or via Config object
config = tidesdb.Config(
    db_path="./mydb",
    unified_memtable=True,
    unified_memtable_write_buffer_size=32 * 1024 * 1024,
)
db = tidesdb.TidesDB(config)

# Check if unified memtable is active
stats = db.get_db_stats()
if stats.unified_memtable_enabled:
    print(f"Unified memtable: {stats.unified_memtable_bytes} bytes")
```

**Configuration options**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `unified_memtable` | `bool` | `False` | Enable unified memtable mode |
| `unified_memtable_write_buffer_size` | `int` | `0` | Write buffer size (0 = default) |
| `unified_memtable_skip_list_max_level` | `int` | `0` | Skip list max level (0 = default) |
| `unified_memtable_skip_list_probability` | `float` | `0.0` | Skip list probability (0.0 = default) |
| `unified_memtable_sync_mode` | `SyncMode` | `SYNC_NONE` | WAL sync mode |
| `unified_memtable_sync_interval_us` | `int` | `0` | Sync interval in microseconds |

### Object Store Mode

Object store mode allows TidesDB to store SSTables in a remote object store (S3, MinIO, GCS, or any S3-compatible service) while using local disk as a cache. This separates compute from storage and enables cold start recovery from the remote store. Object store mode requires unified memtable mode and is automatically enforced when a connector is set.

#### Enabling Object Store Mode (Filesystem Connector)

```python
import tidesdb

# Create a filesystem connector (for testing and local replication)
store = tidesdb.objstore_fs_create("/mnt/nfs/tidesdb-objects")

# Get default object store config, then customize
os_cfg = tidesdb.objstore_default_config()
os_cfg.local_cache_max_bytes = 512 * 1024 * 1024  # 512MB local cache
os_cfg.max_concurrent_uploads = 8

# Open database with object store
db = tidesdb.TidesDB.open(
    "./mydb",
    object_store=store,
    object_store_config=os_cfg,
)

# Use the database normally -- SSTables are uploaded after flush
db.close()
```

#### Using Config Object

```python
import tidesdb

store = tidesdb.objstore_fs_create("/mnt/nfs/tidesdb-objects")

os_cfg = tidesdb.ObjStoreConfig(
    local_cache_max_bytes=512 * 1024 * 1024,
    max_concurrent_uploads=8,
    max_concurrent_downloads=16,
)

config = tidesdb.Config(
    db_path="./mydb",
    object_store=store,
    object_store_config=os_cfg,
)

db = tidesdb.TidesDB(config)
```

#### Object Store Configuration

Use `objstore_default_config()` for sensible defaults, then override fields as needed.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `local_cache_path` | `str \| None` | `None` (uses db_path) | Local directory for cached SSTable files |
| `local_cache_max_bytes` | `int` | `0` (unlimited) | Maximum local cache size in bytes |
| `cache_on_read` | `bool` | `True` | Cache downloaded files locally |
| `cache_on_write` | `bool` | `True` | Keep local copy after upload |
| `max_concurrent_uploads` | `int` | `4` | Number of parallel upload threads |
| `max_concurrent_downloads` | `int` | `8` | Number of parallel download threads |
| `multipart_threshold` | `int` | `67108864` (64MB) | Use multipart upload above this size |
| `multipart_part_size` | `int` | `8388608` (8MB) | Chunk size for multipart uploads |
| `sync_manifest_to_object` | `bool` | `True` | Upload MANIFEST after each compaction |
| `replicate_wal` | `bool` | `True` | Upload closed WAL segments for replication |
| `wal_upload_sync` | `bool` | `False` | `False` for background WAL upload, `True` to block flush |
| `wal_sync_threshold_bytes` | `int` | `1048576` (1MB) | Sync active WAL to object store when it grows by this many bytes (0 to disable) |
| `wal_sync_on_commit` | `bool` | `False` | Upload WAL after every txn commit for RPO=0 replication |
| `replica_mode` | `bool` | `False` | Enable read-only replica mode (writes raise `TidesDBError`) |
| `replica_sync_interval_us` | `int` | `5000000` (5s) | MANIFEST poll interval for replica sync in microseconds |
| `replica_replay_wal` | `bool` | `True` | Replay WAL from object store for near-real-time reads on replicas |

#### Per-CF Object Store Tuning

Column family configurations include three object store tuning fields.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `object_lazy_compaction` | `bool` | `False` | Compact less aggressively for remote storage |
| `object_prefetch_compaction` | `bool` | `True` | Download all inputs before compaction merge |

#### Replica Mode

Replica mode enables read-only nodes that follow a primary through the object store.

```python
import tidesdb

store = tidesdb.objstore_fs_create("/mnt/shared/tidesdb-objects")

os_cfg = tidesdb.ObjStoreConfig(
    replica_mode=True,
    replica_sync_interval_us=1000000,  # 1 second sync interval
    replica_replay_wal=True,
)

db = tidesdb.TidesDB.open(
    "./mydb_replica",
    object_store=store,
    object_store_config=os_cfg,
)

# Reads work normally
cf = db.get_column_family("my_cf")
with db.begin_txn() as txn:
    value = txn.get(cf, b"key")
    txn.commit()

# Writes raise TidesDBError with code TDB_ERR_READONLY
```

#### Sync-on-Commit WAL (Primary Side)

For tighter replication lag, enable sync-on-commit on the primary so every committed write is uploaded to the object store immediately.

```python
os_cfg = tidesdb.ObjStoreConfig(
    wal_sync_on_commit=True,  # RPO = 0, every commit is durable in object store
)
```

#### Cold Start Recovery

When the local database directory is empty but a connector is configured, TidesDB automatically discovers column families from the object store during recovery. It downloads MANIFEST and config files in parallel, reconstructs the SSTable inventory, and fetches SSTable data on demand as queries arrive.

```python
import shutil
shutil.rmtree("./mydb", ignore_errors=True)

# Reopen with the same connector -- cold start recovery
db = tidesdb.TidesDB.open(
    "./mydb",
    object_store=store,
    object_store_config=os_cfg,
)

# All data is available -- SSTables are fetched from the object store on demand
cf = db.get_column_family("my_cf")
```

### Promote to Primary

When a database is opened with an object store in replica mode, it is read-only. Use `promote_to_primary()` to switch to primary mode and enable writes.

```python
# Promote a replica to primary
db.promote_to_primary()

# Now writes are allowed
with db.begin_txn() as txn:
    txn.put(cf, b"key", b"value")
    txn.commit()
```

## Error Handling

```python
try:
    value = txn.get(cf, b"nonexistent_key")
except tidesdb.TidesDBError as e:
    print(f"Error: {e}")
    print(f"Error code: {e.code}")
```
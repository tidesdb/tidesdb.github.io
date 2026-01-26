---
title: TidesDB Python API Reference
description: Complete Python API reference for TidesDB
---

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/python.md).

<hr/>

## Getting Started

### Prerequisites

You **must** have the TidesDB shared C library installed on your system.  You can find the installation instructions [here](/reference/building/#_top).

## Installation

```bash
pip install tidesdb
```

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

# Write data in a transaction
with db.begin_txn() as txn:
    txn.put(cf, b"user:1", b"Alice")
    txn.put(cf, b"user:2", b"Bob")
    txn.commit()

# Read data
with db.begin_txn() as txn:
    value = txn.get(cf, b"user:1")
    print(f"user:1 = {value.decode()}")

# Iterate over all entries
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
    block_cache_size=64 * 1024 * 1024,  # 64MB
    max_open_sstables=256,
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

# Rename column family
db.rename_column_family("my_cf", "new_cf")

# Drop column family
db.drop_column_family("new_cf")
```

### Transactions

```python
txn = db.begin_txn()

try:
    # Put key-value pairs (TTL -1 means no expiration)
    txn.put(cf, b"key1", b"value1", ttl=-1)
    txn.put(cf, b"key2", b"value2", ttl=-1)
    
    value = txn.get(cf, b"key1")
    
    txn.delete(cf, b"key2")
    
    # Commit transaction
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
# - READ_UNCOMMITTED: Sees all data including uncommitted changes
# - READ_COMMITTED: Sees only committed data (default)
# - REPEATABLE_READ: Consistent snapshot, phantom reads possible
# - SNAPSHOT: Write-write conflict detection
# - SERIALIZABLE: Full read-write conflict detection (SSI)
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
        
        it.seek_to_first()
        for key, value in it:
            print(f"{key} = {value}")
```

### Maintenance Operations

```python
# Manual compaction
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
# - write_buffer_size: Memtable flush threshold
# - skip_list_max_level: Skip list level for new memtables
# - skip_list_probability: Skip list probability for new memtables
# - bloom_fpr: False positive rate for new SSTables
# - index_sample_ratio: Index sampling ratio for new SSTables
# - sync_mode: Durability mode
# - sync_interval_us: Sync interval in microseconds

# Save config to custom INI file
tidesdb.save_config_to_ini("custom_config.ini", "my_cf", new_config)
```

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
    log_level=tidesdb.LogLevel.LOG_DEBUG,   # Detailed diagnostic info
    # log_level=tidesdb.LogLevel.LOG_INFO,  # General info (default)
    # log_level=tidesdb.LogLevel.LOG_WARN,  # Warnings only
    # log_level=tidesdb.LogLevel.LOG_ERROR, # Errors only
    # log_level=tidesdb.LogLevel.LOG_FATAL, # Critical errors only
    # log_level=tidesdb.LogLevel.LOG_NONE,  # Disable logging
)
```

### Column Family Configuration Reference

All available configuration options for column families:

```python
config = tidesdb.default_column_family_config()

# Memory and LSM structure
config.write_buffer_size = 64 * 1024 * 1024  # Memtable flush threshold (default: 64MB)
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
```

### Custom Comparators

TidesDB uses comparators to determine the sort order of keys. Built-in comparators are automatically registered:

- `"memcmp"` (default): Binary byte-by-byte comparison
- `"lexicographic"`: Null-terminated string comparison
- `"uint64"`: Unsigned 64-bit integer comparison
- `"int64"`: Signed 64-bit integer comparison
- `"reverse"`: Reverse binary comparison
- `"case_insensitive"`: Case-insensitive ASCII comparison

```python
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

## Error Handling

```python
try:
    value = txn.get(cf, b"nonexistent_key")
except tidesdb.TidesDBError as e:
    print(f"Error: {e}")
    print(f"Error code: {e.code}")
```
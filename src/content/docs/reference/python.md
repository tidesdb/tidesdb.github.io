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
db.create_column_family("my_cf", config)

cf = db.get_column_family("my_cf")

names = db.list_column_families()
print(names)

stats = cf.get_stats()
print(f"Levels: {stats.num_levels}, Memtable: {stats.memtable_size} bytes")

# Drop column family
db.drop_column_family("my_cf")
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

# Get cache statistics
cache_stats = db.get_cache_stats()
print(f"Cache hits: {cache_stats.hits}, misses: {cache_stats.misses}")
print(f"Hit rate: {cache_stats.hit_rate:.2%}")
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

## Error Handling

```python
try:
    value = txn.get(cf, b"nonexistent_key")
except tidesdb.TidesDBError as e:
    print(f"Error: {e}")
    print(f"Error code: {e.code}")
```
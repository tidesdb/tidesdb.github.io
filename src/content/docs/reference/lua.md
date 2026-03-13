---
title: TidesDB Lua API Reference
description: Lua API reference for TidesDB
---

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/lua.md).

<hr/>

## Getting Started

### Prerequisites

You **must** have the TidesDB shared C library installed on your system.  You can find the installation instructions [here](/reference/building/#_top).

You also need **LuaJIT 2.1+** or **Lua 5.1+** with LuaFFI installed.

### Installation

**Using LuaRocks**
```bash
luarocks install tidesdb
```

**Manual Installation**
```bash
# Clone the repository
git clone https://github.com/tidesdb/tidesdb-lua.git

# Copy to your Lua package path
cp tidesdb-lua/src/tidesdb.lua /usr/local/share/lua/5.1/
```

### Custom Installation Paths

If you installed TidesDB to a non-standard location, you can specify custom paths using environment variables:

```bash
# Set custom library path
export LD_LIBRARY_PATH="/custom/path/lib:$LD_LIBRARY_PATH"  # Linux
# or
export DYLD_LIBRARY_PATH="/custom/path/lib:$DYLD_LIBRARY_PATH"  # macOS
```

**Custom prefix installation**
```bash
# Install TidesDB to custom location
cd tidesdb
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/opt/tidesdb
cmake --build build
sudo cmake --install build

# Configure library path
export LD_LIBRARY_PATH="/opt/tidesdb/lib:$LD_LIBRARY_PATH"  # Linux
# or
export DYLD_LIBRARY_PATH="/opt/tidesdb/lib:$DYLD_LIBRARY_PATH"  # macOS
```

## Usage

### Opening and Closing a Database

```lua
local tidesdb = require("tidesdb")

local db = tidesdb.TidesDB.open("./mydb", {
    num_flush_threads = 2,
    num_compaction_threads = 2,
    log_level = tidesdb.LogLevel.LOG_INFO,
    block_cache_size = 64 * 1024 * 1024,
    max_open_sstables = 256,
    max_memory_usage = 0,                  -- Global memory limit in bytes (0 = auto, 50% of system RAM)
    log_to_file = false,                   -- Write logs to file instead of stderr
    log_truncation_at = 24 * 1024 * 1024,  -- Log file truncation size (24MB), 0 = no truncation
})

print("Database opened successfully")

db:close()
```

### Creating and Dropping Column Families

Column families are isolated key-value stores with independent configuration.

```lua
local cf_config = tidesdb.default_column_family_config()
db:create_column_family("my_cf", cf_config)

local cf_config = tidesdb.default_column_family_config()
cf_config.write_buffer_size = 128 * 1024 * 1024
cf_config.level_size_ratio = 10
cf_config.min_levels = 5
cf_config.dividing_level_offset = 2
cf_config.skip_list_max_level = 12
cf_config.skip_list_probability = 0.25
cf_config.compression_algorithm = tidesdb.CompressionAlgorithm.LZ4_COMPRESSION
cf_config.enable_bloom_filter = true
cf_config.bloom_fpr = 0.01
cf_config.enable_block_indexes = true
cf_config.index_sample_ratio = 1
cf_config.block_index_prefix_len = 16
cf_config.sync_mode = tidesdb.SyncMode.SYNC_INTERVAL
cf_config.sync_interval_us = 128000
cf_config.klog_value_threshold = 512         -- Values >= 512 bytes go to vlog
cf_config.min_disk_space = 100 * 1024 * 1024 -- Minimum disk space required (100MB)
cf_config.default_isolation_level = tidesdb.IsolationLevel.READ_COMMITTED
cf_config.l1_file_count_trigger = 4          -- L1 file count trigger for compaction
cf_config.l0_queue_stall_threshold = 20      -- L0 queue stall threshold
cf_config.use_btree = false                  -- Use B+tree format for klog (default: false)

db:create_column_family("my_cf", cf_config)

db:drop_column_family("my_cf")
```

### Dropping a Column Family by Pointer

When you already hold a column family handle, use `delete_column_family` to skip the name lookup.

```lua
local cf = db:get_column_family("my_cf")

db:delete_column_family(cf)
```

:::tip[Which to use]
- `db:drop_column_family(name)` · convenient when you only have the name
- `db:delete_column_family(cf)` · faster when you already hold a column family handle, avoids a redundant linear scan
:::

### B+tree KLog Format (Optional)

Column families can optionally use a B+tree structure for the key log instead of the default block-based format. The B+tree klog format offers faster point lookups through O(log N) tree traversal rather than linear block scanning.

```lua
local cf_config = tidesdb.default_column_family_config()
cf_config.use_btree = true  -- Enable B+tree klog format

db:create_column_family("btree_cf", cf_config)
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

:::caution[Important]
`use_btree` **cannot be changed** after column family creation. Different column families can use different formats.
:::

### Renaming Column Families

Atomically rename a column family and its underlying directory. The operation waits for any in-progress flush or compaction to complete before renaming.

```lua
db:rename_column_family("old_name", "new_name")

local cf = db:get_column_family("new_name")
```

### Cloning Column Families

Create a complete copy of an existing column family with a new name. The clone contains all the data from the source at the time of cloning.

```lua
db:clone_column_family("source_cf", "cloned_cf")

local original = db:get_column_family("source_cf")
local clone = db:get_column_family("cloned_cf")
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

### CRUD Operations

All operations in TidesDB are performed through transactions for ACID guarantees.

#### Writing Data

```lua
local cf = db:get_column_family("my_cf")

local txn = db:begin_txn()

txn:put(cf, "key", "value", -1)

txn:commit()
txn:free()
```

#### Writing with TTL

```lua
local cf = db:get_column_family("my_cf")

local txn = db:begin_txn()

local ttl = os.time() + 10

txn:put(cf, "temp_key", "temp_value", ttl)

txn:commit()
txn:free()
```

**TTL Examples**
```lua
local ttl = -1

local ttl = os.time() + 5 * 60

local ttl = os.time() + 60 * 60

local ttl = os.time({year=2026, month=12, day=31, hour=23, min=59, sec=59})
```

#### Reading Data

```lua
local cf = db:get_column_family("my_cf")

local txn = db:begin_txn()

local value = txn:get(cf, "key")

print("Value: " .. value)

txn:free()
```

#### Deleting Data

```lua
local cf = db:get_column_family("my_cf")

local txn = db:begin_txn()

txn:delete(cf, "key")

txn:commit()
txn:free()
```

#### Multi-Operation Transactions

```lua
local cf = db:get_column_family("my_cf")

local txn = db:begin_txn()

local ok, err = pcall(function()
    txn:put(cf, "key1", "value1", -1)
    txn:put(cf, "key2", "value2", -1)
    txn:delete(cf, "old_key")
end)

if not ok then
    txn:rollback()
    error(err)
end

txn:commit()
txn:free()
```

#### Multi-Column-Family Transactions

TidesDB supports atomic transactions across multiple column families with true all-or-nothing semantics.

```lua
local users_cf = db:get_column_family("users")
local orders_cf = db:get_column_family("orders")

local txn = db:begin_txn()

txn:put(users_cf, "user:1000", "John Doe", -1)
txn:put(orders_cf, "order:5000", "user:1000|product:A", -1)

txn:commit()
txn:free()
```

**Multi-CF guarantees**
- Either all CFs commit or none do (atomic)
- Automatically detected when operations span multiple CFs
- Uses global sequence numbers for atomic ordering
- Each CF's WAL receives operations with the same commit sequence number

### Iterating Over Data

Iterators provide efficient bidirectional traversal over key-value pairs.

#### Forward Iteration

```lua
local cf = db:get_column_family("my_cf")

local txn = db:begin_txn()

local iter = txn:new_iterator(cf)

iter:seek_to_first()

while iter:valid() do
    local key = iter:key()
    local value = iter:value()
    
    print(string.format("Key: %s, Value: %s", key, value))
    
    iter:next()
end

iter:free()
txn:free()
```

#### Backward Iteration

```lua
local cf = db:get_column_family("my_cf")

local txn = db:begin_txn()

local iter = txn:new_iterator(cf)

iter:seek_to_last()

while iter:valid() do
    local key = iter:key()
    local value = iter:value()
    
    print(string.format("Key: %s, Value: %s", key, value))
    
    iter:prev()
end

iter:free()
txn:free()
```

#### Seek to Specific Key

`iter:seek(key)` positions the iterator at the first key >= target key.

```lua
local cf = db:get_column_family("my_cf")

local txn = db:begin_txn()

local iter = txn:new_iterator(cf)

iter:seek("user:1000")

if iter:valid() then
    local key = iter:key()
    print("Found: " .. key)
end

iter:free()
txn:free()
```

`iter:seek_for_prev(key)` positions the iterator at the last key <= target key.

```lua
local cf = db:get_column_family("my_cf")

local txn = db:begin_txn()

local iter = txn:new_iterator(cf)

iter:seek_for_prev("user:2000")

while iter:valid() do
    local key = iter:key()
    print("Found: " .. key)
    iter:prev()
end

iter:free()
txn:free()
```

#### Prefix Seeking

Since `iter:seek(key)` positions the iterator at the first key >= target, you can use a prefix as the seek target to efficiently scan all keys sharing that prefix:

```lua
local cf = db:get_column_family("my_cf")

local txn = db:begin_txn()

local iter = txn:new_iterator(cf)

local prefix = "user:"
iter:seek(prefix)

while iter:valid() do
    local key = iter:key()
    if key:sub(1, #prefix) ~= prefix then break end
    
    local value = iter:value()
    print(string.format("Key: %s, Value: %s", key, value))
    
    iter:next()
end

iter:free()
txn:free()
```

### Getting Column Family Statistics

Retrieve detailed statistics about a column family.

```lua
local cf = db:get_column_family("my_cf")

local stats = cf:get_stats()

print(string.format("Number of Levels: %d", stats.num_levels))
print(string.format("Memtable Size: %d bytes", stats.memtable_size))
print(string.format("Total Keys: %d", stats.total_keys))
print(string.format("Total Data Size: %d bytes", stats.total_data_size))
print(string.format("Average Key Size: %.2f bytes", stats.avg_key_size))
print(string.format("Average Value Size: %.2f bytes", stats.avg_value_size))
print(string.format("Read Amplification: %.2f", stats.read_amp))
print(string.format("Hit Rate: %.2f%%", stats.hit_rate * 100))

for i, size in ipairs(stats.level_sizes) do
    print(string.format("Level %d: %d bytes, %d SSTables, %d keys",
        i, size, stats.level_num_sstables[i], stats.level_key_counts[i]))
end

if stats.use_btree then
    print(string.format("B+tree Total Nodes: %d", stats.btree_total_nodes))
    print(string.format("B+tree Max Height: %d", stats.btree_max_height))
    print(string.format("B+tree Avg Height: %.2f", stats.btree_avg_height))
end

if stats.config then
    print(string.format("Write Buffer Size: %d", stats.config.write_buffer_size))
    print(string.format("Compression: %d", stats.config.compression_algorithm))
    print(string.format("Bloom Filter: %s", tostring(stats.config.enable_bloom_filter)))
    print(string.format("Sync Mode: %d", stats.config.sync_mode))
    print(string.format("Use B+tree: %s", tostring(stats.config.use_btree)))
end
```

**Statistics Fields**
- `num_levels` · Number of LSM levels
- `memtable_size` · Current memtable size in bytes
- `level_sizes` · Array of sizes per level
- `level_num_sstables` · Array of SSTable counts per level
- `level_key_counts` · Array of key counts per level
- `total_keys` · Total keys across memtable and all SSTables
- `total_data_size` · Total data size (klog + vlog) across all SSTables
- `avg_key_size` · Average key size in bytes
- `avg_value_size` · Average value size in bytes
- `read_amp` · Read amplification (point lookup cost multiplier)
- `hit_rate` · Cache hit rate (0.0 if cache disabled)
- `use_btree` · Whether column family uses B+tree klog format
- `btree_total_nodes` · Total B+tree nodes across all SSTables (only if use_btree=true)
- `btree_max_height` · Maximum tree height across all SSTables (only if use_btree=true)
- `btree_avg_height` · Average tree height across all SSTables (only if use_btree=true)
- `config` · Column family configuration

### Getting Database-Level Statistics

Get aggregate statistics across the entire database instance.

```lua
local db_stats = db:get_db_stats()

print(string.format("Column families: %d", db_stats.num_column_families))
print(string.format("Total memory: %d bytes", db_stats.total_memory))
print(string.format("Resolved memory limit: %d bytes", db_stats.resolved_memory_limit))
print(string.format("Memory pressure level: %d", db_stats.memory_pressure_level))
print(string.format("Global sequence: %d", db_stats.global_seq))
print(string.format("Flush queue: %d pending", db_stats.flush_queue_size))
print(string.format("Compaction queue: %d pending", db_stats.compaction_queue_size))
print(string.format("Total SSTables: %d", db_stats.total_sstable_count))
print(string.format("Total data size: %d bytes", db_stats.total_data_size_bytes))
print(string.format("Open SSTable handles: %d", db_stats.num_open_sstables))
print(string.format("In-flight txn memory: %d bytes", db_stats.txn_memory_bytes))
print(string.format("Immutable memtables: %d", db_stats.total_immutable_count))
print(string.format("Memtable bytes: %d", db_stats.total_memtable_bytes))
```

**Database statistics fields**
- `num_column_families` · Number of column families
- `total_memory` · System total memory
- `available_memory` · System available memory at open time
- `resolved_memory_limit` · Resolved memory limit (auto or configured)
- `memory_pressure_level` · Current memory pressure (0=normal, 1=elevated, 2=high, 3=critical)
- `flush_pending_count` · Number of pending flush operations (queued + in-flight)
- `total_memtable_bytes` · Total bytes in active memtables across all CFs
- `total_immutable_count` · Total immutable memtables across all CFs
- `total_sstable_count` · Total SSTables across all CFs and levels
- `total_data_size_bytes` · Total data size (klog + vlog) across all CFs
- `num_open_sstables` · Number of currently open SSTable file handles
- `global_seq` · Current global sequence number
- `txn_memory_bytes` · Bytes held by in-flight transactions
- `compaction_queue_size` · Number of pending compaction tasks
- `flush_queue_size` · Number of pending flush tasks in queue

:::note[Stack Allocated]
Unlike `cf:get_stats()` (which heap-allocates), `db:get_db_stats()` fills a caller-provided struct on the stack. No free is needed.
:::

### Getting Block Cache Statistics

Get statistics for the global block cache (shared across all column families).

```lua
local cache_stats = db:get_cache_stats()

if cache_stats.enabled then
    print("Cache enabled: yes")
    print(string.format("Total entries: %d", cache_stats.total_entries))
    print(string.format("Total bytes: %.2f MB", cache_stats.total_bytes / (1024 * 1024)))
    print(string.format("Hits: %d", cache_stats.hits))
    print(string.format("Misses: %d", cache_stats.misses))
    print(string.format("Hit rate: %.1f%%", cache_stats.hit_rate * 100))
    print(string.format("Partitions: %d", cache_stats.num_partitions))
else
    print("Cache enabled: no (block_cache_size = 0)")
end
```

### Range Cost Estimation

Estimate the computational cost of iterating between two keys in a column family. The returned value is an opaque double - meaningful only for comparison with other values from the same function. It uses only in-memory metadata and performs no disk I/O.

```lua
local cf = db:get_column_family("my_cf")

local cost_a = cf:range_cost("user:0000", "user:0999")
local cost_b = cf:range_cost("user:1000", "user:1099")

if cost_a < cost_b then
    print("Range A is cheaper to iterate")
end
```

**How it works**
- With block indexes enabled · Uses O(log B) binary search per overlapping SSTable to find the block slots containing each key bound
- Without block indexes · Falls back to byte-level key interpolation using the leading 8 bytes of each key
- B+tree SSTables · Uses key interpolation against tree node counts, plus tree height as a seek cost
- Compression · Compressed SSTables receive a 1.5× weight multiplier to account for decompression overhead
- Key order does not matter - the function normalizes the range internally

**Use cases**
- Query planning · Compare candidate key ranges to find the cheapest one to scan
- Load balancing · Distribute range scan work across threads by estimating per-range cost
- Adaptive prefetching · Decide how aggressively to prefetch based on range size
- Monitoring · Track how data distribution changes across key ranges over time

:::note[Cost Values]
The returned cost is not an absolute measure (it does not represent milliseconds, bytes, or entry counts). It is a relative scalar - only meaningful when compared with other `cf:range_cost` results. A cost of 0.0 means no overlapping SSTables or memtable entries were found for the range.
:::

### Listing Column Families

```lua
local cf_list = db:list_column_families()

print("Available column families:")
for _, name in ipairs(cf_list) do
    print("  - " .. name)
end
```

### Compaction

#### Manual Compaction

```lua
local cf = db:get_column_family("my_cf")

local ok, err = pcall(function()
    cf:compact()
end)
if not ok then
    print("Compaction note: " .. tostring(err))
end
```

#### Manual Memtable Flush

```lua
local cf = db:get_column_family("my_cf")

local ok, err = pcall(function()
    cf:flush_memtable()
end)
if not ok then
    print("Flush note: " .. tostring(err))
end
```

#### Checking Flush/Compaction Status

Check if a column family currently has flush or compaction operations in progress.

```lua
local cf = db:get_column_family("my_cf")

if cf:is_flushing() then
    print("Flush in progress")
end

if cf:is_compacting() then
    print("Compaction in progress")
end

while cf:is_flushing() or cf:is_compacting() do
    os.execute("sleep 0.1")
end
print("Background operations completed")
```

**Use cases**
- Graceful shutdown · Wait for background operations to complete before closing
- Maintenance windows · Check if operations are running before triggering manual compaction
- Monitoring · Track background operation status for observability

#### Purge Column Family

`cf:purge()` forces a synchronous flush and aggressive compaction for a single column family. Unlike `cf:flush_memtable()` and `cf:compact()` (which are non-blocking), purge blocks until all flush and compaction I/O is complete.

```lua
local cf = db:get_column_family("my_cf")

cf:purge()
-- All data is now flushed to SSTables and compacted
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

#### Purge Database

`db:purge()` forces a synchronous flush and aggressive compaction for **all** column families, then drains both the global flush and compaction queues.

```lua
db:purge()
-- All CFs flushed and compacted, all queues drained
```

**Behavior**
1. Calls `cf:purge()` on each column family
2. Drains the global flush queue (waits for queue size and pending count to reach 0)
3. Drains the global compaction queue (waits for queue size to reach 0)

:::tip[Purge vs Manual Flush + Compact]
`cf:flush_memtable()` and `cf:compact()` are non-blocking - they enqueue work and return immediately. `cf:purge()` and `db:purge()` are synchronous - they block until all work is complete. Use purge when you need a guarantee that all data is on disk and compacted before proceeding.
:::

### Manual WAL Sync

`cf:sync_wal()` forces an immediate fsync of the active write-ahead log for a column family. This is useful for explicit durability control when using `SYNC_NONE` or `SYNC_INTERVAL` modes.

```lua
local cf = db:get_column_family("my_cf")

-- Force WAL durability after a batch of writes
cf:sync_wal()
```

**When to use**
- Application-controlled durability · Sync the WAL at specific points (e.g., after a batch of related writes) when using `SYNC_NONE` or `SYNC_INTERVAL`
- Pre-checkpoint · Ensure all buffered WAL data is on disk before taking a checkpoint
- Graceful shutdown · Flush WAL buffers before closing the database
- Critical writes · Force durability for specific high-value writes without using `SYNC_FULL` for all writes

**Behavior**
- Acquires a reference to the active memtable to safely access its WAL
- Calls `fdatasync` on the WAL file descriptor
- Thread-safe - can be called concurrently from multiple threads
- If the memtable rotates during the call, retries with the new active memtable

### Sync Modes

Control the durability vs performance tradeoff.

```lua
local cf_config = tidesdb.default_column_family_config()

cf_config.sync_mode = tidesdb.SyncMode.SYNC_NONE

cf_config.sync_mode = tidesdb.SyncMode.SYNC_INTERVAL
cf_config.sync_interval_us = 128000  -- Sync every 128ms

cf_config.sync_mode = tidesdb.SyncMode.SYNC_FULL

db:create_column_family("my_cf", cf_config)
```

### Compression Algorithms

TidesDB supports multiple compression algorithms:

```lua
local cf_config = tidesdb.default_column_family_config()

cf_config.compression_algorithm = tidesdb.CompressionAlgorithm.NO_COMPRESSION
cf_config.compression_algorithm = tidesdb.CompressionAlgorithm.SNAPPY_COMPRESSION   -- Not available on SunOS/Illumos
cf_config.compression_algorithm = tidesdb.CompressionAlgorithm.LZ4_COMPRESSION      -- Default, balanced
cf_config.compression_algorithm = tidesdb.CompressionAlgorithm.LZ4_FAST_COMPRESSION -- Faster, slightly lower ratio
cf_config.compression_algorithm = tidesdb.CompressionAlgorithm.ZSTD_COMPRESSION     -- Best ratio, moderate speed

db:create_column_family("my_cf", cf_config)
```

**Choosing a Compression Algorithm**

| Workload | Recommended | Rationale |
|----------|-------------|----------|
| General purpose | `LZ4_COMPRESSION` | Best balance of speed and compression |
| Write-heavy | `LZ4_FAST_COMPRESSION` | Minimize CPU overhead on writes |
| Storage-constrained | `ZSTD_COMPRESSION` | Maximum compression ratio |
| Pre-compressed data | `NO_COMPRESSION` | Avoid double compression overhead |

### Database Backup

Create an on-disk snapshot of an open database without blocking normal reads/writes.

```lua
db:backup("./mydb_backup")

local backup_db = tidesdb.TidesDB.open("./mydb_backup")
```

**Behavior**
- Requires the backup directory to be non-existent or empty
- Does not copy the `LOCK` file, so the backup can be opened normally
- Database stays open and usable during backup
- The backup represents the database state after the final flush/compaction drain

### Database Checkpoint

Create a lightweight, near-instant snapshot of an open database using hard links instead of copying SSTable data.

```lua
db:checkpoint("./mydb_checkpoint")

local checkpoint_db = tidesdb.TidesDB.open("./mydb_checkpoint")
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

| | `db:backup(dir)` | `db:checkpoint(dir)` |
|--|---|---|
| Speed | Copies every SSTable byte-by-byte | Near-instant (hard links, O(1) per file) |
| Disk usage | Full independent copy | No extra disk until compaction removes old SSTables |
| Portability | Can be moved to another filesystem or machine | Same filesystem only (hard link requirement) |
| Use case | Archival, disaster recovery, remote shipping | Fast local snapshots, point-in-time reads, streaming backups |

### Updating Runtime Configuration

Update runtime-safe configuration settings for a column family. Changes apply to new operations only.

```lua
local cf = db:get_column_family("my_cf")

local new_config = tidesdb.default_column_family_config()
new_config.write_buffer_size = 256 * 1024 * 1024  -- 256MB
new_config.bloom_fpr = 0.001  -- 0.1% false positive rate

cf:update_runtime_config(new_config, true)
```

**Updatable settings** (safe to change at runtime):
- `write_buffer_size` · Memtable flush threshold
- `skip_list_max_level` · Skip list level for new memtables
- `skip_list_probability` · Skip list probability for new memtables
- `bloom_fpr` · False positive rate for new SSTables
- `index_sample_ratio` · Index sampling ratio for new SSTables
- `sync_mode` · Durability mode
- `sync_interval_us` · Sync interval in microseconds

**Non-updatable settings** (would corrupt existing data):
- `compression_algorithm`, `enable_block_indexes`, `enable_bloom_filter`, `comparator_name`, `level_size_ratio`, `klog_value_threshold`, `min_levels`, `dividing_level_offset`, `block_index_prefix_len`, `l1_file_count_trigger`, `l0_queue_stall_threshold`, `use_btree`

### Commit Hook (Change Data Capture)

`cf:set_commit_hook` registers a callback that fires synchronously after every transaction commit on a column family. The hook receives the full batch of committed operations atomically, enabling real-time change data capture without WAL parsing.

```lua
local ffi = require("ffi")

local cf = db:get_column_family("my_cf")

local my_hook = ffi.cast("tidesdb_commit_hook_fn", function(ops, num_ops, commit_seq, ctx)
    for i = 0, num_ops - 1 do
        local key = ffi.string(ops[i].key, ops[i].key_size)
        if ops[i].is_delete ~= 0 then
            print(string.format("[seq=%d] DELETE %s", tonumber(commit_seq), key))
        else
            local value = ffi.string(ops[i].value, ops[i].value_size)
            print(string.format("[seq=%d] PUT %s = %s", tonumber(commit_seq), key, value))
        end
    end
    return 0
end)

-- Attach hook
cf:set_commit_hook(my_hook, nil)

-- Normal writes now trigger the hook automatically
local txn = db:begin_txn()
txn:put(cf, "key1", "value1", -1)
txn:commit()  -- my_hook fires here
txn:free()

-- Detach hook
cf:clear_commit_hook()

-- Free the callback when no longer needed
my_hook:free()
```

**Operation fields** (available inside the callback)
- `ops[i].key` / `ops[i].key_size` · Key data and size
- `ops[i].value` / `ops[i].value_size` · Value data and size (`NULL`/0 for deletes)
- `ops[i].ttl` · Time-to-live for the entry
- `ops[i].is_delete` · 1 for delete operations, 0 for puts

**Behavior**
- The hook fires after WAL write, memtable apply, and commit status marking are complete - data is fully durable before the callback runs
- Hook failure (non-zero return) is logged but does not affect the commit result
- Each column family has its own independent hook; a multi-CF transaction fires the hook once per CF with only that CF's operations
- `commit_seq` is monotonically increasing across commits and can be used as a replication cursor
- Pointers in the operation struct are valid only during the callback invocation - copy any data you need to retain
- The hook executes synchronously on the committing thread; keep the callback fast to avoid stalling writers
- Setting the hook to `nil` via `cf:clear_commit_hook()` disables it immediately

**Use cases**
- Replication · Ship committed batches to replicas in commit order
- Event streaming · Publish mutations to Kafka, NATS, or any message broker
- Secondary indexing · Maintain a reverse index or materialized view
- Audit logging · Record every mutation with key, value, TTL, and sequence number
- Debugging · Attach a temporary hook in production to inspect live writes

:::note[Runtime-Only]
Commit hooks are not persisted. After a database restart, hooks must be re-registered by the application. This is by design - function pointers cannot be serialized.
:::

### Configuration File Operations

Load and save column family configurations from/to INI files.

```lua
local config = tidesdb.load_config_from_ini("config.ini", "my_cf")

tidesdb.save_config_to_ini("config.ini", "my_cf", config)
```

## Error Handling

```lua
local cf = db:get_column_family("my_cf")

local txn = db:begin_txn()

local ok, err = pcall(function()
    txn:put(cf, "key", "value", -1)
end)

if not ok then
    print("Error: " .. tostring(err))
    txn:rollback()
    return
end

txn:commit()
txn:free()
```

**Error Codes**
- `TDB_SUCCESS` (0) · Operation successful
- `TDB_ERR_MEMORY` (-1) · Memory allocation failed
- `TDB_ERR_INVALID_ARGS` (-2) · Invalid arguments
- `TDB_ERR_NOT_FOUND` (-3) · Key not found
- `TDB_ERR_IO` (-4) · I/O error
- `TDB_ERR_CORRUPTION` (-5) · Data corruption
- `TDB_ERR_EXISTS` (-6) · Resource already exists
- `TDB_ERR_CONFLICT` (-7) · Transaction conflict
- `TDB_ERR_TOO_LARGE` (-8) · Key or value too large
- `TDB_ERR_MEMORY_LIMIT` (-9) · Memory limit exceeded
- `TDB_ERR_INVALID_DB` (-10) · Invalid database handle
- `TDB_ERR_UNKNOWN` (-11) · Unknown error
- `TDB_ERR_LOCKED` (-12) · Database is locked

## Complete Example

```lua
local tidesdb = require("tidesdb")

local db = tidesdb.TidesDB.open("./example_db", {
    num_flush_threads = 1,
    num_compaction_threads = 1,
    log_level = tidesdb.LogLevel.LOG_INFO,
    block_cache_size = 64 * 1024 * 1024,
    max_open_sstables = 256,
})

local cf_config = tidesdb.default_column_family_config()
cf_config.write_buffer_size = 64 * 1024 * 1024
cf_config.compression_algorithm = tidesdb.CompressionAlgorithm.LZ4_COMPRESSION
cf_config.enable_bloom_filter = true
cf_config.bloom_fpr = 0.01
cf_config.sync_mode = tidesdb.SyncMode.SYNC_INTERVAL
cf_config.sync_interval_us = 128000

db:create_column_family("users", cf_config)

local cf = db:get_column_family("users")

local txn = db:begin_txn()

txn:put(cf, "user:1", "Alice", -1)
txn:put(cf, "user:2", "Bob", -1)

local ttl = os.time() + 30  -- Expire in 30 seconds
txn:put(cf, "session:abc", "temp_data", ttl)

txn:commit()
txn:free()

local read_txn = db:begin_txn()

local value = read_txn:get(cf, "user:1")
print("user:1 = " .. value)

local iter = read_txn:new_iterator(cf)

print("\nAll entries:")
iter:seek_to_first()
while iter:valid() do
    local key = iter:key()
    local val = iter:value()
    print(string.format("  %s = %s", key, val))
    iter:next()
end
iter:free()

read_txn:free()

local stats = cf:get_stats()

print("\nColumn Family Statistics:")
print(string.format("  Number of Levels: %d", stats.num_levels))
print(string.format("  Memtable Size: %d bytes", stats.memtable_size))

db:drop_column_family("users")
db:close()
```

### Transaction Reset

Reset a committed or aborted transaction for reuse with a new isolation level. This avoids the overhead of freeing and reallocating transaction resources in hot loops.

```lua
local cf = db:get_column_family("my_cf")

local txn = db:begin_txn()

txn:put(cf, "key1", "value1", -1)
txn:commit()

txn:reset(tidesdb.IsolationLevel.READ_COMMITTED)

txn:put(cf, "key2", "value2", -1)
txn:commit()

txn:free()
```

**Behavior**
- The transaction must be committed or aborted before reset; resetting an active transaction raises an error
- Internal buffers are retained to avoid reallocation
- A fresh transaction ID and snapshot sequence are assigned based on the new isolation level
- The isolation level can be changed on each reset

**When to use**
- Batch processing · Reuse a single transaction across many commit cycles in a loop
- Connection pooling · Reset a transaction for a new request without reallocation
- High-throughput ingestion · Reduce allocation overhead in tight write loops

## Isolation Levels

TidesDB supports five MVCC isolation levels:

```lua
local txn = db:begin_txn_with_isolation(tidesdb.IsolationLevel.READ_COMMITTED)

txn:free()
```

**Available Isolation Levels**
- `READ_UNCOMMITTED` · Sees all data including uncommitted changes
- `READ_COMMITTED` · Sees only committed data (default)
- `REPEATABLE_READ` · Consistent snapshot, phantom reads possible
- `SNAPSHOT` · Write-write conflict detection
- `SERIALIZABLE` · Full read-write conflict detection (SSI)

## Savepoints

Savepoints allow partial rollback within a transaction:

```lua
local txn = db:begin_txn()

txn:put(cf, "key1", "value1", -1)

txn:savepoint("sp1")
txn:put(cf, "key2", "value2", -1)

txn:rollback_to_savepoint("sp1")

txn:commit()
txn:free()
```

**Savepoint API**
- `txn:savepoint(name)` · Create a savepoint
- `txn:rollback_to_savepoint(name)` · Rollback to savepoint
- `txn:release_savepoint(name)` · Release savepoint without rolling back

## Custom Comparators

TidesDB uses comparators to determine the sort order of keys. Once a comparator is set for a column family, it **cannot be changed** without corrupting data.

### Built-in Comparators

TidesDB provides six built-in comparators that are automatically registered:

- **`"memcmp"`** (default) · Binary byte-by-byte comparison
- **`"lexicographic"`** · Null-terminated string comparison (uses `strcmp`)
- **`"uint64"`** · Unsigned 64-bit integer comparison (8-byte keys)
- **`"int64"`** · Signed 64-bit integer comparison (8-byte keys)
- **`"reverse"`** · Reverse binary comparison (descending order)
- **`"case_insensitive"`** · Case-insensitive ASCII comparison

```lua
local cf_config = tidesdb.default_column_family_config()
cf_config.comparator_name = "reverse"  -- Use reverse ordering

db:create_column_family("sorted_cf", cf_config)
```

### Registering Custom Comparators

You can register custom comparators using FFI callbacks:

```lua
local ffi = require("ffi")

local my_compare = ffi.cast("tidesdb_comparator_fn", function(key1, key1_size, key2, key2_size, ctx)
    local s1 = ffi.string(key1, key1_size)
    local s2 = ffi.string(key2, key2_size)
    if s1 < s2 then return -1
    elseif s1 > s2 then return 1
    else return 0 end
end)

db:register_comparator("my_comparator", my_compare, nil, nil)

local cf_config = tidesdb.default_column_family_config()
cf_config.comparator_name = "my_comparator"
db:create_column_family("custom_cf", cf_config)
```

### Retrieving Comparators

```lua
local fn, ctx = db:get_comparator("memcmp")
```

## Testing

```bash
# Run all tests with LuaJIT
cd tests
luajit test_tidesdb.lua

# Run with standard Lua (requires LuaFFI)
lua test_tidesdb.lua
```

## API Reference

### Module Functions

| Function | Description |
|----------|-------------|
| `tidesdb.TidesDB.open(path, options)` | Open a database |
| `tidesdb.default_config()` | Get default database configuration |
| `tidesdb.default_column_family_config()` | Get default column family configuration |
| `tidesdb.load_config_from_ini(file, section)` | Load config from INI file |
| `tidesdb.save_config_to_ini(file, section, config)` | Save config to INI file |

### TidesDB Class

| Method | Description |
|--------|-------------|
| `db:close()` | Close the database |
| `db:create_column_family(name, config)` | Create a column family |
| `db:drop_column_family(name)` | Drop a column family |
| `db:delete_column_family(cf)` | Drop a column family by handle (skips name lookup) |
| `db:rename_column_family(old_name, new_name)` | Rename a column family |
| `db:clone_column_family(source_name, dest_name)` | Clone a column family |
| `db:get_column_family(name)` | Get a column family handle |
| `db:list_column_families()` | List all column family names |
| `db:begin_txn()` | Begin a transaction |
| `db:begin_txn_with_isolation(level)` | Begin transaction with isolation level |
| `db:get_cache_stats()` | Get block cache statistics |
| `db:get_db_stats()` | Get database-level aggregate statistics |
| `db:purge()` | Synchronous flush and compaction for all column families |
| `db:backup(dir)` | Create database backup |
| `db:checkpoint(dir)` | Create lightweight database checkpoint using hard links |
| `db:register_comparator(name, fn, ctx_str, ctx)` | Register custom comparator |
| `db:get_comparator(name)` | Get registered comparator |

### ColumnFamily Class

| Method | Description |
|--------|-------------|
| `cf:compact()` | Trigger manual compaction |
| `cf:flush_memtable()` | Trigger manual memtable flush |
| `cf:is_flushing()` | Check if flush is in progress |
| `cf:is_compacting()` | Check if compaction is in progress |
| `cf:get_stats()` | Get column family statistics |
| `cf:range_cost(key_a, key_b)` | Estimate range iteration cost between two keys |
| `cf:sync_wal()` | Force immediate fsync of the active WAL |
| `cf:purge()` | Synchronous flush and aggressive compaction |
| `cf:set_commit_hook(fn, ctx)` | Set commit hook callback for change data capture |
| `cf:clear_commit_hook()` | Clear (disable) the commit hook |
| `cf:update_runtime_config(config, persist)` | Update runtime configuration |

### Transaction Class

| Method | Description |
|--------|-------------|
| `txn:put(cf, key, value, ttl)` | Put a key-value pair |
| `txn:get(cf, key)` | Get a value by key |
| `txn:delete(cf, key)` | Delete a key |
| `txn:commit()` | Commit the transaction |
| `txn:rollback()` | Rollback the transaction |
| `txn:reset(isolation)` | Reset transaction for reuse with new isolation level |
| `txn:savepoint(name)` | Create a savepoint |
| `txn:rollback_to_savepoint(name)` | Rollback to savepoint |
| `txn:release_savepoint(name)` | Release a savepoint |
| `txn:new_iterator(cf)` | Create an iterator |
| `txn:free()` | Free transaction resources |

### Iterator Class

| Method | Description |
|--------|-------------|
| `iter:seek_to_first()` | Seek to first entry |
| `iter:seek_to_last()` | Seek to last entry |
| `iter:seek(key)` | Seek to key (or next key >= target) |
| `iter:seek_for_prev(key)` | Seek to key (or prev key <= target) |
| `iter:valid()` | Check if iterator is valid |
| `iter:next()` | Move to next entry |
| `iter:prev()` | Move to previous entry |
| `iter:key()` | Get current key |
| `iter:value()` | Get current value |
| `iter:free()` | Free iterator resources |

### Constants

**Compression Algorithms** (`tidesdb.CompressionAlgorithm`)
- `NO_COMPRESSION` (0)
- `SNAPPY_COMPRESSION` (1)
- `LZ4_COMPRESSION` (2) -- default
- `ZSTD_COMPRESSION` (3)
- `LZ4_FAST_COMPRESSION` (4)

**Sync Modes** (`tidesdb.SyncMode`)
- `SYNC_NONE` (0)
- `SYNC_FULL` (1)
- `SYNC_INTERVAL` (2)

**Log Levels** (`tidesdb.LogLevel`)
- `LOG_DEBUG` (0)
- `LOG_INFO` (1)
- `LOG_WARN` (2)
- `LOG_ERROR` (3)
- `LOG_FATAL` (4)
- `LOG_NONE` (99)

**Isolation Levels** (`tidesdb.IsolationLevel`)
- `READ_UNCOMMITTED` (0)
- `READ_COMMITTED` (1) -- default
- `REPEATABLE_READ` (2)
- `SNAPSHOT` (3)
- `SERIALIZABLE` (4)

**Error Codes**
- `TDB_SUCCESS` (0)
- `TDB_ERR_MEMORY` (-1)
- `TDB_ERR_INVALID_ARGS` (-2)
- `TDB_ERR_NOT_FOUND` (-3)
- `TDB_ERR_IO` (-4)
- `TDB_ERR_CORRUPTION` (-5)
- `TDB_ERR_EXISTS` (-6)
- `TDB_ERR_CONFLICT` (-7)
- `TDB_ERR_TOO_LARGE` (-8)
- `TDB_ERR_MEMORY_LIMIT` (-9)
- `TDB_ERR_INVALID_DB` (-10)
- `TDB_ERR_UNKNOWN` (-11)
- `TDB_ERR_LOCKED` (-12)

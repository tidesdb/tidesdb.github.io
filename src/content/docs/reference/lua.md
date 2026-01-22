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
})

print("Database opened successfully")

db:close()
```

### Creating and Dropping Column Families

Column families are isolated key-value stores with independent configuration.

```lua
local cf_config = tidesdb.default_column_family_config()
db:create_column_family("my_cf", cf_config)

-- Create with custom configuration based on defaults
local cf_config = tidesdb.default_column_family_config()

-- You can modify the configuration as needed
cf_config.write_buffer_size = 128 * 1024 * 1024
cf_config.level_size_ratio = 10
cf_config.min_levels = 5
cf_config.compression_algorithm = tidesdb.CompressionAlgorithm.LZ4_COMPRESSION
cf_config.enable_bloom_filter = true
cf_config.bloom_fpr = 0.01
cf_config.enable_block_indexes = true
cf_config.sync_mode = tidesdb.SyncMode.SYNC_INTERVAL
cf_config.sync_interval_us = 128000
cf_config.default_isolation_level = tidesdb.IsolationLevel.READ_COMMITTED

db:create_column_family("my_cf", cf_config)

db:drop_column_family("my_cf")
```

### CRUD Operations

All operations in TidesDB are performed through transactions for ACID guarantees.

#### Writing Data

```lua
local cf = db:get_column_family("my_cf")

local txn = db:begin_txn()

-- Put a key-value pair (TTL -1 means no expiration)
txn:put(cf, "key", "value", -1)

txn:commit()
txn:free()
```

#### Writing with TTL

```lua
local cf = db:get_column_family("my_cf")

local txn = db:begin_txn()

-- Set expiration time (Unix timestamp)
local ttl = os.time() + 10  -- Expire in 10 seconds

txn:put(cf, "temp_key", "temp_value", ttl)

txn:commit()
txn:free()
```

**TTL Examples**
```lua
-- No expiration
local ttl = -1

-- Expire in 5 minutes
local ttl = os.time() + 5 * 60

-- Expire in 1 hour
local ttl = os.time() + 60 * 60

-- Expire at specific time
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

-- Multiple operations in one transaction, across column families as well
local ok, err = pcall(function()
    txn:put(cf, "key1", "value1", -1)
    txn:put(cf, "key2", "value2", -1)
    txn:delete(cf, "old_key")
end)

if not ok then
    txn:rollback()
    error(err)
end

-- Commit atomically -- all or nothing
txn:commit()
txn:free()
```

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

### Getting Column Family Statistics

Retrieve detailed statistics about a column family.

```lua
local cf = db:get_column_family("my_cf")

local stats = cf:get_stats()

print(string.format("Number of Levels: %d", stats.num_levels))
print(string.format("Memtable Size: %d bytes", stats.memtable_size))

if stats.config then
    print(string.format("Write Buffer Size: %d", stats.config.write_buffer_size))
    print(string.format("Compression: %d", stats.config.compression_algorithm))
    print(string.format("Bloom Filter: %s", tostring(stats.config.enable_bloom_filter)))
    print(string.format("Sync Mode: %d", stats.config.sync_mode))
end
```

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

-- Manually trigger compaction (queues compaction from L1+)
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

-- Manually trigger memtable flush (queues memtable for sorted run to disk (L1))
local ok, err = pcall(function()
    cf:flush_memtable()
end)
if not ok then
    print("Flush note: " .. tostring(err))
end
```

### Sync Modes

Control the durability vs performance tradeoff.

```lua
local cf_config = tidesdb.default_column_family_config()

-- SYNC_NONE -- Fastest, least durable (OS handles flushing on sorted runs and compaction to sync after completion)
cf_config.sync_mode = tidesdb.SyncMode.SYNC_NONE

-- SYNC_INTERVAL -- Balanced (periodic background syncing)
cf_config.sync_mode = tidesdb.SyncMode.SYNC_INTERVAL
cf_config.sync_interval_us = 128000  -- Sync every 128ms

-- SYNC_FULL -- Most durable (fsync on every write)
cf_config.sync_mode = tidesdb.SyncMode.SYNC_FULL

db:create_column_family("my_cf", cf_config)
```

### Compression Algorithms

TidesDB supports multiple compression algorithms:

```lua
local cf_config = tidesdb.default_column_family_config()

cf_config.compression_algorithm = tidesdb.CompressionAlgorithm.NO_COMPRESSION
cf_config.compression_algorithm = tidesdb.CompressionAlgorithm.LZ4_COMPRESSION
cf_config.compression_algorithm = tidesdb.CompressionAlgorithm.LZ4_FAST_COMPRESSION
cf_config.compression_algorithm = tidesdb.CompressionAlgorithm.ZSTD_COMPRESSION

db:create_column_family("my_cf", cf_config)
```

## Error Handling

```lua
local cf = db:get_column_family("my_cf")

local txn = db:begin_txn()

local ok, err = pcall(function()
    txn:put(cf, "key", "value", -1)
end)

if not ok then
    -- Errors include context and error codes
    print("Error: " .. tostring(err))
    
    -- Example error message:
    -- "TidesDBError: failed to put key-value pair: memory allocation failed (code: -1)"
    
    txn:rollback()
    return
end

txn:commit()
txn:free()
```

**Error Codes**
- `TDB_SUCCESS` (0) -- Operation successful
- `TDB_ERR_MEMORY` (-1) -- Memory allocation failed
- `TDB_ERR_INVALID_ARGS` (-2) -- Invalid arguments
- `TDB_ERR_NOT_FOUND` (-3) -- Key not found
- `TDB_ERR_IO` (-4) -- I/O error
- `TDB_ERR_CORRUPTION` (-5) -- Data corruption
- `TDB_ERR_EXISTS` (-6) -- Resource already exists
- `TDB_ERR_CONFLICT` (-7) -- Transaction conflict
- `TDB_ERR_TOO_LARGE` (-8) -- Key or value too large
- `TDB_ERR_MEMORY_LIMIT` (-9) -- Memory limit exceeded
- `TDB_ERR_INVALID_DB` (-10) -- Invalid database handle
- `TDB_ERR_UNKNOWN` (-11) -- Unknown error
- `TDB_ERR_LOCKED` (-12) -- Database is locked

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

## Isolation Levels

TidesDB supports five MVCC isolation levels:

```lua
local txn = db:begin_txn_with_isolation(tidesdb.IsolationLevel.READ_COMMITTED)

txn:free()
```

**Available Isolation Levels**
- `READ_UNCOMMITTED` -- Sees all data including uncommitted changes
- `READ_COMMITTED` -- Sees only committed data (default)
- `REPEATABLE_READ` -- Consistent snapshot, phantom reads possible
- `SNAPSHOT` -- Write-write conflict detection
- `SERIALIZABLE` -- Full read-write conflict detection (SSI)

## Savepoints

Savepoints allow partial rollback within a transaction:

```lua
local txn = db:begin_txn()

txn:put(cf, "key1", "value1", -1)

txn:savepoint("sp1")
txn:put(cf, "key2", "value2", -1)

-- Rollback to savepoint -- key2 is discarded, key1 remains
txn:rollback_to_savepoint("sp1")

-- Commit -- only key1 is written
txn:commit()
txn:free()
```

## Testing

```bash
# Run all tests with LuaJIT
cd tests
luajit test_tidesdb.lua

# Run with standard Lua (requires LuaFFI)
lua test_tidesdb.lua
```

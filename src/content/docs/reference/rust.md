---
title: TidesDB Rust API Reference
description: Rust API reference for TidesDB
---

<div class="no-print">

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/rust.md).

<hr/>

</div>

## Getting Started

### Prerequisites

You need a C compiler and CMake installed, along with compression libraries. The crate will automatically download and build TidesDB from source if the C library is not already installed.

**Debian/Ubuntu**
```bash
sudo apt install build-essential cmake libzstd-dev liblz4-dev libsnappy-dev
```

**macOS**
```bash
brew install cmake zstd lz4 snappy
```

**Windows**
```bash
vcpkg install zstd:x64-windows lz4:x64-windows snappy:x64-windows
```

For S3 object store support, you also need `libcurl` and `openssl` (see [Object Store Support](#object-store-support) below).

### Installing from crates.io

The easiest way to add TidesDB to your project is via [crates.io](https://crates.io/crates/tidesdb):

```toml
[dependencies]
tidesdb = "0.6"
```

Or using `cargo add`:

```bash
cargo add tidesdb
```

### How the Build System Works

The build script (`build.rs`) handles linking automatically:

1. pkg-config check · It first tries to find TidesDB already installed on your system via `pkg-config` with an exact version match. If found, it links against the system library and no further steps are needed.

2. Auto-build from source · If the system library is not found, the build script automatically downloads the matching TidesDB C library source from GitHub, builds it with CMake as a static library, and links it into your project.

3. Compression libraries · TidesDB depends on zstd, lz4, and snappy. The build script tries to find these via `pkg-config` and falls back to linking by name if not found.

### Version Selection

Each crate release defaults to a specific TidesDB C library version. You can select a different version using Cargo features:

```toml
[dependencies]
# Uses the default version (currently v9.0.6)
tidesdb = "0.6"

# Pin to a specific TidesDB version
tidesdb = { version = "0.6", default-features = false, features = ["v9_0_5"] }
```

Only one version feature can be enabled at a time. The version feature (e.g., `v9_0_6`) maps directly to the TidesDB C library release tag (e.g., `v9.0.6`).

### Object Store Support

To enable S3 object store support, enable the `objectstore` feature:

```toml
[dependencies]
tidesdb = { version = "0.6", features = ["objectstore"] }
```

This requires additional dependencies:

- Debian/Ubuntu · `sudo apt install libcurl4-openssl-dev libssl-dev`
- macOS · `brew install curl openssl`
- Windows · `vcpkg install curl:x64-windows openssl:x64-windows` (requires tidesdb >= v9.0.6)

### Building from GitHub

To build the Rust bindings directly from the GitHub repository:

```bash
git clone https://github.com/tidesdb/tidesdb-rs.git
cd tidesdb-rs
cargo build --release
cargo test -- --test-threads=1
```

**Using directly from GitHub in your Cargo.toml**

```toml
[dependencies]
tidesdb = { git = "https://github.com/tidesdb/tidesdb-rs.git" }
```

**Using pkg-config**
```bash
# If TidesDB was installed with pkg-config support
export PKG_CONFIG_PATH="/custom/path/lib/pkgconfig:$PKG_CONFIG_PATH"
cargo build
```

**Custom prefix installation**
```bash
# Install TidesDB to custom location
cd tidesdb
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/opt/tidesdb
cmake --build build
sudo cmake --install build

# Configure environment
export LIBRARY_PATH="/opt/tidesdb/lib:$LIBRARY_PATH"
export LD_LIBRARY_PATH="/opt/tidesdb/lib:$LD_LIBRARY_PATH"  # Linux
# or
export DYLD_LIBRARY_PATH="/opt/tidesdb/lib:$DYLD_LIBRARY_PATH"  # macOS

cargo build
```

## Initialization

TidesDB supports optional custom memory allocators for integration with custom memory managers (e.g., jemalloc, mimalloc).

### `init`

Initializes TidesDB with the system allocator. Must be called exactly once before any other TidesDB function when using the explicit initialization path.

```rust
use tidesdb;

fn main() -> tidesdb::Result<()> {
    tidesdb::init()?;

    // ... use TidesDB ...

    tidesdb::finalize();
    Ok(())
}
```

### `init_with_allocator`

Initializes TidesDB with custom C-level memory allocator functions. This is an `unsafe` function for advanced use cases.

```rust
use tidesdb;

// Example with custom allocator function pointers
unsafe {
    tidesdb::init_with_allocator(
        Some(my_malloc),
        Some(my_calloc),
        Some(my_realloc),
        Some(my_free),
    )?;
}
```

### `finalize`

Finalizes TidesDB and resets the allocator. Should be called after all TidesDB operations are complete (all databases closed). After calling this, `init()` or `init_with_allocator()` can be called again.

```rust
tidesdb::finalize();
```

:::note[Auto-initialization]
If `init()` is not called, TidesDB will auto-initialize with the system allocator on the first call to `TidesDB::open()`.
:::

## Usage

### Opening and Closing a Database

```rust
use tidesdb::{TidesDB, Config, LogLevel, SyncMode};

fn main() -> tidesdb::Result<()> {
    let config = Config::new("./mydb")
        .num_flush_threads(2)
        .num_compaction_threads(2)
        .log_level(LogLevel::Info)
        .block_cache_size(64 * 1024 * 1024)
        .max_open_sstables(256)
        .max_memory_usage(0)                   // 0 = auto (50% of system RAM)
        .log_to_file(false)                    // Write logs to file instead of stderr
        .log_truncation_at(24 * 1024 * 1024)   // Log file truncation threshold (24MB)
        .unified_memtable(false)               // Enable unified memtable mode (default: false)
        .unified_memtable_write_buffer_size(0) // 0 = auto
        .unified_memtable_sync_mode(SyncMode::None);

    let db = TidesDB::open(config)?;

    println!("Database opened successfully");

    Ok(())
}
```

### Creating and Dropping Column Families

Column families are isolated key-value stores with independent configuration.

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig, CompressionAlgorithm, SyncMode, IsolationLevel};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;

    let cf_config = ColumnFamilyConfig::default();
    db.create_column_family("my_cf", cf_config)?;

    let cf_config = ColumnFamilyConfig::new()
        .write_buffer_size(128 * 1024 * 1024)
        .level_size_ratio(10)
        .min_levels(5)
        .compression_algorithm(CompressionAlgorithm::Lz4)
        .enable_bloom_filter(true)
        .bloom_fpr(0.01)
        .enable_block_indexes(true)
        .sync_mode(SyncMode::Interval)
        .sync_interval_us(128000)
        .default_isolation_level(IsolationLevel::ReadCommitted)
        .use_btree(false); // Use block-based format (default)

    db.create_column_family("custom_cf", cf_config)?;

    db.drop_column_family("my_cf")?;

    Ok(())
}
```

#### Dropping by Pointer

When you already hold a `ColumnFamily`, you can skip the name lookup:

```rust
let cf = db.get_column_family("my_cf")?;
db.delete_column_family(cf)?; // cf is consumed and cannot be used after this
```

:::tip[Which to use]
- `drop_column_family(name)` · Convenient when you only have the name
- `delete_column_family(cf)` · Faster when you already hold a `ColumnFamily`, avoids a redundant linear scan
:::

### CRUD Operations

All operations in TidesDB are performed through transactions for ACID guarantees.

#### Writing Data

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    let mut txn = db.begin_transaction()?;

    txn.put(&cf, b"key", b"value", -1)?;

    txn.commit()?;

    Ok(())
}
```

#### Writing with TTL

```rust
use std::time::{SystemTime, UNIX_EPOCH};
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    let mut txn = db.begin_transaction()?;

    let ttl = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64 + 10; // Expires in 10 seconds

    txn.put(&cf, b"temp_key", b"temp_value", ttl)?;

    txn.commit()?;

    Ok(())
}
```

**TTL Examples**
```rust
use std::time::{SystemTime, UNIX_EPOCH, Duration};

let ttl: i64 = -1;

let ttl = SystemTime::now()
    .duration_since(UNIX_EPOCH)
    .unwrap()
    .as_secs() as i64 + 5 * 60;

let ttl = SystemTime::now()
    .duration_since(UNIX_EPOCH)
    .unwrap()
    .as_secs() as i64 + 60 * 60;

let ttl: i64 = 1798761599;
```

#### Reading Data

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    let txn = db.begin_transaction()?;

    let value = txn.get(&cf, b"key")?;
    println!("Value: {:?}", String::from_utf8_lossy(&value));

    Ok(())
}
```

#### Deleting Data

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    let mut txn = db.begin_transaction()?;
    txn.delete(&cf, b"key")?;
    txn.commit()?;

    Ok(())
}
```

#### Multi-Operation Transactions

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    let mut txn = db.begin_transaction()?;

    txn.put(&cf, b"key1", b"value1", -1)?;
    txn.put(&cf, b"key2", b"value2", -1)?;
    txn.delete(&cf, b"old_key")?;

    txn.commit()?;

    Ok(())
}
```

#### Transaction Rollback

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    let mut txn = db.begin_transaction()?;
    txn.put(&cf, b"key", b"value", -1)?;

    txn.rollback()?;

    Ok(())
}
```

### Multi-Column-Family Transactions

TidesDB supports atomic transactions across multiple column families with true all-or-nothing semantics.

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("users", ColumnFamilyConfig::default())?;
    db.create_column_family("orders", ColumnFamilyConfig::default())?;

    let users_cf = db.get_column_family("users")?;
    let orders_cf = db.get_column_family("orders")?;

    let mut txn = db.begin_transaction()?;

    txn.put(&users_cf, b"user:1000", b"John Doe", -1)?;
    txn.put(&orders_cf, b"order:5000", b"user:1000|product:A", -1)?;

    // Commit atomically -- all or nothing
    txn.commit()?;

    Ok(())
}
```

**Multi-CF guarantees**
- Either all CFs commit or none do (atomic)
- Automatically detected when operations span multiple CFs
- Uses global sequence numbers for atomic ordering
- Each CF's WAL receives operations with the same commit sequence number

### Transaction Reset

`Transaction::reset` resets a committed or aborted transaction for reuse with a new isolation level. This avoids the overhead of freeing and reallocating transaction resources in hot loops.

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig, IsolationLevel};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    let mut txn = db.begin_transaction()?;

    txn.put(&cf, b"key1", b"value1", -1)?;
    txn.commit()?;

    txn.reset(IsolationLevel::ReadCommitted)?;

    txn.put(&cf, b"key2", b"value2", -1)?;
    txn.commit()?;

    Ok(())
}
```

**Behavior**
- The transaction must be committed or aborted before reset; resetting an active transaction returns an error
- Internal buffers are retained to avoid reallocation
- A fresh transaction ID and snapshot sequence are assigned based on the new isolation level
- The isolation level can be changed on each reset (e.g., `ReadCommitted` -> `RepeatableRead`)

**When to use**
- Batch processing · Reuse a single transaction across many commit cycles in a loop
- Connection pooling · Reset a transaction for a new request without reallocation
- High-throughput ingestion · Reduce allocation overhead in tight write loops

:::tip[Reset vs Drop + Begin]
For a single transaction, `reset` is functionally equivalent to dropping the transaction and calling `begin_transaction_with_isolation`. The difference is performance, reset retains allocated buffers and avoids repeated allocation overhead. This matters most in loops that commit and restart thousands of transactions.
:::

### Iterating Over Data

Iterators provide efficient bidirectional traversal over key-value pairs.

#### Forward Iteration

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    let txn = db.begin_transaction()?;
    let mut iter = txn.new_iterator(&cf)?;

    iter.seek_to_first()?;

    while iter.is_valid() {
        let key = iter.key()?;
        let value = iter.value()?;

        println!("Key: {:?}, Value: {:?}",
            String::from_utf8_lossy(&key),
            String::from_utf8_lossy(&value));

        iter.next()?;
    }

    Ok(())
}
```

#### Backward Iteration

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    let txn = db.begin_transaction()?;
    let mut iter = txn.new_iterator(&cf)?;

    iter.seek_to_last()?;

    while iter.is_valid() {
        let key = iter.key()?;
        let value = iter.value()?;

        println!("Key: {:?}, Value: {:?}",
            String::from_utf8_lossy(&key),
            String::from_utf8_lossy(&value));

        iter.prev()?;
    }

    Ok(())
}
```

#### Seek Operations

**`seek(key)`** positions the iterator at the first key >= target key:

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    let txn = db.begin_transaction()?;
    let mut iter = txn.new_iterator(&cf)?;

    // Seek to prefix and iterate all matching keys
    iter.seek(b"user:")?;

    while iter.is_valid() {
        let key = iter.key()?;

        if !key.starts_with(b"user:") {
            break;
        }

        let value = iter.value()?;
        println!("Key: {:?}, Value: {:?}",
            String::from_utf8_lossy(&key),
            String::from_utf8_lossy(&value));

        iter.next()?;
    }

    Ok(())
}
```

**`seek_for_prev(key)`** positions the iterator at the last key <= target key:

```rust
let txn = db.begin_transaction()?;
let mut iter = txn.new_iterator(&cf)?;

// Seek for reverse iteration from a specific key
iter.seek_for_prev(b"user:2000")?;

while iter.is_valid() {
    let key = iter.key()?;
    let value = iter.value()?;
    println!("Key: {:?}, Value: {:?}",
        String::from_utf8_lossy(&key),
        String::from_utf8_lossy(&value));
    iter.prev()?;
}
```

#### Combined Key-Value Retrieval

**`key_value()`** retrieves both key and value in a single FFI call, which is more efficient than calling `key()` and `value()` separately:

```rust
let txn = db.begin_transaction()?;
let mut iter = txn.new_iterator(&cf)?;
iter.seek_to_first()?;

while iter.is_valid() {
    let (key, value) = iter.key_value()?;
    println!("Key: {:?}, Value: {:?}",
        String::from_utf8_lossy(&key),
        String::from_utf8_lossy(&value));
    iter.next()?;
}
```

### Getting Column Family Statistics

Retrieve detailed statistics about a column family.

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    let stats = cf.get_stats()?;

    println!("Number of Levels: {}", stats.num_levels);
    println!("Memtable Size: {} bytes", stats.memtable_size);
    println!("Total Keys: {}", stats.total_keys);
    println!("Total Data Size: {} bytes", stats.total_data_size);
    println!("Average Key Size: {:.2} bytes", stats.avg_key_size);
    println!("Average Value Size: {:.2} bytes", stats.avg_value_size);
    println!("Read Amplification: {:.2}", stats.read_amp);
    println!("Hit Rate: {:.1}%", stats.hit_rate * 100.0);

    for (i, (size, count)) in stats.level_sizes.iter()
        .zip(stats.level_num_sstables.iter())
        .enumerate()
    {
        println!("Level {}: {} SSTables, {} bytes", i + 1, count, size);
    }

    // B+tree stats (only populated if use_btree=true)
    if stats.use_btree {
        println!("B+tree Total Nodes: {}", stats.btree_total_nodes);
        println!("B+tree Max Height: {}", stats.btree_max_height);
        println!("B+tree Avg Height: {:.2}", stats.btree_avg_height);
    }

    Ok(())
}
```

**Statistics Fields**

| Field | Type | Description |
|-------|------|-------------|
| `num_levels` | `i32` | Number of LSM levels |
| `memtable_size` | `usize` | Current memtable size in bytes |
| `level_sizes` | `Vec<usize>` | Array of per-level total sizes |
| `level_num_sstables` | `Vec<i32>` | Array of per-level SSTable counts |
| `level_key_counts` | `Vec<u64>` | Array of per-level key counts |
| `config` | `Option<ColumnFamilyConfig>` | Column family configuration |
| `total_keys` | `u64` | Total keys across memtable and all SSTables |
| `total_data_size` | `u64` | Total data size (klog + vlog) in bytes |
| `avg_key_size` | `f64` | Estimated average key size in bytes |
| `avg_value_size` | `f64` | Estimated average value size in bytes |
| `read_amp` | `f64` | Read amplification factor (point lookup cost) |
| `hit_rate` | `f64` | Block cache hit rate (0.0 to 1.0) |
| `use_btree` | `bool` | Whether column family uses B+tree KLog format |
| `btree_total_nodes` | `u64` | Total B+tree nodes across all SSTables |
| `btree_max_height` | `u32` | Maximum tree height across all SSTables |
| `btree_avg_height` | `f64` | Average tree height across all SSTables |

### Getting Cache Statistics

Retrieve statistics about the global block cache.

```rust
use tidesdb::{TidesDB, Config};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;

    let stats = db.get_cache_stats()?;

    if stats.enabled {
        println!("Cache enabled: yes");
        println!("Total entries: {}", stats.total_entries);
        println!("Total bytes: {:.2} MB", stats.total_bytes as f64 / (1024.0 * 1024.0));
        println!("Hits: {}", stats.hits);
        println!("Misses: {}", stats.misses);
        println!("Hit rate: {:.1}%", stats.hit_rate * 100.0);
        println!("Partitions: {}", stats.num_partitions);
    } else {
        println!("Cache enabled: no");
    }

    Ok(())
}
```

### Getting Database-Level Statistics

Get aggregate statistics across the entire database instance.

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let stats = db.get_db_stats()?;

    println!("Column families: {}", stats.num_column_families);
    println!("Total memory: {} bytes", stats.total_memory);
    println!("Resolved memory limit: {} bytes", stats.resolved_memory_limit);
    println!("Memory pressure level: {}", stats.memory_pressure_level);
    println!("Global sequence: {}", stats.global_seq);
    println!("Flush queue: {} pending", stats.flush_queue_size);
    println!("Compaction queue: {} pending", stats.compaction_queue_size);
    println!("Total SSTables: {}", stats.total_sstable_count);
    println!("Total data size: {} bytes", stats.total_data_size_bytes);
    println!("Open SSTable handles: {}", stats.num_open_sstables);
    println!("In-flight txn memory: {} bytes", stats.txn_memory_bytes);
    println!("Immutable memtables: {}", stats.total_immutable_count);
    println!("Memtable bytes: {}", stats.total_memtable_bytes);

    Ok(())
}
```

**Database statistics include**

| Field | Type | Description |
|-------|------|-------------|
| `num_column_families` | `i32` | Number of column families |
| `total_memory` | `u64` | System total memory |
| `available_memory` | `u64` | System available memory at open time |
| `resolved_memory_limit` | `usize` | Resolved memory limit (auto or configured) |
| `memory_pressure_level` | `i32` | Current memory pressure (0=normal, 1=elevated, 2=high, 3=critical) |
| `flush_pending_count` | `i32` | Number of pending flush operations (queued + in-flight) |
| `total_memtable_bytes` | `i64` | Total bytes in active memtables across all CFs |
| `total_immutable_count` | `i32` | Total immutable memtables across all CFs |
| `total_sstable_count` | `i32` | Total SSTables across all CFs and levels |
| `total_data_size_bytes` | `u64` | Total data size (klog + vlog) across all CFs |
| `num_open_sstables` | `i32` | Number of currently open SSTable file handles |
| `global_seq` | `u64` | Current global sequence number |
| `txn_memory_bytes` | `i64` | Bytes held by in-flight transactions |
| `compaction_queue_size` | `usize` | Number of pending compaction tasks |
| `flush_queue_size` | `usize` | Number of pending flush tasks in queue |
| `unified_memtable_enabled` | `bool` | Whether unified memtable mode is active |
| `unified_memtable_bytes` | `i64` | Bytes in unified active memtable |
| `unified_immutable_count` | `i32` | Number of unified immutable memtables |
| `unified_is_flushing` | `bool` | Whether unified memtable is currently flushing/rotating |
| `unified_next_cf_index` | `u32` | Next CF index to be assigned in unified mode |
| `unified_wal_generation` | `u64` | Current unified WAL generation counter |
| `object_store_enabled` | `bool` | Whether object store mode is active |
| `object_store_connector` | `String` | Connector name ("s3", "gcs", "fs", etc.) |
| `local_cache_bytes_used` | `usize` | Current local file cache usage in bytes |
| `local_cache_bytes_max` | `usize` | Configured maximum local cache size in bytes |
| `local_cache_num_files` | `i32` | Number of files tracked in local cache |
| `last_uploaded_generation` | `u64` | Highest WAL generation confirmed uploaded |
| `upload_queue_depth` | `usize` | Number of pending upload jobs in the queue |
| `total_uploads` | `u64` | Lifetime count of objects uploaded to object store |
| `total_upload_failures` | `u64` | Lifetime count of permanently failed uploads |
| `replica_mode` | `bool` | Whether running in read-only replica mode |

:::note[Stack Allocated]
Unlike `ColumnFamily::get_stats` (which heap-allocates), `get_db_stats` fills a struct on the stack. No manual free is needed.
:::

### Range Cost Estimation

Estimate the computational cost of iterating between two keys in a column family. The returned value is an opaque double - meaningful only for comparison with other `range_cost` results. It uses only in-memory metadata and performs no disk I/O.

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    let cost_a = cf.range_cost(b"user:0000", b"user:0999")?;
    let cost_b = cf.range_cost(b"user:1000", b"user:1099")?;

    if cost_a < cost_b {
        println!("Range A is cheaper to iterate");
    }

    Ok(())
}
```

**Behavior**
- Key order does not matter - the function normalizes the range so `key_a > key_b` produces the same result as `key_b > key_a`
- A cost of 0.0 means no overlapping SSTables or memtable entries were found for the range
- With block indexes enabled, uses O(log B) binary search per overlapping SSTable
- Without block indexes, falls back to byte-level key interpolation
- B+tree SSTables use key interpolation against tree node counts plus tree height as seek cost
- Compressed SSTables receive a 1.5× weight multiplier for decompression overhead

**Use cases**
- Query planning · Compare candidate key ranges to find the cheapest one to scan
- Load balancing · Distribute range scan work across threads by estimating per-range cost
- Adaptive prefetching · Decide how aggressively to prefetch based on range size
- Monitoring · Track how data distribution changes across key ranges over time

:::note[Cost Values]
The returned cost is not an absolute measure (it does not represent milliseconds, bytes, or entry counts). It is a relative scalar - only meaningful when compared with other `range_cost` results.
:::

### Listing Column Families

```rust
use tidesdb::{TidesDB, Config};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;

    let cf_list = db.list_column_families()?;

    println!("Available column families:");
    for name in cf_list {
        println!("  - {}", name);
    }

    Ok(())
}
```

### Renaming Column Families

Atomically rename a column family and its underlying directory:

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("old_name", ColumnFamilyConfig::default())?;

    // Rename column family (waits for flush/compaction to complete)
    db.rename_column_family("old_name", "new_name")?;

    // Access with new name
    let cf = db.get_column_family("new_name")?;

    Ok(())
}
```

### Cloning Column Families

Create a complete copy of an existing column family with a new name. The clone contains all the data from the source at the time of cloning.

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("source_cf", ColumnFamilyConfig::default())?;

    // Insert some data into source
    let cf = db.get_column_family("source_cf")?;
    let mut txn = db.begin_transaction()?;
    txn.put(&cf, b"key1", b"value1", -1)?;
    txn.put(&cf, b"key2", b"value2", -1)?;
    txn.commit()?;

    // Clone the column family
    db.clone_column_family("source_cf", "cloned_cf")?;

    // Both column families now exist independently
    let cloned_cf = db.get_column_family("cloned_cf")?;
    let txn = db.begin_transaction()?;
    let value = txn.get(&cloned_cf, b"key1")?;
    println!("Cloned value: {:?}", String::from_utf8_lossy(&value));

    Ok(())
}
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

**Return values**
- `Ok(())` · Clone completed successfully
- `ErrorCode::NotFound` · Source column family doesn't exist
- `ErrorCode::Exists` · Destination column family already exists
- `ErrorCode::InvalidArgs` · Invalid arguments (same source/destination name)
- `ErrorCode::Io` · Failed to copy files or create directory

### Compaction

#### Manual Compaction

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    // Manually trigger compaction (queues compaction from L1+)
    cf.compact()?;

    Ok(())
}
```

#### Manual Memtable Flush

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    // Manually trigger memtable flush (Queues sorted run for L1)
    cf.flush_memtable()?;

    Ok(())
}
```

#### Checking Flush/Compaction Status

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    // Check if operations are in progress
    if cf.is_flushing() {
        println!("Flush operation in progress");
    }

    if cf.is_compacting() {
        println!("Compaction operation in progress");
    }

    Ok(())
}
```

#### Purge Column Family

`purge` forces a synchronous flush and aggressive compaction for a single column family. Unlike `flush_memtable` and `compact` (which are non-blocking), purge blocks until all flush and compaction I/O is complete.

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    // Force synchronous flush + compaction
    cf.purge()?;
    // All data is now flushed to SSTables and compacted

    Ok(())
}
```

**Behavior**
1. Waits for any in-progress flush to complete
2. Force-flushes the active memtable (even if below threshold)
3. Waits for flush I/O to fully complete
4. Waits for any in-progress compaction to complete
5. Triggers synchronous compaction inline (bypasses the compaction queue)
6. Waits for any queued compaction to drain

**When to use**
- Before backup or checkpoint -- ensure all data is on disk and compacted
- After bulk deletes -- reclaim space immediately by compacting away tombstones
- Manual maintenance -- force a clean state during a maintenance window
- Pre-shutdown -- ensure all pending work is complete before closing

#### Purge Database

`purge` on the database forces a synchronous flush and aggressive compaction for **all** column families, then drains both the global flush and compaction queues.

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("cf_a", ColumnFamilyConfig::default())?;
    db.create_column_family("cf_b", ColumnFamilyConfig::default())?;

    // Purge all column families
    db.purge()?;
    // All CFs flushed and compacted, all queues drained

    Ok(())
}
```

:::tip[Purge vs Manual Flush + Compact]
`flush_memtable` and `compact` are non-blocking -- they enqueue work and return immediately. `ColumnFamily::purge` and `TidesDB::purge` are synchronous -- they block until all work is complete. Use purge when you need a guarantee that all data is on disk and compacted before proceeding.
:::

### Manual WAL Sync

`sync_wal` forces an immediate fsync of the active write-ahead log for a column family. This is useful for explicit durability control when using `SyncMode::None` or `SyncMode::Interval` modes.

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig, SyncMode};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;

    let cf_config = ColumnFamilyConfig::new()
        .sync_mode(SyncMode::None);
    db.create_column_family("my_cf", cf_config)?;

    let cf = db.get_column_family("my_cf")?;

    // Write some data
    let mut txn = db.begin_transaction()?;
    txn.put(&cf, b"key1", b"value1", -1)?;
    txn.put(&cf, b"key2", b"value2", -1)?;
    txn.commit()?;

    // Force WAL durability after the batch
    cf.sync_wal()?;

    Ok(())
}
```

**When to use**
- Application-controlled durability -- sync the WAL at specific points (e.g., after a batch of related writes) when using `SyncMode::None` or `SyncMode::Interval`
- Pre-checkpoint -- ensure all buffered WAL data is on disk before taking a checkpoint
- Graceful shutdown -- flush WAL buffers before closing the database
- Critical writes -- force durability for specific high-value writes without using `SyncMode::Full` for all writes

**Behavior**
- Acquires a reference to the active memtable to safely access its WAL
- Calls `fdatasync` on the WAL file descriptor
- Thread-safe -- can be called concurrently from multiple threads
- If the memtable rotates during the call, retries with the new active memtable

:::tip[Structural Operations]
Regardless of sync mode, TidesDB **always** enforces durability for structural operations:
- Memtable flush to SSTable
- SSTable compaction and merging
- WAL rotation
- Column family metadata updates

This ensures the database structure remains consistent even if user data syncing is delayed.
:::

### Database Backup

```rust
use tidesdb::{TidesDB, Config};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;

    // Create a backup to the specified directory
    db.backup("./mydb_backup")?;

    Ok(())
}
```

### Database Checkpoint

`checkpoint` creates a lightweight, near-instant snapshot of an open database using hard links instead of copying SSTable data.

```rust
use tidesdb::{TidesDB, Config};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;

    // Create a checkpoint to the specified directory
    db.checkpoint("./mydb_checkpoint")?;

    Ok(())
}
```

**Behavior**
- Requires `checkpoint_dir` to be a non-existent or empty directory
- For each column family:
  - Flushes the active memtable so all data is in SSTables
  - Halts compactions to ensure a consistent view of live SSTable files
  - Hard links all SSTable files (`.klog` and `.vlog`) into the checkpoint directory
  - Copies small metadata files (manifest, config) into the checkpoint directory
  - Resumes compactions
- Falls back to file copy if hard linking fails (e.g., cross-filesystem)
- Database stays open and usable during checkpoint

**Checkpoint vs Backup**

| | `backup` | `checkpoint` |
|--|---|---|
| Speed | Copies every SSTable byte-by-byte | Near-instant (hard links, O(1) per file) |
| Disk usage | Full independent copy | No extra disk until compaction removes old SSTables |
| Portability | Can be moved to another filesystem or machine | Same filesystem only (hard link requirement) |
| Use case | Archival, disaster recovery, remote shipping | Fast local snapshots, point-in-time reads, streaming backups |

**Notes**
- The checkpoint represents the database state at the point all memtables are flushed and compactions are halted
- Hard-linked files share storage with the live database. Deleting the original database does not affect the checkpoint (hard link semantics)
- The checkpoint can be opened as a normal TidesDB database with `TidesDB::open`

### Promote Replica to Primary

`promote_to_primary` switches a read-only replica to primary mode. This is only valid when the database was opened in replica mode (via object store configuration with `replica_mode` enabled).

```rust
use tidesdb::{TidesDB, Config};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;

    // Promote from replica to primary mode
    db.promote_to_primary()?;

    Ok(())
}
```

**Return values**
- `Ok(())` -- Promotion completed successfully
- `ErrorCode::InvalidArgs` -- Database is not in replica mode

### Runtime Configuration Updates

Update column family configuration at runtime:

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig, CompressionAlgorithm};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    // Create new configuration
    let new_config = ColumnFamilyConfig::new()
        .write_buffer_size(256 * 1024 * 1024)
        .compression_algorithm(CompressionAlgorithm::Zstd);

    // Update runtime config (persist_to_disk = true to save changes)
    cf.update_runtime_config(&new_config, true)?;

    Ok(())
}
```

### Commit Hook (Change Data Capture)

`ColumnFamily::set_commit_hook` registers a callback that fires synchronously after every transaction commit on a column family. The hook receives the full batch of committed operations atomically, enabling real-time change data capture without WAL parsing or external log consumers.

```rust
use std::sync::{Arc, Mutex};
use tidesdb::{TidesDB, Config, ColumnFamilyConfig, CommitOp};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let mut cf = db.get_column_family("my_cf")?;

    // Track all committed operations
    let log: Arc<Mutex<Vec<CommitOp>>> = Arc::new(Mutex::new(Vec::new()));
    let log_clone = log.clone();

    cf.set_commit_hook(move |ops, commit_seq| {
        println!("Commit seq {}: {} ops", commit_seq, ops.len());
        let mut l = log_clone.lock().unwrap();
        for op in ops {
            l.push(op.clone());
        }
        0 // return 0 on success
    })?;

    // Normal writes now trigger the hook automatically
    let mut txn = db.begin_transaction()?;
    txn.put(&cf, b"key1", b"value1", -1)?;
    txn.put(&cf, b"key2", b"value2", -1)?;
    txn.commit()?; // hook fires here

    // Detach hook
    cf.clear_commit_hook()?;

    Ok(())
}
```

**`CommitOp` fields**

| Field | Type | Description |
|-------|------|-------------|
| `key` | `Vec<u8>` | The key |
| `value` | `Option<Vec<u8>>` | The value (`None` for deletes) |
| `ttl` | `i64` | TTL as Unix timestamp (0 = no expiry) |
| `is_delete` | `bool` | Whether this is a delete operation |

**Behavior**
- The hook fires after WAL write, memtable apply, and commit status marking are complete - the data is fully durable before the callback runs
- Hook failure (non-zero return) is logged but does not affect the commit result
- Each column family has its own independent hook; a multi-CF transaction fires the hook once per CF with only that CF's operations
- `commit_seq` is monotonically increasing across commits and can be used as a replication cursor
- The hook executes synchronously on the committing thread; keep the callback fast to avoid stalling writers
- Calling `set_commit_hook` again replaces the previous hook (the old callback is freed automatically)
- Calling `clear_commit_hook` or dropping the `ColumnFamily` disables the hook immediately

**Use cases**
- Replication · Ship committed batches to replicas in commit order
- Event streaming · Publish mutations to Kafka, NATS, or any message broker
- Secondary indexing · Maintain a reverse index or materialized view
- Audit logging · Record every mutation with key, value, TTL, and sequence number
- Debugging · Attach a temporary hook in production to inspect live writes

:::note[Runtime-Only]
Commit hooks are not persisted to `config.ini`. After a database restart, hooks must be re-registered by the application. This is by design - closures cannot be serialized.
:::

### INI Configuration Files

Load and save column family configurations from/to INI files:

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    // Load configuration from INI file
    let cf_config = ColumnFamilyConfig::load_from_ini("config.ini", "my_column_family")?;

    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", cf_config.clone())?;

    // Save configuration to INI file
    cf_config.save_to_ini("config_backup.ini", "my_column_family")?;

    Ok(())
}
```

### Sync Modes

Control the durability vs performance tradeoff.

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig, SyncMode};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;

    // SyncMode::None -- Fastest, least durable (OS handles flushing)
    let cf_config = ColumnFamilyConfig::new()
        .sync_mode(SyncMode::None);
    db.create_column_family("fast_cf", cf_config)?;

    // SyncMode::Interval -- Balanced (periodic background syncing)
    let cf_config = ColumnFamilyConfig::new()
        .sync_mode(SyncMode::Interval)
        .sync_interval_us(128000); // Sync every 128ms
    db.create_column_family("balanced_cf", cf_config)?;

    // SyncMode::Full -- Most durable (fsync on every write)
    let cf_config = ColumnFamilyConfig::new()
        .sync_mode(SyncMode::Full);
    db.create_column_family("durable_cf", cf_config)?;

    Ok(())
}
```

### Compression Algorithms

TidesDB supports multiple compression algorithms:

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig, CompressionAlgorithm};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;

    // No compression
    let cf_config = ColumnFamilyConfig::new()
        .compression_algorithm(CompressionAlgorithm::None);

    // LZ4 compression (default, balanced)
    let cf_config = ColumnFamilyConfig::new()
        .compression_algorithm(CompressionAlgorithm::Lz4);

    // LZ4 fast compression (faster, slightly lower ratio)
    let cf_config = ColumnFamilyConfig::new()
        .compression_algorithm(CompressionAlgorithm::Lz4Fast);

    // Zstandard compression (best ratio)
    let cf_config = ColumnFamilyConfig::new()
        .compression_algorithm(CompressionAlgorithm::Zstd);

    // Snappy compression
    let cf_config = ColumnFamilyConfig::new()
        .compression_algorithm(CompressionAlgorithm::Snappy);

    db.create_column_family("my_cf", cf_config)?;

    Ok(())
}
```

### B+tree KLog Format

Column families can optionally use a B+tree structure for the key log instead of the default block-based format. The B+tree klog format offers faster point lookups through O(log N) tree traversal.

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig, CompressionAlgorithm};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;

    // Create column family with B+tree klog format
    let cf_config = ColumnFamilyConfig::new()
        .use_btree(true)
        .compression_algorithm(CompressionAlgorithm::Lz4);

    db.create_column_family("btree_cf", cf_config)?;

    // Create column family with block-based format (default)
    let cf_config = ColumnFamilyConfig::new()
        .use_btree(false);

    db.create_column_family("block_cf", cf_config)?;

    Ok(())
}
```

**B+tree Characteristics**
- Point lookups · O(log N) tree traversal with binary search at each node
- Range scans · Doubly-linked leaf nodes enable efficient bidirectional iteration
- Immutable · Tree is bulk-loaded from sorted memtable data during flush
- Compression · Nodes compress independently using the same algorithms

**When to use B+tree klog format**
- Read-heavy workloads with frequent point lookups
- Workloads where read latency is more important than write throughput
- Large SSTables where block scanning becomes expensive

**Tradeoffs**
- Slightly higher write amplification during flush (building tree structure)
- Larger metadata overhead per node compared to block-based format
- Block-based format may be faster for sequential scans of entire SSTables

:::note
`use_btree` **cannot be changed** after column family creation. Different column families can use different formats.
:::

### Unified Memtable Mode

When enabled, all column families share a single memtable and WAL instead of having independent per-CF memtables. This can reduce memory overhead and write amplification when using many column families with small write volumes.

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig, SyncMode, LogLevel};

fn main() -> tidesdb::Result<()> {
    let config = Config::new("./mydb")
        .num_flush_threads(2)
        .num_compaction_threads(2)
        .log_level(LogLevel::Info)
        .unified_memtable(true)
        .unified_memtable_write_buffer_size(128 * 1024 * 1024)
        .unified_memtable_skip_list_max_level(16)
        .unified_memtable_skip_list_probability(0.25)
        .unified_memtable_sync_mode(SyncMode::None)
        .unified_memtable_sync_interval_us(0);

    let db = TidesDB::open(config)?;

    // Column families work the same way
    db.create_column_family("cf_a", ColumnFamilyConfig::default())?;
    db.create_column_family("cf_b", ColumnFamilyConfig::default())?;

    let cf_a = db.get_column_family("cf_a")?;
    let cf_b = db.get_column_family("cf_b")?;

    let mut txn = db.begin_transaction()?;
    txn.put(&cf_a, b"key1", b"value1", -1)?;
    txn.put(&cf_b, b"key2", b"value2", -1)?;
    txn.commit()?;

    // Check unified memtable status via db stats
    let stats = db.get_db_stats()?;
    println!("Unified memtable enabled: {}", stats.unified_memtable_enabled);
    println!("Unified memtable bytes: {}", stats.unified_memtable_bytes);

    Ok(())
}
```

**When to use**
- Many column families with small individual write volumes
- Reducing total memory overhead from per-CF memtable allocation
- Simplifying WAL management across multiple column families

**Configuration**
- `unified_memtable_write_buffer_size` · Total write buffer threshold (0 = auto)
- `unified_memtable_skip_list_max_level` · Skip list max level (0 = default 12)
- `unified_memtable_skip_list_probability` · Skip list probability (0 = default 0.25)
- `unified_memtable_sync_mode` · WAL sync mode (default: `SyncMode::None`)
- `unified_memtable_sync_interval_us` · WAL sync interval in microseconds

### Object Store Mode

Object store mode allows TidesDB to store SSTables in a remote object store (S3, MinIO, GCS, or any S3-compatible service) while using local disk as a cache. This separates compute from storage and enables cold start recovery from the remote store. Object store mode requires unified memtable mode and is automatically enforced when a connector is set.

#### Enabling Object Store Mode (Filesystem Connector)

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig, ObjectStoreConfig};

fn main() -> tidesdb::Result<()> {
    let config = Config::new("./mydb")
        .object_store_fs("/mnt/nfs/tidesdb-objects");

    let db = TidesDB::open(config)?;

    // use the database normally -- SSTables are uploaded after flush

    Ok(())
}
```

#### Custom Object Store Configuration

Use `ObjectStoreConfig::default()` for sensible defaults, then override fields as needed:

```rust
use tidesdb::{TidesDB, Config, ObjectStoreConfig};

fn main() -> tidesdb::Result<()> {
    let os_config = ObjectStoreConfig::new()
        .local_cache_max_bytes(512 * 1024 * 1024) // 512MB local cache
        .max_concurrent_uploads(8)
        .max_concurrent_downloads(16);

    let config = Config::new("./mydb")
        .object_store_fs("/mnt/nfs/tidesdb-objects")
        .object_store_config(os_config);

    let db = TidesDB::open(config)?;

    Ok(())
}
```

#### Object Store Configuration Reference

| Method | Type | Default | Description |
|--------|------|---------|-------------|
| `local_cache_path(path)` | `&str` | None (uses db_path) | Local directory for cached SSTable files |
| `local_cache_max_bytes(size)` | `usize` | 0 (unlimited) | Maximum local cache size in bytes |
| `cache_on_read(enable)` | `bool` | true | Cache downloaded files locally |
| `cache_on_write(enable)` | `bool` | true | Keep local copy after upload |
| `max_concurrent_uploads(n)` | `i32` | 4 | Number of parallel upload threads |
| `max_concurrent_downloads(n)` | `i32` | 8 | Number of parallel download threads |
| `multipart_threshold(size)` | `usize` | 64MB | Use multipart upload above this size |
| `multipart_part_size(size)` | `usize` | 8MB | Chunk size for multipart uploads |
| `sync_manifest_to_object(enable)` | `bool` | true | Upload MANIFEST after each compaction |
| `replicate_wal(enable)` | `bool` | true | Upload closed WAL segments for replication |
| `wal_upload_sync(enable)` | `bool` | false | false for background WAL upload, true to block flush |
| `wal_sync_threshold_bytes(size)` | `usize` | 1MB | Sync active WAL when it grows by this many bytes (0 = off) |
| `wal_sync_on_commit(enable)` | `bool` | false | Upload WAL after every txn commit for RPO=0 replication |
| `replica_mode(enable)` | `bool` | false | Enable read-only replica mode (writes return `ErrorCode::ReadOnly`) |
| `replica_sync_interval_us(interval)` | `u64` | 5000000 (5s) | MANIFEST poll interval for replica sync in microseconds |
| `replica_replay_wal(enable)` | `bool` | true | Replay WAL from object store for near-real-time reads on replicas |

#### Per-CF Object Store Tuning

Column family configurations include three object store tuning fields (see Column Family Configuration Reference):
- `object_lazy_compaction` · Compact less aggressively for remote storage
- `object_prefetch_compaction` · Download all inputs before compaction merge

#### Object Store Statistics

`get_db_stats` includes object store fields when a connector is active:

```rust
use tidesdb::{TidesDB, Config, ObjectStoreConfig};

fn main() -> tidesdb::Result<()> {
    let config = Config::new("./mydb")
        .object_store_fs("/mnt/nfs/tidesdb-objects");

    let db = TidesDB::open(config)?;

    let stats = db.get_db_stats()?;
    if stats.object_store_enabled {
        println!("connector: {}", stats.object_store_connector);
        println!("total uploads: {}", stats.total_uploads);
        println!("upload failures: {}", stats.total_upload_failures);
        println!("upload queue depth: {}", stats.upload_queue_depth);
        println!("local cache: {} / {} bytes",
            stats.local_cache_bytes_used, stats.local_cache_bytes_max);
    }

    Ok(())
}
```

#### Replica Mode

Replica mode enables read-only nodes that follow a primary through the object store.

```rust
use tidesdb::{TidesDB, Config, ObjectStoreConfig};

fn main() -> tidesdb::Result<()> {
    let os_config = ObjectStoreConfig::new()
        .replica_mode(true)
        .replica_sync_interval_us(1_000_000)         // 1 second sync interval
        .replica_replay_wal(true);                   // replay WAL for fresh reads

    let config = Config::new("./mydb_replica")
        .object_store_fs("/mnt/nfs/tidesdb-objects") // same store as the primary
        .object_store_config(os_config);

    let db = TidesDB::open(config)?;

    // reads work normally, writes return ErrorCode::ReadOnly

    // promote to primary when the original primary fails
    db.promote_to_primary()?;

    Ok(())
}
```

#### Sync-on-Commit WAL (Primary Side)

For tighter replication lag, enable sync-on-commit on the primary so every committed write is uploaded to the object store immediately:

```rust
use tidesdb::{TidesDB, Config, ObjectStoreConfig};

fn main() -> tidesdb::Result<()> {
    let os_config = ObjectStoreConfig::new()
        .wal_sync_on_commit(true); // RPO = 0, every commit is durable in the store

    let config = Config::new("./mydb")
        .object_store_fs("/mnt/nfs/tidesdb-objects")
        .object_store_config(os_config);

    let db = TidesDB::open(config)?;

    // replica sees committed data within one replica_sync_interval_us

    Ok(())
}
```

:::note[Object Store Requirements]
- Object store mode automatically enables unified memtable mode
- After each flush, SSTables are uploaded via an asynchronous upload pipeline with retry (3 attempts with exponential backoff)
- Point lookups on remote SSTables fetch just the needed block (~64KB) via range request
- Iterators prefetch all needed SSTable files in parallel at creation time
- The MANIFEST is uploaded after each flush/compaction for cold start recovery
:::

### Custom Comparators

A comparator defines the sort order of keys throughout the entire system, memtables, SSTables, block indexes, and iterators. TidesDB ships with six built-in comparators and supports registering custom ones.

**Built-in comparators** `memcmp` (default), `lexicographic`, `uint64`, `int64`, `reverse`, `case_insensitive`

#### Registering a Custom Comparator

Register a custom comparator **after** opening the database but **before** creating any column family that uses it. Once a comparator is set for a column family, it **cannot be changed** without corrupting data.

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;

    // Register a reverse byte comparator
    db.register_comparator("my_reverse", |key1, key2| {
        let min_len = key1.len().min(key2.len());
        for i in 0..min_len {
            if key1[i] != key2[i] {
                return key2[i] as i32 - key1[i] as i32;
            }
        }
        key2.len() as i32 - key1.len() as i32
    })?;

    // Use the custom comparator in a column family
    let cf_config = ColumnFamilyConfig::new()
        .comparator_name("my_reverse");
    db.create_column_family("reverse_cf", cf_config)?;

    Ok(())
}
```

The comparator function receives two key byte slices and must return:
- **< 0** if `key1 < key2`
- **0** if `key1 == key2`
- **> 0** if `key1 > key2`

#### Checking if a Comparator Exists

```rust
if db.has_comparator("my_reverse") {
    println!("Comparator is registered");
}

// Built-in comparators are always available
assert!(db.has_comparator("memcmp"));
assert!(db.has_comparator("reverse"));
```

:::caution[Comparator Permanence]
Once a column family is created with a specific comparator, it **must always** be opened with the same comparator. Changing or removing a comparator after column family creation will corrupt the data ordering.
:::

### Utility Functions

#### `tidesdb::free`

Frees memory allocated by TidesDB. This is primarily useful for advanced FFI scenarios. For normal Rust usage, the safe wrappers handle memory management automatically.

```rust
// Safety: ptr must have been allocated by TidesDB
unsafe { tidesdb::free(ptr); }
```

## Database Configuration Reference

All available `Config` builder methods:

| Method | Type | Default | Description |
|--------|------|---------|-------------|
| `num_flush_threads(n)` | `i32` | 2 | Number of background flush threads |
| `num_compaction_threads(n)` | `i32` | 2 | Number of background compaction threads |
| `log_level(level)` | `LogLevel` | Info | Minimum log level (`Debug`, `Info`, `Warn`, `Error`, `Fatal`, `None`) |
| `block_cache_size(size)` | `usize` | 64MB | Global block cache size in bytes |
| `max_open_sstables(n)` | `usize` | 256 | Maximum number of open SSTable file descriptors |
| `max_memory_usage(size)` | `usize` | 0 | Global memory limit in bytes (0 = auto, 50% of system RAM) |
| `log_to_file(enable)` | `bool` | false | Write logs to file instead of stderr |
| `log_truncation_at(size)` | `usize` | 24MB | Log file truncation threshold in bytes (0 = no truncation) |
| `unified_memtable(enable)` | `bool` | false | Enable unified memtable mode (all CFs share one memtable/WAL) |
| `unified_memtable_write_buffer_size(size)` | `usize` | 0 | Unified memtable write buffer size (0 = auto) |
| `unified_memtable_skip_list_max_level(level)` | `i32` | 0 | Skip list max level for unified memtable (0 = default 12) |
| `unified_memtable_skip_list_probability(prob)` | `f32` | 0.0 | Skip list probability for unified memtable (0 = default 0.25) |
| `unified_memtable_sync_mode(mode)` | `SyncMode` | None | Sync mode for unified WAL |
| `unified_memtable_sync_interval_us(interval)` | `u64` | 0 | Sync interval for unified WAL in microseconds |
| `object_store_fs(root_dir)` | `&str` | None | Enable object store with filesystem connector at `root_dir` |
| `object_store_config(config)` | `ObjectStoreConfig` | None | Object store behavior configuration (see Object Store Configuration Reference) |

## Column Family Configuration Reference

All available `ColumnFamilyConfig` builder methods:

| Method | Type | Default | Description |
|--------|------|---------|-------------|
| `write_buffer_size(size)` | `usize` | 64MB | Memtable flush threshold in bytes |
| `level_size_ratio(ratio)` | `usize` | 10 | Level size multiplier |
| `min_levels(levels)` | `i32` | 5 | Minimum LSM levels |
| `dividing_level_offset(offset)` | `i32` | 2 | Compaction dividing level offset |
| `klog_value_threshold(threshold)` | `usize` | 512 | Values > threshold go to vlog |
| `compression_algorithm(algo)` | `CompressionAlgorithm` | Lz4 | Compression algorithm |
| `enable_bloom_filter(enable)` | `bool` | true | Enable bloom filters |
| `bloom_fpr(fpr)` | `f64` | 0.01 | Bloom filter false positive rate |
| `enable_block_indexes(enable)` | `bool` | true | Enable compact block indexes |
| `index_sample_ratio(ratio)` | `i32` | 1 | Sample every N blocks for index |
| `block_index_prefix_len(len)` | `i32` | 16 | Block index prefix length |
| `sync_mode(mode)` | `SyncMode` | Full | Durability mode |
| `sync_interval_us(interval)` | `u64` | 128000 | Sync interval (for Interval mode) |
| `comparator_name(name)` | `&str` | "memcmp" | Key comparator name |
| `skip_list_max_level(level)` | `i32` | 12 | Skip list max level |
| `skip_list_probability(prob)` | `f32` | 0.25 | Skip list probability |
| `default_isolation_level(level)` | `IsolationLevel` | ReadCommitted | Default transaction isolation |
| `min_disk_space(space)` | `u64` | 100MB | Minimum disk space required |
| `l1_file_count_trigger(trigger)` | `i32` | 4 | L1 file count trigger for compaction |
| `l0_queue_stall_threshold(threshold)` | `i32` | 20 | L0 queue stall threshold |
| `use_btree(enable)` | `bool` | false | Use B+tree format for klog |
| `object_lazy_compaction(enable)` | `bool` | false | Compact less aggressively in object store mode |
| `object_prefetch_compaction(enable)` | `bool` | true | Download all inputs before merge in object store mode |

**Updatable at runtime** (via `update_runtime_config`):
- `write_buffer_size`, `skip_list_max_level`, `skip_list_probability`
- `bloom_fpr`, `enable_bloom_filter`, `enable_block_indexes`, `block_index_prefix_len`
- `index_sample_ratio`, `compression_algorithm`, `klog_value_threshold`
- `sync_mode`, `sync_interval_us`, `level_size_ratio`, `min_levels`
- `dividing_level_offset`, `l1_file_count_trigger`, `l0_queue_stall_threshold`
- `default_isolation_level`, `min_disk_space`

**Non-updatable settings** (cannot be changed after column family creation):
- `comparator_name` · Cannot change sort order after creation (would corrupt key ordering in existing SSTables)
- `use_btree` · Cannot change klog format after creation (existing SSTables use the original format)

## Error Handling

TidesDB uses a custom `Result` type with detailed error information:

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig, Error, ErrorCode};

fn main() {
    let db = match TidesDB::open(Config::new("./mydb")) {
        Ok(db) => db,
        Err(e) => {
            eprintln!("Failed to open database: {}", e);
            return;
        }
    };

    db.create_column_family("my_cf", ColumnFamilyConfig::default()).unwrap();
    let cf = db.get_column_family("my_cf").unwrap();

    let txn = db.begin_transaction().unwrap();

    match txn.get(&cf, b"nonexistent_key") {
        Ok(value) => println!("Value: {:?}", value),
        Err(Error::TidesDB { code, context }) => {
            match code {
                ErrorCode::NotFound => println!("Key not found"),
                ErrorCode::Memory => println!("Memory allocation failed"),
                ErrorCode::Io => println!("I/O error"),
                _ => println!("Error ({}): {}", code as i32, context),
            }
        }
        Err(e) => println!("Other error: {}", e),
    }
}
```

**Error Codes**
- `ErrorCode::Success` (0) · Operation successful
- `ErrorCode::Memory` (-1) · Memory allocation failed
- `ErrorCode::InvalidArgs` (-2) · Invalid arguments
- `ErrorCode::NotFound` (-3) · Key not found
- `ErrorCode::Io` (-4) · I/O error
- `ErrorCode::Corruption` (-5) · Data corruption
- `ErrorCode::Exists` (-6) · Resource already exists
- `ErrorCode::Conflict` (-7) · Transaction conflict
- `ErrorCode::TooLarge` (-8) · Key or value too large
- `ErrorCode::MemoryLimit` (-9) · Memory limit exceeded
- `ErrorCode::InvalidDb` (-10) · Invalid database handle
- `ErrorCode::Unknown` (-11) · Unknown error
- `ErrorCode::Locked` (-12) · Database is locked
- `ErrorCode::ReadOnly` (-13) · Database is in read-only mode

## Complete Example

```rust
use std::time::{SystemTime, UNIX_EPOCH};
use tidesdb::{
    TidesDB, Config, ColumnFamilyConfig, CompressionAlgorithm,
    SyncMode, IsolationLevel, LogLevel,
};

fn main() -> tidesdb::Result<()> {
    let config = Config::new("./example_db")
        .num_flush_threads(1)
        .num_compaction_threads(1)
        .log_level(LogLevel::Info)
        .block_cache_size(64 * 1024 * 1024)
        .max_open_sstables(256)
        .max_memory_usage(0); // 0 = auto (50% of system RAM)

    let db = TidesDB::open(config)?;

    // Create column family with custom configuration
    let cf_config = ColumnFamilyConfig::new()
        .write_buffer_size(64 * 1024 * 1024)
        .compression_algorithm(CompressionAlgorithm::Lz4)
        .enable_bloom_filter(true)
        .bloom_fpr(0.01)
        .sync_mode(SyncMode::Interval)
        .sync_interval_us(128000);

    db.create_column_family("users", cf_config)?;

    let cf = db.get_column_family("users")?;

    {
        let mut txn = db.begin_transaction()?;

        txn.put(&cf, b"user:1", b"Alice", -1)?;
        txn.put(&cf, b"user:2", b"Bob", -1)?;

        // Write with TTL (expires in 30 seconds)
        let ttl = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64 + 30;
        txn.put(&cf, b"session:abc", b"temp_data", ttl)?;

        txn.commit()?;
    }

    {
        let txn = db.begin_transaction()?;

        let value = txn.get(&cf, b"user:1")?;
        println!("user:1 = {}", String::from_utf8_lossy(&value));
    }

    {
        let txn = db.begin_transaction()?;
        let mut iter = txn.new_iterator(&cf)?;

        println!("\nAll entries:");
        iter.seek_to_first()?;
        while iter.is_valid() {
            let key = iter.key()?;
            let value = iter.value()?;
            println!("  {} = {}",
                String::from_utf8_lossy(&key),
                String::from_utf8_lossy(&value));
            iter.next()?;
        }
    }

    let stats = cf.get_stats()?;
    println!("\nColumn Family Statistics:");
    println!("  Number of Levels: {}", stats.num_levels);
    println!("  Memtable Size: {} bytes", stats.memtable_size);

    db.drop_column_family("users")?;

    Ok(())
}
```

## Isolation Levels

TidesDB supports five MVCC isolation levels:

```rust
use tidesdb::{TidesDB, Config, IsolationLevel};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    let txn = db.begin_transaction_with_isolation(IsolationLevel::ReadCommitted)?;

    // Use transaction...

    Ok(())
}
```

**Available Isolation Levels**
- `IsolationLevel::ReadUncommitted` · Sees all data including uncommitted changes
- `IsolationLevel::ReadCommitted` · Sees only committed data (default)
- `IsolationLevel::RepeatableRead` · Consistent snapshot, phantom reads possible
- `IsolationLevel::Snapshot` · Write-write conflict detection
- `IsolationLevel::Serializable` · Full read-write conflict detection (SSI)

## Savepoints

Savepoints allow partial rollback within a transaction:

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    let mut txn = db.begin_transaction()?;

    txn.put(&cf, b"key1", b"value1", -1)?;

    txn.savepoint("sp1")?;

    txn.put(&cf, b"key2", b"value2", -1)?;

    // Rollback to savepoint -- key2 is discarded, key1 remains
    txn.rollback_to_savepoint("sp1")?;

    // Add different data after rollback
    txn.put(&cf, b"key3", b"value3", -1)?;

    // Commit -- only key1 and key3 are written
    txn.commit()?;

    Ok(())
}
```

## Thread Safety

TidesDB is thread-safe. The `TidesDB` and `ColumnFamily` types implement `Send` and `Sync`, allowing them to be shared across threads:

```rust
use std::sync::Arc;
use std::thread;
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = Arc::new(TidesDB::open(Config::new("./mydb"))?);
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    let handles: Vec<_> = (0..4).map(|i| {
        let db = Arc::clone(&db);
        let cf_name = "my_cf".to_string();

        thread::spawn(move || {
            let cf = db.get_column_family(&cf_name).unwrap();
            let mut txn = db.begin_transaction().unwrap();

            let key = format!("key:{}", i);
            let value = format!("value:{}", i);
            txn.put(&cf, key.as_bytes(), value.as_bytes(), -1).unwrap();
            txn.commit().unwrap();
        })
    }).collect();

    for handle in handles {
        handle.join().unwrap();
    }

    Ok(())
}
```

## Testing

```bash
cargo test

# Run tests with output
cargo test -- --nocapture

# Run specific test
cargo test test_open_close

# Run with release optimizations
cargo test --release

# Run single-threaded (recommended for TidesDB tests)
cargo test -- --test-threads=1
```

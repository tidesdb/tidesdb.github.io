---
title: TidesDB Rust API Reference
description: Rust API reference for TidesDB
---

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/rust.md).

<hr/>

## Getting Started

### Prerequisites

You **must** have the TidesDB shared C library installed on your system. You can find the installation instructions [here](/reference/building/#_top).

### Building from GitHub

To build the library directly from the GitHub repository:

```bash
# Clone the repository
git clone https://github.com/tidesdb/tidesdb-rust.git
cd tidesdb-rust

# Build the library
cargo build --release

# Run tests
cargo test -- --test-threads=1

# Install locally (optional)
cargo install --path .
```

**Using as a local dependency**

You can reference the local build in your project's `Cargo.toml`:

```toml
[dependencies]
tidesdb = { path = "/path/to/tidesdb-rust" }
```

**Using directly from GitHub**

You can also add the dependency directly from GitHub:

```toml
[dependencies]
tidesdb = { git = "https://github.com/tidesdb/tidesdb-rust.git" }

# Or pin to a specific branch
tidesdb = { git = "https://github.com/tidesdb/tidesdb-rust.git", branch = "main" }

# Or pin to a specific tag/version
tidesdb = { git = "https://github.com/tidesdb/tidesdb-rust.git", tag = "v0.2.0" }

# Or pin to a specific commit
tidesdb = { git = "https://github.com/tidesdb/tidesdb-rust.git", rev = "abc123" }
```

### Custom Installation Paths

If you installed TidesDB to a non-standard location, you can specify custom paths using environment variables:

```bash
# Set custom library path
export LIBRARY_PATH="/custom/path/lib:$LIBRARY_PATH"
export LD_LIBRARY_PATH="/custom/path/lib:$LD_LIBRARY_PATH"  # Linux
# or
export DYLD_LIBRARY_PATH="/custom/path/lib:$DYLD_LIBRARY_PATH"  # macOS

# Then build
cargo build
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

## Usage

### Opening and Closing a Database

```rust
use tidesdb::{TidesDB, Config, LogLevel};

fn main() -> tidesdb::Result<()> {
    let config = Config::new("./mydb")
        .num_flush_threads(2)
        .num_compaction_threads(2)
        .log_level(LogLevel::Info)
        .block_cache_size(64 * 1024 * 1024)
        .max_open_sstables(256);

    let db = TidesDB::open(config)?;

    println!("Database opened successfully");

    // Database is automatically closed when `db` goes out of scope
    Ok(())
}
```

### Creating and Dropping Column Families

Column families are isolated key-value stores with independent configuration.

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig, CompressionAlgorithm, SyncMode, IsolationLevel};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;

    // Create with default configuration
    let cf_config = ColumnFamilyConfig::default();
    db.create_column_family("my_cf", cf_config)?;

    // Create with custom configuration
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

    // Drop a column family
    db.drop_column_family("my_cf")?;

    Ok(())
}
```

### CRUD Operations

All operations in TidesDB are performed through transactions for ACID guarantees.

#### Writing Data

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    let txn = db.begin_transaction()?;

    // Put a key-value pair (TTL -1 means no expiration)
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

    let txn = db.begin_transaction()?;

    // Set expiration time (Unix timestamp)
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

// No expiration
let ttl: i64 = -1;

// Expire in 5 minutes
let ttl = SystemTime::now()
    .duration_since(UNIX_EPOCH)
    .unwrap()
    .as_secs() as i64 + 5 * 60;

// Expire in 1 hour
let ttl = SystemTime::now()
    .duration_since(UNIX_EPOCH)
    .unwrap()
    .as_secs() as i64 + 60 * 60;

// Expire at specific Unix timestamp
let ttl: i64 = 1798761599; // Dec 31, 2026 23:59:59 UTC
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

    let txn = db.begin_transaction()?;
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

    let txn = db.begin_transaction()?;

    // Multiple operations in one transaction
    txn.put(&cf, b"key1", b"value1", -1)?;
    txn.put(&cf, b"key2", b"value2", -1)?;
    txn.delete(&cf, b"old_key")?;

    // Commit atomically -- all or nothing
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

    let txn = db.begin_transaction()?;
    txn.put(&cf, b"key", b"value", -1)?;

    // Decide to rollback instead of commit
    txn.rollback()?;
    // No changes were applied

    Ok(())
}
```

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

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    let txn = db.begin_transaction()?;
    let mut iter = txn.new_iterator(&cf)?;

    // Seek to first key >= "user:"
    iter.seek(b"user:")?;

    // Iterate all keys with "user:" prefix
    while iter.is_valid() {
        let key = iter.key()?;

        // Stop when keys no longer match prefix
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
- Point lookups -- O(log N) tree traversal with binary search at each node
- Range scans -- Doubly-linked leaf nodes enable efficient bidirectional iteration
- Immutable -- Tree is bulk-loaded from sorted memtable data during flush
- Compression -- Nodes compress independently using the same algorithms

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

**Non-updatable settings** (cannot be changed after column family creation):
- `compression_algorithm`, `enable_block_indexes`, `enable_bloom_filter`
- `comparator_name`, `level_size_ratio`, `klog_value_threshold`
- `min_levels`, `dividing_level_offset`, `block_index_prefix_len`
- `l1_file_count_trigger`, `l0_queue_stall_threshold`, `use_btree`

**Updatable at runtime** (via `update_runtime_config`):
- `write_buffer_size`, `skip_list_max_level`, `skip_list_probability`
- `bloom_fpr`, `index_sample_ratio`, `sync_mode`, `sync_interval_us`

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
- `ErrorCode::Success` (0) -- Operation successful
- `ErrorCode::Memory` (-1) -- Memory allocation failed
- `ErrorCode::InvalidArgs` (-2) -- Invalid arguments
- `ErrorCode::NotFound` (-3) -- Key not found
- `ErrorCode::Io` (-4) -- I/O error
- `ErrorCode::Corruption` (-5) -- Data corruption
- `ErrorCode::Exists` (-6) -- Resource already exists
- `ErrorCode::Conflict` (-7) -- Transaction conflict
- `ErrorCode::TooLarge` (-8) -- Key or value too large
- `ErrorCode::MemoryLimit` (-9) -- Memory limit exceeded
- `ErrorCode::InvalidDb` (-10) -- Invalid database handle
- `ErrorCode::Unknown` (-11) -- Unknown error
- `ErrorCode::Locked` (-12) -- Database is locked

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
        .max_open_sstables(256);

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
        let txn = db.begin_transaction()?;

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
- `IsolationLevel::ReadUncommitted` -- Sees all data including uncommitted changes
- `IsolationLevel::ReadCommitted` -- Sees only committed data (default)
- `IsolationLevel::RepeatableRead` -- Consistent snapshot, phantom reads possible
- `IsolationLevel::Snapshot` -- Write-write conflict detection
- `IsolationLevel::Serializable` -- Full read-write conflict detection (SSI)

## Savepoints

Savepoints allow partial rollback within a transaction:

```rust
use tidesdb::{TidesDB, Config, ColumnFamilyConfig};

fn main() -> tidesdb::Result<()> {
    let db = TidesDB::open(Config::new("./mydb"))?;
    db.create_column_family("my_cf", ColumnFamilyConfig::default())?;

    let cf = db.get_column_family("my_cf")?;

    let txn = db.begin_transaction()?;

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
            let txn = db.begin_transaction().unwrap();

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

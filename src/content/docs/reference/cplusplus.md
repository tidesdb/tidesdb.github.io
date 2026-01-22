---
title: TidesDB C++ API Reference
description: C++ API reference for TidesDB
---

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/cplusplus.md).

<hr/>

## Getting Started

### Prerequisites

You **must** have the TidesDB shared C library installed on your system. You can find the installation instructions [here](/reference/building/#_top).

### Installation

```bash
git clone https://github.com/tidesdb/tidesdb-cpp.git
cd tidesdb-cpp
cmake -S . -B build
cmake --build build
sudo cmake --install build
```

### Custom Installation Paths

If you installed TidesDB to a non-standard location, you can specify custom paths:

```bash
cmake -S . -B build -DCMAKE_PREFIX_PATH=/custom/path
cmake --build build
```

## Usage

### Opening and Closing a Database

```cpp
#include <tidesdb/tidesdb.hpp>
#include <iostream>

int main() {
    tidesdb::Config config;
    config.dbPath = "./mydb";
    config.numFlushThreads = 2;
    config.numCompactionThreads = 2;
    config.logLevel = tidesdb::LogLevel::Info;
    config.blockCacheSize = 64 * 1024 * 1024;
    config.maxOpenSSTables = 256;

    try {
        tidesdb::TidesDB db(config);
        std::cout << "Database opened successfully" << std::endl;
        // Database automatically closes when db goes out of scope
    } catch (const tidesdb::Exception& e) {
        std::cerr << "Failed to open database: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
```

### Creating and Dropping Column Families

Column families are isolated key-value stores with independent configuration.

```cpp
auto cfConfig = tidesdb::ColumnFamilyConfig::defaultConfig();
db.createColumnFamily("my_cf", cfConfig);

// Create with custom configuration
auto cfConfig = tidesdb::ColumnFamilyConfig::defaultConfig();
cfConfig.writeBufferSize = 128 * 1024 * 1024;
cfConfig.levelSizeRatio = 10;
cfConfig.minLevels = 5;
cfConfig.compressionAlgorithm = tidesdb::CompressionAlgorithm::LZ4;
cfConfig.enableBloomFilter = true;
cfConfig.bloomFPR = 0.01;
cfConfig.enableBlockIndexes = true;
cfConfig.syncMode = tidesdb::SyncMode::Interval;
cfConfig.syncIntervalUs = 128000;
cfConfig.defaultIsolationLevel = tidesdb::IsolationLevel::ReadCommitted;

db.createColumnFamily("my_cf", cfConfig);

db.dropColumnFamily("my_cf");
```

### CRUD Operations

All operations in TidesDB are performed through transactions for ACID guarantees.

#### Writing Data

```cpp
auto cf = db.getColumnFamily("my_cf");

auto txn = db.beginTransaction();
txn.put(cf, "key", "value", -1);  // TTL -1 means no expiration
txn.commit();
```

#### Writing with TTL

```cpp
#include <ctime>

auto cf = db.getColumnFamily("my_cf");

auto txn = db.beginTransaction();

// Set expiration time (Unix timestamp)
auto ttl = std::time(nullptr) + 10;  // Expires in 10 seconds

txn.put(cf, "temp_key", "temp_value", ttl);
txn.commit();
```

**TTL Examples**
```cpp
// No expiration
auto ttl = static_cast<std::time_t>(-1);

// Expire in 5 minutes
auto ttl = std::time(nullptr) + (5 * 60);

// Expire in 1 hour
auto ttl = std::time(nullptr) + (60 * 60);

// Expire at specific time
auto ttl = static_cast<std::time_t>(1735689599);  // Specific Unix timestamp
```

#### Reading Data

```cpp
auto cf = db.getColumnFamily("my_cf");

auto txn = db.beginTransaction();
auto value = txn.get(cf, "key");
std::string valueStr(value.begin(), value.end());
std::cout << "Value: " << valueStr << std::endl;
```

#### Deleting Data

```cpp
auto cf = db.getColumnFamily("my_cf");

auto txn = db.beginTransaction();
txn.del(cf, "key");
txn.commit();
```

#### Multi-Operation Transactions

```cpp
auto cf = db.getColumnFamily("my_cf");

auto txn = db.beginTransaction();

// Multiple operations in one transaction
txn.put(cf, "key1", "value1", -1);
txn.put(cf, "key2", "value2", -1);
txn.del(cf, "old_key");

// Commit atomically -- all or nothing
txn.commit();
```

### Iterating Over Data

Iterators provide efficient bidirectional traversal over key-value pairs.

#### Forward Iteration

```cpp
auto cf = db.getColumnFamily("my_cf");

auto txn = db.beginTransaction();
auto iter = txn.newIterator(cf);

iter.seekToFirst();

while (iter.valid()) {
    auto key = iter.key();
    auto value = iter.value();

    std::string keyStr(key.begin(), key.end());
    std::string valueStr(value.begin(), value.end());

    std::cout << "Key: " << keyStr << ", Value: " << valueStr << std::endl;

    iter.next();
}
```

#### Backward Iteration

```cpp
auto cf = db.getColumnFamily("my_cf");

auto txn = db.beginTransaction();
auto iter = txn.newIterator(cf);

iter.seekToLast();

while (iter.valid()) {
    auto key = iter.key();
    auto value = iter.value();
    // Process entries in reverse order
    iter.prev();
}
```

#### Seeking

```cpp
auto iter = txn.newIterator(cf);

// Seek to first key >= "user:1000"
iter.seek("user:1000");

// Seek to last key <= "user:2000"
iter.seekForPrev("user:2000");
```

### Getting Column Family Statistics

Retrieve detailed statistics about a column family.

```cpp
auto cf = db.getColumnFamily("my_cf");

auto stats = cf.getStats();

std::cout << "Number of Levels: " << stats.numLevels << std::endl;
std::cout << "Memtable Size: " << stats.memtableSize << " bytes" << std::endl;

if (stats.config.has_value()) {
    std::cout << "Write Buffer Size: " << stats.config->writeBufferSize << std::endl;
    std::cout << "Compression: " << static_cast<int>(stats.config->compressionAlgorithm) << std::endl;
    std::cout << "Bloom Filter: " << (stats.config->enableBloomFilter ? "enabled" : "disabled") << std::endl;
}
```

### Listing Column Families

```cpp
auto cfList = db.listColumnFamilies();

std::cout << "Available column families:" << std::endl;
for (const auto& name : cfList) {
    std::cout << "  - " << name << std::endl;
}
```

### Compaction

#### Manual Compaction

```cpp
auto cf = db.getColumnFamily("my_cf");

// Manually trigger compaction 
cf.compact();
```

#### Manual Memtable Flush

```cpp
auto cf = db.getColumnFamily("my_cf");

// Manually trigger memtable flush (Queues sorted run for L1)
cf.flushMemtable(); 
```

### Sync Modes

Control the durability vs performance tradeoff.

```cpp
auto cfConfig = tidesdb::ColumnFamilyConfig::defaultConfig();

// SyncNone -- Fastest, least durable
cfConfig.syncMode = tidesdb::SyncMode::None;

// SyncInterval -- Balanced (periodic background syncing)
cfConfig.syncMode = tidesdb::SyncMode::Interval;
cfConfig.syncIntervalUs = 128000;  // Sync every 128ms

// SyncFull -- Most durable (fsync on every write)
cfConfig.syncMode = tidesdb::SyncMode::Full;

db.createColumnFamily("my_cf", cfConfig);
```

### Compression Algorithms

TidesDB supports multiple compression algorithms:

```cpp
auto cfConfig = tidesdb::ColumnFamilyConfig::defaultConfig();

cfConfig.compressionAlgorithm = tidesdb::CompressionAlgorithm::None;
cfConfig.compressionAlgorithm = tidesdb::CompressionAlgorithm::LZ4;
cfConfig.compressionAlgorithm = tidesdb::CompressionAlgorithm::LZ4Fast;
cfConfig.compressionAlgorithm = tidesdb::CompressionAlgorithm::Zstd;

db.createColumnFamily("my_cf", cfConfig);
```

## Error Handling

The C++ wrapper uses exceptions for error handling. All errors throw `tidesdb::Exception`.

```cpp
try {
    auto cf = db.getColumnFamily("my_cf");

    auto txn = db.beginTransaction();
    txn.put(cf, "key", "value", -1);
    txn.commit();
} catch (const tidesdb::Exception& e) {
    std::cerr << "Error: " << e.what() << std::endl;
    std::cerr << "Code: " << static_cast<int>(e.code()) << std::endl;
}
```

**Error Codes**
- `ErrorCode::Success` (0) -- Operation successful
- `ErrorCode::Memory` (-1) -- Memory allocation failed
- `ErrorCode::InvalidArgs` (-2) -- Invalid arguments
- `ErrorCode::NotFound` (-3) -- Key not found
- `ErrorCode::IO` (-4) -- I/O error
- `ErrorCode::Corruption` (-5) -- Data corruption
- `ErrorCode::Exists` (-6) -- Resource already exists
- `ErrorCode::Conflict` (-7) -- Transaction conflict
- `ErrorCode::TooLarge` (-8) -- Key or value too large
- `ErrorCode::MemoryLimit` (-9) -- Memory limit exceeded
- `ErrorCode::InvalidDB` (-10) -- Invalid database handle
- `ErrorCode::Unknown` (-11) -- Unknown error
- `ErrorCode::Locked` (-12) -- Database is locked

## Complete Example

```cpp
#include <tidesdb/tidesdb.hpp>
#include <iostream>
#include <ctime>

int main() {
    try {
        tidesdb::Config config;
        config.dbPath = "./example_db";
        config.numFlushThreads = 1;
        config.numCompactionThreads = 1;
        config.logLevel = tidesdb::LogLevel::Info;
        config.blockCacheSize = 64 * 1024 * 1024;
        config.maxOpenSSTables = 256;

        tidesdb::TidesDB db(config);

        auto cfConfig = tidesdb::ColumnFamilyConfig::defaultConfig();
        cfConfig.writeBufferSize = 64 * 1024 * 1024;
        cfConfig.compressionAlgorithm = tidesdb::CompressionAlgorithm::LZ4;
        cfConfig.enableBloomFilter = true;
        cfConfig.bloomFPR = 0.01;
        cfConfig.syncMode = tidesdb::SyncMode::Interval;
        cfConfig.syncIntervalUs = 128000;

        db.createColumnFamily("users", cfConfig);

        auto cf = db.getColumnFamily("users");

        // Write data
        {
            auto txn = db.beginTransaction();
            txn.put(cf, "user:1", "Alice", -1);
            txn.put(cf, "user:2", "Bob", -1);

            auto ttl = std::time(nullptr) + 30;
            txn.put(cf, "session:abc", "temp_data", ttl);

            txn.commit();
        }

        // Read data
        {
            auto txn = db.beginTransaction();
            auto value = txn.get(cf, "user:1");
            std::string valueStr(value.begin(), value.end());
            std::cout << "user:1 = " << valueStr << std::endl;
        }

        // Iterate
        {
            auto txn = db.beginTransaction();
            auto iter = txn.newIterator(cf);

            std::cout << "\nAll entries:" << std::endl;
            iter.seekToFirst();
            while (iter.valid()) {
                auto key = iter.key();
                auto value = iter.value();
                std::string keyStr(key.begin(), key.end());
                std::string valueStr(value.begin(), value.end());
                std::cout << "  " << keyStr << " = " << valueStr << std::endl;
                iter.next();
            }
        }

        auto stats = cf.getStats();
        std::cout << "\nColumn Family Statistics:" << std::endl;
        std::cout << "  Number of Levels: " << stats.numLevels << std::endl;
        std::cout << "  Memtable Size: " << stats.memtableSize << " bytes" << std::endl;

        db.dropColumnFamily("users");

    } catch (const tidesdb::Exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
```

## Isolation Levels

TidesDB supports five MVCC isolation levels:

```cpp
auto txn = db.beginTransaction(tidesdb::IsolationLevel::ReadCommitted);
// Perform operations
txn.commit();
```

**Available Isolation Levels**
- `IsolationLevel::ReadUncommitted` -- Sees all data including uncommitted changes
- `IsolationLevel::ReadCommitted` -- Sees only committed data (default)
- `IsolationLevel::RepeatableRead` -- Consistent snapshot, phantom reads possible
- `IsolationLevel::Snapshot` -- Write-write conflict detection
- `IsolationLevel::Serializable` -- Full read-write conflict detection (SSI)

## Savepoints

Savepoints allow partial rollback within a transaction:

```cpp
auto txn = db.beginTransaction();

txn.put(cf, "key1", "value1", -1);

txn.savepoint("sp1");
txn.put(cf, "key2", "value2", -1);

// Rollback to savepoint -- key2 is discarded, key1 remains
txn.rollbackToSavepoint("sp1");

// Commit -- only key1 is written
txn.commit();
```

## Testing

```bash
# Build with tests
cmake -S . -B build -DTIDESDB_CPP_BUILD_TESTS=ON
cmake --build build

# Run tests
cd build
ctest --output-on-failure
```

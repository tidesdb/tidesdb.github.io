---
title: Building TidesDB
description: How to build TidesDB.
---

You need cmake and a C compiler. You also require the `snappy`, `lz4`, `zstd`, and `openssl` libraries.

### Dependencies
- [Snappy](https://github.com/google/snappy) - Compression
- [LZ4](https://github.com/lz4/lz4) - Compression
- [Zstandard](https://github.com/facebook/zstd) - Compression
- [OpenSSL](https://www.openssl.org/) - Cryptographic hashing (SHA1)

### Linux
```bash
sudo apt install libzstd-dev
sudo apt install liblz4-dev
sudo apt install libsnappy-dev
sudo apt install libssl-dev
```

### MacOS
```bash
brew install zstd
brew install lz4
brew install snappy
brew install openssl
```

### Windows
Windows using vcpkg
```bash
vcpkg install zstd
vcpkg install lz4
vcpkg install snappy
vcpkg install openssl
```

Once you have everything set you can build using below commands.

### Unix (Linux/macOS)
```bash
rm -rf build && cmake -S . -B build
cmake --build build
cmake --install build
```

### Windows
```bash
rmdir /s /q build && cmake -S . -B build
cmake --build build
cmake --install build
```

## Build Configuration Constants

Before building TidesDB, you can modify compile-time configuration constants in `src/tidesdb.h` to customize behavior:

### TDB_BLOCK_INDICES
**Default:** `1` (enabled)  
**Description:** Enables Sorted Binary Hash Array (SBHA) indices for fast SSTable lookups. When enabled, each SSTable maintains a hash-based index that allows direct access to blocks without scanning the entire file.

```c
#define TDB_BLOCK_INDICES 1  /* 0 = disabled, 1 = enabled */
```

**Impact:**
- **Enabled**: Faster reads, slightly larger SSTable files
- **Disabled**: Slower reads (linear scan), smaller SSTable files

### TDB_DEBUG_LOG
**Default:** `0` (disabled)  
**Description:** Enables debug logging throughout TidesDB operations. Useful for development and troubleshooting.

```c
#define TDB_DEBUG_LOG 0  /* 0 = disabled, 1 = enabled */
```

**Usage:**
```c
/* In your application */
tidesdb_config_t config = {
    .db_path = "./mydb",
    .enable_debug_logging = 1  /* Enable at runtime */
};
```

### TDB_DEBUG_LOG_TRUNCATE_AT
**Default:** `10485760` (10MB)  
**Description:** Maximum size of the debug log file in bytes before it gets truncated. Prevents unbounded log growth.

```c
#define TDB_DEBUG_LOG_TRUNCATE_AT 10485760  /* 10MB */
```

### TDB_AVAILABLE_MEMORY_THRESHOLD
**Default:** `0.8` (80%)  
**Description:** Maximum percentage of available system memory that TidesDB can use for memtables and caches. Helps prevent out-of-memory conditions.

```c
#define TDB_AVAILABLE_MEMORY_THRESHOLD 0.8  /* 80% of available memory */
```

**Note:** This is a soft limit. TidesDB will attempt to flush memtables when approaching this threshold.

## Default Configuration Values

These constants define default values for column family configuration:

```c
#define TDB_DEFAULT_MEMTABLE_FLUSH_SIZE      (128 * 1024 * 1024)  /* 128MB */
#define TDB_DEFAULT_MAX_SSTABLES_COMPACTION  512                   /* 512 SSTables */
#define TDB_DEFAULT_COMPACTION_THREADS       4                     /* 4 threads */
#define TDB_DEFAULT_SKIP_LIST_MAX_LEVEL      12                    /* Max level 12 */
#define TDB_DEFAULT_SKIP_LIST_PROBABILITY    0.25f                 /* 25% probability */
#define TDB_DEFAULT_BLOOM_FILTER_FP_RATE     0.01                  /* 1% false positive */
#define TDB_DEFAULT_SYNC_INTERVAL            1.0f                  /* 1 second */
```

## Modifying Build Configuration

1. Edit `src/tidesdb.h` before building
2. Modify the desired constants
3. Rebuild TidesDB with the new configuration

**Example:**
```c
/* In src/tidesdb.h */
#define TDB_DEBUG_LOG 1                      /* Enable debug logging */
#define TDB_BLOCK_INDICES 1                  /* Keep SBHA enabled */
#define TDB_AVAILABLE_MEMORY_THRESHOLD 0.9   /* Use up to 90% memory */
```

Then rebuild:
```bash
rm -rf build && cmake -S . -B build
cmake --build build
cmake --install build
```

## Testing

After building, run the test suite to verify everything works:

```bash
cd build
ctest --output-on-failure
```

Or run tests directly:
```bash
./build/tidesdb_tests
```

## Benchmarking

Run the benchmark suite to measure performance:

```bash
./build/tidesdb_bench
```

The benchmark tests:
- Sequential writes (PUT operations)
- Random reads (GET operations)  
- Sequential deletes (DELETE operations)
- All operations use transactions and test parallel compaction

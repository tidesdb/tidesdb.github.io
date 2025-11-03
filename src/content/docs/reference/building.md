---
title: Building TidesDB
description: How to build TidesDB.
---

## Requirements

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

## Building

Once you have the dependencies installed, you can build using the commands below.

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

## Default Configuration Values

These constants define default values for column family configuration:

```c
#define TDB_DEFAULT_MEMTABLE_FLUSH_SIZE            (64 * 1024 * 1024)
#define TDB_DEFAULT_MAX_SSTABLES                   128
#define TDB_DEFAULT_COMPACTION_THREADS             4
#define TDB_DEFAULT_BACKGROUND_COMPACTION_INTERVAL 1000000
#define TDB_DEFAULT_MAX_OPEN_FILE_HANDLES          1024
#define TDB_DEFAULT_SKIPLIST_LEVELS                12
#define TDB_DEFAULT_SKIPLIST_PROBABILITY           0.25
#define TDB_DEFAULT_BLOOM_FILTER_FP_RATE           0.01
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

---
title: Building TidesDB
description: How to build TidesDB.
---

:::tip[Latest Version]
Check the [latest release](https://github.com/tidesdb/tidesdb/releases/latest) on GitHub for the current version.
:::

## Prerequisites

### Build Tools
- **CMake** 3.10 or higher
- **C Compiler** with C11 support:
  - GCC 7.0+ (Linux/MinGW)
  - Clang 6.0+ (macOS/Linux)
  - MSVC 2019 16.8+ (Windows)

### Required Dependencies
TidesDB requires the following libraries for compression and cryptographic operations

- **[Snappy](https://github.com/google/snappy)** - Fast compression/decompression
- **[LZ4](https://github.com/lz4/lz4)** - Extremely fast compression
- **[Zstandard](https://github.com/facebook/zstd)** - High compression ratio
- **[OpenSSL](https://www.openssl.org/)** - SHA-256 cryptographic hashing

## Installing Dependencies

### Linux (Debian/Ubuntu)
```bash
# Install all dependencies
sudo apt update
sudo apt install -y cmake build-essential \
    libzstd-dev liblz4-dev libsnappy-dev libssl-dev
```

**Other Linux Distributions**
```bash
# Fedora/RHEL/CentOS
sudo dnf install cmake gcc libzstd-devel lz4-devel snappy-devel openssl-devel

# Arch Linux
sudo pacman -S cmake gcc zstd lz4 snappy openssl
```

### macOS
```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install dependencies
brew install cmake zstd lz4 snappy openssl
```

### Windows

**Using vcpkg (Recommended)**
```powershell
# Install vcpkg if not already installed
git clone https://github.com/Microsoft/vcpkg.git
cd vcpkg
.\bootstrap-vcpkg.bat

# Install dependencies
.\vcpkg install zstd:x64-windows lz4:x64-windows snappy:x64-windows openssl:x64-windows

# For 32-bit builds
.\vcpkg install zstd:x86-windows lz4:x86-windows snappy:x86-windows openssl:x86-windows
```

## Building

Once you have the dependencies installed, you can build using the commands below.

### Unix (Linux/macOS)
```bash
rm -rf build && cmake -S . -B build
cmake --build build
cmake --install build

# Production build
rm -rf build && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DTIDESDB_WITH_SANITIZER=OFF -DTIDESDB_BUILD_TESTS=OFF
cmake --build build --config Release
cmake --install build

# On linux run ldconfig to update the shared library cache
ldconfig
```

### Windows

#### MinGW-w64 
MinGW-w64 provides a GCC-based toolchain with better C11 support and POSIX compatibility.

**Prerequisites**
- Install [MinGW-w64](https://www.mingw-w64.org/)
- Install [CMake](https://cmake.org/download/)
- Install [vcpkg](https://vcpkg.io/en/getting-started.html) for dependencies

**Build Steps**
```powershell
# Clean previous build
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue

# Configure with MinGW
cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_C_COMPILER=gcc -DCMAKE_TOOLCHAIN_FILE=C:\vcpkg\scripts\buildsystems\vcpkg.cmake

# Build (Debug or Release)
cmake --build build --config Release

# Run tests
cd build
ctest --verbose  # or use --output-on-failure to only show failures
```

#### MSVC (Visual Studio)
**Prerequisites**
- Install [Visual Studio 2019 or later](https://visualstudio.microsoft.com/) with C++ development tools
- Install [CMake](https://cmake.org/download/)
- Install [vcpkg](https://vcpkg.io/en/getting-started.html) for dependencies

**Build Steps**
```powershell
# Clean previous build
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue

# Configure with MSVC
cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE=C:\vcpkg\scripts\buildsystems\vcpkg.cmake

# Build (Debug or Release)
cmake --build build --config Release

# Run tests
cd build

ctest -C Debug --verbose
# or
ctest -C Release --verbose
```

:::note
MSVC requires Visual Studio 2019 16.8 or later for C11 atomics support (`/experimental:c11atomics`). Both Debug and Release builds are fully supported.
:::

## Default Configuration Values

These constants define default values for column family configuration

```c
#define TDB_DEFAULT_MEMTABLE_FLUSH_SIZE            (64 * 1024 * 1024)
#define TDB_DEFAULT_MAX_SSTABLES                   128
#define TDB_DEFAULT_COMPACTION_THREADS             4
#define TDB_DEFAULT_BACKGROUND_COMPACTION_INTERVAL 1000000
#define TDB_DEFAULT_MAX_OPEN_FILE_HANDLES          1024
#define TDB_DEFAULT_SKIPLIST_LEVELS                12
#define TDB_DEFAULT_SKIPLIST_PROBABILITY           0.25
#define TDB_DEFAULT_BLOOM_FILTER_FP_RATE           0.01
#define TDB_DEFAULT_THREAD_POOL_SIZE               2
```

## Testing

After building, run the test suite to verify everything works

```bash
cd build
ctest --output-on-failure
```

Or run tests directly
```bash
./build/tidesdb_tests
```

## Benchmarking

TidesDB includes a comprehensive benchmark suite with fully configurable parameters.

### Quick Start

```bash
# Build and run with defaults
cmake -B build
cmake --build build
./build/tidesdb_bench
```

### Benchmark Operations

The benchmark tests the following operations
- Concurrent writes across multiple threads
- Concurrent reads across multiple threads
- Concurrent deletes across multiple threads
- Full scan from first to last key
- Full scan from last to first key
- Random seeks to specific keys

### Configuration Options

All benchmark parameters can be customized at build time using CMake variables

#### Operation Parameters

| Variable | Description | Default |
|----------|-------------|----------|
| `BENCH_NUM_OPERATIONS` | Number of put/get/delete operations | 10 |
| `BENCH_NUM_SEEK_OPS` | Number of iterator seek operations | 10 |
| `BENCH_KEY_SIZE` | Key size in bytes | 16 |
| `BENCH_VALUE_SIZE` | Value size in bytes | 100 |
| `BENCH_NUM_THREADS` | Number of concurrent threads | 2 |
| `BENCH_DEBUG` | Enable debug logging (0=off, 1=on) | 0 |
| `BENCH_KEY_PATTERN` | Key distribution pattern | "random" |
| `BENCH_CF_NAME` | Column family name | "benchmark_cf" |
| `BENCH_DB_PATH` | Database directory path | "benchmark_db" |

#### Column Family Configuration

| Variable | Description | Default |
|----------|-------------|----------|
| `BENCH_MEMTABLE_FLUSH_SIZE` | Memtable flush threshold (bytes) | 67108864 (64MB) |
| `BENCH_MAX_SSTABLES_BEFORE_COMPACTION` | Max SSTables before compaction | 128 |
| `BENCH_COMPACTION_THREADS` | Number of compaction threads | 4 |
| `BENCH_SL_MAX_LEVEL` | Skip list max level | 12 |
| `BENCH_SL_PROBABILITY` | Skip list probability | 0.25 |
| `BENCH_ENABLE_COMPRESSION` | Enable compression (0=off, 1=on) | 1 |
| `BENCH_COMPRESSION_ALGORITHM` | Compression algorithm | COMPRESS_LZ4 |
| `BENCH_ENABLE_BLOOM_FILTER` | Enable bloom filter (0=off, 1=on) | 1 |
| `BENCH_BLOOM_FILTER_FP_RATE` | Bloom filter false positive rate | 0.01 |
| `BENCH_ENABLE_BACKGROUND_COMPACTION` | Enable background compaction | 1 |
| `BENCH_BACKGROUND_COMPACTION_INTERVAL` | Compaction interval (μs) | 1000000 |
| `BENCH_ENABLE_BLOCK_INDEXES` | Enable block indexes | 1 |
| `BENCH_SYNC_MODE` | Sync mode | TDB_SYNC_NONE |
| `BENCH_COMPARATOR_NAME` | Key comparator | "memcmp" |

### Key Distribution Patterns

The benchmark supports three key distribution patterns to simulate different workloads:

#### Sequential
Keys are generated in order: `key_0000000000000000`, `key_0000000000000001`, etc.
- **Use case** · Testing sequential write/read performance
- **Best for** · Measuring raw throughput with optimal cache behavior

```bash
cmake -B build -DBENCH_KEY_PATTERN=sequential
```

#### Random (Default)
Keys are randomly generated alphanumeric strings.
- **Use case** · Testing random access patterns
- **Best for** · Simulating unpredictable workloads with poor cache locality

```bash
cmake -B build -DBENCH_KEY_PATTERN=random
```

#### Zipfian
Keys follow a Zipfian distribution (80/20 rule) where 80% of accesses go to 20% of keys.
- **Use case** · Simulating real-world workloads with "hot" keys
- **Best for** · Testing cache effectiveness and realistic access patterns

```bash
cmake -B build -DBENCH_KEY_PATTERN=zipfian
```

### Example Configurations

#### Small Workload (Default)
```bash
cmake -B build
cmake --build build
./build/tidesdb_bench
```

#### Medium Workload
```bash
cmake -B build \
  -DBENCH_NUM_OPERATIONS=1000 \
  -DBENCH_NUM_SEEK_OPS=100 \
  -DBENCH_NUM_THREADS=4 \
  -DBENCH_KEY_PATTERN=random

cmake --build build
./build/tidesdb_bench
```

#### Large Workload with Zipfian Distribution
```bash
cmake -B build \
  -DBENCH_NUM_OPERATIONS=100000 \
  -DBENCH_NUM_SEEK_OPS=10000 \
  -DBENCH_KEY_SIZE=32 \
  -DBENCH_VALUE_SIZE=512 \
  -DBENCH_NUM_THREADS=8 \
  -DBENCH_KEY_PATTERN=zipfian

cmake --build build
./build/tidesdb_bench
```

#### Stress Test with No Compression
```bash
cmake -B build \
  -DBENCH_NUM_OPERATIONS=10000000 \
  -DBENCH_KEY_SIZE=128 \
  -DBENCH_VALUE_SIZE=4096 \
  -DBENCH_NUM_THREADS=16 \
  -DBENCH_ENABLE_COMPRESSION=0 \
  -DBENCH_ENABLE_BLOOM_FILTER=0 \
  -DBENCH_KEY_PATTERN=sequential

cmake --build build
./build/tidesdb_bench
```

#### Testing Different Compression Algorithms
```bash
# LZ4 (fastest)
cmake -B build -DBENCH_COMPRESSION_ALGORITHM=COMPRESS_LZ4

# Snappy (balanced)
cmake -B build -DBENCH_COMPRESSION_ALGORITHM=COMPRESS_SNAPPY

# Zstandard (best compression)
cmake -B build -DBENCH_COMPRESSION_ALGORITHM=COMPRESS_ZSTD
```

### Benchmark Output

The benchmark displays
- Configuration summary (operations, threads, key pattern, features enabled)
- Operations per second for each operation type
- Total time taken for each operation
- Debug logs (if `enable_debug_logging` is enabled in config)

### Notes

- The benchmark creates a temporary database directory that is cleaned up before each run
- All operations use transactions for consistency
- Results may vary based on system resources, disk speed, and configuration
- For accurate results, run multiple times and average the results
- Disable debug logging for production-like performance measurements

### Getting Help

If you encounter issues not covered here:

1. Check the [GitHub Issues](https://github.com/tidesdb/tidesdb/issues) for similar problems
2. Review the [CI build logs](.github/workflows/) for working configurations
3. Open a new issue with
   - Your OS and version
   - Compiler and version
   - Full build output
   - CMake configuration command used

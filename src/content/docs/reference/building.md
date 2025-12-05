---
title: Building & Benchmarking TidesDB
description: How to build and benchmark TidesDB.
---

:::tip[Latest Version]
Check the [latest release](https://github.com/tidesdb/tidesdb/releases/latest) on GitHub for the current version.
:::

## Supported Platforms

TidesDB is tested and supported on the following platforms:

### Operating Systems
- **Linux** (x86, x64, PowerPC 32-bit)
- **macOS** (x64, ARM64/Apple Silicon)
- **Windows** (x86, x64 with MSVC or MinGW)
- **FreeBSD** 14.0+ (x64)
- **OpenBSD** 7.4+ (x64)
- **NetBSD** (x64)
- **DragonFlyBSD** (x64)
- **Illumos/OmniOS** (x64)
- **Solaris** (x64)

### Architectures
- **x86** (32-bit Intel/AMD)
- **x64** (64-bit Intel/AMD)
- **ARM64** (Apple Silicon, ARM v8)
- **PowerPC** (32-bit, cross-compiled)

### Compilers
- **GCC** 7.0+ (Linux, MinGW, cross-compilation)
- **Clang** 6.0+ (macOS, Linux, BSD)
- **MSVC** 2019 16.8+ (Windows with `/experimental:c11atomics`)

:::note[Platform-Specific Notes]
- **SunOS/Illumos** · Snappy compression is not available; TidesDB automatically disables it
- **PowerPC** · Requires `libatomic` for 64-bit atomic operations
- **32-bit architectures** · Require `libatomic` and multilib support
- **Windows** · Both MSVC and MinGW are fully supported with vcpkg for dependencies
:::

## Prerequisites

### Build Tools
- **CMake** 3.25 or higher
- **C Compiler** with C11 support:
  - GCC 7.0+ (Linux/MinGW)
  - Clang 6.0+ (macOS/Linux)
  - MSVC 2019 16.8+ (Windows with `/experimental:c11atomics`)

### Required Dependencies
TidesDB requires the following libraries for compression and threading:

- **[Snappy](https://github.com/google/snappy)** · Fast compression/decompression (not available on SunOS/Illumos)
- **[LZ4](https://github.com/lz4/lz4)** · Extremely fast compression
- **[Zstandard](https://github.com/facebook/zstd)** · High compression ratio
- **pthreads** · POSIX threads (Linux/macOS/BSD: built-in, Windows: PThreads4W via vcpkg)
- **libatomic** · Atomic operations library (required for 32-bit architectures like PowerPC)
- **C++ standard library** · Required by Snappy (automatically linked on Linux)

## Installing Dependencies

### Linux (Debian/Ubuntu)
```bash
# Install all dependencies
sudo apt update
sudo apt install -y cmake build-essential \
    libzstd-dev liblz4-dev libsnappy-dev
```

**Other Linux Distributions**
```bash
# Fedora/RHEL/CentOS
sudo dnf install cmake gcc libzstd-devel lz4-devel snappy-devel

# Arch Linux
sudo pacman -S cmake gcc zstd lz4 snappy

# 32-bit builds (e.g., x86, PowerPC)
sudo apt install -y gcc-multilib g++-multilib libatomic1
```

### macOS

TidesDB supports multiple package managers on macOS. By default, CMake will auto-detect Homebrew, but you can use MacPorts, pkgsrc, or Fink instead.

#### Option 1 · Homebrew (Default)
```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install dependencies
brew install cmake zstd lz4 snappy

# Build (Homebrew is auto-detected)
cmake -S . -B build
cmake --build build
```

#### Option 2 · MacPorts
```bash
# Install MacPorts from https://www.macports.org/install.php

# Install dependencies
sudo port install cmake zstd lz4 snappy

# Build with MacPorts prefix
cmake -S . -B build -DMACOS_DEPENDENCY_PREFIX=/opt/local -DUSE_HOMEBREW=OFF
cmake --build build
```

#### Option 3 · pkgsrc
```bash
# Install pkgsrc for macOS

# Install dependencies
pkgin install cmake zstd lz4 snappy

# Build with pkgsrc prefix
cmake -S . -B build -DMACOS_DEPENDENCY_PREFIX=/usr/pkg -DUSE_HOMEBREW=OFF
cmake --build build
```

#### Option 4 · Fink
```bash
# Install Fink from https://www.finkproject.org/

# Install dependencies
fink install cmake zstd lz4 snappy

# Build with Fink prefix
cmake -S . -B build -DMACOS_DEPENDENCY_PREFIX=/sw -DUSE_HOMEBREW=OFF
cmake --build build
```

:::note[Custom Paths]
If you have dependencies installed in a custom location, use:
```bash
cmake -S . -B build -DMACOS_DEPENDENCY_PREFIX=/your/custom/path -DUSE_HOMEBREW=OFF
```

Or set `CMAKE_PREFIX_PATH` environment variable:
```bash
export CMAKE_PREFIX_PATH=/your/custom/path
cmake -S . -B build -DUSE_HOMEBREW=OFF
```
:::

### Windows

**Using vcpkg (Recommended)**
```powershell
# Install vcpkg if not already installed
git clone https://github.com/Microsoft/vcpkg.git
cd vcpkg
.\bootstrap-vcpkg.bat

# Install dependencies
.\vcpkg install zstd:x64-windows lz4:x64-windows snappy:x64-windows pthreads:x64-windows

# For 32-bit builds
.\vcpkg install zstd:x86-windows lz4:x86-windows snappy:x86-windows pthreads:x86-windows
```

### BSD Variants

TidesDB supports FreeBSD, OpenBSD, NetBSD, and DragonFlyBSD with platform-specific package paths.

#### FreeBSD
```bash
# Install dependencies (packages in /usr/local)
sudo pkg install cmake pkgconf liblz4 zstd snappy

# Build
cmake -S . -B build
cmake --build build
```

#### OpenBSD
```bash
# Install dependencies (packages in /usr/local)
sudo pkg_add cmake gmake lz4 zstd snappy pkgconf

# Build
cmake -S . -B build
cmake --build build
```

#### NetBSD
```bash
# Install dependencies (packages in /usr/pkg)
sudo pkgin install cmake lz4 zstd snappy

# Build
cmake -S . -B build
cmake --build build
```

#### DragonFlyBSD
```bash
# Install dependencies (packages in /usr/local)
sudo pkg install cmake lz4 zstd snappy

# Build
cmake -S . -B build
cmake --build build
```

### Illumos/OmniOS/Solaris

**Note:** Snappy is not available in OmniOS repositories. TidesDB automatically disables Snappy compression on SunOS builds.

```bash
# Install dependencies (packages in /opt/ooce)
sudo pkg install cmake lz4 zstd

# Build
cmake -S . -B build
cmake --build build
```

### PowerPC (32-bit)

Cross-compilation for PowerPC requires building dependencies from source.

```bash
# Install cross-compilation toolchain
sudo apt install -y crossbuild-essential-powerpc \
  gcc-powerpc-linux-gnu g++-powerpc-linux-gnu \
  qemu-user-static

# Build dependencies from source (LZ4, Zstandard, Snappy)
# See .github/workflows/build_and_test_tidesdb.yml for complete build script

# Configure with PowerPC toolchain
cmake -S . -B build \
  -DCMAKE_C_COMPILER=powerpc-linux-gnu-gcc \
  -DCMAKE_CXX_COMPILER=powerpc-linux-gnu-g++ \
  -DCMAKE_SYSTEM_NAME=Linux \
  -DCMAKE_SYSTEM_PROCESSOR=powerpc

# Build
cmake --build build
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
| `BENCH_NUM_OPERATIONS` | Number of put/get/delete operations | 10000000 |
| `BENCH_NUM_SEEK_OPS` | Number of iterator seek operations | 100 |
| `BENCH_KEY_SIZE` | Key size in bytes | 16 |
| `BENCH_VALUE_SIZE` | Value size in bytes | 100 |
| `BENCH_NUM_THREADS` | Number of concurrent threads | 2 |
| `BENCH_DB_DEBUG` | Enable debug logging (0=off, 1=on) | 1 |
| `BENCH_KEY_PATTERN` | Key distribution pattern | "sequential" |
| `BENCH_CF_NAME` | Column family name | "benchmark_cf" |
| `BENCH_DB_PATH` | Directory path | "benchmark_db" |
| `BENCH_DB_FLUSH_POOL_THREADS` | Flush thread pool size | 2 |
| `BENCH_DB_COMPACTION_POOL_THREADS` | Compaction thread pool size | 2 |

#### Column Family Configuration

| Variable | Description | Default |
|----------|-------------|----------|
| `BENCH_WRITE_BUFFER_SIZE` | Memtable flush threshold (bytes) | 67108864 (64MB) |
| `BENCH_LEVEL_RATIO` | Level size multiplier | 10 |
| `BENCH_DIVIDING_LEVEL_OFFSET` | Compaction dividing level offset | 2 |
| `BENCH_MAX_LEVELS` | Maximum LSM levels | 7 |
| `BENCH_SKIP_LIST_MAX_LEVEL` | Skip list max level | 16 |
| `BENCH_SKIP_LIST_PROBABILITY` | Skip list probability | 0.25 |
| `BENCH_ENABLE_COMPRESSION` | Enable compression (0=off, 1=on) | 1 |
| `BENCH_COMPRESSION_ALGORITHM` | Compression algorithm | LZ4_COMPRESSION |
| `BENCH_ENABLE_BLOOM_FILTER` | Enable bloom filter (0=off, 1=on) | 1 |
| `BENCH_BLOOM_FILTER_FP_RATE` | Bloom filter false positive rate | 0.01 |
| `BENCH_ENABLE_BLOCK_INDEXES` | Enable block indexes | 1 |
| `BENCH_BLOCK_INDEX_SAMPLING_COUNT` | Index sampling ratio (1 in N keys) | 16 |
| `BENCH_SYNC_MODE` | Sync mode | TDB_SYNC_NONE |
| `BENCH_SYNC_INTERVAL_US` | Sync interval in microseconds (for TDB_SYNC_INTERVAL) | 128000 (128ms) |
| `BENCH_COMPARATOR_NAME` | Key comparator | "memcmp" |
| `BENCH_BLOCK_CACHE_SIZE` | Global block cache size (bytes) | 67108864 (64MB) |
| `BENCH_ISOLATION_LEVEL` | Transaction isolation level | TDB_ISOLATION_READ_COMMITTED |

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

- The benchmark creates a temporary storage directory that is cleaned up before each run
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

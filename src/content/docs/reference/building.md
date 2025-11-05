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

# Production build
rm -rf build && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DTIDESDB_WITH_SANITIZER=OFF -DTIDESDB_BUILD_TESTS=OFF
cmake --build build --config Release
cmake --install build

# On linux run ldconfig to update the shared library cache
ldconfig
```

### Windows

#### Option 1: MinGW-w64 (Recommended for Windows)
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

# Build
cmake --build build

# Run tests
cd build
ctest --verbose  # or use --output-on-failure to only show failures
```

#### Option 2: MSVC (Visual Studio)
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
cmake --build build --config Debug
# or
cmake --build build --config Release

# Run tests
cd build

ctest -C Debug --verbose
# or
ctest -C Release --verbose
```

**Note:** MSVC requires Visual Studio 2019 16.8 or later for C11 atomics support (`/experimental:c11atomics`). Both Debug and Release builds are fully supported.

## Default Configuration Values

These constants define default values for column family configuration:

```c
#define TDB_DEFAULT_MEMTABLE_FLUSH_SIZE            (64 * 1024 * 1024)
#define TDB_DEFAULT_MAX_SSTABLES                   512
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

---
title: Building TidesDB
description: How to build TidesDB.
---

Firstly you will need cmake and a C compiler. You also require the snappy, lz4, and zstd libraries.

### Dependencies
- [Snappy](https://github.com/google/snappy)
- [LZ4](https://github.com/lz4/lz4)
- [Zstandard](https://github.com/facebook/zstd)

### Linux
```bash
sudo apt install libzstd-dev
sudo apt install liblz4-dev
sudo apt install libsnappy-dev
```

### MacOS
```bash
brew install zstd
brew install lz4
brew install snappy
```

### Windows
Windows using vcpkg
```bash
vcpkg install zstd
vcpkg install lz4
vcpkg install snappy
```

Once you have everything set you can build using below commands.
```bash
cmake -S . -B build
cmake --build build
cmake --install build
```

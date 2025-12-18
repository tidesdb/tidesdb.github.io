---
title: "Seek and Range Query Performance · TidesDB v6.1.0 vs RocksDB v10.7.5"
description: "Deep dive into how block caching and index design deliver 4-9x faster seek operations."
---

*by Alex Gaetano Padula*

After optimizing TidesDB's seek and range query performance, I want to share the architectural decisions that led to some remarkable results. The benchmarks show TidesDB achieving 4.17x faster random seeks and 4.74x faster sequential seeks compared to RocksDB. This isn't luck or cherry-picked workloads - it's the result of specific design choices around block caching, index structures, and memory management.

You can download the raw benchmark report <a href="/benchmark_results_tdb610_rdb1075_range_seek1.txt" download>here</a>

You can find the **benchtool** source code <a href="https://github.com/tidesdb/benchtool" target="_blank">here</a> and run your own benchmarks!

## Test Environment

**Hardware**
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)
- Ubuntu 23.04 x86_64 6.2.0-39-generic

**Software Versions**
- **TidesDB v6.1.0**
- **RocksDB v10.7.5**
- GCC with -O3 optimization

**Test Configuration**
- **Sync Mode** · DISABLED (maximum performance)
- **Default Batch Size** · 1000 operations
- **Threads** · 8 concurrent threads
- **Key Size** · 16 bytes (unless specified)
- **Value Size** · 100 bytes (unless specified)

## The Seek Performance Problem

LSM-trees are traditionally optimized for writes, not point lookups. When you seek to a specific key, you potentially need to:

1. Check bloom filters across multiple SSTables
2. Load block indices from disk
3. Binary search the index to find the right block
4. Read and decompress the block
5. Binary search within the block for the key

Each disk I/O adds milliseconds. With dozens of SSTables across multiple levels, seeks can become prohibitively expensive. RocksDB addresses this with block caching and table caching, but there's room for improvement.

## The TidesDB Approach · Cache Everything That Matters

I made a fundamental architectural decision: **keep SSTable metadata in memory aggressively**. Not just temporarily, but until it's provably safe to free. This includes:

- **Block indices** · sparse sampled indices with prefix compression
- **Bloom filters** · 1% false positive rate, ~10 bits per key
- **Min/max keys** · enables range filtering without disk access
- **File handles** · kept open until memory pressure requires closing

The trade-off is explicit - use more memory to eliminate disk I/O on the critical path.

## Random Seek Performance · 4.17x Advantage

### The Numbers

**TidesDB (5M operations, 8 threads)**
- Throughput · 3.73M ops/sec
- Median latency · 2μs
- P99 latency · 5μs
- CPU utilization · 469%

**RocksDB (5M operations, 8 threads)**
- Throughput · 893K ops/sec
- Median latency · 8μs
- P99 latency · 17μs
- CPU utilization · 635%

### Why the 4.17x Difference?

**1. Cache-First Seek Path**

When TidesDB seeks to a key, the first operation is a cache lookup:

```c
tidesdb_ref_counted_block_t *rc_block = NULL;
tidesdb_klog_block_t *kb = tidesdb_cache_block_get(
    sst->db, cf_name, sst->klog_path, cursor->current_pos, &rc_block);
```

If the block is cached (which it often is for hot data), we get:
- Zero disk I/O
- Zero decompression overhead
- Direct memory access to the deserialized block
- Atomic reference counting prevents use-after-free

The cache hit path is **pure memory operations**. No syscalls, no decompression, no deserialization.

**2. Block Index in Memory**

Even on cache misses, TidesDB's block indices are already in memory. The seek path

1. Check bloom filter (memory) -> 99% of non-existent keys eliminated
2. Binary search block index (memory) → exact block position
3. Seek to block position (single disk I/O)
4. Read and cache block

RocksDB's approach requires loading the index from disk on cold starts, adding I/O overhead.

**3. Reference-Counted Block Ownership**

TidesDB uses atomic reference counting for cached blocks

```c
typedef struct {
    tidesdb_klog_block_t *block;
    atomic_int ref_count;
    size_t block_memory;
} tidesdb_ref_counted_block_t;
```

When a seek operation uses a cached block
- Increment refcount atomically
- Store reference in merge source
- Block stays alive until all references released
- No locks, no contention, no race conditions

This enables safe concurrent access without serialization overhead.

**4. Partitioned CLOCK Cache**

TidesDB's block cache uses
- 2 partitions per CPU core (reduces contention)
- CLOCK eviction (second-chance algorithm)
- Lock-free atomic operations
- Zero-copy API (no memcpy on hits)

With 8 cores, that's 16 independent cache partitions. Threads rarely contend for the same partition lock.

## Sequential Seek Performance · 4.74x Advantage

### The Numbers

**TidesDB**
- Throughput · 8.87M ops/sec
- Median latency · 1μs
- P99 latency · 2μs

**RocksDB**
- Throughput · 1.87M ops/sec
- Median latency · 3μs
- P99 latency · 7μs

### Why Sequential Seeks Are Even Faster

Sequential access patterns hit the same blocks repeatedly. Once a block is cached:

1. First seek in block · cache miss, load block (2-3μs)
2. Next 1000+ seeks in same block · cache hits (<1μs each)

The 8.87M ops/sec throughput means **sub-microsecond latency** for cached seeks. This is approaching memory bandwidth limits, not storage limits.

With TidesDB's block-level caching, sequential seeks become pure memory operations after the first block load.

## Zipfian Seek Performance · 5.25x Advantage

### The Numbers

**TidesDB**
- Throughput · 3.56M ops/sec
- Median latency · 1μs
- Database size · 10.13 MB (650K unique keys)

**RocksDB**
- Throughput · 679K ops/sec
- Median latency · 11μs
- Database size · 37.20 MB (656K unique keys)

### Why Zipfian Workloads Favor TidesDB

Zipfian distributions hit a small set of "hot" keys repeatedly (80/20 rule). TidesDB's aggressive caching means:

1. Hot keys' blocks stay in cache
2. Bloom filters eliminate cold key checks
3. DCA compacts obsolete versions aggressively
4. Database size shrinks (10MB vs 37MB)

The 5.25x advantage comes from **cache affinity**. Hot data stays hot, cold data gets compacted away.

## Range Query Performance · Competitive But Not Dominant

### Small Ranges (100 keys, Random Access)

**TidesDB**
- Throughput · 776K ops/sec
- Median latency · 0μs (sub-microsecond)
- P99 latency · 38μs
- CPU utilization · 463%

**RocksDB**
- Throughput · 322K ops/sec
- Median latency · 22μs
- P99 latency · 49μs
- CPU utilization · 713%

**Result** · TidesDB is 2.41x faster on small random ranges.

### Large Ranges (1000 keys, Random Access)

**TidesDB**
- Throughput · 48.6K ops/sec
- Median latency · 137μs
- P99 latency · 279μs
- CPU utilization · 725%

**RocksDB**
- Throughput · 43.6K ops/sec
- Median latency · 154μs
- P99 latency · 439μs
- CPU utilization · 771%

**Result** · TidesDB is 1.11x faster on large random ranges (roughly competitive).

### Sequential Ranges (100 keys)

**TidesDB**
- Throughput · 313K ops/sec
- Median latency · 15μs
- P99 latency · 67μs

**RocksDB**
- Throughput · 275K ops/sec
- Median latency · 20μs
- P99 latency · 55μs

**Result** · TidesDB is 1.14x faster on sequential ranges.

### Why Range Queries Are Different

Unlike point seeks, range queries require:
1. Seeking to the start key (benefits from TidesDB's fast seeks)
2. Iterating through N consecutive keys (both engines are similar)
3. Reading and deserializing values (I/O bound for large ranges)

The 2.41x advantage on small ranges comes from TidesDB's fast seek positioning. Once positioned, iteration speed is comparable between engines.

For large ranges (1000 keys), both engines spend most time iterating, not seeking. The 1.11x difference is within measurement variance—essentially a tie.

### The Honest Assessment

Range queries are **not** TidesDB's killer feature. The advantages are
- Small ranges · 2.41x faster (seek overhead dominates)
- Large ranges · Roughly competitive (iteration dominates)
- Sequential ranges · Slightly faster (1.14x)

If your workload is range-scan heavy with large ranges, TidesDB won't provide dramatic speedups. The real wins are in point seeks and small range queries where seek overhead matters.

## The Memory Trade-Off Quantified

### Random Seek Test (5M keys)

**TidesDB memory usage**
- Peak RSS · 851 MB
- Block cache · ~64 MB (default)
- SSTable metadata · ~787 MB (indices, bloom filters, structures)

**RocksDB memory usage**
- Peak RSS · 246 MB
- Block cache · ~200 MB (estimated)
- Metadata loaded on-demand

**The trade-off** · TidesDB uses 3.46x more memory for 4.17x faster seeks.

### Is This Worth It?

**For modern servers (128GB+ RAM):**
- 851 MB is negligible
- Sub-microsecond seek latency is transformative
- Memory is cheap, latency is expensive

**For memory-constrained environments:**
- 3.46x memory overhead matters
- Containers with 2GB limits
- Hundreds of database instances per server
- Edge devices with limited RAM

The decision depends on your deployment constraints.

## The Block Cache Architecture

### Why CLOCK Over LRU?

TidesDB uses CLOCK eviction instead of LRU because:

1. **Better concurrency** - no global LRU list to lock
2. **Simpler atomics** - just a reference bit per entry
3. **Good-enough approximation** - CLOCK is "LRU-ish" without the overhead
4. **Lock-free reads** - cache hits don't acquire locks

### Partitioning Strategy

With 2 partitions per CPU core:
- 8 cores = 16 partitions
- Hash key → partition (deterministic)
- Each partition has independent lock
- Contention reduced by 16x

### Reference Counting Lifecycle

```c
// Seek operation
rc_block = cache_get(...);  // Atomic increment
store_in_merge_source(rc_block);  // Transfer ownership
// ... use block ...
tidesdb_block_release(rc_block);  // Atomic decrement
```

Only when refcount reaches zero is the block freed. This prevents:
- Use-after-free during concurrent seeks
- Race conditions during compaction
- Need for complex locking schemes

## The Index Design

### Sparse Sampling with Prefix Compression

TidesDB's block indices use:
- **Sampling ratio** · 1:1 by default (every block sampled)
- **Prefix length** · 16 bytes for min/max keys
- **Position encoding** · Delta-encoded with varint compression

For 1M entries across 1000 blocks:
- Index size · ~50 KB (with compression)
- Lookup time · O(log n) binary search in memory
- Disk I/O · Zero (index is resident)

### Why This Matters

Traditional LSM-trees load indices on-demand:
1. Open SSTable file
2. Read index block from end of file
3. Parse and build in-memory structure
4. Now you can seek

TidesDB loads indices once during SSTable open and keeps them resident. Every subsequent seek benefits.

## The Bloom Filter Strategy

### Configuration

- **False positive rate** · 1% (configurable)
- **Bits per key** · ~10 bits
- **Memory cost** · 1.25 MB per 1M keys

### Why Keep Bloom Filters in Memory?

For a database with 10 levels and 100 SSTables
- Bloom filter memory · ~125 MB total
- Disk I/O eliminated · 99% of non-existent key checks
- Latency saved · 1-2ms per eliminated check

The memory cost is paid once. The I/O savings happen on every seek.

## CPU Utilization Analysis

### Random Seek Test

**TidesDB** · 469% CPU utilization
**RocksDB** · 635% CPU utilization

TidesDB achieves 4.17x higher throughput with **26% less CPU**. This suggests:

1. Lock-free architecture reduces contention
2. Cache hits eliminate decompression overhead
3. Memory-resident indices reduce syscall overhead
4. Atomic operations scale better than mutexes

RocksDB's higher CPU usage likely comes from:
- More cache misses -> more decompression
- More index loads -> more syscalls
- More lock contention -> more context switches

## What I Learned Optimizing Seeks

### 1. Cache Locality Trumps Everything

The difference between a cache hit (1μs) and cache miss (100μs+) is two orders of magnitude. Optimizing for cache hits matters more than optimizing cache misses.

### 2. Memory Is Cheaper Than You Think

Using 3.46x more memory for 4.17x faster seeks is an excellent trade on modern hardware. Don't optimize for 2011 constraints.

### 3. Reference Counting Provides Safety Without Locks

Atomic refcounts eliminate entire classes of race conditions. The overhead is negligible compared to the safety gained.

### 4. Block-Level Caching Beats Key-Level Caching

Caching entire blocks (1000+ keys) means one cache entry serves hundreds of seeks. The memory efficiency is better than key-level caches.

### 5. Partitioned Caches Scale Linearly

With 16 partitions, 8 threads rarely contend. Lock-free reads + partitioned writes = near-linear scaling.

### 6. Range Queries Need Different Optimizations

Point seeks benefit from aggressive caching. Range queries benefit from sequential I/O and prefetching. The same architecture doesn't optimize both equally.

### 7. Sub-Microsecond Latency Is Achievable

The 1μs median latency on sequential seeks shows that with proper caching, storage engine latency can approach memory latency. This opens up new use cases.

### 8. The Recovery Bug Was Critical

The initial benchmark failures revealed a race condition where transactions could start before database recovery completed. The fix (`wait_for_open` now checks both `is_open` and `!is_recovering`) was essential for correctness.

## When TidesDB's Seek Performance Matters

**Use TidesDB when**
- Point lookups are frequent (OLTP workloads)
- Small range queries (<100 keys) are common
- Latency matters more than memory (user-facing services)
- Working set fits in memory (hot data caching)
- Concurrent access is high (many threads seeking)
- Memory is available (servers with 64GB+ RAM)

**Use RocksDB when**
- Large range scans (1000+ keys) dominate your workload
- Memory is severely constrained (containers with 2GB limits)
- Working set exceeds available memory (cold data dominant)
- Predictable memory usage is required (strict limits)
- Operational maturity is critical (10+ years of production use)

## The Path Forward

### What Needs More Work

1. **Large range query optimization** · prefetching and sequential I/O hints
2. **Cold start performance** · how fast do caches warm up?
3. **Memory pressure behavior** · what happens when cache is full?
4. **Very large datasets** · does performance hold at 100M+ keys?
5. **Mixed workloads** · seeks + writes + range queries simultaneously

## Conclusion

The benchmark results show clear performance characteristics:

**Point Seeks (TidesDB's Strength)**
- Random seeks · 4.11x faster (3.34M vs 813K ops/sec)
- Sequential seeks · 4.58x faster (8.23M vs 1.80M ops/sec)
- Zipfian seeks · 6.31x faster (3.47M vs 550K ops/sec)

**Range Queries (Competitive)**
- Small ranges (100 keys) · 2.41x faster
- Large ranges (1000 keys) · 1.11x faster (essentially tied)
- Sequential ranges · 1.14x faster

The architectural decisions that enable this

1. **Aggressive metadata caching** · indices and bloom filters stay resident
2. **Reference-counted blocks** · safe concurrent access without locks
3. **Partitioned CLOCK cache** · scales with CPU cores
4. **Cache-first seek path** · eliminates disk I/O on hot data
5. **Block-level granularity** · one cache entry serves many keys

The memory trade-off (3.46x more RAM) is acceptable for modern servers. The latency improvement (4-6x faster seeks) is transformative for latency-sensitive workloads.

TidesDB makes different trade-offs than RocksDB. If your workload is **seek-heavy** with memory available, TidesDB delivers substantial advantages. If your workload is **range-scan-heavy** with large ranges, the benefits are minimal.


---

*Thanks for reading!*
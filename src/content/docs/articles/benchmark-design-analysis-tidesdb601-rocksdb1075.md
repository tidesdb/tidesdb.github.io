---
title: "Design Decisions and Performance Analysis of TidesDB v6.0.1 & RocksDB v10.7.5"
description: "Deep dive into architectural decisions and performance characteristics of TidesDB."
---

*by Alex Gaetano Padula*

*published on December 17th, 2025*

After spending the better part of two years building TidesDB from the ground up, I want to share some insights about the architectural decisions that led to the performance characteristics you're seeing in these benchmarks. This isn't just about being "fast" - it's about understanding what trade-offs you're making and why.

You can download the raw benchtool report <a href="/benchmark_results_tdb601_rdb1075_1.txt" download>here</a>

You can find the **benchtool** source code <a href="https://github.com/tidesdb/benchtool" target="_blank">here</a> and run your own benchmarks!


## Why I Built TidesDB

I started this project because I wanted to understand LSM-trees at a fundamental level. Not "how to use RocksDB" but "how do LSM-trees actually work, and can we do better?" Reading papers like O'Neil's original LSM-tree paper (1996), WiscKey (2016), and Spooky (2022) convinced me that there was room for improvement if you were willing to commit to certain architectural decisions from day one.

The goal wasn't to build "RocksDB but faster" - it was to build a storage engine that made different trade-offs, ones that make sense for modern hardware (lots of RAM, fast SSDs, many CPU cores) rather than hardware from 2011-2015 when LevelDB's and RocksDB's architecture was established.

## The Lock-Free Decision

The single biggest architectural choice in TidesDB is that **everything is almost lock-free**

- Skip list memtable · lock-free CAS operations
- WAL group commit · atomic buffer reservation with lock-free leader election
- Comparator registry · atomic copy-on-write pattern
- Block cache · CLOCK eviction with partitioned structure (2 partitions per CPU core)
- Transaction buffer · atomic slot states with generation counters
- SSTable reference counting · atomic operations throughout

Above is just the tip of the iceberg.

This isn't easy. Lock-free programming is notoriously difficult to get right. But here's why I committed to it.

**Modern CPUs have many cores**. My test machine has 8 cores, servers have 64+. When you use mutexes, you serialize operations at the lock. With 8 threads hitting the same mutex, you get 1/8th the theoretical throughput. With lock-free atomic operations, you get near-linear scaling.

The 3.28x advantage on sequential writes with 8 threads? That's the lock-free architecture paying off. Every operation uses atomic CAS instead of mutexes. No thread blocks waiting for a lock. They either succeed or retry, but they never sleep.

The cost · Lock-free code is harder to debug, harder to reason about, and harder to maintain. You have to worry about ABA problems (solved with generation counters), memory ordering (acquire/release semantics), and spurious CAS failures. But for a solo project where I control the entire codebase, I can commit to this complexity.

## Spooky Compaction + Dynamic Capacity Adaptation

RocksDB uses leveled compaction with fixed ratios. I implemented Spooky (Dayan et al., 2022) which uses three different merge strategies:

1. **Full preemptive merge** - compact levels 1 to q when capacity allows
2. **Dividing merge** - compact to level X (the dividing level)
3. **Partitioned merge** - compact within lower levels, creating non-overlapping partitions

As well as **Dynamic Capacity Adaptation (DCA)**. After every compaction, DCA recalibrates level capacities based on actual data distribution:

```
C_i = N_L / T^(L-i)
```

Where `N_L` is the current size of the largest level, not some theoretical maximum. This means capacities adapt to reality - if you write 200GB but the largest level is only 64GB, DCA shrinks upper level capacities proportionally.

Why this matters · Look at the Zipfian results. 10MB database for TidesDB vs 61MB for RocksDB - that's 6.1x smaller. Zipfian workloads hit the same keys repeatedly. Without DCA, you'd have levels sized for theoretical capacity even though only a fraction is actually used. With DCA, capacities tighten based on actual data, triggering more frequent compaction of obsolete versions.

The 1.08x-1.12x write amplification across workloads isn't luck - it's Spooky + DCA working together. RocksDB at 1.33-1.50x is good, but fixed ratios can't adapt like DCA does.

## WiscKey-Style Key-Value Separation

TidesDB separates keys from values. Every SSTable has two files:
- **klog** (key log) · sorted keys with metadata and small inline values
- **vlog** (value log) · large values referenced by offset

For the 4KB value test, this is why TidesDB hits 319K ops/sec vs RocksDB's 143K (2.23x faster) with 1.05x write amplification. When you compact large values in a standard LSM-tree, you rewrite entire 4KB blobs even if the keys don't change. With separation, compaction only moves key references - the values stay in the vlog.

The trade-off · Added complexity. You have two files per SSTable, reference counting gets more involved, and recovery is more complex. But for workloads with varied value sizes, the performance and efficiency gains are worth it.

## The Read Performance Story (And Why Memory Usage Is Higher)

People are surprised TidesDB is 1.76x faster on random reads while also being faster on writes. LSM-trees are supposed to sacrifice reads for writes. So what's happening?

The benchmarks show TidesDB using 1,722 MB vs RocksDB's 332 MB during random reads (5.2x more). This isn't bloat or inefficiency - it's a deliberate architectural choice, and understanding why requires understanding how TidesDB manages resources.

### How TidesDB Manages SSTables in Memory

**The key insight  TidesDB keeps SSTable metadata in memory until it's safe to free.**

When you open an SSTable for reading, TidesDB:
1. Opens the file handles (klog + vlog)
2. Loads the compact block index into memory (~2.5MB for 1M entries)
3. Loads the bloom filter into memory
4. Stores min/max keys
5. Sets up atomic reference counting
6. Updates `last_access_time` atomically

**Here's the critical part · The SSTable structure stays in memory until the reference count reaches zero.** This includes:
- Min/max keys (enables range filtering without disk access)
- Bloom filter (enables false-positive filtering without disk access)
- Compact block index (enables direct seeks to specific blocks)
- File handles (when open)
- Metadata (sizes, counts, compression info)

A background reaper thread runs every 100ms checking if we've exceeded `max_open_sstables` (default 512). When the limit is reached:

1. Scans all SSTables to find candidates
2. Filters for SSTables with `refcount == 1` (not actively in use)
3. Sorts candidates by `last_access_time` (oldest first)
4. Closes 25% of the oldest SSTables' **file handles only**
5. **But the metadata, bloom filters, and indices stay in memory**

This is the key design decision. Even after file handles close, the SSTable metadata remains allocated. When you need to read that SSTable again:

1. Check min/max keys (already in memory) → might skip entirely
2. Check bloom filter (already in memory) → might skip entirely  
3. If needed, reopen file handles (fast, no index/filter rebuild)
4. Binary search block index (already in memory) → seek to exact block
5. Read block, increment refcount
6. When done, decrement refcount

### Why This Design Choice?

**Three reasons**

**1. Compact Block Indices**

My block indices use sparse sampling (configurable via `index_sample_ratio`, default is 1 which samples every block) with prefix compression. For 1M entries, the default configuration (ratio 1:1) keeps the full index in memory. If you configure a higher sampling ratio like 16:1, the index would be only ~2.5MB instead of 32MB, trading some seek precision for memory savings. These indices are small enough to keep in memory permanently without significant cost.

The format is:
- Min key prefix (16 bytes)
- Max key prefix (16 bytes)
- File position (8 bytes, delta-encoded with varint compression)

With sparse sampling ratios (configurable via `index_sample_ratio`), you can reduce index size significantly. The default ratio of 1:1 samples every block for maximum seek precision. Keeping these in memory means every read can directly seek to the right block without rebuilding the index from disk.

**2. Bloom Filters**

Bloom filters are critical for LSM-trees. Without them, you'd check every SSTable for keys that don't exist. With them, you get ~99% false-positive filtering.

The cost is memory - typically 10 bits per key. For 1M keys, that's 1.25MB per SSTable. In a database with 10 levels and multiple SSTables per level, bloom filters can add up to 100-200MB.

But here's the trade-off · Keeping bloom filters in memory means you can eliminate 99% of unnecessary SSTable checks **without any disk I/O**. The memory cost is paid once; the disk I/O savings happen on every read.

**3. Reference Counting Safety**

This is the part people often miss. **TidesDB uses atomic reference counting to manage SSTable lifecycle safely.**

When a read operation accesses an SSTable:
```c
tidesdb_sstable_ref(sstable);     // Atomic increment
// ... do read operations ...
tidesdb_sstable_unref(sstable);   // Atomic decrement
```

Only when `refcount` reaches zero is the SSTable actually freed. This prevents use-after-free bugs during compaction.

Here's the scenario
1. Thread A is reading from SSTable X (refcount = 1)
2. Compaction decides to delete SSTable X (obsolete after merge)
3. Compaction marks SSTable X for deletion but refcount > 0
4. Thread A completes read, calls unref, refcount → 0
5. **Now it's safe to free · SSTable X is deallocated**

Without this reference counting, you'd have race conditions:
- Thread A reading → compaction deletes SSTable → Thread A crashes (use-after-free)
- Solution · complicated locking or delayed deletion with uncertainty

With reference counting, it's simple and safe · **The SSTable stays in memory until nothing is using it.**

### The Read Performance Impact

This design choice produces the 1.76x read advantage and 3μs median latency:

**Without metadata in memory** (RocksDB's approach):
1. Open SSTable file
2. Read and parse bloom filter from disk (I/O)
3. Check bloom filter → false positive or continue
4. Read and parse block index from disk (I/O)
5. Binary search index to find block
6. Seek to block position
7. Read block (I/O)

**With metadata in memory** (TidesDB's approach):
1. Check min/max keys (memory) -> might skip SSTable entirely
2. Check bloom filter (memory) -> 99% of non-existent keys eliminated
3. Binary search block index (memory) -> exact block position
4. If file closed, reopen (fast, no index/filter rebuild)
5. Read block (I/O) or hit CLOCK cache (memory)

The difference · TidesDB eliminates 2-3 disk I/O operations per read by keeping metadata in memory. For random reads, this is the difference between 3μs and 5μs median latency.

### The Memory Trade-off Quantified

For a database with 10M keys across multiple SSTables

**TidesDB memory usage:**
- Block indices · ~25MB (sparse sampling)
- Bloom filters · ~125MB (10 bits per key)
- Min/max keys · ~5MB  
- SSTable structures · ~20MB
- Block cache · ~1.5GB (configurable)
- **Total · ~1.7GB**

**RocksDB memory usage:**
- Block cache only · ~300MB (conservative)
- Indices/filters loaded on-demand · disk I/O
- **Total · ~300MB**

The 5.2x difference comes from TidesDB keeping indices and bloom filters resident, while RocksDB loads them on-demand.

**The trade-off is explicit:**
- Use 5x more memory
- Get 1.76x faster reads
- Eliminate 99% of unnecessary SSTable checks (bloom filters)
- Eliminate index rebuild overhead (cached indices)
- Eliminate 2-3 disk I/O operations per read

For modern servers with 128GB+ RAM, using 1.7GB to accelerate reads is an excellent trade. For memory-constrained environments (containers with 2GB limits, edge devices, hundreds of instances per server), this matters.

### The Block CLOCK Cache

On top of metadata caching, TidesDB has an aggressive block cache:

- **Partitioned design** · 2 partitions per CPU core (reduces contention)
- **CLOCK eviction** · Second-chance algorithm, better concurrency than LRU
- **Block-level granularity** · Caches entire deserialized klog blocks
- **Zero-copy API** · No memcpy on cache hits, just reference bit updates
- **Lock-free** · All operations use atomic CAS

One cached block serves hundreds of keys. When you read key X and it's in block B, the entire block B gets cached. Future reads to keys in block B are pure memory accesses.

This is why iteration is so fast (8.91M ops/sec) - sequential access patterns hit the same blocks repeatedly, all served from cache.

## The Batch=10,000 Problem

The benchmarks show TidesDB collapsing at batch size 10,000 (659K ops/sec vs RocksDB's 1.33M). This is the one result I'm not happy with, and I'll explain what's happening.

At batch=10,000 with 8 threads, you have 80,000 operations in flight simultaneously. The problem is in the lock-free skip list:

Lock-free skip lists work great under normal contention. CAS operations succeed most of the time, failed CAS operations retry, everything scales well. But at extreme contention (80,000 concurrent insertions), CAS failures increase exponentially. Threads spin retrying, burning CPU without making progress.

Additionally, the memtable isn't sized for 80,000 operations at once. When it fills, writes block waiting for flush. The combination of CAS contention + memtable pressure creates a performance cliff.

**This is a known trade-off** · Lock-free data structures have excellent average-case performance but can have pathological worst-cases under extreme contention. Traditional locks would perform better here - threads would queue, but they'd eventually make progress without spinning.

**My assessment** · For 99% of workloads, batches don't exceed 1,000. TidesDB's sweet spot (10-100) is well-aligned with typical usage. If you're bulk loading with 10,000+ operation batches, RocksDB will outperform. I'm okay with this trade-off - I optimized for common cases, not extremes.

## The Delete and Space Reclamation Story

TidesDB achieves 0.00 MB database size after deleting all 5M records. RocksDB retains 63.77 MB. This reveals different compaction philosophies.

**TidesDB's approach** · When tombstones accumulate, compaction runs aggressively. Tombstones + deleted data are eliminated together, returning storage to zero. This happens automatically as part of the normal compaction cycle triggered by DCA.

**RocksDB's approach** · Tombstones are written, but space reclamation waits for manual compaction. This is more predictable (no surprise compaction I/O during deletes) but requires operational awareness.

Neither is "wrong" - they optimize for different priorities. I chose immediate cleanup because:
1. Applications with retention policies (logs, time-series, caches) benefit
2. No manual compaction operations needed
3. Storage usage reflects actual data, not data + garbage

The cost is occasional compaction I/O during delete-heavy periods. I think this is acceptable for the benefit of automatic space reclamation.

## Iteration Performance · Why It's So Fast

TidesDB consistently shows 1.55-2.17x faster iteration across workloads:
- Sequential writes · 8.22M vs 5.30M ops/sec
- Random reads · 8.91M vs 4.88M ops/sec  
- Large values · 961K vs 444K ops/sec

**This comes from storage layout:**

1. **Key-value separation** · Iteration only reads the klog (keys + metadata), not values. For 4KB values, this is a huge win.

2. **Compact block format** · Each block is compressed, has a simple footer with count, and stores entries sequentially. No complex skip pointers or internal fragmentation.

3. **Block caching** · CLOCK cache keeps hot blocks in memory. Iteration hits cache repeatedly for sequential access patterns.

4. **No version traversal** · Because DCA and Spooky compact aggressively, there are fewer obsolete versions. Iteration sees mostly current data.

The 8.91M ops/sec random read iteration is particularly notable - that's with a fragmented dataset. The combination of cached block indices, efficient seeking, and compact storage makes even random-order iteration fast.

## What I Learned Building This

**1. Lock-free is worth it if you commit fully.** Half-lock-free, half-mutex code is worse than all-mutex. The 3.28x sequential write advantage comes from consistent lock-free design throughout.

**2. Research papers work in production.** Spooky (2022), WiscKey (2016), SSI (2008) - all of these are implementable. The gap between research and practice is smaller than people think.

**3. Memory trade-offs are acceptable.** Using 5.2x more memory for 1.76x faster reads is a good trade on modern hardware. Don't optimize for 2011 constraints.

**4. Reference counting provides safety without locks.** Atomic refcounts + careful lifecycle management eliminate entire classes of race conditions. The SSTable metadata staying in memory until safe to free is both simpler and safer than manual locking schemes.

**5. Compaction strategy matters more than people realize.** The difference between 1.08x and 1.50x write amplification compounds over billions of operations. DCA's adaptive behavior produces consistently low write amp.

**6. Solo development has advantages.** I can make radical architectural commitments (lock-free everywhere, aggressive caching, reference-counted resources) that would be risky in team settings. No design-by-committee, no legacy compatibility, no organizational politics.

**7. Extreme cases reveal limits.** The batch=10,000 problem taught me where lock-free algorithms saturate. Knowing your limits is as important as knowing your strengths.

## Benchmarking Honesty

These benchmarks show TidesDB winning most scenarios. But I want to be clear about what they don't show:

**What's not tested**
- Production stability over months/years
- Recovery time after crashes (WAL replay with reference counting)
- Behavior under extreme memory pressure (what happens when cache is full?)
- Multi-column-family resource sharing
- Performance with hundreds of concurrent column families
- Edge cases (corruption, disk full, SSD stalls, reference count leaks)

**What needs longer validation**
- Compaction behavior at billions of operations
- Read performance when working set exceeds cache
- Write latency during major compaction
- Memory usage patterns over extended runtime
- Reference counting overhead at extreme scale

I'm confident in TidesDB's architecture and the performance results are real, not artifacts. But production maturity comes from time and diverse workloads. RocksDB has 10+ years of battle-testing; TidesDB is newer.

## When to Choose TidesDB

**Use TidesDB when**
- Write throughput is critical (1.5-3.3x faster)
- Space efficiency saves money (1.2-6.1x smaller databases)
- Both read and write performance matter (balanced optimization)
- **Memory is available** (5.2x more memory for reads is acceptable)
- Access patterns have locality (Zipfian results show 6.1x space advantage)
- Batch sizes are moderate (10-1,000 operations)
- Immediate space reclamation is valuable (delete-heavy workloads)
- You want low write amplification (SSD longevity, I/O efficiency)
- Read latency matters (3μs vs 5μs median)

**Use RocksDB when**
- **Resource constraints are strict and concurrency is minimal** 
- Predictability matters more than peak performance
- Very large batches are common (>5,000 operations per batch)
- Operational maturity is required (extensive tooling, community support)
- Risk aversion is high (proven at massive scale for 10+ years)
- You need ecosystem features (backup tools, replication, admin utilities)
- Resource limits are tight (containers with 2GB RAM, hundreds of instances)

## Design Philosophy

TidesDB makes trade-offs for modern hardware:
- **Lock-free everywhere** -> scales with CPU cores
- **Memory for performance** -> uses RAM to accelerate reads (keeps metadata resident)
- **Aggressive caching** -> keeps hot data in memory longer (block cache + metadata)
- **Reference counting** -> safe resource management without locks
- **Immediate cleanup** -> automatic space reclamation
- **Research-backed algorithms** -> Spooky, WiscKey, SSI
- **Adaptive behavior** -> DCA recalibrates based on actual data

These aren't universal truths - they're choices optimized for servers with many cores, lots of RAM, and fast SSDs. If your constraints are different (embedded systems, memory-limited containers, extreme scale with thousands of databases), different trade-offs may be better.

## The Path Forward

The performance is there. The architecture is sound. Now it's about proving operational maturity through diverse production use really.

## Conclusion

Building TidesDB taught me that fundamental architectural decisions matter more than incremental optimizations. Lock-free concurrency, adaptive compaction, memory trade-offs for performance, reference-counted resources, and research-backed algorithms compound to produce the 1.5-3.3x write advantages and 1.76x read advantages you see in benchmarks.

The 5.2x memory usage isn't bloat - it's keeping SSTable metadata in memory until it's safe to free, enabled by atomic reference counting. The bloom filters, compact indices, and min/max keys stay resident, eliminating 2-3 disk I/O operations per read. The batch=10,000 problem isn't a flaw - it's a known trade-off of lock-free algorithms under extreme contention.

Every storage engine makes trade-offs. TidesDB makes trade-offs for modern hardware, typical workloads, and performance-first priorities. If those align with your needs, TidesDB offers compelling advantages. If your constraints differ, other systems may be better.

The goal was never "beat RocksDB" per se - it was "understand LSM-trees deeply and make different trade-offs." The benchmarks suggest those trade-offs work.

---

*Thanks for reading!*
---
title: "1GB Value Observations TidesDB 7 & RocksDB 10"
description: "An article on observations of 1GB value benchmarks between TidesDB 7 & RocksDB 10"
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-budget-bizar-92378004-16644281.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-budget-bizar-92378004-16644281.jpg
---

<div class="article-image">

![1GB Value Observations TidesDB 7 & RocksDB 10](/pexels-budget-bizar-92378004-16644281.jpg)

</div>

*by Alex Gaetano Padula*

*published on January 2nd, 2026*

This question comes up often on the TidesDB Discord, how do these engines handle very large values? In this article, I benchmark 1GB values against TidesDB 7 and RocksDB 10. The first run uses default configurations for both engines; The second increases the memtable write buffer and cache to 3GB each.

One recommendation before diving in, if possible, break up large values into smaller chunks with keys that sort near each other. This improves locality and reduces fragmentation. For example, a multi-gigabyte video file could be stored as sequential chunks in TidesDB, then read back in order for streaming playback. In practice, chunking is almost always the better approach, really these benchmarks represent an _extreme_ edge case.

# Test Configuration

All benchmarks were executed with sync mode disabled to measure maximum throughput potential. 

**We recommend you benchmark your own use case to determine which storage engine is best for your needs!**


**Hardware**
- Intel Core i7-11700K (8 cores, 16 threads) @ 4.9GHz
- 48GB DDR4
- Western Digital 500GB WD Blue 3D NAND Internal PC SSD (SATA)
- Ubuntu 23.04 x86_64 6.2.0-39-generic

**Software Versions**
- **TidesDB v7.0.10**
- **RocksDB v10.7.5**
- GCC with -O3 optimization

You can download the raw benchtool report for first run wih 64mb memtable write buffer and 64mb cache <a href="/large_value_benchmark_1gb_results_tdb7_rdb10_1.txt" download>here</a>

You can download the raw benchtool report for second run with 3GB memtable write buffer and 3GB cache <a href="/large_value_benchmark_1gb_results_tdb7_rdb10_2.txt" download>here</a>

You can download the raw benchtool report for second run with 3GB memtable write buffer and 3GB cache with RocksDB utilizing BlobDB <a href="/large_value_benchmark_1gb_results_tdb7_rdb10_3.txt" download>here</a>

You can find the **benchtool** source code <a href="https://github.com/tidesdb/benchtool" target="_blank">here</a> and run your own benchmarks!


## Findings

### Run 1 · Default Configuration (64MB memtable/cache)

| Operation | TidesDB | RocksDB | Winner |
|-----------|---------|---------|--------|
| **PUT** | 0.28 ops/sec | 0.44 ops/sec | RocksDB (1.57x) |
| **GET** | 1.49 ops/sec | 1.07 ops/sec | TidesDB (1.39x) |
| **RANGE** | 0.19 ops/sec | 0.84 ops/sec | RocksDB (4.4x) |

**Resource Usage (PUT)**

| Metric | TidesDB | RocksDB | Winner |
|--------|---------|---------|--------|
| Peak RSS | 1,059 MB | 6,166 MB | TidesDB (5.8x less) |
| Database Size | 40.16 MB | 1,060 MB | TidesDB (26x smaller) |
| Write Amplification | 1.01x | 1.00x | Similar |

**Resource Usage (GET)**

| Metric | TidesDB | RocksDB | Winner |
|--------|---------|---------|--------|
| Peak RSS | 25 MB | 3,095 MB | TidesDB (124x less) |
| Avg Latency | 621ms | 912ms | TidesDB (32% lower) |

### Run 2 · Optimized Configuration (3GB memtable/cache)

| Operation | TidesDB | RocksDB | Winner |
|-----------|---------|---------|--------|
| **PUT** | 0.19 ops/sec | 0.46 ops/sec | RocksDB (2.4x) |
| **GET** | 1.55 ops/sec | 1.04 ops/sec | TidesDB (1.49x) |
| **RANGE** | 0.18 ops/sec | 0.85 ops/sec | RocksDB (4.7x) |

**Resource Usage (PUT)**

| Metric | TidesDB | RocksDB | Winner |
|--------|---------|---------|--------|
| Peak RSS | 6,165 MB | 6,166 MB | Similar |
| Database Size | 40.16 MB | 1,060 MB | TidesDB (26x smaller) |
| Write Amplification | 1.00x | 1.00x | Similar |

**Resource Usage (GET)**

| Metric | TidesDB | RocksDB | Winner |
|--------|---------|---------|--------|
| Peak RSS | 25 MB | 3,095 MB | TidesDB (124x less) |
| Avg Latency | 601ms | 925ms | TidesDB (35% lower) |

### Run 3 · RocksDB with BlobDB Enabled (3GB memtable/cache)

RocksDB's BlobDB is designed specifically for large values - it separates keys from values similar to TidesDB's klog/vlog approach. This run tests whether BlobDB closes the gap.

| Operation | TidesDB | RocksDB BlobDB | Winner |
|-----------|---------|----------------|--------|
| **PUT** | 0.20 ops/sec | 0.44 ops/sec | RocksDB (2.2x) |
| **GET** | 1.54 ops/sec | 0.95 ops/sec | TidesDB (1.62x) |
| **RANGE** | 0.18 ops/sec | 0.59 ops/sec | RocksDB (3.3x) |

**Resource Usage (PUT)**

| Metric | TidesDB | RocksDB BlobDB | Winner |
|--------|---------|----------------|--------|
| Peak RSS | 6,182 MB | 1,046 MB | RocksDB (5.9x less) |
| Database Size | 40.16 MB | 1,060 MB | TidesDB (26x smaller) |
| Write Amplification | 1.00x | 1.00x | Similar |

**Resource Usage (GET)**

| Metric | TidesDB | RocksDB BlobDB | Winner |
|--------|---------|----------------|--------|
| Peak RSS | 25 MB | 27 MB | Similar |
| Avg Latency | 605ms | 1,006ms | TidesDB (40% lower) |

**BlobDB Observations**

With BlobDB enabled, RocksDB's memory usage during reads drops dramatically from 3,095 MB to just 27 MB - now matching TidesDB's efficiency. This confirms that key-value separation is the key architectural decision for large value handling.

However, TidesDB still wins on GET throughput (1.62x faster) and latency (40% lower). RocksDB BlobDB also uses significantly less memory during writes (1,046 MB vs 6,182 MB), though it still produces a 26x larger database.

### Key Observations

**RocksDB wins on writes and range scans with 1GB values.** 

RocksDB's write path seems to be optimized for large values but at quite a cost - it achieves 1.57-2.4x faster PUT throughput. For range queries, RocksDB is 3.3-4.7x faster (BlobDB narrows the gap slightly). 

**TidesDB wins on point reads - even against BlobDB.** 

TidesDB achieves 1.39-1.62x faster GET operations with 32-40% lower latency across all configurations. Even when RocksDB uses BlobDB (its own key-value separation), TidesDB's read path remains significantly faster. The WiscKey-style klog/vlog separation pays off here - keys are stored separately from values, so finding the right key is fast even when values are massive.

**BlobDB levels the memory playing field for reads.** 

Without BlobDB, RocksDB uses 3,095 MB during GET operations vs TidesDB's 25 MB (124x difference). With BlobDB enabled, RocksDB drops to 27 MB - essentially matching TidesDB. This proves key-value separation is the critical architectural decision for large value handling. TidesDB doesn't need to load entire 1GB values into memory to find them; it can locate the key first, then stream the value.

**TidesDB produces 26x smaller databases.** 

TidesDB's database size is 40.16 MB vs RocksDB's 1,060 MB. This is due to TidesDB's aggressive compaction and space reclamation. With 10 x 1GB values (10GB total data), TidesDB's 40MB footprint shows excellent space efficiency!

**Larger memtables hurt TidesDB's write performance.** 

Interestingly, increasing the memtable from 64MB to 3GB actually slowed TidesDB's writes (0.28 -> 0.19 ops/sec). This is because TidesDB's memtable is already well-tuned for default sizes, and larger buffers introduce a bit of overhead without benefit for this workload.

**Latency variance is higher with 1GB values.** 

TidesDB's p95 latency for writes reached 5-10 seconds in some cases, while RocksDB stayed more consistent at 1.3-2.2 seconds. Large values amplify key-value seperation inefficiencies in the write path.

## Conclusion

For 1GB values, RocksDB is the better choice for write-heavy and range-scan workloads, while TidesDB excels at point reads with dramatically lower memory usage.

If your use case involves storing very large values (videos, images, large documents) and you primarily read them by key, TidesDB offers quite compelling advantages at 1.4-1.5x faster reads, 124x less memory during reads, and 26x smaller database footprint.

However, if you're writing large values frequently or scanning ranges of them, RocksDB's mature large-value handling gives it a clear edge.

**My recommendation?** 

If you must store 1GB values, consider chunking them into smaller pieces (say, 4MB chunks) with sequential keys. This plays to TidesDB's strengths in write throughput and iteration while maintaining the ability to reconstruct the full value. Both engines will perform better with smaller, more manageable value sizes.

These results show general patterns, but your specific access patterns, hardware, and configuration will determine which engine performs best for you.

## Why TidesDB Excels at Large Value Reads?

Diving into the TidesDB source code reveals the architectural decisions that drive these benchmark results.

**The klog/vlog Separation**

TidesDB implements a WiscKey-inspired design with separate storage for keys and large values. The `tidesdb_klog_entry_t` structure stores key metadata (flags, sizes, TTL, sequence number) alongside a `vlog_offset` field that points to where large values live on disk. When a value exceeds the configurable `klog_value_threshold` (default 512 bytes), it's written to a separate value log (vlog) file rather than being stored inline with the key. This is the core reason TidesDB uses only 25MB of RAM during GET operations versus RocksDB's 3GB - the engine can locate keys without loading massive values into memory.

```c
if (value_size >= sst->config->klog_value_threshold && !deleted && value)
{
    /* write value directly as a block to vlog */
    block_manager_block_t *vlog_block = block_manager_block_create(final_size, final_data);
    ...
    kv->entry.vlog_offset = (uint64_t)block_offset;
}
```

During reads, TidesDB first searches the compact klog using bloom filters and block indexes to find the key, then performs a single targeted `pread()` to fetch the value from its vlog offset. This two-phase approach means the read path touches minimal data until the exact value location is known.

**Aggressive Compression on Large Values**

Each 1GB value is individually compressed (LZ4 by default) before being written to the vlog. The `compress_data()` function wraps the value with an 8-byte size header for decompression, and the block manager stores it with checksums for integrity. This per-value compression explains the 26x smaller database footprint - highly compressible data (like the benchmark's test values) shrinks dramatically, while RocksDB's block-based compression operates on mixed key-value blocks that may not compress as efficiently for this workload.

**The Write Path Trade-off**

The benchmark's finding that larger memtables hurt TidesDB's write performance makes sense when examining the flush path. During memtable flush, TidesDB iterates through all entries, compresses large values individually, writes them to vlog, then serializes klog blocks with compression. For 1GB values, this means each write triggers a full compression pass on a gigabyte of data. The default 64MB memtable forces more frequent but smaller flushes, while a 3GB memtable accumulates more data before triggering this expensive operation - but the compression cost per value remains constant regardless of memtable size.

*Thanks for reading!*

---

**Links**
- GitHub · https://github.com/tidesdb/tidesdb
- Design deep-dive · https://tidesdb.com/getting-started/how-does-tidesdb-work
- RocksDB · https://github.com/facebook/rocksdb
- RocksDB BlobDB · https://github.com/facebook/rocksdb/wiki/BlobDB

Join the TidesDB Discord for more updates and discussions at https://discord.gg/tWEmjR66cy

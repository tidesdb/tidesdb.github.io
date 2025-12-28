---
title: "What I Learned Building a Storage Engine That Outperforms RocksDB"
description: "Lessons learned building TidesDB - an embeddable storage engine that outperforms RocksDB through lock-free concurrency, adaptive compaction, and aggressive caching."
---

*by Alex Gaetano Padula*

*published on December 27th, 2025*

I spent the almost past two years building TidesDB, an embeddable key-value storage engine written in C. But this isn't version 1.0 - it's version 7.0. There have been many revisions(majors, minors and patches), complete rewrites, failed experiments. I learn constantly, obsessively. Each version taught me something new about storage engines, LSM-trees, lock-free algorithms, or the subtle ways systems break.

I don't tend to follow others. I design from the ground up, experiment, find the bugs, discover the bottlenecks, and keep building. Storage engines are my obsession - the kind where you wake up at 3am thinking about data loss, a missing feature, or even atomic memory ordering on something you wrote recently. It's hard to leave alone. Some people collect stamps; I collect insights about how data moves through memory and disk.

The goal was never to create "RocksDB but faster" - it was to understand storage systems from first principles - from raw bytes on disk to ACID transactions - and push the boundaries of what's possible. This post walks through the design choices, benchmark results, and lessons learned.

## Background

I'm Alex Gaetano Padula. I've been programming since I was twelve almost thirteen, started freelancing at sixteen, and have spent the last few years researching and building databases from first principles. I approach projects with what some might call obsessive curiosity - taking systems apart, finding what doesn't work, and rebuilding for modern hardware.

TidesDB is the result of reading papers like O'Neil's LSM-tree (1996), WiscKey (2016), and Spooky (2022), then asking: can we do better if we optimize for 2025 hardware - lots of RAM, fast SSDs, many CPU cores whilst making the system clean, portable, and easy to use.

## Design Decisions

### Lock-Free Concurrency

The biggest architectural choice: everything is mostly lock-free. Skip list memtables use atomic CAS (Compare-And-Swap) operations. The block cache uses partitioned CLOCK eviction with atomic state machines. The block manager uses `pread`/`pwrite` for position-independent I/O. Reference counting is atomic throughout.

**What does "lock-free" mean?** 

Traditional databases use mutexes (locks) - when one thread is writing, others wait in line. With lock-free design, threads use atomic operations to update data simultaneously. Think of it like multiple people editing different parts of a Google Doc at once, versus taking turns with a single keyboard.

This isn't easy. Lock-free programming requires careful attention to memory ordering, ABA problems (solved with generation counters), and spurious CAS failures. But modern CPUs have many cores. When you use mutexes, you serialize operations - only one thread makes progress at a time. With lock-free atomics, you get near-linear scaling - all cores work simultaneously.

The sequential write benchmark shows 511% CPU utilization on 8 cores - that's 6.4 cores working simultaneously. RocksDB achieves 306% (3.8 cores). The lock-free architecture is paying off.

### Spooky Compaction + Dynamic Capacity Adaptation

I implemented all three merge strategies from the Spooky paper (Dayan et al., 2022):
- Full preemptive merge (compact adjacent levels entirely)
- Dividing merge (merge levels 1→X into X+1)
- Partitioned merge (divide key space, merge ranges independently)

Plus Dynamic Capacity Adaptation (DCA). After every compaction, DCA recalibrates level capacities based on actual data distribution:

```
C[i] = N_L / T^(L-1-i)
```

**Breaking down the formula:**

- `C[i]` = capacity for level i
- `N_L` = actual current size of the largest level (not a theoretical max)
- `T` = level size ratio (default 10x)
- `L` = total number of levels
- `i` = which level we're calculating (0, 1, 2, etc.)

**Example** 

If you have 5 levels and the largest level is 64GB:
- Level 4 (largest): 64GB
- Level 3: 64GB / 10^1 = 6.4GB
- Level 2: 64GB / 10^2 = 640MB
- Level 1: 64GB / 10^3 = 64MB

If you write 200GB but only 64GB survives compaction, capacities shrink proportionally. This triggers more frequent compaction of obsolete versions.

Result: 1.08x average write amplification across all workloads vs RocksDB's 1.34x. For Zipfian (hot key) workloads, the database is 5.6x smaller (10.2 MB vs 57.6 MB) because DCA aggressively compacts obsolete versions.

### WiscKey-Style Key-Value Separation

Every SSTable has two files:
- **klog** (key log) · sorted keys with metadata and small inline values
- **vlog** (value log) · large values (>4KB) referenced by offset

**Why separate keys and values?** 

In traditional LSM-trees, compaction rewrites entire key-value pairs. If your value is 4KB, you're rewriting 4KB every time that key gets compacted. With key-value separation, compaction only rewrites the key and a pointer to the value. The 4KB value stays put in the vlog.

**The tradeoff?** 

Writes are slightly slower (two files to write) but iteration is much faster (only read keys, not values) and write amplification is lower (only keys get rewritten during compaction).

For 4KB values, TidesDB achieves 96K writes/sec with 1.07x write amplification. Iteration is 2.08x faster (835K vs 401K ops/sec) because we only read keys, not 4KB value blobs. Compaction only moves key references - values stay in the vlog.

### Memory Trade-offs

TidesDB keeps SSTable metadata in memory until reference counts reach zero:
- Block indices (~25MB for 10M keys with sparse sampling)
- Bloom filters (~125MB at 10 bits per key)
- Min/max keys (~5MB)

**What are these?**

- Block indices · Like a table of contents - tells you which block contains which key range, so you can jump directly to the right block instead of scanning the whole file
- Bloom filters · A probabilistic data structure that quickly answers "is this key definitely NOT in this file?" - saves you from opening files that don't contain your key
- Min/max keys · The smallest and largest key in each file - helps skip entire files during searches

This uses 5.2x more memory than RocksDB during random reads (1,722 MB vs 332 MB). But it eliminates 2-3 disk I/O operations per read. For random reads, TidesDB achieves 1.22M ops/sec with 5μs median latency vs RocksDB's 1.08M ops/sec with 7μs latency.

**The trade-off is explicit** 

use more memory to accelerate reads. On modern servers with 128GB+ RAM, using 1.7GB to eliminate disk I/O is worthwhile. Disk reads take milliseconds; memory reads take microseconds - that's a 1000x difference.

## Benchmark Results

Test environment · Intel i7-11700K (8 cores), 48GB RAM, WD 500GB SATA SSD, Ubuntu 23.04. Sync disabled for both engines, 8 threads, 16B keys, 100B values (unless specified).

### Sequential Writes (10M operations)
- **TidesDB** · 6.21M ops/sec, 1.09x write amplification, 511% CPU
- **RocksDB** · 2.36M ops/sec, 1.47x write amplification, 306% CPU
- **Result** · 2.63x faster

**What is write amplification?** 

When you write 1GB of data, the database might actually write 1.5GB to disk due to compaction, indexing, and metadata. Write amplification of 1.09x means for every 1GB you write, TidesDB writes 1.09GB total. Lower is better for SSD longevity.

### Random Writes (10M operations)
- **TidesDB** · 1.66M ops/sec, 1.09x write amplification
- **RocksDB** · 1.35M ops/sec, 1.32x write amplification
- **Result** · 1.23x faster

### Random Reads (10M operations)
- **TidesDB** · 1.22M ops/sec, p50: 5μs, p99: 14μs
- **RocksDB** · 1.08M ops/sec, p50: 7μs, p99: 17μs
- **Result** · 1.13x faster, 29% lower latency

**What is p50/p99?** 

p50 (median) means 50% of reads complete in 5μs or less. p99 means 99% of reads complete in 14μs or less. These percentiles show consistency - you care about the slowest 1% of requests, not just the average.

### Zipfian Mixed Workload (5M operations, hot keys)
- **TidesDB** · 2.48M PUT/sec, 2.79M GET/sec, p50: 2μs, DB size: 10.2 MB
- **RocksDB** · 1.52M PUT/sec, 1.55M GET/sec, p50: 11μs, DB size: 57.6 MB
- **Result** · 1.63x faster writes, 1.80x faster reads, 5.6x smaller database

**What is Zipfian?** 

A distribution where some keys are accessed much more frequently than others - like how 20% of your users generate 80% of your traffic. This tests how well the database handles "hot" keys. DCA shines here because it aggressively compacts obsolete versions of frequently-updated keys.

### Large Values (1M operations, 4KB values)
- **TidesDB** · 96K ops/sec, 835K iteration ops/sec, 1.07x write amp
- **RocksDB** · 108K ops/sec, 401K iteration ops/sec, 1.21x write amp
- **Result** · Slightly slower writes, 2.08x faster iteration, better write amplification

### Delete Performance (5M operations)
- **TidesDB** · Database size after deletes: 0.00 MB
- **RocksDB** · Database size after deletes: 63.77 MB
- **Result** · Complete space reclamation

The large value result is interesting. TidesDB's dual-path write (klog + vlog) is slightly slower for writes, but iteration only reads keys, making it 2.08x faster. The write amplification advantage (1.07x vs 1.21x) comes from compaction only moving key references.

## What I Learned

**Don't be afraid to do things differently.** 

Many people say "it's not possible" or "it's not worth it". Don't listen to them. Build what you need, what you WANT and if it's not good enough, try again and build better. 

**Design as you go.** 

Sometimes your original design is not the best. Don't be afraid to change it. 

**Lock-free is worth it if you commit fully.** 

Half lock-free, half mutex code is worse than all-mutex. The 2.63x sequential write advantage comes from consistent lock-free design throughout.

**Research papers work in production.** 

Spooky (2022), WiscKey (2016), SSI (2008) - all implementable. The gap between research and practice is smaller than people think.

**Memory trade-offs are acceptable.** 

Using more memory for 1.13x faster reads and 29% lower latency is a good trade on modern hardware. Don't optimize for 2011 constraints.

**Reference counting provides safety without locks.** 

Atomic refcounts + careful lifecycle management eliminate entire classes of race conditions. SSTable metadata stays in memory until safe to free.

**Compaction strategy matters more than people realize.** 
The difference between 1.08x and 1.34x write amplification compounds over billions of operations. DCA's adaptive behavior produces consistently low write amp.

**Extreme cases reveal limits.** 

At batch size 10,000 with 8 threads (80,000 concurrent operations), lock-free skip lists saturate with CAS contention. Think of it like too many people trying to edit the same Google Doc simultaneously - eventually the atomic operations start failing and retrying, burning CPU without making progress. TidesDB drops to 852K ops/sec vs RocksDB's 1.33M. I optimized for common cases (batches of 10-1,000), not extremes.

## What's Not Tested

These benchmarks show TidesDB winning most scenarios. But I want to be clear about what they don't show:
- Production stability over months/years
- Performance with hundreds of concurrent column families

RocksDB has 10+ years of battle-testing. TidesDB is newer. The architecture is sound and the performance is real, but production maturity comes from time and diverse workloads.

## When to Use TidesDB

**Use TidesDB when**
- Write throughput is critical (1.5-3.3x faster)
- Space efficiency matters (1.2-6.1x smaller databases)
- Memory is available (more memory for reads is acceptable)
- Access patterns have locality (Zipfian results show 5.6x space advantage)
- Batch sizes are moderate (10-1,000 operations)
- You want low write amplification (SSD longevity, I/O efficiency)

**Use RocksDB when**
- Resource constraints are strict 
- Very large batches are common (>5,000 operations per batch)
- Operational maturity is required (extensive tooling, community support)
- Risk aversion is high (proven at massive scale for 10+ years)

## Architecture Deep Dive

Beyond the high-level design decisions, several implementation details contribute to TidesDB's performance:

### Skip List · Lock-Free Multi-Version Insertion

The skip list uses a CAS loop for inserting new versions:

```c
do {
    old_head = atomic_load_explicit(versions_ptr, memory_order_acquire);
    if (skip_list_validate_sequence(old_head, seq) != 0) {
        return -1;  // Sequence number validation failed
    }
    atomic_store_explicit(&new_version->next, old_head, memory_order_release);
} while (!atomic_compare_exchange_weak(versions_ptr, &old_head, new_version));
```

**Why this matters?** 

Multiple threads can insert versions simultaneously without locks. If a CAS fails (another thread modified the version chain), it retries. The sequence number validation ensures MVCC correctness - newer versions must have higher sequence numbers.

### SSTable Reaper · Avoiding File Descriptor Exhaustion

TidesDB has a background "reaper" thread that closes unused SSTable files when the open file count exceeds the limit (default 512). It sorts SSTables by `last_access_time` and closes the oldest 25%.

**The optimization?** 

Instead of calling `time()` on every read (expensive syscall), the reaper thread updates a cached timestamp every 100ms:

```c
atomic_store(&db->cached_current_time, time(NULL));
```

All reads use the cached time for TTL checks and access tracking. This eliminates thousands of syscalls per second on hot paths.

### Block Cache · Partitioned for Scalability

The CLOCK cache uses 2 partitions per CPU core (16 partitions on 8 cores). Each partition has:
- Independent hash table for O(1) lookups
- Independent CLOCK hand for eviction
- Atomic operations for lock-free access

**Why partition?** 

With 8 threads and 16 partitions, average contention is 0.5 threads per partition. Compare this to a single global cache where all 8 threads contend on every operation.

### Sparse Block Indexes · Binary Search Optimization

TidesDB uses sparse sampled block indexes for fast key lookups. Instead of indexing every block, it samples every Nth block (configurable `index_sample_ratio`, default 1 = every block). Each index entry stores:
- First key prefix (configurable length, default 16 bytes)
- Last key prefix
- File position of the block

**How GET uses block indexes**

```c
// Binary search the block index to find predecessor
compact_block_index_find_predecessor(sst->block_indexes, key, key_size, &start_position);

// Jump directly to that block
block_manager_cursor_goto(cursor, start_position);

// Binary search within the block
while (left <= right) {
    int mid = left + (right - left) / 2;
    int cmp = comparator_fn(key, key_size, block->keys[mid], ...);
    // ... standard binary search
}
```

**How SEEK uses block indexes**

Iterator seek operations also use block indexes to jump directly to the right block, then scan forward from there. The bloom filter is checked first (eliminates 99% of negative lookups), then the block index narrows down to the specific block.

**Why sparse sampling?**

- Sample ratio 1 (every block) · Maximum seek performance, larger index (~32 bytes per block)
- Sample ratio 10 (every 10th block) · 10x smaller index, may need to scan up to 10 blocks
- Default ratio 1 · Optimizes for read performance on modern hardware with abundant RAM

**Cache integration**

Both GET and SEEK check the block cache before disk reads. Cache keys are `"cf_name:sstable_id:block_offset"`. On cache hit, the deserialized block is returned without any disk I/O or decompression. This makes repeated reads to the same blocks extremely fast.

### Block Manager · Self-Describing Layout

The block manager uses a self-describing file format that enables fast validation and recovery:

**File Structure**
```
[HEADER: 8 bytes]
  - Magic: 0x544442 ("TDB", 3 bytes)
  - Version: 7 (1 byte)
  - Padding: 4 bytes reserved

[BLOCK 1]
  - Size: 4 bytes (supports up to 4GB blocks)
  - Checksum: 4 bytes (xxHash32)
  - Data: variable size
  - Footer Size: 4 bytes (duplicate for validation)
  - Footer Magic: 0x42445442 ("BTDB", 4 bytes)

[BLOCK 2...]
[BLOCK N]
```

**Why Self-Describing?**

Each block has both a header and footer with size information. This enables:
- **Forward scanning** · Read size from header, jump to next block
- **Backward scanning** · Read size from footer, jump to previous block
- **Fast validation** · Check footer magic without reading entire block
- **Crash recovery** · Walk backward from end of file to find last valid block

**Position-Independent I/O**

The block manager uses `pread`/`pwrite` for all operations:

```c
// Read at specific offset without seeking
ssize_t nread = pread(fd, buffer, size, offset);

// Write at specific offset without seeking  
ssize_t written = pwrite(fd, buffer, size, offset);
```

**Why this matters:**
- **No locks needed** · Multiple threads read/write different offsets simultaneously
- **No seek overhead** · Direct offset access, no syscall to move file pointer
- **Atomic operations** · Single `pwrite` call writes header + data + footer atomically
- **Cursor independence** · Each cursor maintains its own position, no shared state

**Atomic Offset Allocation**

Writers allocate offsets atomically from the file size:

```c
uint64_t offset = atomic_fetch_add(&bm->current_file_size, total_size);
pwrite(fd, data, total_size, offset);
```

This enables lock-free concurrent writes - multiple threads can write different blocks simultaneously without coordination.

**Checksum Validation**

Every block has an xxHash32 checksum of its data. On read:
1. Read header to get size and stored checksum
2. Read data
3. Compute xxHash32 of data
4. Compare with stored checksum
5. If mismatch, return corruption error

**Crash Recovery Modes**

- **Permissive mode** (WAL files) · Walk backward, truncate to last valid block
- **Strict mode** (SSTable files) · Any corruption in last block rejects entire file

This reflects their roles: WAL files are temporary and rebuilt on recovery; SSTables are permanent and must be correct.

### Background Workers · Hybrid Lock-Free Queues

TidesDB uses a hybrid queue design that combines lock-free reads with mutex-protected writes:

**Queue Architecture**
```c
typedef struct {
    queue_node_t *head;                    // Protected by mutex for writes
    _Atomic(queue_node_t *) atomic_head;   // Lock-free for reads
    queue_node_t *tail;
    _Atomic(size_t) size;                  // Lock-free size queries
    pthread_mutex_t lock;
    pthread_cond_t not_empty;
    queue_node_t *node_pool;               // Up to 64 reusable nodes
} queue_t;
```

**Lock-Free Size Queries**

The size is stored atomically, allowing threads to check queue depth without acquiring locks:

```c
size_t queue_size(queue_t *queue) {
    return atomic_load_explicit(&queue->size, memory_order_relaxed);
}
```

This is used throughout TidesDB to check if work remains without blocking (e.g., checking if immutable memtables need flushing).

**Node Pooling**

The queue maintains a pool of up to 64 reusable nodes. Instead of malloc/free on every enqueue/dequeue:
- **Enqueue** · Allocate from pool if available, else malloc
- **Dequeue** · Return node to pool if space available, else free

On high-throughput workloads where memtables flush frequently, this eliminates thousands of allocations per second.

**Blocking Dequeue for Workers**

Worker threads use `queue_dequeue_wait()` which blocks on a condition variable until work arrives:

```c
void *queue_dequeue_wait(queue_t *queue) {
    pthread_mutex_lock(&queue->lock);
    
    // Wait until queue is not empty or shutdown
    while (queue->head == NULL && !queue->shutdown) {
        pthread_cond_wait(&queue->not_empty, &queue->lock);
    }
    
    void *data = queue_dequeue_internal(queue);
    pthread_mutex_unlock(&queue->lock);
    return data;
}
```

Workers sleep when idle instead of spinning, reducing CPU usage to near-zero when there's no work.

**How Flush Works**

When a memtable fills:
1. Main thread atomically swaps in new empty memtable
2. Old memtable becomes immutable and is enqueued:
   ```c
   queue_enqueue(db->flush_queue, flush_work);
   ```
3. Flush worker wakes up, dequeues work
4. Worker writes SSTable to disk, updates manifest
5. Worker deletes WAL file
6. Worker goes back to sleep waiting for next flush

**How Compaction Works**

When level 1 exceeds threshold (default 4 SSTables):
1. Main thread creates compaction work item
2. Enqueues to compaction queue:
   ```c
   queue_enqueue(db->compaction_queue, compaction_work);
   ```
3. Compaction worker wakes up, dequeues work
4. Worker merges SSTables, writes new ones
5. Worker updates manifest, marks old SSTables for deletion
6. Worker applies DCA to rebalance level capacities
7. Worker goes back to sleep

**Why This Design?**

- **Write path never blocks**: Enqueue is fast (just mutex lock/unlock), write operations return immediately
- **Workers don't spin**: Condition variables mean zero CPU usage when idle
- **Parallel processing**: Multiple workers can process different column families simultaneously
- **Retry safety**: If flush fails (disk full), work is re-enqueued with exponential backoff

The hybrid approach gives you the best of both worlds: lock-free reads for checking queue state, efficient blocking for workers, and safe concurrent access.

### Memtable Rotation · Atomic Swap

When a memtable fills, TidesDB atomically swaps in a new empty memtable:

```c
tidesdb_memtable_t *old = atomic_load(&cf->active_memtable);
tidesdb_memtable_t *new = create_new_memtable();
atomic_store(&cf->active_memtable, new);
```

The old memtable goes to an immutable queue for flushing. Writers immediately use the new memtable. No locks, no waiting.

### SSI Conflict Detection · Hash Table Optimization

For serializable transactions, TidesDB tracks read sets to detect conflicts. Small transactions (< 64 reads) use arrays. Larger transactions automatically switch to a hash table using xxHash for O(1) conflict detection:

```c
if (read_set_size > 64) {
    create_hash_table_for_conflict_detection();
}
```

**Why this matters?** 

Most transactions are small. Arrays are faster for small read sets (better cache locality, no hash overhead). But for large analytical transactions, the hash table prevents O(n²) conflict checking.

### Node Pooling · Reducing Allocation Overhead

The queue implementation maintains a pool of up to 64 reusable nodes. Instead of malloc/free on every enqueue/dequeue, nodes are recycled:

**Why this matters?** 

On high-throughput workloads, memtables flush frequently. Without pooling, the flush queue would allocate/free thousands of nodes per second. Pooling eliminates this overhead entirely.

## Transaction System · ACID with SSI

TidesDB implements full ACID transactions with 5 isolation levels:

**Isolation Levels**
- **READ_UNCOMMITTED** · Sees all versions including uncommitted (dirty reads allowed)
- **READ_COMMITTED** · Refreshes snapshot on each read (prevents dirty reads)
- **REPEATABLE_READ** · Consistent snapshot + read-write conflict detection
- **SNAPSHOT** · Consistent snapshot + read-write + write-write conflict detection
- **SERIALIZABLE** · Full SSI with dangerous structure detection (prevents all anomalies)

**Read-Your-Own-Writes Optimization**

Transactions check their write set before reading from memtables. For small transactions (< 256 ops), this is a linear scan from the end (cache-friendly). For large transactions, it automatically builds a hash table for O(1) lookups:

```c
if (txn->num_ops == 256 && !txn->write_set_hash) {
    txn->write_set_hash = tidesdb_write_set_hash_create();
    // Populate hash with all existing operations
}
```

**SSI Conflict Detection**

For serializable isolation, TidesDB tracks read sets to detect dangerous structures. Small transactions (< 64 reads) use arrays. Large transactions automatically switch to xxHash-based hash tables for O(1) conflict detection:

```c
if (txn->read_set_count == 64 && !txn->read_set_hash) {
    txn->read_set_hash = tidesdb_read_set_hash_create();
    // Populate hash with all existing reads
}
```

At commit time, the system checks all concurrent transactions for read-write conflicts. If transaction T reads key K that another transaction T' writes, it sets conflict flags. If both flags are set (transaction is a pivot in a dangerous structure), it aborts.

**Cross-Column-Family Transactions**

Transactions work across multiple column families atomically. Each CF's WAL receives operations with the same global commit sequence number, ensuring atomicity through sequence-based ordering.

**Savepoints**

Transactions support savepoints for partial rollback:

```c
tidesdb_txn_savepoint(txn, "before_update");
// ... operations ...
tidesdb_txn_rollback_to_savepoint(txn, "before_update");
```

## The API · Clean and Intuitive

TidesDB's C API is designed for clarity and safety:

**Error Handling**
- Returns `TDB_SUCCESS` (0) on success
- Negative error codes: `TDB_ERR_MEMORY`, `TDB_ERR_INVALID_ARGS`, `TDB_ERR_NOT_FOUND`, `TDB_ERR_IO`, `TDB_ERR_CORRUPTION`, `TDB_ERR_CONFLICT`
- No exceptions, no hidden state

**Transaction Example**

```c
tidesdb_txn_t *txn;
tidesdb_txn_begin_with_isolation(db, TDB_ISOLATION_SERIALIZABLE, &txn);

tidesdb_txn_put(txn, cf, key, key_size, value, value_size, 0);
tidesdb_txn_delete(txn, cf, old_key, old_key_size);

if (tidesdb_txn_commit(txn) == TDB_ERR_CONFLICT) {
    // Serializable conflict detected, retry
}
tidesdb_txn_free(txn);
```

**Iterator Example**

```c
tidesdb_iter_t *iter;
tidesdb_iter_new(txn, cf, &iter);

tidesdb_iter_seek(iter, start_key, start_key_size);
while (tidesdb_iter_valid(iter)) {
    uint8_t *key, *value;
    size_t key_size, value_size;
    tidesdb_iter_key(iter, &key, &key_size);
    tidesdb_iter_value(iter, &value, &value_size);
    // ... process ...
    free(key); free(value);
    tidesdb_iter_next(iter);
}
tidesdb_iter_free(iter);
```

**Custom Comparators**

6 built-in comparators: `memcmp`, `lexicographic`, `uint64`, `int64`, `reverse_memcmp`, `case_insensitive`. Register custom ones:

```c
tidesdb_register_comparator(db, "my_comparator", my_fn, ctx_str, ctx);
```

**Runtime Configuration**

Column families support runtime configuration updates without restart:

```c
tidesdb_cf_config_update(cf, &new_config, persist_to_disk);
```

**Statistics API**

```c
tidesdb_stats_t *stats;
tidesdb_get_stats(cf, &stats);
printf("Levels: %d, Memtable: %zu bytes\n", stats->num_levels, stats->memtable_size);
tidesdb_free_stats(stats);
```

View rest of API documentation [here](https://tidesdb.com/reference/c/).

## Implementation Details

TidesDB is ~565KB of C code (the main engine) plus 8 focused modules totaling ~150KB:
- **block_manager** (32KB) · Lock-free file I/O with atomic reference counting
- **skip_list** (48KB) · Multi-version lock-free skip list with MVCC
- **clock_cache** (31KB) · Partitioned CLOCK eviction with atomic state machines
- **bloom_filter** (9KB) · Probabilistic filters for negative lookups
- **buffer** (11KB) · Lock-free buffer with generation counters
- **queue** (11KB) · Lock-free queue for background workers
- **manifest** (10KB) · Transaction log for metadata changes
- **compress** (6KB) · LZ4/Snappy/Zstd compression wrapper

It supports:
- ACID transactions with 5 isolation levels (including SSI)
- Cross-column-family atomic transactions
- Bidirectional iterators with seek operations
- TTL support
- Custom comparators (6 built-in)
- 3 compression algorithms (LZ4, Snappy, Zstd)
- 3 sync modes (none, interval, full)

Tested on 10 platform/architecture combinations: Linux (x86, x64, PowerPC), macOS (x64, ARM64), Windows (x86, x64), FreeBSD, OpenBSD, NetBSD, DragonFlyBSD, Illumos, Solaris.

## A Complete Database Foundation

TidesDB isn't just a key-value store - it's a complete foundation for building production databases. Few embeddable storage engines offer this combination:

**Feature Completeness**
- 5 isolation levels · including full SSI (most engines: 1-2 levels)
- Cross-CF atomic transactions · (most engines: single-namespace only)
- Savepoints · for partial rollback (rare in embedded engines)
- Bidirectional iterators · with seek operations (many engines: forward-only)
- 6 built-in comparators · + custom comparator registry (most engines: fixed ordering)
- Runtime reconfiguration · without restart (most engines: restart required)
- TTL support · at the engine level (most engines: application-level only)
- 3 compression algorithms · (LZ4, Snappy, Zstd) with per-CF configuration
- 3 sync modes · for durability/performance tradeoff
- Statistics API · for monitoring and debugging

**What You Can Build**

With TidesDB, you can build:
- Document databases · (use column families for collections, custom comparators for indexing)
- Time-series databases · (TTL for retention, uint64 comparator for timestamps)
- Graph databases · (multi-CF transactions for atomic edge updates)
- Distributed databases · (embeddable, portable files, ACID transactions)
- Caching layers · (TTL, fast reads, low memory overhead)

**Comparison with Other Engines**

- **RocksDB** · More mature, larger ecosystem
- **LevelDB** · Simpler, but no transactions, no column families, no compression options
- **LMDB** · Fast reads, but copy-on-write (space amplification), no compression
- **WiredTiger** · Feature-rich, but complex API, larger codebase
- **SQLite** · SQL interface, but not optimized for write-heavy workloads

TidesDB combines the best aspects: ACID transactions with SSI, column families, compression, TTL, custom comparators, and a clean C API - all in ~715KB of code.

## What Differentiates TidesDB

Several architectural decisions set TidesDB apart from other LSM-tree implementations:

**1. Pervasive Lock-Free Design**

Most databases use locks for critical sections. TidesDB uses atomics everywhere - skip lists, caches, queues, reference counts, even the comparator registry. This isn't just "lock-free data structures" - it's a commitment to lock-free as the default concurrency model.

**2. Aggressive Metadata Caching**

Traditional LSM-trees load block indices and bloom filters on-demand. TidesDB keeps them in memory with atomic reference counting. The memory cost is explicit and measurable (5.2x). The performance gain is substantial (1.13x throughput, 29% lower latency).

**3. Adaptive Compaction**

DCA recalibrates level capacities after every compaction based on actual data, not theoretical maximums. This produces consistently low write amplification (1.08x average) and dramatically smaller databases for hot-key workloads (5.6x).

**4. Syscall Elimination**

The cached timestamp eliminates thousands of `time()` calls per second. The partitioned cache reduces contention. The atomic memtable swap avoids coordination overhead. These micro-optimizations compound.

**5. Research Implementation Speed**

Spooky was published in 2022. TidesDB implemented all three merge strategies plus DCA by 2025. The gap between research and production is shrinking.

**6. True Cross-Platform Portability**

Not just "compiles on multiple platforms" - the database files are portable. Create a database on Linux x64, copy the files to Windows ARM64, and it works. Little-endian serialization throughout. The CI actually tests this: creates a DB on Linux, uploads it, downloads on 7 different platforms, verifies all keys are readable.

**7. Modular, Reusable Components**

Each component (skip list, bloom filter, block manager, clock cache) is a standalone module with its own test suite. You can use the skip list in your own project without pulling in the entire database. Clean interfaces, zero dependencies between modules.

## Lessons from Building a Storage Engine

**Start with research, not reinvention.** 

I didn't try to invent new algorithms or really copy other storage engines. I read papers (O'Neil's LSM-tree, WiscKey, Spooky, SSI) and implemented them faithfully and failed many times. The innovation was in the integration - making them work together with linear scaling concurrency features.

**Lock-free is hard but worth it.** 

I spent weeks debugging race conditions, ABA problems, and memory ordering issues. The payoff: Very good CPU utilization on 8 cores. Traditional mutex-based designs can't achieve this.

**Measure everything.** 

The cached timestamp optimization came from profiling and running the system benchmarks and tests over and over and over AGAIN. Syscalls are expensive. We cache them when we can. One atomic load instead of a syscall - thousands of times per second.

**Cross-platform from day one.** 

I didn't build for Linux first and port later. I used `compat.h` from the start. This forced abstractions and caught portability issues early and still do.

**Test on real hardware.** 

The batch=10,000 failure only appeared under high contention on real multi-core CPUs. Synthetic tests didn't catch it.

**Document and benchmark honestly.** 

Honesty it key.

## The Path Forward

The goal isn't to declare victory and stop. It's to continue making TidesDB the best it can be.   Incorporating feedback, fixing and finding bugs, and staying current with research. Storage engines are never "done" - they evolve with hardware, workloads, and understanding.

If you're building something that needs fast, embeddable storage with ACID guarantees, give TidesDB a try. If you find bugs or have ideas, open an issue or join the Discord. This is a learning journey, and I'm excited to see where it goes.

## Conclusion

Building TidesDB taught me that fundamental architectural decisions matter more than incremental optimizations. Mostly lock-free concurrency, adaptive compaction, memory trade-offs for performance, and research-backed algorithms compound to produce the 1.5-3.3x write advantages and 1.13x read advantages you see in benchmarks.

The large memory usage isn't bloat - it's keeping metadata in memory until safe to free, enabled by atomic reference counting. The batch=10,000 problem isn't a flaw - it's a known trade-off of lock-free algorithms under extreme contention.

Every storage engine makes trade-offs. TidesDB makes trade-offs for modern hardware, typical workloads, and performance-first priorities. If those align with your needs, TidesDB offers compelling advantages.

*Thanks for reading!*

---

**Links**
- GitHub · https://github.com/tidesdb/tidesdb
- Documentation · https://tidesdb.com
- Benchmarks · https://tidesdb.com/articles/benchmark-analysis-tidesdb7-rocksdb1075
- Design deep-dive · https://tidesdb.com/getting-started/how-does-tidesdb-work

**About me** 

I'm Alex Gaetano Padula, a software engineer who's spent the last few years building databases and storage engines from first principles. You can find me at https://alexpadula.com or https://github.com/guycipher.

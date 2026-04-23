---
title: How does TidesDB work?
description: A comprehensive design overview of TidesDB's architecture, core components, and operational mechanisms.
---

<div id="tidesdb-version" class="version-section"></div>

<script>
(function() {
  var badge = document.getElementById('tidesdb-version');
  fetch('https://api.github.com/repos/tidesdb/tidesdb/releases/latest')
    .then(function(r) { return r.json(); })
    .then(function(data) {
      var version = data.tag_name || 'v8.1.0';
      var url = data.html_url || 'https://github.com/tidesdb/tidesdb/releases';
      badge.innerHTML = 
        '<span>' + version + '</span></a>';
    })
    .catch(function() {
      badge.innerHTML =
        '<span>v9.0.1</span>';
    });
})();
</script>

<div class="no-print">

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/getting-started/how-does-tidesdb-work.md).

<hr/>

<details>
<summary>Want to watch a presentation instead?</summary>

<ul>
<li><a href="https://www.youtube.com/watch?v=7HROlAaiGVQ">
TidesDB - LSM-tree storage engines don’t need to be complex to be exceptional (Database Internals)</a>
</li>
<li><a href="https://www.youtube.com/watch?v=JuAjaNPE1Bc">
TidesDB Bengaluru Systems Presentation</a>
</li>
<li><a href="https://www.youtube.com/watch?v=WwHqEvOuD3E">
Riding The Tides - Building a Modern Storage Engine (MariaDB Foundation)
</a>
</li>
</ul>

</div>

## Introduction

TidesDB is an embeddable key-value storage engine built on log-structured merge trees. The LSM tree is an old and well-understood idea: batch writes in memory, then flush sorted runs to disk. The cost of this approach is write amplification, since data must be written multiple times during compaction. The benefit is improved write throughput and sequential I/O patterns. The fundamental bargain is that writes become fast while reads must search multiple sorted files.

The system provides ACID transactions with five isolation levels and manages data through a hierarchy of sorted string tables (SSTables). Each level in the hierarchy holds roughly N times more data than the previous level. Compaction merges SSTables from adjacent levels, discarding obsolete entries and reclaiming space.

Data flows from memory to disk in stages (Figure 1). Writes first enter an in-memory skip list, chosen over AVL trees for its easier lock-free potential and simpler implementation. A write-ahead log backs each skip list. When the skip list exceeds the configured write buffer size, it becomes immutable and a background worker flushes it to disk as an SSTable. These tables accumulate in levels. Compaction merges tables from adjacent levels to maintain the level size invariant.
<div class="architecture-diagram">
<img src="/design-diags/01_data_model.png" alt="Figure 1. Data flow through the LSM tree.">
</div>

## Data Model

### Column Families

The database organizes data into column families. Each column family is an independent key-value namespace with its own configuration, memtables, write-ahead logs, and disk levels. This isolation allows different column families to use different compression algorithms, comparators, and tuning parameters within the same database instance.

In the default per-column-family mode, a column family maintains one active memtable for new writes, a queue of immutable memtables awaiting flush, a write-ahead log paired with each memtable, up to 32 levels of sorted string tables on disk, and a manifest file tracking which SSTables belong to which levels.

TidesDB also supports a unified memtable mode where all column families share a single skip list and single WAL. The [Unified Memtable](#unified-memtable) section covers this alternative in detail.

### Sorted String Tables

Each sorted string table consists of two files: a key log (.klog) and a value log (.vlog). The key log stores keys, metadata, and values smaller than a configurable threshold (512 bytes by default). Values meeting or exceeding this threshold reside in the value log, with the key log storing only the file offset. This separation keeps the key log compact for efficient scanning while accommodating arbitrarily large values.

The key log uses a block-based format. Each block, fixed at 64KB, contains multiple entries serialized with variable-length integer encoding. Blocks compress independently using LZ4, LZ4-FAST, Zstd, or Snappy. The key log ends with three auxiliary structures: a block index for binary search, a bloom filter for negative lookups, and a metadata block with SSTable statistics. The on-disk layout of these components is shown in Figure 2.
<div class="architecture-diagram">
<img src="/design-diags/02_sstable_layout.png" alt="Figure 2. SSTable file layout.">
</div>

### B+tree Format (Optional)

Column families can optionally use a B+tree structure for the key log instead of the default block-based format. This is enabled with `use_btree=1` in the column family configuration. The B+tree stores all key-value entries exclusively in leaf nodes, with internal nodes containing only separator keys and child pointers for navigation. Leaf nodes are doubly-linked via `prev_offset` and `next_offset` pointers, enabling O(1) bidirectional traversal. The tree is immutable after construction: it is bulk-loaded from sorted memtable data during flush and never modified afterward.

During construction, the builder accumulates entries in a pending leaf until it reaches the target node size (64KB by default). When full, the leaf is serialized and written to disk. After all leaves are written, internal nodes are built level-by-level from separator keys extracted from each child's first key. A backpatching pass then updates each leaf's `prev_offset` and `next_offset` pointers to their final values. For compressed nodes, the leaf links are stored in a header before the compressed data, allowing the backpatch to update them without decompressing and recompressing the entire node.

Point lookups traverse from root to leaf using binary search at each internal node to select the correct child, then binary search within the leaf to locate the key. This yields O(log N) complexity where N is the number of nodes, compared to potentially scanning multiple 64KB blocks in the block-based format. Range scans use cursors that hold a reference to the current leaf node, advancing through entries before following the `next_offset` link to load the next leaf. Backward iteration follows `prev_offset` links similarly.

The B+tree format excels at point lookups and range scans with seeks. Point lookups benefit from O(log N) tree traversal versus potentially scanning multiple 64KB blocks. Range scans with `seek()` navigate directly to the target key position rather than scanning sequentially. Workloads with many small-to-medium SSTables see the most improvement, as each SSTable's hot nodes remain cached independently. The block-based format remains preferable for sequential full-table scans and write-heavy workloads where B+tree metadata overhead during flush is less desirable.

When `block_cache_size` is configured, TidesDB creates a dedicated clock cache for B+tree nodes. Frequently accessed nodes remain in memory as fully deserialized structures, avoiding repeated disk reads and deserialization overhead. Cache keys combine the SSTable ID and node offset to ensure uniqueness across tables. On eviction, the callback frees the node's memory via arena destruction. Cached nodes use arena allocation, where all node memory (keys, values, metadata) is allocated from a single arena, enabling O(1) bulk deallocation when the node is evicted. When an SSTable is closed or deleted, all its cached nodes are invalidated by prefix scan to prevent stale references.

Large values meeting or exceeding the configured threshold (512 bytes by default) are written to the value log, with the leaf entry storing only the vlog offset. Nodes compress independently using LZ4, LZ4-FAST, Zstd, or Snappy. When bloom filters are enabled, they are checked before tree traversal. A negative result skips the B+tree lookup entirely, which is critical for LSM-trees where most SSTables will not contain the requested key. SSTable metadata persists five additional fields for B+tree format: root offset, first leaf offset, last leaf offset, node count, and tree height. These are restored when the SSTable is reopened.

#### Serialization Optimizations

The B+tree uses several techniques to minimize serialized node size.

Varint encoding is used for metadata fields such as entry counts, key sizes, value sizes, and vlog offsets. These use LEB128-style variable-length integers. Small values under 128 require only one byte; the full 64-bit range needs at most ten bytes. This typically saves 50 to 70 percent on metadata overhead compared to fixed-width integers.

Prefix compression takes advantage of the fact that keys within a leaf node often share common prefixes with their predecessors. Each key stores only its suffix, with the prefix length encoded as a varint. During deserialization, keys are reconstructed by copying the prefix from the previous key. For sorted string keys with common prefixes (such as "user:1001" and "user:1002"), this achieves 60 to 80 percent key size reduction.

A key indirection table in each leaf node contains 2-byte offsets pointing to each key's position within the node. This enables O(1) random access to any key during binary search without scanning through variable-length prefix-compressed keys sequentially.

Delta sequence encoding stores sequence numbers within a leaf as signed deltas from a base sequence number (the minimum in the node). Since entries in a leaf typically have similar sequence numbers, deltas are small and compress well with varint encoding. TTL values use zigzag encoding for efficient signed integer representation.

Internal nodes store child offsets as sequential signed deltas. Each offset is encoded as the difference from the previous child's offset, starting from a base offset (the first child). Since child nodes are typically written sequentially, deltas are small positive values that compress efficiently.

**Leaf node format**
```
[type:1][num_entries:varint][prev_offset:8][next_offset:8]
[key_offsets_table: num_entries × 2 bytes]
[base_seq:varint]
[entries: prefix_len:varint, suffix_len:varint, value_size:varint,
          vlog_offset:varint, seq_delta:signed_varint, ttl:signed_varint, flags:1]
[keys: prefix-compressed suffixes]
[values: inline values only]
```

**Internal node format**
```
[type:1][num_keys:varint][base_offset:8]
[child_offset_deltas: signed_varint × (num_keys + 1)]
[key_sizes: varint × num_keys]
[separator_keys: raw key bytes]
```

### File Format

Each klog entry uses this format:
```
flags (1 byte)
key_size (varint)
value_size (varint)
seq (varint)
ttl (8 bytes, if HAS_TTL flag set)
vlog_offset (varint, if HAS_VLOG flag set)
key (key_size bytes)
value (value_size bytes, if inline)
```

The flags byte encodes tombstones (0x01), TTL presence (0x02), value log indirection (0x04), and delta sequence encoding (0x08). Variable-length integers save space: a value under 128 requires one byte, while the full 64-bit range needs at most ten bytes.

In per-column-family mode, write-ahead logs use the same format. Each memtable has its own WAL file, named by the SSTable ID it will become. Recovery reads these files in sequence order, deserializes entries into skip lists, and enqueues them for asynchronous flushing. In unified memtable mode, per-CF WAL files are not created since all writes go through the unified WAL. This avoids wasted I/O, file descriptors, and empty WAL file artifacts in column family directories.

When unified memtable mode is enabled, all column families share a single WAL per memtable generation. The unified WAL uses a different batch format: a 2-byte magic prefix (`0x55AA`) followed by entries, each prefixed with a 4-byte big-endian column family index before the standard flags, varints, and key-value data. During recovery, the system detects unified WAL files by their filename prefix (`uwal_`) and magic bytes, deserializes entries back into the unified skip list with their CF index prefixes intact, and flushes them through the standard unified flush path.


## Transactions

### Isolation Levels

The system provides five isolation levels.

Read Uncommitted sees all versions, including uncommitted ones. The snapshot sequence is set to UINT64_MAX.

Read Committed performs no validation. Each read refreshes its snapshot to see the most recently committed version.

Repeatable Read detects if any read key changed between read and commit time. The transaction tracks each key it reads along with the sequence number of the version it saw. At commit, it checks whether a newer version exists.

Snapshot Isolation uses first-committer-wins semantics with write-write conflict detection only. No read set is tracked. If another transaction committed a write to the same key after this transaction's snapshot time, the commit aborts. Write skew anomalies, where two transactions read overlapping data and write disjoint sets, are explicitly allowed. This matches standard database theory where snapshot isolation requires only write-write conflict detection.

Serializable implements serializable snapshot isolation (SSI). In addition to the write-write conflict detection from snapshot isolation, the system tracks read-write conflicts. Each transaction maintains a read set consisting of arrays of CF pointers, keys, key sizes, and sequence numbers. Only Repeatable Read and Serializable allocate read sets. The system creates a hash table (`tidesdb_read_set_hash_t`) using xxHash for O(1) conflict detection when the read set exceeds `TDB_TXN_READ_HASH_THRESHOLD` (64 reads). At commit, it checks all concurrent transactions: if transaction T reads key K that another transaction T' writes, it sets `T.has_rw_conflict_out = 1` and `T'.has_rw_conflict_in = 1`. If both flags are set, meaning the transaction is a pivot in a dangerous structure, the commit aborts.

This is a simplified SSI. It detects pivot transactions but does not maintain a full precedence graph or perform cycle detection. False aborts are possible when non-pivot transactions have both flags set.


### Multi-Version Concurrency Control

Each transaction receives a snapshot sequence number at begin time. For Read Uncommitted, this is UINT64_MAX (sees all versions). For Read Committed, it refreshes on each read. For Repeatable Read, Snapshot, and Serializable, the snapshot is `global_seq - 1`, capturing all transactions committed before this one started.

The snapshot sequence determines which versions the transaction sees. It reads the most recent version with sequence number less than or equal to its snapshot sequence. Each key maintains a chain of versions, newest first, as illustrated in Figure 3.
<div class="architecture-diagram">
<img src="/design-diags/03_transactions.png" alt="Figure 3. Version chain for a single key.">
</div>

At commit time, the system assigns a commit sequence number from a global atomic counter. It writes operations to the write-ahead log, applies them to the active memtable with the commit sequence, and marks the sequence as committed in a fixed-size circular buffer (defined by `TDB_COMMIT_STATUS_BUFFER_SIZE`, currently 65536 entries). The buffer wraps around: sequence N maps to slot N % 65536. When the buffer wraps, old entries are overwritten, so visibility checks for very old sequences may return incorrect results. In practice, this is acceptable because transactions with sequence numbers more than 65536 behind the current sequence are extremely rare. Readers skip versions whose sequence numbers are not yet marked committed.

### Multi-Column Family Transactions

TidesDB achieves multi-column-family transactions through a design where the transaction structure maintains an array of all involved column families. When you commit, it assigns operations across all these column families the same sequence number from a global atomic counter shared throughout the database. This shared sequence number serves as a lightweight coordination mechanism that ensures atomicity without the overhead of traditional two-phase commit protocols. Each column family's write-ahead log records its operations with this same sequence number, effectively synchronizing the commit across all involved column families in a single atomic step.

## Write Path

The path a write takes from the application to durable storage is shown in Figure 4.
<div class="architecture-diagram">
<img src="/design-diags/04_write_path.png" alt="Figure 4. The write path.">
</div>

### Transaction Commit

A transaction buffers operations in memory until commit. At commit time, the system validates according to the isolation level, assigns a commit sequence number from the global counter, serializes operations to each column family's write-ahead log, applies operations to the active memtable with the commit sequence, marks the commit sequence as committed in the status buffer, and checks if any memtable exceeds its adaptive flush threshold.

For Snapshot Isolation and higher, commit-time validation checks each key in the write set against the active memtable, unified memtable (if enabled), immutable memtables, and SSTables across all levels. Two optimizations reduce the cost of this check. First, SSTables whose maximum sequence number predates the transaction's snapshot are skipped entirely without acquiring a reference, checking the bloom filter, or reading any blocks, since no entry in them can conflict. In a typical workload the vast majority of SSTables predate any active transaction, so this eliminates most of the I/O from conflict detection. Second, when an SSTable does need to be probed, the search uses a seq-only mode that finds the key through the bloom filter, block index, and block search path but returns only the sequence number without allocating a key-value pair, copying the value, or reading from the value log.

The transaction uses hash-based deduplication to apply only the final operation for each key. The hash table is created lazily when the transaction exceeds `TDB_TXN_DEDUP_SKIP_THRESHOLD` (8 operations) and is sized at `TDB_TXN_DEDUP_HASH_MULTIPLIER` (2x) the number of operations with a minimum of `TDB_TXN_DEDUP_MIN_HASH_SIZE` (64 slots). This is a fast non-cryptographic hash. Collisions are possible but rare, and would cause the transaction to write both operations to the memtable (the skip list handles duplicates correctly). This optimization reduces memtable size when a transaction modifies the same key multiple times.

### Memtable Flush

When a memtable exceeds the flush threshold, the system atomically swaps in a new empty memtable and enqueues the old one for flushing. The swap takes one atomic store with a memory fence for visibility.

#### Adaptive Flush Threshold

The flush threshold is not a fixed value. At transaction commit, the system adjusts the threshold based on L0 immutable queue pressure to balance write batching against memory pressure. When the L0 queue is empty (idle), the threshold is 150% of `write_buffer_size`, providing 50% headroom and allowing the memtable to accumulate more data before flushing for better batching. When one or more immutables are pending but below half the stall threshold (moderate pressure), the threshold drops to 125% of `write_buffer_size`, providing 25% headroom. When the L0 queue depth reaches 50% or more of `l0_queue_stall_threshold` (high pressure), the threshold equals `write_buffer_size` exactly, with zero headroom, triggering an immediate flush. This adaptive mechanism reduces flush frequency during idle periods, improving write throughput, while ensuring rapid flushing under pressure to prevent memory buildup. With the default 64MB write buffer, the effective threshold ranges from 64MB under pressure to 96MB when idle.

A flush worker dequeues the immutable memtable and creates an SSTable. It iterates the skip list in sorted order, writing entries to 64KB blocks. Values meeting or exceeding the threshold (512 bytes by default) go to the value log; the key log stores only the file offset. The worker compresses each block optionally, writes the block index and bloom filter, and appends metadata. It then fsyncs both files, adds the SSTable to level 1, commits to the manifest, and deletes the write-ahead log.

The ordering of these steps is critical. Fsync before manifest commit ensures the SSTable is durable before it becomes discoverable. Manifest commit before WAL deletion ensures crash recovery can find the data.

#### Crash Scenarios

If the system crashes after fsync but before manifest commit, the SSTable exists on disk but is not discoverable. Recovery detects it is not in the manifest and deletes it at startup. If it crashes after manifest commit but before WAL deletion, recovery finds both the SSTable and the WAL. It flushes the WAL again, creating a duplicate SSTable. The manifest deduplicates by SSTable ID.

#### Validation Modes

WAL files use permissive validation (`block_manager_validate_last_block(bm, 0)`). If the last block has invalid footer magic or incomplete data, the system truncates the file to the last valid block by walking backward through the file. This handles crashes during WAL writes. If no valid blocks exist, it truncates to the header only.

SSTables, by contrast, use strict validation (`block_manager_validate_last_block(bm, 1)`). Any corruption in the last block causes the SSTable to be rejected entirely. This reflects the different nature of these files: SSTables are permanent and must be correct.

### Unified Memtable

By default, each column family maintains its own skip list and WAL. This means a transaction touching N column families performs N WAL writes, one per column family. For workloads that create many column families per logical entity (for example, a MariaDB plugin where each table has one data CF plus N secondary index CFs), this multiplies WAL I/O linearly with the number of column families involved in each transaction.

Unified memtable mode replaces all per-CF skip lists and WALs with a single shared skip list and a single WAL at the database level. All column families write into the same memtable and the same WAL file, reducing N WAL writes per transaction to exactly one regardless of how many column families are involved.

#### Key Isolation

Column families share the same skip list but must not see each other's keys. The system assigns each column family a unique 4-byte index (`unified_cf_index`) at creation time, allocated from an atomic counter (`next_cf_index`). Keys in the unified skip list are prefixed with this 4-byte big-endian index before the user key. The prefix ensures keys from different column families sort into contiguous groups (all keys for CF 0 come before CF 1, and so on) and that lookups and iterations only see keys belonging to the target column family. All column families sharing a unified memtable must use the same comparator (enforced at creation), because the shared skip list has a single sort order. The unified skip list itself always uses `memcmp` as its comparator, which correctly orders the 4-byte big-endian prefix numerically and then sorts the suffixed user keys in byte order.

#### Write Path in Unified Mode

At transaction commit, the system serializes all operations across all column families into a single unified WAL batch. The batch begins with a 2-byte magic (`0x55AA`) followed by entries, each prefixed with the 4-byte big-endian column family index. The entire batch is written as a single block to the unified WAL. Operations are then applied to the unified skip list with prefixed keys using `tdb_build_prefixed_key()`, which prepends the 4-byte CF index to each user key. For a transaction touching 5 column families, this results in 1 WAL write instead of 5.

#### Read Path in Unified Mode

When reading a key from a specific column family, the system constructs the prefixed key (4-byte CF index + user key) and searches the unified active skip list, then unified immutable memtables (newest to oldest), then falls back to the per-CF SSTable levels. The prefixed key lookup in the skip list is an exact match, so keys from other column families are never visible. Immutable unified memtables that have already been flushed are skipped (via a `flushed` flag check) to avoid returning stale data that is already durable in SSTables.

#### Flush Demuxing

When the unified memtable exceeds `unified_memtable_write_buffer_size` (which defaults to the same value as `write_buffer_size`, 64MB), it becomes immutable and is enqueued for flushing. The flush worker processes the unified immutable by iterating it in sorted order. Since keys are sorted by [4-byte CF index][user key], consecutive entries with the same prefix belong to the same column family. For each CF group, the flush worker builds a temporary skip list with stripped keys (CF prefix removed) using the CF's own comparator, then flushes it to an SSTable in that CF's level 1 using the existing SSTable write machinery. This produces per-CF SSTables with user keys (no prefix), so the on-disk format and read path through SSTables are identical to per-CF mode. After all groups are flushed, the unified WAL file is deleted.

#### Rotation

The rotation mechanism mirrors per-CF memtable rotation. A CAS-based admission gate (`unified_mt.is_flushing`) ensures only one thread enters rotation at a time. The rotating thread creates a new skip list and WAL, atomically swaps the active pointer, enqueues the old memtable as an immutable, and submits a flush work item with `cf=NULL` to signal unified flush dispatch. The flush worker detects `cf==NULL` and routes to `tidesdb_unified_flush_immutable()`.

#### Backpressure in Unified Mode

Even though the memtable is shared, backpressure is still applied per column family. At commit time, the system iterates all CFs involved in the transaction and calls `tidesdb_apply_backpressure()` on each, which checks that CF's L0 immutable queue depth and L1 file count. This ensures that individual column families falling behind on flush or compaction still throttle writes appropriately.

#### WAL Lifetime

Each unified WAL has a one-to-one relationship with the unified immutable memtable it belongs to. There is no generation refcounting. The WAL is created when the unified memtable is created. After the flush worker successfully demuxes all entries into per-CF SSTables and commits their manifests, the closed WAL segment is uploaded to the object store if `replicate_wal` is enabled, then deleted locally. In non-object-store mode the WAL is deleted immediately after flush.

#### Configuration

Unified memtable mode is enabled via `unified_memtable = 1` in `tidesdb_config_t`. Additional configuration fields control the write buffer size (`unified_memtable_write_buffer_size`), skip list parameters (`unified_memtable_skip_list_max_level`, `unified_memtable_skip_list_probability`), and WAL sync mode (`unified_memtable_sync_mode`, `unified_memtable_sync_interval_us`). When `unified_memtable_write_buffer_size` is 0, it defaults to `TDB_DEFAULT_WRITE_BUFFER_SIZE` (64MB).

### Write Backpressure and Flow Control

When writes arrive faster than flush workers can persist memtables to disk, immutable memtables accumulate in the flush queue. Without throttling, this causes unbounded memory growth. The system implements graduated backpressure based on the L0 immutable queue depth and L1 file count.

Each column family maintains a queue of immutable memtables awaiting flush. When the active memtable exceeds the adaptive flush threshold, it becomes immutable and enters this queue. A flush worker dequeues it asynchronously and writes it to an SSTable at level 1. The queue depth indicates how far behind the flush workers are.

The system monitors two metrics: L0 queue depth, meaning the number of immutable memtables in the flush queue (configurable threshold, default 20), and L1 file count, meaning the number of SSTables at level 1 (configurable trigger, default 4). The system then applies increasing delays to transaction commits based on pressure, once per column family per commit.

At moderate pressure (50% of stall threshold or 3x L1 trigger), writes sleep for 0.5ms. This gently slows the write rate without significantly impacting throughput. At 50% of the default threshold (10 immutable memtables), writes experience minimal latency increase. The 0.5ms delay provides flush workers CPU time while remaining barely noticeable in multi-threaded workloads.

At high pressure (80% of stall threshold or 4x L1 trigger), writes sleep for 2ms. This more aggressively reduces write throughput to give flush and compaction workers time to catch up. At 80% of the default threshold (16 immutable memtables), write latency increases noticeably but writes continue. The 4x escalation creates a non-linear control response. Since flush operations take roughly 120ms, the 2ms delay gives workers meaningful time to drain the queue.

At the stall threshold (100% or above), writes block completely until the queue drains below the threshold. The system checks queue depth every 10ms, waiting up to 10 seconds before timing out with an error. This prevents memory exhaustion when flush workers cannot keep pace. At the default threshold of 20 immutable memtables, all writes stall until flush workers reduce the queue depth. The 10ms check interval balances responsiveness with syscall overhead.

#### Coordination with L1

The backpressure mechanism considers both L0 queue depth and L1 file count. High L1 file count indicates compaction is falling behind, which will eventually slow flush operations (flush workers must wait for compaction to free space). By throttling writes based on L1 file count, the system prevents a cascading backlog. L1 acts as a leading indicator, and throttling occurs before L0 pressure becomes critical.

#### Memory Protection

Each immutable memtable holds the full contents of a flushed memtable (64MB by default). The hard cap of 16 immutable memtables per column family limits queued immutable memory to 1.024GB. Combined with the active memtable (64MB), this bounds memory usage to roughly 1.09GB per column family under maximum write pressure, preventing out-of-memory conditions. The stall threshold (default 20) is higher than the hard cap, meaning writes block at the hard cap before reaching the stall threshold under normal conditions.

To prevent truly unbounded memory growth from immutable accumulation, the flush path enforces a hard cap of 16 immutable memtables per column family. When the queue reaches this limit, the flush path blocks until the flush worker drains the queue below the cap. This complements the L0 stall threshold (which slows writes) by providing an absolute ceiling on immutable memory.

#### Global Memory Pressure

Per-column-family backpressure alone cannot prevent OOM when many column families accumulate memory simultaneously. The system maintains a global memory pressure level computed by the reaper thread every 100ms. The reaper sums all active memtables, immutable memtable estimates (using `write_buffer_size` as a conservative bound on each immutable's data size), in-flight transaction memory (`txn_memory_bytes`), compaction temporary memory estimates, bloom filter bitsets, block index arrays, and cache memory across all column families. It then computes the ratio against a resolved memory limit (configurable via `max_memory_usage`, default 50% of system RAM, minimum 5% of system RAM). Column family creation validates that `write_buffer_size` does not exceed the resolved memory limit. Cache sizes are validated at open time and clamped to 30% of the limit if they would exceed it.

The pressure level is graduated: normal (below 60%), elevated (60 to 75%), high (75 to 90%), and critical (90% or above). The write path reads this level with a single atomic load per commit, adding zero overhead at normal pressure. At elevated pressure, the adaptive flush threshold tightens to 100% of `write_buffer_size` (no headroom) and the write path proactively triggers a non-forced flush on the current column family if it is not already flushing, plus a 0.2ms yield to slow ingestion and prevent escalation (skipped if L0/L1 backpressure already applied a delay on this commit). At high pressure, the write path force-flushes the current column family and sleeps for 2ms (skipped if L0/L1 already delayed), while the reaper force-flushes the largest non-flushing active memtable. At critical pressure, the write path performs a self-help flush on the current column family (if not already flushing) and then blocks writes entirely until the reaper brings pressure below critical, timing out after 10 seconds with `TDB_ERR_MEMORY_LIMIT`. The reaper responds to critical pressure with a nuclear flush, force-flushing every column family that is not already flushing, plus aggressive compaction on the column family with the most SSTables. The `is_flushing` and `is_compacting` atomic flags are checked at every level to prevent redundant operations and ensure relief efforts target actionable column families.

The L0 stall threshold scales dynamically in multi-CF deployments: the effective threshold is reduced when multiple column families share the memory budget, ensuring per-CF stall engages before global pressure reaches critical. An OS-level safety net polls `get_available_memory()` every roughly 5 seconds and overrides the pressure level to critical if real available memory drops below 5% of total system RAM, catching memory consumption from sources outside TidesDB's tracking.

#### Worker Coordination

The throttling mechanism assumes flush workers are making progress. If the queue depth remains at or above the stall threshold for 10 seconds (1000 iterations at 10ms each), the system returns an error indicating the flush worker may be stuck. This typically indicates disk I/O failure, insufficient disk space, or a deadlock in the flush path.

#### Configuration Interaction

Increasing `write_buffer_size` reduces flush frequency but increases memory usage during stalls. Increasing `l0_queue_stall_threshold` allows more memory usage but provides more buffering for bursty workloads. Increasing flush worker count reduces queue depth under sustained write load. Setting `max_memory_usage` caps the global memory envelope across all column families. The optimal configuration depends on write patterns, available memory, and disk throughput.

The graduated backpressure approach provides smooth degradation rather than traditional binary throttling (normal operation or complete stall), contributing to TidesDB's sustained write performance advantage.

## Read Path

### Search Order

A read searches for a key in the following order (Figure 5): the active memtable first, then immutable memtables from newest to oldest, then SSTables in level 1, then level 2, and so on. The search stops at the first occurrence. Since newer data resides in earlier locations, this finds the most recent version.
<div class="architecture-diagram">
<img src="/design-diags/05_read_path.png" alt="Figure 5. The read path for a point lookup.">
</div>

### SSTable Lookup

For each SSTable, the system first checks min/max key bounds using the column family's comparator. If a bloom filter exists (`enable_bloom_filter=1`), it checks that next. A negative result means the key is definitely absent. If a block index exists (`enable_block_indexes=1`), the system finds which block might contain the key. It then initializes a cursor at the block index hint (if available) or at the first block.

For each block, the system generates a cache key from column family name, SSTable ID, and block offset if the block cache exists. On a cache hit, it copies raw bytes from cache, decompresses if needed, and deserializes. On a cache miss, it reads the block from disk, decompresses if needed, deserializes, and caches the raw bytes. It then binary searches the block for the key. If the entry is found and has a vlog offset, the system reads the value from the value log.

The bloom filter (default 1% FPR) and block index are optional optimizations configured per column family. A bloom filter false positive requires a bloom filter check (memory access), a block index lookup (likely a cache miss and therefore a disk read), a block read and deserialize (another cache miss and disk read), and a binary search of the block (memory). That amounts to two disk reads for a key that does not exist. With 1% FPR and high query rate, this adds significant I/O.

The block cache uses a clock eviction policy with reference bits. Multiple readers share cached blocks without copying. The clock hand checks each entry's `ref_bit`: if `ref_bit == 0`, the entry is evicted; if `ref_bit > 0`, the bit is cleared to 0 (second chance) and the hand moves on. Readers increment `ref_bit` when accessing an entry, protecting it from eviction during use.

### Block Index

The block index enables fast key lookups by mapping key ranges to file offsets. Instead of scanning all blocks sequentially, the system uses binary search on the index to jump directly to the block that might contain the key.

#### Structure

The index stores three parallel arrays: `min_key_prefixes`, holding the first key prefix of each indexed block (configurable length, default 16 bytes); `max_key_prefixes`, holding the last key prefix of each indexed block; and `file_positions`, holding the file offset where each block starts.

#### Sparse Sampling

The `index_sample_ratio` (configurable via `TDB_DEFAULT_INDEX_SAMPLE_RATIO`, default 1) controls how many blocks to index. A ratio of 1 indexes every block; a ratio of 10 indexes every 10th block. Sparse indexing reduces memory usage at the cost of potentially scanning multiple blocks on lookup.

#### Prefix Compression

Keys are stored as fixed-length prefixes (default 16 bytes, configurable via `block_index_prefix_len`). Keys shorter than the prefix length are zero-padded. This trades precision for space: keys with identical prefixes may require scanning multiple blocks to disambiguate.

#### Binary Search Algorithm

The function `compact_block_index_find_predecessor()` finds the rightmost block where `min_key <= search_key <= max_key`. It first creates a search key prefix (padded with zeros if shorter than the prefix length). It exits early if the search key is less than the first block's min key, returning the first block. Otherwise, it performs binary search for blocks where `min_key <= search_key <= max_key`, returning the rightmost matching block to handle keys at block boundaries. If no exact match is found, it returns the last block where `min_key <= search_key`. This ensures the search always starts from the correct block, avoiding false negatives when keys fall between indexed blocks.

#### Early Termination

When a block index successfully identifies the target block, the point read path enables early termination. If the key is not found in the indexed block, the search stops immediately rather than scanning subsequent blocks. Since blocks are sorted, the key cannot exist in later blocks if it was not in the block the index pointed to. This optimization significantly reduces I/O for negative lookups and keys near block boundaries.

#### Serialization

The index serializes compactly using delta encoding for file positions (varints) and raw prefix bytes. The format is `varint(count)`, `varint(prefix_len)`, delta-encoded file positions, min key prefixes, and max key prefixes. This achieves roughly 50% space savings compared to storing absolute positions.

#### Custom Comparators

The index supports pluggable comparator functions, allowing column families with custom key orderings (uint64, lexicographic, reverse, and others) to use block indexes correctly.

#### Memory Usage

For an SSTable with 1000 blocks and default 16-byte prefixes, the index requires 32KB for prefixes plus 8KB for positions, totaling 40KB. With sparse sampling (ratio 10), this reduces to 4KB. The index is loaded into memory when an SSTable is opened and remains resident.

#### Usage in Seeks and Iteration

Block indexes are also used by iterator seek operations (`tidesdb_iter_seek()` and `tidesdb_iter_seek_for_prev()`). When seeking to a key, the block index finds the predecessor block using binary search, the cursor jumps directly to that block position, and the iterator scans forward (or backward for `seek_for_prev`) from there.

This optimization is critical for range queries. Without block indexes, seeking to a key in the middle of a large SSTable would require scanning all blocks from the beginning. With block indexes, the seek operation is O(log N) on the index plus O(M) scanning a few blocks, rather than O(N*M) scanning all blocks.

#### Block Reuse Fast Path

When an SSTable source already has a deserialized block loaded and the seek target falls within that block's key range (between the first and last key), the seek skips the expensive release, cache lookup, and deserialization cycle entirely and performs an in-place binary search on the existing block. This eliminates the dominant cost of repeated seeks to nearby keys. The fast path fires for both forward and backward seeks and handles edge cases where the target is before the current block (returns first entry) or after it (sequential advance to the next block via cursor_next, bypassing the block index binary search). For workloads with high seek locality, this reduces deserialization CPU from roughly 88% to roughly 8%. The sequential advance path is critical for monotonically advancing seeks (the common iteration pattern) where the next key is always in the next block.

#### Block Boundary Prefetch

When the iterator advances to the last entry in a klog block, it issues a `posix_fadvise` willneed hint on the next block's file position so the OS begins reading it into the page cache before the iterator actually needs it. This hides I/O latency for sequential iteration across block boundaries.

#### Block Cache Integration for Sequential Advance

When the iterator needs the next block during sequential advancement, it checks the block clock cache before falling back to a pread syscall. On a cache hit, the block data is pinned zero-copy from the cache, the indexed block header is stripped if present, and deserialization proceeds directly from cached memory without any I/O. On a cache miss, the block is read from disk and populated into the cache for subsequent iterations. This closes the gap where iterator seek operations were cache-aware but sequential advancement was not. For hot-set workloads where the same blocks are accessed repeatedly across range scans, point lookups by one thread populate blocks that other threads' iterators can then read from cache, enabling cross-path cache sharing.

#### Incremental Indexed Advance

When a cached block has a pre-built key offset index (the indexed block format produced by `tidesdb_build_indexed_block_data`), the iterator advance path parses only the single next entry directly from the raw bytes using the index table offsets instead of deserializing the entire block. Each `next()` call reads the 20-byte index entry to get the byte offset, key offset, key size, and absolute sequence number, then jumps to that position in the raw data to parse flags, value size, TTL, and vlog offset from a few varints. Key and value pointers reference the raw buffer directly via cache pin with zero copy. The seek path wires the index pointers from the cached block into the lazy state so the incremental advance fires on every cached block after a seek. Non-indexed blocks (cache miss, no pre-built index) fall back to full O(N) deserialization. This replaces the previous behavior where every `next()` call after a seek forced full deserialization of all entries in the block even though only one entry was needed.

#### Cached Memtable Sources

Iterator seek operations cache memtable sources (active memtable, immutable memtables, and transaction write buffer) on the iterator at creation time rather than recreating them on every seek call. This eliminates per-seek overhead of allocating source structs, initializing skip list cursors, traversing to the first entry, and creating initial key-value pairs. The active memtable is pinned with `try_ref` during iterator creation to prevent a concurrent rotation plus flush from freeing the memtable between the atomic load and the merge source creation. The pin is released after the merge source takes its own internal reference. Immutable memtables are snapshotted via the lock-free RCU snapshot mechanism with per-item `try_ref` for the same reason. The cached sources are repositioned to the target key on each seek using the existing cursor seek operations. A pre-allocated temporary source array on the iterator avoids malloc/free of the source list on every seek as well. Combined with the SSTable source cache (which persists across seeks via `cached_sources`), this means the hot seek path performs zero memory allocations.

## Compaction

### Strategy

The compaction strategy consists of three distinct policies based on the principles of the "Spooky" compaction algorithm described in academic literature, working in concert with Dynamic Capacity Adaptation (DCA) to maintain an efficient LSM-tree structure.

### Overview

The primary goal of compaction in TidesDB is to reduce read amplification by merging multiple SSTable files, cleaning up obsolete data, and maintaining an efficient LSM-tree structure. TidesDB does not use traditional selectable policies (like Leveled or Tiered); instead, it employs three complementary merge strategies that are automatically selected based on the current state of the database. The core logic resides in the `tidesdb_trigger_compaction` function, which acts as the central controller for the entire process.

### Triggering Process

Compaction is triggered when specific thresholds are exceeded, indicating that the LSM-tree structure requires rebalancing. It initiates under two conditions. First, when Level 1 accumulates a threshold number of SSTables (configurable, default 4 files), the system recognizes that flushed memtables are piling up and need to be merged down into the LSM-tree hierarchy. Second, when any level's total size exceeds its configured capacity, the system must merge data into the next level to maintain the level size invariant. Each level holds approximately N times more data than the previous level (configurable ratio, default 10x).

### Calculating the Dividing Level

The algorithm calculates a dividing level (X) that serves as the primary compaction target (Figure 6). This is not a theoretical reference point but rather a concrete level in the LSM-tree computed using:
<div class="architecture-diagram">
<img src="/design-diags/06_compaction.png" alt="Figure 6. Compaction and the dividing level.">
</div>

```
X = num_levels - 1 - dividing_level_offset
```

Where `dividing_level_offset` is a configurable parameter (default 2) that controls compaction aggressiveness. A lower offset means more aggressive compaction (merging more frequently into higher levels), while a higher offset defers compaction work.

For example, with 7 active levels and the default offset of 2:
```
X = 7 - 1 - 2 = 4
```

This means Level 4 serves as the primary merge destination.

### Selecting the Merge Strategy

Based on the compaction trigger and the relationship between the affected level and the dividing level X, the algorithm selects one of three merge strategies.

If the target level equals X, the system performs a dividing merge, merging all levels from 1 through X into level X+1. This is the default case when no level before X is overflowing.

If a level before X cannot accommodate the cumulative data, the system performs a full preemptive merge from level 1 to that target level. This handles cases where intermediate levels are filling up faster than expected.

After the initial merge, if level X is still full, the system performs a partitioned merge from level X to a computed target level z. This is a secondary cleanup phase that runs after the primary merge completes.

### The Three Merge Modes

The compaction algorithm employs three distinct merge methods, each optimized for different scenarios within the LSM-tree lifecycle.

#### Full Preemptive Merge

This is the most straightforward merge operation. It combines all SSTables from two adjacent levels into the target level.

It is used when a level before the dividing level X cannot accommodate the cumulative data from levels 1 through that level. It also serves as a fallback mechanism by the other merge functions when they cannot determine partitioning boundaries (for example, when there are no existing SSTables at the target level to use as partition guides).

The operation takes a `start_level` and `target_level` as input, opens all SSTables from both levels, and creates a min-heap containing merge sources from all SSTables. It iteratively pops the minimum key from the heap, writing surviving entries (non-tombstones, non-expired TTLs, keeping only the newest version by sequence number) to new SSTables at the target level. It fsyncs the new SSTables, commits them to the manifest, and marks old SSTables for deletion.

This mode is simple and effective for small-scale merges but generates potentially large output files since it does not partition the key space.

#### Dividing Merge

This is the standard, large-scale compaction method for maintaining the overall health of the LSM-tree. It is designed to periodically consolidate the upper levels of the tree into a deeper level.

It is used when the target level equals the dividing level X, which is the default case when no intermediate level is overflowing. This is the expected scenario during normal write-heavy workloads when Level 1 accumulates the threshold number of SSTables (default 4).

The merge combines all levels from Level 1 through the dividing level X into level X+1. If X is the largest level in the database, the system first invokes Dynamic Capacity Adaptation (DCA) to add a new level before performing the merge, ensuring there is always a destination level available. The merge is intelligent about partitioning: it examines level X+1 (the destination level) and extracts the minimum and maximum keys from each SSTable at that level. These key ranges serve as partition boundaries. The key space is divided into ranges based on these boundaries, and the merge is performed in chunks. Each chunk produces SSTables that cover only a single key range. This partitioning prevents the creation of monolithic SSTables and distributes data more evenly across the target level. If no partitioning boundaries can be determined (for example, if the target level is empty), the function falls back to calling `tidesdb_full_preemptive_merge`.

This mode handles large-scale data movement efficiently, produces smaller and more manageable output files due to partitioning, and is critical for maintaining read performance by preventing excessive file proliferation at upper levels.

#### Partitioned Merge

This is a specialized merge designed for secondary cleanup after the initial merge phase. It addresses scenarios where the dividing level X remains full after the primary merge operation.

It is used after the initial merge (dividing or full preemptive), when the dividing level X is still full and its size exceeds its capacity. The merge operates on a specific range of levels (from level X to a computed target level z) rather than merging all the way from Level 1. Like the dividing merge, it uses the largest level's SSTable key ranges as partition boundaries. It divides the key space and merges each partition independently, producing smaller output SSTables that each cover a single key range.

This approach is more focused and less resource-intensive than a full dividing merge, allowing the system to relieve pressure in a specific area of the LSM-tree without triggering a full tree-wide compaction. It is fast and targeted, and helps prevent compaction from falling behind during bursty write patterns.

When the partitioned merge targets the largest level, output SSTables are capped at `file_max = C_X` (the capacity of the dividing level), per Algorithm 2 of the Spooky paper. If a partition's output exceeds this threshold, it is split into multiple SSTables at klog block boundaries. This bounds transient space amplification to 1/T regardless of partition key distribution skew, ensuring all files at the largest level have similar sizes between `N_L/(T·2)` and `N_L/T` bytes.

### Dynamic Capacity Adaptation (DCA)

DCA is a separate mechanism from compaction. Whilst the three merge modes determine how to merge data, DCA determines when to add or remove levels from the LSM-tree structure and continuously recalibrates level capacities to match the actual data distribution.

DCA is not a constantly running process. Instead, it is triggered automatically after operations that significantly change the structure or data distribution of the LSM-tree. It runs after a compaction cycle completes, when the `tidesdb_trigger_compaction` function calls `tidesdb_apply_dca` at the end of its run. It also runs after a level is removed, when the `tidesdb_remove_level` function calls `tidesdb_apply_dca` to rebalance the capacities of the remaining levels.

#### Capacity Recalculation Formula

The core of DCA is the `tidesdb_apply_dca()` function, which recalculates the capacity of all levels based on the actual size of the largest (bottom-most) level. The formula used is:

```
C_i = N_L / T^(L-i)
```

Where `C_i` is the new calculated capacity for level i, `N_L` is the actual size in bytes of data in the largest level L (the ground truth of how much data exists), `T` is the configured level size ratio between levels (default 10, meaning each level is 10x larger than the one above), `L` is the total number of active levels in the column family, and `i` is the index of the current level being calculated.

The execution proceeds as follows. The system gets the current number of active levels, identifies the largest level and measures its current total size, iterates through all levels from Level 0 to Level L-2, applies the formula to calculate the new capacity for each level (with a minimum floor of `write_buffer_size`), and updates the capacity property accordingly.

This adaptive approach ensures that level capacities remain proportional to the real-world size of data at the bottom of the tree. As the database grows or shrinks, DCA automatically adjusts capacities to maintain optimal compaction timing, preventing both over-provisioned capacities (which cause high read amplification) and under-provisioned capacities (which cause excessive compaction and high write amplification).

#### Level Addition

DCA adds a new level when the dividing merge attempts to merge into the largest level (X is the maximum level number), or when a level exceeds its capacity and needs a destination level that does not yet exist.

The system creates a new empty level with capacity calculated using the formula `write_buffer_size * T^(level_num-1)`, where `level_num` is the new level's number. It atomically increments `num_active_levels` to reflect the new structure. Normal compaction then moves data into this new level. The data is not moved during level addition itself, to avoid complex data migration logic and potential key loss. After the compaction cycle completes, `tidesdb_apply_dca()` is invoked to recalculate capacities for all levels based on actual data distribution.

#### Level Removal

DCA removes a level when several conditions are met: the largest level has become completely empty after compaction, the number of active levels exceeds the configured minimum (default 5 levels), the level was not just added in the current compaction cycle (newly added levels are intentionally empty), and no pending flushes are queued and no SSTables exist at level 1.

The system verifies that `num_active_levels > min_levels` to prevent thrashing (repeatedly adding and removing levels). It updates the new largest level's capacity using the formula `new_capacity = old_capacity / level_size_ratio`, frees the empty level structure, atomically decrements `num_active_levels`, and invokes `tidesdb_apply_dca()` to rebalance all level capacities based on the new level count and the actual size of the new largest level.

#### Initialization

Column families start with a minimum number of pre-allocated levels (configurable via `min_levels`, default 5). During recovery, if the manifest indicates SSTables exist at level N where N exceeds min_levels, the system initializes with N levels to accommodate the existing data. If SSTables exist only at levels below min_levels (for example, only Levels 1 through 3), the system still initializes with min_levels (5), leaving upper levels (4 and 5) empty. This floor prevents small databases from thrashing between 2 and 3 levels and guarantees predictable read performance by maintaining a minimum tree depth. After initialization, `tidesdb_apply_dca()` is invoked to set appropriate capacities for all levels based on the actual data found during recovery.

### The Merge Process

All three merge policies share a common merge execution path with slight variations.

The system first opens all source SSTables, including the klog and vlog files for all SSTables involved in the merge from both the source and target levels. For each SSTable, it creates a merge source structure containing the source type, the current key-value pair being considered, and a cursor for iterating through the source.

Next, the system constructs a min-heap (`tidesdb_merge_heap_t`) with elements of type `tidesdb_merge_source_t*`. The heap orders sources by their current key using the column family's configured comparator.

The iterative merge proceeds by repeatedly popping the minimum element from the heap (the source with the smallest current key), advancing that source's cursor to the next entry, and sifting the source back down into the heap based on its new current key.

Filtering and deduplication happen during this process. Tombstone entries are discarded. Entries whose time-to-live has expired are discarded. When multiple sources contain the same key, only the version with the highest sequence number is kept. Older versions are discarded.

Surviving entries are written to new SSTables at the target level. Data is written in 64KB blocks. Values meeting or exceeding the configured threshold (512 bytes by default) are written to the value log, while the key log stores only the file offset. Smaller values are stored inline in the key log. Blocks are optionally compressed using the column family's configured compression algorithm.

After all data is written, the system appends auxiliary structures to each key log: a block index for fast lookups, a bloom filter for negative lookups (if enabled), and a metadata block with SSTable statistics. The system fsyncs both the klog and vlog files to ensure durability.

The new SSTables are committed to the manifest file, which tracks which SSTables belong to which levels. This operation is atomic: the manifest is written to a temporary file, fsynced, and atomically renamed over the original. Finally, the old SSTables from the source and target levels are marked for deletion. The actual file deletion may be deferred by the reaper worker to avoid blocking the compaction worker.

### Handling Corruption During Merge

If a source encounters corruption while its cursor is advancing, the `tidesdb_merge_heap_pop()` function detects the corruption via checksum failures in the block manager. It returns the corrupted SSTable to the caller for deletion. The corrupted source is removed from the heap, and the merge continues with the remaining sources. This ensures that compaction can complete even if one SSTable is damaged, allowing the system to recover by discarding the corrupted data.

### Value Recompression

Large values (those meeting or exceeding the value log threshold) flow through compaction rather than being copied byte-for-byte. The system reads the value from the source value log, recompresses it according to the current column family configuration (which may differ from the original compression setting), and writes the recompressed value to the destination value log. This allows compression settings to evolve over time without requiring a full database rebuild.

### Summary

TidesDB's compaction is a multi-faceted algorithm that employs three distinct merge policies, each optimized for different scenarios within the LSM-tree lifecycle. These policies work in concert with Dynamic Capacity Adaptation to automatically scale the tree structure up or down as data volume changes.

The system intelligently selects the appropriate merge strategy based on concrete triggers. When the target level equals the dividing level X, it performs a dividing merge. When a level before X cannot accommodate cumulative data, it performs a full preemptive merge. After the initial merge, if level X remains full, it performs a partitioned merge as a secondary cleanup phase. The dividing level itself is calculated using a simple formula (`num_levels - 1 - dividing_level_offset`) rather than being inferred from complex bottleneck analysis.

This design allows TidesDB to handle a wide range of workloads efficiently, from steady-state writes to sudden bursts, while maintaining both read and write performance through intelligent data placement and compaction scheduling.

## Recovery

On startup, the system scans each column family directory for write-ahead logs and SSTables. It reads the manifest file to determine which SSTables belong to which levels.

For each write-ahead log, ordered by sequence number, the system opens the log file, validates it by truncating partial writes at the end (permissive mode), deserializes entries into a new skip list with the correct comparator, and enqueues the skip list for asynchronous flushing.

The manifest tracks the maximum sequence number across all SSTables. Recovery updates the global sequence counter to one past this maximum, ensuring new transactions receive higher sequence numbers than any existing data.

For SSTables, the system uses strict validation, rejecting any corruption. This reflects the different roles of these two kinds of files: logs are temporary and rebuilt on recovery; SSTables are permanent and must be correct.

## Background Workers

Four worker pools handle asynchronous operations (Figure 7).
<div class="architecture-diagram">
<img src="/design-diags/07_background_workers.png" alt="Figure 7. Background worker pools.">
</div>

Flush workers (configurable, default 2 threads) dequeue immutable memtables and write them to SSTables. Multiple workers enable parallel flushing across column families.

Compaction workers (configurable, default 2 threads) merge SSTables across levels. Multiple workers enable parallel compaction of different level ranges.

The sync worker (1 thread) periodically fsyncs write-ahead logs for column families configured with interval sync mode. It scans all column families, finds the minimum sync interval, sleeps for that duration, and fsyncs all WALs. This worker is only started if any column family is configured with interval sync mode during startup. If none are, it is omitted entirely.

Column families configured with `TDB_SYNC_INTERVAL` propagate full sync to block managers during structural operations. When a memtable becomes immutable (rotation), the system escalates an fsync on the WAL to ensure durability before the memtable enters the flush queue. During sorted run creation and merge operations, block managers always receive explicit fsync calls regardless of the column family's sync mode. This ensures correct durability guarantees for interval-based syncing while maintaining the performance benefits of batched syncs for normal writes.

The reaper worker (1 thread) performs three duties each cycle: global memory pressure computation, retired array reclamation, and unused file handle eviction. It sleeps for `TDB_SSTABLE_REAPER_SLEEP_US` (100ms) between cycles.

### Global Memory Pressure

Each cycle, the reaper scans all column families to compute total memory usage: active memtable sizes (via atomic load), immutable queue estimates, bloom filter bitsets, block index arrays, and cache bytes. It divides this total by the resolved memory limit to produce a pressure level (normal, elevated, high, critical) stored atomically for the write path to consume. The reaper uses the `is_flushing` and `is_compacting` atomic flags to avoid redundant operations and target only actionable column families. When selecting a flush victim, it picks the column family with the largest active memtable that is not already flushing (mirroring the compaction victim selection which already filters by `!is_compacting`). At high pressure, the reaper force-flushes this single largest non-flushing column family. At critical pressure, the reaper performs a nuclear flush, force-flushing every column family that is not already flushing, to shed memory as fast as possible across the entire database. In both cases, the reaper also triggers aggressive compaction on the column family with the most SSTables (that is not already compacting), merging N SSTables into 1 to free N-1 bloom filters and block indexes, producing tighter replacements sized to the exact merged entry count.

### Retired Array Reclamation

When flush or compaction swaps a level's SSTable array (via atomic compare-and-swap), the old array cannot be freed immediately because concurrent readers may still be traversing it. Each level maintains an `array_readers` counter that readers increment before accessing the array and decrement after. Rather than spinning unboundedly waiting for readers to finish, which would block the flush or compaction worker and cause cascading stalls under mixed read-write workloads, the system attempts a brief spin (`TDB_DEFERRED_FREE_SPIN_ATTEMPTS`, default 64 iterations with `cpu_pause`) and, if readers are still active, pushes the retired pointer onto a lock-free deferred free list. The reaper sweeps this list every cycle, freeing entries whose level has no active readers (`array_readers == 0`). Entries that still have active readers are re-enqueued for the next sweep. The lock-free list uses atomic compare-and-swap for push (producers are flush/compaction workers) and atomic exchange for bulk steal (consumer is the reaper). At shutdown, `tidesdb_deferred_free_drain` force-drains any remaining entries after the reaper thread has been joined.

### File Handle Eviction

When the open SSTable count exceeds the limit (configurable via `max_open_sstables`, default 256 SSTables, equivalent to 512 file descriptors), the reaper sorts open SSTables by last access time (updated atomically on each SSTable open, not on every read) and closes the oldest `TDB_SSTABLE_REAPER_EVICT_RATIO` (25%). With more SSTables than the limit, the reaper runs the eviction logic continuously, causing file descriptor thrashing.

### Work Distribution

The database maintains two global work queues: one for flush operations and one for compaction operations. Each work item identifies the target column family. When a memtable exceeds its size threshold, the system enqueues a flush work item containing the column family pointer and immutable memtable. When a level exceeds capacity, it enqueues a compaction work item with the column family and level range.

Workers call `queue_dequeue_wait()` to block until work arrives. Multiple workers can process different column families simultaneously: worker 1 might flush column family A while worker 2 flushes column family B. Each column family uses atomic flags (`is_flushing`, `is_compacting`) with compare-and-swap to prevent concurrent operations on the same structure. Only one flush can run per column family at a time, and only one compaction per column family at a time. The `is_flushing` flag is cleared in the flush worker after flush I/O completes, ensuring only one flush lifecycle (rotation, enqueue, I/O, and cleanup) runs per column family at a time. This prevents cascading flush storms under write pressure. The public `tidesdb_is_flushing()` and `tidesdb_is_compacting()` functions check both the atomic flag and the respective work queue size, returning true if either indicates pending work.

The `tidesdb_purge_cf()` function provides a synchronous force-flush and aggressive compaction for a single column family. If unified memtable mode is enabled, it first rotates the unified memtable and waits for the flush to complete so that entries belonging to this CF are moved to SSTables. It then waits for any in-progress flush to complete, force-flushes the active per-CF memtable, waits for flush I/O to finish, then triggers synchronous compaction inline (bypassing the compaction queue) and waits for any queued compaction to drain. The `tidesdb_purge()` function applies this to all column families, rotating the unified memtable once upfront, and additionally drains both the global flush and compaction queues before returning. These are useful for manual maintenance, pre-backup preparation, or reclaiming space after bulk deletes.

The parallelism semantics are straightforward. Multiple flush and compaction workers can process different column families in parallel (cross-CF parallelism). A single column family can only have one flush and one compaction running at any time (within-CF serialization). Even if a CF has multiple immutable memtables queued, they are flushed sequentially.

Thread pool sizing follows from these semantics. For a single column family, set `num_flush_threads = 1` and `num_compaction_threads = 1`; additional threads provide no benefit since only one operation per CF can run at a time. For multiple column families, set thread counts up to the number of column families. With N column families and M flush workers (where M is at most N), flush latency is roughly N/M times the flush time. The global queue provides natural load balancing. For mixed workloads where some CFs are write-heavy and others read-heavy, the thread pool automatically prioritizes work from active CFs.

Workers coordinate through thread-safe queues and atomic flags. The main thread enqueues work and returns immediately. Workers process work asynchronously, allowing high write throughput.

## Error Handling

Functions return integer error codes. Zero indicates success; negative values indicate specific errors: `TDB_ERR_MEMORY` (-1) for allocation failure, `TDB_ERR_INVALID_ARGS` (-2) for invalid parameters, `TDB_ERR_NOT_FOUND` (-3) for key not found, `TDB_ERR_IO` (-4) for I/O errors, `TDB_ERR_CORRUPTION` (-5) for data corruption detected, `TDB_ERR_EXISTS` (-6) for resource already exists, `TDB_ERR_CONFLICT` (-7) for transaction conflict, `TDB_ERR_TOO_LARGE` (-8) for key or value too large, `TDB_ERR_MEMORY_LIMIT` (-9) for memory limit exceeded, `TDB_ERR_INVALID_DB` (-10) for invalid database handle, `TDB_ERR_UNKNOWN` (-11) for unknown error, and `TDB_ERR_LOCKED` (-12) for database locked by another process, and `TDB_ERR_READONLY` (-13) for write operations attempted on a read-only replica.

More status codes can be seen in the [C reference](/reference/c) section.

The system distinguishes transient errors (disk space, memory) from permanent errors (corruption, invalid arguments). Critical operations use fsync for durability. All disk reads validate checksums at the block manager level. At a higher level the system utilizes magic numbers to detect corruption at the SSTable level.

Several error scenarios deserve explicit discussion.

If the disk fills during flush, the flush fails and the memtable remains in the immutable queue. Writes continue to the active memtable. When the active memtable fills, writes stall since no more memtable swaps are possible. The system logs the error but does not fail writes until memory is exhausted.

If corruption is encountered during read, the system returns `TDB_ERR_CORRUPTION` to the caller. It does not mark the SSTable as bad; subsequent reads may succeed if the corruption is localized to one block.

If corruption is encountered during compaction, `tidesdb_merge_heap_pop()` detects it when advancing a source and returns the corrupted SSTable. Compaction marks it for deletion and continues with the remaining sources.

If a memory allocation fails during compaction, the compaction aborts and returns `TDB_ERR_MEMORY`. Old SSTables remain intact. Compaction retries on the next trigger.

If the comparator changes between restarts, keys will be in the wrong order within SSTables. Binary search will miss existing keys (returning NOT_FOUND for keys that exist). Iterators will return keys out of order. Compaction will produce incorrectly sorted output. The system does not detect comparator changes. This is a configuration error that corrupts the logical structure without corrupting the physical data.

Bloom filter false positives cause two unnecessary disk reads (block index plus block) but no errors.

## Design Rationale

### Block Size

Blocks balance compression efficiency and random access granularity. Larger blocks compress better because they provide more context for LZ4 and Zstd, but they require reading more data for point lookups. Smaller blocks reduce read amplification but compress poorly and increase block index size. The fixed 64KB block size matches common SSD page sizes and provides reasonable compression ratios (typically 2 to 3x for text data). The tradeoff is that a point lookup reads 64KB even for a 100-byte value.

### Level Size Ratio

Each level holds N times more data than the previous level. This determines write amplification. Lower ratios (5x) reduce write amplification but increase levels, which worsens reads. Higher ratios (20x) reduce levels but increase write amplification. The ratio is configurable per column family (default 10x).

### Write Amplification

In leveled compaction, each entry gets rewritten once per level it passes through. With ratio R and L levels, average write amplification is approximately R * L / 2 (not R * L) because data at shallow levels gets rewritten more than data at deep levels. For a 1TB database with default 64MB L1 and ratio 10, log base 10 of (1TB/64MB) gives approximately 7 levels, so roughly 35x average write amplification (not 70x). Actual write amplification depends on workload; updates to existing keys have lower write amplification than pure inserts.

### Read Amplification

Worst case reads one SSTable per level. With 7 levels, that is 7 disk reads without bloom filters. Bloom filters (1% FPR) reduce this. Expected reads are approximately 1 + 7 * 0.01 = 1.07 for absent keys. This is an approximation valid for small FPR (probability of no false positives across all levels is roughly 0.99^7, or about 0.93). For present keys, bloom filters do not help; the system still needs to read the actual block.

### Value Log Threshold

Values meeting or exceeding the configured threshold (512 bytes by default) go to the value log. This keeps the key log compact for efficient scanning. The threshold balances two costs: small thresholds cause many value log lookups (extra disk seeks), while large thresholds bloat the key log (more data to scan during iteration). The default 512 bytes is a heuristic, roughly the size where the indirection cost (reading vlog offset, seeking to vlog, reading value) becomes cheaper than scanning a large inline value during iteration.

### Bloom Filter FPR

The default 1% false positive rate balances memory usage and effectiveness. Lower FPR (0.1%) requires 10x more bits per key but only reduces false positives by 10x. Higher FPR (5%) saves memory but causes more unnecessary disk reads. At 1% FPR, a bloom filter uses roughly 10 bits per key. For 1M keys, that amounts to 1.25MB, small enough to keep in memory. The FPR is configurable per column family.

### Memtable Size

Larger memtables reduce flush frequency but increase recovery time and memory usage. Smaller memtables flush more often (more SSTables, more compaction) but recover faster. The default size is 64MB, which holds roughly 1M small key-value pairs and flushes every few seconds under moderate write load.

Increasing memtable size to 128MB reduces flush frequency by 2x but also increases L0 to L1 write amplification because each flush produces a larger SSTable that takes longer to merge. The optimal size depends on write rate and acceptable recovery time.

### Worker Thread Counts

The default configuration uses 2 flush workers and 2 compaction workers to enable parallelism across column families while limiting resource usage. More threads help with multiple active column families but increase memory (each worker buffers 64KB blocks during merge) and file descriptor usage (2 FDs per SSTable being read or written). The counts are configurable.

With N column families and 2 flush workers, flush latency is roughly N/2 times the flush time. Increasing to 4 workers halves latency but doubles memory usage during concurrent flushes.

On HDDs, multiple concurrent compaction workers cause head seeks, destroying throughput. On NVMe SSDs with high parallelism, multiple workers improve throughput. Choose worker counts based on storage device characteristics: 1 to 2 workers for HDD, 4 to 8 for NVMe.

## Operational Considerations

### Concurrency and Process Safety

TidesDB database instances are multi-thread safe and single-process exclusive.

#### Multiprocess Safety

Only one process can open a database directory at a time. The system acquires an exclusive file lock on a lock file named `LOCK` within the database directory during `tidesdb_open()`. The lock is non-blocking: if another process holds the lock, `tidesdb_open()` returns `TDB_ERR_LOCKED` immediately rather than waiting. The implementation uses platform-specific locking primitives. On macOS and BSD, it uses `fcntl()` F_SETLK, chosen over `flock()` because fcntl locks are not inherited across `fork()`, preventing child processes from inheriting the parent's lock. On older systems without F_OFD_SETLK, it uses `flock()`. On Linux 3.15 and later, it uses F_OFD_SETLK for per-file-descriptor semantics. On macOS and BSD, the system additionally writes the owning process's PID to the lock file after acquiring the lock, enabling detection of same-process double-open attempts (since fcntl allows the same process to re-acquire its own lock). The lock is released and the PID cleared during `tidesdb_close()`. On Windows, the system uses `LockFileEx()` with `LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY` for equivalent non-blocking exclusive locking. The lock acquisition includes retry logic (default 3 retries) specifically for `EINTR` errors, which occur when a signal interrupts the locking syscall. This ensures transient signal interruptions do not cause spurious lock failures.

### Memory Footprint

Per column family, the active memtable is configurable (default 64MB). Immutable memtables consume memtable_size times the queue depth, typically 1 to 2. The block cache is shared across all column families (configurable, default 64MB total). Bloom filters require roughly 10 bits per key across all SSTables (depending on FPR). Block indexes require roughly 32 bytes per block across all SSTables.

For a column family with 10M keys across 100 SSTables using defaults, that works out to roughly 12MB in bloom filters, 2MB in block indexes, and 128MB in memtables. The total comes to about 150MB plus the column family's share of the block cache.

The `max_memory_usage` configuration (default 0 for auto) sets an upper bound on total tracked memory across all column families. When set to 0, the system resolves this to 50% of total system RAM at startup, with a minimum floor of 5% of total RAM. The reaper thread monitors the aggregate of memtables, caches, bloom filters, and block indexes against this limit, applying graduated pressure to the write path and triggering force-flushes and aggressive compaction when usage exceeds thresholds. This prevents OOM in multi-column-family deployments where per-CF limits alone cannot bound aggregate memory consumption.

### Compaction Lag

Writes can outpace compaction if the write rate exceeds the compaction throughput. The system applies backpressure: when L0 exceeds 20 immutable memtables (configurable via `l0_queue_stall_threshold`), writes stall until flush workers catch up. This prevents unbounded memory growth but can cause write latency spikes.

### Disk Space

SSTables are immutable, so space is not reclaimed until compaction completes and old SSTables are deleted. In the worst case, during compaction both input and output SSTables exist simultaneously. For a level with 1GB of data, compaction temporarily requires 2GB. The system checks available disk space before starting compaction.

### File Descriptor Usage

Each SSTable uses 2 file descriptors (klog and vlog). When the number of SSTables exceeds the open file limit (default 256, equivalent to 512 open file descriptors), the reaper closes the least recently used files. With many SSTables, this can cause file descriptor thrashing as files are repeatedly opened and closed.

## Internal Components

TidesDB's internal components are designed as reusable, well-tested modules with clean interfaces. Each component solves a specific problem and integrates with the core LSM tree implementation through clearly defined APIs.

### Block Manager

The block manager provides a lock-free, append-only file abstraction with atomic reference counting and checksumming. Each file begins with an 8-byte header (3-byte magic "TDB", 1-byte version, 4-byte padding). Blocks consist of a header (4-byte size, 4-byte xxHash32 checksum), data, and footer (4-byte size duplicate, 4-byte magic "BTDB") for fast backward validation.

Writers use `pread`/`pwrite` for position-independent I/O, allowing concurrent reads and writes without locks. Block writes use `pwritev` to combine the header, data, and footer into a single scatter-gather syscall (3 syscalls down to 1), improving sequential and parallel write throughput by 2 to 2.5x. These POSIX functions are abstracted through `compat.h` for cross-platform support (Windows uses `ReadFile`/`WriteFile` with `OVERLAPPED` structures). The file size is tracked atomically in memory to avoid syscalls. Blocks use atomic reference counting: callers must call `block_manager_block_release()` when done, and blocks free when refcount reaches zero. Durability operations use `fdatasync` (also abstracted via `compat.h`).

Concurrent writers face a second contention point inside the kernel: filesystems take a per-inode write lock on any operation that advances the file's logical EOF (`i_rwsem` on Linux ext4, the vnode write lock on macOS APFS, the file-extension lock on NTFS). With many threads appending to the same block manager, this lock serializes them regardless of how cleanly the userland code hands out disjoint offsets. To keep the kernel out of the way, the block manager preallocates the file in 64 MB chunks (`BLOCK_MANAGER_PREALLOC_CHUNK`) ahead of writes via a cross-platform `tdb_preallocate_extent()` helper in `compat.h` (`fallocate` on Linux, `F_PREALLOCATE` plus `ftruncate` on macOS, `FILE_ALLOCATION_INFO` plus `FILE_END_OF_FILE_INFO` on Windows, `posix_fallocate` elsewhere). Subsequent `pwrite` calls land within the already-extended EOF and take only the cheaper read path on the inode lock. The extension itself is lock-free: a CAS on `preallocated_size` claims the right to extend, and racing claimants at worst issue a redundant idempotent `fallocate`. On clean close, `block_manager_close` truncates the file back to the actual data extent, so the trailing zeros only exist while the file is open. After a crash, `block_manager_validate_last_block` distinguishes a preallocation tail (all-zero suffix, legitimate) from real corruption (non-zero garbage past the data) by combining a forward scan with a trailing-zero check: strict mode accepts the former and rejects the latter, permissive mode truncates either. This yields 1.6 to 2x higher multi-writer throughput on small-block workloads (the WAL case) at the cost of bounded space amplification (one preallocation chunk per open file at runtime, zero at rest).

Block reads use two `pread` syscalls: one for the 8-byte header (size plus checksum) and one for the data payload directly into the final allocation, avoiding intermediate buffer copies. The fused `block_manager_cursor_read_and_advance()` operation combines read and cursor advance into a single call, using the block size from the just-read block to compute the next position without a redundant `pread`. Cursors also cache block sizes from previous operations, allowing `cursor_read_partial()` to skip the size lookup when the cache is valid. These optimizations reduce syscall overhead on the hot read path.

Block manager cursors enable sequential and random access. Cursors maintain current position and can move forward, backward, or jump to specific offsets. The `cursor_read_partial()` operation reads only the first N bytes of a block, useful for reading headers without loading large values.

The system supports strict and permissive validation modes. WAL files use permissive mode to handle crashes during writes. SSTable files use strict mode since they must be correct. Validation walks backward from the file end, checking footer magic numbers.

The block format provides layered protection against silent data corruption, whether from media degradation, controller firmware bugs, or bit flips in the storage path. Each block stores an xxHash32 checksum computed over the data payload at write time. On every read, the checksum is recomputed and compared against the stored value; any mismatch causes the read to fail immediately rather than return corrupt data. The block size field is stored twice, once in the header and once in the footer, so a single-bit corruption in either copy can be detected by cross-validation during backward cursor traversal. The footer magic number (0x42445442, "BTDB") acts as a high-entropy sentinel: random corruption is unlikely to produce it, so its absence reliably identifies torn writes and partial flushes. During recovery, permissive validation uses this structure to walk forward through WAL blocks, accepting blocks whose footer magic and header/footer size agree, and truncating at the first inconsistency. Forward cursor operations that encounter a checksum failure can call `block_manager_cursor_skip_corrupt()`, which distinguishes partial writes (footer magic absent, block extent known from the size field) from genuine corruption (footer magic present but data checksum fails), advancing past the former and rejecting the latter. The combination of per-block checksums, redundant size fields, and magic sentinels means that any single-point corruption, whether it hits the data, the metadata, or the framing, is detected before it can propagate to the application layer. SSTables inherit this protection directly since their klog and vlog files are block manager files. WAL files add an additional layer: entries are deserialized with bounds checking on every varint and field offset, so a corrupt WAL entry that passes the block checksum (for example, valid bytes rearranged by a controller bug) still fails deserialization rather than silently loading garbage into the memtable.

TidesDB uses block managers for all persistent storage: WAL files, klog files, and vlog files. The atomic offset allocation combined with file preallocation enables concurrent flush and compaction workers to write to different files simultaneously, and lets multiple writers share a single file (notably the WAL) without serializing on the kernel's per-inode write lock. The reference counting prevents use-after-free when multiple readers access the same SSTable.

### Bloom Filter

The bloom filter implementation uses a packed bitset (uint64_t words) with multiple hash functions to provide probabilistic set membership testing. The filter calculates optimal parameters from the desired false positive rate and expected element count: `m = -n*ln(p)/(ln(2)^2)` bits and `h = (m/n)*ln(2)` hash functions.

The filter serializes using varint encoding for headers and sparse encoding for the bitset, storing only non-zero words with their indices. This achieves 70 to 90% space savings for low fill rates (below 50%). The serialization format is varint(m), varint(h), varint(non_zero_count), then pairs of varint(index) and uint64_t(word).

The hash function uses Kirsch-Mitzenmacher double hashing. Two base hashes (h1 and h2) are computed using a multiplicative hash with seeds 0 and 1. The i-th hash function is derived as `h1 + i * h2`, producing h independent bit positions from only two hash computations. Each hash sets one bit in the bitset using Lemire's fast range reduction for uniform distribution across the bitset.

TidesDB creates one bloom filter per SSTable during flush and merges, adding all keys. The filter is serialized and written to the klog file after data blocks. During reads, the system checks the bloom filter before consulting the block index. With 1% FPR, this eliminates 99% of disk reads for absent keys. The filter is loaded into memory when an SSTable is opened and remains resident.

### Buffer

The buffer provides a lock-free slot allocator with atomic state machines and generation counters for ABA prevention. Each slot has four states: FREE (0), ACQUIRED (1), OCCUPIED (2), and RELEASING (3). State transitions use atomic compare-and-swap operations.

The `buffer_acquire()` function scans from a hint index (atomically incremented) to find a FREE slot, atomically transitions it to ACQUIRED, stores data, then transitions to OCCUPIED. If no slots are available, it retries with exponential backoff. The hint index reduces contention by spreading acquire attempts across the buffer.

Each slot maintains a generation counter incremented on release. This prevents ABA problems where a slot is released and reacquired between two operations. Callers can validate (slot_id, generation) pairs to ensure they are still referencing the same allocation.

The buffer supports optional eviction callbacks invoked when slots are released. This enables custom cleanup logic without requiring callers to track allocations.

TidesDB uses buffers for tracking active transactions in each column family (`active_txn_buffer`, configurable, default 64K slots). During serializable isolation, the system needs to detect conflicts between concurrent transactions. The buffer stores transaction entries that can be quickly scanned for conflict detection. The eviction callback (`txn_entry_evict`) frees transaction metadata when slots are released. The lock-free design allows concurrent transaction begins without blocking.

### Clock Cache

The clock cache implements a partitioned, lock-free cache with a hybrid hash table plus CLOCK eviction. Each partition contains a circular array of slots for CLOCK and a separate hash index for O(1) lookups. The hash index uses XXH3_64bits hashing with linear probing and a maximum probe distance of 128.

#### Partitioning

The cache divides into N partitions (default: 4 per CPU core, up to 512). Each partition has an independent CLOCK hand and hash index. Keys are hashed to partitions using `hash(key) & partition_mask`. This reduces contention: with 64 partitions and 16 threads, average contention is 16/64, or 0.25 threads per partition.

#### NUMA-aware Partition Routing

On multi-CCX processors (AMD Threadripper, EPYC), the cache detects L3 cache topology by reading `/sys/devices/system/cpu/cpu*/cache/index3/id` on Linux. CPUs sharing an L3 cache are grouped together, and partitions are divided equally among groups. When routing a key, the system calls `sched_getcpu()` (a fast vDSO call, roughly 5ns) to determine which L3 group the calling thread belongs to, then selects a partition local to that group. The group ID is cached in thread-local storage and re-probed every 4096 accesses to detect OS thread migrations across CCX or NUMA boundaries. This keeps the amortized cost negligible (one getcpu per several thousand cache ops) while catching migrations within seconds under normal access rates. On monolithic dies (single L3 group) or non-Linux platforms, this reduces to simple `hash & partition_mask`. On Windows, `GetCurrentProcessorNumber()` provides the CPU ID.

#### Cache-line-aligned Layout

The partition struct is carefully laid out to prevent false sharing. Cache line 0 holds read-only fields (slots pointer, hash index, masks) that are immutable after initialization. Cache line 1 holds eviction-path atomics (clock_hand, occupied_count, bytes_used) accessed only by writers. Cache line 2 holds per-partition hit/miss counters accessed only by readers. Statistics are aggregated from per-partition counters on demand, avoiding contention on global counters.

#### Lock-free Operations

Entries use atomic state machines (EMPTY, WRITING, VALID, DELETING). The `ref_bit` field encodes two things: the LSB is the CLOCK recently-used flag, and the upper bits are an active reader count (incremented by 2 per reader). Get operations are fully lock-free. They hash to the partition, prefetch the first hash index entry, probe the hash index for a matching slot while prefetching both the slot data and next hash index entry simultaneously to overlap memory latency, atomically increment the reader count, re-validate state, compare keys, and return the pointer. If hash index probing fails (rare overflow), a capped linear fallback scans up to 128 slots. Put operations claim a slot via the CLOCK eviction sweep, which starts from a thread-local position to reduce contention on the global clock_hand. The sweep prefetches 2 entries ahead during scanning. Key and payload are stored in a single allocation (8-byte aligned) to halve malloc calls and improve data locality.

#### Eviction

The CLOCK hand gives entries with the recently-used bit set a second chance by clearing the bit and moving on; entries with the bit clear and no active readers are evicted. Eviction checks active readers twice: once before clearing pointers, and again after clearing but before freeing, to handle races where a reader acquired a reference between the two checks. If readers appeared, the eviction is reverted (pointers restored, state reset to VALID). Partitions trigger proactive eviction when occupancy exceeds 85%.

#### Zero-copy Reads

The `clock_cache_get_zero_copy()` function returns a pointer to cached data without copying. The reader count in the upper bits of `ref_bit` protects the entry from eviction while in use. Callers must call `clock_cache_release()` to decrement the reader count when done.

#### Integration

When `block_cache_size` is configured, TidesDB creates two independent clock caches: one for raw klog block bytes (block-based format) and one for deserialized B+tree nodes. The block cache stores raw bytes (decompressed but not deserialized) inline, using keys formatted as "cf_name:klog_filename:block_offset" (for example, "users:L2P3_1336.klog:65536"). This yields roughly 20x smaller cache entries compared to caching deserialized blocks, dramatically improving cache hit rates (87% versus 3.7% for a 64MB cache with an 80MB dataset). The B+tree node cache uses "sstable_id:node_offset" with hex-encoded integers and stores fully deserialized node structures. On block cache hit, the system returns a copy of the raw bytes which the caller decompresses and deserializes. The `clock_cache_put_new` fast path skips redundant hash probes on cache-miss insertions since the caller just confirmed the key was absent. On B+tree cache hit, the system increments the ref_bit and returns the cached node without disk I/O. When an SSTable is closed or deleted, its B+tree node cache entries are invalidated by prefix to prevent use-after-free.

### Skip List

The skip list provides a lock-free, multi-versioned ordered map with MVCC support. Each key has a linked list of versions, newest first. Versions store sequence numbers, values, TTL, and tombstone flags. The skip list uses probabilistic leveling (default p=0.25, max_level=12) for O(log n) average search time.

Insert operations use optimistic concurrency: traverse to find position, create new node, then atomically CAS the forward pointers. If CAS fails (concurrent modification), the operation retries from the beginning. The implementation uses atomic operations for all pointer updates and supports up to `SKIP_LIST_MAX_CAS_ATTEMPTS` (1000) CAS attempts before failing.

The hot path `skip_list_put_with_seq()` uses stack-allocated update arrays for skip lists with max_level below 64, eliminating malloc/free overhead. This covers virtually all practical configurations since 64 levels can index 2^64 entries. The default configuration uses `skip_list_max_level = 12` and `skip_list_probability = 0.25`.

Skip lists can optionally be backed by a lock-free bump arena (`skip_list_new_with_arena()`). The arena allocates nodes and versions from contiguous memory blocks using thread-local block slots for the fast path (non-atomic pointer bump, zero contention). When a thread's local block is exhausted, a new block is allocated and linked via atomic CAS on the `current_block` pointer. A shared fallback block using `atomic_fetch_add` serves threads beyond the thread-local slot limit. All allocations are aligned to 8 bytes. Individual frees are no-ops; all memory is reclaimed in bulk when the arena is destroyed. This improves spatial locality during iteration (nodes are packed sequentially rather than scattered across the heap) and eliminates per-node `free()` overhead during skip list destruction. It is ideal for memtable skip lists that are filled, flushed to an SSTable, then freed whole. If `arena_initial_capacity` is 0, the skip list falls back to standard `malloc`/`free`.

Each key maintains a version chain. New writes prepend a version to the chain using atomic CAS on the version list head. Readers traverse the version chain to find the appropriate version for their snapshot sequence. Tombstones are represented as versions with the DELETED flag set.

Nodes store both forward and backward pointers at each level. Forward pointers enable ascending iteration, backward pointers enable descending iteration. The backward pointers are stored in the same array as forward pointers, at `forward[max_level+1+level]`. This enables O(1) access to the last element via `skip_list_cursor_goto_last()` and `skip_list_get_max_key()` using the tail sentinel's backward pointer.

Skip lists can be created with `skip_list_new_with_comparator_and_cached_time()` which accepts a pointer to an externally-maintained cached time value. This avoids repeated `time()` syscalls during iteration and lookups when checking TTL expiration. TidesDB maintains a global `cached_current_time` updated by the reaper thread and refreshed before compaction and flush operations.

The skip list supports pluggable comparator functions with context pointers. TidesDB uses this for column families with different key orderings (memcmp, lexicographic, uint64, int64, custom).

TidesDB uses skip lists for memtables. The lock-free design allows concurrent reads and writes without blocking. The multi-version storage implements MVCC: readers see consistent snapshots while writers add new versions. During flush, the system creates an iterator and writes versions in sorted order to SSTables.

### Queue

The queue provides a thread-safe FIFO with node pooling and blocking dequeue. It uses separate head and tail locks to reduce contention between enqueue and dequeue operations, plus an atomic size field for lock-free size queries.

The queue maintains a free list of reusable nodes (up to 64). When dequeuing, nodes are returned to the pool instead of freed. When enqueuing, nodes are allocated from the pool if available. This reduces malloc/free overhead for high-throughput workloads.

The `queue_dequeue_wait()` function blocks on a condition variable until the queue becomes non-empty or shutdown. This enables worker threads to sleep when idle instead of spinning. The shutdown flag allows graceful termination: workers wake up and exit when the queue is destroyed.

The size is stored atomically, allowing readers to query `queue_size()` without acquiring the lock. This is used by the flush drain logic to check if work remains without blocking.

TidesDB uses queues for work distribution to background workers. The flush queue holds immutable memtables awaiting flush. The compaction queue holds compaction work items. Workers call `queue_dequeue_wait()` to block until work arrives. The node pooling reduces allocation overhead when memtables flush frequently.

### Manifest

The manifest tracks SSTable metadata in a simple text format with reader-writer locks for concurrency. Each line represents one SSTable: `level,id,num_entries,size_bytes`. The manifest file begins with a version header and global sequence number.

The manifest maintains an in-memory array of entries with dynamic resizing (starts at 64, doubles when full). Entries are unsorted, so lookups are O(n). This is acceptable because manifest operations are infrequent (only during flush and compaction) and the number of SSTables per column family is typically under 1000.

The `tidesdb_manifest_commit()` function writes all entries to a temporary file, fsyncs it, and then atomically renames it over the original path. The manifest file is kept open for reading after each commit. This ensures the manifest is always consistent: either the old version or the new version is visible, never a partial update.

Reader-writer locks allow multiple concurrent readers (checking if an SSTable exists) but exclusive writers (adding or removing SSTables). The `active_ops` counter tracks ongoing operations, and `tidesdb_manifest_close()` waits for active_ops to reach zero before closing.

TidesDB uses one manifest per column family. During flush, the system adds the new SSTable to the manifest and fsyncs before deleting the WAL. During compaction, it adds new SSTables and removes old ones atomically. During recovery, it reads the manifest to determine which SSTables belong to which levels. The manifest is the source of truth for the LSM tree structure.

### Platform Compatibility (compat.h)

The `compat.h` header isolates all platform-specific code, enabling TidesDB to run on Windows (MSVC, MinGW), macOS, Linux, BSD variants, and Solaris/Illumos without changes to the core implementation. I/O operations (`pread`/`pwrite`, `fdatasync`) map to Windows equivalents (`ReadFile`/`WriteFile` with `OVERLAPPED`, `FlushFileBuffers`). Atomics use C11 `stdatomic.h` on modern compilers or Windows `Interlocked*` functions on older MSVC. Threading uses POSIX `pthread` (pthreads-win32 on MSVC, native on MinGW). File system operations (`opendir`/`readdir`) map to Windows `FindFirstFile`/`FindNextFile`. Semaphores use Windows APIs on MSVC, native `semaphore.h` elsewhere. Type definitions handle platform differences (`off_t`, `ssize_t`, format specifiers). Performance hints (`PREFETCH_READ`, `LIKELY`, `UNLIKELY`) use compiler intrinsics where available. Every source file includes `compat.h` first. The abstraction layer has zero runtime overhead: all macros and inline functions compile to native platform calls.

## Object Store Mode

TidesDB can optionally store SSTables in a remote object store (S3, MinIO, GCS, or any S3-compatible service) instead of relying solely on local disk. This enables cloud-native deployments where compute and storage are separated, local disk serves as a cache, and the object store provides durable, replicated storage. Object store mode uses unified memtable mode (automatically enabled at open time if not already set) and is activated by setting a pluggable connector on `tidesdb_config_t.object_store`.

### Pluggable Connector Interface

Object store access is abstracted behind a connector interface (`tidesdb_objstore_t`). Each connector implements seven operations (put, get, range_get, delete_object, exists, list, destroy) and carries an opaque context pointer for credentials and client handles. Connectors must be thread-safe since multiple threads may call concurrently. The connector's backend is identified by a `tidesdb_objstore_backend_t` enum (`TDB_BACKEND_FS`, `TDB_BACKEND_S3`) rather than an arbitrary string, preventing invalid backend configurations at compile time. TidesDB ships two connectors. The filesystem connector (`tidesdb_objstore_fs_create`) stores objects as files under a root directory, useful for testing and local replication. The S3 connector (`tidesdb_objstore_s3_create`) signs requests with AWS SigV4 and supports path-style and virtual-hosted URLs, working with AWS S3, MinIO, and other compatible endpoints. Object keys are path-like strings derived from the local file path relative to the database directory (for example, `cf_name/L1/sst_5.klog`).

### Storage Tiers and Data Lifecycle

Data flows through two tiers with well-defined transitions at each stage (Figure 8). The local tier is the database directory on local disk. All writes, flushes, and compactions produce files here using the same format and machinery as non-object-store mode. The remote tier is the object store. Files are uploaded after creation and downloaded on demand when not present locally.
<div class="architecture-diagram">
<img src="/design-diags/08_object_store.png" alt="Figure 8. Storage tiers in object store mode.">
</div>

A key-value pair moves through the following stages in order.

The entry begins in the active memtable, living in the unified skip list in memory and backed by the unified WAL on local disk. The reaper thread periodically syncs the WAL to the object store based on write volume (`wal_sync_threshold_bytes`).

When the memtable exceeds `unified_memtable_write_buffer_size`, it rotates to immutable and a flush work item is enqueued. The entry is still in memory and the WAL is still on local disk.

The flush worker then demuxes the unified immutable into per-CF SSTables, writing klog and vlog files to local disk. This is identical to non-object-store mode. The SSTable is added to the CF's level 1.

Immediately after flush, `tidesdb_level_add_sstable` uploads the klog and vlog synchronously to the object store and registers both files in the local cache via `tdb_local_cache_track`. The synchronous upload ensures the object store has a copy before local cache eviction can delete the file. The MANIFEST is uploaded asynchronously. At this point the SSTable exists in both tiers. The local copy serves reads with zero network latency.

The SSTable files remain on local disk as cache entries. Every read access calls `tdb_local_cache_touch` to promote the file to the head of the LRU list. As long as the file stays warm (accessed within the LRU window), it stays local.

When `local_cache_max_bytes` is set and new files push the cache over its limit, the cache evicts the least-recently-used files from the tail of the LRU list. SSTable pairs (klog and vlog) are always evicted together. The local files are deleted via `unlink`. The SSTable still exists in the object store. The SSTable reaper may also close the file's block managers independently when `max_open_sstables` is exceeded.

When a read needs an evicted SSTable, the behavior depends on the access pattern. Point lookups use `tidesdb_sstable_range_get_block` to fetch just the single needed klog block (typically 64KB) via one HTTP range request, bypassing the full file download entirely. The block is cached in the clock cache and promoted directly to the hot tier. Iterators use `tdb_objstore_prefetch_sstables` to download all needed SSTable files in parallel at iterator creation time, so sequential reads proceed at local disk speed. If range_get fails or the block index is not definitive, the system falls back to downloading the full file via `tdb_objstore_download_if_missing`.

When compaction merges SSTables, input files are downloaded if evicted. The output SSTable is written locally and uploaded. Input SSTables are deleted from both the object store (`tdb_objstore_delete_file`) and local disk (`tdb_unlink`), and removed from the local cache (`tdb_local_cache_remove`). The merged SSTable enters the upload stage.

The result is a four-tier hot/warm/cold/frozen hierarchy that naturally separates data by access recency.

The hot tier consists of the active memtable skip list and the block clock cache. Reads are served from memory with zero I/O. The clock cache holds recently accessed klog blocks as deserialized structures with pinned reader refs for zero-copy access. B+tree nodes have their own dedicated clock cache. This tier is bounded by `max_memory_usage` and `block_cache_size`.

The warm tier consists of SSTables whose block managers are open and whose files exist on local disk. Reads hit the OS page cache or local NVMe with microsecond latency. The SSTable reaper closes block managers for idle SSTables when `max_open_sstables` is exceeded, demoting them to the next tier.

The cold tier consists of SSTable files tracked by the local file cache but whose block managers have been closed by the reaper. The files still exist on local disk. A read triggers `tidesdb_sstable_ensure_open`, which reopens the block managers (no network I/O, just a local file open). The LRU cache evicts files from this tier when `local_cache_max_bytes` is exceeded, demoting them to frozen.

The frozen tier consists of SSTables that have been evicted from local disk but still exist in the object store. Point lookups fetch just the needed block via a single HTTP range request (roughly 64KB, roughly 50ms) and cache it directly in the hot tier (clock cache), never touching local disk. Iterators prefetch all needed SSTable files in parallel at creation time, transitioning them directly to warm. The frozen tier provides virtually unlimited capacity with access latency proportional to the operation type: one network round-trip for point lookups, parallel bulk download for scans.

Data naturally flows downward through these tiers as it ages. Recent writes live in hot memory. After flush they enter warm local disk. As the working set grows beyond local capacity, cold files get evicted to frozen. The block cache and LRU cache work together to keep the active working set in the fastest tiers while the object store provides the capacity floor. The system is self-tuning: frequently accessed SSTables stay promoted to warm and hot tiers automatically via LRU touch and clock cache access patterns.

### Write Path

The write path is unchanged at the memtable and WAL level. All writes go to the unified memtable and unified WAL as usual. When the memtable is flushed, the flush worker writes per-CF SSTables to local disk. After `tidesdb_level_add_sstable` writes the SSTable locally, it uploads the klog and vlog files synchronously to the object store with retry (3 attempts with exponential backoff) and post-upload verification (size check). The synchronous upload ensures the object store has a copy before local cache eviction can delete the file. The MANIFEST is uploaded asynchronously after each flush and compaction when `sync_manifest_to_object` is enabled (default), ensuring the remote store has the latest SSTable inventory without blocking the flush worker. Closed unified WAL segments are uploaded to the object store before local deletion when `replicate_wal` is enabled, with upload timing controlled by `wal_upload_sync` (synchronous or background via the upload thread pool).

### Read Path

Point lookups and iterators follow the same search order as non-object-store mode (active memtable, immutable memtables, SSTables level by level). The read path diverges based on access pattern when an SSTable is frozen (not present on local disk).

For point lookups, `tidesdb_sstable_get` performs the bloom filter check and block index binary search using in-memory metadata (loaded at startup, always resident). These checks reject most SSTables without any I/O. When a definitive block index hit identifies the target block, and the klog file is not local, the function calls `tidesdb_sstable_range_get_block` to fetch just that one block (roughly 64KB) from the object store via a single HTTP range request. The block header and data are read in one call, the XXH32 checksum is verified, and the data is decompressed. The result is cached in the clock cache so subsequent lookups for keys in the same block are pure memory hits with zero network I/O. If the value resides in the vlog (`vlog_offset > 0`), a second range request via `tidesdb_vlog_range_get_value` fetches just that vlog block. If range_get fails or the block index is not definitive (sampling ratio != 1), the function falls through to the standard full-file download path.

For iterators, when creating merge sources from SSTables, the iterator calls `tdb_objstore_prefetch_sstables`, which identifies all non-local klog and vlog files and downloads them in parallel using bounded threads (`max_concurrent_downloads`, default 8). Downloads are batched and run concurrently so the total prefetch time is bounded by network latency plus the size of the largest file, not the sum of all files. By the time the lazy merge sources are created, all files are local and sequential reads proceed at local disk speed. Prefetch runs both at initial iterator creation and when the source cache is rebuilt after a seek invalidation.

When the object store is unavailable or range_get returns an error, reads fall through to `tdb_objstore_download_if_missing`, which downloads the full file with retry (3 attempts, exponential backoff 50ms/200ms/800ms). The download checks whether the object exists before attempting retrieval. If the `exists` check returns an error (network failure) rather than a definitive "not found", the download is attempted anyway since the store may be reachable for GET but not HEAD. Downloaded files are tracked by the local cache and subject to LRU eviction.

### Compaction

Compaction operates on local files with object store integration at the input, output, and cleanup boundaries. When `object_prefetch_compaction` is enabled (default 1), all three merge strategies (full preemptive, dividing, partitioned) call `tdb_objstore_prefetch_sstables` on the collected input SSTables before the merge begins, downloading evicted klog and vlog files in parallel using bounded threads (`max_concurrent_downloads`). When disabled, input SSTables are downloaded on demand during merge source creation via `tidesdb_sstable_ensure_open`, one at a time. The output SSTable is written locally, uploaded synchronously, and the MANIFEST is committed to local disk and uploaded to the object store before old input SSTables are cleaned up. This ordering ensures replicas and cold-start nodes can see the new merged SSTable before the old inputs are removed. Old input SSTables are then deleted from the MANIFEST (one commit per input, each followed by a MANIFEST upload), and when their reference count reaches zero, deleted from both the object store (with retry and exponential backoff matching the upload path) and local disk via `tdb_unlink`, and removed from the local cache via `tdb_local_cache_remove`.

When `object_lazy_compaction` is enabled (default 0), the level 1 file count compaction trigger is doubled, reducing compaction frequency and thus remote I/O at the cost of higher read amplification. Both fields are persisted to config.ini and survive restarts.

### Cold Start Recovery

When a node starts with an empty local directory but a configured object store, `tdb_objstore_cold_start_discover` runs during database recovery. It lists all objects in the store, identifies column families by their MANIFEST files (keys matching `cf_name/MANIFEST`), and downloads the config.ini and MANIFEST for each discovered CF in parallel using one thread per CF. The recovery code then reads each MANIFEST to reconstruct the SSTable inventory, downloads SSTable metadata (bloom filter, block index, min/max keys) to build in-memory state, and leaves the actual SSTable data in the object store until queries arrive. This makes cold start proportional to network latency (parallel metadata download) rather than the total data size or number of column families.

### Periodic WAL Sync

The reaper thread periodically uploads the active unified WAL to the object store based on write volume rather than wall clock time. The reaper reads the WAL's `current_file_size` atomic (lock-free, zero contention with writers) every cycle (roughly 100ms) and uploads when the delta since the last sync exceeds `wal_sync_threshold_bytes` (default 1MB, configurable, 0 to disable). During idle periods no syncs occur. During write bursts syncs fire more frequently. The WAL is append-only so uploading a snapshot mid-write is safe. On cold start, recovery downloads and replays the WAL normally. This bounds the data loss window on crash to the configured byte threshold worth of writes rather than the full flush cycle.

### WAL Replication

When `replicate_wal` is enabled (default), closed WAL segments are uploaded to the object store after flush. This provides a replication mechanism where another node can recover uncommitted data by downloading and replaying WAL segments. The `wal_upload_sync` flag controls whether the upload blocks the flush path (synchronous, stronger durability) or runs in the background (asynchronous, lower latency).

### Local File Cache

The local file cache (`tdb_local_cache_t`) tracks downloaded and locally written SSTable files using a 256-bucket XXH32 hash table for O(1) path lookups combined with a doubly-linked LRU list for eviction ordering. When `local_cache_max_bytes` is set, the cache evicts least-recently-used files to stay within the limit. SSTable file pairs (klog and vlog) are always evicted together to prevent a state where one half of the pair is cached but the other must be re-downloaded. Files are touched on access to update their position in the LRU list. The cache works alongside the SSTable reaper, which closes block managers for idle SSTables. Even when a file is evicted from local disk, re-downloading it from the object store is transparent to the read path.

### Replica Mode

TidesDB supports read-only replicas that follow a primary node through the object store. The primary handles all writes and uploads SSTables, MANIFESTs, and WAL segments. Replicas poll the object store for updates and serve reads from the same data without accepting writes.

A replica is enabled by setting `replica_mode = 1` on `tidesdb_objstore_config_t`. In replica mode, `tidesdb_txn_put` and `tidesdb_txn_delete` return `TDB_ERR_READONLY` immediately. Read transactions work normally using the same MVCC isolation levels, iterators, bloom filters, and block caches as the primary.

Before each MANIFEST sync cycle, the reaper discovers new column families in the object store that do not exist locally and creates them automatically by downloading their config and MANIFEST. This allows a replica to pick up CFs created by the primary after the replica started. The reaper then polls the remote MANIFEST for each column family every `replica_sync_interval_us` (default 5 seconds). `tdb_replica_sync_manifests` downloads each CF's MANIFEST to a temporary file, diffs it against the local MANIFEST, adds new SSTables (following the same pattern as cold start recovery), and removes SSTables that the primary compacted away. SSTable data is not downloaded during sync; it is fetched on demand via range_get for point lookups or prefetch for iterators.

When `replica_replay_wal` is enabled (default), the reaper discovers all available unified WAL segments from the object store via listing, sorts them by generation, and replays new entries from each into the unified memtable. Replay is idempotent using sequence numbers. Entries with sequence numbers at or below the current `global_seq` are skipped. This gives the replica access to writes that the primary committed but has not yet flushed to SSTables, even when the primary has rotated through multiple WAL generations between sync intervals. The replica's memtable is ephemeral and rebuilt from the primary's WAL segments on each sync cycle.

For tighter replication lag, the primary can set `wal_sync_on_commit = 1`, which uploads the WAL synchronously after every `tidesdb_txn_commit`. This ensures the replica sees committed data within one sync interval rather than waiting for the periodic WAL threshold upload. The tradeoff is one additional HTTP round-trip per commit on the primary.

The replica's view of the data lags behind the primary by at most `replica_sync_interval_us` plus network latency. With `wal_sync_on_commit` enabled on the primary and a 1-second sync interval on the replica, the lag is bounded to approximately 1 second.

### Primary Promotion

When the primary fails, a replica can be promoted to primary via `tidesdb_promote_to_primary`. The function first waits for any in-progress reaper sync cycle to complete to avoid lock contention with the first post-promotion query, then performs a final MANIFEST sync and WAL replay to capture any last writes from the old primary, creates a local WAL for crash recovery of new writes, and atomically switches `replica_mode` to 0. After promotion, the node accepts writes immediately.

Promotion is fast since the replica already has the MANIFEST and SSTable metadata in memory from the sync loop. The only work is one final WAL download plus replay and a WAL file creation. An external orchestration layer (health checks, DNS failover, Kubernetes operator, or a coordination service) handles the decision of when to promote.

### Node Failure and Recovery

The storage engine remains fully multi-writer within a single process. Multiple threads can write concurrently through transactions with full MVCC isolation, just as in non-object-store mode. The single-writer constraint applies only at the object store level, where one node at a time owns the bucket and uploads SSTables, MANIFESTs, and WAL segments.

On clean shutdown, `tidesdb_close` shuts down the upload pipeline first to drain any pending WAL uploads, then flushes the active unified memtable to SSTables before stopping workers. The object store receives all committed data. On crash, the data loss window depends on configuration. With `wal_sync_on_commit = 1`, every committed write is in S3 (RPO = 0). With `wal_sync_threshold_bytes` set to 1MB (default), the worst case is 1MB of writes since the last WAL sync. Setting it to 0 disables periodic WAL sync, in which case the RPO equals one full flush cycle. On clean shutdown there is no data loss.

Recovery without replicas follows the cold start path. A new node starts with an empty local directory, discovers CFs from the object store via `tdb_objstore_cold_start_discover` (parallel MANIFEST download), and reconstructs the SSTable inventory. SSTable data is fetched on demand as queries arrive.

Recovery with replicas is faster. The replica already has the MANIFEST and metadata in memory from the sync loop. Calling `tidesdb_promote_to_primary` does a final sync, creates a WAL, and starts accepting writes. No cold start discovery is needed.

The recovery time objective (RTO) depends on the deployment. With a warm replica, promotion takes milliseconds. With cold start from S3, it takes approximately one network round-trip (parallel MANIFEST download) plus on-demand SSTable fetches for the first queries.

Within the owning node, the engine's full concurrency model applies. Multiple application threads can call `tidesdb_txn_commit` concurrently, the unified memtable handles concurrent inserts via its skip list, and flush and compaction workers run in parallel. The object store upload pipeline is also multi-threaded (default 4 upload threads). The constraint is that only one node at a time should own the object store bucket. Two nodes writing to the same bucket would produce conflicting MANIFEST uploads, overlapping SSTable IDs, and race conditions on compaction deletes.

### Failure Handling and Monitoring

Upload failures are tracked via `total_upload_failures` on `tidesdb_db_stats_t`, allowing operators to monitor object store health. The shutdown log reports both successful uploads and permanent failures. Download failures after all retry attempts return `TDB_ERR_IO` to the caller, which propagates to the transaction as a read error. The `exists` check before downloads distinguishes between "object not in store" (returns success, the file is being created locally for the first time) and "network error" (falls through to attempt the download anyway). At shutdown, the upload pipeline sends poison pill sentinels to each worker thread and calls `queue_shutdown` to broadcast-wake all blocked workers, ensuring prompt thread termination on all platforms including MinGW where condition variable timeouts may not behave reliably.

## Testing and Quality Assurance

TidesDB employs comprehensive testing with CI/CD automation across 10 or more platform and architecture combinations. Each internal component has dedicated test files (`block_manager__tests.c`, `skip_list__tests.c`, `bloom_filter__tests.c`, and others) with unit tests, integration tests, and performance benchmarks. The main integration suite (`tidesdb__tests.c`) contains tests covering the full database lifecycle: basic operations, transactions across all isolation levels, persistence, WAL recovery, compaction strategies, iterators, TTL, compression, bloom filters, block indexes, concurrent operations, edge cases, and stress tests. This is not including the tests within each modular component. Test utilities (`test_utils.h`) provide assertion macros, execution harnesses with colored output, and test name filtering. Any test binary accepts an optional command-line argument to run only tests whose names contain the given substring (for example, `./build/tidesdb_tests checkpoint` runs only checkpoint-related tests).

The CMake build system automatically configures for Linux (x64, x86, PowerPC), macOS (x64, x86, Intel, Apple Silicon), Windows (MSVC x64/x86, MinGW x64/x86), BSD variants, and Solaris/Illumos. It manages dependencies via vcpkg (Windows with binary caching), Homebrew (macOS), and pkg-config (Linux), handles cross-compilation for PowerPC with custom-built dependencies, enables sanitizers (AddressSanitizer, UndefinedBehaviorSanitizer) on Unix platforms, provides 30 or more benchmark configuration variables, and registers tests with CTest for execution.

GitHub Actions CI builds and tests all 15 or more platform and architecture combinations, installs compression libraries (zstd, lz4, snappy) and pthreads on each platform, cross-compiles PowerPC builds with dependencies built from source, and runs tests via CTest (native platforms) or QEMU emulation (PowerPC). A cross-platform portability test creates a database on Linux x64, uploads it as an artifact, downloads it on 7 different platforms, and verifies all keys are readable with correct values, proving the database format is truly portable across architectures and endianness. Windows builds use vcpkg binary caching to reduce build times from over 20 minutes to 2 to 3 minutes on cache hits.  When it comes to object storage there is dedicated workflows testing object store capabilities utilizing local S3 supported storage and by default we use MinIO though this will be replaced soon.  

The testing infrastructure ensures TidesDB maintains correctness, performance, and portability across all supported platforms.
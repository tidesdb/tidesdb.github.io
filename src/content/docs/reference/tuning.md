---
title: TidesDB Tuning Reference
description: Official TidesDB tuning reference
---

<div class="no-print">

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/tidesql.md).

<hr/>

</div>


This reference gives small, mid, and large scale configuration presets for the
engine and column families
configuration, tuned for modern systems. These configurations can be applied to integrations such as FFI libraries and TideSQL. Every number here
is derived from the engine knobs, defaults, and clamps in `tidesdb.h` and
`tidesdb.c`, not from guesswork. Read the mental model first, then pick the tier
that matches your hardware and adjust it with the workload overlays.

The code ships with a 64 MB write buffer, a level ratio of 10, a 1 percent bloom
false-positive rate, a 512 byte value threshold, an L1 trigger of 4, an L0 stall
of 10, two flush and two compaction threads, a 64 MB block cache, 256 open
SSTables, a memory limit of 50 percent of RAM, READ_COMMITTED isolation, and LZ4
compression. The presets below move away from these defaults only where a tier
benefits.

---

## What "modern systems" means here

| Tier | Profile | RAM for the DB | Cores | Storage | Scale |
|------|---------|---------------|-------|---------|-------|
| Small | edge, container, sidecar, embedded | 1 to 4 GB | 2 to 4 | eMMC / SATA SSD / constrained NVMe | up to tens of GB, a handful of CFs |
| Mid | single production server, typical cloud VM | 8 to 32 GB | 8 to 16 | NVMe SSD | up to ~1 TB, dozens of CFs |
| Large | storage node, high-end server | 64 to 512 GB | 32 to 128 | fast NVMe (or striped) | multi-TB, many CFs, high concurrency |

---

## The mental model

A few formulas in the engine determine almost everything, so it is better to
tune with these in mind than knob by knob.

Per-CF write memory is bounded by two mechanisms acting together. The L0 stall
throttles writes once the immutable queue reaches `l0_queue_stall_threshold`, and
each immutable holds one `write_buffer_size`. The active memtable is hard-capped
at `2 x write_buffer_size`. The worst-case steady-state memory for one busy
column family is therefore about

```
per_cf_mem  ~=  l0_queue_stall_threshold * write_buffer_size   (queued immutables)
              + 2 * write_buffer_size                          (active memtable ceiling)
              + bloom filters + block indexes                  (small, resident)
```

Above the stall sits a last-resort hard cap of `l0_queue_stall_threshold + 6`
immutables. It scales with the threshold, so raising the threshold raises the cap
in lockstep and there is no hidden ceiling.

When more than one column family shares the database in per-CF mode, the
effective L0 stall is reduced to
`resolved_memory_limit / (num_cfs * write_buffer_size)`, floored at 2. The more
column families you run this way, the sooner each one stalls, so the total never
exceeds the memory budget. If you have many column families, either give the
database a larger `max_memory_usage` or switch to unified memtable mode, which
shares one queue and ignores this split.

A `max_memory_usage` of 0 resolves to 50 percent of system RAM, with a floor of 5
percent. A non-zero value is honored but clamped up to that 5 percent floor. The
block cache is clamped separately so that both internal caches together use at
most 30 percent of the resolved limit. Set the limit explicitly in containers,
where the host RAM the engine measures is not your cgroup limit.

Each open SSTable holds two file descriptors. At open time the engine clamps
`max_open_sstables` to `(fd_limit - 64) / 2`, so a target of N open SSTables needs
roughly `2N + 64` descriptors. About one eighth of that budget is reserved for the
write path, and reads back off with the retryable `TDB_ERR_BUSY` at the cap. To
run a large `max_open_sstables`, raise the ceiling before `tidesdb_open()`.

```c
tidesdb_raise_open_file_limit(32768);  /* opt-in, POSIX RLIMIT_NOFILE / Windows CRT cap */
```

The `max_concurrent_flushes` count is pinned one to one to `num_flush_threads` at
open, and a mismatch is normalized with a warning. A single hot column family
drains its immutable queue at the speed of the flush pool. Compaction runs one
round per column family, but each round fans out across the compaction pool
through sub-compaction.

---

## Database-level presets

| Field | Small | Mid | Large | Notes |
|-------|-------|-----|-------|-------|
| `num_flush_threads` | 2 | 4 | 8 to 16 | match to concurrently hot CFs; pins `max_concurrent_flushes` |
| `num_compaction_threads` | 2 | 4 | 8 to 16 | up to core count on NVMe, 1 to 2 on HDD |
| `block_cache_size` | 32 MB | 1 to 4 GB | 16 to 64 GB | shared across all CFs; clamped to 30 percent of mem limit |
| `max_open_sstables` | 64 to 128 | 512 to 1024 | 4096 to 16384 | needs `2N + 64` fds; raise ulimit for mid and large |
| `max_memory_usage` | 512 MB to 1 GB | 0 (50 percent RAM) or explicit | explicit (~50 percent RAM) | set explicitly inside containers |
| `log_to_file` | 1 | 1 | 1 | keep `LOG` in the data dir |
| `log_level` | `TDB_LOG_WARN` | `TDB_LOG_WARN` | `TDB_LOG_INFO` | drop to WARN in steady state |
| `unified_memtable` | 0 (1 if many CFs) | per workload | per workload | see the many-column-family overlay |

The `max_concurrent_flushes` field is left at its default so it tracks
`num_flush_threads`.

---

## Column-family presets

| Field | Small | Mid | Large | Notes |
|-------|-------|-----|-------|-------|
| `write_buffer_size` | 8 to 16 MB | 64 MB | 128 to 256 MB | bigger batches, more memory, bigger L1 SSTables |
| `level_size_ratio` | 10 | 10 | 10 (12 to 15 for multi-TB) | higher ratio means fewer levels and more write amp |
| `min_levels` | 1 | 1 | 1 to 2 | a deeper floor avoids early level churn on big sets |
| `dividing_level_offset` | 1 | 1 | 1 | lower is more aggressive compaction |
| `l0_queue_stall_threshold` | 6 to 8 | 10 | 16 to 20 | drives per-CF write memory (see model) |
| `l1_file_count_trigger` | 4 | 4 | 4 to 8 | higher tolerates burstier flushing |
| `klog_value_threshold` | 512 | 512 | 512 to 1024 | values at or above this go to the value log |
| `compression_algorithm` | `TDB_COMPRESS_LZ4` | `TDB_COMPRESS_LZ4` | `TDB_COMPRESS_LZ4` (`ZSTD` for cold) | LZ4 is the throughput default |
| `enable_bloom_filter` | 1 | 1 | 1 | almost always worth it |
| `bloom_fpr` | 0.01 | 0.01 | 0.01 (0.005 read-heavy) | lower FPR means more bits per key |
| `enable_block_indexes` | 1 | 1 | 1 | required for fast seeks |
| `index_sample_ratio` | 1 | 1 | 1 | 1 indexes every block, making lookups definitive |
| `block_index_prefix_len` | 16 | 16 | 16 to 32 | raise if keys share long prefixes |
| `sync_mode` | `TDB_SYNC_INTERVAL` | `TDB_SYNC_INTERVAL` or `FULL` | `TDB_SYNC_INTERVAL` or `FULL` | see durability |
| `sync_interval_us` | 128000 | 128000 | 128000 | only used with INTERVAL |
| `default_isolation_level` | `READ_COMMITTED` | `READ_COMMITTED` | per workload | SERIALIZABLE only when you need SSI |
| `use_btree` | 0 | 0 (1 for point and seek-heavy) | 0 (1 for point and seek-heavy) | B+tree klog favors point lookups and seeks |

### What each tier costs in memory

Using the per-CF model above, one busy column family bounds to roughly the
following.

| Tier | buffer | L0 stall | worst-case per-CF write memory |
|------|--------|----------|-------------------------------|
| Small | 16 MB | 8 | 8x16 + 2x16 = ~160 MB |
| Mid | 64 MB | 10 | 10x64 + 2x64 = ~768 MB |
| Large | 128 MB | 16 | 16x128 + 2x128 = ~2.3 GB |

Multiply by the number of concurrently hot column families and keep the total
under `max_memory_usage`. In per-CF mode the engine auto-scales the stall down to
protect the budget, but sizing it yourself avoids surprise throttling.

### What each tier costs in file descriptors

| Tier | `max_open_sstables` | fds needed (`2N + 64`) | recommended `ulimit -n` |
|------|--------------------|------------------------|-------------------------|
| Small | 128 | ~320 | 1024 (default is fine) |
| Mid | 1024 | ~2112 | 4096 or more |
| Large | 8192 | ~16448 | 32768 or more (call `tidesdb_raise_open_file_limit`) |

---

## Full examples

### Small

```c
tidesdb_config_t db = tidesdb_default_config();
db.db_path             = "./data";
db.num_flush_threads   = 2;
db.num_compaction_threads = 2;
db.block_cache_size    = 32 * 1024 * 1024;      /* 32 MB */
db.max_open_sstables   = 128;                   /* ~320 fds */
db.max_memory_usage    = 768 * 1024 * 1024;     /* explicit cap for a small box */
db.log_to_file         = 1;
db.log_level           = TDB_LOG_WARN;

tidesdb_column_family_config_t cf = tidesdb_default_column_family_config();
cf.write_buffer_size          = 16 * 1024 * 1024;   /* 16 MB */
cf.l0_queue_stall_threshold   = 8;
cf.compression_algorithm      = TDB_COMPRESS_LZ4;
cf.sync_mode                  = TDB_SYNC_INTERVAL;
```

### Mid

```c
tidesdb_raise_open_file_limit(8192);            /* before open */

tidesdb_config_t db = tidesdb_default_config();
db.db_path             = "./data";
db.num_flush_threads   = 4;
db.num_compaction_threads = 4;
db.block_cache_size    = 2ull * 1024 * 1024 * 1024;     /* 2 GB */
db.max_open_sstables   = 1024;                          /* ~2112 fds */
db.max_memory_usage    = 0;                             /* 50 percent of RAM */
db.log_to_file         = 1;
db.log_level           = TDB_LOG_WARN;

tidesdb_column_family_config_t cf = tidesdb_default_column_family_config();
cf.write_buffer_size          = 64 * 1024 * 1024;   /* 64 MB (default) */
cf.l0_queue_stall_threshold   = 10;
cf.compression_algorithm      = TDB_COMPRESS_LZ4;
cf.sync_mode                  = TDB_SYNC_INTERVAL;  /* TDB_SYNC_FULL for strict durability */
```

### Large

```c
tidesdb_raise_open_file_limit(65536);                                      /* before open */

tidesdb_config_t db = tidesdb_default_config();
db.db_path             = "./data";
db.num_flush_threads   = 12;
db.num_compaction_threads = 12;
db.block_cache_size    = 32ull * 1024 * 1024 * 1024;                       /* 32 GB */
db.max_open_sstables   = 8192;                                             /* ~16448 fds */
db.max_memory_usage    = 128ull * 1024 * 1024 * 1024;                      /* explicit on a 256 GB box */
db.log_to_file         = 1;
db.log_level           = TDB_LOG_INFO;

tidesdb_column_family_config_t cf = tidesdb_default_column_family_config();
cf.write_buffer_size          = 128 * 1024 * 1024;   
cf.l0_queue_stall_threshold   = 16;
cf.level_size_ratio           = 10;                                        /* 12 to 15 for very large datasets */
cf.l1_file_count_trigger      = 6;
cf.compression_algorithm      = TDB_COMPRESS_LZ4;
cf.sync_mode                  = TDB_SYNC_INTERVAL;
```

---

## Workload overlays

Apply these on top of a tier.

For write-heavy ingest, use a larger `write_buffer_size` for better batching and a
higher `l0_queue_stall_threshold` to absorb bursts at the cost of memory, add
flush threads, and choose `TDB_SYNC_INTERVAL`, or `TDB_SYNC_NONE` for a
rebuildable cache. Keep `level_size_ratio` at 10 to bound write amplification, and
raise it only if reads can absorb the extra level depth.

For read-heavy point lookups, lower `bloom_fpr` to 0.005 or 0.002 to cut false
positives, give the block cache more room, and consider `use_btree = 1` for
O(log n) klog lookups instead of block scans. Keep `index_sample_ratio` at 1 so
block index lookups are definitive and can short-circuit negative reads.

For range scans and iteration, `use_btree = 1` helps seek-then-scan, block indexes
must stay enabled, and a larger block cache keeps hot blocks resident. Raise
`block_index_prefix_len` if your keys share long common prefixes.

For delete-heavy workloads, arm the tombstone density trigger so delete-dominated
column families are compacted before range scans degrade.

```c
cf.tombstone_density_trigger     = 0.30;   /* compact when an sstable is >30% tombstones */
cf.tombstone_density_min_entries = 1024;   /* ignore tiny sstables */
```

Use `tidesdb_txn_single_delete` for keys put at most once between deletes, which
lets a put and its delete cancel at the first merge regardless of level, and
`tidesdb_compact_range` to reclaim a known range immediately.

For large values, raise `klog_value_threshold` so more of them move to the value
log and keep the klog scannable, and lower it if values are small and hot so they
stay inline. Raise `multipart_part_size` in object store mode for very large
SSTables.

For many column families that map to one logical entity, such as a table plus N
secondary index column families, enable unified memtable mode so a transaction
touching K column families does one WAL write instead of K.

```c
db.unified_memtable                    = 1;
db.unified_memtable_write_buffer_size  = 0;   /* 0 => 64 MB (TDB_DEFAULT_WRITE_BUFFER_SIZE) */
db.unified_memtable_sync_mode          = TDB_SYNC_INTERVAL;
```

Unified mode requires the default `memcmp` comparator for every column family,
since the shared skip list has a single sort order, and it shares one immutable
queue, so the per-CF stall auto-scaling does not apply. This is the right default
once you exceed a handful of column families per transaction.

### Unified memtable sizing and the L0 and L1 split

Unified mode changes what `write_buffer_size` and the L0 stall mean, and the two
buffer knobs drive different things. This is the subtle part.

The `unified_memtable_write_buffer_size` sizes the one shared memtable. All column
families write into it, and it rotates as a whole the moment its total size
reaches that value. The threshold is fixed, with no adaptive idle headroom, unlike
per-CF mode, which rotates at up to 1.5x its buffer. A value of 0 means 64 MB, the
`TDB_DEFAULT_WRITE_BUFFER_SIZE` constant, not any column family's
`write_buffer_size`.

Each column family's own `write_buffer_size` no longer sizes a memtable in unified
mode, and the per-CF active and immutable memtables stay empty. That value still
matters, but only as level geometry. It is the capacity floor for that column
family's levels, since DCA never sizes a level below it, so it governs the on-disk
level shape rather than the in-memory footprint.

L0 is shared while L1 and everything below it stays per-CF, and this asymmetry is
the heart of the model. There is exactly one L0 flush queue,
`unified_mt.immutables`. The L0 stall, the hard cap of `stall + 6`, and the
graduated L0 delays all measure that single shared queue. Backpressure is still
evaluated once per column family in a commit, comparing the shared queue depth
against each participating column family's `l0_queue_stall_threshold`, so the
smallest configured threshold among the column families in a transaction is the
one that actually stalls it. Set `l0_queue_stall_threshold` consistently across
column families in unified mode, or expect the minimum to win.

L1 stays per column family. Flush demux writes each column family's slice of the
rotated memtable to that column family's own level 1, so every column family keeps
its own L1 file count, its own `l1_file_count_trigger`, and its own compaction. L1
never hard-stalls writes in either mode and only applies graduated delays, and
compaction stays one round per column family.

Memory in unified mode is database-wide rather than per column family. Because the
queue and the active memtable are shared, the worst-case write memory is bounded
once for the whole database, regardless of column family count.

```
unified_write_mem  ~=  l0_queue_stall_threshold * unified_memtable_write_buffer_size
                     + 2 * unified_memtable_write_buffer_size   (shared active ceiling, 2x)
```

With the defaults of a 64 MB unified buffer and a stall of 10, that is about
`(10 + 2) * 64 MB = ~768 MB` total, no matter how many column families you run.
That fixed, count-independent ceiling is the main reason to choose unified mode
for many-CF workloads. In per-CF mode the bound is instead per column family, and
the engine auto-scales each one's stall down to protect the budget. So in unified
mode you tune memory with the unified buffer and a single `l0_queue_stall_threshold`,
not with per-CF `write_buffer_size`.

For object store and cloud-native deployments, set `object_store` and an
`tidesdb_objstore_config_t`, and unified memtable mode is enabled automatically.
Give `local_cache_max_bytes` enough room for the hot working set, keep
`replicate_wal = 1`, and set `wal_sync_on_commit = 1` for an RPO of zero, or rely
on the 1 MB `wal_sync_threshold_bytes` for a bounded loss window. The
`max_concurrent_uploads` count defaults to 4 and `max_concurrent_downloads` to 8,
and both are worth raising on large nodes. Two per-CF knobs trade remote I/O
against read amplification. The `object_lazy_compaction` flag, off by default,
doubles the L1 file-count compaction trigger when an object store is attached,
which cuts compaction frequency and upload churn at the cost of more files to
read. The `object_prefetch_compaction` flag, on by default, downloads all evicted
merge inputs in parallel before a compaction instead of one at a time.

---

## Durability

| Mode | Behavior | Use when |
|------|----------|----------|
| `TDB_SYNC_NONE` | WAL written, not fsynced per commit, synced at flush | rebuildable cache, max throughput |
| `TDB_SYNC_INTERVAL` | background fsync every `sync_interval_us` (default 128 ms) | general purpose, good throughput with a bounded loss window |
| `TDB_SYNC_FULL` | fsync coalesced across concurrent committers | strict durability; unified-mode group commit keeps it fast |

In full-sync unified mode the WAL fsync is coalesced into one fsync per batch of
concurrent committers, so `TDB_SYNC_FULL` stays performant at high concurrency. In
per-CF mode every commit fragments across separate WALs, so `TDB_SYNC_FULL` costs
one fsync per commit.

---

## Lower-impact knobs

These rarely need changing from their defaults, but they are real and worth
knowing.

The `skip_list_max_level` (default 12) and `skip_list_probability` (default 0.25)
are the standard probabilistic skip-list parameters. Keep `skip_list_max_level`
below 64, because the memtable write path uses a stack-allocated update array only
when the level is under 64, and a higher value forces a per-operation heap
allocation. A level of 12 already indexes far more entries than a memtable holds.
The unified memtable has its own `unified_memtable_skip_list_max_level` and
`unified_memtable_skip_list_probability`, and a 0 for either resolves to the same
12 and 0.25 defaults.

The `min_disk_space` field (default 100 MB) is a safety floor. Flush and
compaction are skipped while free space on the column family directory is below
it, so the data stays in memory and writes keep flowing until memory pressure
intervenes. Raise it if you want a larger headroom before the engine stops writing
new files.

The `log_truncation_at` field (default 24 MB) matters only with `log_to_file = 1`.
The `LOG` file is truncated once it grows past this size, which bounds log disk
use.

The `num_compaction_threads` count sets both the number of compaction worker
threads and the shared sub-compaction helper budget, so one round of a single
column family can fan out across the whole pool. Size it to your storage
parallelism, one to two on HDD and up to the core count on NVMe, not to your
column family count.

---

## Things to watch

Set `max_memory_usage` explicitly in containers, because the auto-resolve uses
host RAM rather than your cgroup limit.

A high `max_open_sstables` is silently clamped if the file-descriptor limit cannot
honor it, so call `tidesdb_raise_open_file_limit()` before `tidesdb_open()`.

The `max_concurrent_flushes` count follows `num_flush_threads`, so set the thread
count and do not fight the one-to-one pin.

The comparator is permanent. It cannot change after a column family is created
without corrupting key order, and unified mode forces `memcmp`.

Many column families in per-CF mode self-throttle, since the effective L0 stall
shrinks with column family count. Grow `max_memory_usage` or switch to unified
mode.

The block cache shares the 30 percent memory clamp with the B+tree node cache, so
a large `block_cache_size` may be clamped down relative to `max_memory_usage`.

The `min_disk_space` floor gates flush and compaction, not just writes. If free
space drops below it, new SSTables stop being written and memory climbs until
pressure relief intervenes, so monitor disk free space against this floor.

A `skip_list_max_level` of 64 or more costs a heap allocation on every memtable
write, so stay below 64. The default 12 is fine.

---
title: "Configuring TideSQL in MariaDB"
description: "An article on configuring TideSQL, the TidesDB storage engine in MariaDB."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/georg_wietschorke-gray-seal-3918766_1920.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/georg_wietschorke-gray-seal-3918766_1920.jpg
---

<div class="article-image">

![Configuring TideSQL in MariaDB](/georg_wietschorke-gray-seal-3918766_1920.jpg)

</div>

*by <a target="_blank" href="https://alexpadula.com">Alex Gaetano Padula</a>*
 
*published on June 16th, 2026*

It's come to my attention that many of you would like a run down on configurations when running TideSQL, the MariaDB storage engine, built on TidesDB.  Thus in this article I'll be going over some important configurations for your `.cnf` files when running the engine in MariaDB.

Firstly, know that the TideSQL plugin differs from that of MyRocks and the InnoDB storage engine, but I will compare the TidesDB config to an InnoDB configuration for those used to Inno.

One thing to keep in mind up front, every TideSQL variable is prefixed with `tidesdb_`, and the ones named `tidesdb_default_*` are not global engine settings.  They are the *defaults for new tables*, copied onto each column family at `CREATE TABLE` time, so changing them only affects tables created afterwards.  The plain global knobs (`tidesdb_block_cache_size`, `tidesdb_flush_threads`, the sync modes, and so on) are read-only at startup and must live in your `.cnf`.

Below are some configurations that are set quite frequently.  This particular block is tuned for raw throughput, so think benchmarks and bulk loads, not durability.

```ini
# how much memory should the engine use? 0 means default of 75% of the system's memory at start up.
# value is in bytes, so for 10G or 100G you write that out. if you go over system limits TidesDB will
# still throttle you for safety when nearing a potential OOM.
tidesdb_max_memory_usage = 0


# similar to innodb_buffer_pool_size, configure to your desired cache size. this is
# the TidesDB block clock cache which holds blocks once they're read from disk.
tidesdb_block_cache_size                       = 64M

# the unified memtable option is on by default and gives you a single shared WAL and skip list
# instead of N. with it off, every column family/table gets its own WAL files and skip list,
# which depending on the workload can sometimes be faster.
tidesdb_unified_memtable                       = ON

# this is the size the memtable grows to before it seals into l0 (the unsorted wal + immutable
# skip list) and gets flushed out as a sorted l1 sstable. be careful, setting the unified write
# buffer too large makes your l0 wal segments, and then the l1 sstables, large too.
tidesdb_unified_memtable_write_buffer_size     = 64M

# durability mode.
# NONE for benchmarks (no per-commit sync), FULL or INTERVAL for production.
# which setting owns commit durability depends on whether unified mode is on:
#   unified ON  (default) -> every commit syncs the one shared WAL per the unified sync mode.
#                            tidesdb_default_sync_mode then only syncs sstable (klog/vlog) files.
#   unified OFF -> each table has its own WAL and tidesdb_default_sync_mode governs both that WAL
#                  and its sstable files; the unified setting does nothing.
# so it really is one or the other for the WAL, the unified knob here matters because unified is on.
tidesdb_unified_memtable_sync_mode             = NONE
tidesdb_default_sync_mode                      = NONE

# flush threads dequeue work across the whole instance and flush l0 wal files into sorted
# l1 sstable files per column family. at 0 it auto sizes the shared pool to min(cpu count, 4).
tidesdb_flush_threads                          = 0

# like flush threads, compaction workers take compaction work. this one can't be 0 (min 1).
tidesdb_compaction_threads                     = 6

# how many open sstables to keep in the LRU cache. 0 means unlimited, bounded only by the
# process open-file limit. note each sstable uses two descriptors.
tidesdb_max_open_sstables                      = 0

# sstable compression, NONE, LZ4, SNAPPY, ZSTD, LZ4_FAST
tidesdb_default_compression                    = NONE

# TidesDB log level, logs to a file in the data dir by default. DEBUG, INFO, WARN, ERROR, FATAL, NONE
tidesdb_log_level                              = NONE

# on by default, OFF is optimistic MVCC mode
tidesdb_pessimistic_locking                    = OFF

# how many unsorted wal files with immutable skip lists can sit in the queue before
# we stall writers and require flushes to drain
tidesdb_default_l0_queue_stall_threshold       = 8

# how many sstable files at l1 before triggering compaction (per cf)
tidesdb_default_l1_file_count_trigger          = 4

# skip the uniqueness check on the primary key and unique indexes during INSERT.
# only safe when you guarantee no duplicates (bulk loads with monotonic PKs). this is a
# session default, so ON here disables the check for every session, fine for a load, risky as a
# general production default.
tidesdb_skip_unique_check                      = ON

tidesdb_default_isolation_level                = READ_COMMITTED

# bloom filter false positive rate in parts per 10000, so 10 = 0.1% (default is 100 = 1%)
tidesdb_default_bloom_fpr                       = 10

# how many leading key bytes each sstable's block index keys on. longer is a more selective
# index probe at the cost of a larger index. default 16, range 1-256.
tidesdb_default_block_index_prefix_len          = 32

# values at or above this many bytes go to the vlog instead of inline in the klog
tidesdb_default_klog_value_threshold            = 1024

# trigger compaction when any sstable's tombstone ratio (tombstones / entries) exceeds this,
# in parts per 10000, so 5000 = 0.50. 0 (the default) disables it. the check scans every level,
# and a dense sstable above the bottom level gets its key range steered down so the tombstones
# can actually drop.
tidesdb_default_tombstone_density_trigger       = 5000
# only consider sstables with at least this many entries, smaller ones are ignored. note 0 here
# does not mean "no minimum", it falls back to the default of 1024.
tidesdb_default_tombstone_density_min_entries   = 2048
```

---

Now let's get into the defaults, and the table options behind them.  Almost everything named `tidesdb_default_*` is exactly that, a default.  Each one seeds a `CREATE TABLE` option of the same name minus the `default_` part, it only applies to tables you create after setting it, and naming the option on the table wins over the global.  So your `.cnf` sets the house style and individual tables opt out where they need to.

These two give that one table the same 128M memtable, one globally, one inline:

```sql
SET GLOBAL tidesdb_default_write_buffer_size = 134217728;   -- 128M for new tables
CREATE TABLE a (id BIGINT PRIMARY KEY) ENGINE=TidesDB;

CREATE TABLE b (id BIGINT PRIMARY KEY) ENGINE=TidesDB WRITE_BUFFER_SIZE=134217728;
```

And a fuller one, house defaults from the `.cnf` with a couple of per-table overrides:

```sql
CREATE TABLE events (
  id      BIGINT PRIMARY KEY,
  payload BLOB
) ENGINE=TidesDB
  WRITE_BUFFER_SIZE=134217728     -- 128M memtable just for this table
  LEVEL_SIZE_RATIO=12
  COMPRESSION='ZSTD'
  SYNC_MODE='FULL'
  BLOOM_FPR=10;                   -- 0.1%
```

`SHOW CREATE TABLE` echoes back whatever you set.  The pairing is mechanical, `tidesdb_default_write_buffer_size` ↔ `WRITE_BUFFER_SIZE`, `tidesdb_default_compression` ↔ `COMPRESSION`, and so on for every one of them.

A few of these shape the LSM tree itself and have no real InnoDB counterpart, a B+tree just isn't built this way.

| Table option (`tidesdb_default_…`) | Default | What it shapes | InnoDB |
|---|---|---|---|
| `WRITE_BUFFER_SIZE` | 64M | per-table memtable size, and the base unit its disk levels are sized from | — |
| `LEVEL_SIZE_RATIO` | 10 | LSM fanout, each level holds ~this many times the level above | none, a B+tree isn't leveled |
| `DIVIDING_LEVEL_OFFSET` | 1 | the Spooky compaction algorithm's write-amplification vs open-file trade off (advanced, leave it alone) | none |
| `INDEX_SAMPLE_RATIO` | 1 | block-index density, 1 indexes every block, higher indexes every Nth for a smaller, coarser index | none |
| `USE_BTREE` | 0 (LSM) | 1 writes the klog as an on-disk btree instead of carrying a block index | none |

Two of those are worth a quick note.

`WRITE_BUFFER_SIZE` does double duty.  It's the per-table memtable flush threshold, but it's also the base unit the on-disk levels are sized from, level 1 is about one buffer, the next is `LEVEL_SIZE_RATIO` times that, and so on down.  One wrinkle, with the unified memtable on the shared memtable actually flushes at `tidesdb_unified_memtable_write_buffer_size`, but each table's *level capacities* still come from its own `WRITE_BUFFER_SIZE`.  So it's not dead under unified mode, it's still shaping your levels even when it isn't the thing triggering the flush.

`USE_BTREE` is a read-path trade.  Off (the default) every sstable carries a sampled block index.  Turn it on and the klog is written as an on-disk btree and block indexes are skipped entirely, you pay extra disk space for the btree but carry less in memory, since btree nodes page through a cache instead of you holding a block index resident.  Worth a look for big read-heavy tables where memory is tighter than disk.

One knob in the throughput block isn't a table default at all.  `tidesdb_single_delete_primary` is a session flag, not a `default_`.  It switches the primary key's deletes to cheaper single-delete tombstones that compaction can cancel against exactly one prior insert.  That's only correct if the session never updates, REPLACEs, or `INSERT ... ON DUPLICATE KEY`s a row it later deletes, so it's an insert-then-delete-only optimization, think queue tables, and it's off by default for good reason.  InnoDB has nothing like it, it deletes rows in place.

And a few options live only on the table with no global default behind them, `TTL` (row expiry in seconds, 0 = never), `ENCRYPTED` (data-at-rest, off by default) and `ENCRYPTION_KEY_ID`.

---

So how does this map to InnoDB, you may ask? If you've tuned InnoDB before, most of the muscle memory carries over, the knobs just have different names and the engine underneath is an LSM tree instead of a B+tree.  Here's how the ones you actually reach for line up, with each engine's out-of-the-box default.

| What you're tuning | TideSQL | default | InnoDB | default |
|---|---|---|---|---|
| Read cache | `tidesdb_block_cache_size` | 256M | `innodb_buffer_pool_size` | 128M |
| Global memory ceiling | `tidesdb_max_memory_usage` | 0 (75% RAM) | *(no single equivalent)* | — |
| Commit durability | `tidesdb_unified_memtable_sync_mode` | FULL | `innodb_flush_log_at_trx_commit` | 1 |
| Flush timer (INVERVAL mode only) | `tidesdb_default_sync_interval_us` | 128000 (µs) | `innodb_flush_log_at_timeout` | 1 (s) |
| Write buffer sizing | `tidesdb_unified_memtable_write_buffer_size` | 256M | `innodb_log_file_size` | 96M |
| Background write workers | `tidesdb_flush_threads` + `tidesdb_compaction_threads` | 4 / 4 | `innodb_write_io_threads` + `innodb_io_capacity` | 4 / 200 |
| Row-lock wait | `tidesdb_lock_wait_timeout_ms` | 50000 (ms) | `innodb_lock_wait_timeout` | 50 (s) |
| Locking model | `tidesdb_pessimistic_locking` | ON | *(always pessimistic)* | — |
| Default isolation | `tidesdb_default_isolation_level` | REPEATABLE_READ | `transaction_isolation` | REPEATABLE-READ |
| Compression | `tidesdb_default_compression` | LZ4 | `innodb_compression_algorithm` | zlib *(page compression off by default)* |
| Conflict logging | `tidesdb_print_all_conflicts` | OFF | `innodb_print_all_deadlocks` | OFF |

A couple of these mappings are loose enough to be worth spelling out.

The cache is not the working set.  `innodb_buffer_pool_size` is where InnoDB reads *and writes*, dirty pages live in the buffer pool until a checkpoint flushes them.  `tidesdb_block_cache_size` only caches read blocks pulled off sstables, writes land in the memtable, which is a separate budget.  So on TideSQL you think about the block cache and the memtable write buffer as two distinct things, not one big pool.

Durability is one knob, not a checkpoint dance.  With the unified memtable on (the default), commit durability is entirely `tidesdb_unified_memtable_sync_mode`.  `FULL` fsyncs the shared WAL on every commit, this is your `innodb_flush_log_at_trx_commit = 1`.  `INTERVAL` syncs the foreground WAL on a timer (`tidesdb_unified_memtable_sync_interval`, 128 ms by default), which lands close to `innodb_flush_log_at_trx_commit = 2`.  `NONE` leans on the OS page cache and gives no per-commit guarantee, in the neighborhood of `innodb_flush_log_at_trx_commit = 0`.

Background work is explicit.  InnoDB hides flushing behind `innodb_io_capacity` and a pool of IO threads, and you tune the *rate*.  TideSQL hands you the worker counts directly, `tidesdb_flush_threads` to drain l0 into l1, and `tidesdb_compaction_threads` to merge levels.  On a write-heavy box you give compaction more threads; flush at `0` auto sizes to `min(cpu, 4)`.

Watch the lock-wait units in pessimistic mode.  Both default to a 50 second wait, but `tidesdb_lock_wait_timeout_ms` is in milliseconds and `innodb_lock_wait_timeout` is in seconds.  `50000` and `50` are the same wait.

---

Let's look at a durable production setup.  The throughput block above turns durability off, so it's not what you'd run in production.  Here's a durable starting point for an OLTP box.  Scale the cache and write buffer to your hardware and hot working set.

```ini
# global memory ceiling. 0 = 75% of system RAM with OOM throttling.
# pin it (in bytes) if InnoDB or other engines share the box.
tidesdb_max_memory_usage                   = 0

# read block cache, size to your hot set. closest thing to innodb_buffer_pool_size.
tidesdb_block_cache_size                   = 8G

# one shared WAL + skip list across every table, on by default.
tidesdb_unified_memtable                   = ON

# commit durability. FULL fsyncs the unified WAL on every commit,
# this is your innodb_flush_log_at_trx_commit = 1. use INTERVAL for the ~timer-flush trade off.
tidesdb_unified_memtable_sync_mode         = FULL

# how big the memtable grows before it seals into l0 and flushes out as a sorted l1 sstable.
tidesdb_unified_memtable_write_buffer_size = 128M

# background workers. flush drains l0 wal -> l1 sstables, compaction merges levels.
# flush at 0 auto sizes to min(cpu, 4). give compaction room on write-heavy boxes.
tidesdb_flush_threads                      = 0
tidesdb_compaction_threads                 = 6

# pessimistic row locks for SELECT ... FOR UPDATE / UPDATE / DELETE, like InnoDB.
# OFF switches to optimistic MVCC where write-write conflicts surface at commit.
tidesdb_pessimistic_locking                = ON

# row-lock wait before a lock-wait-timeout. NOTE this is in milliseconds.
tidesdb_lock_wait_timeout_ms               = 50000

# compress sstables. TidesDB compresses by default (LZ4), InnoDB does not.
tidesdb_default_compression                = LZ4

# keep bloom filters for point lookups. 100 = 1% false positive rate.
tidesdb_default_bloom_filter               = ON
tidesdb_default_bloom_fpr                  = 100

# quieter logs in production, written to a file in the data dir.
tidesdb_log_level                          = WARN

# log conflicts to the error log, the innodb_print_all_deadlocks analog.
tidesdb_print_all_conflicts                = ON
```

And for comparison, the InnoDB `my.cnf` you'd write for the same box.  The values are tuned-up suggestions; the defaults are in the comments so you can see how far off the shipped defaults are.

```ini
innodb_buffer_pool_size        = 8G      # default 128M
innodb_flush_log_at_trx_commit = 1       # fsync redo on every commit (default)
innodb_log_file_size           = 2G      # default is only 96M
innodb_io_capacity             = 2000    # background flush rate, default 200
innodb_io_capacity_max         = 4000
innodb_read_io_threads         = 8       # default 4
innodb_write_io_threads        = 8       # default 4
innodb_lock_wait_timeout       = 50      # seconds (default 50)
innodb_print_all_deadlocks     = ON      # default OFF
```

If you want durability without paying the full fsync-per-commit cost, swap `tidesdb_unified_memtable_sync_mode = FULL` for `INTERVAL`, the same move as dropping `innodb_flush_log_at_trx_commit` from `1` to `2`.

---

What doesn't carry over from InnoDB? Well, a few InnoDB knobs simply have no TideSQL equivalent, and that's by design rather than an omission.

There's no doublewrite buffer.  `innodb_doublewrite` exists because InnoDB updates pages in place and a torn 16K page write would corrupt data.  TideSQL's sstables are immutable and written once, sequentially, so there's no in-place page to tear and nothing to double-write.

There's no change buffer or adaptive hash index to reason about, the LSM write path is already a sequential append into the memtable, and reads go through bloom filters and block indexes rather than a buffer-pool hash.

And the redo log analogy only goes so far.  `innodb_log_file_size` is a fixed-size redo ring you size against your checkpoint interval; the TideSQL WAL is segmented and tied to the memtable write buffer, so `tidesdb_unified_memtable_write_buffer_size` is really sizing how much un-flushed write data you carry, not a separate log file you pre-allocate.

---

That should give you enough to get a sensible `.cnf` going, whether you're chasing throughput for a benchmark or running something durable.  Start from the production block, size the cache and write buffer to your box, and pick a sync mode that matches how much you're willing to lose on a power cut, the same decision you already make with `innodb_flush_log_at_trx_commit`.

For the exhaustive list of every variable and what it maps to internally, see the <a href="/reference/tidesql/">TideSQL reference</a>.

---

*Thanks for reading!*

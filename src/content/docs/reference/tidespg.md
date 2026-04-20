---
title: TidesDB Table Access Method Reference
description: Official reference for TidesDB's table access method for PostgreSQL.
---

<div class="no-print">

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/tidespg.md).

<hr/>

</div>

TidesPG is a PostgreSQL Table Access Method extension that plugs TidesDB in as an alternative to PostgreSQL's built-in heap storage.

`CREATE TABLE ... USING tidesdb` gives you a PG table whose rows live in TidesDB column families. Writes go through TidesDB's WAL, reads go through its block cache and (where configured) its bloom filters, and compaction/flushing is handled by TidesDB's background threads.

## Why?

Postgres's heap is excellent, but it's one storage model. It's page-based with full tuple versions and a vacuum-driven reclamation story. LSM trees occupy a different point in the tradeoff space with cheap writes, tunable read amplification, good compression, and background compaction that reclaims space without a separate vacuum pass. TidesPG lets you pick that model per-table without giving up anything else about Postgres (SQL, transactions at the statement level, indexes, constraints, the planner).

## When to pick tidesdb (vs. heap)

LSM storage earns its keep in specific, well-understood situations. Use `USING tidesdb` for a table when:

- Your writes are durable and frequent. With `synchronous_commit = on` + `tidesdb.sync_mode = full`, LSM's sequential WAL beats heap's per-page fsync by a wide margin, many multiples. The gap grows with the commit rate because every fsync you save compounds.
- On-disk space matters. LZ4 compression (default) typically buys 40–60% smaller footprint than heap on the same rows. ZSTD buys more at higher CPU cost. Smaller footprint also means more working set fits in the OS page cache.
- You store large values. tidesdb streams anything over `tidesdb.klog_value_threshold` (default 512 B) into its own value-log, so there's no TOAST table, no TOAST pointer indirection, no decompression round-trip on read. JSONB blobs, bytea, long text columns.
- The workload is insert-dominant and mostly ordered. Append-heavy tables (event streams, audit logs, time-series, change-data-capture) sort well under a 48-bit monotonic row counter; sequential scans stay tight and compaction rarely moves the same data twice.
- You want to avoid VACUUM tuning. Dead rows are reclaimed by LSM compaction running on background threads. No table bloat tracking, no `vacuum_*` autovacuum knobs for that table, no anti-wraparound scares.
- You have many tables with mixed hotness. Each tidesdb table is a separate column family with its own bloom/index/compression config; cold tables get squeezed hard, hot tables get more memtable and larger block cache. The built-in `tidesdb_cf_stats('my_table')` lets you see per-table amplification.

Stick with heap when:

- Read-dominant workload on an in-RAM working set. Heap's `ctid -> page -> slot` is hard to beat when everything's already in shared_buffers. Our bench shows heap leading on pure SELECT TPS (~80% headroom over tidesdb on point lookups).
- UPDATE-heavy workloads. Heap's HOT update path keeps the same TID; tidesdb does delete+insert and relies on compaction to reclaim. Write amp is higher on tidesdb for in-place-feeling updates.
- High concurrent write fan-in. TidesDB takes a process-exclusive advisory lock on its directory, so every extra PG backend that touches a tidesdb table serializes. Fine for modest concurrency; pathological at hundreds of parallel writers. (Fixable with a background-worker fronting design, on the roadmap.)
- You rely on `PREPARE TRANSACTION`. tidespg refuses it with `ERRCODE_FEATURE_NOT_SUPPORTED`; use heap tables for any relation that will participate in an external-coordinator 2PC.
- Tables small enough that heap overhead is invisible. Sub-megabyte lookup tables don't benefit from compression and pay the LSM's skiplist + block-cache indirection cost.

Per-table granularity is the real sell. You can mix `USING tidesdb` and the default heap in the same database, same transaction, same query. Put the 2 TB event log on tidesdb, keep the 50 kB reference tables on heap.

## Requirements

- PostgreSQL *18 or newer* (uses the PG 18 TableAM surface `ReadStream`-flavored `scan_analyze_next_block`, the new five-arg `scan_bitmap_next_tuple`, `pg_noreturn`, and `rs_base.st.rs_tbmiterator`)
- TidesDB installed so that `<tidesdb/tidesdb.h>` is on the include path and `-ltidesdb` resolves
- A C11-capable compiler and GNU make (standard PGXS requirements)

## Build & install

```bash
make
sudo make install
```

If `pg_config` isn't on your `PATH`, point PGXS at it explicitly:

```bash
make PG_CONFIG=/usr/local/pgsql/bin/pg_config
sudo make install PG_CONFIG=/usr/local/pgsql/bin/pg_config
```

If TidesDB is installed somewhere non-standard:

```bash
make TIDESDB_CFLAGS="-I/opt/tidesdb/include" \
     TIDESDB_LIBS="-L/opt/tidesdb/lib -ltidesdb -Wl,-rpath,/opt/tidesdb/lib"
```

Then in `psql`:

```sql
CREATE EXTENSION tidesdb;
```

## Usage

```sql
CREATE TABLE events (
    id    bigint,
    ts    timestamptz,
    payload jsonb
) USING tidesdb;

INSERT INTO events VALUES (1, now(), '{"hello": "world"}');

-- Indexes work normally; they live in PG's heap storage and point at
-- tidesdb TIDs.
CREATE INDEX ON events (id);
CREATE INDEX ON events (ts);

SELECT * FROM events WHERE id = 1;
```

To make `tidesdb` the default for new tables in a session:

```sql
SET default_table_access_method = 'tidesdb';
```

## Architecture

### Storage layout

- One TidesDB handle per PG backend, rooted at `$PGDATA/tidesdb/`, opened lazily on the first TidesPG operation in a backend and closed via `on_proc_exit`. TidesDB's advisory lock on the db directory means only one backend can hold it at a time; `TidesPG_GetDB` retries on `TDB_ERR_LOCKED` with a short backoff to ride through PG's fork-per-backend handoff.
- One column family per PG relation, named `r_<relfilenumber>`. Using `relfilenumber` (not `relname`) means renames are free and rewrites (TRUNCATE, CLUSTER, some ALTERs) swap storage cleanly by picking up a fresh relfilenumber.
- Unified memtable mode is on by default (`tidesdb.unified_memtable`), so all CFs share one WAL and one in-memory skiplist, which fits multi-table Postgres transactions and lowers WAL write amp.

### Key encoding

Each live tuple gets a unique 48-bit row counter, packed into an `ItemPointer` as:

- `BlockNumber`   = counter ÷ 1024
- `OffsetNumber`  = (counter mod 1024) + 1

(Offset 0 is reserved in PG, and 1024 stays well under `MaxOffsetNumber` so bitmap scans and sample scans, which work in (block, offset) space, still have meaningful block locality.)

The TidesDB key is the 6-byte big-endian encoding of that counter. Big-endian means TidesDB's default `memcmp` comparator orders keys numerically, so forward iteration matches insertion order.

The counter is persisted per-CF under a reserved 1-byte key (`0x00`). Because 1 byte ≠ 6 bytes, scans reject the counter key by length check without a special case. See [Row-counter allocation](#row-counter-allocation) below for the reservation scheme.

### Tuple layout

Each row is stored as a raw `MinimalTuple`, which is the same wire form PG uses for slot materialization, starting with the 4-byte `t_len`. There is no tidespg-specific header, no magic sentinel, and no `xmin/xmax`, because visibility is handled by TidesDB's own MVCC so we don't need our own.

TidesDB values can be arbitrarily large, so we don't need PG's TOAST machinery, and the extension's `relation_needs_toast_table` callback returns `false`. Large JSONB / text columns go through TidesDB's own value-log (`vlog`), which stores any value over `klog_value_threshold` (default 512 B) out of line.

### MVCC and transactions

MVCC is delegated to TidesDB. Each backend holds at most one live TidesDB transaction, opened lazily on the first TidesPG operation in a PG transaction and committed / rolled back via `RegisterXactCallback`. PG subtransactions map to TidesDB savepoints named by `SubTransactionId`; if a subxact starts before we've opened the per-xact txn, the savepoints are replayed on the first lazy open so later `ABORT SUB` callbacks still find the right rollback point.

Visibility, write-write conflict detection, and tombstone reclamation all ride on TidesDB's `commit_seq` / `snapshot_seq` machinery. Deletes call `tidesdb_txn_delete` (not payload rewrites with an `xmax` marker), so dead rows are cleaned up by TidesDB's own compaction; no separate VACUUM pass is required for space reclamation.

Isolation mapping (PG -> TidesDB, configurable):

| PG level            | TidesDB level                              |
|---------------------|--------------------------------------------|
| `READ UNCOMMITTED`  | `tidesdb.rc_isolation` (default `read_committed`) |
| `READ COMMITTED`    | `tidesdb.rc_isolation` (default `read_committed`) |
| `REPEATABLE READ`   | `TDB_ISOLATION_REPEATABLE_READ`            |
| `SERIALIZABLE`      | `TDB_ISOLATION_SERIALIZABLE`               |

No TidesDB level matches PG's per-statement snapshot semantics exactly. `read_committed` is the closest in spirit (both allow non-repeatable reads) but TidesDB refreshes snapshots per-read rather than per-statement, so a statement that reads the same row twice may see different versions. Flip `tidesdb.rc_isolation` to `snapshot` to buy xact-level consistency plus write-write conflict detection, at the cost of stricter-than-PG-RC behavior.

### Scan path and index fetches

`scan_getnextslot` drives a `tidesdb_iter_t` over the backend's per-xact TidesDB transaction and does not open its own. Entries are filtered only by key length (the reserved 1-byte counter key is skipped), and visibility is handled below the iterator. Direction changes re-seek rather than trusting `prev` from an ambiguous position.

`index_fetch_tuple` is a point `tidesdb_txn_get` on the same per-xact transaction, so index lookups see the backend's own uncommitted writes and benefit from TidesDB's snapshot consistency without per-fetch txn overhead. When the caller passes a `SnapshotDirty` (ON CONFLICT, exclusion-constraint checks), we explicitly populate `xmin / xmax / speculativeToken = 0`, because PG uses those fields to decide whether to wait on another transaction, and leaving them uninitialized causes `check_exclusion_or_unique_constraint` to livelock on stack garbage.

### Parallel sequential scans

Parallel scans share a `ParallelBlockTableScanDescData` whose `phs_nallocated` atomic we repurpose as a chunk claim. At first call, each participant computes a chunk size from the CF's high-water counter and claims a range via `pg_atomic_fetch_add_u64`. The iterator is seeked to the chunk start via `tidesdb_iter_seek`; iteration stops once the current key leaves the chunk, at which point the participant claims the next chunk. This distributes work dynamically (no straggler starvation) without needing any up-front partitioning.

### Bitmap heap scans and TABLESAMPLE

Bitmap scans consume `rs_base.st.rs_tbmiterator`, and each `TBMIterateResult` gives us a synthetic page (our 1024-counter block). Lossy pages expand to all 1024 offsets, while exact pages use `tbm_extract_page_tuple`. Either way we fall through to point `tidesdb_txn_get` per offset, yielding only the offsets that resolve to live rows.

`TABLESAMPLE` uses the same (block, offset) vocabulary. `scan_sample_next_block` asks the TSM routine for a synthetic block in `[0, high_water / 1024)`; `scan_sample_next_tuple` loops the TSM routine's offset picker against the block, skipping `NOT_FOUND` gaps.

### ANALYZE

`scan_analyze_next_block` reports the whole CF as a single virtual block (returns true once, then false). `scan_analyze_next_tuple` drains the iterator into the caller for reservoir sampling. Under unified-memtable mode per-CF stats can read zero until a flush, so `relation_size` / `estimate_rel_size` fall back to the reserved-counter high-water mark times a small per-row constant, which gives ANALYZE's block sampler a non-zero block count to iterate.

### Row-counter allocation

Counters are handed out from a per-backend in-memory reservation. When a chunk is exhausted (default `tidesdb.counter_chunk_size = 1024`), we round-trip to TidesDB under `TDB_ISOLATION_SNAPSHOT` to claim the next chunk, and concurrent reservers serialize via write-write conflict on the counter key. The persisted counter records the next unclaimed counter. Crashed / exited backends "leak" the unused tail of their chunk, but the 48-bit counter space absorbs that effortlessly.

## Testing

```bash
make installcheck
```

This runs the regression tests under `test/sql/` and compares against `test/expected/`. You need a running PostgreSQL cluster whose `pg_config` matches the one you installed against.

## Configuration

All TidesDB tuning knobs are surfaced as `tidesdb.*` GUCs. `SIGHUP` settings reload on `pg_reload_conf()` and are picked up by new backends on their next `tidesdb_open`; `USERSET` settings take effect for any CF created after the change. Existing CFs carry their own config persisted on disk; changing a CF-level GUC does not retroactively reconfigure them.

Database-level (`PGC_SIGHUP`, applied per-backend at `tidesdb_open()`):

| GUC | Default | Notes |
|-----|---------|-------|
| `tidesdb.block_cache_size_mb` | 64 | Shared block cache size |
| `tidesdb.num_flush_threads` | 2 | |
| `tidesdb.num_compaction_threads` | 2 | |
| `tidesdb.max_open_sstables` | 256 | |
| `tidesdb.max_memory_usage_mb` | 0 | 0 = auto |
| `tidesdb.unified_memtable` | `on` | Shared memtable+WAL across CFs |
| `tidesdb.log_level` | `warn` | `debug`/`info`/`warn`/`error`/`fatal`/`none` |
| `tidesdb.log_to_file` | `on` | `$PGDATA/tidesdb/LOG` |
| `tidesdb.log_truncate_mb` | 24 | |

Column-family-level (applied to newly-created CFs, `PGC_USERSET`):

| GUC | Default | Notes |
|-----|---------|-------|
| `tidesdb.use_btree` | `off` | B+tree klog; faster point lookups (index fetches) |
| `tidesdb.compression` | `lz4` | `none`/`snappy`/`lz4`/`lz4_fast`/`zstd` |
| `tidesdb.enable_bloom_filter` | `on` | |
| `tidesdb.bloom_fpr` | 0.01 | |
| `tidesdb.enable_block_indexes` | `on` | |
| `tidesdb.index_sample_ratio` | 1 | |
| `tidesdb.block_index_prefix_len` | 16 | |
| `tidesdb.klog_value_threshold` | 512 | Values > this go to vlog (no TOAST) |
| `tidesdb.write_buffer_size_mb` | 128 | Drives both per-CF and unified memtable size |
| `tidesdb.level_size_ratio` | 10 | |
| `tidesdb.min_levels` | 5 | |
| `tidesdb.sync_mode` | `none` | `none`/`full`/`interval` |
| `tidesdb.sync_interval_us` | 128000 | for `sync_mode = interval` |

Process-local:

| GUC | Default | Notes |
|-----|---------|-------|
| `tidesdb.counter_chunk_size` | 1024 | Row counters reserved per TidesDB round-trip |
| `tidesdb.rc_isolation` | `read_committed` | TidesDB isolation used for PG RC. Closest match by name, though TidesDB RC refreshes per-read vs PG's per-statement. Flip to `snapshot` for xact-level consistency and write-write conflict detection. |
| `tidesdb.open_max_retries` | 20 | Retries on `TDB_ERR_LOCKED` during `tidesdb_open` |
| `tidesdb.open_retry_delay_ms` | 50 | Delay between those retries |

### Memory allocator

tidespg does not plug Postgres's `palloc` / `pfree` into TidesDB's allocator hook (`tidesdb_init`), because TidesDB has flush / compaction / sync background threads and Postgres memory contexts are single-threaded. TidesDB runs on its own libc `malloc` by default. Users who want a faster / contention-friendlier allocator can rebuild TidesDB with `-DTIDESDB_WITH_MIMALLOC=ON`, `-DTIDESDB_WITH_TCMALLOC=ON`, or `-DTIDESDB_WITH_JEMALLOC=ON`, which are all thread-safe drop-in replacements. tidespg's own allocations stay on `palloc` (per-xact memory context), so memory lifetime of everything the extension owns is bounded.

## Inspecting TidesDB state

Three SQL-callable functions expose TidesDB's internal counters, useful for tuning.

```sql
SELECT * FROM tidesdb_cf_stats('events');   -- per-CF: levels, keys, cache, btree
SELECT * FROM tidesdb_db_stats();           -- cluster-wide memory / queues / CFs
SELECT * FROM tidesdb_cache_stats();        -- block cache hits / misses / hit_rate
```


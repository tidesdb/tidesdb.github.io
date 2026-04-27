---
title: TidesDB Engine for MariaDB Reference
description: Official TidesDB pluggable storage engine for MariaDB (TideSQL) reference
---

<div class="no-print">

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/tidesql.md).

<hr/>

</div>

TideSQL is a pluggable storage engine for <a href="https://mariadb.org/">MariaDB</a>, built on top of TidesDB.

The engine supports ACID transactions through multi-version concurrency control (MVCC), letting readers proceed without blocking writers. It handles primary keys, secondary indexes, auto-increment columns, virtual and stored generated columns, savepoints, TTL-based expiration, data-at-rest encryption, online DDL, partitioning, and online backups. All of these features are accessible through standard SQL, so switching from InnoDB to TidesDB for a particular table requires nothing more than changing the `ENGINE` clause.

The TidesDB data files live in a sibling directory next to the MariaDB data directory, named `tidesdb_data`. The engine manages its own file layout entirely. In object store mode, the engine uses MariaDB's schema discovery mechanism to replicate table definitions across nodes (see "Schema Discovery" under Object Store Mode).


## Getting Started

The engine is loaded as a shared plugin. Once the server is built with the TidesDB plugin compiled, it can be loaded at startup:

```
[mysqld]
plugin-load-add=ha_tidesdb.so
```

Or loaded dynamically:

```sql
INSTALL SONAME 'ha_tidesdb';
```

Once loaded, the engine appears in `SHOW ENGINES`:

```
MariaDB [(none)]> SHOW ENGINES
...
*************************** 1. row ***************************
      Engine: TIDESDB
     Support: YES
     Comment: LSM-tree engine with ACID transactions, MVCC concurrency, secondary/spatial/full-text/vector indexes, and encryption
Transactions: YES
          XA: NO
  Savepoints: YES
...
```

After that, creating a table with TidesDB is straightforward:

```sql
CREATE TABLE events (
  id    INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  ts    DATETIME NOT NULL,
  kind  VARCHAR(50),
  data  TEXT
) ENGINE=TIDESDB;
```

This creates a column family inside TidesDB for the table's data. If you later drop the table, the column family and all of its SSTables are removed as well.


## Quick Install

The repository includes `install.sh`, a cross-platform script that clones MariaDB, builds it with the TidesDB plugin, and sets up a ready-to-run server. It handles dependencies, submodules, and configuration automatically.

```bash
git clone https://github.com/tidesdb/tidesql.git
cd tidesql
./install.sh --mariadb-prefix ~/mariadb-tidesdb
```

The script accepts several options:

| Option | Description |
|--------|-------------|
| `--mariadb-prefix <path>` | MariaDB installation directory (default: `/usr/local/mariadb-tidesdb`) |
| `--tidesdb-prefix <path>` | TidesDB library installation directory (default: `/usr/local`) |
| `--mariadb-version <tag>` | MariaDB version/branch to build (i.e: `mariadb-11.4.5`) |
| `--tidesdb-version <tag>` | TidesDB library version/tag (i.e: `v8.9.2`) |
| `--build-dir <path>` | Build directory (default: `./build`) |
| `--jobs <n>` | Parallel build jobs (default: number of CPU cores) |
| `--skip-deps` | Skip system dependency installation |
| `--skip-tidesdb` | Skip building the TidesDB library (use if already installed) |
| `--skip-engines <list>` | Comma-separated storage engines to exclude from the build |
| `--list-engines` | List available storage engines and exit |
| `--pgo` | Enable profile-guided optimization (longer build, faster binaries) |
| `--s3` | Build with S3 object store connector (requires libcurl + OpenSSL) |
| `--allocator <name>` | Link libtidesdb against `system` (default), `jemalloc`, `mimalloc`, or `tcmalloc` |

For object store mode with S3:

```bash
./install.sh --mariadb-prefix ~/mariadb-tidesdb --s3
```

For a non-default allocator:

```bash
./install.sh --allocator jemalloc
```

The `--allocator` flag only affects `libtidesdb.so`'s internal allocations (memtable, klog/vlog buffers, compaction scratch, txn ops). `mariadbd`'s allocator is unchanged. For a process-wide swap, also `LD_PRELOAD` the allocator at server startup:

```bash
LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2 \
  ~/mariadb-tidesdb/bin/mariadbd-safe --defaults-file=~/mariadb-tidesdb/my.cnf &
```

Note that `--rebuild-plugin` does not rebuild `libtidesdb.so`, so changing `--allocator` requires a full install run (omit `--rebuild-plugin`) to take effect. Verify the linkage with:

```bash
ldd /usr/local/lib/libtidesdb.so | grep -E 'jemalloc|mimalloc|tcmalloc'
```

After installation, start the server:

```bash
~/mariadb-tidesdb/bin/mariadbd --defaults-file=~/mariadb-tidesdb/my.cnf &
```

Connect via socket (faster for local access):

```bash
~/mariadb-tidesdb/bin/mariadb -S /tmp/mariadb.sock
```

Or via TCP:

```bash
~/mariadb-tidesdb/bin/mariadb -h 127.0.0.1 -P 3306
```

The installer creates a `my.cnf` that loads the TidesDB plugin automatically. For user-owned prefixes, the server runs as your current user; for system prefixes, it runs as `mysql`.


## Tables and Column Families

Every TidesDB table corresponds to one main column family that holds the row data. Each secondary index gets its own separate column family. The naming convention is rather deterministic, a table `test.events` maps to the column family `test__events`, and a secondary index named `idx_ts` on that table maps to `test__events__idx_idx_ts`.

This separation is meaningful. Because each column family has its own LSM-tree, a secondary index has its own memtable, its own set of SSTables files, and its own compaction and flush schedules. 

When a table is renamed with `RENAME TABLE` or `ALTER TABLE ... RENAME`, the engine renames all associated column families, both the main data CF and every secondary index CF.


## Primary Keys and Row Storage

If you define a `PRIMARY KEY` on a table, TidesDB uses it as the physical ordering key for the data column family. The key bytes are stored in a memcmp-comparable format, integers are encoded big-endian with their sign bit flipped so that negative values sort before positive ones, and strings use their collation's sort key encoding. This means range scans on the primary key are efficient, because physically adjacent keys in the LSM-tree correspond to logically adjacent rows.

If you create a table without an explicit primary key, the engine generates a hidden 8-byte row ID for each row, encoded in big-endian. These hidden IDs are monotonically increasing, assigned from an atomic counter that is recovered on restart by seeking to the last key in the column family.

Inside the column family, every row's key is prefixed with a single namespace byte (`0x01` for data rows, `0x00` for metadata). The value is stored in a packed binary format with a 5-byte header (see "How It Stores Data Internally" for details), followed by the null bitmap and each non-null field serialized using MariaDB's `Field::pack()` method. Fixed-size fields like `INT` and `BIGINT` are stored at their native pack length. `CHAR` fields have trailing spaces stripped. `VARCHAR` fields store only the actual data length rather than padding to the declared maximum. `BLOB` and `TEXT` fields are inlined with a length prefix followed by the data bytes. This packed format is more compact than the raw record buffer and reduces I/O and storage costs, especially for tables with variable-length columns.

Composite primary keys are fully supported. Each key part is encoded in comparable format and concatenated, so a composite key like `(dept_id, emp_id)` sorts first by department, then by employee within each department. The optimizer can use prefix lookups on the leading columns of a composite PK (e.g., `WHERE dept_id = 3` on a `PRIMARY KEY (dept_id, emp_id)`) via an iterator-based prefix scan.

```sql
-- With explicit PK (comparable key ordering)
CREATE TABLE users (
  id   INT NOT NULL PRIMARY KEY,
  name VARCHAR(100)
) ENGINE=TIDESDB;

-- Composite PK (multi-column ordering)
CREATE TABLE emp_projects (
  emp_id  INT NOT NULL,
  proj_id INT NOT NULL,
  hours   INT NOT NULL,
  PRIMARY KEY (emp_id, proj_id)
) ENGINE=TIDESDB;

-- Without PK (hidden auto-generated row ID)
CREATE TABLE logs (
  ts      DATETIME,
  message TEXT
) ENGINE=TIDESDB;
```


## Secondary Indexes

Secondary indexes are stored in their own column families, separate from the main data. Each index entry consists of a key that concatenates the comparable-format index column bytes with the comparable-format primary key bytes. The value is empty (a single zero byte). This design means that every secondary index entry is self-contained, given an index key, the engine can extract the primary key from its tail and perform a point lookup into the main data CF to fetch the full row.

When you insert, update, or delete a row, the engine transactionally maintains all secondary indexes within the same transaction. For updates, the engine builds the old and new comparable index key for each secondary index and compares them with `memcmp`; if the indexed columns and PK bytes are identical, that index is skipped entirely, avoiding a redundant delete-then-reinsert round-trip into the library. This is a significant optimization for updates that only touch non-indexed columns. For deletes, the corresponding index entries are removed.

Duplicate key violations on primary keys and unique indexes are properly detected. Inserting a row with a primary key that already exists returns the standard `ER_DUP_ENTRY` error. The same applies to unique secondary indexes. `REPLACE INTO` and `INSERT ... ON DUPLICATE KEY UPDATE` work correctly, `write_row()` returns `HA_ERR_FOUND_DUPP_KEY` with the conflicting row's PK in `dup_ref`, so the server can perform the delete-then-reinsert (REPLACE) or switch to `update_row()` (IODKU), properly cleaning up old secondary index entries in the process.

```sql
CREATE TABLE products (
  id       INT NOT NULL PRIMARY KEY,
  category INT,
  name     VARCHAR(100),
  KEY idx_category (category)
) ENGINE=TIDESDB;

INSERT INTO products VALUES (1, 10, 'Widget'), (2, 20, 'Gadget'), (3, 10, 'Sprocket');

-- Uses the secondary index for the lookup
SELECT * FROM products WHERE category = 10;
```

The optimizer is aware of these indexes. The engine reports cost estimates based on the LSM-tree's read amplification factor, which it obtains from TidesDB's internal statistics. Point lookups through a secondary index cost roughly one seek into the index CF plus one point-get into the data CF.

### Index Condition Pushdown (ICP)

The engine supports Index Condition Pushdown for secondary index scans. When the optimizer pushes a WHERE condition down to the storage engine, the engine evaluates it on the index key columns before performing the expensive primary key point-lookup into the data column family. Index entries that fail the condition are skipped without touching the data CF at all. This is the same pattern used by InnoDB - the engine decodes the index key columns into the record buffer and calls MariaDB's `handler_index_cond_check()` evaluator. ICP is supported for indexes on integer types (`TINYINT`, `SMALLINT`, `MEDIUMINT`, `INT`, `BIGINT`), temporal types (`DATE`, `DATETIME`, `TIMESTAMP`, `YEAR`), and fixed-length `CHAR`/`BINARY` columns with binary or latin1 charset. For indexes on multi-byte charset string columns (e.g., `utf8mb4`), the engine falls through to the standard PK-lookup path.

### Multi-Range Read (MRR)

The engine implements a custom MRR path for point-lookup batches such as `WHERE col IN (v1, v2, ..., vN)` on a primary or full-key unique index. When every range the optimizer hands the engine is a full-key point equality (`UNIQUE_RANGE | EQ_RANGE`) and there are at least two ranges, the engine buffers them, converts each key into comparable bytes, and sorts by those bytes so the LSM sees a monotone stream of seeks - much friendlier to the block cache and the merge-heap than N scattered seeks in user-supplied order. Primary-key lookups bypass the iterator entirely via `fetch_row_by_pk`; secondary-index lookups reuse a single cached iterator and do one seek per entry. Ranges whose rows have been deleted concurrently are silently skipped.

The engine deliberately declines MRR in three cases, falling back to the base handler's default implementation:

- Single-range scans (`count < 2`) - MRR has no sorting win for one key, and the eq_ref path is where pessimistic row locking engages.
- Non-point ranges - true `BETWEEN`/`<`/`>` scans stay on `read_range_first`.
- Partitioned tables - `ha_partition` already dispatches MRR across children using its own DS-MRR logic.


## Auto-Increment

Auto-increment works in a similar way to InnoDB. The engine calls MariaDB's built-in `update_auto_increment()` mechanism during `write_row()`. Rather than calling `index_last()` on every INSERT (which would create and destroy a TidesDB merge-heap iterator each time), the engine maintains an in-memory atomic counter on the shared table descriptor. The counter is seeded once at table open time by seeking to the last key in the primary key column family, and is atomically incremented via a CAS loop on each INSERT - making auto-increment assignment O(1). When a user inserts an explicit value larger than the current counter, `write_row()` bumps the counter to match.

`TRUNCATE TABLE` and `ALTER TABLE ... AUTO_INCREMENT=N` both reset the counter via the engine's `reset_auto_increment` handler hook - the next generated ID equals `N` (or `1` after a bare `TRUNCATE`). This applies to both user-defined AUTO_INCREMENT columns and hidden-PK tables.

```sql
CREATE TABLE tickets (
  id   INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  desc VARCHAR(200)
) ENGINE=TIDESDB;

INSERT INTO tickets (desc) VALUES ('First ticket');
INSERT INTO tickets (desc) VALUES ('Second ticket');
INSERT INTO tickets (id, desc) VALUES (100, 'Explicit ID');
INSERT INTO tickets (desc) VALUES ('Continues from 100');

SELECT * FROM tickets ORDER BY id;
-- 1, 2, 100, 101
```


## Transactions and Concurrency

TidesDB uses MVCC internally. Each statement runs inside a TidesDB transaction. The engine maintains a per-connection transaction context through MariaDB's handlerton callback interface, following the same pattern as InnoDB. A transaction object is allocated lazily on the first data access and registered with MariaDB's transaction coordinator. After commit or rollback, the transaction object is kept alive and reused via `tidesdb_txn_reset()` on the next statement, which obtains a fresh MVCC snapshot while preserving internal buffers (ops array, arenas, read-set arrays). This avoids the malloc/free overhead of creating a new transaction on every autocommit statement. Autocommit single-statement DML uses `READ_COMMITTED` isolation since there is no concurrent modification within a single-statement transaction, eliminating unnecessary conflict tracking overhead. Multi-statement transactions (`BEGIN ... COMMIT`) use the session's isolation level for proper write-write conflict detection.

The engine respects the session's isolation level set via `SET TRANSACTION ISOLATION LEVEL`. The mapping from MariaDB isolation levels to TidesDB isolation levels is:

| MariaDB | TidesDB |
|---------|---------|
| `READ UNCOMMITTED` | `TDB_ISOLATION_READ_UNCOMMITTED` |
| `READ COMMITTED` | `TDB_ISOLATION_READ_COMMITTED` |
| `REPEATABLE READ` | `TDB_ISOLATION_SNAPSHOT` |
| `SERIALIZABLE` | `TDB_ISOLATION_SERIALIZABLE` |

MariaDB's `REPEATABLE READ` maps to TidesDB's `SNAPSHOT` isolation, which is the semantic equivalent of InnoDB's repeatable-read, consistent read snapshot with write-write conflict detection only, no read-set tracking. TidesDB's own `REPEATABLE_READ` level is stricter (tracks read-set, detects read-write conflicts at commit) and would cause excessive conflicts under normal OLTP concurrency. TidesDB's `SNAPSHOT` level (which has no SQL equivalent) can also be selected explicitly via the table option `ISOLATION_LEVEL='SNAPSHOT'`.

DDL operations (`ALTER TABLE`, `CREATE INDEX`, `DROP INDEX`, `TRUNCATE`, `OPTIMIZE`) and autocommit single-statement DML always use `READ_COMMITTED` regardless of the session setting, to avoid unnecessary conflict tracking overhead and unbounded read-set growth during large scans.

TidesDB supports SQL savepoints (`SAVEPOINT`, `ROLLBACK TO SAVEPOINT`, `RELEASE SAVEPOINT`) inside explicit multi-statement transactions. Savepoints are only meaningful inside `BEGIN ... COMMIT` blocks.

### Consistent Snapshots

The engine supports `START TRANSACTION WITH CONSISTENT SNAPSHOT`. This eagerly creates a TidesDB transaction and captures the snapshot sequence number immediately, rather than waiting until the first data access. The isolation level is enforced to be at least `SNAPSHOT`, regardless of the session setting, since lower levels like `READ_COMMITTED` would refresh the snapshot on each read, violating the consistent snapshot semantics. Rows committed by other connections after the snapshot are invisible to the transaction. This is useful for cross-engine consistency when TidesDB and InnoDB tables coexist in the same transaction:

```sql
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION WITH CONSISTENT SNAPSHOT;
-- snapshot is taken now, not at first SELECT
SELECT * FROM tidesdb_table;   -- sees data as of snapshot time
SELECT * FROM innodb_table;    -- InnoDB also snapshotted at the same time
COMMIT;
```

The engine sets `lock_count()` to zero, which tells MariaDB to bypass its own table-level locking layer entirely. By default, all concurrency control is handled by TidesDB's MVCC, which allows readers and writers to proceed without blocking each other. When `tidesdb_pessimistic_locking` is enabled, the engine adds plugin-level row locks on top of MVCC for write-intent statements (see Pessimistic Row Locking below).

Because TidesDB uses optimistic concurrency control, write-write conflicts are detected at commit time rather than during the DML operation. When `tidesdb_txn_commit()` encounters a conflict it returns `TDB_ERR_CONFLICT`. The engine maps this to `HA_ERR_LOCK_DEADLOCK`, which triggers MariaDB's built-in deadlock retry logic. For autocommit statements, MariaDB automatically retries the statement without application intervention. For multi-statement transactions (`BEGIN ... COMMIT`), the transaction is rolled back and the application receives ERROR 1213 (`ER_LOCK_DEADLOCK`), the same error InnoDB returns for deadlocks, and should retry the transaction. Conflicts are most likely under concurrent writes to the same rows at `REPEATABLE_READ` or higher isolation. Enabling `tidesdb_print_all_conflicts` logs every conflict event to the error log for diagnostics (see System Variables).

This is a fundamental architectural difference between the two engines. InnoDB uses pessimistic row-level locks that serialize access to hot rows - when two transactions want to update the same row, the second one waits until the first commits or rolls back. TidesDB uses optimistic MVCC - both transactions proceed concurrently without blocking each other, and the second one to commit fails with a conflict error. In other words, InnoDB makes concurrent writers wait; TidesDB makes them fail and retry. Neither approach is inherently better. Pessimistic locking guarantees forward progress but introduces lock waits and potential deadlocks. Optimistic MVCC eliminates all lock waits and deadlocks but requires applications to handle retries. Workloads with low contention (most rows are touched by at most one writer at a time) see virtually no conflicts and benefit from the absence of lock overhead. Workloads with high contention on a small number of hot rows (e.g., a single counter row updated by every transaction) will see higher conflict rates and depend on efficient retry logic.

### Pessimistic Row Locking

For workloads that depend on InnoDB-style row-level serialization, TidesDB provides an optional pessimistic locking mode that can be enabled at runtime:

```sql
SET GLOBAL tidesdb_pessimistic_locking = ON;
```

When enabled, the engine acquires row level locks on primary key values for every write intent statement such as `SELECT ... FOR UPDATE`, `UPDATE`, `DELETE`, and `INSERT`. Locks are held until the transaction commits or rolls back. A second transaction that attempts to access the same primary key value will block until the first transaction releases its lock, rather than proceeding optimistically and failing at commit time.

The lock manager uses a partitioned hash table with 65,536 partitions, each protected by its own mutex. Primary key bytes are hashed (XXH3) to a partition, and each partition maintains a chain of lock entries keyed by the full comparable PK bytes. This gives per-row granularity without a global bottleneck. Lock entries are created on demand and persist in the hash table for the lifetime of the server, so repeated access to the same key reuses the existing entry without allocation.

#### Which Statements Acquire Locks

All write-intent statements acquire a row lock during the primary key lookup phase (`index_read_map()`), before reading or modifying the row:

| Statement | Acquires Lock | When |
|-----------|--------------|------|
| `SELECT ... FOR UPDATE` | Yes | During the PK read |
| `UPDATE` | Yes | During the PK read that precedes the row modification |
| `DELETE` | Yes | During the PK read that precedes the row removal |
| `INSERT` | Yes | Before the PK uniqueness check and data write |
| `SELECT` (plain) | No | Read-only, no write intent |

Both explicit transactions (`BEGIN ... COMMIT`) and autocommit single-statement DML participate in locking. Autocommit statements block on locks held by other transactions, which prevents an autocommit `UPDATE` from silently bypassing a lock held by a `SELECT ... FOR UPDATE` in another session.

#### Locking Non-Existing Rows

Locks are keyed by primary key bytes, not by the existence of a row. A `SELECT ... FOR UPDATE` on a primary key value that does not exist (e.g., `WHERE id = 15` when no such row exists) still acquires a lock on that key. This blocks other transactions from inserting, updating, or deleting that key until the lock is released. This behavior supports the common "check-then-insert" pattern:

```sql
BEGIN;
SELECT * FROM t WHERE id = 42 FOR UPDATE;  -- empty set, but lock is held
-- no other transaction can INSERT id=42 while this lock is held
INSERT INTO t VALUES (42, 'reserved');
COMMIT;
```

#### Deadlock Detection

Before blocking on a held lock, the engine performs wait-for-graph cycle detection. It follows the chain of `waiting_on` pointers from the current lock's owner through any locks they are waiting on, up to a depth of 100 hops. If the chain leads back to the requesting transaction, a cycle exists and the engine returns `ER_LOCK_DEADLOCK` (ERROR 1213) immediately instead of blocking. The victim transaction can retry. This is the same error code and semantics that InnoDB uses for deadlocks.

The graph walk is performed without holding the current partition's mutex. The engine publishes its wait intent under the mutex, drops the mutex, walks the graph using atomic loads on the `owner_trx` and `waiting_on` fields (which are `std::atomic` precisely for this reason), then reacquires the mutex and rechecks state. This avoids serializing every locker on a partition behind a walk of up to 100 hops and lets other threads proceed while detection runs. Lock entries and transaction objects are never freed during normal operation, so pointer stability across the walk is guaranteed.

A waiter that receives `KILL QUERY` during its wait is woken promptly. The `kill_query` handlerton callback broadcasts on the owning lock's condition variable, the wait loop observes `thd_killed()` on its next iteration, and the statement returns `HA_ERR_LOCK_WAIT_TIMEOUT` instead of hanging until the holder commits.

```sql
-- Connection A:
BEGIN;
SELECT * FROM t WHERE id = 1 FOR UPDATE;  -- holds lock on id=1

-- Connection B:
BEGIN;
SELECT * FROM t WHERE id = 2 FOR UPDATE;  -- holds lock on id=2

-- Connection A:
SELECT * FROM t WHERE id = 2 FOR UPDATE;  -- blocks, waiting for B

-- Connection B:
SELECT * FROM t WHERE id = 1 FOR UPDATE;  -- deadlock detected, ERROR 1213
```

#### Lock Release

All locks held by a transaction are released atomically when the transaction commits or rolls back. There is no early lock release. Each lock entry's owner is cleared and any threads waiting on that lock are woken via a condition variable broadcast. If a connection is closed while holding locks, the engine releases them during connection cleanup.

#### When to Enable It

Pessimistic locking is off by default because most workloads perform better with optimistic MVCC. Enable it when the application depends on `SELECT ... FOR UPDATE` semantics for correctness, such as TPC-C style read-modify-write cycles where two transactions must not both read the same counter value before incrementing it. With pessimistic locking enabled, the second transaction blocks on the first rather than reading a stale value and failing at commit, which guarantees forward progress without application-level retry logic.

The per-table isolation level is configurable at table creation time and defaults to `REPEATABLE_READ`:

```sql
CREATE TABLE ledger (
  id  INT PRIMARY KEY,
  amt DECIMAL(10,2)
) ENGINE=TIDESDB ISOLATION_LEVEL='SERIALIZABLE';
```

The available isolation levels are `READ_UNCOMMITTED`, `READ_COMMITTED`, `REPEATABLE_READ`, `SNAPSHOT`, and `SERIALIZABLE`.

### Bulk DML Batching

Statements that touch many rows such as `LOAD DATA INFILE`, multi row `INSERT`, `INSERT ... SELECT`, and `UPDATE` or `DELETE` over a range keep the TidesDB transaction from growing unbounded by committing mid statement in fixed size batches. The engine hooks MariaDB's `start_bulk_insert`, `start_bulk_update`, and `start_bulk_delete` callbacks, counts the row operations (data write plus secondary index maintenance) against `TIDESDB_BULK_INSERT_BATCH_OPS` (500 ops), and at each threshold commits the current transaction and resets it with `READ_COMMITTED` for the next batch. This keeps statement memory bounded regardless of statement size. Autocommit semantics are preserved so a failure rolls back only the current batch, and the statement as a whole reports the first error encountered.

The mid commit logic is shared between INSERT, UPDATE, and DELETE via a single `maybe_bulk_commit` helper, so the batching threshold and the iterator plus dup cache invalidation policy are identical across the three paths.


## Single-Delete Optimization

DELETE on a TidesDB table writes a tombstone into every column family the row touches: the primary row CF plus one CF per secondary, full-text, or spatial index. Regular tombstones have to be carried forward through every compaction until they reach the largest active level, because any level below could still contain an older put of the same key that the tombstone is masking. Insert-then-delete workloads (event streams, log tables, TTL-style purges, the classic iibench benchmark) pile these tombstones at the low end of the key space where DELETE range scans start, and the scan CPU climbs linearly with the backlog until compaction catches up.

The TidesDB library's single-delete primitive (`tidesdb_txn_single_delete`) lets compaction drop a put and its matching tombstone together the first time both appear in the same merge input, regardless of level. The caller's contract is "at most one put between single-deletes on the same key (or between the start of the key's history and its first single-delete)". For reads, a single-delete behaves exactly like a regular tombstone.

The plugin splits this across two behaviours:

### Secondary-index single-delete (automatic)

Every secondary index entry -- `(col_values, pk)` for a regular index, `(term, pk)` for a FULLTEXT index, `(hilbert_value, pk)` for a SPATIAL index -- is written exactly once per row lifetime and deleted exactly once, across every path the plugin takes: `INSERT`, `UPDATE` (which delete-plus-put when the indexed columns change), `DELETE`, `REPLACE INTO`, `INSERT ... ON DUPLICATE KEY UPDATE`. The same `(composite, pk)` bytes never see a second put without an intervening delete, so the single-delete contract holds by construction of the index key layout.

The plugin therefore uses `tidesdb_txn_single_delete` for every secondary-index delete automatically. No configuration, no user flag, no workload assumption. This alone covers three of the four tombstones per deleted row on a table with three secondary indexes.

### Primary-CF single-delete (opt-in per session)

The primary row CF is different. `UPDATE t SET non_pk_col = ...` writes a fresh row at the same `data_key(pk)`, producing a put-over-put. `REPLACE INTO` on a table without secondary indexes takes a short-circuit path that overwrites the primary row silently for the same reason. Under either pattern, dropping a primary-CF put and its later single-delete together at compaction can re-expose an older put -- a silent correctness problem the engine cannot detect from the outside.

Primary-CF single-delete is therefore behind the session variable `tidesdb_single_delete_primary`, default OFF. Enabling it is the caller's explicit promise that:

- The session performs no `UPDATE` on non-PK columns of TidesDB tables.
- The session performs no `REPLACE INTO` or `INSERT ... ON DUPLICATE KEY UPDATE` that hits the line-5143 silent-overwrite path on a table without secondary indexes.
- New rows with a given PK are always preceded by a `DELETE` of that PK (append-only or insert-then-delete).

Enable it only when the workload is known to fit this shape. Typical safe cases:

```sql
-- classic insert-then-delete (event stream, TTL purge, iibench-shape)
SET SESSION tidesdb_single_delete_primary = 1;
INSERT INTO events (...) VALUES ...;   -- monotonic PK
DELETE FROM events WHERE ts < NOW() - INTERVAL 1 HOUR;
```

Leave it OFF for any session that may issue `UPDATE` on a non-PK column, `REPLACE INTO` on a no-secondary table, or `INSERT ... ON DUPLICATE KEY UPDATE` on a no-secondary table. Setting the variable ON in those scenarios can leak older row versions through reads after a compaction.

### When to expect a benefit

The larger the tombstone backlog at the scan head of your DELETE statements, the more the single-delete pair-cancellation helps. On iibench-shaped insert-then-delete workloads, with three secondary indexes, turning both automatic secondary-index SD and the primary-CF session variable together typically cuts the `max_d` sawtooth peak by 60 to 95 percent, depending on how long deletes have been running against the same key range without compaction catching up. On workloads with no DELETE, no benefit -- and no risk either, since the secondary-index path only changes behaviour on DELETE and UPDATE.


## Tombstone Density Trigger

Single-delete + pair-cancellation handles INSERT+DELETE workloads where the contract holds. For everything else (UPDATEs of indexed columns, REPLACE INTO on tables without secondary indexes, mixed read-write OLTP) tombstones still accumulate inside SSTables until a compaction at the largest level reclaims them. Reads over a deleted region pay for every tombstone the merge iterator has to skip, and a column family with infrequent natural compactions can accumulate enough tombstones to seriously degrade range-scan latency.

The library's tombstone-density trigger lets the engine notice and act on this state without waiting for capacity-based or file-count-based triggers. After every flush, the engine inspects level-1 SSTables and asks whether any single SSTable's tombstone count divided by entry count exceeds a configurable ratio while having at least a configurable minimum entry count. A single witness is enough to escalate compaction.

TideSQL exposes the trigger as two per-table options that map onto the underlying column family's `tombstone_density_trigger` and `tombstone_density_min_entries` settings:

```sql
CREATE TABLE events (
  id    BIGINT PRIMARY KEY,
  ts    DATETIME,
  body  TEXT,
  KEY (ts)
) ENGINE=TIDESDB
  TOMBSTONE_DENSITY_TRIGGER=5000      -- 50% (parts per 10000)
  TOMBSTONE_DENSITY_MIN_ENTRIES=2048;
```

`TOMBSTONE_DENSITY_TRIGGER` is in parts per 10000, where `5000` means 0.50. A value of `0` (the default) disables the check and preserves the previous structural-trigger-only behavior. `TOMBSTONE_DENSITY_MIN_ENTRIES` (default `1024`) is a floor that prevents a single-entry SSTable that happens to be a tombstone from noisily firing compaction.

Both options are also surfaced as session defaults so a deployment can switch the policy globally without touching every CREATE TABLE statement:

```sql
SET GLOBAL tidesdb_default_tombstone_density_trigger = 5000;
SET GLOBAL tidesdb_default_tombstone_density_min_entries = 2048;
```

`ALTER TABLE ... TOMBSTONE_DENSITY_TRIGGER=N` updates the live column family configuration via `tidesdb_cf_update_runtime_config`, so the new ratio takes effect on the next post-flush check without requiring a restart.

The aggregates surface in monitoring as four global status variables which read from a once-per-refresh CF-list walk so the cost is paid by the monitoring caller, not the write path:

| Variable | Meaning |
|----------|---------|
| `Tidesdb_total_tombstones` | Sum of tombstone entries across every CF |
| `Tidesdb_tombstone_ratio` | Database-wide tombstone count divided by entry count (0.0 to 1.0) |
| `Tidesdb_max_sst_tombstone_density` | Worst single-SSTable tombstone density observed |
| `Tidesdb_max_sst_tombstone_density_level` | LSM level (1-based) where the worst SSTable lives |

`SHOW ENGINE TIDESDB STATUS` includes a `--- Tombstones ---` block with the same four numbers in human-readable form.

## Auto Compact After Range Delete

Bulk operations such as sliding-window expiry, tenant eviction, and time-bucketed log rotation share a shape: a multi-row DELETE over a known primary-key range followed by a wait for compaction to physically reclaim the tombstoned space. The tombstone-density trigger handles this eventually, but a caller that already knows the range can skip the wait by asking the engine to compact that range synchronously at end-of-statement.

The session variable `tidesdb_compact_after_range_delete_min_rows` enables this:

```sql
SET SESSION tidesdb_compact_after_range_delete_min_rows = 100000;
DELETE FROM events WHERE ts < NOW() - INTERVAL 30 DAY;
-- end_bulk_delete fires tidesdb_compact_range over the touched PK range
```

The default is `0`, which disables the feature. A non-zero value is both an opt-in and a row-count threshold: only DELETE statements that touch at least that many rows trigger the synchronous compaction, so a one-row primary-key DELETE never pays the cost. The plugin tracks the comparable minimum and maximum primary-key bytes seen during the statement (no additional locking, no scan, just two `std::string` swaps per `delete_row` call) and on `end_bulk_delete` calls `tidesdb_compact_range` over the observed range on the table's primary CF.

Secondary index tombstones are not directly compacted by this feature, since their key shape is `(col_values, pk)` rather than just the PK and a PK range does not bound a secondary-index range. Secondary-index tombstones are reclaimed by the per-CF tombstone density trigger above instead, which is the natural division of labor.

The compaction is synchronous and runs on the caller's thread, so the trade-off is that the DELETE statement returns only after the compaction commits. The threshold should be set high enough that the synchronous compaction time is small relative to the DELETE work that triggered it. Typical values are 10000 to 1000000 depending on row size and disk throughput.


## Table Options

TidesDB exposes a rich set of per-table options that control the underlying column family's behavior. These are specified as table-level options in `CREATE TABLE` and are baked into the column family at creation time. They appear in `SHOW CREATE TABLE` output.

### Compression

The engine supports several compression algorithms for SSTables. The default is LZ4:

```sql
CREATE TABLE archive (
  id   INT PRIMARY KEY,
  data TEXT
) ENGINE=TIDESDB COMPRESSION='ZSTD';
```

Available choices are `NONE`, `SNAPPY`, `LZ4`, `ZSTD`, and `LZ4_FAST`. Different tables can use different compression algorithms. ZSTD tends to give the best compression ratio, while LZ4 and LZ4_FAST favor speed.

### Write Buffer Size

The write buffer is the in-memory skip list that absorbs writes before they are flushed to disk as an SSTable. A larger buffer means fewer, larger flushes, which can improve write throughput at the cost of higher memory usage:

```sql
CREATE TABLE high_write (
  id  INT PRIMARY KEY,
  val VARCHAR(200)
) ENGINE=TIDESDB WRITE_BUFFER_SIZE=16777216;  -- 16 MB
```

The default is 128 MB.

### Bloom Filters

By default, TidesDB creates bloom filters for each SSTable, which allow point lookups to skip SSTables that definitely do not contain the requested key. The false positive rate is configurable:

```sql
-- Disable bloom filters entirely
CREATE TABLE no_bloom (id INT PRIMARY KEY, v INT) ENGINE=TIDESDB BLOOM_FILTER=0;

-- Very low FPR (10 basis points = 0.01%)
CREATE TABLE precise (id INT PRIMARY KEY, v INT) ENGINE=TIDESDB BLOOM_FPR=10;
```

The `BLOOM_FPR` value is specified in parts per 10,000. The default of 100 gives a 1% false positive rate.

### Sync Mode

Controls how aggressively the engine flushes writes to durable storage:

```sql
-- No fsync (fastest, data at risk on crash)
CREATE TABLE fast_writes (id INT PRIMARY KEY, v INT) ENGINE=TIDESDB SYNC_MODE='NONE';

-- Periodic fsync every 500ms
CREATE TABLE balanced (id INT PRIMARY KEY, v INT)
  ENGINE=TIDESDB SYNC_MODE='INTERVAL' SYNC_INTERVAL_US=500000;

-- fsync every write (safest, slowest)
CREATE TABLE durable (id INT PRIMARY KEY, v INT) ENGINE=TIDESDB SYNC_MODE='FULL';
```

The default is `FULL`. For benchmarking or non-critical data, `NONE` can dramatically improve throughput.

### B+tree SSTable Format

TidesDB can optionally use a B+tree layout for the key log within SSTables instead of the default block-based format. The SSTable still consists of a key log and a value log; only the key log's internal organization changes. This is a per-table choice:

```sql
CREATE TABLE btree_table (id INT PRIMARY KEY, v INT) ENGINE=TIDESDB USE_BTREE=1;
```

When `ANALYZE TABLE` is run on a B+tree-formatted table, the output includes additional statistics about the tree structure (node counts, heights).

### Per-Index USE_BTREE

The B+tree format can also be set on individual secondary indexes, overriding the table-level default. This allows mixing LSM and B+tree indexes on the same table:

```sql
CREATE TABLE mixed (
  id INT NOT NULL PRIMARY KEY,
  a  INT,
  b  INT,
  KEY idx_a (a) USE_BTREE=1,    -- B+tree index
  KEY idx_b (b)                 -- inherits table default (LSM)
) ENGINE=TIDESDB;
```

`SHOW KEYS` reflects the per-index type `idx_a` shows `BTREE`, `idx_b` shows `LSM`. The per-index option is also honoured during `ALTER TABLE ... ADD INDEX ... USE_BTREE=1`.

### Block Indexes

When using the default block-based key log format (i.e., `USE_BTREE=0`), TidesDB builds block-level indexes inside each SSTable to speed up key lookups. Block indexes are enabled by default. You can disable them, or tune their sampling ratio and prefix length:

```sql
-- Disable block indexes entirely
CREATE TABLE no_block_idx (id INT PRIMARY KEY, v INT) ENGINE=TIDESDB BLOCK_INDEXES=0;

-- Tune block index parameters
CREATE TABLE custom_idx (
  id INT PRIMARY KEY,
  v  VARCHAR(200)
) ENGINE=TIDESDB
  BLOCK_INDEXES=1
  INDEX_SAMPLE_RATIO=4
  BLOCK_INDEX_PREFIX_LEN=32;
```

`BLOCK_INDEXES` enables or disables block-level indexes within the SSTable key log (default enabled). `INDEX_SAMPLE_RATIO` controls how frequently index entries are sampled from the key log blocks (default 1, meaning every block is indexed). Higher values reduce index size at the cost of more binary search steps during lookups. `BLOCK_INDEX_PREFIX_LEN` sets the byte length of the key prefix stored in each block index entry (default 16). A longer prefix improves point-lookup accuracy but increases index memory usage.

### Key Log Value Threshold

Each SSTable consists of a key log and a value log. Small values are stored inline in the key log alongside the key, while larger values are written to the separate value log with only a pointer kept in the key log. The `KLOG_VALUE_THRESHOLD` option controls the cutoff in bytes:

```sql
-- Store values up to 1 KB inline in the key log
CREATE TABLE inline_vals (
  id  INT PRIMARY KEY,
  val VARCHAR(200)
) ENGINE=TIDESDB KLOG_VALUE_THRESHOLD=1024;
```

The default is 512 bytes. Raising the threshold keeps more data inline, which benefits workloads with small rows by avoiding an extra indirection through the value log. Lowering it reduces key log size, which can improve cache efficiency for tables with large row values.

### Minimum Disk Space

`MIN_DISK_SPACE` sets the minimum free disk space (in bytes) that TidesDB requires before it will flush memtables or run compaction. If free space drops below this threshold, background operations are paused to prevent filling the disk:

```sql
CREATE TABLE guarded (
  id INT PRIMARY KEY,
  v  INT
) ENGINE=TIDESDB MIN_DISK_SPACE=1073741824;  -- 1 GB
```

The default is 100 MB.

### LSM-Tree Tuning

Several options let you tune the shape and behavior of the LSM-tree:

```sql
CREATE TABLE tuned (
  id INT PRIMARY KEY,
  v  VARCHAR(200)
) ENGINE=TIDESDB
  LEVEL_SIZE_RATIO=8
  MIN_LEVELS=3
  DIVIDING_LEVEL_OFFSET=1
  SKIP_LIST_MAX_LEVEL=16
  SKIP_LIST_PROBABILITY=25
  L1_FILE_COUNT_TRIGGER=4
  L0_QUEUE_STALL_THRESHOLD=20;
```

`LEVEL_SIZE_RATIO` controls how much larger each level is compared to the previous one (default 10). `MIN_LEVELS` sets the minimum depth of the LSM-tree (default 5). `DIVIDING_LEVEL_OFFSET` sets the offset used to compute the dividing level, which serves as the primary compaction target (default 2). The dividing level is calculated as `num_levels - 1 - DIVIDING_LEVEL_OFFSET`. TidesDB does not use traditional selectable compaction policies (like Leveled or Tiered); instead, it employs three complementary merge strategies - full preemptive merge, dividing merge, and partitioned merge - that are automatically selected based on the current state of the LSM-tree relative to the dividing level. The skip list parameters control the in-memory memtable structure. `L1_FILE_COUNT_TRIGGER` determines how many SSTables can accumulate at Level 1 before compaction merges them into deeper levels. `L0_QUEUE_STALL_THRESHOLD` sets how many immutable memtables can be queued for flush before the engine stalls new writes to allow flushes to catch up (default 20). Note that the flush threshold is adaptive, under idle conditions the active memtable can grow to 150% of `WRITE_BUFFER_SIZE` before flushing, dropping to 100% under pressure. Worst-case memtable memory per column family is approximately `(WRITE_BUFFER_SIZE × 1.5) + (WRITE_BUFFER_SIZE × min(L0_QUEUE_STALL_THRESHOLD, 16))`, with a hard cap of 16 immutable memtables regardless of the stall threshold.

### Object Store Compaction Tuning

When using S3 object store mode, two per-table options control compaction behavior for remote storage:

```sql
-- Reduce compaction frequency for write-heavy tables in object store mode
CREATE TABLE remote_logs (
  id  BIGINT PRIMARY KEY,
  msg TEXT
) ENGINE=TIDESDB OBJECT_LAZY_COMPACTION=1 OBJECT_PREFETCH_COMPACTION=1;
```

`OBJECT_LAZY_COMPACTION` (default 0) doubles the L1 file count compaction trigger when enabled, reducing the frequency of compaction and thus remote I/O at the cost of higher read amplification. `OBJECT_PREFETCH_COMPACTION` (default 1) downloads all input SSTables in parallel before the compaction merge begins, using bounded threads. When disabled, input SSTables are downloaded on demand during merge source creation one at a time. These options are persisted to the column family config and have corresponding session-level defaults `tidesdb_default_object_lazy_compaction` and `tidesdb_default_object_prefetch_compaction`. In non-object-store deployments, these options have no effect.

### Tombstone Density

Two per-table options arm the post-flush tombstone-density compaction trigger described under [Tombstone Density Trigger](#tombstone-density-trigger):

```sql
CREATE TABLE events (
  id    BIGINT PRIMARY KEY,
  ts    DATETIME,
  body  TEXT,
  KEY (ts)
) ENGINE=TIDESDB
  TOMBSTONE_DENSITY_TRIGGER=5000      -- 50%, parts per 10000
  TOMBSTONE_DENSITY_MIN_ENTRIES=2048;
```

`TOMBSTONE_DENSITY_TRIGGER` is in parts per 10000, where `5000` means 0.50. Default `0` disables the check. `TOMBSTONE_DENSITY_MIN_ENTRIES` (default `1024`) is a floor on the SSTable entry count before the density check considers it. Both options are session-defaultable via `tidesdb_default_tombstone_density_trigger` and `tidesdb_default_tombstone_density_min_entries`. ALTER TABLE updates the runtime CF config so changes take effect on the next post-flush check.

### Combining Multiple Options

Options can be freely combined:

```sql
CREATE TABLE optimized (
  id  INT PRIMARY KEY,
  val VARCHAR(100)
) ENGINE=TIDESDB
  COMPRESSION='ZSTD'
  WRITE_BUFFER_SIZE=8388608
  BLOOM_FILTER=1
  BLOOM_FPR=50
  SYNC_MODE='FULL'
  KLOG_VALUE_THRESHOLD=1024
  L0_QUEUE_STALL_THRESHOLD=6
  ISOLATION_LEVEL='REPEATABLE_READ';
```


## TTL (Time-To-Live)

TidesDB supports automatic expiration of rows, at both the table level and the per-row level. Expired rows are silently filtered out during reads and eventually reclaimed during compaction.

### Table-Level TTL

Every row inserted into the table expires after the specified number of seconds:

```sql
CREATE TABLE sessions (
  id    INT PRIMARY KEY,
  token VARCHAR(100)
) ENGINE=TIDESDB TTL=3600;  -- 1 hour

INSERT INTO sessions VALUES (1, 'abc123');
-- After 3600 seconds, this row will no longer be returned by queries
```

### Per-Row TTL

A column can be designated as the TTL source using the `TTL` field option. The value in that column specifies the row's lifetime in seconds from the time of insertion:

```sql
CREATE TABLE cache (
  id      INT PRIMARY KEY,
  val     VARCHAR(100),
  ttl_sec INT `TTL`=1
) ENGINE=TIDESDB;

INSERT INTO cache VALUES (1, 'short-lived', 5);       -- expires in 5 seconds
INSERT INTO cache VALUES (2, 'long-lived', 86400);    -- expires in 1 day
INSERT INTO cache VALUES (3, 'permanent', 0);         -- 0 means no expiration
```

When a per-row TTL column is present and has a non-zero value, it takes precedence over the table-level TTL. If the per-row value is zero, the table-level default applies. If neither is set, the row never expires.

When a row is updated, its TTL is recomputed from the new column value, effectively refreshing its expiration.

### Session-Level TTL

A per-session TTL can be set with the `tidesdb_ttl` session variable. This applies a TTL to all inserts and updates on any TidesDB table for the duration of the session, even tables that were not created with a TTL option:

```sql
SET SESSION tidesdb_ttl = 300;                          -- 5 minutes
INSERT INTO events (id, data) VALUES (1, 'temporary');  -- expires in 300s
SET SESSION tidesdb_ttl = 0;                            -- back to table default
```

The `SET STATEMENT` syntax can scope the TTL to a single statement:

```sql
SET STATEMENT tidesdb_ttl = 60 FOR INSERT INTO events (id, data) VALUES (2, 'one-minute');
```

The priority order is per-row TTL column > session `tidesdb_ttl` > table-level `TTL` option > no expiration.


## Data-at-Rest Encryption

TidesDB can encrypt row data before writing it to the column family. Encryption uses MariaDB's built-in key management infrastructure, so it works with any configured key management plugin (e.g., `file_key_management`).

```sql
CREATE TABLE secrets (
  id  INT NOT NULL PRIMARY KEY,
  val VARCHAR(100)
) ENGINE=TIDESDB `ENCRYPTED`=YES;
```

Each row is encrypted individually. The format is a 16-byte random IV followed by the ciphertext. On read, the engine decrypts transparently. You can specify which encryption key ID to use:

```sql
CREATE TABLE classified (
  id   INT NOT NULL PRIMARY KEY,
  data TEXT
) ENGINE=TIDESDB `ENCRYPTED`=YES `ENCRYPTION_KEY_ID`=2;
```

Encryption works with all other features, including secondary indexes, BLOB columns, and TTL. The secondary index keys themselves are not encrypted (they need to remain comparable for seeking), but the row data pointed to by those keys is encrypted in the data column family.


## Full-Text Search

TidesDB supports FULLTEXT indexes for natural language and boolean mode full-text search, with BM25 relevance ranking. Each FULLTEXT index is stored as a dedicated column family containing an inverted index, where each key-value pair maps a (term, document) pair to its term frequency and document length.

```sql
CREATE TABLE articles (
  id    INT NOT NULL PRIMARY KEY,
  title VARCHAR(200),
  body  TEXT,
  FULLTEXT ft_content (title, body)
) ENGINE=TIDESDB;

INSERT INTO articles VALUES (1, 'MySQL Tutorial', 'DBMS stands for DataBase Management System');
INSERT INTO articles VALUES (2, 'How To Use MySQL', 'After you went through a tutorial you can start');
INSERT INTO articles VALUES (3, 'Optimizing MySQL', 'In this tutorial we show optimization techniques');
```

### Natural Language Mode

The default search mode. The engine tokenizes the query, scans the inverted index for each term, computes BM25 relevance scores, and returns results sorted by score:

```sql
SELECT id, title, MATCH(title, body) AGAINST('tutorial') AS score
FROM articles WHERE MATCH(title, body) AGAINST('tutorial')
ORDER BY score DESC;
```

Multi-term queries accumulate BM25 scores across all query terms. Documents matching more terms and with higher term frequencies rank higher, normalized by document length.

### Boolean Mode

Boolean mode supports required (`+`), excluded (`-`), prefix wildcard (`*`), and exact phrase (`"..."`) operators:

```sql
-- Documents must contain 'mysql' AND 'tutorial'
SELECT * FROM articles
WHERE MATCH(title, body) AGAINST('+mysql +tutorial' IN BOOLEAN MODE);

-- Documents must contain 'mysql' but NOT 'tutorial'
SELECT * FROM articles
WHERE MATCH(title, body) AGAINST('+mysql -tutorial' IN BOOLEAN MODE);

-- Prefix wildcard: matches 'optimization', 'optimizing', etc.
SELECT * FROM articles
WHERE MATCH(title, body) AGAINST('optim*' IN BOOLEAN MODE);

-- Exact phrase: words must appear consecutively in this order
SELECT * FROM articles
WHERE MATCH(title, body) AGAINST('"database management system"' IN BOOLEAN MODE);

-- Phrase with operator: require phrase, exclude a word
SELECT * FROM articles
WHERE MATCH(title, body) AGAINST('+"management system" -tutorial' IN BOOLEAN MODE);
```

Phrase queries use the inverted index to find candidate documents containing all phrase words, then verify the exact word sequence by re-tokenizing the document text. This matches the approach used by InnoDB's FTS implementation.

### BM25 Ranking

Relevance scores are computed using the Okapi BM25 algorithm:

```
IDF(t) = ln(1 + (N - df + 0.5) / (df + 0.5))
score  = IDF * (tf * (k1+1)) / (tf + k1 * (1 - b + b * |d| / avgdl))
```

where `N` is the total number of documents, `df` is the document frequency of the term, `tf` is the term frequency in the document, `|d|` is the document length in tokens, and `avgdl` is the average document length. The parameters `k1` and `b` are configurable via system variables (see below). The IDF formula includes the `+1` inside the logarithm to guarantee non-negative scores for all terms, matching the Lucene variant that is now the industry standard.

### Tokenization

The engine uses a charset-aware tokenizer that correctly handles multi-byte character sets including UTF-8, CJK characters, Cyrillic, Greek, and other Unicode scripts. Text is split on word boundaries using MariaDB's charset classification tables, then lowercased using the charset's case-folding rules. Words shorter than `tidesdb_fts_min_word_len` or longer than `tidesdb_fts_max_word_len` are excluded from the index and search queries.

### Stop Words

Common words like "the", "is", "a", "of" are excluded from the full-text index to reduce index bloat and improve search quality. By default, TidesDB uses the same 36 stop words as InnoDB (the list from `information_schema.INNODB_FT_DEFAULT_STOPWORD`). Stop words are filtered during tokenization, so they are never stored in the inverted index and never match in search queries.

The stop word list can be customized via the `tidesdb_ft_stopword_table` system variable. When set to a `db_name/table_name` string, the engine loads stop words from the specified TidesDB table (which must have a `value` VARCHAR column containing one word per row). When set to NULL or empty string, the default stop words are restored:

```sql
-- Use a custom stop word table
CREATE TABLE mydb.my_stopwords (value VARCHAR(50)) ENGINE=TidesDB;
INSERT INTO mydb.my_stopwords (value) VALUES ('custom'), ('words'), ('here');
SET GLOBAL tidesdb_ft_stopword_table = 'mydb/my_stopwords';

-- Restore defaults
SET GLOBAL tidesdb_ft_stopword_table = NULL;
```

After changing the stop word table, existing FULLTEXT indexes should be rebuilt with `ALTER TABLE ... DROP INDEX ..., ADD FULLTEXT INDEX ...` to reflect the new stop word list.

### Blend Characters

Blend characters are treated as both word separators and valid word characters during tokenization. When a blend character appears inside a token, the tokenizer emits both the full blended form and the individual sub-parts. This enables Romance language elision (Italian, French, Catalan) and names with apostrophes to be searchable by any component or the full form.

For example, with `tidesdb_fts_blend_chars = "'"`:

| Input | Indexed Tokens |
|-------|---------------|
| `L'aria` | `l'aria`, `aria` |
| `Dell'aria` | `dell'aria`, `dell`, `aria` |
| `O'Malley` | `o'malley`, `malley` |

Searching for any of the indexed forms will match the document. The full blended form scores higher than a sub-part match because both the blended token and the sub-part contribute to the BM25 score.

```sql
-- Enable apostrophe blending for Italian/French
SET GLOBAL tidesdb_fts_blend_chars = "'";

CREATE TABLE articoli (
  id    INT PRIMARY KEY,
  testo TEXT,
  FULLTEXT (testo)
) ENGINE=TIDESDB;

INSERT INTO articoli VALUES (1, "L'aria fresca della montagna");
INSERT INTO articoli VALUES (2, "Dell'aria pura si respira bene");

-- All three queries match:
SELECT * FROM articoli WHERE MATCH(testo) AGAINST('aria');          -- sub-part
SELECT * FROM articoli WHERE MATCH(testo) AGAINST("l'aria");        -- blended
SELECT * FROM articoli WHERE MATCH(testo) AGAINST("dell'aria");     -- blended
```

The default is empty (no blend characters). The setting is global and takes effect for all subsequent FULLTEXT indexing and query operations. After changing blend characters, existing indexes should be rebuilt.

### Multi-Column Indexes

A single FULLTEXT index can span multiple columns. The engine concatenates the text from all indexed columns into a single document for tokenization and scoring:

```sql
CREATE TABLE docs (
  id      INT NOT NULL PRIMARY KEY,
  title   VARCHAR(200),
  summary TEXT,
  body    TEXT,
  FULLTEXT (title, summary, body)
) ENGINE=TIDESDB;
```

### Index Maintenance

FULLTEXT index entries are maintained transactionally within the same transaction as row data changes. When a row is inserted, the engine tokenizes the document, counts term frequencies, and writes one inverted index entry per unique term. When a row is deleted, the corresponding index entries are removed. When a row is updated and the indexed columns have changed, the old entries are removed and new entries are inserted. Global document count and average document length statistics are maintained atomically in the data column family for BM25 scoring.

### FTS System Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_fts_min_word_len` | 3 | Minimum word length in characters for indexing |
| `tidesdb_fts_max_word_len` | 84 | Maximum word length in characters for indexing |
| `tidesdb_fts_bm25_k1` | 1.2 | BM25 k1 parameter (term-frequency saturation) |
| `tidesdb_fts_bm25_b` | 0.75 | BM25 b parameter (document-length normalization, 0-1) |
| `tidesdb_ft_stopword_table` | NULL | Custom stop word table (`db_name/table_name`). NULL uses InnoDB defaults. |
| `tidesdb_fts_blend_chars` | empty | Characters treated as both separators and word chars. Set to `'` for Italian/French. |


## Vector Search

TidesDB supports approximate nearest neighbor (ANN) vector search through MariaDB's built-in MHNSW (Multi-layer Hierarchical Navigable Small World) vector index. The server handles all graph construction and search logic transparently; TidesDB provides the storage layer for both the main table data and the hidden MHNSW graph structure (hlindex).

```sql
CREATE TABLE embeddings (
  id    INT NOT NULL PRIMARY KEY,
  title VARCHAR(200),
  v     VECTOR(384) NOT NULL,
  VECTOR INDEX (v)
) ENGINE=TIDESDB;

INSERT INTO embeddings VALUES (1, 'cat picture', Vec_FromText('[0.1, 0.9, ...]'));
INSERT INTO embeddings VALUES (2, 'dog picture', Vec_FromText('[0.2, 0.8, ...]'));
```

### ANN Search

Vector search uses `ORDER BY VEC_DISTANCE_EUCLIDEAN()` or `VEC_DISTANCE_COSINE()` with a `LIMIT` clause. The MHNSW index provides approximate nearest neighbor results without scanning the entire table:

```sql
-- Find 5 nearest neighbors by Euclidean distance
SELECT id, title,
       VEC_DISTANCE_EUCLIDEAN(v, Vec_FromText('[0.15, 0.85, ...]')) AS dist
FROM embeddings
ORDER BY dist
LIMIT 5;

-- Cosine distance
SELECT id, title,
       VEC_DISTANCE_COSINE(v, Vec_FromText('[0.15, 0.85, ...]')) AS dist
FROM embeddings
ORDER BY dist
LIMIT 5;
```

### Index Options

The MHNSW index accepts two optional parameters:

```sql
CREATE TABLE docs (
  id INT PRIMARY KEY,
  v  VECTOR(128) NOT NULL,
  VECTOR INDEX (v) M=12 DISTANCE='cosine'
) ENGINE=TIDESDB;
```

`M` controls the number of neighbors per node in the MHNSW graph (default 6, range 3 to 200). Higher values improve recall at the cost of slower inserts and more memory. `DISTANCE` selects the distance metric, either `euclidean` (default) or `cosine`.

### DML Support

All DML operations are fully supported on vector-indexed tables. INSERT adds the vector to the MHNSW graph, DELETE removes it, and UPDATE on the vector column invalidates the old graph node and inserts a new one with the updated vector. The engine correctly handles the interleaved `record[0]`/`record[1]` access pattern that the MHNSW graph maintenance requires for BLOB-backed vector data.

### Limitations

Partitioned tables do not support vector indexes. Only one vector index per table is currently supported by MariaDB's MHNSW implementation.


## Spatial Indexes

TidesDB supports SPATIAL indexes for geographic and geometric data using a Hilbert curve encoding on the LSM tree. Instead of a traditional R-tree (which requires in-place node updates that conflict with LSM append-only semantics), each geometry's MBR center is mapped to a 64-bit Hilbert curve value and stored as a sorted key in a dedicated column family.

```sql
CREATE TABLE places (
  id       INT NOT NULL PRIMARY KEY,
  name     VARCHAR(100),
  location GEOMETRY NOT NULL,
  SPATIAL INDEX (location)
) ENGINE=TIDESDB;

INSERT INTO places VALUES (1, 'NYC',     ST_GeomFromText('POINT(40.7128 -74.0060)'));
INSERT INTO places VALUES (2, 'LA',      ST_GeomFromText('POINT(34.0522 -118.2437)'));
INSERT INTO places VALUES (3, 'Chicago', ST_GeomFromText('POINT(41.8781 -87.6298)'));
```

### Spatial Queries

All MBR-based spatial predicates are supported through the standard MariaDB spatial functions:

```sql
-- Find cities within a bounding box
SELECT name FROM places
WHERE MBRIntersects(location,
  ST_GeomFromText('POLYGON((39 -76, 43 -76, 43 -72, 39 -72, 39 -76))'));

-- Find cities contained within a region
SELECT name FROM places
WHERE MBRContains(
  ST_GeomFromText('POLYGON((25 -125, 45 -125, 45 -70, 25 -70, 25 -125))'),
  location);

-- Find cities within a region (equivalent to MBRContains with swapped args)
SELECT name FROM places
WHERE MBRWithin(location,
  ST_GeomFromText('POLYGON((25 -125, 45 -125, 45 -70, 25 -70, 25 -125))'));
```

The supported spatial predicates are `MBRIntersects`, `MBRContains`, `MBRWithin`, `MBREquals`, and `MBRDisjoint`. All geometry types are supported (POINT, LINESTRING, POLYGON, MULTIPOINT, MULTILINESTRING, MULTIPOLYGON, GEOMETRYCOLLECTION).

### How It Works

The spatial index stores each geometry as a single entry in a dedicated column family. The key is the 64-bit Hilbert curve value of the MBR center point (in big-endian for lexicographic ordering), followed by the primary key suffix. The value stores the full MBR (4 doubles = 32 bytes) for predicate evaluation during scans. The Hilbert curve provides excellent spatial locality - geographically nearby geometries tend to have numerically adjacent Hilbert values, which means they cluster together in the LSM tree and benefit from sequential I/O during range scans.

Spatial queries use Hilbert range decomposition to avoid scanning the entire index. The query bounding box is mapped to a coarse grid on the Hilbert curve, and only the grid cells that overlap the box are included. These cells are sorted and merged into contiguous Hilbert ranges, and the engine seeks directly to each range - skipping over large portions of the curve that fall outside the query box. Each candidate entry within a range undergoes exact MBR predicate filtering to eliminate false positives from curve approximation. For a query box covering 1% of the coordinate space, this typically produces 10-50 targeted seeks instead of a full index scan. INSERT, UPDATE, and DELETE operations maintain the spatial index transactionally alongside the row data, following the same pattern as secondary indexes and full-text indexes.


## Generated Columns

The engine supports both `VIRTUAL` and `STORED` (persistent) generated columns. Virtual columns are computed on read and never physically stored. Stored columns are computed on write and persisted as part of the row data, so they can be read back without recomputation.

```sql
CREATE TABLE orders (
  id       INT PRIMARY KEY,
  price    DECIMAL(10,2),
  qty      INT,
  total    DECIMAL(10,2) AS (price * qty) VIRTUAL,
  category VARCHAR(10) AS (
    CASE WHEN price >= 100 THEN 'premium' ELSE 'standard' END
  ) VIRTUAL
) ENGINE=TIDESDB;

INSERT INTO orders (id, price, qty) VALUES (1, 49.99, 3);
SELECT * FROM orders;
-- total = 149.97, category = 'standard'
```


## JSON

MariaDB's `JSON` type is an alias for a text type (typically `LONGTEXT`), so JSON storage and JSON querying work normally on TidesDB tables. JSON functions like `JSON_VALUE()`, `JSON_EXTRACT()`, `JSON_SET()`, and `JSON_CONTAINS()` are evaluated by the MariaDB server.

For efficient filtering on JSON paths, the recommended pattern is to use generated columns that extract the JSON paths you care about, then index those generated columns:

```sql
CREATE TABLE docs (
  id   INT NOT NULL PRIMARY KEY,
  data LONGTEXT,
  name VARCHAR(100) AS (JSON_VALUE(data, '$.name')) PERSISTENT,
  age  INT AS (JSON_VALUE(data, '$.age')) PERSISTENT,
  KEY idx_name (name),
  KEY idx_age (age)
) ENGINE=TIDESDB;

INSERT INTO docs (id, data) VALUES
  (1, '{"name":"Alice","age":30,"tags":["admin","dev"]}'),
  (2, '{"name":"Bob","age":25,"tags":["dev"]}');

-- Uses idx_name
SELECT * FROM docs WHERE name='Alice';

-- Uses idx_age
SELECT * FROM docs WHERE age >= 30;

-- Server-evaluated JSON predicate (typically not indexable unless you extract it)
SELECT * FROM docs WHERE JSON_CONTAINS(data, '"admin"', '$.tags');
```

This pattern provides engine-native indexing via normal secondary indexes, while keeping JSON manipulation and path extraction in standard SQL.


## Online DDL

The engine classifies `ALTER TABLE` operations into three tiers, each with different performance characteristics.

### Instant Operations

These complete instantly without rebuilding data. MariaDB rewrites the `.frm` metadata file, and the change takes effect immediately:

- Adding a column (`ADD COLUMN`)
- Dropping a column (`DROP COLUMN`)
- Renaming a column or index
- Changing a column's default value
- Changing table-level options (like `SYNC_MODE`, `COMPRESSION`, `BLOOM_FPR`, etc.)

When table-level options are changed, the engine applies the new configuration to all live column families (data CF and secondary index CFs) via `tidesdb_cf_update_runtime_config()` with `persist_to_disk=1`. The changes take effect immediately for new operations (new SSTables, new memtables, WAL sync mode). Existing SSTables retain their original settings and are read correctly. Share-level cached options such as isolation level, TTL, and encryption settings are also updated in memory.

Adding or dropping columns is instant because the packed row format includes a self-describing header that records the null bitmap size and field count at write time. When reading old rows written before the schema change, the engine adapts automatically, added columns receive their `DEFAULT` value, and dropped columns are silently skipped.

```sql
ALTER TABLE events ADD COLUMN priority INT NOT NULL DEFAULT 0, ALGORITHM=INSTANT;
ALTER TABLE events DROP COLUMN priority, ALGORITHM=INSTANT;
ALTER TABLE events ALTER COLUMN data SET DEFAULT 'none', ALGORITHM=INSTANT;
ALTER TABLE events CHANGE kind event_kind VARCHAR(50), ALGORITHM=INSTANT;
ALTER TABLE events SYNC_MODE='NONE', ALGORITHM=INSTANT;
```

### Inplace Operations

Adding or dropping secondary indexes is done inplace. When a new index is added, the engine creates a new column family for it, then performs a full table scan to populate all index entries. This runs with no server-level lock blocking (`HA_ALTER_INPLACE_NO_LOCK`), so concurrent reads and writes can proceed during the index build. When adding a `UNIQUE` index, the engine checks for duplicate values during the population scan and aborts with `ER_DUP_ENTRY` if any are found, preserving all existing rows.

```sql
ALTER TABLE events ADD INDEX idx_ts (ts), ALGORITHM=INPLACE;
ALTER TABLE events DROP INDEX idx_ts, ALGORITHM=INPLACE;

-- Add and drop in a single statement
ALTER TABLE events ADD INDEX idx_kind (event_kind), DROP INDEX idx_ts, ALGORITHM=INPLACE;
```

For large tables, the index population is batched in groups of 10,000 rows per transaction commit, to avoid unbounded memory growth in the transaction's write buffer.

### Copy Operations

Changing column types or altering the primary key require a full table copy:

```sql
ALTER TABLE events MODIFY COLUMN data MEDIUMTEXT;
ALTER TABLE events DROP PRIMARY KEY, ADD PRIMARY KEY (id, ts);
```

The engine explicitly rejects `ALGORITHM=INPLACE` for these operations with a clear error message, so you will never accidentally trigger a slow copy when you expected an instant change.


## ANALYZE TABLE

Running `ANALYZE TABLE` on a TidesDB table produces detailed internal statistics as note-level messages in the result set:

```
MariaDB [demo]> ANALYZE TABLE products;
+---------------+---------+----------+-------------------------------------------------------------------------------------+
| Table         | Op      | Msg_type | Msg_text                                                                            |
+---------------+---------+----------+-------------------------------------------------------------------------------------+
| demo.products | analyze | Note     | TIDESDB: CF 'demo__products'  total_keys=10  data_size=636 bytes  memtable=0 bytes  |
|               |         |          |   levels=5  read_amp=2.00  cache_hit=0.0%                                           |
| demo.products | analyze | Note     | TIDESDB: avg_key=18.8 bytes  avg_value=44.0 bytes                                   |
| demo.products | analyze | Note     | TIDESDB: level 1  sstables=0  size=0 bytes  keys=0                                  |
| demo.products | analyze | Note     | TIDESDB: level 2  sstables=1  size=636 bytes  keys=10                               |
| demo.products | analyze | Note     | TIDESDB: level 3  sstables=0  size=0 bytes  keys=0                                  |
| demo.products | analyze | Note     | TIDESDB: level 4  sstables=0  size=0 bytes  keys=0                                  |
| demo.products | analyze | Note     | TIDESDB: level 5  sstables=0  size=0 bytes  keys=0                                  |
| demo.products | analyze | Note     | TIDESDB: idx CF 'demo__products__idx_idx_category'  keys=10  data_size=449 bytes     |
|               |         |          |   levels=5                                                                          |
| demo.products | analyze | status   | OK                                                                                  |
+---------------+---------+----------+-------------------------------------------------------------------------------------+
```

The output includes the total number of keys, data size, memtable size, number of LSM levels, read amplification factor, cache hit rate, average key and value sizes, and per-level SSTable counts and sizes. For tables with secondary indexes, each index CF's statistics are reported separately.

This information is useful for understanding the physical layout of your data and diagnosing performance characteristics.


## SHOW ENGINE TIDESDB STATUS

The engine supports `SHOW ENGINE TIDESDB STATUS`, which displays database-level statistics and block cache metrics:

```sql
SHOW ENGINE TIDESDB STATUS\G
```

The output includes the data directory path, number of column families, global sequence number, memory usage (total system memory, resolved memory limit, memory pressure level, memtable bytes, transaction memory bytes), storage metrics (total SSTables, open SSTable handles, total data size, immutable memtable count), background queue sizes (flush pending, flush queue, compaction queue), and block cache statistics (enabled, entries, size, hits, misses, hit rate, partitions).

When `tidesdb_print_all_conflicts` is enabled, the last conflict event is also displayed under a Conflicts section.

### Status Variables

The engine also exposes machine-readable status variables for monitoring tools (Prometheus mysqld_exporter, PMM, Datadog, etc.):

```sql
SHOW GLOBAL STATUS LIKE 'tidesdb%';
```

| Variable | Description |
|----------|-------------|
| `Tidesdb_version` | TideSQL plugin version string (e.g. `4.2.1`) |
| `Tidesdb_version_hex` | TideSQL plugin version as integer (e.g. `262657` = `0x40201`) |
| `Tidesdb_column_families` | Number of active column families |
| `Tidesdb_global_sequence` | Global MVCC sequence number |
| `Tidesdb_memtable_bytes` | Total memtable memory usage in bytes |
| `Tidesdb_txn_memory_bytes` | Transaction buffer memory in bytes |
| `Tidesdb_memory_limit` | Resolved memory limit in bytes |
| `Tidesdb_memory_pressure` | Memory pressure level (0 = normal) |
| `Tidesdb_total_sstables` | Total SSTable count across all column families |
| `Tidesdb_open_sstables` | Open SSTable file handles |
| `Tidesdb_data_size_bytes` | Total data size on disk in bytes |
| `Tidesdb_immutable_memtables` | Immutable memtables pending flush |
| `Tidesdb_flush_pending` | Flush operations pending |
| `Tidesdb_flush_queue` | Flush queue depth |
| `Tidesdb_compaction_queue` | Compaction queue depth |
| `Tidesdb_cache_entries` | Block cache entry count |
| `Tidesdb_cache_bytes` | Block cache memory usage in bytes |
| `Tidesdb_cache_hits` | Block cache hit count |
| `Tidesdb_cache_misses` | Block cache miss count |
| `Tidesdb_cache_hit_rate` | Block cache hit rate (percentage) |
| `Tidesdb_cache_partitions` | Block cache partition count |

Values are refreshed every two seconds, aligned with the optimizer statistics refresh cycle. This provides the same monitoring integration that InnoDB offers via `SHOW GLOBAL STATUS LIKE 'innodb%'`.


## Online Backup

TidesDB supports online backups triggered through a system variable. Setting `tidesdb_backup_dir` to a directory path initiates a consistent backup of the entire TidesDB data directory:

```sql
SET GLOBAL tidesdb_backup_dir = '/path/to/backup';
```

The backup runs without blocking normal read and write operations. The target directory must not already exist or must be empty. After the backup completes, the variable reflects the path of the last successful backup. To clear it:

```sql
SET GLOBAL tidesdb_backup_dir = '';
```


## Checkpoint

TidesDB also supports lightweight checkpoints that use hard links instead of copying SSTable data. Checkpoints are near-instant and consume no additional disk space until compaction removes old SSTables from the live database.

```sql
SET GLOBAL tidesdb_checkpoint_dir = '/path/to/checkpoint';
```

The checkpoint directory must not already exist or must be empty. Unlike a full backup, checkpoints require the target to be on the same filesystem as the data directory (hard link requirement). The checkpoint can be opened as a normal TidesDB database.

For archival or cross-filesystem copies, use `tidesdb_backup_dir` instead.


## Partitioning

TidesDB tables can be partitioned using MariaDB's standard partitioning syntax. Each partition becomes a separate TidesDB table (and therefore a separate column family), which means compaction and flushes happen independently per partition.

```sql
CREATE TABLE metrics (
  id      INT NOT NULL,
  ts      DATE NOT NULL,
  value   DOUBLE,
  PRIMARY KEY (id, ts)
) ENGINE=TIDESDB
PARTITION BY RANGE COLUMNS(ts) (
  PARTITION p_2024   VALUES LESS THAN ('2025-01-01'),
  PARTITION p_2025   VALUES LESS THAN ('2026-01-01'),
  PARTITION p_future VALUES LESS THAN MAXVALUE
);
```

All partitioning schemes supported by MariaDB work with TidesDB, `HASH`, `KEY`, `RANGE`, `LIST`, and `RANGE COLUMNS`. Secondary indexes on partitioned tables also work correctly, with each partition maintaining its own index column family.

Partitions can be added and dropped with `ALTER TABLE`:

```sql
ALTER TABLE metrics ADD PARTITION (PARTITION p_2026 VALUES LESS THAN ('2027-01-01'));
ALTER TABLE metrics DROP PARTITION p_2024;  -- removes all data in that range
```


## System Variables

The engine exposes several system variables that control TidesDB's runtime behavior:

### Global Variables (read-only, set at startup)

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_flush_threads` | 4 | Number of background threads flushing memtables to SSTables |
| `tidesdb_compaction_threads` | 4 | Number of background threads performing LSM compaction |
| `tidesdb_log_level` | DEBUG | TidesDB internal log level (DEBUG, INFO, WARN, ERROR, FATAL, NONE) |
| `tidesdb_block_cache_size` | 256 MB | Size of the global block cache shared across all column families |
| `tidesdb_max_open_sstables` | 256 | Maximum number of SSTable file handles cached in the LRU |
| `tidesdb_max_memory_usage` | 0 (auto) | Global memory limit in bytes; 0 lets the library auto-detect (50% of system RAM; minimum 5%) |
| `tidesdb_data_home_dir` | (empty) | Override the TidesDB data directory; defaults to `<mysql_datadir>/../tidesdb_data` |
| `tidesdb_log_to_file` | ON | Write TidesDB logs to a LOG file in the data directory instead of stderr |
| `tidesdb_log_truncation_at` | 24 MB | Log file truncation size in bytes; 0 disables truncation |
| `tidesdb_unified_memtable` | ON | Use a single shared WAL and memtable across all column families. Reduces WAL I/O from O(num_tables) to O(1) per commit. Requires all CFs to use the same comparator |
| `tidesdb_unified_memtable_write_buffer_size` | 128 MB | Write buffer size for the unified memtable (0 = library default). Only meaningful when `tidesdb_unified_memtable=ON` |
| `tidesdb_unified_memtable_sync_mode` | FULL | Sync mode for the unified WAL (NONE, INTERVAL, FULL). Controls durability of all commits when unified memtable is enabled. Per-CF `SYNC_MODE` is ignored in unified mode since per-CF WALs do not exist |
| `tidesdb_unified_memtable_sync_interval` | 128000 | Sync interval in microseconds for the unified WAL (only used when `unified_memtable_sync_mode=INTERVAL`) |
| `tidesdb_object_store_backend` | LOCAL | Object store backend (LOCAL disables, S3 enables S3-compatible storage) |
| `tidesdb_s3_endpoint` | (empty) | S3 endpoint hostname (e.g. s3.amazonaws.com or minio.local:9000) |
| `tidesdb_s3_bucket` | (empty) | S3 bucket name |
| `tidesdb_s3_prefix` | (empty) | S3 key prefix for multi-tenant buckets (e.g. production/db1/) |
| `tidesdb_s3_access_key` | (empty) | S3 access key ID |
| `tidesdb_s3_secret_key` | (empty) | S3 secret access key |
| `tidesdb_s3_region` | (empty) | S3 region (e.g. us-east-1, empty for MinIO) |
| `tidesdb_s3_use_ssl` | ON | Use HTTPS for S3 connections |
| `tidesdb_s3_path_style` | OFF | Use path-style S3 URLs (required for MinIO) |
| `tidesdb_objstore_local_cache_max` | 0 | Maximum local cache size in bytes (0 = unlimited) |
| `tidesdb_objstore_wal_sync_threshold` | 1 MB | Sync active WAL to object store when it grows by this many bytes (0 = disable) |
| `tidesdb_objstore_wal_sync_on_commit` | OFF | Upload WAL after every commit for RPO=0 replication |
| `tidesdb_replica_mode` | OFF | Enable read-only replica mode (writes return SQL error) |
| `tidesdb_replica_sync_interval` | 5000000 | MANIFEST poll interval for replica sync in microseconds |

### Global Variables (dynamic)

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_backup_dir` | (empty) | Set to a path to trigger an online backup; clear with empty string |
| `tidesdb_checkpoint_dir` | (empty) | Set to a path to trigger a hard-link checkpoint (near-instant, same filesystem only); clear with empty string |
| `tidesdb_print_all_conflicts` | OFF | Log every `TDB_ERR_CONFLICT` event to the error log (similar to `innodb_print_all_deadlocks`). Last conflict info also shown in `SHOW ENGINE TIDESDB STATUS` |
| `tidesdb_pessimistic_locking` | OFF | Enable plugin-level row locks for `SELECT ... FOR UPDATE`, `UPDATE`, `DELETE`, and `INSERT` on user-defined primary keys. OFF (default) uses pure optimistic MVCC where concurrent writers on the same row are detected at COMMIT time. ON acquires per-row locks via a partitioned hash-table lock manager with wait-for-graph deadlock detection. All write-intent statements acquire locks, including autocommit statements. Locks can be acquired on non-existing PK values (e.g. `SELECT ... FOR UPDATE` on a missing row blocks `INSERT` of that key). Locks are held until `COMMIT` or `ROLLBACK`. Enable for TPC-C or workloads that depend on row-level serialization semantics |
| `tidesdb_promote_primary` | OFF | Set to ON to promote a replica to primary mode. Performs a final MANIFEST sync and WAL replay, creates a local WAL, and starts accepting writes. Resets to OFF after promotion |

### Session Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_ttl` | 0 | Per-session TTL in seconds applied to INSERT/UPDATE; 0 means use the table-level default. Can be set with `SET SESSION` or `SET STATEMENT` |
| `tidesdb_skip_unique_check` | OFF | Skip uniqueness checks on primary key and unique secondary indexes during INSERT. Only safe when the application guarantees no duplicates (e.g., bulk loads with monotonic PKs) |
| `tidesdb_single_delete_primary` | OFF | Use single-delete semantics on the primary row CF for this session's DELETEs. See [Single-Delete Optimization](#single-delete-optimization) |
| `tidesdb_compact_after_range_delete_min_rows` | 0 | If non-zero, after a multi-row DELETE that touches at least this many rows, the engine calls `tidesdb_compact_range` over the touched primary-key range to physically reclaim tombstoned space synchronously. See [Auto Compact After Range Delete](#auto-compact-after-range-delete) |
| `tidesdb_default_compression` | LZ4 | Default compression algorithm (NONE, SNAPPY, LZ4, ZSTD, LZ4_FAST) |
| `tidesdb_default_write_buffer_size` | 128 MB | Default write buffer size in bytes |
| `tidesdb_default_bloom_filter` | ON | Default bloom filter setting |
| `tidesdb_default_use_btree` | OFF | Default USE_BTREE setting (0=LSM, 1=B-tree) |
| `tidesdb_default_block_indexes` | ON | Default block indexes setting |
| `tidesdb_default_sync_mode` | FULL | Default sync mode (NONE, INTERVAL, FULL) |
| `tidesdb_default_sync_interval_us` | 128000 | Default sync interval in microseconds (for INTERVAL mode) |
| `tidesdb_default_bloom_fpr` | 100 | Default bloom FPR in parts per 10,000 (100 = 1%) |
| `tidesdb_default_klog_value_threshold` | 512 | Default klog value threshold in bytes (values >= this go to vlog) |
| `tidesdb_default_l0_queue_stall_threshold` | 20 | Default L0 queue stall threshold |
| `tidesdb_default_l1_file_count_trigger` | 4 | Default L1 file count compaction trigger |
| `tidesdb_default_level_size_ratio` | 10 | Default level size ratio |
| `tidesdb_default_min_levels` | 5 | Default minimum LSM-tree levels |
| `tidesdb_default_dividing_level_offset` | 2 | Default dividing level offset |
| `tidesdb_default_skip_list_max_level` | 12 | Default skip list max level |
| `tidesdb_default_skip_list_probability` | 25 | Default skip list probability (percentage; 25 = 0.25) |
| `tidesdb_default_index_sample_ratio` | 1 | Default block index sample ratio |
| `tidesdb_default_block_index_prefix_len` | 16 | Default block index prefix length |
| `tidesdb_default_min_disk_space` | 100 MB | Default minimum disk space in bytes |
| `tidesdb_default_isolation_level` | REPEATABLE_READ | Default isolation level |
| `tidesdb_default_object_lazy_compaction` | OFF | Double L1 compaction trigger in object store mode |
| `tidesdb_default_object_prefetch_compaction` | ON | Prefetch input SSTables before compaction merge |
| `tidesdb_default_tombstone_density_trigger` | 0 | Default tombstone-density compaction trigger ratio for new tables, in parts per 10000 (5000 = 0.50). Default 0 disables the check |
| `tidesdb_default_tombstone_density_min_entries` | 1024 | Minimum entry count for an SSTable to be considered by the tombstone-density trigger; smaller SSTables are ignored |

Every table option has a corresponding `tidesdb_default_*` session variable. When `CREATE TABLE` does not explicitly set an option, the session (or global) default is used. Table-level options in `CREATE TABLE` override the default. This design mirrors InnoDB's approach of having global defaults that individual tables can override, and makes it straightforward to configure all tables uniformly for benchmarking or deployment without repeating options in every DDL statement:

```ini
# my.cnf -- set defaults for all new TidesDB tables
[mysqld]
plugin-load-add=ha_tidesdb.so
tidesdb_default_sync_mode=NONE
tidesdb_default_compression=NONE
tidesdb_default_bloom_fpr=10
tidesdb_default_klog_value_threshold=1024
tidesdb_default_l0_queue_stall_threshold=20
```

```sql
-- All new tables inherit the global defaults
CREATE TABLE t1 (id INT PRIMARY KEY) ENGINE=TIDESDB;

-- Override a specific option for one table
CREATE TABLE t2 (id INT PRIMARY KEY) ENGINE=TIDESDB COMPRESSION='ZSTD';

-- Change defaults for the current session only
SET SESSION tidesdb_default_sync_mode = 'FULL';
CREATE TABLE t3 (id INT PRIMARY KEY) ENGINE=TIDESDB;  -- uses FULL
```

The block cache is a read cache backed by two independent clock caches, one for raw klog block bytes (used by the default block-based SSTable format) and one for deserialized B+tree nodes (used by column families with `USE_BTREE=1`). Both caches share the configured `tidesdb_block_cache_size` budget. A larger cache reduces read amplification for workloads that repeatedly access the same key ranges. The flush and compaction thread counts should be tuned based on the number of column families in use - only one flush and one compaction can run per column family at a time, so with N column families, up to N threads can be busy simultaneously. The default of 4 threads handles workloads with up to 4 tables (8 column families, data + one secondary index each). When `tidesdb_log_to_file` is enabled (the default), TidesDB writes to a `LOG` file in the data directory with automatic truncation controlled by `tidesdb_log_truncation_at` (default 24 MB, 0 to disable truncation). When disabled, logs are written to stderr.

The `tidesdb_max_memory_usage` variable controls the global memory cap enforced by the library. When set to 0, the library auto-detects available system memory and targets 50% of it (with a minimum floor of 5% of total system RAM). In a shared MariaDB server where InnoDB and other components also consume memory, you may want to set an explicit limit. When `tidesdb_unified_memtable=ON` (the default), all column families share a single memtable with its own write buffer (`tidesdb_unified_memtable_write_buffer_size`, default 128 MB), so per-CF `WRITE_BUFFER_SIZE` does not affect memtable memory. The per-CF `L0_QUEUE_STALL_THRESHOLD` (default 20) still applies for backpressure. A hard cap of 16 immutable memtables applies regardless of the stall threshold. When unified memtable is disabled, each CF has its own memtable and worst-case memory per column family is approximately `(WRITE_BUFFER_SIZE × 1.5) + (WRITE_BUFFER_SIZE × min(L0_QUEUE_STALL_THRESHOLD, 16))`.


## How It Stores Data Internally

Understanding the physical layout helps when interpreting `ANALYZE TABLE` output or debugging performance.

Each table's data lives in a column family, which is an independent LSM-tree. Writes go to a skip-list memtable. When the memtable reaches the configured write buffer size, it becomes immutable and is flushed to disk as a sorted SSTable in Level 1. Compaction then merges overlapping SSTables from lower levels into higher levels, maintaining the sorted invariant.

Row keys inside the column family use a namespace prefix byte. Data rows use `0x01`, and the byte `0x00` is reserved for future metadata entries. This prefix ensures that a table scan (which seeks to `0x01`) naturally skips over any non-data keys.

Primary key bytes are encoded in a memcmp-comparable format. For a signed 32-bit integer, the encoding flips the sign bit and stores the result in big-endian byte order. This means that the integer -1 sorts before 0, and 0 sorts before 1, all under a simple byte comparison. The same principle extends to all numeric types and string collations.

Row values are stored in a packed binary format. Each row begins with a 5-byte header, a magic byte (`0xFE`), followed by the null bitmap size (2 bytes LE) and field count (2 bytes LE) at the time the row was written. This header enables instant `ADD COLUMN` and `DROP COLUMN` by letting the deserializer adapt to rows written with any prior schema. After the header, the null bitmap is written, then each non-null field is serialized using `Field::pack()`. On read, `Field::unpack()` restores the fields into MariaDB's record buffer. If a row was written with fewer fields than the current schema (column was added), the missing fields receive their `DEFAULT` value. If a row was written with more fields (column was dropped), the extra data is skipped. This format is more compact than storing the raw `reclength` bytes, particularly for tables with `VARCHAR` or `CHAR` columns.

Secondary index entries are stored in their own column family. The key format is the concatenation of the comparable index-column bytes and the comparable primary key bytes. The value is a single zero byte (effectively empty); all the information lives in the key. To resolve a secondary index lookup, the engine seeks into the index CF, reads the key, splits off the trailing PK bytes, and performs a point-get into the data CF. When the server indicates that only indexed columns are needed (a covering index scan), the engine can decode primary key and index column values directly from the comparable-format index key bytes - integers, temporal types (DATE, DATETIME, TIMESTAMP, YEAR), and fixed-length CHAR/BINARY (binary/latin1) - skipping the data CF point-get entirely.

For tables without an explicit primary key, the engine generates a hidden 8-byte big-endian row ID, assigned from an atomic counter. This counter is recovered on table open by seeking to the last key in the column family.


## Statistics and the Optimizer

The engine maintains cached statistics that are refreshed at most every two seconds. These statistics include the total number of keys, total data size, average key and value sizes, and the LSM-tree's read amplification factor. They are stored as atomic variables on the shared table descriptor and feed into MariaDB's cost-based optimizer through `info()`, `scan_time()`, `keyread_time()`, `rnd_pos_time()`, and `records_in_range()`.

The cost model accounts for the fact that LSM-tree reads may need to consult multiple levels. The read amplification factor - obtained from `tidesdb_get_stats()` - scales the cost of point lookups and random-position reads. A higher read amplification nudges the optimizer toward sequential scans; when the data is well-compacted and the amplification is low, index lookups are cheap.

### Cost Methods

- `scan_time()` uses `tidesdb_range_cost()` over the full data column family key space, giving the optimizer an LSM-aware full-table-scan cost that accounts for the actual number of levels, SSTables, compression overhead, and merge complexity. The cost is split 90% I/O / 10% CPU. Falls back to the base `handler::scan_time()` when the library cannot produce a meaningful estimate.

- `keyread_time()` models index reads as `rows × 0.00003 × read_amp + ranges × 0.0001`. Each point lookup touches `read_amp` levels; range scans amortize the merge-heap setup cost across rows.

- `rnd_pos_time()` models random-position lookups as `rows × 0.00005 × read_amp`, reflecting that each random fetch is a point-get through the full LSM stack.

### Range-Aware Cardinality Estimation

`records_in_range()` uses a two-path strategy:

1. Equality detection · When both key bounds convert to identical comparable bytes (a point equality like `WHERE k = 5`), the engine returns the `rec_per_key` estimate directly. This avoids the `tidesdb_range_cost()` path, which is an I/O cost metric rather than a cardinality metric - for memtable-only data it cannot distinguish a point range from a full scan, so the proportional estimate would be meaningless.

2. Range estimation · For range predicates the engine calls `tidesdb_range_cost()` for the requested key range and for the full key space, then returns `total_records × (range_cost / full_cost)`. The function examines in-memory metadata - block indexes, SSTable min/max keys, and entry counts - without any disk I/O. A narrow range returns a small estimate while a wide range returns a proportionally larger one, allowing the optimizer to make informed decisions about index selection and join ordering.


## OPTIMIZE TABLE

Running `OPTIMIZE TABLE` triggers a synchronous flush and compaction on all column families associated with the table, both the main data CF and every secondary index CF. The engine calls `tidesdb_purge_cf()` for each column family, which rotates the unified memtable (when enabled), flushes the resulting immutable memtable to SSTables, and then runs a full compaction inline, blocking until complete. This means the table is fully compacted when the statement returns. In object store mode, the flushed SSTables are uploaded to S3, making `OPTIMIZE TABLE` the most direct way to push data to the object store. After compaction, the cached statistics are invalidated so the optimizer sees the post-compaction state sooner.

```sql
OPTIMIZE TABLE products;
```

This is useful after bulk deletes or updates that leave behind a large number of tombstones, or when `ANALYZE TABLE` reports high read amplification.

## CHECK TABLE / REPAIR TABLE

`CHECK TABLE` verifies that all column families associated with the table are readable by fetching metadata from all SSTables. This validates manifests, block indexes, bloom filters, and metadata blocks are intact. If any SSTable is unreadable, the command returns an error indicating the table is corrupt.

```sql
CHECK TABLE orders;
```

`REPAIR TABLE` triggers a full purge (flush + compaction) of all column families, identical to `OPTIMIZE TABLE`. The compaction pass reads and re-checksums every block, dropping corrupt entries, expired TTL data, and tombstones. In unified memtable mode, the first purge call rotates the shared memtable once, and subsequent index CF purges just run compaction.

```sql
REPAIR TABLE orders;
```

## FLUSH TABLES FOR EXPORT

TidesDB supports `FLUSH TABLES ... FOR EXPORT` for online physical table copies. The statement flushes all pending memtable data to SSTables and holds a table lock while the data directory files are consistent and copyable. After copying, release the lock with `UNLOCK TABLES`.

```sql
FLUSH TABLES orders FOR EXPORT;
-- copy the column family directories from tidesdb_data/
UNLOCK TABLES;
```

## Rename and Drop

Renaming a table renames all associated column families, including secondary index CFs. The engine enumerates all column families whose names start with the old table's prefix and renames each one.

Dropping a table drops the main data CF and then enumerates and drops all index CFs that share the table's naming prefix. The operation is idempotent, if a CF does not exist, the engine simply continues.

`DROP DATABASE` is wired through the engine's handlerton `drop_database` callback. MariaDB invokes it after removing the `.frm` files for the database; the engine then enumerates every column family whose name starts with `<db_name>__` and drops each one (data CFs plus their `__idx_*` secondary-index CFs), force-removes the on-disk directories, and purges schema-CF entries for the database (object-store mode only). This prevents orphaned column families accumulating on disk when a database is dropped.

```sql
RENAME TABLE events TO event_log;
TRUNCATE TABLE event_log;
DROP TABLE event_log;
DROP DATABASE mydb;   -- drops every TidesDB CF under mydb__*
```

## Server Lifecycle Hooks

The engine wires several handlerton callbacks so that TidesDB cooperates with MariaDB's lifecycle and durability guarantees:

| Callback | Purpose |
|---------|---------|
| `flush_logs` | `FLUSH LOGS` (and `mariadb-backup`'s pre-copy step) syncs the TidesDB WAL so on-disk copies are a consistent snapshot. |
| `panic` | On signal-driven shutdown paths MariaDB may call `panic(HA_PANIC_CLOSE)` instead of the normal deinit; the engine performs an orderly `tidesdb_close()` there so pending commits are flushed. |
| `pre_shutdown` | Lets background threads quiesce before the deinit path begins; syncs the unified WAL so compactions in flight don't get killed mid-write. |
| `kill_query` | `KILL QUERY <id>` wakes any waiter blocked in `row_lock_acquire` and, in combination with `thd_killed()` checks scattered through the scan loops (`rnd_next`, `index_next`, `index_prev`, `index_next_same`, `spatial_scan_next`, `ft_read`), promptly terminates long-running statements with `HA_ERR_ABORTED_BY_USER`. |


## Object Store Mode

TidesDB supports an optional object store backend that stores SSTables in S3-compatible storage (AWS S3, MinIO, Google Cloud Storage) while using local disk as a cache. This enables cloud-native deployments where storage capacity is virtually unlimited and compute nodes can be replaced without data loss.

### Why Use Object Store Mode

Object store mode is designed for deployments where local disk is either limited, ephemeral, or both. In container environments, Kubernetes pods, and serverless setups, local storage is temporary. Object store mode turns local disk into a bounded cache while S3 holds the durable copy of all data. A node with 1TB of NVMe and an S3 bucket can serve a 100TB dataset, with the hot working set at local disk speed and cold data fetched on demand.

The storage engine maintains a four-tier hierarchy automatically. Hot data lives in the in-memory block cache (microsecond reads). Warm data lives on local disk with open file handles (microsecond to millisecond reads). Cold data is on local disk but closed (reopened on access). Frozen data is in the object store only and fetched via HTTP range requests for point lookups or parallel bulk download for scans. Data flows downward through these tiers as it ages and flows back up when accessed.

### When to Use It

- Cloud-native deployments with separated compute and storage
- Workloads that benefit from virtually unlimited storage capacity
- Environments where local disk is ephemeral (containers, serverless, spot instances)
- Multi-node setups where cold start recovery from remote storage replaces traditional replication

### When Not to Use It

- Single-server deployments with abundant local storage and no cloud requirement
- Latency-critical workloads where every read must be served from local disk
- Air-gapped environments without network access to an object store

### Enabling Object Store Mode

Add the following to `my.cnf`:

```ini
[mariadb]
tidesdb_object_store_backend = S3
tidesdb_s3_endpoint = s3.amazonaws.com
tidesdb_s3_bucket = my-tidesdb-bucket
tidesdb_s3_access_key = AKIAIOSFODNN7EXAMPLE
tidesdb_s3_secret_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
tidesdb_s3_region = us-east-1
tidesdb_objstore_local_cache_max = 536870912
```

For MinIO:

```ini
tidesdb_object_store_backend = S3
tidesdb_s3_endpoint = minio.local:9000
tidesdb_s3_bucket = tidesdb-data
tidesdb_s3_use_ssl = OFF
tidesdb_s3_path_style = ON
tidesdb_s3_access_key = minioadmin
tidesdb_s3_secret_key = minioadmin
```

Object store mode works with unified memtable mode (enabled by default). Unified memtable is strongly recommended for object store deployments because it reduces WAL I/O to a single file and ensures all column families are flushed together. No other configuration changes are needed. Existing SQL, table options, indexes, transactions, and all engine features work identically.

### Schema Discovery

When object store mode is active, the engine creates a reserved column family called `__tidesql_schema` that stores the binary `.frm` image for every TidesDB table. This column family replicates through S3 alongside data, so replicas automatically discover table definitions without any manual schema synchronization.

The schema CF is updated on every DDL operation:

- `CREATE TABLE` stores the `.frm` binary from the in-memory image (MariaDB does not write `.frm` files to disk for engines with discovery callbacks)
- `ALTER TABLE` updates the stored `.frm` after the inplace alter commits
- `DROP TABLE` removes the entry
- `RENAME TABLE` moves the entry to the new key

At startup, the plugin scans the schema CF for all unique database names and creates any missing database directories under the MariaDB data directory. This ensures `SHOW DATABASES` and `SHOW TABLES` work correctly on replicas without manual `CREATE DATABASE` commands.

The engine registers MariaDB's `discover_table`, `discover_table_names`, and `discover_table_existence` handlerton callbacks. When MariaDB opens a table that has no local `.frm` file, these callbacks read the `.frm` from the schema CF and materialize it. The `.frm` is then cached on disk for subsequent opens.

To prevent an infinite retry loop, `discover_table` verifies that the data column family exists locally before returning the `.frm`. If the table definition has been replicated but the data has not been synced yet, the engine returns "table not found" rather than entering a discover -> open-fail -> re-discover cycle.

In local-only mode (no object store), none of this machinery is active. The schema CF is never created, discovery callbacks are not registered, and there is zero overhead.

### Read Replicas

A separate MariaDB instance can run as a read-only replica by pointing to the same S3 bucket with replica mode enabled:

```ini
tidesdb_replica_mode = ON
tidesdb_replica_sync_interval = 1000000
```

The replica periodically polls S3 for MANIFEST updates and discovers new column families that the primary has created. It also replays unified WAL segments for near-real-time reads. Writes are rejected with a clean SQL error. Multiple replicas can run simultaneously, each with its own local cache.

Table definitions are discovered automatically from the `__tidesql_schema` column family. When a client queries a table that the replica has not opened before, the engine reads the `.frm` from the schema CF, writes it to local disk, and opens the table. Database directories are created at startup, so `SHOW DATABASES` and `SHOW TABLES` reflect the primary's schema immediately.

`OPTIMIZE TABLE` on the primary triggers a unified memtable flush, which creates SSTables for all column families (including `__tidesql_schema`) and uploads them to S3. This ensures that both table data and schema definitions reach the object store promptly.

### Primary Promotion

When the primary fails, a replica can be promoted to accept writes:

```sql
SET GLOBAL tidesdb_promote_primary = ON;
```

This waits for any in-progress replica sync to complete, performs a final MANIFEST sync and WAL replay to catch the last writes from the old primary, creates a local WAL for crash recovery, and starts accepting writes. The promotion is fast because the replica already has metadata in memory from the sync loop.

After promotion, tables that were previously opened (and have their `.frm` cached on disk) are accessible immediately. Tables that have not been opened yet will be discovered from the schema CF on first access, provided their data column family has been synced. If a table's schema has been replicated but its data has not arrived yet, the query returns "table not found" rather than blocking.

### WAL Sync Options

The data loss window on crash depends on WAL sync configuration:

| Setting | RPO | Tradeoff |
|---------|-----|----------|
| `objstore_wal_sync_on_commit = ON` | Zero | One HTTP round-trip per commit |
| `objstore_wal_sync_threshold = 1048576` (default) | ~1MB of writes | Periodic sync based on write volume |
| `objstore_wal_sync_threshold = 0` | One full flush cycle | No periodic sync |

On clean shutdown there is no data loss regardless of configuration.

### Monitoring

`SHOW ENGINE TIDESDB STATUS` includes an Object Store section when enabled:

```
--- Object Store ---
Connector: s3
Total uploads: 1234
Upload failures: 0
Upload queue depth: 2
Local cache: 234567890 / 536870912 bytes (45 files)
Replica mode: OFF
```

### Kubernetes Deployment

The `k8s/` directory contains example manifests for deploying TidesQL with object store mode:

- `primary.yaml` - StatefulSet for the primary MariaDB with S3 configuration
- `replica.yaml` - Deployment for read replicas with replica mode
- `failover-controller.yaml` - Automated failover controller that health-checks the primary and promotes a replica when unresponsive

The failover controller runs as a separate pod, checks the primary every few seconds, and after consecutive failures promotes a replica via `SET GLOBAL tidesdb_promote_primary = ON`.

Because MariaDB's default `root` user authenticates via unix socket (localhost only), the failover controller needs a dedicated user with TCP access to run the promotion command from a separate pod:

```sql
CREATE USER 'monitor'@'%' IDENTIFIED BY '<strong-password>';
GRANT ALL PRIVILEGES ON *.* TO 'monitor'@'%' WITH GRANT OPTION;
```

This user must be created on both the primary and every replica. If MariaDB's `simple_password_check` plugin is active, the password must meet complexity requirements (mixed case, digits, special characters).

Replica pods start with a fresh data directory. The plugin's schema discovery creates database directories at startup from the `__tidesql_schema` column family, and table definitions are materialized on first access. No manual `CREATE DATABASE` commands are needed on replicas.

### Build Requirement

The S3 connector requires TidesDB to be built with `-DTIDESDB_WITH_S3=ON`, which requires libcurl and OpenSSL. The filesystem connector is always available without additional dependencies and can be used for testing object store mode locally.


## Limitations

There are a few things to be aware of when using TidesDB:

The engine does not support foreign keys. Cross-table referential integrity must be enforced at the application level. When a `CREATE TABLE` statement includes `FOREIGN KEY` clauses, the constraint is silently ignored and only the supporting index is created. To convert an InnoDB table that has foreign keys to TidesDB, disable FK checks first:

```sql
SET FOREIGN_KEY_CHECKS = 0;
ALTER TABLE t1 ENGINE = TidesDB;
SET FOREIGN_KEY_CHECKS = 1;
```

Changing the primary key of a table requires a full copy rebuild. The engine does not support inplace primary key changes. Changing a column's type (e.g., `INT` to `BIGINT`) also requires a copy rebuild.

The statistics cache refreshes every two seconds, so immediately after a bulk load, the optimizer may briefly see stale row counts. Running `ANALYZE TABLE` forces an immediate refresh.

Multi-statement transactions at `REPEATABLE_READ` or higher isolation may fail at commit time with `ER_LOCK_DEADLOCK` (ERROR 1213) due to optimistic concurrency control conflicts. Applications using explicit `BEGIN ... COMMIT` blocks should implement retry logic for this error. Autocommit statements are retried automatically by MariaDB. Enabling `tidesdb_pessimistic_locking` eliminates most write-write conflicts by serializing access to hot rows via row locks, at the cost of introducing lock waits and potential deadlocks (also ERROR 1213).

--

## MariaDB Compatibility

| MariaDB Version |  TideSQL Version | Full Support |
|-----------------|--------|--------|
| 10.x.x        | ✗     | ✗     |
| 11.4.10         | >= 3.4.0     | ✔     |
| 11.8.6          | >= 4.0.0    | ✔    |
| 12.2.2          | >= 1.0.0     | ✔     |
| 12.3.1          | >= 4.2.6     | ✔     |

*As versions are tested and confirmed working we update this table. Full Support means the system is tested against all known functionality.*

--

TideSQL repository: <https://github.com/tidesdb/tidesql>

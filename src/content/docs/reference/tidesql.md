---
title: TidesDB Engine for MariaDB Reference
description: TidesDB Storage Engine for MariaDB (TideSQL) Reference
---

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/tidesql.md).

<hr/>

## Overview

TideSQL is a pluggable storage engine for <a href="https://mariadb.org/">MariaDB</a>, built on top of TidesDB.

The engine supports ACID transactions through multi-version concurrency control (MVCC), letting readers proceed without blocking writers. It handles primary keys, secondary indexes, auto-increment columns, virtual and stored generated columns, TTL-based expiration, data-at-rest encryption, online DDL, partitioning, and online backups. All of these features are accessible through standard SQL, so switching from InnoDB to TidesDB for a particular table requires nothing more than changing the `ENGINE` clause.

The TidesDB data files live in a sibling directory next to the MariaDB data directory, named `tidesdb_data`. The engine manages its own file layout entirely, and MariaDB's schema discovery mechanism does not interfere with it. 


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


## Tables and Column Families

Every TidesDB table corresponds to one main column family that holds the row data. Each secondary index gets its own separate column family. The naming convention is rather deterministic, a table `test.events` maps to the column family `test__events`, and a secondary index named `idx_ts` on that table maps to `test__events__idx_idx_ts`.

This separation is meaningful. Because each column family has its own LSM-tree, a secondary index has its own memtable, its own set of SSTables files, and its own compaction and flush schedules. 

When a table is renamed with `RENAME TABLE` or `ALTER TABLE ... RENAME`, the engine renames all associated column families, both the main data CF and every secondary index CF.


## Primary Keys and Row Storage

If you define a `PRIMARY KEY` on a table, TidesDB uses it as the physical ordering key for the data column family. The key bytes are stored in a memcmp-comparable format, integers are encoded big-endian with their sign bit flipped so that negative values sort before positive ones, and strings use their collation's sort key encoding. This means range scans on the primary key are efficient, because physically adjacent keys in the LSM-tree correspond to logically adjacent rows.

If you create a table without an explicit primary key, the engine generates a hidden 8-byte row ID for each row, encoded in big-endian. These hidden IDs are monotonically increasing, assigned from an atomic counter that is recovered on restart by seeking to the last key in the column family.

Inside the column family, every row's key is prefixed with a single namespace byte (`0x01` for data rows, `0x00` for metadata). The value is stored in a packed binary format. A null bitmap is written first, followed by each non-null field serialized using MariaDB's `Field::pack()` method. Fixed-size fields like `INT` and `BIGINT` are stored at their native pack length. `CHAR` fields have trailing spaces stripped. `VARCHAR` fields store only the actual data length rather than padding to the declared maximum. `BLOB` and `TEXT` fields are inlined with a length prefix followed by the data bytes. This packed format is more compact than the raw record buffer and reduces I/O and storage costs, especially for tables with variable-length columns.

```sql
-- With explicit PK (comparable key ordering)
CREATE TABLE users (
  id   INT NOT NULL PRIMARY KEY,
  name VARCHAR(100)
) ENGINE=TIDESDB;

-- Without PK (hidden auto-generated row ID)
CREATE TABLE logs (
  ts      DATETIME,
  message TEXT
) ENGINE=TIDESDB;
```


## Secondary Indexes

Secondary indexes are stored in their own column families, separate from the main data. Each index entry consists of a key that concatenates the comparable-format index column bytes with the comparable-format primary key bytes. The value is empty (a single zero byte). This design means that every secondary index entry is self-contained, given an index key, the engine can extract the primary key from its tail and perform a point lookup into the main data CF to fetch the full row.

When you insert, update, or delete a row, the engine transactionally maintains all secondary indexes within the same transaction. For updates, the old index entry is deleted and the new one is inserted. For deletes, the corresponding index entries are removed.

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


## Auto-Increment

Auto-increment works in a similar way to InnoDB. The engine calls MariaDB's built-in `update_auto_increment()` mechanism during `write_row()`, and the default `get_auto_increment()` handler method uses `index_last` on the primary key to discover the current maximum value. There is no separate metadata key for the auto-increment counter; it is derived from the data at runtime.

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

TidesDB uses MVCC internally. Each statement runs inside a TidesDB transaction that provides MVCC-based isolation at the level configured for the table. The engine maintains a per-connection transaction context through MariaDB's handlerton callback interface, following the same pattern as InnoDB. A transaction object is allocated lazily on the first data access and registered with MariaDB's transaction coordinator. At statement end, dirty transactions are committed and then freed. Read-only transactions are rolled back and reset for reuse, which avoids the overhead of allocating a fresh transaction object for the next read statement.

The engine sets `lock_count()` to zero, which tells MariaDB to bypass its own table-level locking layer entirely. All concurrency control is handled by TidesDB's MVCC, which allows readers and writers to proceed without blocking each other.

The per-table isolation level is configurable at table creation time and defaults to `REPEATABLE_READ`:

```sql
CREATE TABLE ledger (
  id  INT PRIMARY KEY,
  amt DECIMAL(10,2)
) ENGINE=TIDESDB ISOLATION_LEVEL='SERIALIZABLE';
```

The available isolation levels are `READ_UNCOMMITTED`, `READ_COMMITTED`, `REPEATABLE_READ`, `SNAPSHOT`, and `SERIALIZABLE`.


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

### LSM-Tree Tuning

Several options let you tune the shape and behavior of the LSM-tree:

```sql
CREATE TABLE tuned (
  id INT PRIMARY KEY,
  v  VARCHAR(200)
) ENGINE=TIDESDB
  LEVEL_SIZE_RATIO=8
  MIN_LEVELS=3
  SKIP_LIST_MAX_LEVEL=16
  SKIP_LIST_PROBABILITY=25
  L1_FILE_COUNT_TRIGGER=4;
```

`LEVEL_SIZE_RATIO` controls how much larger each level is compared to the previous one (default 10). `MIN_LEVELS` sets the minimum depth of the LSM-tree (default 5). The skip list parameters control the in-memory memtable structure. `L1_FILE_COUNT_TRIGGER` determines how many SSTables can accumulate at Level 1 before compaction merges them into deeper levels.

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


## Online DDL

The engine classifies `ALTER TABLE` operations into three tiers, each with different performance characteristics.

### Instant Operations

These require no engine work at all. MariaDB rewrites the `.frm` metadata file, and the change takes effect immediately:

- Renaming a column or index
- Changing a column's default value
- Changing table-level options (like `SYNC_MODE`)

```sql
ALTER TABLE events ALTER COLUMN data SET DEFAULT 'none', ALGORITHM=INSTANT;
ALTER TABLE events CHANGE kind event_kind VARCHAR(50), ALGORITHM=INSTANT;
ALTER TABLE events SYNC_MODE='NONE', ALGORITHM=INSTANT;
```

### Inplace Operations

Adding or dropping secondary indexes is done inplace. When a new index is added, the engine creates a new column family for it, then performs a full table scan to populate all index entries. This runs with no server-level lock blocking (`HA_ALTER_INPLACE_NO_LOCK`), so concurrent reads and writes can proceed during the index build.

```sql
ALTER TABLE events ADD INDEX idx_ts (ts), ALGORITHM=INPLACE;
ALTER TABLE events DROP INDEX idx_ts, ALGORITHM=INPLACE;

-- Add and drop in a single statement
ALTER TABLE events ADD INDEX idx_kind (event_kind), DROP INDEX idx_ts, ALGORITHM=INPLACE;
```

For large tables, the index population is batched in groups of 10,000 rows per transaction commit, to avoid unbounded memory growth in the transaction's write buffer.

### Copy Operations

Structural changes like adding or dropping columns, changing column types, or altering the primary key require a full table copy:

```sql
ALTER TABLE events ADD COLUMN priority INT DEFAULT 0;
ALTER TABLE events DROP COLUMN priority;
```

The engine explicitly rejects `ALGORITHM=INPLACE` for these operations with a clear error message, so you will never accidentally trigger a slow copy when you expected an instant change.


## ANALYZE TABLE

Running `ANALYZE TABLE` on a TidesDB table produces detailed internal statistics as note-level messages in the result set:

```sql
ANALYZE TABLE products;
```

The output includes the total number of keys, data size, memtable size, number of LSM levels, read amplification factor, cache hit rate, average key and value sizes, and per-level SSTable counts and sizes. For tables with secondary indexes, each index CF's statistics are reported separately.

This information is useful for understanding the physical layout of your data and diagnosing performance characteristics.


## Online Backup

TidesDB supports online backups triggered through a system variable. Setting `tidesdb_backup_dir` to a directory path initiates a consistent backup of the entire TidesDB data directory:

```sql
SET GLOBAL tidesdb_backup_dir = '/path/to/backup';
```

The backup runs without blocking normal read and write operations. The target directory must not already exist or must be empty. After the backup completes, the variable reflects the path of the last successful backup. To clear it:

```sql
SET GLOBAL tidesdb_backup_dir = '';
```


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

All partitioning schemes supported by MariaDB work with TidesDB: `HASH`, `KEY`, `RANGE`, `LIST`, and `RANGE COLUMNS`. Secondary indexes on partitioned tables also work correctly, with each partition maintaining its own index column family.

Partitions can be added and dropped with `ALTER TABLE`:

```sql
ALTER TABLE metrics ADD PARTITION (PARTITION p_2026 VALUES LESS THAN ('2027-01-01'));
ALTER TABLE metrics DROP PARTITION p_2024;  -- removes all data in that range
```


## System Variables

The engine exposes several global system variables that control TidesDB's runtime behavior. These are set at server startup and are read-only (except for `backup_dir` and `debug_trace`):

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_flush_threads` | 2 | Number of background threads flushing memtables to SSTables |
| `tidesdb_compaction_threads` | 2 | Number of background threads performing LSM compaction |
| `tidesdb_log_level` | WARN | TidesDB internal log level (DEBUG, INFO, WARN, ERROR, FATAL, NONE) |
| `tidesdb_block_cache_size` | 256 MB | Size of the global block cache shared across all column families |
| `tidesdb_max_open_sstables` | 256 | Maximum number of SSTable file handles cached in the LRU |
| `tidesdb_backup_dir` | (empty) | Set to a path to trigger an online backup |
| `tidesdb_debug_trace` | OFF | Enables per-operation trace logging to the error log |

The block cache is a read cache that holds decompressed SSTable klog blocks or nodes (if CF is configured with B+tree layout) in memory. A larger cache reduces read amplification for workloads that repeatedly access the same key ranges. The flush and compaction thread counts should be tuned based on the number of available CPU cores and the I/O bandwidth of the storage device.


## How It Stores Data Internally

Understanding the physical layout helps when interpreting `ANALYZE TABLE` output or debugging performance.

Each table's data lives in a column family, which is an independent LSM-tree. Writes go to a skip-list memtable. When the memtable reaches the configured write buffer size, it becomes immutable and is flushed to disk as a sorted SSTable in Level 1. Compaction then merges overlapping SSTables from lower levels into higher levels, maintaining the sorted invariant.

Row keys inside the column family use a namespace prefix byte. Data rows use `0x01`, and the byte `0x00` is reserved for future metadata entries. This prefix ensures that a table scan (which seeks to `0x01`) naturally skips over any non-data keys.

Primary key bytes are encoded in a memcmp-comparable format. For a signed 32-bit integer, the encoding flips the sign bit and stores the result in big-endian byte order. This means that the integer -1 sorts before 0, and 0 sorts before 1, all under a simple byte comparison. The same principle extends to all numeric types and string collations.

Row values are stored in a packed binary format. The null bitmap from MariaDB's record header is written first, then each non-null field is serialized using `Field::pack()`. On read, `Field::unpack()` restores the fields into MariaDB's record buffer. This format is more compact than storing the raw `reclength` bytes, particularly for tables with `VARCHAR` or `CHAR` columns.

Secondary index entries are stored in their own column family. The key format is the concatenation of the comparable index-column bytes and the comparable primary key bytes. The value is a single zero byte (effectively empty); all the information lives in the key. To resolve a secondary index lookup, the engine seeks into the index CF, reads the key, splits off the trailing PK bytes, and performs a point-get into the data CF. When the server indicates that only indexed columns are needed (a covering index scan), the engine can decode integer primary key and index column values directly from the index key bytes, skipping the data CF point-get entirely.

For tables without an explicit primary key, the engine generates a hidden 8-byte big-endian row ID, assigned from an atomic counter. This counter is recovered on table open by seeking to the last key in the column family.


## Statistics and the Optimizer

The engine maintains cached statistics that are refreshed at most every two seconds. These statistics include the total number of keys, total data size, average key and value sizes, and the LSM-tree's read amplification factor. They feed into MariaDB's cost-based optimizer through the `info()`, `scan_time()`, `keyread_time()`, and `records_in_range()` methods.

The cost model accounts for the fact that LSM-tree reads may need to consult multiple levels. A higher read amplification (more levels with overlapping key ranges) increases the cost of point lookups, which nudges the optimizer toward sequential scans when the amplification is high. Conversely, when the data is well-compacted and the read amplification is low, index lookups are cheap.

For `records_in_range()`, the engine returns a rough estimate (one quarter of the cached total row count) rather than performing an expensive exact count. This is a pragmatic tradeoff, the optimizer needs a reasonable estimate to choose between index scan and table scan, but an exact count would require iterating through the range, which defeats the purpose.


## OPTIMIZE TABLE

Running `OPTIMIZE TABLE` triggers compaction on all column families associated with the table, both the main data CF and every secondary index CF. Compaction merges SSTables, removes tombstones from deleted rows, and reduces read amplification. TidesDB enqueues the work to its background compaction threads and the statement returns immediately. After compaction, the cached statistics are invalidated so the optimizer sees the post-compaction state sooner.

```sql
OPTIMIZE TABLE products;
```

This is useful after bulk deletes or updates that leave behind a large number of tombstones, or when `ANALYZE TABLE` reports high read amplification.


## Rename and Drop

Renaming a table renames all associated column families, including secondary index CFs. The engine enumerates all column families whose names start with the old table's prefix and renames each one.

Dropping a table drops the main data CF and then enumerates and drops all index CFs that share the table's naming prefix. The operation is idempotent, if a CF does not exist, the engine simply continues.

```sql
RENAME TABLE events TO event_log;
TRUNCATE TABLE event_log;
DROP TABLE event_log;
```


## Limitations

There are a few things to be aware of when using TidesDB:

The engine does not support foreign keys. Cross-table referential integrity must be enforced at the application level.

Changing the primary key of a table requires a full copy rebuild. The engine does not support inplace primary key changes.

Adding or dropping columns also requires a copy rebuild. Only secondary index operations and metadata changes can be done inplace or instantly.

The statistics cache refreshes every two seconds, so immediately after a bulk load, the optimizer may briefly see stale row counts. Running `ANALYZE TABLE` forces an immediate refresh.

--

TideSQL repository: <https://github.com/tidesdb/tidesql>
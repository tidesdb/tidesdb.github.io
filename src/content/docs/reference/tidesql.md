---
title: TidesDB Engine for MariaDB/MySQL Reference
description: TidesDB Engine for MariaDB/MySQL Reference
---

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/tidesdb.md).

<hr/>

## Overview

TidesDB is a pluggable storage engine designed primarily for <a href="https://mariadb.org/">MariaDB</a>, built on a Log-Structured Merge-tree (LSM-tree) architecture with optional B+tree format for point lookups. It supports ACID transactions and MVCC, and is optimized for write-heavy workloads, delivering reduced write and space amplification.

---

## Quick Start

### Verify Installation



```sql
SHOW ENGINES\G
```

```sql
      Engine: TidesDB
     Support: YES
     Comment: TidesDB LSMB+ storage engine with ACID transactions
Transactions: YES
          XA: YES
  Savepoints: YES
```

### Create a Table

```sql
CREATE TABLE users (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(100),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_name (name)
) ENGINE=TIDESDB;

INSERT INTO users (name, email) VALUES 
  ('Alice', 'alice@example.com'),
  ('Bob', 'bob@example.com'),
  ('Charlie', 'charlie@example.com');

SELECT * FROM users;
```

```
+----+---------+---------------------+---------------------+
| id | name    | email               | created_at          |
+----+---------+---------------------+---------------------+
|  1 | Alice   | alice@example.com   | 2026-01-28 16:39:09 |
|  2 | Bob     | bob@example.com     | 2026-01-28 16:39:09 |
|  3 | Charlie | charlie@example.com | 2026-01-28 16:39:09 |
+----+---------+---------------------+---------------------+
```

### View Table Structure

```sql
SHOW CREATE TABLE users\G
```

```
*************************** 1. row ***************************
       Table: users
Create Table: CREATE TABLE `users` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `email` varchar(100) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_name` (`name`(63))
) ENGINE=TIDESDB DEFAULT CHARSET=utf8mb4
```

---

## Feature Comparison

| Feature | TidesDB | MyRocks | InnoDB |
|---------|:-------:|:-------:|:------:|
| Storage Structure | LSMB+ | LSM-tree | B+tree |
| ACID Transactions | ✓ | ✓ | ✓ |
| MVCC | ✓ | ✓ | ✓ |
| Compression | ✓ (5 algorithms) | ✓ | ✓ |
| Bloom Filters | ✓ | ✓ | — |
| Secondary Indexes | ✓ | ✓ | ✓ |
| FULLTEXT Search | ✓ (inverted index) | — | ✓ |
| Spatial Indexes | ✓ (Z-order) | — | ✓ |
| Isolation Levels | 5 (incl. SSI) | 2 | 4 |
| XA Transactions | ✓ | ✓ | ✓ |
| Savepoints | ✓ | ✓ | ✓ |
| TTL/Expiration | ✓ (per-row + per-table) | ✓ (CF-level) | — |
| Foreign Keys | ✓ | — | ✓ |
| Partitioning | ✓ | ✓ | ✓ |
| Encryption | ✓ | ✓ | ✓ |
| Online DDL | ✓ (indexes) | ✓ | ✓ |
| Per-Table CF Options | ✓ (20 options) | ✓ | — |
| Semi-Consistent Reads | ✓ | — | ✓ |
| Bulk Load Index Disable | ✓ | — | ✓ |
| Sequential Scan Prefetch | ✓ | — | ✓ |
| Write Amplification | Low | Low | High |
| Space Amplification | Low | Medium | High |
| Read Amplification | Medium | Medium | Low |


## 1. Plugin Architecture

### Registration

The plugin registers with MariaDB at server startup:

```c
maria_declare_plugin(tidesdb)
{
  MYSQL_STORAGE_ENGINE_PLUGIN,
  &tidesdb_storage_engine,
  "TidesDB",
  "TidesDB Authors",
  "TidesDB LSMB+ storage engine with ACID transactions",
  PLUGIN_LICENSE_GPL,
  tidesdb_init_func,       /* Plugin Init */
  tidesdb_done_func,       /* Plugin Deinit */
  0x0140,                  /* version: 1.4.0 */
  NULL,                    /* status variables */
  tidesdb_system_variables,/* system variables */
  "1.4.0",                 /* version string */
  MariaDB_PLUGIN_MATURITY_STABLE  /* maturity */
}
maria_declare_plugin_end;
```

### Handlerton

The handlerton connects MariaDB's transaction coordinator to TidesDB:

```c
tidesdb_hton->create = tidesdb_create_handler;
tidesdb_hton->flags = HTON_CLOSE_CURSORS_AT_COMMIT |
                      HTON_SUPPORTS_EXTENDED_KEYS;
tidesdb_hton->commit = tidesdb_commit;
tidesdb_hton->rollback = tidesdb_rollback;
tidesdb_hton->show_status = tidesdb_show_status;

/* Savepoints */
tidesdb_hton->savepoint_offset = sizeof(tidesdb_savepoint_t);
tidesdb_hton->savepoint_set = tidesdb_savepoint_set;
tidesdb_hton->savepoint_rollback = tidesdb_savepoint_rollback;
tidesdb_hton->savepoint_release = tidesdb_savepoint_release;

/* XA (two-phase commit) */
tidesdb_hton->prepare = tidesdb_xa_prepare;
tidesdb_hton->recover = tidesdb_xa_recover;
tidesdb_hton->commit_by_xid = tidesdb_commit_by_xid;
tidesdb_hton->rollback_by_xid = tidesdb_rollback_by_xid;

/* Partitioning */
tidesdb_hton->partition_flags = tidesdb_partition_flags;

/* LSM-tree specific optimizer costs */
tidesdb_hton->update_optimizer_costs = tidesdb_update_optimizer_costs;

/* Consistent snapshot support */
tidesdb_hton->start_consistent_snapshot = tidesdb_start_consistent_snapshot;

/* Per-table CREATE TABLE options (compression, bloom, buffer size, TTL, etc.) */
tidesdb_hton->table_options = tidesdb_table_option_list;
```

---

## 2. Handler Class

The `ha_tidesdb` class extends MySQL's `handler` base class. Each open table gets its own handler instance.

### Key Members

```cpp
class ha_tidesdb: public handler
{
  THR_LOCK_DATA lock;           // MySQL lock
  TIDESDB_SHARE *share;         // Shared lock info and CF handle

  /* Current transaction for this handler */
  tidesdb_txn_t *current_txn;
  bool scan_txn_owned;            /* True if we created the scan transaction */
  bool index_txn_owned;           /* True if we created the index scan transaction */
  bool is_read_only_scan;         /* True if current operation is read-only */

  /* Iterator for table scans */
  tidesdb_iter_t *scan_iter;
  bool scan_initialized;

  /* Buffer for current row's primary key */
  uchar *pk_buffer;
  uint pk_buffer_len;

  /* Buffer for serialized row data */
  uchar *row_buffer;
  uint row_buffer_len;

  /* Current row position (for rnd_pos) -- pre-allocated buffer */
  uchar *current_key;
  size_t current_key_len;
  size_t current_key_capacity;

  /* Bulk insert state */
  bool bulk_insert_active;
  tidesdb_txn_t *bulk_txn;
  ha_rows bulk_insert_rows;
  ha_rows bulk_insert_count;                          /* Rows inserted in current batch */
  static const ha_rows BULK_COMMIT_THRESHOLD = 10000; /* Commit every N rows */

  /* Disable/enable indexes state for bulk load */
  bool indexes_disabled;

  /* Sequential scan prefetch state */
  bool prefetch_active;
  static const uint PREFETCH_BATCH_SIZE = 64;

  /* Performance optimizations */
  bool skip_dup_check;            /* Skip redundant duplicate key check */
  uchar *pack_buffer;             /* Buffer pooling for pack_row() */
  size_t pack_buffer_capacity;
  Item *pushed_idx_cond;          /* Index Condition Pushdown */
  uint pushed_idx_cond_keyno;
  const COND *pushed_cond;        /* Table Condition Pushdown (full WHERE clause) */
  bool keyread_only;              /* Index-only scan mode */
  bool txn_read_only;             /* Track read-only transactions */
  time_t cached_now;              /* Cached time to avoid per-row syscalls */
  uchar *idx_key_buffer;          /* Buffer pooling for build_index_key() */
  size_t idx_key_buffer_capacity;

  /* Semi-consistent read state */
  bool semi_consistent_read_enabled;
  bool did_semi_consistent_read;

  /* Fulltext search state */
  uint ft_current_idx;            /* Current FT index being searched */
  tidesdb_iter_t *ft_iter;        /* Iterator for FT results */
  char **ft_matched_pks;          /* Array of matched primary keys */
  size_t *ft_matched_pk_lens;     /* Lengths of matched PKs */
  uint ft_matched_count;          /* Number of matched PKs */
  uint ft_current_match;          /* Current position in matches */

  /* Secondary index scan state */
  tidesdb_iter_t *index_iter;
  uchar *index_key_buf;
  uint index_key_len;
  uint index_key_buf_capacity;

  /* Buffer for saved old key in update_row */
  uchar *saved_key_buffer;
  size_t saved_key_buffer_capacity;

  /* Buffer pooling for insert_index_entry() PK value */
  uchar *idx_pk_buffer;
  size_t idx_pk_buffer_capacity;

  /* DS-MRR (Disk-Sweep Multi-Range Read) implementation */
  DsMrr_impl m_ds_mrr;
  ...
};
```

### Table Flags

```cpp
ulonglong table_flags() const
{
  return HA_BINLOG_ROW_CAPABLE |
         HA_BINLOG_STMT_CAPABLE |
         HA_REC_NOT_IN_SEQ |        /* Records not in sequential order */
         HA_NULL_IN_KEY |           /* Nulls allowed in keys */
         HA_CAN_INDEX_BLOBS |       /* Can index blob columns */
         HA_CAN_FULLTEXT |          /* Supports FULLTEXT indexes */
         HA_CAN_VIRTUAL_COLUMNS |   /* Supports virtual/generated columns */
         HA_CAN_GEOMETRY |          /* Supports spatial/geometry types */
         HA_PRIMARY_KEY_IN_READ_INDEX |
         HA_PRIMARY_KEY_REQUIRED_FOR_POSITION |
         HA_STATS_RECORDS_IS_EXACT |  /* We can provide exact row counts */
         HA_CAN_SQL_HANDLER |         /* Supports HANDLER interface */
         HA_CAN_EXPORT |              /* Supports transportable tablespaces */
         HA_CAN_ONLINE_BACKUPS |      /* Supports online backup */
         HA_CONCURRENT_OPTIMIZE |     /* OPTIMIZE doesn't block */
         HA_CAN_RTREEKEYS |           /* Supports spatial indexes via Z-order */
         HA_TABLE_SCAN_ON_INDEX |     /* Can scan table via index */
         HA_CAN_REPAIR |              /* Supports REPAIR TABLE (via compaction) */
         HA_CRASH_SAFE |              /* Crash-safe via WAL */
         HA_ONLINE_ANALYZE |          /* No cache eviction after ANALYZE */
         HA_CAN_TABLE_CONDITION_PUSHDOWN | /* WHERE pushdown during scans */
         HA_CAN_SKIP_LOCKED |         /* MVCC: SELECT FOR UPDATE SKIP LOCKED */
         HA_CAN_FULLTEXT_EXT;         /* Extended fulltext API */
}
```

### Index Flags

```cpp
ulong index_flags(uint inx, uint part, bool all_parts) const
{
  ulong flags = HA_READ_NEXT |      /* Can read next in index order */
                HA_READ_PREV |      /* Can read previous in index order */
                HA_READ_ORDER |     /* Returns records in index order */
                HA_READ_RANGE |     /* Can read ranges */
                HA_DO_INDEX_COND_PUSHDOWN; /* Index Condition Pushdown */

  /* Primary key is clustered -- data stored with key */
  if (table_share && inx == table_share->primary_key)
  {
    flags |= HA_CLUSTERED_INDEX;
  }
  else
  {
    /* Secondary indexes support keyread and rowid filter */
    flags |= HA_KEYREAD_ONLY | HA_DO_RANGE_FILTER_PUSHDOWN;
  }
  return flags;
}

/* Primary key is always the clustering key in TidesDB */
bool pk_is_clustering_key(uint index) const { return true; }
```

### Advanced Handler Features

TidesDB implements several advanced handler capabilities:

| Feature | Method | Description |
|---------|--------|-------------|
| Table Condition Pushdown | `cond_push()` / `cond_pop()` | Pushes WHERE clauses to storage engine for early filtering; returns condition to SQL layer for re-check (safe for complex expressions) |
| Index Condition Pushdown | `idx_cond_push()` | Evaluates conditions during index scans before fetching rows |
| DESC LIMIT 1 Optimization | `index_read_last_map()` | Seeks to last row matching key prefix for `ORDER BY ... DESC LIMIT 1` |
| Per-Index Cardinality | `info(HA_STATUS_CONST)` | Sets `rec_per_key` for each index key part (exact for unique, heuristic for non-unique) |
| Online Row Count | `write_row()` / `delete_row()` | Atomically updates `share->row_count` on each DML for live statistics |
| Key Buffer Pre-allocation | `open()` | Pre-allocates key buffers based on max key length to avoid per-row realloc |
| FK Fast Path | `check_foreign_key_constraints_*()` | Skips `ha_thd()` call entirely when table has no FK constraints |
| Consistent Snapshot | `start_consistent_snapshot` | Supports `START TRANSACTION WITH CONSISTENT SNAPSHOT` |
| Cache Preload | `preload_keys()` | `LOAD INDEX INTO CACHE` warms up block cache |
| SKIP LOCKED | `HA_CAN_SKIP_LOCKED` | MVCC never blocks · `SELECT FOR UPDATE SKIP LOCKED` works naturally |
| Clustered Index | `HA_CLUSTERED_INDEX` | Primary key data stored with key (no secondary lookup) |
| Crash Safety | `HA_CRASH_SAFE` | WAL ensures durability across crashes |
| Query Cache | `table_cache_type()` | Returns `HA_CACHE_TBL_TRANSACT` for proper query cache integration |
| Exact Row Count | `records()` | Returns exact row count from `tidesdb_get_stats()` minus metadata keys |
| Truncate | `truncate()` | Instant table truncation via `drop_cf_and_cleanup()` + recreate |
| Custom Errors | `get_error_message()` | Human-readable error messages for TidesDB errors |
| Rowid Filter Pushdown | `rowid_filter_push()` | Accepts rowid filters for semi-join optimization |
| Persistent Statistics | `persist_table_stats()` / `load_table_stats()` | ANALYZE TABLE persists stats to metadata; loaded on table open |
| Compatible Data Check | `check_if_incompatible_data()` | Returns COMPATIBLE_DATA_YES for metadata-only ALTERs to avoid unnecessary rebuilds |
| Semi-Consistent Reads | `was_semi_consistent_read()` / `try_semi_consistent_read()` | Optimistic reads under READ COMMITTED — reads last committed version instead of blocking |
| Disable/Enable Indexes | `disable_indexes()` / `enable_indexes()` | Disable secondary index maintenance during bulk load; rebuild on re-enable |
| Row Estimate Upper Bound | `estimate_rows_upper_bound()` | Returns SSTable metadata total_keys for tighter optimizer estimates |
| Query Cache Integration | `register_query_cache_table()` | Allows query cache when no active transaction |
| Sequential Scan Prefetch | `extra(HA_EXTRA_CACHE)` | Warms block cache by reading keys ahead before sequential scans |
| Per-Table CF Options | `ha_table_option_struct` | 20 CREATE TABLE options for per-table column family configuration |

### Row Count Statistics (`info()`)

The `info(HA_STATUS_VARIABLE)` method reports `stats.records` to the optimizer
and to `SELECT COUNT(*)`. TidesDB uses a two-tier approach:

1. **Tracked count** (`share->row_count_valid == true`) — When `write_row()` and
   `delete_row()` have been called on the table, they atomically maintain
   `share->row_count`. This value is exact and preferred.

2. **Realtime stats** (`share->row_count_valid == false`) — Falls back to
   `tidesdb_get_stats()` which returns `total_keys` from the column family's
   SSTable metadata. Metadata keys (hidden PK counter, auto-increment counter)
   are subtracted to yield the user row count.

In both paths, zero is reported accurately — there is no artificial floor.
This ensures `COUNT(*)` returns 0 after `TRUNCATE TABLE`, `TRUNCATE PARTITION`,
or `DELETE` of all rows.

```cpp
if (share->row_count_valid)
{
    stats.records = share->row_count;  /* Exact tracked count */
}
else
{
    tidesdb_stats_t *tdb_stats = get_realtime_stats(share);
    if (tdb_stats)
    {
        ha_rows metadata_keys = 0;
        if (!share->has_primary_key) metadata_keys++;
        if (table->s->found_next_number_field) metadata_keys++;

        stats.records = tdb_stats->total_keys > metadata_keys
                            ? tdb_stats->total_keys - metadata_keys
                            : 0;
        tidesdb_free_stats(tdb_stats);
    }
}
```

---

## 3. Data Storage Model

### Column Families

Each MySQL table maps to a TidesDB column family:

| MySQL Concept | TidesDB Mapping |
|---------------|-----------------|
| Table | Column Family (CF) |
| Row | Key-Value pair |
| Primary Key | Key |
| Row Data | Serialized Value |
| Secondary Index | Separate CF |
| Fulltext Index | Inverted Index CF |

### TIDESDB_SHARE Structure

Shared metadata for each table:

```c
typedef struct st_tidesdb_share {
  char *table_name;
  uint table_name_length;
  uint use_count;
  pthread_mutex_t mutex;
  THR_LOCK lock;

  /* TidesDB column family for this table (primary data) */
  tidesdb_column_family_t *cf;

  /* Secondary index column families (one per non-primary index) */
  tidesdb_column_family_t *index_cf[TIDESDB_MAX_INDEXES];
  uint num_indexes;

  /* Primary key info */
  bool has_primary_key;
  uint pk_parts;  /* Number of key parts in primary key */

  /* TTL column index (-1 if no TTL column) */
  int ttl_field_index;

  /* Auto-increment tracking */
  ulonglong auto_increment_value;
  pthread_mutex_t auto_inc_mutex;
  bool auto_inc_loaded;  /* Whether auto-increment was loaded from storage */

  /* Row count cache */
  ha_rows row_count;
  bool row_count_valid;

  /* Hidden primary key counter for tables without explicit PK */
  ulonglong hidden_pk_value;
  pthread_mutex_t hidden_pk_mutex;

  /* Fulltext index column families (inverted indexes) */
  tidesdb_column_family_t *ft_cf[TIDESDB_MAX_FT_INDEXES];
  uint ft_key_nr[TIDESDB_MAX_FT_INDEXES];  /* Key number for each FT index */
  uint num_ft_indexes;

  /* Spatial index column families (Z-order encoded) */
  tidesdb_column_family_t *spatial_cf[TIDESDB_MAX_INDEXES];
  uint spatial_key_nr[TIDESDB_MAX_INDEXES];  /* Key number for each spatial index */
  uint num_spatial_indexes;

  /* Foreign key constraints on this table (child FKs) */
  TIDESDB_FK fk[TIDESDB_MAX_FK];
  uint num_fk;

  /* Tables that reference this table (parent FKs) -- for DELETE/UPDATE checks */
  char referencing_tables[TIDESDB_MAX_FK][TIDESDB_TABLE_NAME_MAX_LEN]; /* "db.table" format */
  int referencing_fk_rules[TIDESDB_MAX_FK];                /* delete_rule for each referencing FK */
  uint referencing_fk_cols[TIDESDB_MAX_FK][TIDESDB_FK_MAX_COLS]; /* FK column indices in child */
  uint referencing_fk_col_count[TIDESDB_MAX_FK];           /* Number of FK columns per reference */
  size_t referencing_fk_offsets[TIDESDB_MAX_FK][TIDESDB_FK_MAX_COLS]; /* Byte offset per col */
  size_t referencing_fk_lengths[TIDESDB_MAX_FK][TIDESDB_FK_MAX_COLS]; /* Byte length per col */

  uint num_referencing;

  /* Cached stats from tidesdb_get_stats() to avoid repeated calls */
  tidesdb_stats_t *cached_stats;
  time_t cached_stats_time;  /* When stats were last fetched */

  /* Tablespace state -- for DISCARD/IMPORT TABLESPACE */
  bool tablespace_discarded;
} TIDESDB_SHARE;
```

### Key-Value Format

- Primary Key · Built from MySQL's primary key columns using `key_copy()`
- Hidden PK · For tables without explicit PK, an 8-byte auto-increment value is used
- Row Value · Serialized using `pack_row()` / `unpack_row()` methods

---

## 4. Transaction Management

### Transaction Lifecycle

```
+------------------------------------------------------------------+
|                    MySQL Query Execution                          |
+------------------------------------------------------------------+
|  1. external_lock(F_RDLCK/F_WRLCK)  ->  Begin TidesDB transaction |
|  2. Execute operations (read/write)                               |
|  3. external_lock(F_UNLCK)          ->  Detach handler            |
|  4. tidesdb_commit / tidesdb_rollback called by tx coordinator    |
+------------------------------------------------------------------+
```

### Unified Transaction Path

TidesDB uses a single unified transaction path for both auto-commit and
multi-statement modes. Every statement always gets a THD-level transaction:

```c
int ha_tidesdb::external_lock(THD *thd, int lock_type)
{
  if (lock_type != F_UNLCK)
  {
    /* Always use THD-level transaction */
    tidesdb_txn_t *thd_txn = get_thd_txn(thd, tidesdb_hton);

    if (!thd_txn)
    {
      int isolation = map_isolation_level(
        (enum_tx_isolation)thd->variables.tx_isolation);

      tidesdb_txn_begin_with_isolation(tidesdb_instance,
                                        (tidesdb_isolation_level_t)isolation,
                                        &thd_txn);
      set_thd_txn(thd, tidesdb_hton, thd_txn);
    }

    current_txn = thd_txn;
    txn_read_only = (lock_type == F_RDLCK);

    /* Always register at statement level */
    trans_register_ha(thd, FALSE, tidesdb_hton, 0);

    /* Register at global level only for multi-statement transactions
       (BEGIN...COMMIT or autocommit=0). For single auto-commit statements,
       statement-level registration is sufficient. */
    if (thd_test_options(thd, OPTION_NOT_AUTOCOMMIT | OPTION_BEGIN))
      trans_register_ha(thd, TRUE, tidesdb_hton, 0);
  }
  else
  {
    /* F_UNLCK -- detach handler. Actual commit/rollback happens via
       tidesdb_commit / tidesdb_rollback called by MariaDB's tx coordinator. */
    current_txn = NULL;
  }
}
```

### Isolation Level Mapping

```c
static int map_isolation_level(enum_tx_isolation mysql_iso)
{
  switch (mysql_iso)
  {
    case ISO_READ_UNCOMMITTED:
      return 0;  /* TDB_ISOLATION_READ_UNCOMMITTED */
    case ISO_READ_COMMITTED:
      return 1;  /* TDB_ISOLATION_READ_COMMITTED */
    case ISO_REPEATABLE_READ:
      return 2;  /* TDB_ISOLATION_REPEATABLE_READ */
    case ISO_SERIALIZABLE:
      return 4;  /* TDB_ISOLATION_SERIALIZABLE */
    default:
      return 1;  /* Default to READ_COMMITTED */
  }
}
```

### MVCC and Iterator Visibility

TidesDB iterators and point lookups see the transaction's own uncommitted writes.
The library builds a merge heap from four source types:

| Merge Source | Description |
|-------------|-------------|
| `MERGE_SOURCE_MEMTABLE` | Active memtable |
| `MERGE_SOURCE_SSTABLE` | On-disk SSTables (block-based format) |
| `MERGE_SOURCE_BTREE` | On-disk SSTables (B+tree format) |
| `MERGE_SOURCE_TXN_OPS` | Transaction's write buffer (uncommitted ops) |

Transaction ops use `seq=UINT64_MAX` so they are always visible to the owning
transaction. For `REPEATABLE_READ`, a `snapshot_seq` is captured at transaction
start and only committed data with `seq <= snapshot_seq` is visible from other
transactions.

Point lookups (`tidesdb_txn_get`) check the write buffer first ("read your own
writes"), then fall through to memtable → immutable memtables → SSTables.

---

## 5. Read/Write Paths

### Write Path (`write_row`)

```
+--------------------------------------------------------------+
|  write_row(buf)                                               |
+--------------------------------------------------------------+
|  1. Handle auto_increment if needed                           |
|  2. build_primary_key(buf) -> key                             |
|  3. pack_row(buf) -> value                                    |
|  4. Encrypt value if encryption enabled                       |
|  5. Get transaction (bulk_txn / current_txn / THD txn)        |
|  6. check_foreign_key_constraints_insert()                    |
|  7. Calculate TTL (per-row _ttl field / table option / global) |
|  8. Check for duplicate primary key (unless skip_dup_check)   |
|  9. tidesdb_txn_put(txn, cf, key, value, ttl)                 |
| 10. If !indexes_disabled:                                     |
|     a. Insert secondary index entries                         |
|     b. Insert fulltext index words                            |
|     c. Insert spatial index entries (Z-order encoded)         |
| 11. If own_txn: commit                                        |
|     If bulk_insert: intermediate commit every 10K rows        |
| 12. Update stats.records and share->row_count                 |
+--------------------------------------------------------------+
```

### Read Path (Table Scan)

```
+--------------------------------------------------------------+
|  rnd_init(scan=true)                                          |
+--------------------------------------------------------------+
|  1. Use current_txn (set by external_lock)                    |
|  2. tidesdb_iter_new(txn, cf) -> scan_iter                    |
|  3. tidesdb_iter_seek_to_first(scan_iter)                     |
+--------------------------------------------------------------+

+--------------------------------------------------------------+
|  rnd_next(buf)  [called repeatedly]                           |
+--------------------------------------------------------------+
|  1. tidesdb_iter_key(scan_iter) -> key_ptr                    |
|  2. Skip metadata keys (starting with \0)                     |
|  3. tidesdb_iter_value(scan_iter) -> val_ptr                  |
|  4. Copy key to current_key, copy value to val_copy           |
|     (iterator memory is invalidated by iter_next)             |
|  5. tidesdb_iter_next(scan_iter)  -- advance BEFORE unpack    |
|  6. Decrypt val_copy if encryption enabled                    |
|  7. unpack_row(buf, value)                                    |
|  8. Evaluate pushed_cond (Table Condition Pushdown)           |
+--------------------------------------------------------------+

+--------------------------------------------------------------+
|  rnd_end()                                                    |
+--------------------------------------------------------------+
|  1. tidesdb_iter_free(scan_iter)                              |
+--------------------------------------------------------------+
```

### Index Read Path

```
+--------------------------------------------------------------+
|  index_read_map(buf, key, keypart_map, find_flag)             |
+--------------------------------------------------------------+
|  Primary Key:                                                 |
|    tidesdb_txn_get(txn, cf, key) -> value                     |
|    unpack_row(buf, value)                                     |
|                                                               |
|  Secondary Index:                                             |
|    1. tidesdb_iter_new(txn, index_cf[idx]) -> iter            |
|    2. tidesdb_iter_seek(iter, search_key)                     |
|    3. Evaluate pushed_idx_cond (ICP) on index columns         |
|       -- If condition fails, skip to next index entry         |
|    4. tidesdb_iter_value(iter) -> primary_key                 |
|    5. tidesdb_txn_get(txn, cf, primary_key) -> value          |
|    6. unpack_row(buf, value)                                  |
+--------------------------------------------------------------+
```

### Keyread Limitation (Sort-Key Format)

TidesDB advertises `HA_KEYREAD_ONLY` on secondary indexes so the optimizer
can factor covering-index plans into its cost model. However, secondary index
keys are stored in **sort-key format** (`make_sort_key` weights) rather than
`key_copy` format. Because `key_restore()` cannot decode sort-key weights back
to field values, the actual index scan code always falls through to a PK lookup:

This means every secondary index scan performs the full path:
1. Seek/iterate in the index CF (sort-key → PK mapping)
2. Fetch the row from the main CF via `tidesdb_txn_get(txn, cf, primary_key)`
3. `unpack_row(buf, value)`

The `HA_KEYREAD_ONLY` flag is retained because it still benefits the optimizer's
cost estimates — it indicates that index-only plans *would* be efficient if the
key format were compatible, influencing join order and access path selection.

### Multi-Range Read (DS-MRR)

TidesDB implements the DS-MRR (Disk-Sweep Multi-Range Read) interface for
efficient batch key lookups. This is particularly beneficial for:
- Range scans with multiple ranges
- Batched Key Access (BKA) joins
- Secondary index lookups that need PK fetch

```cpp
/* MRR interface methods */
int multi_range_read_init(RANGE_SEQ_IF *seq, void *seq_init_param,
                          uint n_ranges, uint mode, HANDLER_BUFFER *buf);
int multi_range_read_next(range_id_t *range_info);
ha_rows multi_range_read_info_const(uint keyno, RANGE_SEQ_IF *seq,
                                    void *seq_init_param, uint n_ranges,
                                    uint *bufsz, uint *flags, ha_rows limit,
                                    Cost_estimate *cost);
ha_rows multi_range_read_info(uint keyno, uint n_ranges, uint keys,
                              uint key_parts, uint *bufsz, uint *flags,
                              Cost_estimate *cost);
```

DS-MRR benefits for TidesDB (LSM-tree):
- Sorting keys before lookup improves block cache hit rate
- Batching secondary index → PK lookups reduces transaction overhead
- Key-ordered access is more efficient for LSM merge iterators

### Read-Only Transaction Tracking

TidesDB tracks whether a handler's transaction is read-only via the
`txn_read_only` flag, set in `external_lock()` based on the lock type:

```cpp
/* In external_lock() */
txn_read_only = (lock_type == F_RDLCK);
```

Read-only transactions skip unnecessary commit overhead in `tidesdb_commit()`.
The `rnd_init()` method itself always uses the THD-level transaction set by
`external_lock()` — it does not create its own transaction:

```cpp
int ha_tidesdb::rnd_init(bool scan)
{
    /* current_txn is always set by external_lock before we get here.
       If somehow it's not (e.g. internal scan), fall back to THD txn. */
    if (!current_txn)
    {
        THD *thd = ha_thd();
        current_txn = get_thd_txn(thd, tidesdb_hton);
    }

    ret = tidesdb_iter_new(current_txn, share->cf, &scan_iter);
    tidesdb_iter_seek_to_first(scan_iter);
}
```

### Handler Cloning

TidesDB supports handler cloning for parallel operations:

```cpp
handler *ha_tidesdb::clone(const char *name, MEM_ROOT *mem_root)
{
    /* Use base class clone -- TidesDB handlers share TIDESDB_SHARE */
    handler *new_handler = handler::clone(name, mem_root);
    if (new_handler)
        new_handler->set_optimizer_costs(ha_thd());
    return new_handler;
}
```

Handler cloning enables:
- DS-MRR · Uses two handlers (index scan + rnd_pos)
- Parallel query execution · Multiple handlers for concurrent scans
- WITHOUT OVERLAPS · Unique hash key lookups

---

## 6. Secondary Indexes

Secondary indexes are stored in separate column families:
- Key · `sort_key(index_columns) + primary_key` (ensures uniqueness and correct ordering)
- Value · `primary_key` (for fetching actual row)

Index keys use **sort-key format** via `field->make_sort_key_part()`, not `key_copy` format.
This ensures correct binary comparison ordering for all field types (VARCHAR, DECIMAL, DATE, etc.)
but means `key_restore()` cannot decode the keys back to field values (see Keyread Limitation above).

Null byte polarity differs from `key_copy`:
- `key_copy`: `0x00` = NOT NULL, `0x01` = NULL
- `make_sort_key_part`: `0x00` = NULL (sorts first), `0x01` = NOT NULL

```c
/**
  Insert an entry into a secondary index.
  Stores: sort_key(index_columns) + pk -> primary_key
*/
int ha_tidesdb::insert_index_entry(uint idx, const uchar *buf, tidesdb_txn_t *txn);
```

---

## 7. Fulltext Search

Fulltext indexes use an inverted index pattern:
- Key · `word + '\0' + primary_key`
- Value · (empty or relevance score)

Search process:
1. Tokenize query into words (up to `tidesdb_ft_max_query_words`, default 32)
2. For each word, seek to prefix in FT column family
3. Collect matching primary keys
4. Intersect (AND for boolean mode) or union (OR for natural language) results
5. Compute per-document TF-IDF relevance scores
6. Sort results by relevance descending (most relevant first)
7. Fetch rows by primary key via `ft_read()`

### TF-IDF Relevance Scoring

Each matched document receives a relevance score computed as:

```
score(doc) = Σ IDF(word) for each query word present in doc
IDF(word) = log(1 + N / df)
```

Where `N` = total documents (from cached stats) and `df` = documents containing the word.
Results are sorted by score descending so `ORDER BY MATCH(...) AGAINST(...) DESC` returns
the most relevant documents first without requiring a filesort. Per-document scores are
returned via `ft_find_relevance()` and `ft_get_relevance()` in the `_ft_vft` interface.

### Result Set Operations

Multi-word searches combine results using hash-based set operations for O(n) complexity:

```cpp
/* Hash-based union for O(n) instead of O(n²) */
HASH pk_hash;
my_hash_init(&pk_hash, &my_charset_bin, count1 + count2, ...);

/* Add first set to hash and output */
for (uint i = 0; i < count1; i++) {
    /* Entry format: [4-byte len][pk data] */
    my_hash_insert(&pk_hash, entry);
    output[out_count++] = pk;
}

/* Add second set only if not in hash */
for (uint i = 0; i < count2; i++) {
    if (!my_hash_search(&pk_hash, pks2[i], lens2[i])) {
        output[out_count++] = pk;
    }
}
```

---

## 8. System Variables

The plugin exposes all TidesDB configuration parameters as MySQL system variables.

### Database-Level Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_data_dir` | `{datadir}/tidesdb` | Database directory |
| `tidesdb_flush_threads` | 2 | Number of background flush threads |
| `tidesdb_compaction_threads` | 2 | Number of background compaction threads |
| `tidesdb_block_cache_size` | 256MB | Clock cache size for hot SSTable blocks |
| `tidesdb_max_open_sstables` | 256 | Maximum cached SSTable structures (each uses 2 FDs) |
| `tidesdb_log_level` | info | Log level (debug/info/warn/error/fatal/none) |
| `tidesdb_log_to_file` | FALSE | Log to file instead of stderr |
| `tidesdb_log_truncation_at` | 24MB | Size at which to truncate log file (0 = no truncation) |

### Column Family Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_write_buffer_size` | 64MB | Memtable size before flush |
| `tidesdb_level_size_ratio` | 10 | LSM level size ratio for compaction |
| `tidesdb_min_levels` | 5 | Minimum number of LSM levels |
| `tidesdb_dividing_level_offset` | 2 | Compaction dividing level offset |
| `tidesdb_l1_file_count_trigger` | 4 | L1 file count trigger for compaction |
| `tidesdb_l0_queue_stall_threshold` | 20 | L0 queue stall threshold for backpressure |
| `tidesdb_use_btree` | FALSE | Use B+tree format for column families (faster point lookups) |

### Compression & Bloom Filters

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_enable_compression` | TRUE | Enable compression for SSTables |
| `tidesdb_compression_algo` | LZ4 | Compression algorithm (none/snappy/lz4/zstd/lz4_fast) |
| `tidesdb_enable_bloom_filter` | TRUE | Enable bloom filters for key existence checks |
| `tidesdb_bloom_fpr` | 0.01 | Bloom filter false positive rate (1%) |

### Block Index Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_enable_block_indexes` | TRUE | Enable block indexes for O(log n) seeks |
| `tidesdb_index_sample_ratio` | 1 | Index sample ratio (1 = every key) |
| `tidesdb_block_index_prefix_len` | 16 | Block index prefix length in bytes |

### Skip List (Memtable) Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_skip_list_max_level` | 12 | Maximum skip list level |
| `tidesdb_skip_list_probability` | 0.25 | Skip list level probability |

### Sync & Durability

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_sync_mode` | full | Sync mode (none/interval/full) |
| `tidesdb_sync_interval_us` | 128000 | Sync interval in microseconds (128ms) |

### Value Log (KLog/VLog)

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_klog_value_threshold` | 512 | Values larger than this go to vlog (bytes) |

### Transaction & Isolation

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_default_isolation` | REPEATABLE_READ | Default isolation level |
| `tidesdb_active_txn_buffer_size` | 64KB | Buffer size for SSI conflict detection |

### TTL & Expiration

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_default_ttl` | 0 | Default TTL in seconds (0 = no expiration) |

### Disk Space

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_min_disk_space` | 100MB | Minimum free disk space required |

### Fulltext Search

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_ft_min_word_len` | 4 | Minimum word length for fulltext indexing |
| `tidesdb_ft_max_word_len` | 84 | Maximum word length for fulltext indexing |
| `tidesdb_ft_max_query_words` | 32 | Maximum words in a fulltext search query (1-256) |

### Per-Table Column Family Options

All column family configuration parameters can be overridden per table using
`CREATE TABLE` options. When a value is 0 (or empty string), the global system
variable default is used.

```sql
CREATE TABLE hot_data (
  id INT PRIMARY KEY,
  data VARCHAR(255)
) ENGINE=TidesDB
  COMPRESSION='zstd'
  WRITE_BUFFER_SIZE=134217728
  BLOOM_FILTER=1
  BLOOM_FPR=10
  USE_BTREE=1
  LEVEL_SIZE_RATIO=8
  MIN_LEVELS=3
  SYNC_MODE='full'
  TTL=86400;
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `COMPRESSION` | String | (global) | Compression algorithm: `none`, `snappy`, `lz4`, `zstd`, `lz4_fast` |
| `USE_BTREE` | Bool | 0 | Use B+tree SSTable format (faster point lookups) |
| `WRITE_BUFFER_SIZE` | Number | 0 (global) | Memtable size in bytes |
| `SKIP_LIST_MAX_LEVEL` | Number | 0 (global) | Skip list max level for memtable |
| `SKIP_LIST_PROBABILITY` | Number | 0 (global) | Skip list probability × 10000 (2500 = 0.25) |
| `BLOOM_FILTER` | Bool | 1 | Enable/disable bloom filter |
| `BLOOM_FPR` | Number | 0 (global) | Bloom filter FPR in parts per 10000 (100 = 1%, 10 = 0.1%) |
| `BLOCK_INDEXES` | Bool | 1 | Enable compact block indexes |
| `INDEX_SAMPLE_RATIO` | Number | 0 (global) | Block index sampling ratio |
| `BLOCK_INDEX_PREFIX_LEN` | Number | 0 (global) | Block index prefix length in bytes |
| `LEVEL_SIZE_RATIO` | Number | 0 (global) | LSM level size ratio |
| `MIN_LEVELS` | Number | 0 (global) | Minimum number of LSM levels |
| `DIVIDING_LEVEL_OFFSET` | Number | 0 (global) | Compaction dividing level offset |
| `L1_FILE_COUNT_TRIGGER` | Number | 0 (global) | L1 file count trigger for compaction |
| `L0_QUEUE_STALL_THRESHOLD` | Number | 0 (global) | L0 queue stall threshold for backpressure |
| `SYNC_MODE` | String | (global) | Sync mode: `none`, `interval`, `full` |
| `SYNC_INTERVAL_US` | Number | 0 (global) | Sync interval in microseconds |
| `KLOG_VALUE_THRESHOLD` | Number | 0 (global) | Values larger than this go to vlog |
| `MIN_DISK_SPACE` | Number | 0 (global) | Minimum free disk space in bytes |
| `ISOLATION_LEVEL` | String | (global) | Default isolation: `read_uncommitted`, `read_committed`, `repeatable_read`, `snapshot`, `serializable` |
| `TTL` | Number | 0 | Default TTL in seconds for rows (0 = no expiry) |

Per-table options are applied when the column family is created. The TTL option
is also checked at write time — if no per-row TTL field exists, the per-table
TTL is used before falling back to the global `tidesdb_default_ttl`.

### B+tree Format Option

TidesDB supports an optional B+tree format for column families (disabled by default; block-based is the default klog format).
This provides faster point lookups compared to the standard block-based format:

| Format | Point Lookup | Range Scan | Write |
|--------|-------------|------------|-------|
| B+tree | O(log N) | O(log N + K) | Slightly slower |
| Block-based | O(log B) + O(log E) | O(N) sequential | Faster |

Enable/disable via system variable:
```sql
SET GLOBAL tidesdb_use_btree = ON;  -- Default: OFF (block-based)
```

---

## 9. Optimizer Cost Model

TidesDB provides accurate cost estimates to the MariaDB optimizer based on
LSM-tree architecture characteristics.

### Engine-Level Cost Constants

TidesDB registers LSM-tree specific optimizer costs via `update_optimizer_costs`:

```cpp
static void tidesdb_update_optimizer_costs(OPTIMIZER_COSTS *costs)
{
    /* With bloom filters, point lookups are efficient */
    if (tidesdb_enable_bloom_filter)
    {
        costs->key_lookup_cost = TIDESDB_KEY_LOOKUP_COST_BTREE;  /* 0.0008 */
        costs->row_lookup_cost = TIDESDB_ROW_LOOKUP_COST_BTREE;  /* 0.0010 */
    }
    else
    {
        costs->key_lookup_cost = TIDESDB_KEY_LOOKUP_COST_BLOCK;  /* 0.0020 */
        costs->row_lookup_cost = TIDESDB_ROW_LOOKUP_COST_BLOCK;  /* 0.0025 */
    }

    /* Merge iterator overhead for sequential access */
    costs->key_next_find_cost = TIDESDB_KEY_NEXT_FIND_COST;  /* 0.00012 */
    costs->row_next_find_cost = TIDESDB_ROW_NEXT_FIND_COST;  /* 0.00015 */

    /* Key/row copy costs */
    costs->key_copy_cost = TIDESDB_KEY_COPY_COST;            /* 0.000015 */
    costs->row_copy_cost = TIDESDB_ROW_COPY_COST;            /* 0.000060 */

    /* Disk read characteristics -- 80% block cache hit rate */
    costs->disk_read_cost = TIDESDB_DISK_READ_COST;          /* 0.000875 */
    costs->disk_read_ratio = TIDESDB_DISK_READ_RATIO;        /* 0.20 */

    /* Index block, key comparison, and rowid costs */
    costs->index_block_copy_cost = TIDESDB_INDEX_BLOCK_COPY_COST; /* 0.000030 */
    costs->key_cmp_cost = TIDESDB_KEY_CMP_COST;              /* 0.000011 */
    costs->rowid_cmp_cost = TIDESDB_ROWID_CMP_COST;          /* 0.000006 */
    costs->rowid_copy_cost = TIDESDB_ROWID_COPY_COST;        /* 0.000012 */
}
```

| Cost Variable | TidesDB Value | Notes |
|--------------|---------------|-------|
| `key_lookup_cost` | 0.0008 / 0.0020 | With / without bloom filters |
| `row_lookup_cost` | 0.0010 / 0.0025 | With / without bloom filters |
| `key_next_find_cost` | 0.00012 | Merge iterator overhead |
| `row_next_find_cost` | 0.00015 | Row fetch in merge iterator |
| `disk_read_ratio` | 0.20 | 80% block cache hit rate |
| `key_cmp_cost` | 0.000011 | Per-key comparison |
| `rowid_cmp_cost` | 0.000006 | For MRR / rowid filter |

### scan_time() · Full Table Scan Cost

```cpp
IO_AND_CPU_COST ha_tidesdb::scan_time()
{
    /* Factors considered:
     * 1. Merge iterator overhead: O(log S) per row where S = number of sources
     * 2. Cache effectiveness: hit_rate reduces I/O cost
     * 3. Vlog indirection: large values (>TIDESDB_VLOG_LARGE_VALUE_THRESHOLD) require extra seeks
     * 4. B+tree vs block-based format overhead
     */
    double merge_overhead = TIDESDB_MIN_IO_COST +
        (log2((double)total_sources) * TIDESDB_MERGE_OVERHEAD_FACTOR);
    double cache_factor = TIDESDB_MIN_IO_COST -
        (hit_rate * TIDESDB_CACHE_EFFECTIVENESS_FACTOR);
    double vlog_overhead = (avg_value_size > TIDESDB_VLOG_LARGE_VALUE_THRESHOLD)
        ? TIDESDB_VLOG_OVERHEAD_LARGE : TIDESDB_MIN_IO_COST;
    double format_factor = use_btree ? TIDESDB_BTREE_FORMAT_OVERHEAD : TIDESDB_MIN_IO_COST;

    cost.io = num_blocks * merge_overhead * cache_factor * vlog_overhead * format_factor;
    cost.cpu = total_keys * TIDESDB_CPU_COST_PER_KEY * merge_overhead;
}
```

### read_time() · Index/Point Lookup Cost

```cpp
IO_AND_CPU_COST ha_tidesdb::read_time(uint index, uint ranges, ha_rows rows)
{
    /* Factors considered:
     * 1. Read amplification from LSM levels
     * 2. Bloom filter benefit: FPR eliminates most negative lookups
     * 3. B+tree height for point lookups
     * 4. Secondary index double-lookup overhead (index CF → main CF)
     * 5. Vlog indirection for large values
     */
    double bloom_benefit = enable_bloom_filter ?
        (TIDESDB_BLOOM_BENEFIT_BASE + (fpr * num_levels)) : TIDESDB_MIN_IO_COST;
    double format_factor = use_btree ?
        (TIDESDB_BTREE_HEIGHT_COST_BASE + (btree_height * TIDESDB_BTREE_HEIGHT_COST_PER_LEVEL))
        : TIDESDB_MIN_IO_COST;
    double secondary_idx_factor =
        (index != primary_key) ? TIDESDB_SECONDARY_IDX_FACTOR : TIDESDB_MIN_IO_COST;

    cost.io = (ranges * seek_cost * cache_factor * secondary_idx_factor) +
              (rows * row_fetch_cost * vlog_factor * secondary_idx_factor);
}
```

### records_in_range() · Range Row Estimate

The optimizer calls `records_in_range()` to estimate how many rows fall within
a key range. TidesDB uses a multi-strategy approach:

1. **PK equality** — returns 1 (clustered index, unique)
2. **Unique secondary index equality** — returns 1
3. **Non-unique equality** — heuristic `1/sqrt(N)` selectivity per key part
4. **PK range scans** — **data sampling**: creates a temporary iterator, scans
   up to `TIDESDB_RANGE_SAMPLE_LIMIT` keys in the range, and returns the exact
   count if the range is fully scanned; otherwise extrapolates
5. **Fallback** — heuristic estimate capped at a fraction of total rows

```cpp
/* For PK range scans, sample actual keys */
if (inx == primary_key && min_key && current_txn && share->cf)
{
    tidesdb_iter_t *sample_iter = NULL;
    tidesdb_iter_new(current_txn, share->cf, &sample_iter);
    tidesdb_iter_seek(sample_iter, min_key->key, min_key->length);

    ha_rows sample_count = 0;
    while (tidesdb_iter_valid(sample_iter) &&
           sample_count < TIDESDB_RANGE_SAMPLE_LIMIT)
    {
        /* Stop if we've passed the max key */
        if (max_key && memcmp(iter_key, max_key->key, ...) > 0)
            break;
        sample_count++;
        tidesdb_iter_next(sample_iter);
    }
    tidesdb_iter_free(sample_iter);
}
```

This data-sampling approach gives much better estimates than pure heuristics,
especially for skewed data distributions common in time-series workloads.

---

## 10. XA Transaction Support

TidesDB supports distributed transactions via the XA protocol:

```sql
XA START 'order_123';
INSERT INTO orders VALUES (123, 'pending', 99.99);
XA END 'order_123';
XA PREPARE 'order_123';
XA COMMIT 'order_123';
```

Implementation:
- `tidesdb_xa_prepare()` -- Phase 1 - write transaction to durable storage
- `tidesdb_commit_by_xid()` -- Phase 2 - commit by XID
- `tidesdb_rollback_by_xid()` -- rollback by XID
- `tidesdb_xa_recover()` -- recover prepared transactions after crash

---

## 11. Partitioning

TidesDB supports MariaDB's native partitioning via `ha_partition`. Each partition
maps to a separate TidesDB column family.

### Example · LIST Partitioning

```sql
CREATE TABLE sales (
  id INT,
  region VARCHAR(20),
  amount DECIMAL(10,2),
  PRIMARY KEY (id, region)
) ENGINE=TIDESDB
PARTITION BY LIST COLUMNS (region) (
  PARTITION p_east VALUES IN ('NY', 'NJ'),
  PARTITION p_west VALUES IN ('CA', 'WA')
);

INSERT INTO sales VALUES (1, 'NY', 100.00);
INSERT INTO sales VALUES (2, 'CA', 200.00);
SELECT * FROM sales;
```

```
+----+--------+--------+
| id | region | amount |
+----+--------+--------+
|  1 | NY     | 100.00 |
|  2 | CA     | 200.00 |
+----+--------+--------+
```

Supported partition types:
- RANGE / RANGE COLUMNS
- LIST / LIST COLUMNS
- HASH
- KEY

### Partition Operations

| Operation | How It Works |
|-----------|-------------|
| `DROP PARTITION` | Drops the partition's column family and all its index CFs |
| `TRUNCATE PARTITION` | Calls `truncate()` on the partition handler, which drops and recreates the partition's column family via `drop_cf_and_cleanup()` |
| `REORGANIZE PARTITION` | Rebuilds affected partitions by copying rows into new column families |
| `ADD PARTITION` | Creates a new column family for the new partition |

Each partition is an independent TidesDB column family with its own memtable,
SSTables, and compaction state. Partition pruning allows the optimizer to skip
irrelevant partitions entirely, reading only the column families that match
the query's WHERE clause.

---

## 12. TTL (Time-To-Live)

Rows can expire automatically using a `_ttl` or `TTL` column (case-insensitive).
The value specifies the number of seconds until expiration.

```sql
CREATE TABLE sessions (
  id INT PRIMARY KEY,
  data VARCHAR(100),
  _ttl INT
) ENGINE=TIDESDB;

INSERT INTO sessions VALUES (1, 'session data', 3600);  -- expires in 1 hour
INSERT INTO sessions VALUES (2, 'permanent', 0);        -- never expires
```

```
+----+-------------------------+------+
| id | data                    | _ttl |
+----+-------------------------+------+
|  1 | expires in 3600 seconds | 3600 |
|  2 | permanent               |    0 |
+----+-------------------------+------+
```

TidesDB's background reaper thread removes expired rows during compaction.

---

## 13. Encryption

TidesDB integrates with MariaDB's encryption service for data-at-rest encryption.

### Configuration

```sql
SHOW VARIABLES LIKE 'tidesdb_enable_encryption';
SHOW VARIABLES LIKE 'tidesdb_encryption_key_id';
```

```
+---------------------------+-------+
| Variable_name             | Value |
+---------------------------+-------+
| tidesdb_enable_encryption | OFF   |
| tidesdb_encryption_key_id | 1     |
+---------------------------+-------+
```

To enable encryption, set in `my.cnf`:

```ini
[mariadb]
tidesdb_enable_encryption = ON
tidesdb_encryption_key_id = 1
plugin-load-add = file_key_management
file_key_management_filename = /etc/mysql/keys.txt
```

The encryption uses AES-256-CBC with a random IV per row. Format:
`[4-byte key version][16-byte IV][encrypted payload]`

---

## 14. Foreign Keys

TidesDB stores foreign key definitions in MariaDB's data dictionary and
enforces referential integrity on DML operations.

### Example · CASCADE Delete

```sql
CREATE TABLE parent (
  id INT PRIMARY KEY,
  name VARCHAR(50)
) ENGINE=TIDESDB;

CREATE TABLE child (
  id INT PRIMARY KEY,
  parent_id INT,
  value VARCHAR(50),
  FOREIGN KEY (parent_id) REFERENCES parent(id) ON DELETE CASCADE
) ENGINE=TIDESDB;

SHOW CREATE TABLE child\G
```

```
*************************** 1. row ***************************
       Table: child
Create Table: CREATE TABLE `child` (
  `id` int(11) NOT NULL,
  `parent_id` int(11) DEFAULT NULL,
  `value` varchar(50) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `parent_id` (`parent_id`)
) ENGINE=TIDESDB
```

Supported referential actions:
- `ON DELETE RESTRICT` — block delete if children exist
- `ON DELETE CASCADE` — delete children when parent is deleted
- `ON DELETE SET NULL` — set FK column to NULL when parent is deleted
- `ON UPDATE CASCADE` — update child FK values when parent key is updated
- `ON UPDATE SET NULL` — set FK column to NULL when parent key is updated

### FK Handler Methods

TidesDB implements the full set of FK handler methods:

| Method | Description |
|--------|-------------|
| `get_foreign_key_create_info()` | Returns FK DDL for `SHOW CREATE TABLE` |
| `get_foreign_key_list()` | Returns list of FKs where this table is the child |
| `get_parent_foreign_key_list()` | Returns list of FKs where this table is the parent (referenced) |
| `referenced_by_foreign_key()` | Returns true if other tables reference this table |
| `can_switch_engines()` | Checks if engine switch is allowed given FK constraints |

The `get_parent_foreign_key_list()` method is used by MariaDB during ALTER TABLE
to properly handle self-referencing foreign keys and validate FK constraints
that would be affected by schema changes.

### Self-Referencing FK Example

```sql
CREATE TABLE employees (
  id INT PRIMARY KEY,
  name VARCHAR(50),
  manager_id INT,
  FOREIGN KEY (manager_id) REFERENCES employees(id) ON DELETE SET NULL
) ENGINE=TIDESDB;

INSERT INTO employees VALUES (1, 'CEO', NULL);
INSERT INTO employees VALUES (2, 'VP', 1);
INSERT INTO employees VALUES (3, 'Manager', 2);

-- ALTER TABLE works correctly with self-referencing FKs
ALTER TABLE employees ADD COLUMN department VARCHAR(50);
```

---

## 15. Spatial Indexing

TidesDB supports spatial indexes using Z-order (Morton) curve encoding. This maps
2D coordinates to a 1D key space while preserving locality, enabling efficient
range queries on geometry data.

### Z-Order Encoding

```cpp
/**
  Encode 2D coordinates into Z-order curve value.
  Interleaves bits of x and y coordinates for locality-preserving 1D key.
  
  @param x  Normalized X coordinate (0.0 to 1.0)
  @param y  Normalized Y coordinate (0.0 to 1.0)
  @return   64-bit Z-order encoded value
*/
static uint64_t encode_zorder(double x, double y)
{
    /* Normalize to 32-bit integer range */
    uint32_t ix = (uint32_t)(x * (double)TIDESDB_ZORDER_MAX_VALUE);
    uint32_t iy = (uint32_t)(y * (double)TIDESDB_ZORDER_MAX_VALUE);

    /* Interleave bits using the "magic bits" method */
    uint64_t z = 0;
    for (int i = 0; i < TIDESDB_ZORDER_BITS; i++)
    {
        z |= ((uint64_t)((ix >> i) & 1) << (2 * i));
        z |= ((uint64_t)((iy >> i) & 1) << (2 * i + 1));
    }
    return z;
}
```

### Spatial Index Storage

Spatial indexes are stored in separate column families with Z-order encoded keys:
- Key: `[z-order value][primary key]`
- Value: `primary key`

### Example Usage

```sql
CREATE TABLE locations (
  id INT PRIMARY KEY,
  name VARCHAR(100),
  coords GEOMETRY NOT NULL,
  SPATIAL INDEX idx_coords (coords)
) ENGINE=TIDESDB;

INSERT INTO locations VALUES 
  (1, 'Office', ST_GeomFromText('POINT(40.7128 -74.0060)')),
  (2, 'Home', ST_GeomFromText('POINT(34.0522 -118.2437)'));

SELECT * FROM locations WHERE MBRContains(
  ST_GeomFromText('POLYGON((30 -120, 30 -70, 45 -70, 45 -120, 30 -120))'),
  coords
);
```

### Bounding Box Extraction

For geometry types, TidesDB extracts the bounding box from WKB format:

```cpp
/* WKB format: [1-byte order][4-byte type][coordinates...] */
const uchar *wkb = field->ptr;
uint32_t wkb_type = uint4korr(wkb + 1);

switch (wkb_type)
{
    case 1:  /* Point */
        min_x = max_x = float8get(wkb + 5);
        min_y = max_y = float8get(wkb + 13);
        break;
    case 2:  /* LineString */
    case 3:  /* Polygon */
        /* Iterate through points to find bounding box */
        ...
}
```

---

## 16. Tablespace Import/Export

TidesDB supports transportable tablespaces for backup and migration scenarios,
similar to InnoDB's approach.

### DISCARD TABLESPACE

Prepares a table for data file replacement:

```sql
ALTER TABLE mytable DISCARD TABLESPACE;
```

This operation:
1. Flushes the memtable to ensure all data is on disk
2. Drops the column family (closes handles, releases files)
3. Marks the table as discarded
4. User can now copy/replace the CF directory files

### IMPORT TABLESPACE

Imports data files after DISCARD:

```sql
ALTER TABLE mytable IMPORT TABLESPACE;
```

This operation:
1. Verifies the table was previously discarded
2. Recreates the column family (picks up new files)
3. Clears the discarded flag

### Example Workflow

```bash
# On source server
mysql -e "FLUSH TABLES mytable FOR EXPORT"
cp -r /var/lib/mysql/tidesdb/mytable_cf /backup/
mysql -e "UNLOCK TABLES"

# On target server
mysql -e "ALTER TABLE mytable DISCARD TABLESPACE"
cp -r /backup/mytable_cf /var/lib/mysql/tidesdb/
mysql -e "ALTER TABLE mytable IMPORT TABLESPACE"
```

---

## 17. Native Backup

TidesDB provides native backup functionality using the `tidesdb_backup` API.
This creates a consistent snapshot without blocking normal operations.

### Triggering Backup

```sql
CHECK TABLE mytable FOR UPGRADE;  -- Triggers backup via handler
```

Or programmatically via the `backup()` handler method:

```cpp
int ha_tidesdb::backup(THD *thd, HA_CHECK_OPT *check_opt)
{
    /* Generate backup directory with timestamp */
    char backup_dir[256];
    snprintf(backup_dir, sizeof(backup_dir), 
             "/tmp/tidesdb_backup_%s", timestamp);

    /* Use native TidesDB backup API */
    int ret = tidesdb_backup(tidesdb_instance, backup_dir);
    if (ret != TDB_SUCCESS)
    {
        sql_print_error("TidesDB: Backup failed: %d", ret);
        return HA_ADMIN_FAILED;
    }

    sql_print_information("TidesDB: Backup completed to '%s'", backup_dir);
    return HA_ADMIN_OK;
}
```

### Backup Characteristics

- Non-blocking · Normal reads/writes continue during backup
- Consistent · Point-in-time snapshot of all column families
- Complete · Includes all SSTables, WAL, and metadata
- Restorable · Backup can be opened as a new TidesDB instance

---

## 18. Online DDL

TidesDB supports online ALTER TABLE with three tiers of support:

### Instant Operations (Metadata Only)

| Operation | Algorithm | Lock |
|-----------|-----------|------|
| RENAME COLUMN | INSTANT | NONE |
| RENAME INDEX | INSTANT | NONE |
| RENAME TABLE | INSTANT | NONE |
| CHANGE DEFAULT | INSTANT | NONE |
| ADD/DROP VIRTUAL COLUMN | INSTANT | NONE |
| ADD/DROP CHECK CONSTRAINT | INSTANT | NONE |
| CHANGE INDEX VISIBILITY | INSTANT | NONE |
| CHANGE TABLE OPTIONS | INSTANT | NONE |
| ENABLE/DISABLE KEYS | INSTANT | NONE |

### In-Place Operations (Index Rebuild)

| Operation | Algorithm | Lock |
|-----------|-----------|------|
| ADD INDEX | INPLACE | NONE |
| DROP INDEX | INPLACE | NONE |
| ADD UNIQUE INDEX | INPLACE | NONE |
| ADD/DROP PRIMARY KEY | INPLACE | SHARED |
| ADD/DROP FOREIGN KEY | INPLACE | SHARED |

### Copy Operations (Table Rebuild)

| Operation | Algorithm | Lock |
|-----------|-----------|------|
| ADD COLUMN (stored) | COPY | SHARED |
| DROP COLUMN (stored) | COPY | SHARED |
| CHANGE COLUMN TYPE | COPY | SHARED |
| CHANGE NULLABILITY | COPY | SHARED |
| CONVERT TO CHARSET | COPY | SHARED |
| REORDER COLUMNS | COPY | SHARED |

```sql
-- Online index creation (no blocking)
ALTER TABLE users ADD INDEX idx_email (email), ALGORITHM=INPLACE, LOCK=NONE;

-- Instant index drop
ALTER TABLE users DROP INDEX idx_email;

-- Instant rename
ALTER TABLE users RENAME COLUMN email TO email_address;

-- Column operations require COPY (table rebuild)
ALTER TABLE users ADD COLUMN age INT;
```

> **Note:** Instant ADD COLUMN (like InnoDB's instant DDL) would require row
> versioning metadata in the storage format. TidesDB's LSM-tree row format
> does not currently track schema versions, so stored column changes require
> a table rebuild via the COPY algorithm.

---

## 19. Handler Methods

### Table Lifecycle

| Method | Purpose |
|--------|---------|
| `open()` | Open table, get column family handle |
| `close()` | Release table resources |
| `create()` | Create column family for new table |
| `delete_table()` | Drop column family (rename-then-drop for safety) |
| `rename_table()` | Atomically rename column family (native) |

#### delete_table Implementation

The `delete_table` method uses a rename-then-drop pattern to avoid race conditions
with in-progress flush/compaction operations:

```c
int ha_tidesdb::delete_table(const char *name)
{
  /* Drop secondary index column families (up to TIDESDB_MAX_INDEXES = 64).
     We don't have access to table->s->keys here since the table may not be open,
     so we try the full range. tidesdb_drop_column_family returns
     TDB_ERR_NOT_FOUND for non-existent CFs which is fine. */
  for (uint i = 0; i < TIDESDB_MAX_INDEXES; i++)
  {
    char idx_cf_name[TIDESDB_IDX_CF_NAME_BUF_SIZE];
    snprintf(idx_cf_name, sizeof(idx_cf_name), TIDESDB_CF_IDX_FMT, cf_name, i);
    tidesdb_drop_column_family(tidesdb_instance, idx_cf_name);
  }

  /* Rename main CF first (waits for flush/compaction), then drop.
     This works around a race condition in tidesdb_drop_column_family. */
  char tmp_cf_name[TIDESDB_IDX_CF_NAME_BUF_SIZE];
  snprintf(tmp_cf_name, sizeof(tmp_cf_name), "%s" TIDESDB_CF_DROPPING_SUFFIX,
           cf_name, (unsigned long)time(NULL));

  int ret = tidesdb_rename_column_family(tidesdb_instance, cf_name, tmp_cf_name);
  if (ret == TDB_SUCCESS)
    ret = tidesdb_drop_column_family(tidesdb_instance, tmp_cf_name);
  else if (ret == TDB_ERR_NOT_FOUND)
    ret = TDB_SUCCESS;  /* CF doesn't exist -- that's fine */
  else
    ret = tidesdb_drop_column_family(tidesdb_instance, cf_name);  /* Fallback: direct drop */
  ...
}
```

#### rename_table Implementation

The `rename_table` method uses TidesDB's native `tidesdb_rename_column_family`
which atomically renames the column family and waits for any in-progress
flush or compaction to complete. The implementation includes retry logic for
file system timing issues:

```c
int ha_tidesdb::rename_table(const char *from, const char *to)
{
  /* Rename main column family (no retry -- fail fast) */
  ret = tidesdb_rename_column_family(tidesdb_instance, old_cf_name, new_cf_name);
  if (ret != TDB_SUCCESS)
    DBUG_RETURN(HA_ERR_GENERIC);

  /* Rename secondary index CFs with retry logic for file system timing issues */
  for (uint i = 0; i < TIDESDB_MAX_INDEXES; i++)
  {
    snprintf(old_idx_cf, sizeof(old_idx_cf), TIDESDB_CF_IDX_FMT, old_cf_name, i);
    snprintf(new_idx_cf, sizeof(new_idx_cf), TIDESDB_CF_IDX_FMT, new_cf_name, i);

    /* Only rename CFs that actually exist */
    tidesdb_column_family_t *old_cf = tidesdb_get_column_family(tidesdb_instance, old_idx_cf);
    if (old_cf)
    {
      int rename_ret = tidesdb_rename_column_family(tidesdb_instance, old_idx_cf, new_idx_cf);
      if (rename_ret != TDB_SUCCESS && rename_ret != TDB_ERR_NOT_FOUND)
      {
        /* Retry with delay for file system timing issues */
        for (int retry = 0; retry < TIDESDB_RENAME_RETRY_COUNT && rename_ret != TDB_SUCCESS;
             retry++)
        {
          my_sleep(TIDESDB_RENAME_RETRY_SLEEP_US);
          rename_ret = tidesdb_rename_column_family(tidesdb_instance, old_idx_cf, new_idx_cf);
        }
      }
    }
  }

  /* Also rename fulltext and spatial index CFs */
  ...
}
```

#### truncate / delete_all_rows Implementation

The `truncate()` method delegates to `delete_all_rows()`, which drops and recreates
the column family for an instant reset. This is far faster than iterating and deleting
individual keys, and avoids LSM-tree tombstone accumulation.

A helper function `drop_cf_and_cleanup()` handles the drop and ensures any residual
on-disk directory is removed before the fresh column family is created:

```c
static int drop_cf_and_cleanup(const char *cf_name)
{
  int ret = tidesdb_drop_column_family(tidesdb_instance, cf_name);
  if (ret != TDB_SUCCESS && ret != TDB_ERR_NOT_FOUND)
    return ret;

  /* If the on-disk directory still exists after drop, remove it so
     tidesdb_create_column_family starts with a clean slate. */
  char cf_dir[FN_REFLEN];
  snprintf(cf_dir, sizeof(cf_dir), "%s/tidesdb/%s", mysql_real_data_home, cf_name);

  MY_DIR *dir = my_dir(cf_dir, MYF(0));
  if (dir)
  {
    for (uint i = 0; i < dir->number_of_files; i++)
      my_delete(filepath, MYF(0));
    my_dirend(dir);
    rmdir(cf_dir);
  }
  return 0;
}

int ha_tidesdb::delete_all_rows()
{
  /* Drop and recreate main column family */
  drop_cf_and_cleanup(cf_name);
  tidesdb_create_column_family(tidesdb_instance, cf_name, &cf_config);
  share->cf = tidesdb_get_column_family(tidesdb_instance, cf_name);

  /* Drop and recreate secondary index CFs */
  for (uint i = 0; i < table->s->keys; i++) { ... }

  /* Drop and recreate fulltext index CFs */
  for (uint i = 0; i < share->num_ft_indexes; i++) { ... }

  stats.records = 0;
  share->row_count = 0;
  share->row_count_valid = true;
}
```

This approach is used for both `TRUNCATE TABLE` and `ALTER TABLE ... TRUNCATE PARTITION`.
For partitioned tables, MariaDB's `ha_partition::truncate_partition()` calls `ha_truncate()`
on each affected partition handler, which calls `truncate()` → `delete_all_rows()` on the
partition's column family.

### Row Operations

| Method | Purpose |
|--------|---------|
| `write_row()` | Insert row, update indexes |
| `update_row()` | Update row and indexes |
| `delete_row()` | Delete row and index entries |

### Scans

| Method | Purpose |
|--------|---------|
| `rnd_init()` | Begin table scan |
| `rnd_next()` | Fetch next row |
| `rnd_pos()` | Fetch row by saved position |
| `index_read_map()` | Seek to key in index |
| `index_next()` | Next row in index order |

### Transactions

| Method | Purpose |
|--------|---------|
| `external_lock()` | Begin/end transaction |
| `start_stmt()` | Statement-level savepoint |

### Bulk Insert Optimization

TidesDB optimizes bulk inserts with:
- Single transaction for all rows (avoids per-row commit overhead)
- Skip duplicate key checks during bulk insert
- Intermediate commits every 10,000 rows to avoid transaction log overflow

```cpp
void ha_tidesdb::start_bulk_insert(ha_rows rows, uint flags)
{
    bulk_insert_rows = rows;
    bulk_insert_count = 0;
    skip_dup_check = true;

    /* Use THD transaction if in multi-statement, else create own */
    THD *thd = ha_thd();
    tidesdb_txn_t *thd_txn = get_thd_txn(thd, tidesdb_hton);
    if (thd_txn)
    {
        bulk_txn = thd_txn;
        bulk_insert_active = true;
        return;
    }

    bulk_insert_active = true;
    if (!bulk_txn)
        tidesdb_txn_begin(tidesdb_instance, &bulk_txn);
}

/* In write_row(): intermediate commit every BULK_COMMIT_THRESHOLD rows */
if (bulk_insert_count >= BULK_COMMIT_THRESHOLD)  // 10,000
{
    tidesdb_txn_commit(bulk_txn);
    tidesdb_txn_begin(tidesdb_instance, &bulk_txn);
    bulk_insert_count = 0;
}
```

---

## 20. Configuration Reference

View all TidesDB variables:

```sql
SHOW VARIABLES LIKE 'tidesdb%';
```

```
+--------------------------------------+----------------------------+
| Variable_name                        | Value                      |
+--------------------------------------+----------------------------+
| tidesdb_active_txn_buffer_size       | 65536                      |
| tidesdb_block_cache_size             | 268435456                  |
| tidesdb_block_index_prefix_len       | 16                         |
| tidesdb_bloom_fpr                    | 0.010000                   |
| tidesdb_compaction_threads           | 2                          |
| tidesdb_compression_algo             | lz4                        |
| tidesdb_data_dir                     | /var/lib/mysql/tidesdb     |
| tidesdb_default_isolation            | repeatable_read            |
| tidesdb_default_ttl                  | 0                          |
| tidesdb_dividing_level_offset        | 2                          |
| tidesdb_enable_block_indexes         | ON                         |
| tidesdb_enable_bloom_filter          | ON                         |
| tidesdb_enable_compression           | ON                         |
| tidesdb_enable_encryption            | OFF                        |
| tidesdb_encryption_key_id            | 1                          |
| tidesdb_flush_threads                | 2                          |
| tidesdb_ft_max_query_words           | 32                         |
| tidesdb_ft_max_word_len              | 84                         |
| tidesdb_ft_min_word_len              | 4                          |
| tidesdb_index_sample_ratio           | 1                          |
| tidesdb_klog_value_threshold         | 512                        |
| tidesdb_l0_queue_stall_threshold     | 20                         |
| tidesdb_l1_file_count_trigger        | 4                          |
| tidesdb_level_size_ratio             | 10                         |
| tidesdb_log_level                    | info                       |
| tidesdb_log_to_file                  | OFF                        |
| tidesdb_log_truncation_at            | 25165824                   |
| tidesdb_max_open_sstables            | 256                        |
| tidesdb_min_disk_space               | 104857600                  |
| tidesdb_min_levels                   | 5                          |
| tidesdb_skip_list_max_level          | 12                         |
| tidesdb_skip_list_probability        | 0.250000                   |
| tidesdb_sync_interval_us             | 128000                     |
| tidesdb_sync_mode                    | full                       |
| tidesdb_use_btree                    | OFF                        |
| tidesdb_write_buffer_size            | 67108864                   |
+--------------------------------------+----------------------------+
```

### Key Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_block_cache_size` | 256MB | Clock cache for hot SSTable blocks |
| `tidesdb_write_buffer_size` | 64MB | Memtable size before flush |
| `tidesdb_compression_algo` | lz4 | Compression - none/snappy/lz4/zstd/lz4_fast |
| `tidesdb_sync_mode` | full | Durability - none/interval/full |
| `tidesdb_default_isolation` | repeatable_read | Transaction isolation level |
| `tidesdb_enable_bloom_filter` | ON | Bloom filters for point lookups |
| `tidesdb_enable_encryption` | OFF | Data-at-rest encryption |
| `tidesdb_use_btree` | OFF | B+tree format for faster point lookups |

---

## 21. Engine Status

View TidesDB runtime statistics and configuration:

```sql
SHOW ENGINE TidesDB STATUS\G
```

```
*************************** 1. row ***************************
  Type: TidesDB
  Name: 
Status: 
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
                         TIDESDB ENGINE STATUS
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
BLOCK CACHE
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
| Status                   | ENABLED              |
| State                    | ACTIVE               |
| Entries                  | 0                    |
| Size                     | 0.00              MB |
| Hits                     | 0                    |
| Misses                   | 0                    |
| Hit Rate                 | 0.00               % |
| Partitions               | 32                   |

░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
THREAD POOLS
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
| Flush Threads            | 2                    |
| Compaction Threads       | 2                    |

░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
MEMORY
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
| Block Cache Size         | 256.00            MB |
| Write Buffer Size        | 64.00             MB |

░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
COMPRESSION
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
| Enabled                  | YES                  |
| Algorithm                | lz4                  |

░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
BLOOM FILTER
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
| Enabled                  | YES                  |
| False Positive Rate      | 1.00               % |

░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
DURABILITY
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
| Sync Mode                | full                 |
| Sync Interval            | 128000            us |

░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
TRANSACTIONS
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
| Default Isolation        | repeatable_read      |
| XA Support               | YES                  |
| Savepoints               | YES                  |

░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
LSM TREE
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
| Level Size Ratio         | 10                   |
| Min Levels               | 5                    |
| Skip List Max Level      | 12                   |
| L1 File Count Trigger    | 4                    |
| L0 Stall Threshold       | 20                   |

░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
STORAGE
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
| Open Tables              | 0                    |
| Max Open SSTables        | 256                  |
| Block Indexes            | ENABLED              |

░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
TTL
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
| Default TTL              | 0                 s  |

░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
                      END OF TIDESDB ENGINE STATUS
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
```

---

## 22. Scalability & Lock-Free Operations

TidesDB is designed for high concurrency with minimal lock contention. The plugin
uses atomic operations where possible to match TidesDB's lockless internal architecture.

### Hidden Primary Key Counter

For tables without an explicit primary key, TidesDB generates hidden 8-byte keys.
The counter uses lock-free atomic increment for scalability:

```cpp
/* Lock-free atomic increment for hidden PK */
ulonglong pk_val = my_atomic_add64_explicit(
    (volatile int64 *)&share->hidden_pk_value, 1,
    MY_MEMORY_ORDER_RELAXED) + 1;
```

### Locking Strategy

| Resource | Lock Type | Purpose |
|----------|-----------|---------|
| Hidden PK counter | Atomic | Lock-free increment |
| Auto-increment | Atomic + Batch Persist | Lock-free with periodic persistence |
| Table share hash | RW Lock | Fast read path, write lock only for new shares |
| Row count | Atomic | Lock-free increment/decrement for live `share->row_count` |

#### Auto-Increment Scalability

Auto-increment uses lock-free atomic operations with batch persistence every
`TIDESDB_AUTO_INC_PERSIST_INTERVAL` (1000) values to avoid per-insert disk writes.
The value is lazy-loaded on first use with a double-check pattern:

```cpp
void ha_tidesdb::get_auto_increment(ulonglong offset, ulonglong increment,
                                    ulonglong nb_desired_values, ulonglong *first_value,
                                    ulonglong *nb_reserved_values)
{
    /* Lazy-load from storage on first access (double-check pattern) */
    if (!my_atomic_load32_explicit(&share->auto_inc_loaded, MY_MEMORY_ORDER_ACQUIRE))
    {
        pthread_mutex_lock(&share->auto_inc_mutex);
        if (!share->auto_inc_loaded)
        {
            load_auto_increment_value();
            if (share->auto_increment_value == 0) share->auto_increment_value = 1;
            my_atomic_store32_explicit(&share->auto_inc_loaded, 1, MY_MEMORY_ORDER_RELEASE);
        }
        pthread_mutex_unlock(&share->auto_inc_mutex);
    }

    /* Lock-free atomic reservation */
    ulonglong reserve_amount = nb_desired_values * increment;
    ulonglong old_val = my_atomic_add64_explicit(
        (volatile int64 *)&share->auto_increment_value,
        reserve_amount, MY_MEMORY_ORDER_RELAXED);

    *first_value = old_val;
    *nb_reserved_values = nb_desired_values;

    /* Batch persist every TIDESDB_AUTO_INC_PERSIST_INTERVAL values */
    ulonglong new_val = old_val + reserve_amount;
    if ((new_val / TIDESDB_AUTO_INC_PERSIST_INTERVAL) >
        (old_val / TIDESDB_AUTO_INC_PERSIST_INTERVAL))
    {
        persist_auto_increment_value(new_val);
    }
}
```

#### Table Share Access (RW Lock)

The global table share hash uses a read-write lock for better concurrency:

```cpp
/* Fast path: read lock for existing shares */
mysql_rwlock_rdlock(&tidesdb_rwlock);
share = my_hash_search(&tidesdb_open_tables, table_name, len);
if (share) {
    my_atomic_add32_explicit(&share->use_count, 1, MY_MEMORY_ORDER_RELAXED);
    mysql_rwlock_unlock(&tidesdb_rwlock);
    return share;
}
mysql_rwlock_unlock(&tidesdb_rwlock);

/* Slow path: write lock only when creating new share */
mysql_rwlock_wrlock(&tidesdb_rwlock);
/* Double-check pattern... */
```

#### Buffer Pooling

Handler instances maintain pooled buffers to avoid per-row allocations:

```cpp
/* In ha_tidesdb class */
uchar *idx_pk_buffer;           /* Pooled buffer for PK in insert_index_entry */
size_t idx_pk_buffer_capacity;

/* Realloc only when needed */
if (pk_len > idx_pk_buffer_capacity) {
    idx_pk_buffer = my_realloc(idx_pk_buffer, pk_len * 2);
    idx_pk_buffer_capacity = pk_len * 2;
}
```

TidesDB's internal components are lockless:
- Skip lists (memtables) · Lock-free CAS for updates
- Block manager · Atomic offset allocation
- Clock cache · Lock-free state machines

---

## 23. Transaction Conflict Handling

TidesDB uses optimistic concurrency control (OCC) with MVCC. When concurrent
transactions modify the same rows, conflicts are detected at commit time.

```c
static int tidesdb_commit(THD *thd, bool all)
{
  tidesdb_txn_t *txn = get_thd_txn(thd, tidesdb_hton);
  if (!txn)
    return 0;

  /* Commit when all=true (explicit COMMIT) or when not inside any form
     of transaction (autocommit=1 single statement). For autocommit=0 or
     explicit BEGIN, all=false is a statement-end no-op. */
  bool do_commit = all || !thd_test_options(thd, OPTION_NOT_AUTOCOMMIT | OPTION_BEGIN);

  if (do_commit)
  {
    int ret = tidesdb_txn_commit(txn);
    tidesdb_txn_free(txn);
    set_thd_txn(thd, tidesdb_hton, NULL);

    if (ret != TDB_SUCCESS)
      return map_tidesdb_error(ret);  /* TDB_ERR_CONFLICT -> HA_ERR_LOCK_DEADLOCK */
  }
  return 0;
}
```

When a conflict occurs, `map_tidesdb_error()` translates `TDB_ERR_CONFLICT` to
`HA_ERR_LOCK_DEADLOCK`, which tells MariaDB to retry the transaction. This is
the standard mechanism for handling optimistic concurrency conflicts.


--- 
You can find the source for the TidesDB project [here](https://github.com/tidesdb/tidesdb).

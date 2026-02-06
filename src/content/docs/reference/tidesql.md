---
title: TidesDB Engine for MariaDB/MySQL Reference
description: TidesDB Engine for MariaDB/MySQL Reference
---

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/tidesql.md).

<hr/>

## Overview

TideSQL is a pluggable storage engine designed primarily for <a href="https://mariadb.org/">MariaDB</a>, built on a Log-Structured Merge-tree (LSM-tree) architecture with optional B+tree format for point lookups. It supports ACID transactions and MVCC, and is optimized for write-heavy workloads, delivering reduced write and space amplification.

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

| Feature | TideSQL | MyRocks | InnoDB |
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
  tidesdb_init_func,       /* plugin Init */
  tidesdb_done_func,       /* plugin Deinit */
  0x0130,                 
  NULL,                    /* status variables */
  tidesdb_system_variables,/* system variables */
  "1.3.0",                 /* version string */
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
  size_t current_key_capacity;    /* Pre-allocated capacity */

  /* Bulk insert state */
  bool bulk_insert_active;
  tidesdb_txn_t *bulk_txn;
  ha_rows bulk_insert_rows;

  /* Performance optimizations */
  bool skip_dup_check;            /* Skip redundant duplicate key check */
  uchar *pack_buffer;             /* Buffer pooling for pack_row() */
  size_t pack_buffer_capacity;
  Item *pushed_idx_cond;          /* Index Condition Pushdown */
  uint pushed_idx_cond_keyno;
  bool keyread_only;              /* Index-only scan mode */
  bool txn_read_only;             /* Track read-only transactions */
  uchar *idx_key_buffer;          /* Buffer pooling for build_index_key() */
  size_t idx_key_buffer_capacity;

  /* Secondary index scan state */
  tidesdb_iter_t *index_iter;
  uchar *index_key_buf;
  uint index_key_len;
  uint index_key_buf_capacity;

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
         HA_HAS_RECORDS |             /* records() returns exact count */
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
| Table Condition Pushdown | `cond_push()` / `cond_pop()` | Pushes WHERE clauses to storage engine for filtering during scans |
| Index Condition Pushdown | `idx_cond_push()` | Evaluates conditions during index scans before fetching rows |
| Consistent Snapshot | `start_consistent_snapshot` | Supports `START TRANSACTION WITH CONSISTENT SNAPSHOT` |
| Cache Preload | `preload_keys()` | `LOAD INDEX INTO CACHE` warms up block cache |
| SKIP LOCKED | `HA_CAN_SKIP_LOCKED` | MVCC never blocks · `SELECT FOR UPDATE SKIP LOCKED` works naturally |
| Clustered Index | `HA_CLUSTERED_INDEX` | Primary key data stored with key (no secondary lookup) |
| Crash Safety | `HA_CRASH_SAFE` | WAL ensures durability across crashes |
| Query Cache | `table_cache_type()` | Returns `HA_CACHE_TBL_TRANSACT` for proper query cache integration |
| Exact Row Count | `records()` | Returns exact row count from TidesDB statistics |
| Truncate | `truncate()` | Fast table truncation via column family drop/recreate |
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
  char referencing_tables[TIDESDB_MAX_FK][256];      /* "db.table" format */
  int referencing_fk_rules[TIDESDB_MAX_FK];          /* delete_rule for each referencing FK */
  uint referencing_fk_cols[TIDESDB_MAX_FK][16];      /* FK column indices in child table */
  uint referencing_fk_col_count[TIDESDB_MAX_FK];     /* Number of FK columns per reference */
  size_t referencing_fk_offsets[TIDESDB_MAX_FK][16]; /* Byte offset of each FK col in child row */
  size_t referencing_fk_lengths[TIDESDB_MAX_FK][16]; /* Byte length of each FK column */

  /* Change buffer for secondary index updates */
  struct {
    bool enabled;
    uint pending_count;
    pthread_mutex_t mutex;
  } change_buffer;
  uint num_referencing;

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
|  3. external_lock(F_UNLCK)          ->  Commit/Rollback           |
+------------------------------------------------------------------+
```

### Two Transaction Modes

Auto-commit Mode (single statement):
```c
/* Auto-commit mode -- use handler-level transaction */
if (!current_txn)
{
  int isolation = map_isolation_level(
    (enum_tx_isolation)thd->variables.tx_isolation);

  ret = tidesdb_txn_begin_with_isolation(tidesdb_instance,
                                          (tidesdb_isolation_level_t)isolation,
                                          &current_txn);
}
```

Multi-statement Transaction (BEGIN...COMMIT):
```c
if (in_transaction)
{
  /* Multi-statement transaction -- use THD-level transaction for savepoint support */
  tidesdb_txn_t *thd_txn = get_thd_txn(thd, tidesdb_hton);

  if (!thd_txn)
  {
    /* Start a new transaction at THD level */
    int isolation = map_isolation_level(
      (enum_tx_isolation)thd->variables.tx_isolation);

    ret = tidesdb_txn_begin_with_isolation(tidesdb_instance,
                                            (tidesdb_isolation_level_t)isolation,
                                            &thd_txn);
    set_thd_txn(thd, tidesdb_hton, thd_txn);

    /* Register with MySQL transaction coordinator */
    trans_register_ha(thd, TRUE, tidesdb_hton, 0);
  }

  /* Use THD transaction for this handler */
  current_txn = thd_txn;
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
|  7. Calculate TTL if applicable                               |
|  8. Check for duplicate primary key (unless skip_dup_check)   |
|  9. tidesdb_txn_put(txn, cf, key, value, ttl)                 |
| 10. Insert secondary index entries                            |
| 11. Insert fulltext index words                               |
| 12. Insert spatial index entries (Z-order encoded)            |
| 13. Commit if own_txn                                         |
+--------------------------------------------------------------+
```

### Read Path (Table Scan)

```
+--------------------------------------------------------------+
|  rnd_init(scan=true)                                          |
+--------------------------------------------------------------+
|  1. Get/create transaction (current_txn)                      |
|  2. For read-only scans, use READ_UNCOMMITTED isolation       |
|  3. tidesdb_iter_new(txn, cf) -> scan_iter                    |
|  4. tidesdb_iter_seek_to_first(scan_iter)                     |
+--------------------------------------------------------------+

+--------------------------------------------------------------+
|  rnd_next(buf)  [called repeatedly]                           |
+--------------------------------------------------------------+
|  1. tidesdb_iter_key(scan_iter) -> key                        |
|  2. Skip metadata keys (starting with \0)                     |
|  3. tidesdb_iter_value(scan_iter) -> value                    |
|  4. Save key to current_key (for position())                  |
|  5. Decrypt if encryption enabled                             |
|  6. unpack_row(buf, value)                                    |
|  7. Evaluate pushed_cond (Table Condition Pushdown)           |
|  8. tidesdb_iter_next(scan_iter)                              |
+--------------------------------------------------------------+

+--------------------------------------------------------------+
|  rnd_end()                                                    |
+--------------------------------------------------------------+
|  1. tidesdb_iter_free(scan_iter)                              |
|  2. Cleanup owned transaction if any                          |
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
|    3. tidesdb_iter_value(iter) -> primary_key                 |
|    4. tidesdb_txn_get(txn, cf, primary_key) -> value          |
|    5. unpack_row(buf, value)                                  |
+--------------------------------------------------------------+
```

### Keyread Optimization (Covering Index)

When a query only needs columns that are part of an index, TidesDB can satisfy
the query directly from the index without fetching the full row. This is called
a "covering index" or "keyread" optimization.

```cpp
/* In index_next(), index_read_map(), index_next_same() */
if (keyread_only)
{
    KEY *key_info = &table->key_info[active_index];
    uint idx_restore_len = key_info->key_length;

    /* Clear the record buffer first */
    memset(buf, 0, table->s->reclength);

    /* Restore the index columns using MariaDB's key_restore() */
    key_restore(buf, idx_key, key_info, idx_restore_len);

    /* Also restore the primary key portion (appended after index columns) */
    if (table->s->primary_key != MAX_KEY)
    {
        KEY *pk_info = &table->key_info[table->s->primary_key];
        key_restore(buf, idx_key + idx_restore_len, pk_info, pk_len);
    }

    DBUG_RETURN(0);  /* Skip expensive PK lookup! */
}
```

This optimization significantly improves performance for queries like:
```sql
SELECT id, name FROM users WHERE name = 'Alice';  -- Uses index on (name)
```

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

### Read-Only Scan Optimization

For simple SELECT queries in auto-commit mode, TidesDB uses `READ_UNCOMMITTED`
isolation level to avoid MVCC visibility checks, improving scan performance:

```cpp
/* In rnd_init() */
bool is_read_only = thd &&
    !thd_test_options(thd, OPTION_NOT_AUTOCOMMIT | OPTION_BEGIN) &&
    (lock.type == TL_READ || lock.type == TL_READ_NO_INSERT);

tidesdb_isolation_level_t iso_level =
    is_read_only ? TDB_ISOLATION_READ_UNCOMMITTED
                 : (tidesdb_isolation_level_t)tidesdb_default_isolation;

ret = tidesdb_txn_begin_with_isolation(tidesdb_instance, iso_level, &current_txn);
scan_txn_owned = true;
is_read_only_scan = is_read_only;
```

This optimization applies when:
- Query is in auto-commit mode (not inside BEGIN...COMMIT)
- Lock type is read-only (TL_READ or TL_READ_NO_INSERT)

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
- Key · `index_columns + primary_key` (ensures uniqueness)
- Value · `primary_key` (for fetching actual row)

```c
/**
  Insert an entry into a secondary index.
  Stores: index_key -> primary_key (extracted from row buffer)
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
5. Fetch rows by primary key

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
| `tidesdb_use_btree` | TRUE | Use B+tree format for column families (faster point lookups) |

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
| `tidesdb_default_isolation` | READ_COMMITTED | Default isolation level |
| `tidesdb_active_txn_buffer_size` | 64KB | Buffer size for SSI conflict detection |

### TTL & Expiration

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_default_ttl` | 0 | Default TTL in seconds (0 = no expiration) |

### Change Buffer

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_enable_change_buffer` | TRUE | Enable change buffer for secondary index updates |
| `tidesdb_change_buffer_max_size` | 1024 | Maximum pending entries before flush |

The change buffer batches secondary index updates to reduce random I/O. When enabled,
index modifications are buffered and applied in batches rather than individually.

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
| `USE_BTREE` | Bool | 1 | Use B+tree SSTable format (faster point lookups) |
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

TidesDB supports an optional B+tree format for column families (enabled by default).
This provides faster point lookups compared to the standard block-based format:

| Format | Point Lookup | Range Scan | Write |
|--------|-------------|------------|-------|
| B+tree | O(log N) | O(log N + K) | Slightly slower |
| Block-based | O(log B) + O(log E) | O(N) sequential | Faster |

Enable/disable via system variable:
```sql
SET GLOBAL tidesdb_use_btree = ON;  -- Default: ON
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
        costs->key_lookup_cost = 0.0008;  /* Slightly higher than B-tree */
        costs->row_lookup_cost = 0.0010;
    }
    else
    {
        costs->key_lookup_cost = 0.0020;  /* Higher without bloom filters */
        costs->row_lookup_cost = 0.0025;
    }
    
    /* Merge iterator overhead for sequential access */
    costs->key_next_find_cost = 0.00012;
    costs->row_next_find_cost = 0.00015;
    
    /* 80% cache hit rate assumed */
    costs->disk_read_ratio = 0.20;
}
```

| Cost Variable | TidesDB Value | Notes |
|--------------|---------------|-------|
| `key_lookup_cost` | 0.0008 | With bloom filters |
| `row_lookup_cost` | 0.0010 | Row fetch after key |
| `key_next_find_cost` | 0.00012 | Merge iterator overhead |
| `disk_read_ratio` | 0.20 | 80% block cache hit rate |

### scan_time() · Full Table Scan Cost

```cpp
IO_AND_CPU_COST ha_tidesdb::scan_time()
{
    /* Factors considered:
     * 1. Merge iterator overhead: O(log S) per row where S = number of sources
     * 2. Cache effectiveness: hit_rate reduces I/O cost
     * 3. Vlog indirection: large values (>512 bytes) require extra seeks
     * 4. B+tree vs block-based format overhead
     */
    double merge_overhead = 1.0 + (log2((double)total_sources) * 0.05);
    double cache_factor = 1.0 - (hit_rate * 0.9);
    double vlog_overhead = (avg_value_size > 512) ? 1.3 : 1.0;
    double format_factor = use_btree ? 1.02 : 1.0;

    cost.io = num_blocks * merge_overhead * cache_factor * vlog_overhead * format_factor;
    cost.cpu = total_keys * 0.001 * merge_overhead;
}
```

### read_time() · Index/Point Lookup Cost

```cpp
IO_AND_CPU_COST ha_tidesdb::read_time(uint index, uint ranges, ha_rows rows)
{
    /* Factors considered:
     * 1. Read amplification from LSM levels
     * 2. Bloom filter benefit: 1% FPR eliminates 99% of negative lookups
     * 3. B+tree height for point lookups
     * 4. Secondary index double-lookup overhead (index CF → main CF)
     * 5. Vlog indirection for large values
     */
    double bloom_benefit = enable_bloom_filter ? 
                           (0.3 + (fpr * num_levels)) : 1.0;
    double format_factor = use_btree ? 
                           (0.2 + (btree_height * 0.15)) : 1.0;
    double secondary_idx_factor = (index != primary_key) ? 2.0 : 1.0;

    cost.io = (ranges * seek_cost * cache_factor * secondary_idx_factor) +
              (rows * row_fetch_cost * vlog_factor * secondary_idx_factor);
}
```

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
uint64_t ha_tidesdb::encode_zorder(double x, double y)
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
| ADD/DROP PRIMARY KEY | INPLACE | NONE |
| ADD/DROP FOREIGN KEY | INPLACE | NONE |

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
  /* Drop secondary index column families first */
  for (uint i = 0; i < 16; i++)
  {
    char idx_cf_name[512];
    snprintf(idx_cf_name, sizeof(idx_cf_name), "%s_idx_%u", cf_name, i);
    tidesdb_drop_column_family(tidesdb_instance, idx_cf_name);
  }

  /* Rename main CF first (waits for flush/compaction), then drop */
  char tmp_cf_name[512];
  snprintf(tmp_cf_name, sizeof(tmp_cf_name), "%s__dropping_%lu", cf_name, time(NULL));
  
  int ret = tidesdb_rename_column_family(tidesdb_instance, cf_name, tmp_cf_name);
  if (ret == TDB_SUCCESS)
    ret = tidesdb_drop_column_family(tidesdb_instance, tmp_cf_name);
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
  /* Rename main column family */
  ret = tidesdb_rename_column_family(tidesdb_instance, old_cf_name, new_cf_name);

  /* Retry with delay for file system timing issues */
  if (ret != TDB_SUCCESS && ret != TDB_ERR_NOT_FOUND)
  {
    for (int retry = 0; retry < TIDESDB_RENAME_RETRY_COUNT && ret != TDB_SUCCESS; retry++)
    {
      my_sleep(TIDESDB_RENAME_RETRY_SLEEP_US);
      ret = tidesdb_rename_column_family(tidesdb_instance, old_cf_name, new_cf_name);
    }
  }

  /* Rename secondary index CFs */
  for (uint i = 0; i < TIDESDB_MAX_INDEXES; i++)
  {
    snprintf(old_idx_cf, sizeof(old_idx_cf), "%s_idx_%u", old_cf_name, i);
    snprintf(new_idx_cf, sizeof(new_idx_cf), "%s_idx_%u", new_cf_name, i);
    tidesdb_rename_column_family(tidesdb_instance, old_idx_cf, new_idx_cf);
  }

  /* Also rename fulltext and spatial index CFs */
  ...
}
```

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
    tidesdb_txn_t *thd_txn = get_thd_txn(thd, tidesdb_hton);
    if (thd_txn)
        bulk_txn = thd_txn;
    else
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
+----------------------------------+----------------+
| Variable_name                    | Value          |
+----------------------------------+----------------+
| tidesdb_active_txn_buffer_size   | 65536          |
| tidesdb_block_cache_size         | 268435456      |
| tidesdb_block_index_prefix_len   | 16             |
| tidesdb_bloom_fpr                | 0.010000       |
| tidesdb_change_buffer_max_size   | 1024           |
| tidesdb_compaction_threads       | 2              |
| tidesdb_compression_algo         | lz4            |
| tidesdb_default_isolation        | read_committed |
| tidesdb_default_ttl              | 0              |
| tidesdb_enable_bloom_filter      | ON             |
| tidesdb_enable_change_buffer     | ON             |
| tidesdb_enable_compression       | ON             |
| tidesdb_enable_encryption        | OFF            |
| tidesdb_encryption_key_id        | 1              |
| tidesdb_flush_threads            | 2              |
| tidesdb_ft_max_word_len          | 84             |
| tidesdb_ft_min_word_len          | 4              |
| tidesdb_ft_max_query_words       | 32             |
| tidesdb_klog_value_threshold     | 512            |
| tidesdb_level_size_ratio         | 10             |
| tidesdb_log_level                | info           |
| tidesdb_max_open_sstables        | 256            |
| tidesdb_min_disk_space           | 104857600      |
| tidesdb_min_levels               | 5              |
| tidesdb_skip_list_max_level      | 12             |
| tidesdb_skip_list_probability    | 0.250000       |
| tidesdb_sync_interval_us         | 128000         |
| tidesdb_sync_mode                | full           |
| tidesdb_write_buffer_size        | 67108864       |
+----------------------------------+----------------+
```

### Key Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_block_cache_size` | 256MB | Clock cache for hot SSTable blocks |
| `tidesdb_write_buffer_size` | 64MB | Memtable size before flush |
| `tidesdb_compression_algo` | lz4 | Compression - none/snappy/lz4/zstd |
| `tidesdb_sync_mode` | full | Durability - none/interval/full |
| `tidesdb_default_isolation` | read_committed | Transaction isolation level |
| `tidesdb_enable_bloom_filter` | ON | Bloom filters for point lookups |
| `tidesdb_enable_encryption` | OFF | Data-at-rest encryption |
| `tidesdb_use_btree` | ON | B+tree format for faster point lookups |

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
| Default Isolation        | read_committed       |
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
| Change buffer counter | Atomic | Lock-free increment |

#### Auto-Increment Scalability

Auto-increment uses lock-free atomic operations with batch persistence every 1000 values
to avoid per-insert disk writes:

```cpp
/* Lock-free atomic reservation */
ulonglong reserve_amount = nb_desired_values * increment;
ulonglong old_val = my_atomic_add64_explicit(
    (volatile int64 *)&share->auto_increment_value,
    reserve_amount, MY_MEMORY_ORDER_RELAXED);

*first_value = old_val;
*nb_reserved_values = nb_desired_values;

/* Batch persist every 1000 values to reduce I/O */
ulonglong new_val = old_val + reserve_amount;
if ((new_val / 1000) > (old_val / 1000))
{
    persist_auto_increment_value(new_val);
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

  if (txn && all)
  {
    int ret = tidesdb_txn_commit(txn);
    tidesdb_txn_free(txn);
    set_thd_txn(thd, tidesdb_hton, NULL);

    if (ret == TDB_ERR_CONFLICT)
    {
      /* Transaction conflict -- tell MySQL to retry */
      return HA_ERR_LOCK_DEADLOCK;
    }
    ...
  }
  return 0;
}
```

When a conflict occurs, TidesDB returns `HA_ERR_LOCK_DEADLOCK` which tells
MariaDB to retry the transaction. This is the standard mechanism for handling
optimistic concurrency conflicts.


--- 
You can find the source for the TideSQL project [here](https://github.com/tidesdb/tidesql).

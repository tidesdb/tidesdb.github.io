---
title: TidesDB Engine for MariaDB/MySQL Reference
description: TidesDB Engine for MariaDB/MySQL Reference
---

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/tidesql.md).

<hr/>

## Overview

TideSQL is a pluggable storage engine designed primarily for <a href="https://mariadb.org/">MariaDB</a>, built on a Log-Structured Merge-tree (LSM-tree) architecture. It supports ACID transactions and MVCC, and is optimized for write-heavy workloads, delivering reduced write and space amplification.

---

## Quick Start

### Verify Installation



```sql
SHOW ENGINES\G
```

```sql
      Engine: TidesDB
     Support: YES
     Comment: TidesDB LSM-based storage engine with ACID transactions
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
) ENGINE=TidesDB;

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
) ENGINE=TidesDB DEFAULT CHARSET=utf8mb4
```

---

## Feature Comparison

| Feature | TidesDB | MyRocks | InnoDB |
|---------|:-------:|:-------:|:------:|
| Storage Structure | LSM-tree | LSM-tree | B+tree |
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
| TTL/Expiration | ✓ (per-row) | ✓ (CF-level) | — |
| Foreign Keys | ✓ | — | ✓ |
| Partitioning | ✓ | ✓ | ✓ |
| Encryption | ✓ | ✓ | ✓ |
| Online DDL | ✓ (indexes) | ✓ | ✓ |
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
  "TidesDB LSM-based storage engine with ACID transactions",
  PLUGIN_LICENSE_GPL,
  tidesdb_init_func,       /* Plugin Init */
  tidesdb_done_func,       /* Plugin Deinit */
  0x0704,                  /* version: 7.4+ */
  NULL,                    /* status variables */
  tidesdb_system_variables,/* system variables */
  "7.4.4",                 /* version string */
  MariaDB_PLUGIN_MATURITY_STABLE  /* maturity */
}
maria_declare_plugin_end;
```

### Handlerton

The handlerton connects MariaDB's transaction coordinator to TidesDB:

```c
tidesdb_hton->create = tidesdb_create_handler;
tidesdb_hton->flags = HTON_CLOSE_CURSORS_AT_COMMIT;
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

  /* Current row position (for rnd_pos) - pre-allocated buffer */
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
         HA_CAN_RTREEKEYS |          /* Supports spatial indexes via Z-order */
         HA_TABLE_SCAN_ON_INDEX;     /* Can scan table via index (covering scans) */
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
  char referencing_tables[TIDESDB_MAX_FK][256];      /* "db.table" format */
  int referencing_fk_rules[TIDESDB_MAX_FK];          /* delete_rule for each referencing FK */
  uint referencing_fk_cols[TIDESDB_MAX_FK][16];      /* FK column indices in child table */
  uint referencing_fk_col_count[TIDESDB_MAX_FK];     /* Number of FK columns per reference */
  size_t referencing_fk_offsets[TIDESDB_MAX_FK][16]; /* Byte offset of each FK col in child row */
  size_t referencing_fk_lengths[TIDESDB_MAX_FK][16]; /* Byte length of each FK column */
  uint num_referencing;

  /* Change buffer for secondary index updates */
  struct {
    bool enabled;
    uint pending_count;
    pthread_mutex_t mutex;
  } change_buffer;

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
|  4. Get transaction (bulk_txn / current_txn / THD txn)        |
|  5. check_foreign_key_constraints_insert()                    |
|  6. Calculate TTL if applicable                               |
|  7. tidesdb_txn_put(txn, cf, key, value, ttl)                 |
|  8. Insert secondary index entries                            |
|  9. Insert fulltext index words                               |
| 10. Commit if own_txn                                         |
+--------------------------------------------------------------+
```

### Read Path (Table Scan)

```
+--------------------------------------------------------------+
|  rnd_init(scan=true)                                          |
+--------------------------------------------------------------+
|  1. Get/create transaction (current_txn)                      |
|  2. tidesdb_iter_new(txn, cf) -> scan_iter                    |
|  3. tidesdb_iter_seek_to_first(scan_iter)                     |
+--------------------------------------------------------------+

+--------------------------------------------------------------+
|  rnd_next(buf)  [called repeatedly]                           |
+--------------------------------------------------------------+
|  1. tidesdb_iter_key(scan_iter) -> key                        |
|  2. Skip metadata keys (starting with \0)                     |
|  3. tidesdb_iter_value(scan_iter) -> value                    |
|  4. Save key to current_key (for position())                  |
|  5. unpack_row(buf, value)                                    |
|  6. tidesdb_iter_next(scan_iter)                              |
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
1. Tokenize query into words
2. For each word, seek to prefix in FT column family
3. Collect matching primary keys
4. Intersect (AND) or union (OR) results
5. Fetch rows by primary key

---

## 8. System Variables

The plugin exposes all TidesDB configuration parameters as MySQL system variables.

### Database-Level Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_data_dir` | `{datadir}/tidesdb` | Database directory |
| `tidesdb_flush_threads` | 2 | Number of background flush threads |
| `tidesdb_compaction_threads` | 2 | Number of background compaction threads |
| `tidesdb_block_cache_size` | 64MB | Clock cache size for hot SSTable blocks |
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

### Disk Space

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_min_disk_space` | 100MB | Minimum free disk space required |

### Fulltext Search

| Variable | Default | Description |
|----------|---------|-------------|
| `tidesdb_ft_min_word_len` | 4 | Minimum word length for fulltext indexing |
| `tidesdb_ft_max_word_len` | 84 | Maximum word length for fulltext indexing |

---

## 9. XA Transaction Support

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

## 10. Partitioning

TidesDB supports MariaDB's native partitioning via `ha_partition`. Each partition
maps to a separate TidesDB column family.

### Example · LIST Partitioning

```sql
CREATE TABLE sales (
  id INT,
  region VARCHAR(20),
  amount DECIMAL(10,2),
  PRIMARY KEY (id, region)
) ENGINE=TidesDB
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

## 11. TTL (Time-To-Live)

Rows can expire automatically using a `_ttl` column. The value specifies
the number of seconds until expiration.

```sql
CREATE TABLE sessions (
  id INT PRIMARY KEY,
  data VARCHAR(100),
  _ttl INT
) ENGINE=TidesDB;

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

## 12. Encryption

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

## 13. Foreign Keys

TidesDB stores foreign key definitions in MariaDB's data dictionary and
enforces referential integrity on DML operations.

### Example · CASCADE Delete

```sql
CREATE TABLE parent (
  id INT PRIMARY KEY,
  name VARCHAR(50)
) ENGINE=TidesDB;

CREATE TABLE child (
  id INT PRIMARY KEY,
  parent_id INT,
  value VARCHAR(50),
  FOREIGN KEY (parent_id) REFERENCES parent(id) ON DELETE CASCADE
) ENGINE=TidesDB;

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
) ENGINE=TidesDB
```

Supported referential actions:
- `ON DELETE RESTRICT` — block delete if children exist
- `ON DELETE CASCADE` — delete children when parent is deleted
- `ON DELETE SET NULL` — set FK column to NULL when parent is deleted

---

## 14. Online DDL

TidesDB supports online ALTER TABLE for index operations:

| Operation | Algorithm | Lock |
|-----------|-----------|------|
| ADD INDEX | INPLACE | NONE |
| DROP INDEX | INSTANT | NONE |
| ADD COLUMN | COPY | SHARED |
| DROP COLUMN | COPY | SHARED |
| RENAME INDEX | INSTANT | NONE |

```sql
-- Online index creation (no blocking)
ALTER TABLE users ADD INDEX idx_email (email), ALGORITHM=INPLACE, LOCK=NONE;

-- Instant index drop
ALTER TABLE users DROP INDEX idx_email;
```

---

## 15. Handler Methods

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
flush or compaction to complete:

```c
int ha_tidesdb::rename_table(const char *from, const char *to)
{
  /* Rename main column family */
  ret = tidesdb_rename_column_family(tidesdb_instance, old_cf_name, new_cf_name);

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

---

## 16. Configuration Reference

View all TidesDB variables:

```sql
SHOW VARIABLES LIKE 'tidesdb%';
```

```
+----------------------------------+----------------+
| Variable_name                    | Value          |
+----------------------------------+----------------+
| tidesdb_active_txn_buffer_size   | 65536          |
| tidesdb_block_cache_size         | 67108864       |
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
| `tidesdb_block_cache_size` | 64MB | Clock cache for hot SSTable blocks |
| `tidesdb_write_buffer_size` | 64MB | Memtable size before flush |
| `tidesdb_compression_algo` | lz4 | Compression - none/snappy/lz4/zstd |
| `tidesdb_sync_mode` | full | Durability - none/interval/full |
| `tidesdb_default_isolation` | read_committed | Transaction isolation level |
| `tidesdb_enable_bloom_filter` | ON | Bloom filters for point lookups |
| `tidesdb_enable_encryption` | OFF | Data-at-rest encryption |

---

## 17. Engine Status

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
| Block Cache Size         | 64.00             MB |
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

## 18. Transaction Conflict Handling

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
      /* Transaction conflict - tell MySQL to retry */
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

## 19. Performance Benchmarks

Sysbench OLTP benchmarks comparing TidesDB and InnoDB (100K rows, 4 threads, 60s):

| Test | Engine | TPS | QPS | Latency avg | Latency p95 | Latency max |
|------|--------|-----|-----|-------------|-------------|-------------|
| Read-Only | InnoDB | 282,680 | 4,522,880 | 0.85ms | 1.12ms | 11.24ms |
| Read-Only | TidesDB | 107,993 | 1,727,888 | 2.22ms | 2.61ms | 5.74ms |
| Write-Only | InnoDB | 135,262 | 811,572 | 1.77ms | 2.03ms | 354.40ms |
| Write-Only | **TidesDB** | **156,839** | **941,034** | **1.53ms** | **1.70ms** | **23.92ms** |
| Read-Write | InnoDB | 105,780 | 2,115,600 | 2.27ms | 2.30ms | 109.78ms |
| Read-Write | TidesDB | 57,417 | 1,149,328 | 4.18ms | 5.09ms | 43.99ms |

---

For write-heavy workloads with high insert rates, TidesDB offers better
performance than B-tree engines while maintaining mostly full SQL compatibility.

--- 
You can find the source for the TideSQL project [here](https://github.com/tidesdb/tidesql).

For detailed benchmarks against InnoDB, see [here](/articles/tidesdb-vs-innodb-within-mariadb).

---
title: TidesDB C API Reference
description: Complete C API reference for TidesDB
---

## Overview

TidesDB uses a simple API. All functions return `0` on success and a negative error code on failure.

## Include

```c
#include <tidesdb/tidesdb.h>
```

:::note
You can use other components of TidesDB such as skip list, bloom filter etc. under `tidesdb/` - this also prevents collisions.
:::

## Error Codes

TidesDB provides detailed error codes for production use.

| Code | Value | Description |
|------|-------|-------------|
| `TDB_SUCCESS` | `0` | Operation completed successfully |
| `TDB_ERROR` | `-1` | Generic error or operation failed |
| `TDB_ERR_MEMORY` | `-2` | Memory allocation failed |
| `TDB_ERR_INVALID_ARGS` | `-3` | Invalid arguments passed to function (NULL pointers, invalid sizes, etc.) |
| `TDB_ERR_IO` | `-4` | I/O operation failed (file read/write error) |
| `TDB_ERR_NOT_FOUND` | `-5` | Key not found in column family |
| `TDB_ERR_EXISTS` | `-6` | Resource already exists (e.g., column family name collision) |
| `TDB_ERR_CORRUPT` | `-7` | Data corruption detected (checksum failure, invalid format version, truncated data) |
| `TDB_ERR_LOCK` | `-8` | Lock acquisition failed |
| `TDB_ERR_TXN_COMMITTED` | `-9` | Transaction already committed, cannot perform operation |
| `TDB_ERR_TXN_ABORTED` | `-10` | Transaction already aborted/rolled back, cannot perform operation |
| `TDB_ERR_READONLY` | `-11` | Operation not allowed on read-only transaction |
| `TDB_ERR_INVALID_NAME` | `-12` | Invalid name provided (empty, too long, or contains invalid characters) |
| `TDB_ERR_COMPARATOR_NOT_FOUND` | `-13` | Specified comparator function not registered |
| `TDB_ERR_MAX_COMPARATORS` | `-14` | Maximum number of comparators reached |
| `TDB_ERR_INVALID_CF` | `-15` | Invalid or non-existent column family |
| `TDB_ERR_THREAD` | `-16` | Thread operation failed (mutex, semaphore, or thread creation error) |
| `TDB_ERR_CHECKSUM` | `-17` | Checksum verification failed during WAL replay or data validation |
| `TDB_ERR_MEMORY_LIMIT` | `-18` | Key or value size exceeds system memory limits (safety check to prevent OOM) |

- `TDB_ERR_CORRUPT`, `TDB_ERR_CHECKSUM` indicate data integrity issues requiring immediate attention
- `TDB_ERR_TXN_COMMITTED`, `TDB_ERR_TXN_ABORTED`, `TDB_ERR_READONLY` indicate transaction state violations
- `TDB_ERR_MEMORY`, `TDB_ERR_MEMORY_LIMIT`, `TDB_ERR_IO` indicate system resource constraints
- `TDB_ERR_NOT_FOUND`, `TDB_ERR_EXISTS` are normal operational conditions, not failures

### Example Error Handling

```c
int result = tidesdb_txn_put(txn, key, key_size, value, value_size, -1);
if (result != TDB_SUCCESS)
{
    switch (result)
    {
        case TDB_ERR_MEMORY:
            fprintf(stderr, "out of memory\n");
            break;
        case TDB_ERR_INVALID_ARGS:
            fprintf(stderr, "invalid arguments\n");
            break;
        case TDB_ERR_READONLY:
            fprintf(stderr, "cannot write to read-only transaction\n");
            break;
        default:
            fprintf(stderr, "operation failed with error code: %d\n", result);
            break;
    }
    return -1;
}
```

## Storage Engine Operations

### Opening TidesDB

```c
tidesdb_config_t config = {
    .db_path = "./mydb",
    .enable_debug_logging = 0,         /* Optional enable debug logging */
    .num_flush_threads = 2,            /* Optional flush thread pool size (default is 2) */
    .num_compaction_threads = 2,       /* Optional compaction thread pool size (default is 2) */
    .wait_for_wal_recovery = 0,        /* Optional wait for WAL recovery flushes (default: 0 = fast startup) */
    .wal_recovery_poll_interval_ms = 100  /* Optional polling interval for WAL recovery (default: 100ms) */
};

tidesdb_t *db = NULL;
if (tidesdb_open(&config, &db) != 0)
{
    return -1;
}

if (tidesdb_close(db) != 0)
{
    return -1;
}
```

### Debug Logging

TidesDB provides runtime debug logging that can be enabled/disabled dynamically.

**Enable at startup**
```c
tidesdb_config_t config = {
    .db_path = "./mydb",
    .enable_debug_logging = 1  
};

tidesdb_t *db = NULL;
tidesdb_open(&config, &db);
```

**Enable/disable at runtime**
```c
extern int _tidesdb_debug_enabled;  /* Global debug flag */

/* Enable debug logging */
_tidesdb_debug_enabled = 1;

/* Your operations here -- debug logs will be written to stderr */

/* Disable debug logging */
_tidesdb_debug_enabled = 0;
```

**Output**
Debug logs are written to **stderr** with the format
```
[TidesDB DEBUG] filename:line: message
```

**Redirect to file**
```bash
./your_program 2> tidesdb_debug.log  # Redirect stderr to file
```

## Column Family Operations

### Creating a Column Family

Column families are isolated key-value stores. Use the config struct for customization or use defaults.

```c
/* Create with default configuration */
tidesdb_column_family_config_t cf_config = tidesdb_default_column_family_config();

if (tidesdb_create_column_family(db, "my_cf", &cf_config) != 0)
{
    return -1;
}
```

**Custom configuration example**
```c
tidesdb_column_family_config_t cf_config = {
    .memtable_flush_size = 128 * 1024 * 1024,   /* 128MB */
    .max_sstables_before_compaction = 128,      /* trigger compaction at 128 SSTables (min 2 required) */
    .compaction_threads = 4,                    /* use 4 threads for parallel compaction (0 = single-threaded) */
    .sl_max_level = 12,                         /* skip list max level */
    .sl_probability = 0.25f,                    /* skip list probability */
    .enable_compression = 1,                    /* enable compression */
    .compression_algorithm = COMPRESS_LZ4,      /* use LZ4 */
    .enable_bloom_filter = 1,                   /* enable bloom filters */
    .bloom_filter_fp_rate = 0.01,               /* 1% false positive rate */
    .enable_background_compaction = 1,          /* enable background compaction */
    .background_compaction_interval = 1000000,  /* check every 1000000 microseconds (1 second) */
    .enable_block_indexes = 1,                  /* enable succinct trie block indexes */
    .sync_mode = TDB_SYNC_FULL,                 /* fsync on every write (most durable) */
    .comparator_name = {0},                     /* empty = use default "memcmp" */
    .block_manager_cache_size = 32 * 1024 * 1024  /* 32MB LRU block cache for column family block managers */
};

if (tidesdb_create_column_family(db, "my_cf", &cf_config) != 0)
{
    return -1;
}
```

**Using custom comparator**
```c
tidesdb_register_comparator("reverse", my_reverse_compare);

tidesdb_column_family_config_t cf_config = tidesdb_default_column_family_config();
strncpy(cf_config.comparator_name, "reverse", TDB_MAX_COMPARATOR_NAME - 1);  
cf_config.comparator_name[TDB_MAX_COMPARATOR_NAME - 1] = '\0';

if (tidesdb_create_column_family(db, "sorted_cf", &cf_config) != 0)
{
    return -1;
}
```

### Dropping a Column Family

```c
if (tidesdb_drop_column_family(db, "my_cf") != 0)
{
    return -1;
}
```

### Getting a Column Family

Retrieve a column family pointer to use in operations.

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (cf == NULL)
{
    /* Column family not found */
    return -1;
}
```

### Listing Column Families

Get all column family names in the storage engine instance.

```c
char **names = NULL;
int count = 0;

if (tidesdb_list_column_families(db, &names, &count) == 0)
{
    printf("Found %d column families:\n", count);
    for (int i = 0; i < count; i++)
    {
        printf("  - %s\n", names[i]);
        free(names[i]);
    }
    free(names);
}
```

### Column Family Statistics

Get detailed statistics about a column family.

```c
tidesdb_column_family_stat_t *stats = NULL;

if (tidesdb_get_column_family_stats(db, "my_cf", &stats) == 0)
{
    printf("Column Family: %s\n", stats->name);
    printf("Comparator: %s\n", stats->comparator_name);
    printf("SSTables: %d\n", stats->num_sstables);
    printf("Total SSTable Size: %zu bytes\n", stats->total_sstable_size);
    printf("Memtable Size: %zu bytes\n", stats->memtable_size);
    printf("Memtable Entries: %d\n", stats->memtable_entries);
    printf("Compression: %s\n", stats->config.enable_compression ? "enabled" : "disabled");
    printf("Bloom Filter FP Rate: %.4f\n", stats->config.bloom_filter_fp_rate);
    
    free(stats);
}
```

**Statistics include**
- Column family name and comparator
- Number of SSTables and total size
- Memtable size and entry count
- Full configuration (compression, bloom filters, sync mode, etc.)

### Updating Column Family Configuration

Update runtime-safe configuration settings without affecting existing data.

```c
tidesdb_column_family_update_config_t update_config = {
    .memtable_flush_size = 128 * 1024 * 1024,     /* increase to 128MB */
    .max_sstables_before_compaction = 256,        /* trigger at 256 SSTables */
    .compaction_threads = 8,                      /* use 8 threads */
    .sl_max_level = 16,                           /* for new memtables */
    .sl_probability = 0.25f,                      /* for new memtables */
    .enable_bloom_filter = 1,                     /* enable bloom filters */
    .bloom_filter_fp_rate = 0.001,                /* 0.1% FP rate for new SSTables */
    .enable_background_compaction = 1,            /* enable background compaction */
    .background_compaction_interval = 500000,     /* check every 500ms */
    .block_manager_cache_size = 32 * 1024 * 1024  /* 32MB block cache */
    .sync_mode = TDB_SYNC_FULL,                   /* fsync on every write (most durable) */
};

if (tidesdb_update_column_family_config(db, "my_cf", &update_config) == 0)
{
    printf("Configuration updated successfully\n");
}
```

**Updatable settings** (safe to change at runtime)
- `memtable_flush_size` - Affects when new flushes trigger
- `max_sstables_before_compaction` - Affects compaction trigger threshold
- `compaction_threads` - Number of parallel compaction threads
- `sl_max_level` - Skip list level for **new** memtables only
- `sl_probability` - Skip list probability for **new** memtables only
- `enable_bloom_filter` - Enable/disable bloom filters for **new** SSTables
- `bloom_filter_fp_rate` - False positive rate for **new** SSTables only
- `enable_background_compaction` - Enable/disable background compaction
- `background_compaction_interval` - Compaction check interval (microseconds)
- `block_manager_cache_size` - LRU block cache size in bytes

**Non-updatable settings** · (would corrupt existing data)
- `enable_compression` - Cannot change compression on existing SSTables
- `compression_algorithm` - Cannot change algorithm on existing SSTables
- `enable_block_indexes` - Cannot change index structure on existing SSTables
- `enable_bloom_filter` - Cannot change bloom filter on existing SSTables
- `max_open_file_handles` - Cannot change file handle cache size
- `sync_mode` - Cannot change durability mode on existing WALs
- `comparator_name` - Cannot change sort order on existing data

**Configuration persistence**
```
mydb/
├── my_cf/
│   ├── config.cfc    
│   ├── wal_0.log
│   ├── sstable_0.sst
│   └── sstable_1.sst
```

On column family creation, the initial config is saved to `config.cfc`. On storage engine restart, the config is loaded from `config.cfc` (if it exists). On config update, changes are immediately saved to `config.cfc`. If the save fails, it returns a `TDB_ERR_IO` error code.

:::tip[Important Notes]
Changes apply immediately to new operations, while existing SSTables and memtables retain their original settings. New memtables use the updated `max_level` and `probability`, and new SSTables use the updated `bloom_filter_fp_rate`. The update operation is thread-safe, using a write lock during the update, and configuration persists across storage engine restarts.
:::

## Transactions

All operations in TidesDB are done through transactions for ACID guarantees per column family.

### Basic Transaction

```c
/* Get column family pointer first */
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_txn_t *txn = NULL;
if (tidesdb_txn_begin(db, cf, &txn) != 0)
{
    return -1;
}

const uint8_t *key = (uint8_t *)"mykey";
const uint8_t *value = (uint8_t *)"myvalue";

if (tidesdb_txn_put(txn, key, 5, value, 7, -1) != 0)
{
    tidesdb_txn_free(txn);
    return -1;
}

if (tidesdb_txn_commit(txn) != 0)
{
    tidesdb_txn_free(txn);
    return -1;
}

tidesdb_txn_free(txn);
```

### With TTL (Time-to-Live)

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin(db, cf, &txn);

const uint8_t *key = (uint8_t *)"temp_key";
const uint8_t *value = (uint8_t *)"temp_value";

/* TTL is Unix timestamp (seconds since epoch) -- absolute expiration time */
time_t ttl = time(NULL) + 60;  /* Expires 60 seconds from now */

/* Use -1 for no expiration */
tidesdb_txn_put(txn, key, 8, value, 10, ttl);
tidesdb_txn_commit(txn);
tidesdb_txn_free(txn);
```

:::tip[TTL Examples]
```c
/* No expiration */
time_t ttl = -1;

/* Expire in 5 minutes */
time_t ttl = time(NULL) + (5 * 60);

/* Expire in 1 hour */
time_t ttl = time(NULL) + (60 * 60);

/* Expire at specific time (e.g., midnight) */
time_t ttl = 1730592000;  /* Specific Unix timestamp */
```
:::

### Getting a Key-Value Pair

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin_read(db, cf, &txn);  /* Read-only transaction */

const uint8_t *key = (uint8_t *)"mykey";
uint8_t *value = NULL;
size_t value_size = 0;

if (tidesdb_txn_get(txn, key, 5, &value, &value_size) == 0)
{
    /* Use value */
    printf("Value: %.*s\n", (int)value_size, value);
    free(value);
}

tidesdb_txn_free(txn);
```

### Deleting a Key-Value Pair

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin(db, cf, &txn);

const uint8_t *key = (uint8_t *)"mykey";
tidesdb_txn_delete(txn, key, 5);

tidesdb_txn_commit(txn);
tidesdb_txn_free(txn);
```

### Multi-Operation Transaction

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin(db, cf, &txn);

/* Multiple operations in one transaction */
tidesdb_txn_put(txn, (uint8_t *)"key1", 4, (uint8_t *)"value1", 6, -1);
tidesdb_txn_put(txn, (uint8_t *)"key2", 4, (uint8_t *)"value2", 6, -1);
tidesdb_txn_delete(txn, (uint8_t *)"old_key", 7);

/* Commit atomically -- all or nothing */
if (tidesdb_txn_commit(txn) != 0)
{
    /* On error, transaction is automatically rolled back */
    tidesdb_txn_free(txn);
    return -1;
}

tidesdb_txn_free(txn);
```

### Transaction Rollback

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin(db, cf, &txn);

tidesdb_txn_put(txn, (uint8_t *)"key", 3, (uint8_t *)"value", 5, -1);

/* Decide to rollback instead of commit */
tidesdb_txn_rollback(txn);
tidesdb_txn_free(txn);
/* No changes were applied */
```

## Iterators

Iterators provide efficient forward and backward traversal over key-value pairs.

### Forward Iteration

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin_read(db, cf, &txn);

tidesdb_iter_t *iter = NULL;
if (tidesdb_iter_new(txn, &iter) != 0)
{
    tidesdb_txn_free(txn);
    return -1;
}

/* Seek to first entry */
tidesdb_iter_seek_to_first(iter);

while (tidesdb_iter_valid(iter))
{
    uint8_t *key = NULL;
    size_t key_size = 0;
    uint8_t *value = NULL;
    size_t value_size = 0;
    
    if (tidesdb_iter_key(iter, &key, &key_size) == 0 &&
        tidesdb_iter_value(iter, &value, &value_size) == 0)
    {
        printf("Key: %.*s, Value: %.*s\n", 
               (int)key_size, key, (int)value_size, value);
    }
    
    tidesdb_iter_next(iter);
}

tidesdb_iter_free(iter);
tidesdb_txn_free(txn);
```

### Backward Iteration

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin_read(db, cf, &txn);

tidesdb_iter_t *iter = NULL;
tidesdb_iter_new(txn, &iter);

tidesdb_iter_seek_to_last(iter);

while (tidesdb_iter_valid(iter))
{
    /* Process entries in reverse order */
    tidesdb_iter_prev(iter);
}

tidesdb_iter_free(iter);
tidesdb_txn_free(txn);
```

### Iterator Seek Operations

TidesDB provides seek operations that allow you to position an iterator at a specific key or key range without scanning from the beginning. If you have block indexes (`enable_block_indexes = 1`) enabled for the column family, these seek operations will be faster as they use succinct trie indexes to locate blocks directly.

#### Seek to Specific Key

**`tidesdb_iter_seek(iter, key, key_size)`** · Positions iterator at the first key >= target key

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin_read(db, cf, &txn);

tidesdb_iter_t *iter = NULL;
tidesdb_iter_new(txn, &iter);

/* Seek to specific key */
const char *target = "user:1000";
if (tidesdb_iter_seek(iter, (uint8_t *)target, strlen(target)) == 0)
{
    /* Iterator is now positioned at "user:1000" or the next key after it */
    if (tidesdb_iter_valid(iter))
    {
        uint8_t *key = NULL;
        size_t key_size = 0;
        tidesdb_iter_key(iter, &key, &key_size);
        printf("Found: %.*s\n", (int)key_size, key);
    }
}

tidesdb_iter_free(iter);
tidesdb_txn_free(txn);
```

**`tidesdb_iter_seek_for_prev(iter, key, key_size)`** · Positions iterator at the last key <= target key

```c
/* Seek for reverse iteration */
const char *target = "user:2000";
if (tidesdb_iter_seek_for_prev(iter, (uint8_t *)target, strlen(target)) == 0)
{
    /* Iterator is now positioned at "user:2000" or the previous key before it */
    while (tidesdb_iter_valid(iter))
    {
        /* Iterate backwards from this point */
        tidesdb_iter_prev(iter);
    }
}
```

## Custom Comparators

Register custom key comparison functions for specialized sorting.

### Register a Comparator

```c
/* Define your comparison function */
int my_reverse_compare(const uint8_t *key1, size_t key1_size,
                       const uint8_t *key2, size_t key2_size, void *ctx)
{
    int result = memcmp(key1, key2, key1_size < key2_size ? key1_size : key2_size);
    return -result;  /* reverse order */
}

/* Register it before creating column families */
tidesdb_register_comparator("reverse", my_reverse_compare);

/* Use in column family */
tidesdb_column_family_config_t cf_config = tidesdb_default_column_family_config();
strncpy(cf_config.comparator_name, "reverse", TDB_MAX_COMPARATOR_NAME - 1);
cf_config.comparator_name[TDB_MAX_COMPARATOR_NAME - 1] = '\0';
cf_config.enable_compression = 1;
cf_config.compression_algorithm = COMPRESS_SNAPPY; 
cf_config.enable_block_indexes = 1;
tidesdb_create_column_family(db, "sorted_cf", &cf_config);
```

:::note[Built-in Comparators]
- `"memcmp"` - Binary comparison (default)
- `"string"` - String comparison
- `"numeric"` - Numeric comparison for  uint8_t* keys
:::


## Sync Modes

Control durability vs performance tradeoff.

```c
tidesdb_column_family_config_t cf_config = tidesdb_default_column_family_config();

/* TDB_SYNC_NONE - Fastest, least durable (OS handles flushing) */
cf_config.sync_mode = TDB_SYNC_NONE;

/* TDB_SYNC_FULL - Most durable (fsync on every write) */
cf_config.sync_mode = TDB_SYNC_FULL;

tidesdb_create_column_family(db, "my_cf", &cf_config);
```

:::note[Sync Mode Options]
- **TDB_SYNC_NONE** · No explicit sync, relies on OS page cache (fastest, least durable)
- **TDB_SYNC_FULL** · Fsync on every write operation (slowest, most durable)
:::

## Compaction

**Manual compaction**
```c
tidesdb_compact(cf);  /* Compact SSTables (requires minimum 2 SSTables) */
```

See [How does TidesDB work?](/getting-started/how-does-tidesdb-work#6-compaction-policy) for details on background compaction and parallel compaction.

## Thread Pools

**Configuration**
```c
tidesdb_config_t config = {
    .db_path = "./mydb",
    .num_flush_threads = 4,      /* 4 threads for flush operations (default: 2) */
    .num_compaction_threads = 8  /* 8 threads for compaction (default: 2) */
};

tidesdb_t *db = NULL;
tidesdb_open(&config, &db);
```

See [How does TidesDB work?](/getting-started/how-does-tidesdb-work#75-thread-pool-architecture) for details on thread pool architecture and tuning.

:::note
`max_open_file_handles` is a **storage-engine-level** configuration, not a column family configuration. It's set in `tidesdb_config_t` when opening the storage engine.
:::

**Configuration**
```c
tidesdb_config_t config = {
    .db_path = "./mydb",
    .max_open_file_handles = 2048  /* Default: 1024 */
};

tidesdb_t *db = NULL;
tidesdb_open(&config, &db);
```

## Concurrency

- **Point reads** (`tidesdb_txn_get`) use **READ COMMITTED** isolation
- **Iterators** (`tidesdb_iter_new`) use **snapshot isolation**
- Lock-free reads with RCU memory management
- Multiple readers can execute concurrently without blocking
- Writers are serialized per column family

See [How does TidesDB work?](/getting-started/how-does-tidesdb-work#8-concurrency-and-thread-safety) for detailed concurrency model and thread safety information.
---
title: TidesDB 1 C API Reference
description: Complete C API reference for TidesDB 1
---

## Overview

TidesDB 1 uses a simplified API. All functions return `0` on success and a negative error code on failure.

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
| `TDB_ERR_NOT_FOUND` | `-5` | Key not found in database |
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
int result = tidesdb_txn_put(txn, "my_cf", key, key_size, value, value_size, -1);
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

## Database Operations

### Opening a Database

```c
tidesdb_config_t config = {
    .db_path = "./mydb",
    .enable_debug_logging = 0,  /* Optional enable debug logging */
    .num_flush_threads = 2,     /* Optional flush thread pool size (default is 2) */
    .num_compaction_threads = 2 /* Optional compaction thread pool size (default is 2) */
};

tidesdb_t *db = NULL;
if (tidesdb_open(&config, &db) != 0)
{
    /* Handle error */
    return -1;
}

/* Close the database */
if (tidesdb_close(db) != 0)
{
    /* Handle error */
    return -1;
}
```

### Debug Logging

TidesDB provides runtime debug logging that can be enabled/disabled dynamically.

**Enable at startup**
```c
tidesdb_config_t config = {
    .db_path = "./mydb",
    .enable_debug_logging = 1  /* Enable debug logging */
};

tidesdb_t *db = NULL;
tidesdb_open(&config, &db);
```

**Enable/disable at runtime**
```c
extern int _tidesdb_debug_enabled;  /* Global debug flag */

/* Enable debug logging */
_tidesdb_debug_enabled = 1;

/* Your operations here - debug logs will be written to stderr */

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
    /* Handle error */
    return -1;
}
```

**Custom configuration example**
```c
tidesdb_column_family_config_t cf_config = {
    .memtable_flush_size = 128 * 1024 * 1024,   /* 128MB */
    .max_sstables_before_compaction = 128,      /* trigger compaction at 128 SSTables (min 2 required) */
    .compaction_threads = 4,                    /* use 4 threads for parallel compaction (0 = single-threaded) */
    .max_level = 12,                            /* skip list max level */
    .probability = 0.25f,                       /* skip list probability */
    .compressed = 1,                            /* enable compression */
    .compress_algo = COMPRESS_LZ4,              /* use LZ4 */
    .bloom_filter_fp_rate = 0.01,               /* 1% false positive rate */
    .enable_background_compaction = 1,          /* enable background compaction */
    .background_compaction_interval = 1000000,  /* check every 1000000 microseconds (1 second) */
    .use_sbha = 1,                              /* use sorted binary hash array */
    .sync_mode = TDB_SYNC_FULL,                 /* fsync on every write (most durable) */
    .comparator_name = NULL                     /* NULL = use default "memcmp" */
};

if (tidesdb_create_column_family(db, "my_cf", &cf_config) != 0)
{
    /* Handle error */
    return -1;
}
```

**Using custom comparator**
```c
/* Register custom comparator first (see examples/custom_comparator.c) */
tidesdb_register_comparator("reverse", my_reverse_compare);

tidesdb_column_family_config_t cf_config = tidesdb_default_column_family_config();
cf_config.comparator_name = "reverse";  /* use registered comparator */

if (tidesdb_create_column_family(db, "sorted_cf", &cf_config) != 0)
{
    /* Handle error */
    return -1;
}
```

### Dropping a Column Family

```c
if (tidesdb_drop_column_family(db, "my_cf") != 0)
{
    /* Handle error */
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

Get all column family names in the database.

```c
char **names = NULL;
int count = 0;

if (tidesdb_list_column_families(db, &names, &count) == 0)
{
    printf("Found %d column families:\n", count);
    for (int i = 0; i < count; i++)
    {
        printf("  - %s\n", names[i]);
        free(names[i]);  /* Free each name */
    }
    free(names);  /* Free the array */
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
    printf("Compression: %s\n", stats->config.compressed ? "enabled" : "disabled");
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
    .memtable_flush_size = 128 * 1024 * 1024,   /* increase to 128MB */
    .max_sstables_before_compaction = 256,      /* trigger at 256 SSTables */
    .compaction_threads = 8,                    /* use 8 threads */
    .max_level = 16,                            /* for new memtables */
    .probability = 0.25f,                       /* for new memtables */
    .bloom_filter_fp_rate = 0.001,              /* 0.1% FP rate for new SSTables */
    .enable_background_compaction = 1,          /* enable background compaction */
    .background_compaction_interval = 500000    /* check every 500ms */
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
- `max_level` - Skip list level for **new** memtables only
- `probability` - Skip list probability for **new** memtables only
- `bloom_filter_fp_rate` - False positive rate for **new** SSTables only
- `enable_background_compaction` - Enable/disable background compaction
- `background_compaction_interval` - Compaction check interval

**Non-updatable settings** (would corrupt existing data)
- `compressed` - Cannot change compression on existing SSTables
- `compress_algo` - Cannot change algorithm on existing SSTables
- `use_sbha` - Cannot change index structure on existing SSTables
- `sync_mode` - Cannot change durability mode on existing WALs
- `comparator_name` - Cannot change sort order on existing data

**Configuration persistence**
```
mydb/
├── my_cf/
│   ├── config.cfc          ← Configuration saved here
│   ├── wal_0.log
│   ├── sstable_0.sst
│   └── sstable_1.sst
```

- **On CF creation** Initial config saved to `config.cfc`
- **On database restart** Config loaded from `config.cfc` (if exists)
- **On config update** Changes immediately saved to `config.cfc`
- **If save fails** Returns `TDB_ERR_IO` error code

:::tip[Important Notes]
- Changes apply immediately to new operations
- Existing SSTables/memtables retain their original settings
- New memtables use updated `max_level` and `probability`
- New SSTables use updated `bloom_filter_fp_rate`
- Thread-safe - uses write lock during update
- Configuration persists across database restarts
:::

## Transactions

All operations in TidesDB 1 are done through transactions for ACID guarantees per column family.

### Basic Transaction

```c
tidesdb_txn_t *txn = NULL;
if (tidesdb_txn_begin(db, &txn) != 0)
{
    return -1;
}

/* Put a key-value pair */
const uint8_t *key = (uint8_t *)"mykey";
const uint8_t *value = (uint8_t *)"myvalue";

if (tidesdb_txn_put(txn, "my_cf", key, 5, value, 7, -1) != 0)
{
    tidesdb_txn_free(txn);
    return -1;
}

/* Commit the transaction */
if (tidesdb_txn_commit(txn) != 0)
{
    tidesdb_txn_free(txn);
    return -1;
}

tidesdb_txn_free(txn);
```

### With TTL (Time-to-Live)

```c
tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin(db, &txn);

const uint8_t *key = (uint8_t *)"temp_key";
const uint8_t *value = (uint8_t *)"temp_value";

/* TTL is Unix timestamp (seconds since epoch) - absolute expiration time */
time_t ttl = time(NULL) + 60;  /* Expires 60 seconds from now */

/* Use -1 for no expiration */
tidesdb_txn_put(txn, "my_cf", key, 8, value, 10, ttl);
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
tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin_read(db, &txn);  /* Read-only transaction */

const uint8_t *key = (uint8_t *)"mykey";
uint8_t *value = NULL;
size_t value_size = 0;

if (tidesdb_txn_get(txn, "my_cf", key, 5, &value, &value_size) == 0)
{
    /* Use value */
    printf("Value: %.*s\n", (int)value_size, value);
    free(value);
}

tidesdb_txn_free(txn);
```

### Deleting a Key-Value Pair

```c
tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin(db, &txn);

const uint8_t *key = (uint8_t *)"mykey";
tidesdb_txn_delete(txn, "my_cf", key, 5);

tidesdb_txn_commit(txn);
tidesdb_txn_free(txn);
```

### Multi-Operation Transaction

```c
tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin(db, &txn);

/* Multiple operations in one transaction */
tidesdb_txn_put(txn, "my_cf", (uint8_t *)"key1", 4, (uint8_t *)"value1", 6, -1);
tidesdb_txn_put(txn, "my_cf", (uint8_t *)"key2", 4, (uint8_t *)"value2", 6, -1);
tidesdb_txn_delete(txn, "my_cf", (uint8_t *)"old_key", 7);

/* Commit atomically - all or nothing */
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
tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin(db, &txn);

tidesdb_txn_put(txn, "my_cf", (uint8_t *)"key", 3, (uint8_t *)"value", 5, -1);

/* Decide to rollback instead of commit */
tidesdb_txn_rollback(txn);
tidesdb_txn_free(txn);
/* No changes were applied */
```

## Iterators

Iterators provide efficient forward and backward traversal over key-value pairs.

### Forward Iteration

```c
tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin_read(db, &txn);

tidesdb_iter_t *iter = NULL;
if (tidesdb_iter_new(txn, "my_cf", &iter) != 0)
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
        /* Use key and value */
        printf("Key: %.*s, Value: %.*s\n", 
               (int)key_size, key, (int)value_size, value);
        free(key);
        free(value);
    }
    
    tidesdb_iter_next(iter);
}

tidesdb_iter_free(iter);
tidesdb_txn_free(txn);
```

### Backward Iteration

```c
tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin_read(db, &txn);

tidesdb_iter_t *iter = NULL;
tidesdb_iter_new(txn, "my_cf", &iter);

/* Seek to last entry */
tidesdb_iter_seek_to_last(iter);

while (tidesdb_iter_valid(iter))
{
    /* Process entries in reverse order */
    tidesdb_iter_prev(iter);
}

tidesdb_iter_free(iter);
tidesdb_txn_free(txn);
```

### Iterator Reference Counting and Compaction Safety

TidesDB uses atomic reference counting to ensure safe concurrent access between iterators and compaction.

:::note[How Reference Counting Works]
- **Automatic Reference Counting** - When an iterator is created, it acquires references on all active SSTables, preventing them from being deleted
- **Copy-on-Write (COW) Semantics** - Compaction creates new merged SSTables and immediately replaces old ones in the active array, but old SSTables remain in memory for active iterators
- **Non-Blocking Compaction** - Compaction completes immediately without waiting for iterators to finish, ensuring high throughput
- **Automatic Cleanup** - When an iterator is freed, it releases its references. SSTables with zero references are automatically deleted (both file and memory)
- **Heap-Based Merge** - Iterators use a min-heap (forward) or max-heap (backward) to efficiently merge-sort entries from multiple sources
:::

**How it works**

1. Iterator creation acquires references on all SSTables (increments `ref_count`)
2. Compaction creates new merged SSTables and swaps them into the active array
3. Compaction releases its reference on old SSTables (decrements `ref_count`)
4. Old SSTables remain accessible to active iterators (ref_count > 0)
5. When iterator is freed, it releases references (decrements `ref_count`)
6. When `ref_count` drops to 0, the SSTable file is deleted and memory is freed

```c
tidesdb_iter_t *iter = NULL;
tidesdb_iter_new(txn, "my_cf", &iter);  /* Acquires references on SSTables */
tidesdb_iter_seek_to_first(iter);

/* Compaction can occur here - new SSTables replace old ones */
/* But iterator still has valid references to old SSTables */

while (tidesdb_iter_valid(iter))
{
    uint8_t *key = NULL, *value = NULL;
    size_t key_size = 0, value_size = 0;
    
    tidesdb_iter_key(iter, &key, &key_size);
    tidesdb_iter_value(iter, &value, &value_size);
    
    /* Process data from snapshot */
    
    free(key);
    free(value);
    tidesdb_iter_next(iter);
}

tidesdb_iter_free(iter);  /* Releases references, triggers cleanup if ref_count == 0 */
```

:::tip[Benefits]
- **True Snapshot Isolation** - Iterators see a consistent snapshot of data from creation time
- **No Blocking** - Compaction and iteration proceed independently without waiting
- **Automatic Resource Management** - No manual cleanup required, reference counting handles everything
- **Safe Concurrent Access** - Multiple iterators and compaction can run simultaneously
:::

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
cf_config.comparator_name = "reverse";
tidesdb_create_column_family(db, "sorted_cf", &cf_config);
```

:::note[Built-in Comparators]
- `"memcmp"` - Binary comparison (default)
- `"string"` - Lexicographic string comparison
- `"numeric"` - Numeric comparison for uint64_t keys
:::

See `examples/custom_comparator.c` for more examples.

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
- **TDB_SYNC_NONE** - No explicit sync, relies on OS page cache (fastest, least durable)
- **TDB_SYNC_FULL** - Fsync on every write operation (slowest, most durable)
:::

## Background Compaction

TidesDB 1 features automatic background compaction with optional parallel execution.

**Automatic background compaction** runs when SSTable count reaches the configured threshold

```c
tidesdb_column_family_config_t cf_config = tidesdb_default_column_family_config();
cf_config.enable_background_compaction = 1;       /* Enable background compaction */
cf_config.max_sstables_before_compaction = 128;   /* Trigger at 128 SSTables (default) */
cf_config.compaction_threads = 4;                 /* Use 4 threads for parallel compaction */

tidesdb_create_column_family(db, "my_cf", &cf_config);
/* Background thread automatically compacts when threshold is reached */
```

:::note[Configuration Options]
- `enable_background_compaction` - Enable/disable automatic background compaction (default: enabled)
- `background_compaction_interval` - Interval in microseconds between compaction checks (default: 1000000 = 1 second)
- `max_sstables_before_compaction` - SSTable count threshold to trigger compaction (default: 128, minimum: 2)
- `compaction_threads` - Number of threads for parallel compaction (default: 4, set to 0 for single-threaded)
:::

**Parallel Compaction**
- Set `compaction_threads > 0` to enable parallel compaction
- Uses semaphore-based thread pool for concurrent SSTable pair merging
- Each thread compacts one pair of SSTables independently
- Automatically limits threads to available CPU cores
- Set `compaction_threads = 0` for single-threaded compaction (default 4 threads)

**Manual compaction** can be triggered at any time (requires minimum 2 SSTables):

```c
tidesdb_compact(cf);  /* Automatically uses parallel compaction if compaction_threads > 0 */
```

:::tip[Benefits]
- Removes tombstones and expired TTL entries
- Merges duplicate keys (keeps latest version)
- Reduces SSTable count
- Background compaction runs in separate thread (non-blocking)
- Parallel compaction significantly speeds up large compactions
- Manual compaction requires minimum 2 SSTables to merge
:::

## Thread Pool Architecture

TidesDB uses shared thread pools at the database level for flush and compaction operations.

:::note[Design]
- **Shared pools** - All column families share the same flush and compaction thread pools
- **Database-level** - Configured once when opening the database
- **Task-based** - Flush and compaction tasks are submitted to the pools
- **Non-blocking** - Operations are asynchronous, don't block application threads
:::

**Configuration**
```c
tidesdb_config_t config = {
    .db_path = "./mydb",
    .num_flush_threads = 4,      /* 4 threads for flush operations */
    .num_compaction_threads = 8  /* 8 threads for compaction operations */
};

tidesdb_t *db = NULL;
tidesdb_open(&config, &db);
```

**Default values**
- `num_flush_threads` - Default is 2
- `num_compaction_threads` - Default is 2
- Set to `0` to use defaults

**How it works**
1. **Flush pool** - Handles memtable flush operations across all column families
2. **Compaction pool** - Handles compaction operations across all column families
3. **Task submission** - When a memtable needs flushing or compaction is triggered, a task is submitted to the appropriate pool
4. **Worker threads** - Pool workers pick up tasks and execute them asynchronously
5. **Shared resources** - Multiple column families can flush/compact simultaneously using the shared pools

:::tip[Benefits]
- **Resource efficiency** - One set of threads serves all column families
- **Better utilization** - Threads are shared across workloads
- **Simpler configuration** - Set once at database level
- **Scalability** - Easily tune for your hardware (e.g., match CPU core count)
:::

:::caution[Tuning Guidelines]
- **Flush threads** - Usually 2-4 is sufficient (I/O bound)
- **Compaction threads** - Can be higher (4-16) for CPU-intensive workloads
- **Total threads** - Consider total = flush + compaction + application threads
- **CPU cores** - Don't exceed available cores significantly
:::

## LRU File Handle Cache

TidesDB features a configurable LRU (Least Recently Used) cache for open file handles to limit system resources while maintaining performance.

:::note[How It Works]
- Caches open file descriptors for SSTables to avoid repeated open/close operations
- Uses LRU eviction policy - least recently used files are closed when cache is full
- Configurable per column family via `max_open_file_handles` setting
- Set to `0` to disable caching (files opened/closed on each access)
- Default: 1024 open file handles
:::

**Configuration Example**

```c
tidesdb_column_family_config_t cf_config = tidesdb_default_column_family_config();

/* Set maximum open file handles */
cf_config.max_open_file_handles = 2048;  /* Cache up to 2048 open files */

/* Or disable caching entirely */
cf_config.max_open_file_handles = 0;  /* No caching - open/close on each access */

tidesdb_create_column_family(db, "my_cf", &cf_config);
```

:::tip[Performance Considerations]
- **Higher cache size** = Better performance for read-heavy workloads with many SSTables
- **Lower cache size** = Reduced system resource usage (file descriptors)
- **Disabled (0)** = Maximum resource conservation, but slower for repeated reads
- Monitor system `ulimit -n` to ensure sufficient file descriptor limits
:::

:::caution[System Limits]
Ensure your system's file descriptor limit is sufficient for your workload. Check with `ulimit -n` on Unix systems. Increase if needed
```bash
# Temporary (current session)
ulimit -n 4096

# Permanent (add to /etc/security/limits.conf)
* soft nofile 4096
* hard nofile 8192
```
:::

## Concurrency Model

TidesDB is designed for high concurrency with minimal blocking.

:::note[Reader-Writer Locks]
- Each column family has a reader-writer lock
- **Multiple readers can read concurrently** - no blocking between readers
- **Writers don't block readers** - readers can access data while writes are in progress
- **Writers block other writers** - only one writer per column family at a time
:::

:::caution[Transaction Isolation]
- Read transactions (`tidesdb_txn_begin_read`) acquire read locks and see a consistent snapshot via COW
- Write transactions (`tidesdb_txn_begin`) acquire write locks on commit
- **Isolation Level** Read Committed - changes not visible to other transactions until commit
- Writers are serialized per column family ensuring atomicity
:::

:::tip[Optimal Use Cases]
- **Read-heavy workloads** - Unlimited concurrent readers with no contention
- **Mixed read/write workloads** - Readers never wait for writers to complete
- **Multi-column-family applications** - Different column families can be written to concurrently
:::

**Concurrent Operations Example**
```c
/* Thread 1 Reading */
tidesdb_txn_t *read_txn;
tidesdb_txn_begin_read(db, &read_txn);
tidesdb_txn_get(read_txn, "my_cf", key, key_size, &value, &value_size);
/* Can read while Thread 2 is writing */

/* Thread 2 Writing */
tidesdb_txn_t *write_txn;
tidesdb_txn_begin(db, &write_txn);
tidesdb_txn_put(write_txn, "my_cf", key, key_size, value, value_size, -1);
tidesdb_txn_commit(write_txn);  /* Briefly blocks other writers only */

/* Thread 3 Reading different CF */
tidesdb_txn_t *other_txn;
tidesdb_txn_begin_read(db, &other_txn);
tidesdb_txn_get(other_txn, "other_cf", key, key_size, &value, &value_size);
/* No blocking - different column family */
```
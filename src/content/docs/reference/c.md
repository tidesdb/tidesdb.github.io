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
| `TDB_ERR_MEMORY` | `-1` | Memory allocation failed |
| `TDB_ERR_INVALID_ARGS` | `-2` | Invalid arguments passed to function (NULL pointers, invalid sizes, etc.) |
| `TDB_ERR_NOT_FOUND` | `-3` | Key not found in column family |
| `TDB_ERR_IO` | `-4` | I/O operation failed (file read/write error) |
| `TDB_ERR_CORRUPTION` | `-5` | Data corruption detected (checksum failure, invalid format version, truncated data) |
| `TDB_ERR_EXISTS` | `-6` | Resource already exists (e.g., column family name collision) |
| `TDB_ERR_LOCK` | `-7` | Lock acquisition failed |
| `TDB_ERR_CONFLICT` | `-8` | Transaction conflict detected (write-write or read-write conflict in SERIALIZABLE/SNAPSHOT isolation) |
| `TDB_ERR_OVERFLOW` | `-9` | Numeric overflow or buffer overflow |
| `TDB_ERR_TOO_LARGE` | `-10` | Key or value size exceeds maximum allowed size |
| `TDB_ERR_MEMORY_LIMIT` | `-11` | Operation would exceed memory limits (safety check to prevent OOM) |

**Error categories:**
- `TDB_ERR_CORRUPTION` indicates data integrity issues requiring immediate attention
- `TDB_ERR_CONFLICT` indicates transaction conflicts (retry may succeed)
- `TDB_ERR_MEMORY`, `TDB_ERR_MEMORY_LIMIT`, `TDB_ERR_TOO_LARGE` indicate resource constraints
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
    .enable_debug_logging = 0,         /* Enable debug logging (default: 0) */
    .num_flush_threads = 2,            /* Flush thread pool size (default: 2) */
    .num_compaction_threads = 2,       /* Compaction thread pool size (default: 2) */
    .block_cache_size = 64 * 1024 * 1024,  /* 64MB global block cache (default: 0 = disabled) */
    .max_open_sstables = 100           /* Max cached SSTable structures (default: 100) */
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
    .write_buffer_size = 128 * 1024 * 1024,     /* 128MB memtable flush threshold */
    .level_size_ratio = 10,                     /* Level size multiplier (default: 10) */
    .max_levels = 7,                            /* Maximum LSM levels (default: 7) */
    .dividing_level_offset = 1,                 /* Compaction dividing level offset (default: 1) */
    .skip_list_max_level = 12,                  /* Skip list max level */
    .skip_list_probability = 0.25f,             /* Skip list probability */
    .compression_algorithm = COMPRESS_LZ4,      /* LZ4, SNAPPY, or ZSTD */
    .enable_bloom_filter = 1,                   /* Enable bloom filters */
    .bloom_fpr = 0.01,                          /* 1% false positive rate */
    .enable_block_indexes = 1,                  /* Enable succinct trie block indexes */
    .index_sample_ratio = 16,                   /* Sample 1 in 16 keys for index (default: 16) */
    .sync_mode = TDB_SYNC_FULL,                 /* TDB_SYNC_NONE or TDB_SYNC_FULL */
    .comparator_name = {0},                     /* Empty = use default "memcmp" */
    .klog_block_size = 4096,                    /* Klog block size (default: 4096) */
    .vlog_block_size = 4096,                    /* Vlog block size (default: 4096) */
    .value_threshold = 1024                     /* Values > 1KB go to vlog (default: 1024) */
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

Get all column family names on the TidesDB instance.

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
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_stats_t *stats = NULL;
if (tidesdb_get_stats(cf, &stats) == 0)
{
    printf("Memtable Size: %zu bytes\n", stats->memtable_size);
    printf("Number of Levels: %d\n", stats->num_levels);
    
    for (int i = 0; i < stats->num_levels; i++)
    {
        printf("Level %d: %d SSTables, %zu bytes\n", 
               i + 1, stats->level_num_sstables[i], stats->level_sizes[i]);
    }
    
    /* Access configuration */
    printf("Write Buffer Size: %zu\n", stats->config->write_buffer_size);
    printf("Compression: %d\n", stats->config->compression_algorithm);
    printf("Bloom Filter: %s\n", stats->config->enable_bloom_filter ? "enabled" : "disabled");
    
    tidesdb_free_stats(stats);
}
```

**Statistics include:**
- Memtable size in bytes
- Number of LSM levels
- Per-level SSTable count and total size
- Full column family configuration

### Updating Column Family Configuration

Update runtime-safe configuration settings. Configuration changes are applied to new operations only.

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_column_family_config_t new_config = tidesdb_default_column_family_config();
new_config.write_buffer_size = 256 * 1024 * 1024;  /* 256MB */
new_config.skip_list_max_level = 16;
new_config.skip_list_probability = 0.25f;
new_config.bloom_fpr = 0.001;  /* 0.1% false positive rate */
new_config.index_sample_ratio = 8;  /* sample 1 in 8 keys */

int persist_to_disk = 1;  /* save to config.cfc */
if (tidesdb_cf_update_runtime_config(cf, &new_config, persist_to_disk) == 0)
{
    printf("Configuration updated successfully\n");
}
```

**Updatable settings** (safe to change at runtime):
- `write_buffer_size` - Memtable flush threshold
- `skip_list_max_level` - Skip list level for **new** memtables
- `skip_list_probability` - Skip list probability for **new** memtables
- `bloom_fpr` - False positive rate for **new** SSTables
- `index_sample_ratio` - Index sampling ratio for **new** SSTables
- `sync_mode` - Durability mode (TDB_SYNC_NONE or TDB_SYNC_FULL)

**Non-updatable settings** (would corrupt existing data):
- `compression_algorithm` - Cannot change on existing SSTables
- `enable_block_indexes` - Cannot change index structure
- `enable_bloom_filter` - Cannot change bloom filter presence
- `comparator_name` - Cannot change sort order
- `level_size_ratio` - Cannot change LSM level sizing
- `value_threshold` - Cannot change klog/vlog separation
- `klog_block_size` / `vlog_block_size` - Cannot change block sizes

**Configuration persistence:**

If `persist_to_disk = 1`, changes are saved to `config.cfc` in the column family directory. On restart, the configuration is loaded from this file.

```c
/* Save configuration to custom INI file */
tidesdb_cf_config_save_to_ini("custom_config.ini", "my_cf", &new_config);
```

:::tip[Important Notes]
Changes apply immediately to new operations. Existing SSTables and memtables retain their original settings. The update operation is thread-safe.
:::

## Transactions

All operations in TidesDB are done through transactions for ACID guarantees per column family.

### Basic Transaction

```c
/* Get column family pointer first */
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_txn_t *txn = NULL;
if (tidesdb_txn_begin(db, &txn) != 0)
{
    return -1;
}

const uint8_t *key = (uint8_t *)"mykey";
const uint8_t *value = (uint8_t *)"myvalue";

if (tidesdb_txn_put(txn, cf, key, 5, value, 7, -1) != 0)
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
tidesdb_txn_begin(db, &txn);

const uint8_t *key = (uint8_t *)"temp_key";
const uint8_t *value = (uint8_t *)"temp_value";

/* TTL is Unix timestamp (seconds since epoch) -- absolute expiration time */
time_t ttl = time(NULL) + 60;  /* Expires 60 seconds from now */

/* Use -1 for no expiration */
tidesdb_txn_put(txn, cf, key, 8, value, 10, ttl);
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
tidesdb_txn_begin(db, &txn);

const uint8_t *key = (uint8_t *)"mykey";
uint8_t *value = NULL;
size_t value_size = 0;

if (tidesdb_txn_get(txn, cf, key, 5, &value, &value_size) == 0)
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
tidesdb_txn_begin(db, &txn);

const uint8_t *key = (uint8_t *)"mykey";
tidesdb_txn_delete(txn, cf, key, 5);

tidesdb_txn_commit(txn);
tidesdb_txn_free(txn);
```

### Multi-Operation Transaction

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin(db, &txn);

/* Multiple operations in one transaction */
tidesdb_txn_put(txn, cf, (uint8_t *)"key1", 4, (uint8_t *)"value1", 6, -1);
tidesdb_txn_put(txn, cf, (uint8_t *)"key2", 4, (uint8_t *)"value2", 6, -1);
tidesdb_txn_delete(txn, cf, (uint8_t *)"old_key", 7);

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
tidesdb_txn_begin(db, &txn);

tidesdb_txn_put(txn, cf, (uint8_t *)"key", 3, (uint8_t *)"value", 5, -1);

/* Decide to rollback instead of commit */
tidesdb_txn_rollback(txn);
tidesdb_txn_free(txn);
/* No changes were applied */
```

### Multi-Column-Family Transactions

TidesDB supports atomic transactions across multiple column families with true all-or-nothing semantics.

```c
tidesdb_column_family_t *users_cf = tidesdb_get_column_family(db, "users");
tidesdb_column_family_t *orders_cf = tidesdb_get_column_family(db, "orders");
if (!users_cf || !orders_cf) return -1;

tidesdb_txn_t *txn = NULL;
if (tidesdb_txn_begin(db, &txn) != 0)
{
    return -1;
}

/* Write to users CF */
tidesdb_txn_put(txn, users_cf, (uint8_t *)"user:1000", 9, 
                (uint8_t *)"John Doe", 8, -1);

/* Write to orders CF */
tidesdb_txn_put(txn, orders_cf, (uint8_t *)"order:5000", 10,
                (uint8_t *)"user:1000|product:A", 19, -1);

/* Atomic commit across both CFs */
if (tidesdb_txn_commit(txn) != 0)
{
    tidesdb_txn_free(txn);
    return -1;
}

tidesdb_txn_free(txn);
```

**Multi-CF guarantees:**
- Either all CFs commit or none do (atomic)
- Automatically detected when operations span multiple CFs
- Uses global sequence numbers with high-bit flagging
- Recovery validates completeness across all participating CFs
- No two-phase commit or coordinator overhead

### Isolation Levels

TidesDB supports five MVCC isolation levels for fine-grained concurrency control.

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_txn_t *txn = NULL;

/* READ UNCOMMITTED - sees all data including uncommitted changes */
tidesdb_txn_begin_with_isolation(db, TDB_ISOLATION_READ_UNCOMMITTED, &txn);

/* READ COMMITTED - sees only committed data (default) */
tidesdb_txn_begin_with_isolation(db, TDB_ISOLATION_READ_COMMITTED, &txn);

/* REPEATABLE READ - consistent snapshot, phantom reads possible */
tidesdb_txn_begin_with_isolation(db, TDB_ISOLATION_REPEATABLE_READ, &txn);

/* SNAPSHOT ISOLATION - write-write conflict detection */
tidesdb_txn_begin_with_isolation(db, TDB_ISOLATION_SNAPSHOT, &txn);

/* SERIALIZABLE - full read-write conflict detection (SSI) */
tidesdb_txn_begin_with_isolation(db, TDB_ISOLATION_SERIALIZABLE, &txn);

/* Use transaction with operations */
tidesdb_txn_put(txn, cf, (uint8_t *)"key", 3, (uint8_t *)"value", 5, -1);

int result = tidesdb_txn_commit(txn);
if (result == TDB_ERR_CONFLICT)
{
    /* Conflict detected - retry transaction */
    tidesdb_txn_free(txn);
    return -1;
}

tidesdb_txn_free(txn);
```

**Isolation level characteristics:**
- **READ UNCOMMITTED** - Maximum concurrency, minimal consistency
- **READ COMMITTED** - Balanced for OLTP workloads (default)
- **REPEATABLE READ** - Strong point read consistency
- **SNAPSHOT** - Prevents lost updates with write-write conflict detection
- **SERIALIZABLE** - Strongest guarantees with full SSI, higher abort rates

## Iterators

Iterators provide efficient forward and backward traversal over key-value pairs.

### Forward Iteration

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin(db, &txn);

tidesdb_iter_t *iter = NULL;
if (tidesdb_iter_new(txn, cf, &iter) != 0)
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
tidesdb_txn_begin(db, &txn);

tidesdb_iter_t *iter = NULL;
tidesdb_iter_new(txn, cf, &iter);

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

TidesDB provides seek operations that allow you to position an iterator at a specific key or key range without scanning from the beginning.

**How Seek Works:**

**With Block Indexes Enabled** (`enable_block_indexes = 1`):
- Uses succinct trie to find the predecessor block (largest indexed key <= target)
- The trie samples keys at a configurable ratio (default 1:16 via `index_sample_ratio`)
- Jumps directly to the target block using the block index
- Scans forward from that block to find the exact key
- **Performance:** O(log n) block lookup + O(k) entries per block scan

**Without Block Indexes** (`enable_block_indexes = 0`):
- Starts from the first klog block
- Scans sequentially through all blocks until target is found
- **Performance:** O(n) blocks × O(k) entries per block

**Example:** For a 1GB SSTable with 4KB blocks:
- With indexes: ~10 trie lookups + scan 1 block (~100 entries)
- Without indexes: scan ~250,000 blocks sequentially

Block indexes provide dramatic speedup for large SSTables at the cost of ~5-10% storage overhead for the succinct trie structure.

#### Seek to Specific Key

**`tidesdb_iter_seek(iter, key, key_size)`** · Positions iterator at the first key >= target key

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin(db, &txn);

tidesdb_iter_t *iter = NULL;
tidesdb_iter_new(txn, cf, &iter);

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

TidesDB uses comparators to determine the sort order of keys throughout the entire system: memtables, SSTables, block indexes, and iterators all use the same comparison logic. Once a comparator is set for a column family, it **cannot be changed** without corrupting data.

### Built-in Comparators

TidesDB provides six built-in comparators that are automatically registered on database open:

**`"memcmp"` (default)** - Binary byte-by-byte comparison
- Compares min(key1_size, key2_size) bytes using `memcmp()`
- If bytes are equal, shorter key sorts first
- **Use case:** Binary keys, raw byte data, general purpose

**`"lexicographic"`** - Null-terminated string comparison
- Uses `strcmp()` for lexicographic ordering
- Ignores key_size parameters (assumes null-terminated)
- **Use case:** C strings, text keys
- **Warning:** Keys must be null-terminated or behavior is undefined

**`"uint64"`** - Unsigned 64-bit integer comparison
- Interprets 8-byte keys as uint64_t values
- Falls back to memcmp if key_size != 8
- **Use case:** Numeric IDs, timestamps, counters
- **Example:** `uint64_t id = 1000; tidesdb_txn_put(txn, cf, (uint8_t*)&id, 8, ...)`

**`"int64"`** - Signed 64-bit integer comparison
- Interprets 8-byte keys as int64_t values
- Falls back to memcmp if key_size != 8
- **Use case:** Signed numeric keys, relative timestamps
- **Example:** `int64_t offset = -500; tidesdb_txn_put(txn, cf, (uint8_t*)&offset, 8, ...)`

**`"reverse"`** - Reverse binary comparison
- Negates the result of memcmp comparator
- Sorts keys in descending order
- **Use case:** Reverse chronological order, descending IDs

**`"case_insensitive"`** - Case-insensitive ASCII comparison
- Converts A-Z to a-z during comparison
- Compares min(key1_size, key2_size) bytes
- If bytes are equal (ignoring case), shorter key sorts first
- **Use case:** Case-insensitive text keys, usernames, email addresses

### Custom Comparator Registration

```c
/* Define your comparison function */
int my_timestamp_compare(const uint8_t *key1, size_t key1_size,
                         const uint8_t *key2, size_t key2_size, void *ctx)
{
    (void)ctx;  /* unused */
    
    if (key1_size != 8 || key2_size != 8)
    {
        /* fallback for invalid sizes */
        return memcmp(key1, key2, key1_size < key2_size ? key1_size : key2_size);
    }
    
    uint64_t ts1, ts2;
    memcpy(&ts1, key1, 8);
    memcpy(&ts2, key2, 8);
    
    /* reverse order for newest-first */
    if (ts1 > ts2) return -1;
    if (ts1 < ts2) return 1;
    return 0;
}

/* Register before creating column families */
tidesdb_register_comparator(db, "timestamp_desc", my_timestamp_compare, NULL, NULL);

/* Use in column family */
tidesdb_column_family_config_t cf_config = tidesdb_default_column_family_config();
strncpy(cf_config.comparator_name, "timestamp_desc", TDB_MAX_COMPARATOR_NAME - 1);
cf_config.comparator_name[TDB_MAX_COMPARATOR_NAME - 1] = '\0';
tidesdb_create_column_family(db, "events", &cf_config);
```

**Comparator function signature:**
```c
int (*comparator_fn)(const uint8_t *key1, size_t key1_size,
                     const uint8_t *key2, size_t key2_size,
                     void *ctx);
```

**Return values:**
- `< 0` if key1 < key2
- `0` if key1 == key2
- `> 0` if key1 > key2

**Important notes:**
- Comparators must be **registered before** creating column families that use them
- Once set, a comparator **cannot be changed** for a column family
- The same comparator is used across memtables, SSTables, block indexes, and iterators
- Custom comparators can use the `ctx` parameter for runtime configuration


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
`max_open_sstables` is a **storage-engine-level** configuration, not a column family configuration. It controls the LRU cache size for SSTable structures. It's set in `tidesdb_config_t` when opening TidesDB.
:::

**Configuration**
```c
tidesdb_config_t config = {
    .db_path = "./mydb",
    .max_open_sstables = 200,  /* LRU cache for 200 SSTable structures (default: 100) */
    .block_cache_size = 128 * 1024 * 1024  /* 128MB global block cache (default: 0) */
};

tidesdb_t *db = NULL;
tidesdb_open(&config, &db);
```

See [How does TidesDB work?](/getting-started/how-does-tidesdb-work#8-concurrency-and-thread-safety) for detailed concurrency model and thread safety information.
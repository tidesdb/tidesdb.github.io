---
title: TidesDB C API Reference
description: Complete C API reference for TidesDB
---

<div id="tidesdb-version" class="version-section"></div>

<script>
(function() {
  var badge = document.getElementById('tidesdb-version');
  fetch('https://api.github.com/repos/tidesdb/tidesdb/releases/latest')
    .then(function(r) { return r.json(); })
    .then(function(data) {
      var version = data.tag_name || 'v8.1.0';
      var url = data.html_url || 'https://github.com/tidesdb/tidesdb/releases';
      badge.innerHTML = 
        '<span>' + version + '</span></a>';
    })
    .catch(function() {
      badge.innerHTML = 
        '<span>v9.0.0</span>';
    });
})();
</script>


<div class="no-print">

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/c.md).

<hr/>



<details>
<summary>Want to watch a dedicated how-to video?</summary>

<iframe style="height: 420px;!important" width="720" height="420px" src="https://www.youtube.com/embed/uDIygMZTcLI?si=Axt_HSCFk8w8AKWx" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>

</details>

</div>

## Overview

TidesDB is designed to provide a simple and intuitive C API for all your embedded storage needs.  This document is complete reference for the C API covering database operations, transactions, column families, iterators and more.

## Include

:::note
You can use other components of TidesDB such as skip list, bloom filter etc. under `tidesdb/` - this also prevents collisions.
:::

### Choosing Between `tidesdb.h` and `db.h`

TidesDB provides two header files with different purposes:

**tidesdb.h**

Full C implementation header. Mainly use this for native C/C++ applications.

```c
#include <tidesdb/tidesdb.h>
```

**db.h**

db.h is mainly an FFI/Language binding interface with minimal dependencies and simpler ABI.

```c
#include <tidesdb/db.h>
```

:::tip[When to Use Each]
- C/C++ applications ➞ Use `tidesdb.h` for full access to the API
- Language bindings (jextract, rust-bindgen, ctypes, cgo, etc.) ➞ Use `db.h` for a stable FFI interface
- Library developers ➞ Use `db.h` to avoid exposing internal implementation details
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
| `TDB_ERR_CONFLICT` | `-7` | Transaction conflict detected (write-write conflict in SNAPSHOT, read-write + write-write in REPEATABLE_READ, full SSI in SERIALIZABLE) |
| `TDB_ERR_TOO_LARGE` | `-8` | Key or value size exceeds maximum allowed size |
| `TDB_ERR_MEMORY_LIMIT` | `-9` | Operation would exceed memory limits (safety check to prevent OOM) |
| `TDB_ERR_INVALID_DB` | `-10` | Database handle is invalid (e.g., after close) |
| `TDB_ERR_UNKNOWN` | `-11` | Unknown or unspecified error |
| `TDB_ERR_LOCKED` | `-12` | Database is locked by another process |
| `TDB_ERR_READONLY` | `-13` | Database is in read-only replica mode (writes rejected) |

**Error categories**
- `TDB_ERR_CORRUPTION` indicates data integrity issues requiring immediate attention
- `TDB_ERR_CONFLICT` indicates transaction conflicts (retry may succeed)
- `TDB_ERR_MEMORY`, `TDB_ERR_MEMORY_LIMIT`, `TDB_ERR_TOO_LARGE` indicate resource constraints
- `TDB_ERR_NOT_FOUND`, `TDB_ERR_EXISTS` are normal operational conditions, not failures

### Example Error Handling

```c
int result = tidesdb_txn_put(txn, cf, key, key_size, value, value_size, -1);
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
        case TDB_ERR_CONFLICT:
            fprintf(stderr, "transaction conflict detected\n");
            break;
        default:
            fprintf(stderr, "operation failed with error code: %d\n", result);
            break;
    }
    return -1;
}
```

## Initialization

TidesDB supports **optional** custom memory allocators for integration with custom memory managers (e.g., a Redis module allocator, jemalloc, etc).  You don't need to do this, this is completely optional.

### tidesdb_init

Initializes TidesDB with *optional* custom memory allocation functions. When in use, this must be called exactly once before any other TidesDB function. 

```c
int tidesdb_init(tidesdb_malloc_fn malloc_fn, tidesdb_calloc_fn calloc_fn,
                 tidesdb_realloc_fn realloc_fn, tidesdb_free_fn free_fn);
```

**Parameters**
| Name | Type | Description |
|------|------|-------------|
| `malloc_fn` | `tidesdb_malloc_fn` | Custom malloc function (or `NULL` for system malloc) |
| `calloc_fn` | `tidesdb_calloc_fn` | Custom calloc function (or `NULL` for system calloc) |
| `realloc_fn` | `tidesdb_realloc_fn` | Custom realloc function (or `NULL` for system realloc) |
| `free_fn` | `tidesdb_free_fn` | Custom free function (or `NULL` for system free) |

**Returns**
- `0` on success
- `-1` if already initialized

**Example (system allocator)**
```c
tidesdb_init(NULL, NULL, NULL, NULL);
```

**Example (custom allocator)**
```c
tidesdb_init(RedisModule_Alloc, RedisModule_Calloc,
             RedisModule_Realloc, RedisModule_Free);
```

:::note[Auto-initialization]
If `tidesdb_init()` is not called, TidesDB will auto-initialize with the system allocator on the first call to `tidesdb_open()`.
:::

### tidesdb_finalize

Finalizes TidesDB and resets the allocator. Should be called after all TidesDB operations are complete. After calling this, `tidesdb_init()` can be called again.

```c
void tidesdb_finalize(void);
```

**Example**
```c
tidesdb_init(NULL, NULL, NULL, NULL);

/* ... use TidesDB ... */

tidesdb_close(db);
tidesdb_finalize();
```

## Storage Engine Operations

### Opening TidesDB

```c
tidesdb_config_t config = {
    .db_path = "./mydb",
    .num_flush_threads = 2,                       /* Flush thread pool size (default: 2) */
    .num_compaction_threads = 2,                  /* Compaction thread pool size (default: 2) */
    .log_level = TDB_LOG_INFO,                    /* Log level: TDB_LOG_DEBUG, TDB_LOG_INFO, TDB_LOG_WARN, TDB_LOG_ERROR, TDB_LOG_FATAL, TDB_LOG_NONE */
    .block_cache_size = 64 * 1024 * 1024,         /* 64MB global block cache (default: 64MB) */
    .max_open_sstables = 256,                     /* Max cached SSTable structures (default: 256) */
    .max_memory_usage = 0,                        /* Global memory limit in bytes (default: 0 = auto, 50% of system RAM; minimum: 5% of system RAM) */
    .log_to_file = 0,                             /* Write logs to file instead of stderr (default: 0) */
    .log_truncation_at = 24 * (1024*1024),        /* Log file truncation size (default: 24MB), 0 = no truncation */
    .unified_memtable = 0,                        /* Enable unified memtable mode (default: 0 = per-CF memtables) */
    .unified_memtable_write_buffer_size = 0,      /* Unified memtable write buffer size (default: 0 = use TDB_DEFAULT_WRITE_BUFFER_SIZE, 64MB) */
    .unified_memtable_skip_list_max_level = 0,    /* Skip list max level for unified memtable (default: 0 = 12) */
    .unified_memtable_skip_list_probability = 0,  /* Skip list probability for unified memtable (default: 0 = 0.25) */
    .unified_memtable_sync_mode = 0,              /* Sync mode for unified WAL (default: 0 = TDB_SYNC_NONE) */
    .unified_memtable_sync_interval_us = 0,       /* Sync interval for unified WAL in microseconds (default: 0) */
    .max_concurrent_flushes = 4,                  /* Global cap on in-flight memtable flushes (default: 4, 0 = use TDB_DEFAULT_MAX_CONCURRENT_FLUSHES) */
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

**Using default configuration**

Use `tidesdb_default_config()` to get a configuration with sensible defaults, then override specific fields as needed:

```c
tidesdb_config_t config = tidesdb_default_config();
config.db_path = "./mydb";
config.log_level = TDB_LOG_WARN;  /* Override: only warnings and errors */

tidesdb_t *db = NULL;
if (tidesdb_open(&config, &db) != 0)
{
    return -1;
}
```

:::note[Multiple DBs Allowed]
Multiple TidesDB instances can be opened in the same process, each with its own configuration and data directory.
:::

### Logging

TidesDB provides structured logging with multiple severity levels.

**Log Levels**
- `TDB_LOG_DEBUG` · Detailed diagnostic information
- `TDB_LOG_INFO` · General informational messages (default)
- `TDB_LOG_WARN` · Warning messages for potential issues
- `TDB_LOG_ERROR` · Error messages for failures
- `TDB_LOG_FATAL` · Critical errors that may cause shutdown
- `TDB_LOG_NONE` · Disable all logging

**Configure at startup**
```c
tidesdb_config_t config = {
    .db_path = "./mydb",
    .log_level = TDB_LOG_DEBUG  /* Enable debug logging */
};

tidesdb_t *db = NULL;
tidesdb_open(&config, &db);
```

**Production configuration**
```c
tidesdb_config_t config = {
    .db_path = "./mydb",
    .log_level = TDB_LOG_WARN  /* Only warnings and errors */
};
```

**Output format**
Logs are written to **stderr** by default with timestamps:
```
[HH:MM:SS.mmm] [LEVEL] filename:line: message
```

**Example output**
```
[22:58:00.454] [INFO] tidesdb.c:9322: Opening TidesDB with path=./mydb
[22:58:00.456] [INFO] tidesdb.c:9478: Block clock cache created with max_bytes=64.00 MB
```

**Log to file**

Enable `log_to_file` to write logs to a `LOG` file in the database directory instead of stderr:

```c
tidesdb_config_t config = {
    .db_path = "./mydb",
    .log_level = TDB_LOG_DEBUG,
    .log_to_file = 1  /* Write to ./mydb/LOG instead of stderr */
};

tidesdb_t *db = NULL;
tidesdb_open(&config, &db);
/* Logs are now written to ./mydb/LOG */
```

The log file is opened in append mode and uses line buffering for real-time logging. If the log file cannot be opened, logging falls back to default.

**Redirect stderr to file (alternative)**
```bash
./your_program 2> tidesdb.log  # Redirect std output to file
```

### Backup

`tidesdb_backup` creates an on-disk snapshot of an open database without blocking normal reads/writes.

```c
int tidesdb_backup(tidesdb_t *db, char *dir);
```

**Usage**
```c
tidesdb_t *db = NULL;
tidesdb_open(&config, &db);

if (tidesdb_backup(db, "./mydb_backup") != 0)
{
    fprintf(stderr, "Backup failed\n");
}
```

**Behavior**
- Requires `dir` to be a non-existent directory or an empty directory; returns `TDB_ERR_EXISTS` if not empty.
- Does not copy the `LOCK` file, so the backup can be opened normally.
- Two-phase copy approach:
  - Copies immutable files first (SSTables listed in the manifest plus metadata/config files) and skips WALs.
  - Forces memtable flushes, waits for flush/compaction queues to drain, then copies any remaining files
    (including WALs and updated manifests). Existing SSTables already copied are not recopied.
- Database stays open and usable during backup; no exclusive lock is taken on the source directory.

**Notes**
- The backup represents the database state after the final flush/compaction drain.
- If you need a quiesced backup window, you can pause writes at the application level before calling this API.

### Checkpoint

`tidesdb_checkpoint` creates a lightweight, near-instant snapshot of an open database using hard links instead of copying SSTable data.

```c
int tidesdb_checkpoint(tidesdb_t *db, const char *checkpoint_dir);
```

**Usage**
```c
tidesdb_t *db = NULL;
tidesdb_open(&config, &db);

if (tidesdb_checkpoint(db, "./mydb_checkpoint") != 0)
{
    fprintf(stderr, "Checkpoint failed\n");
}
```

**Behavior**
- Requires `checkpoint_dir` to be a non-existent directory or an empty directory; returns `TDB_ERR_EXISTS` if not empty.
- For each column family:
  - Flushes the active memtable so all data is in SSTables.
  - Halts compactions to ensure a consistent view of live SSTable files.
  - Hard links all SSTable files (`.klog` and `.vlog`) into the checkpoint directory, preserving the level subdirectory structure.
  - Copies small metadata files (manifest, config) into the checkpoint directory.
  - Resumes compactions.
- Falls back to file copy if hard linking fails (e.g., cross-filesystem).
- Database stays open and usable during checkpoint; no exclusive lock is taken on the source directory.

**Checkpoint vs Backup**

| | `tidesdb_backup` | `tidesdb_checkpoint` |
|--|---|---|
| Speed | Copies every SSTable byte-by-byte | Near-instant (hard links, O(1) per file) |
| Disk usage | Full independent copy | No extra disk until compaction removes old SSTables |
| Portability | Can be moved to another filesystem or machine | Same filesystem only (hard link requirement) |
| Use case | Archival, disaster recovery, remote shipping | Fast local snapshots, point-in-time reads, streaming backups |

**Notes**
- The checkpoint represents the database state at the point all memtables are flushed and compactions are halted.
- Hard-linked files share storage with the live database. Deleting the original database does not affect the checkpoint (hard link semantics).
- The checkpoint can be opened as a normal TidesDB database with `tidesdb_open`.

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
    .write_buffer_size = 128 * 1024 * 1024,                   /* 128MB memtable flush threshold */
    .level_size_ratio = 10,                                   /* Level size multiplier (default: 10) */
    .min_levels = 5,                                          /* Minimum LSM levels (default: 5) */
    .dividing_level_offset = 2,                               /* Compaction dividing level offset (default: 2) */
    .skip_list_max_level = 12,                                /* Skip list max level */
    .skip_list_probability = 0.25f,                           /* Skip list probability */
    .compression_algorithm = TDB_COMPRESS_LZ4,                /* TDB_COMPRESS_LZ4, TDB_COMPRESS_LZ4_FAST, TDB_COMPRESS_ZSTD, TDB_COMPRESS_SNAPPY, or TDB_COMPRESS_NONE */
    .enable_bloom_filter = 1,                                 /* Enable bloom filters */
    .bloom_fpr = 0.01,                                        /* 1% false positive rate */
    .enable_block_indexes = 1,                                /* Enable compact block indexes */
    .index_sample_ratio = 1,                                  /* Sample every block for index (default: 1) */
    .block_index_prefix_len = 16,                             /* Block index prefix length (default: 16) */
    .sync_mode = TDB_SYNC_FULL,                               /* TDB_SYNC_NONE, TDB_SYNC_INTERVAL, or TDB_SYNC_FULL */
    .sync_interval_us = 1000000,                              /* Sync interval in microseconds (1 second, only for TDB_SYNC_INTERVAL) */
    .comparator_name = {0},                                   /* Empty = use default "memcmp" */
    .klog_value_threshold = 512,                              /* Values >= 512 bytes go to vlog (default: 512) */
    .min_disk_space = 100 * 1024 * 1024,                      /* Minimum disk space required (default: 100MB) */
    .default_isolation_level = TDB_ISOLATION_READ_COMMITTED,  /* Default transaction isolation */
    .l1_file_count_trigger = 4,                               /* L1 file count trigger for compaction (default: 4) */
    .l0_queue_stall_threshold = 20,                           /* L0 queue stall threshold (default: 20) */
    .tombstone_density_trigger = 0.0,                         /* Tombstone ratio above which compaction escalates (default: 0.0 = disabled, range 0.0 to 1.0) */
    .tombstone_density_min_entries = 1024,                    /* Minimum entry count for an SSTable to be considered by the density trigger (default: 1024) */
    .use_btree = 0                                            /* Use B+tree format for klog (default: 0 = block-based) */
};

if (tidesdb_create_column_family(db, "my_cf", &cf_config) != 0)
{
    return -1;
}
```

**Using custom comparator**
```c
/* Register comparator after opening database but before creating CF */
tidesdb_register_comparator(db, "reverse", my_reverse_compare, NULL, NULL);

tidesdb_column_family_config_t cf_config = tidesdb_default_column_family_config();
strncpy(cf_config.comparator_name, "reverse", TDB_MAX_COMPARATOR_NAME - 1);  
cf_config.comparator_name[TDB_MAX_COMPARATOR_NAME - 1] = '\0';

if (tidesdb_create_column_family(db, "sorted_cf", &cf_config) != 0)
{
    return -1;
}
```

### Dropping a Column Family

By name (looks up column family internally):

```c
if (tidesdb_drop_column_family(db, "my_cf") != 0)
{
    return -1;
}
```

By pointer (skips name lookup when you already have the pointer):

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

if (tidesdb_delete_column_family(db, cf) != 0)
{
    return -1;
}
```

:::tip[Which to use]
- `tidesdb_drop_column_family(db, name)` · convenient when you only have the name
- `tidesdb_delete_column_family(db, cf)` · faster when you already hold a `tidesdb_column_family_t*`, avoids a redundant linear scan
:::

### Renaming a Column Family

Atomically rename a column family and its underlying directory. The operation drains all in-flight writes and waits for any in-progress flush or compaction to complete before renaming.

```c
if (tidesdb_rename_column_family(db, "old_name", "new_name") != 0)
{
    return -1;
}
```

**Behavior**
- Marks the column family to reject new writes during the rename
- Force-flushes the active memtable to rotate the WAL and drain in-flight transactions
- Waits unbounded for any in-progress flush or compaction to complete
- Atomically renames the column family directory on disk
- Updates all internal paths (SSTables, manifest, config)
- Clears the write rejection mark on completion or error
- Thread-safe with proper locking

**Return values**
- `TDB_SUCCESS` · Rename completed successfully
- `TDB_ERR_NOT_FOUND` · Column family with `old_name` doesn't exist
- `TDB_ERR_EXISTS` · Column family with `new_name` already exists
- `TDB_ERR_IO` · Failed to rename directory on disk

### Cloning a Column Family

Create a complete copy of an existing column family with a new name. The clone contains all the data from the source at the time of cloning.

```c
if (tidesdb_clone_column_family(db, "source_cf", "cloned_cf") != 0)
{
    return -1;
}

/* Both column families now exist independently */
tidesdb_column_family_t *original = tidesdb_get_column_family(db, "source_cf");
tidesdb_column_family_t *clone = tidesdb_get_column_family(db, "cloned_cf");
```

**Behavior**
- Flushes the source column family's memtable to ensure all data is on disk
- Waits for any in-progress flush or compaction to complete
- Copies all SSTable files (`.klog` and `.vlog`) to the new directory
- Copies manifest and configuration files
- Creates a new column family structure and loads the copied SSTables
- The clone is completely independent - modifications to one do not affect the other

**Use cases**
- Testing · Create a copy of production data for testing without affecting the original
- Branching · Create a snapshot of data before making experimental changes
- Migration · Clone data before schema or configuration changes
- Backup verification · Clone and verify data integrity without modifying the source

**Return values**
- `TDB_SUCCESS` · Clone completed successfully
- `TDB_ERR_NOT_FOUND` · Source column family doesn't exist
- `TDB_ERR_EXISTS` · Destination column family already exists
- `TDB_ERR_INVALID_ARGS` · Invalid arguments (NULL pointers or same source/destination name)
- `TDB_ERR_IO` · Failed to copy files or create directory

:::note[Clone vs Backup]
`tidesdb_clone_column_family` creates a new column family within the same database instance. For creating an external backup of the entire database, use `tidesdb_backup` instead.
:::

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
    printf("Total Keys: %" PRIu64 "\n", stats->total_keys);
    printf("Total Data Size: %" PRIu64 " bytes\n", stats->total_data_size);
    printf("Avg Key Size: %.1f bytes\n", stats->avg_key_size);
    printf("Avg Value Size: %.1f bytes\n", stats->avg_value_size);
    printf("Read Amplification: %.2f\n", stats->read_amp);
    printf("Cache Hit Rate: %.1f%%\n", stats->hit_rate * 100.0);
    
    /* Column family name is available via config */
    printf("Column Family: %s\n", stats->config->name);
    
    for (int i = 0; i < stats->num_levels; i++)
    {
        printf("Level %d: %d SSTables, %zu bytes, %" PRIu64 " keys\n", 
               i + 1, stats->level_num_sstables[i], stats->level_sizes[i],
               stats->level_key_counts[i]);
    }
    
    /* B+tree stats (only populated if use_btree=1) */
    if (stats->use_btree)
    {
        printf("B+tree Total Nodes: %" PRIu64 "\n", stats->btree_total_nodes);
        printf("B+tree Max Height: %u\n", stats->btree_max_height);
        printf("B+tree Avg Height: %.2f\n", stats->btree_avg_height);
    }

    /* Tombstone density observability */
    printf("Total Tombstones: %" PRIu64 "\n", stats->total_tombstones);
    printf("Tombstone Ratio: %.2f%%\n", stats->tombstone_ratio * 100.0);
    printf("Worst SSTable Density: %.2f%% at level %d\n",
           stats->max_sst_density * 100.0, stats->max_sst_density_level + 1);
    for (int i = 0; i < stats->num_levels; i++)
    {
        printf("Level %d tombstones: %" PRIu64 "\n", i + 1, stats->level_tombstone_counts[i]);
    }
    
    /* Access configuration */
    printf("Write Buffer Size: %zu\n", stats->config->write_buffer_size);
    printf("Compression: %d\n", stats->config->compression_algorithm);
    printf("Bloom Filter: %s\n", stats->config->enable_bloom_filter ? "enabled" : "disabled");
    
    tidesdb_free_stats(stats);
}
```

**Statistics include**

| Field | Type | Description |
|-------|------|-------------|
| `num_levels` | `int` | Number of LSM levels |
| `memtable_size` | `size_t` | Current memtable size in bytes |
| `level_sizes` | `size_t*` | Array of per-level total sizes |
| `level_num_sstables` | `int*` | Array of per-level SSTable counts |
| `level_key_counts` | `uint64_t*` | Array of per-level key counts |
| `config` | `tidesdb_column_family_config_t*` | Full column family configuration. This includes column family name if you need it! |
| `total_keys` | `uint64_t` | Total keys across memtable and all SSTables |
| `total_data_size` | `uint64_t` | Total data size (klog + vlog) in bytes |
| `avg_key_size` | `double` | Estimated average key size in bytes |
| `avg_value_size` | `double` | Estimated average value size in bytes |
| `read_amp` | `double` | Read amplification factor (point lookup cost) |
| `hit_rate` | `double` | Block cache hit rate (0.0 to 1.0) |
| `use_btree` | `int` | Whether column family uses B+tree format |
| `btree_total_nodes` | `uint64_t` | Total B+tree nodes across all SSTables |
| `btree_max_height` | `uint32_t` | Maximum tree height across all SSTables |
| `btree_avg_height` | `double` | Average tree height across all SSTables |
| `total_tombstones` | `uint64_t` | Total tombstones across all SSTables |
| `tombstone_ratio` | `double` | Database-wide tombstone count divided by entry count (0.0 to 1.0) |
| `level_tombstone_counts` | `uint64_t*` | Per-level tombstone counts |
| `max_sst_density` | `double` | Worst single-SSTable tombstone density seen |
| `max_sst_density_level` | `int` | Level index where the worst SSTable lives |

:::tip[B+tree Statistics]
The B+tree stats (`btree_total_nodes`, `btree_max_height`, `btree_avg_height`) are only populated when `use_btree=1` in the column family configuration. These provide insight into the index structure overhead and lookup depth.
:::

### Database-Level Statistics

Get aggregate statistics across the entire database instance.

```c
tidesdb_db_stats_t db_stats;
if (tidesdb_get_db_stats(db, &db_stats) == 0)
{
    printf("Column families: %d\n", db_stats.num_column_families);
    printf("Total memory: %" PRIu64 " bytes\n", db_stats.total_memory);
    printf("Resolved memory limit: %zu bytes\n", db_stats.resolved_memory_limit);
    printf("Memory pressure level: %d\n", db_stats.memory_pressure_level);
    printf("Global sequence: %" PRIu64 "\n", db_stats.global_seq);
    printf("Flush queue: %zu pending\n", db_stats.flush_queue_size);
    printf("Compaction queue: %zu pending\n", db_stats.compaction_queue_size);
    printf("Total SSTables: %d\n", db_stats.total_sstable_count);
    printf("Total data size: %" PRIu64 " bytes\n", db_stats.total_data_size_bytes);
    printf("Open SSTable handles: %d\n", db_stats.num_open_sstables);
    printf("In-flight txn memory: %" PRId64 " bytes\n", db_stats.txn_memory_bytes);
    printf("Immutable memtables: %d\n", db_stats.total_immutable_count);
    printf("Memtable bytes: %" PRId64 "\n", db_stats.total_memtable_bytes);
}
```

**Database statistics include**

| Field | Type | Description |
|-------|------|-------------|
| `num_column_families` | `int` | Number of column families |
| `total_memory` | `uint64_t` | System total memory |
| `available_memory` | `uint64_t` | System available memory at open time |
| `resolved_memory_limit` | `size_t` | Resolved memory limit (auto or configured) |
| `memory_pressure_level` | `int` | Current memory pressure (0=normal, 1=elevated, 2=high, 3=critical) |
| `flush_pending_count` | `int` | Number of pending flush operations (queued + in-flight) |
| `total_memtable_bytes` | `int64_t` | Total bytes in active memtables across all CFs |
| `total_immutable_count` | `int` | Total immutable memtables across all CFs |
| `total_sstable_count` | `int` | Total SSTables across all CFs and levels |
| `total_data_size_bytes` | `uint64_t` | Total data size (klog + vlog) across all CFs |
| `num_open_sstables` | `int` | Number of currently open SSTable file handles |
| `global_seq` | `uint64_t` | Current global sequence number |
| `txn_memory_bytes` | `int64_t` | Bytes held by in-flight transactions |
| `compaction_queue_size` | `size_t` | Number of pending compaction tasks |
| `flush_queue_size` | `size_t` | Number of pending flush tasks in queue |

:::note[Stack Allocated]
Unlike `tidesdb_get_stats` (which heap-allocates), `tidesdb_get_db_stats` fills a caller-provided struct on the stack. No free is needed.
:::

### Block Cache Statistics

Get statistics for the global block cache (shared across all column families).

```c
tidesdb_cache_stats_t cache_stats;
if (tidesdb_get_cache_stats(db, &cache_stats) == 0)
{
    if (cache_stats.enabled)
    {
        printf("Cache enabled: yes\n");
        printf("Total entries: %zu\n", cache_stats.total_entries);
        printf("Total bytes: %.2f MB\n", cache_stats.total_bytes / (1024.0 * 1024.0));
        printf("Hits: %lu\n", cache_stats.hits);
        printf("Misses: %lu\n", cache_stats.misses);
        printf("Hit rate: %.1f%%\n", cache_stats.hit_rate * 100.0);
        printf("Partitions: %zu\n", cache_stats.num_partitions);
    }
    else
    {
        printf("Cache enabled: no (block_cache_size = 0)\n");
    }
}
```

**Cache statistics include**
- `enabled` · Whether block cache is active (0 if `block_cache_size` was set to 0)
- `total_entries` · Number of cached blocks
- `total_bytes` · Total memory used by cached blocks
- `hits` · Number of cache hits (blocks served from memory)
- `misses` · Number of cache misses (blocks read from disk)
- `hit_rate` · Hit rate as a decimal (0.0 to 1.0)
- `num_partitions` · Number of cache partitions (scales with CPU cores)

:::note[Block Cache]
The block cache is a database-level resource shared across all column families. It caches raw klog block bytes (decompressed but not deserialized) to avoid repeated disk I/O. On cache hit, the block is deserialized on the fly. This yields much smaller cache entries compared to caching deserialized blocks, dramatically improving hit rates for a given cache size. Configure cache size via `config.block_cache_size` when opening the database. Set to 0 to disable caching.
:::

### Range Cost Estimation

`tidesdb_range_cost` estimates the computational cost of iterating between two keys in a column family. The returned value is an opaque double - meaningful only for comparison with other values from the same function. It uses only in-memory metadata and performs no disk I/O.

```c
int tidesdb_range_cost(tidesdb_column_family_t *cf,
                       const uint8_t *key_a, size_t key_a_size,
                       const uint8_t *key_b, size_t key_b_size,
                       double *cost);
```

**Parameters**
| Name | Type | Description |
|------|------|-------------|
| `cf` | `tidesdb_column_family_t*` | Column family to estimate cost for |
| `key_a` | `const uint8_t*` | First key (bound of range) |
| `key_a_size` | `size_t` | Size of first key |
| `key_b` | `const uint8_t*` | Second key (bound of range) |
| `key_b_size` | `size_t` | Size of second key |
| `cost` | `double*` | Output: estimated traversal cost (higher = more expensive) |

**Returns**
- `TDB_SUCCESS` on success
- `TDB_ERR_INVALID_ARGS` on bad input (NULL pointers, zero-length keys)

**Example**
```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

double cost_a = 0.0, cost_b = 0.0;

tidesdb_range_cost(cf, (uint8_t *)"user:0000", 9,
                       (uint8_t *)"user:0999", 9, &cost_a);

tidesdb_range_cost(cf, (uint8_t *)"user:1000", 9,
                       (uint8_t *)"user:1099", 9, &cost_b);

if (cost_a < cost_b)
{
    printf("Range A is cheaper to iterate\n");
}
```

**How it works**

The function walks all SSTable levels and uses in-memory metadata to estimate how many blocks and entries fall within the given key range:

- With block indexes enabled · Uses O(log B) binary search per overlapping SSTable to find the block slots containing each key bound. The block span between slots, scaled by `index_sample_ratio`, gives the estimated block count.
- Without block indexes · Falls back to byte-level key interpolation. The leading 8 bytes of each key are converted to a numeric position within the SSTable's min/max key range to estimate the fraction of blocks covered.
- B+tree SSTables (`use_btree=1`) · Uses the same key interpolation against tree node counts, plus tree height as a seek cost. Only applies to column families configured with B+tree klog format.
- Compression · Compressed SSTables receive a 1.5× weight multiplier to account for decompression overhead.
- Merge overhead · Each overlapping SSTable adds a small fixed cost for merge-heap operations.
- Memtable · The active memtable's entry count contributes a small in-memory cost.

Key order does not matter - the function normalizes the range so `key_a > key_b` produces the same result as `key_b > key_a`.

**Use cases**
- Query planning · Compare candidate key ranges to find the cheapest one to scan
- Load balancing · Distribute range scan work across threads by estimating per-range cost
- Adaptive prefetching · Decide how aggressively to prefetch based on range size
- Monitoring · Track how data distribution changes across key ranges over time

:::note[Cost Values]
The returned cost is not an absolute measure (it does not represent milliseconds, bytes, or entry counts). It is a relative scalar - only meaningful when compared with other `tidesdb_range_cost` results. A cost of 0.0 means no overlapping SSTables or memtable entries were found for the range.
:::

### Compression Algorithms

TidesDB supports multiple compression algorithms to reduce storage footprint and I/O bandwidth. Compression is applied to both klog (key-log) and vlog (value-log) blocks before writing to disk.

**Available Algorithms**

- **`TDB_COMPRESS_NONE`** · No compression (value: 0)
  - Raw data written directly to disk
  - **Use case** · Pre-compressed data, maximum write throughput, CPU-constrained environments

- **`TDB_COMPRESS_LZ4`** · LZ4 standard compression (value: 2, **default**)
  - Fast compression and decompression with good compression ratios
  - **Use case** · General purpose, balanced performance and compression
  - **Performance** · ~500 MB/s compression, ~2000 MB/s decompression (typical)

- **`TDB_COMPRESS_LZ4_FAST`** · LZ4 fast mode (value: 4)
  - Faster compression than standard LZ4 with slightly lower compression ratio
  - Uses acceleration factor of 2
  - **Use case** · Write-heavy workloads prioritizing speed over compression ratio
  - **Performance** · Higher compression throughput than standard LZ4

- **`TDB_COMPRESS_ZSTD`** · Zstandard compression (value: 3)
  - Best compression ratio with moderate speed (compression level 1)
  - **Use case** · Storage-constrained environments, archival data, read-heavy workloads
  - **Performance** · ~400 MB/s compression, ~1000 MB/s decompression (typical)

- **`TDB_COMPRESS_SNAPPY`** · Snappy compression (value: 1)
  - Fast compression with moderate compression ratios
  - **Availability** · Not available on SunOS/Illumos/OmniOS platforms
  - **Use case** · Legacy compatibility, platforms where Snappy is preferred

**Configuration Example**

```c
tidesdb_column_family_config_t cf_config = tidesdb_default_column_family_config();

/* Use LZ4 compression (default) */
cf_config.compression_algorithm = TDB_COMPRESS_LZ4;

/* Use Zstandard for better compression ratio */
cf_config.compression_algorithm = TDB_COMPRESS_ZSTD;

/* Use LZ4 fast mode for maximum write throughput */
cf_config.compression_algorithm = TDB_COMPRESS_LZ4_FAST;

/* Disable compression */
cf_config.compression_algorithm = TDB_COMPRESS_NONE;

tidesdb_create_column_family(db, "my_cf", &cf_config);
```

:::caution[Important]
Compression algorithm can be changed at runtime via `tidesdb_cf_update_runtime_config`, but the change only affects **new** SSTables. Existing SSTables retain their original compression and are decompressed correctly during reads. Compression is applied at the block level (both klog and vlog blocks).
:::
- Decompression happens automatically during reads
- Block cache stores **raw bytes** (decompressed but not deserialized) to maximize cache capacity and hit rates
- Different column families can use different compression algorithms

### B+tree KLog Format (Optional)

Column families can optionally use a B+tree structure for the key log instead of the default block-based format. The B+tree format offers faster point lookups through O(log N) tree traversal rather than linear block scanning.

**Enabling B+tree format**

```c
tidesdb_column_family_config_t cf_config = tidesdb_default_column_family_config();
cf_config.use_btree = 1;  /* Enable B+tree format */

tidesdb_create_column_family(db, "btree_cf", &cf_config);
```

**Characteristics**
- Point lookups · O(log N) tree traversal with binary search at each node, compared to potentially scanning multiple 64KB blocks in block-based format
- Range scans · Doubly-linked leaf nodes enable efficient bidirectional iteration
- Immutable · Tree is bulk-loaded from sorted memtable data during flush and never modified afterward
- Compression · Nodes compress independently using the same algorithms (LZ4, LZ4-FAST, Zstd, Snappy)
- Large values · Values meeting or exceeding `klog_value_threshold` are stored in vlog, same as block-based format
- Bloom filter · Works identically -- checked before tree traversal to skip lookups for absent keys

**When to use B+tree format**
- Read-heavy workloads with frequent point lookups
- Workloads where read latency is more important than write throughput
- Large SSTables where block scanning becomes expensive

**Tradeoffs**
- Slightly higher write amplification during flush (building tree structure)
- Larger metadata overhead per node compared to block-based format
- Block-based format may be faster for sequential scans of entire SSTables

:::caution[Important]
`use_btree` **cannot be changed** after column family creation. Different column families can use different formats (some B+tree, some block-based). Both formats support the same compression algorithms and bloom filters.
:::

**Choosing a Compression Algorithm**

| Workload | Recommended Algorithm | Rationale |
|----------|----------------------|-----------|
| General purpose | `TDB_COMPRESS_LZ4` | Best balance of speed and compression |
| Write-heavy | `TDB_COMPRESS_LZ4_FAST` | Minimize CPU overhead on writes |
| Storage-constrained | `TDB_COMPRESS_ZSTD` | Maximum compression ratio |
| Read-heavy | `TDB_COMPRESS_ZSTD` | Reduce I/O bandwidth, decompression is fast |
| Pre-compressed data | `TDB_COMPRESS_NONE` | Avoid double compression overhead |
| CPU-constrained | `TDB_COMPRESS_NONE` or `TDB_COMPRESS_LZ4_FAST` | Minimize CPU usage |

### Updating Column Family Configuration

Update runtime-safe configuration settings. Configuration changes are applied to new operations only.

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_column_family_config_t new_config = tidesdb_default_column_family_config();
new_config.write_buffer_size = 256 * 1024 * 1024;  
new_config.skip_list_max_level = 16;
new_config.skip_list_probability = 0.25f;
new_config.bloom_fpr = 0.001;       /* 0.1% false positive rate */
new_config.index_sample_ratio = 8;  /* sample 1 in 8 blocks */

int persist_to_disk = 1;            /* save to config.ini */
if (tidesdb_cf_update_runtime_config(cf, &new_config, persist_to_disk) == 0)
{
    printf("Configuration updated successfully\n");
}
```

**Updatable settings** (all applied by `tidesdb_cf_update_runtime_config`):
- `write_buffer_size` · Memtable flush threshold
- `skip_list_max_level` · Skip list level for **new** memtables
- `skip_list_probability` · Skip list probability for **new** memtables
- `bloom_fpr` · False positive rate for **new** SSTables
- `enable_bloom_filter` · Enable/disable bloom filters for **new** SSTables
- `enable_block_indexes` · Enable/disable block indexes for **new** SSTables
- `block_index_prefix_len` · Block index prefix length for **new** SSTables
- `index_sample_ratio` · Index sampling ratio for **new** SSTables
- `compression_algorithm` · Compression for **new** SSTables (existing SSTables retain their original compression)
- `klog_value_threshold` · Value log threshold for **new** writes
- `sync_mode` · Durability mode (TDB_SYNC_NONE, TDB_SYNC_INTERVAL, or TDB_SYNC_FULL). Also updates the active WAL's sync mode immediately.
- `sync_interval_us` · Sync interval in microseconds (only used when sync_mode is TDB_SYNC_INTERVAL)
- `level_size_ratio` · LSM level sizing (DCA recalculates capacities dynamically)
- `min_levels` · Minimum LSM levels
- `dividing_level_offset` · Compaction dividing level offset
- `l1_file_count_trigger` · L1 file count compaction trigger
- `l0_queue_stall_threshold` · Backpressure stall threshold
- `default_isolation_level` · Default transaction isolation level
- `min_disk_space` · Minimum disk space required
- `commit_hook_fn` / `commit_hook_ctx` · Commit hook callback and context

**Non-updatable settings** (not modified by this function):
- `comparator_name` · Cannot change sort order after creation (would corrupt key ordering in existing SSTables)
- `use_btree` · Cannot change klog format after creation (existing SSTables use the original format)

:::note[Backpressure Defaults]
The default `l0_queue_stall_threshold` is 20. The default `l1_file_count_trigger` is 4.
:::

**Configuration persistence**

If `persist_to_disk = 1`, changes are saved to `config.ini` in the column family directory. On restart, the configuration is loaded from this file.

```c
/* Save configuration to custom INI file */
tidesdb_cf_config_save_to_ini("custom_config.ini", "my_cf", &new_config);

/* Load configuration from INI file */
tidesdb_column_family_config_t loaded_config;
if (tidesdb_cf_config_load_from_ini("custom_config.ini", "my_cf", &loaded_config) == 0)
{
    printf("Configuration loaded successfully\n");
}
```

:::tip[Important Notes]
Changes apply immediately to new operations. Existing SSTables and memtables retain their original settings. The update operation is thread-safe.
:::

### Commit Hook (Change Data Capture)

`tidesdb_cf_set_commit_hook` registers an optional callback that fires synchronously after every transaction commit on a column family. The hook receives the full batch of committed operations atomically, enabling real-time change data capture without WAL parsing or external log consumers.

```c
int tidesdb_cf_set_commit_hook(tidesdb_column_family_t *cf,
                                tidesdb_commit_hook_fn fn,
                                void *ctx);
```

**Parameters**
| Name | Type | Description |
|------|------|-------------|
| `cf` | `tidesdb_column_family_t*` | Column family handle |
| `fn` | `tidesdb_commit_hook_fn` | Commit hook callback (or `NULL` to disable) |
| `ctx` | `void*` | User-provided context passed to the callback |

**Returns**
- `TDB_SUCCESS` on success
- `TDB_ERR_INVALID_ARGS` if `cf` is NULL

**Callback signature**

```c
typedef int (*tidesdb_commit_hook_fn)(const tidesdb_commit_op_t *ops, int num_ops,
                                      uint64_t commit_seq, void *ctx);
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `ops` | `const tidesdb_commit_op_t*` | Array of committed operations (valid only during callback) |
| `num_ops` | `int` | Number of operations in the array |
| `commit_seq` | `uint64_t` | Monotonic commit sequence number |
| `ctx` | `void*` | User-provided context pointer |

The callback returns `0` on success. A non-zero return is logged as a warning but does not roll back the commit.

**Operation struct**

```c
typedef struct tidesdb_commit_op_t
{
    const uint8_t *key;
    size_t key_size;
    const uint8_t *value;      /* NULL for deletes */
    size_t value_size;         /* 0 for deletes */
    time_t ttl;
    int is_delete;             /* 1 for delete, 0 for put */
} tidesdb_commit_op_t;
```

**Example (replication sink)**
```c
typedef struct
{
    int socket_fd;
    uint8_t *send_buf;
    size_t buf_size;
} replication_ctx_t;

static int replication_hook(const tidesdb_commit_op_t *ops, int num_ops,
                            uint64_t commit_seq, void *ctx)
{
    replication_ctx_t *rctx = (replication_ctx_t *)ctx;
    for (int i = 0; i < num_ops; i++)
    {
        /* Serialize and send each op to replica */
        send_to_replica(rctx->socket_fd, commit_seq, &ops[i]);
    }
    return 0;
}

/* Attach hook at runtime */
replication_ctx_t rctx = { .socket_fd = replica_fd };
tidesdb_cf_set_commit_hook(cf, replication_hook, &rctx);

/* Normal writes now trigger the hook automatically */
tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin(db, &txn);
tidesdb_txn_put(txn, cf, key, key_size, value, value_size, -1);
tidesdb_txn_commit(txn);  /* replication_hook fires here */
tidesdb_txn_free(txn);

/* Detach hook */
tidesdb_cf_set_commit_hook(cf, NULL, NULL);
```

**Setting hook via config at creation time**
```c
tidesdb_column_family_config_t cf_config = tidesdb_default_column_family_config();
cf_config.commit_hook_fn = replication_hook;
cf_config.commit_hook_ctx = &rctx;

tidesdb_create_column_family(db, "replicated_cf", &cf_config);
```

**Behavior**
- The hook fires after WAL write, memtable apply, and commit status marking are complete - the data is fully durable before the callback runs
- Hook failure (non-zero return) is logged but does not affect the commit result
- Each column family has its own independent hook; a multi-CF transaction fires the hook once per CF with only that CF's operations
- `commit_seq` is monotonically increasing across commits and can be used as a replication cursor
- Pointers in `tidesdb_commit_op_t` are valid only during the callback invocation - copy any data you need to retain
- The hook executes synchronously on the committing thread; keep the callback fast to avoid stalling writers
- Setting the hook to `NULL` disables it immediately with no restart required

**Use cases**
- Replication · Ship committed batches to replicas in commit order
- Event streaming · Publish mutations to Kafka, NATS, or any message broker
- Secondary indexing · Maintain a reverse index or materialized view
- Audit logging · Record every mutation with key, value, TTL, and sequence number
- Debugging · Attach a temporary hook in production to inspect live writes

:::note[Runtime-Only]
The `commit_hook_fn` and `commit_hook_ctx` fields are not persisted to `config.ini`. After a database restart, hooks must be re-registered by the application. This is by design - function pointers cannot be serialized.
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
time_t ttl = -1;

time_t ttl = time(NULL) + (5 * 60);

time_t ttl = time(NULL) + (60 * 60);

time_t ttl = 1730592000;
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

### Single-Delete

`tidesdb_txn_single_delete` writes a tombstone with the same read semantics as `tidesdb_txn_delete`, but carries a caller-provided promise that lets compaction drop the put and the tombstone together as soon as both appear in the same merge input, rather than carrying the tombstone forward until it reaches the largest active level.

Between any two single-deletes on the same key, and between the start of the key's history and its first single-delete, the key has been put **at most once**. The engine does not and cannot verify this at runtime; violating the contract can leave older puts visible after the single-delete and is a bug in the caller.

This is the right choice for workloads that insert each key exactly once and then delete it exactly once (classic insert-benchmark patterns, secondary-index entries on columns that are never updated, log-style tables with scheduled purges). It is **not** safe for tables that issue repeated updates to the same key.

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin(db, &txn);

const uint8_t *key = (uint8_t *)"mykey";
tidesdb_txn_single_delete(txn, cf, key, 5);

tidesdb_txn_commit(txn);
tidesdb_txn_free(txn);
```

Signature:

```c
int tidesdb_txn_single_delete(tidesdb_txn_t *txn,
                              tidesdb_column_family_t *cf,
                              const uint8_t *key,
                              size_t key_size);
```

Returns `TDB_SUCCESS` on success or a negative error code on failure. When in doubt, prefer `tidesdb_txn_delete`.

### Multi-Operation Transaction

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin(db, &txn);

tidesdb_txn_put(txn, cf, (uint8_t *)"key1", 4, (uint8_t *)"value1", 6, -1);
tidesdb_txn_put(txn, cf, (uint8_t *)"key2", 4, (uint8_t *)"value2", 6, -1);
tidesdb_txn_delete(txn, cf, (uint8_t *)"old_key", 7);

/* Commit atomically -- all or nothing */
if (tidesdb_txn_commit(txn) != 0)
{
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

tidesdb_txn_rollback(txn);
tidesdb_txn_free(txn);
```

### Transaction Reset

`tidesdb_txn_reset` resets a committed or aborted transaction for reuse with a new isolation level. This avoids the overhead of freeing and reallocating transaction resources in hot loops.

```c
int tidesdb_txn_reset(tidesdb_txn_t *txn, tidesdb_isolation_level_t isolation);
```

**Parameters**
| Name | Type | Description |
|------|------|-------------|
| `txn` | `tidesdb_txn_t*` | Transaction handle (must be committed or aborted) |
| `isolation` | `tidesdb_isolation_level_t` | New isolation level for the reset transaction |

**Returns**
- `TDB_SUCCESS` on success
- `TDB_ERR_INVALID_ARGS` if txn is NULL, still active (not committed/aborted), or isolation level is invalid

**Example**
```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin(db, &txn);

tidesdb_txn_put(txn, cf, (uint8_t *)"key1", 4, (uint8_t *)"value1", 6, -1);
tidesdb_txn_commit(txn);

tidesdb_txn_reset(txn, TDB_ISOLATION_READ_COMMITTED);

tidesdb_txn_put(txn, cf, (uint8_t *)"key2", 4, (uint8_t *)"value2", 6, -1);
tidesdb_txn_commit(txn);

tidesdb_txn_free(txn);
```

**Behavior**
- The transaction must be committed or aborted before reset; resetting an active transaction returns `TDB_ERR_INVALID_ARGS`
- Internal buffers (ops array, read set arrays, arena pointer array, column family array, savepoints array) are retained to avoid reallocation
- Per-operation key/value data, arena buffers, hash tables, and savepoint children are freed
- A fresh `txn_id` and `snapshot_seq` are assigned based on the new isolation level
- The isolation level can be changed on each reset (e.g., `READ_COMMITTED` -> `REPEATABLE_READ`)
- If switching to an isolation level that requires read tracking (`REPEATABLE_READ` or `SERIALIZABLE`), read set arrays are allocated automatically
- SERIALIZABLE transactions are correctly unregistered from and re-registered to the active transaction list

**When to use**
- Batch processing · Reuse a single transaction across many commit cycles in a loop
- Connection pooling · Reset a transaction for a new request without reallocation
- High-throughput ingestion · Reduce malloc/free overhead in tight write loops

:::tip[Reset vs Free + Begin]
For a single transaction, `tidesdb_txn_reset` is functionally equivalent to calling `tidesdb_txn_free` followed by `tidesdb_txn_begin_with_isolation`. The difference is performance, reset retains allocated buffers and avoids repeated allocation overhead. This matters most in loops that commit and restart thousands of transactions.
:::

### Savepoints

Savepoints allow partial rollback within a transaction. You can create named savepoints and rollback to them without aborting the entire transaction.

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin(db, &txn);

tidesdb_txn_put(txn, cf, (uint8_t *)"key1", 4, (uint8_t *)"value1", 6, -1);

if (tidesdb_txn_savepoint(txn, "sp1") != 0)
{
    tidesdb_txn_rollback(txn);
    tidesdb_txn_free(txn);
    return -1;
}

tidesdb_txn_put(txn, cf, (uint8_t *)"key2", 4, (uint8_t *)"value2", 6, -1);

if (tidesdb_txn_rollback_to_savepoint(txn, "sp1") != 0)
{
    tidesdb_txn_rollback(txn);
    tidesdb_txn_free(txn);
    return -1;
}

tidesdb_txn_put(txn, cf, (uint8_t *)"key3", 4, (uint8_t *)"value3", 6, -1);

if (tidesdb_txn_commit(txn) != 0)
{
    tidesdb_txn_free(txn);
    return -1;
}

tidesdb_txn_free(txn);
```

**Savepoint API**
- `tidesdb_txn_savepoint(txn, "name")` · Create a savepoint
- `tidesdb_txn_rollback_to_savepoint(txn, "name")` · Rollback to savepoint
- `tidesdb_txn_release_savepoint(txn, "name")` · Release savepoint without rolling back

**Savepoint behavior**
- Savepoints capture the transaction state at a specific point
- Rolling back to a savepoint discards all operations after that savepoint
- Releasing a savepoint frees its resources without rolling back
- Multiple savepoints can be created with different names
- Creating a savepoint with an existing name updates that savepoint
- Savepoints are automatically freed when the transaction commits or rolls back
- Returns `TDB_ERR_NOT_FOUND` if the savepoint name doesn't exist

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

tidesdb_txn_put(txn, users_cf, (uint8_t *)"user:1000", 9, 
                (uint8_t *)"John Doe", 8, -1);

tidesdb_txn_put(txn, orders_cf, (uint8_t *)"order:5000", 10,
                (uint8_t *)"user:1000|product:A", 19, -1);

if (tidesdb_txn_commit(txn) != 0)
{
    tidesdb_txn_free(txn);
    return -1;
}

tidesdb_txn_free(txn);
```

**Multi-CF guarantees**
- Either all CFs commit or none do (atomic)
- Automatically detected when operations span multiple CFs
- Uses global sequence numbers for atomic ordering
- Each CF's WAL receives operations with the same commit sequence number
- No two-phase commit or coordinator overhead

### Isolation Levels

TidesDB supports five MVCC isolation levels for fine-grained concurrency control.

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

tidesdb_txn_t *txn = NULL;

tidesdb_txn_begin_with_isolation(db, TDB_ISOLATION_READ_UNCOMMITTED, &txn);
tidesdb_txn_begin_with_isolation(db, TDB_ISOLATION_READ_COMMITTED, &txn);
tidesdb_txn_begin_with_isolation(db, TDB_ISOLATION_REPEATABLE_READ, &txn);
tidesdb_txn_begin_with_isolation(db, TDB_ISOLATION_SNAPSHOT, &txn);
tidesdb_txn_begin_with_isolation(db, TDB_ISOLATION_SERIALIZABLE, &txn);

tidesdb_txn_put(txn, cf, (uint8_t *)"key", 3, (uint8_t *)"value", 5, -1);

int result = tidesdb_txn_commit(txn);
if (result == TDB_ERR_CONFLICT)
{
    tidesdb_txn_free(txn);
    return -1;
}

tidesdb_txn_free(txn);
```

**Isolation level characteristics**
- READ UNCOMMITTED · Maximum concurrency, minimal consistency
- READ COMMITTED · Balanced for OLTP workloads (default)
- REPEATABLE READ · Strong point read consistency
- SNAPSHOT · First-committer-wins with write-write conflict detection only (allows write skew)
- SERIALIZABLE · Strongest guarantees with full SSI (read-write + write-write + dangerous structure detection), higher abort rates

## Iterators

Iterators provide efficient forward and backward traversal over key-value pairs.

:::caution[Memory Ownership]
The key and value pointers returned by `tidesdb_iter_key()` and `tidesdb_iter_value()` are **internal pointers owned by the iterator**. Do **NOT** free them. They remain valid until the next `tidesdb_iter_next()`, `tidesdb_iter_prev()`, seek operation, or `tidesdb_iter_free()` call. If you need to retain the data beyond the current iteration step, copy it to your own buffer.
:::

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
    tidesdb_iter_prev(iter);
}

tidesdb_iter_free(iter);
tidesdb_txn_free(txn);
```

### Iterator Seek Operations

TidesDB provides seek operations that allow you to position an iterator at a specific key or key range without scanning from the beginning.

**How Seek Works**

**With Block Indexes Enabled** (`enable_block_indexes = 1`):
- Uses compact block index with parallel arrays (min/max key prefixes and file positions)
- Binary search through sampled keys at configurable ratio (default 1:1 via `index_sample_ratio`, meaning every block is indexed)
- Jumps directly to the target block using the file position
- Scans forward from that block to find the exact key
- **Performance** · O(log n) binary search + O(k) entries per block scan

Block indexes provide dramatic speedup for large SSTables at the cost of ~2-5% storage overhead for the compact index structure (parallel arrays with delta-encoded file positions).

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

#### Prefix Seeking

Since `tidesdb_iter_seek` positions the iterator at the first key >= target, you can use a prefix as the seek target to efficiently scan all keys sharing that prefix:

```c
/* Seek to prefix and iterate all matching keys */
const char *prefix = "user:";
if (tidesdb_iter_seek(iter, (uint8_t *)prefix, strlen(prefix) + 1) == 0)
{
    while (tidesdb_iter_valid(iter))
    {
        uint8_t *key = NULL;
        size_t key_size = 0;
        tidesdb_iter_key(iter, &key, &key_size);
        
        /* Stop when keys no longer match prefix */
        if (strncmp((char *)key, prefix, strlen(prefix)) != 0) break;
        
        /* Process key */
        printf("Found: %.*s\n", (int)key_size, key);
        
        if (tidesdb_iter_next(iter) != TDB_SUCCESS) break;
    }
}
```

This pattern works across both memtables and SSTables. When block indexes are enabled, the seek operation uses binary search to jump directly to the relevant block, making prefix scans efficient even on large datasets.

## Custom Comparators

TidesDB uses comparators to determine the sort order of keys throughout the entire system, memtables, SSTables, block indexes, and iterators all use the same comparison logic. Once a comparator is set for a column family, it **cannot be changed** without corrupting data.

### Built-in Comparators

TidesDB provides six built-in comparators that are automatically registered on database open:

**`"memcmp"` (default)** · Binary byte-by-byte comparison
- Compares min(key1_size, key2_size) bytes using `memcmp()`
- If bytes are equal, shorter key sorts first
- **Use case** · Binary keys, raw byte data, general purpose

**`"lexicographic"`** · Null-terminated string comparison
- Uses `strcmp()` for lexicographic ordering
- Ignores key_size parameters (assumes null-terminated)
- **Use case** · C strings, text keys
- **Warning** · Keys must be null-terminated or behavior is undefined

**`"uint64"`** · Unsigned 64-bit integer comparison
- Interprets 8-byte keys as uint64_t values
- Falls back to memcmp if key_size != 8
- **Use case** · Numeric IDs, timestamps, counters
- **Example** · `uint64_t id = 1000; tidesdb_txn_put(txn, cf, (uint8_t*)&id, 8, ...)`

**`"int64"`** · Signed 64-bit integer comparison
- Interprets 8-byte keys as int64_t values
- Falls back to memcmp if key_size != 8
- **Use case** · Signed numeric keys, relative timestamps
- **Example** · `int64_t offset = -500; tidesdb_txn_put(txn, cf, (uint8_t*)&offset, 8, ...)`

**`"reverse"`** · Reverse binary comparison
- Negates the result of memcmp comparator
- Sorts keys in descending order
- **Use case** · Reverse chronological order, descending IDs

**`"case_insensitive"`** · Case-insensitive ASCII comparison
- Converts A-Z to a-z during comparison
- Compares min(key1_size, key2_size) bytes
- If bytes are equal (ignoring case), shorter key sorts first
- **Use case** · Case-insensitive text keys, usernames, email addresses

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

### Retrieving a Registered Comparator

Use `tidesdb_get_comparator` to retrieve a previously registered comparator by name:

```c
tidesdb_comparator_fn fn = NULL;
void *ctx = NULL;

if (tidesdb_get_comparator(db, "timestamp_desc", &fn, &ctx) == 0)
{
    /* Comparator found - fn and ctx are now populated */
    printf("Comparator 'timestamp_desc' is registered\n");
}
else
{
    /* Comparator not found */
    printf("Comparator not registered\n");
}
```

**Use cases**
- Validation · Check if a comparator is registered before creating a column family
- Debugging · Verify comparator registration during development
- Dynamic configuration · Query available comparators at runtime

**Comparator function signature**
```c
int (*comparator_fn)(const uint8_t *key1, size_t key1_size,
                     const uint8_t *key2, size_t key2_size,
                     void *ctx);
```

**Return values**
- `< 0` if key1 < key2
- `0` if key1 == key2
- `> 0` if key1 > key2

:::caution[Important]
Comparators must be **registered before** creating column families that use them. Once set, a comparator **cannot be changed** for a column family. The same comparator is used across memtables, SSTables, block indexes, and iterators.
:::
- Custom comparators can use the `ctx` parameter for runtime configuration


## Sync Modes

Control durability vs performance tradeoff with three sync modes.

```c
tidesdb_column_family_config_t cf_config = tidesdb_default_column_family_config();

/* TDB_SYNC_NONE     -- Fastest, least durable (OS handles flushing) */
cf_config.sync_mode = TDB_SYNC_NONE;

/* TDB_SYNC_INTERVAL -- Balanced performance with periodic background syncing */
cf_config.sync_mode = TDB_SYNC_INTERVAL;
cf_config.sync_interval_us = 128000;  /* Sync every 128ms (default) */

/* TDB_SYNC_FULL     -- Most durable (fsync on every write) */
cf_config.sync_mode = TDB_SYNC_FULL;

tidesdb_create_column_family(db, "my_cf", &cf_config);
```

:::note[Sync Mode Options]
- **TDB_SYNC_NONE** · No explicit sync, relies on OS page cache (fastest, least durable)
    - Best for · Maximum throughput, acceptable data loss on crash
    - Use case · Caches, temporary data, reproducible workloads

- **TDB_SYNC_INTERVAL** · Periodic background syncing at configurable intervals (balanced)
    - Best for · Production workloads requiring good performance with bounded data loss
    - Use case · Most applications, configurable durability window
    - Features:
        - Single background sync thread monitors all column families using interval mode
        - Configurable sync interval via `sync_interval_us` (microseconds)
        - Structural operations (flush, compaction, WAL rotation) always enforce durability
        - At most `sync_interval_us` worth of data at risk on crash
        - Mid-durability correctness - When memtables rotate, the WAL receives an escalated fsync before entering the flush queue. Sorted run creation and merge operations always propagate full sync to block managers regardless of sync mode.

- **TDB_SYNC_FULL** · Fsync on every write operation (slowest, most durable)
    - Best for · Critical data requiring maximum durability
    - Use case · Financial transactions, audit logs, critical metadata
    - Structural operations always use fsync regardless of sync mode
      :::

### Sync Interval Examples

```c
/* Sync every 100ms (good for low-latency requirements) */
cf_config.sync_mode = TDB_SYNC_INTERVAL;
cf_config.sync_interval_us = 100000;

/* Sync every 128ms (default) */
cf_config.sync_mode = TDB_SYNC_INTERVAL;
cf_config.sync_interval_us = 128000;

/* Sync every 1 second (higher throughput, more data at risk) */
cf_config.sync_mode = TDB_SYNC_INTERVAL;
cf_config.sync_interval_us = 1000000;
```

### Manual WAL Sync

`tidesdb_sync_wal` forces an immediate fsync of the active write-ahead log for a column family. This is useful for explicit durability control when using `TDB_SYNC_NONE` or `TDB_SYNC_INTERVAL` modes.

```c
int tidesdb_sync_wal(tidesdb_column_family_t *cf);
```

**Parameters**
| Name | Type | Description |
|------|------|-------------|
| `cf` | `tidesdb_column_family_t*` | Column family handle |

**Returns**
- `TDB_SUCCESS` on success
- `TDB_ERR_INVALID_ARGS` if `cf` is NULL or has no associated database
- `TDB_ERR_IO` if the fsync operation fails

**Example**
```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

/* Force WAL durability after a batch of writes */
if (tidesdb_sync_wal(cf) != 0)
{
    fprintf(stderr, "WAL sync failed\n");
}
```

**When to use**
- Application-controlled durability · Sync the WAL at specific points (e.g., after a batch of related writes) when using `TDB_SYNC_NONE` or `TDB_SYNC_INTERVAL`
- Pre-checkpoint · Ensure all buffered WAL data is on disk before taking a checkpoint
- Graceful shutdown · Flush WAL buffers before closing the database
- Critical writes · Force durability for specific high-value writes without using `TDB_SYNC_FULL` for all writes

**Behavior**
- Acquires a reference to the active memtable to safely access its WAL
- Calls `fdatasync` on the WAL file descriptor
- Thread-safe - can be called concurrently from multiple threads
- If the memtable rotates during the call, retries with the new active memtable

:::tip[Structural Operations]
Regardless of sync mode, TidesDB **always** enforces durability for structural operations:
- Memtable flush to SSTable
- SSTable compaction and merging
- WAL rotation
- Column family metadata updates

This ensures the database structure remains consistent even if user data syncing is delayed.
:::

## Compaction

TidesDB performs automatic background compaction when L1 reaches the configured file count trigger (default: 4 SSTables). However, you can manually trigger compaction for specific scenarios.

### Checking Flush/Compaction Status

Check if a column family currently has flush or compaction operations in progress.

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

/* Check if flushing is in progress */
if (tidesdb_is_flushing(cf))
{
    printf("Flush in progress\n");
}

/* Check if compaction is in progress */
if (tidesdb_is_compacting(cf))
{
    printf("Compaction in progress\n");
}
```

**Use cases**
- Graceful shutdown · Wait for background operations to complete before closing
- Maintenance windows · Check if operations are running before triggering manual compaction
- Monitoring · Track background operation status for observability
- Testing · Verify flush/compaction behavior in unit tests

**Return values**
- `1` · Operation is in progress
- `0` · No operation in progress (or invalid column family)

### Manual Flush

Manually flush a column family's memtable to disk. This creates a new SSTable (sorted run) in level 1.

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

/* Trigger flush manually */
if (tidesdb_flush_memtable(cf) != 0)
{
    fprintf(stderr, "Failed to trigger flush\n");
    return -1;
}
```

**When to use manual flush**
- Before backup · Ensure all in-memory data is persisted before taking a backup
- Memory pressure · Force data to disk when memory usage is high
- Testing · Verify SSTable creation and compaction behavior
- Graceful shutdown · Flush pending data before closing the database

**Behavior**
- Rotates the column family's active memtable and enqueues the rotated memtable for flush regardless of its current size (no write-buffer threshold gate)
- In unified-memtable mode the shared memtable is rotated through the unified flush path, so the call behaves the same whether the database is in per-CF or unified-memtable mode
- Returns immediately (non-blocking) -- flush runs asynchronously in background threads
- If flush is already running for the column family, the call succeeds but doesn't queue duplicate work
- Thread-safe -- can be called concurrently from multiple threads

### Manual Compaction

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

/* Trigger compaction manually */
if (tidesdb_compact(cf) != 0)
{
    fprintf(stderr, "Failed to trigger compaction\n");
    return -1;
}
```

**When to use manual compaction**

- After bulk deletes · Reclaim disk space by removing tombstones and obsolete versions
- After bulk updates · Consolidate multiple versions of keys into single entries
- Before read-heavy workloads · Optimize read performance by reducing the number of levels to search
- During maintenance windows · Proactively compact during low-traffic periods to avoid compaction during peak load
- After TTL expiration · Remove expired entries to reclaim storage
- Space optimization · Force compaction to reduce space amplification when storage is constrained

**Behavior**

- Enqueues compaction work in the global compaction thread pool
- Returns immediately (non-blocking) -- compaction runs asynchronously in background threads
- If compaction is already running for the column family, the call succeeds but doesn't queue duplicate work
- Compaction merges SSTables across levels, removes tombstones, expired TTL entries, and obsolete versions
- Thread-safe -- can be called concurrently from multiple threads

**Performance considerations**

- Manual compaction uses the same thread pool as automatic background compaction
- Configure thread pool size via `config.num_compaction_threads` (default: 2)
- Compaction is I/O intensive -- avoid triggering during peak write workloads
- Multiple column families can compact in parallel up to the thread pool limit

See [How does TidesDB work?](/getting-started/how-does-tidesdb-work#6-compaction-policy) for details on compaction algorithms, merge strategies, and parallel compaction.

### Targeted Range Compaction

`tidesdb_compact_range` runs a synchronous compaction over a specific key range. Only SSTables whose minimum and maximum keys overlap the requested range participate in the merge, so the work and I/O are bounded to the affected portion of the LSM tree rather than the whole column family.

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

const uint8_t start[] = "tenant_42:";
const uint8_t end[]   = "tenant_42;";

if (tidesdb_compact_range(cf, start, sizeof(start) - 1, end, sizeof(end) - 1) != 0)
{
    fprintf(stderr, "Targeted compaction failed\n");
    return -1;
}
```

**When to use**

- Bulk reclaim after a large range delete, where waiting for natural compaction would leave tombstones and obsolete versions on disk
- Tenant eviction or sliding-window expiration that does not fit TTL semantics
- Post-import cleanup of a known key range loaded with `tidesdb_txn_put` followed by `tidesdb_txn_delete`
- Operational counterpart to the automatic tombstone density trigger when an operator wants reclaim now rather than at the next natural threshold crossing

**Behavior**

- Synchronous, blocks the caller until the merge commits or fails
- Does not enqueue work onto the compaction thread pool, the calling thread does the work
- Selects only SSTables whose key range overlaps the requested range using the column family's comparator, SSTables outside the range are not touched
- Applies the same emit-loop logic as background compactions (tombstone reclamation rules, single-delete pair cancellation, sequence-based deduplication, value recompression)
- Output SSTables are committed to the manifest atomically and old inputs are marked for deletion

**Return values**

- `TDB_SUCCESS` on success
- `TDB_ERR_INVALID_ARGS` if `cf` or either key pointer is NULL, or sizes are zero
- Standard I/O and memory error codes if the merge cannot complete

### Purge Column Family

`tidesdb_purge_cf` forces a synchronous flush and aggressive compaction for a single column family. Unlike `tidesdb_flush_memtable` and `tidesdb_compact` (which are non-blocking), purge blocks until all flush and compaction I/O is complete.

```c
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
if (!cf) return -1;

if (tidesdb_purge_cf(cf) != 0)
{
    fprintf(stderr, "Purge failed\n");
    return -1;
}
/* All data is now flushed to SSTables and compacted */
```

**Behavior**
1. If unified memtable mode is enabled, rotates the unified memtable and waits for the flush to complete so that entries belonging to this CF are moved to SSTables
2. Waits for any in-progress flush to complete
3. Force-flushes the active per-CF memtable (even if below threshold)
4. Waits for flush I/O to fully complete
5. Waits for any in-progress compaction to complete
6. Triggers synchronous compaction inline (bypasses the compaction queue)
7. Waits for any queued compaction to drain

**When to use**
- Before backup or checkpoint · Ensure all data is on disk and compacted
- After bulk deletes · Reclaim space immediately by compacting away tombstones
- Manual maintenance · Force a clean state during a maintenance window
- Pre-shutdown · Ensure all pending work is complete before closing

**Return values**
- `TDB_SUCCESS` on success
- `TDB_ERR_INVALID_ARGS` if `cf` is NULL or has no associated database

### Purge Database

`tidesdb_purge` forces a synchronous flush and aggressive compaction for **all** column families, then drains both the global flush and compaction queues.

```c
if (tidesdb_purge(db) != 0)
{
    fprintf(stderr, "Database purge failed\n");
}
/* All CFs flushed and compacted, all queues drained */
```

**Behavior**
1. If unified memtable mode is enabled, rotates and flushes the unified memtable then waits for the flush to complete
2. Calls `tidesdb_purge_cf` on each column family
3. Drains the global flush queue (waits for queue size and pending count to reach 0)
4. Drains the global compaction queue (waits for queue size to reach 0)

**Return values**
- `TDB_SUCCESS` if all column families purged successfully
- First non-zero error code if any CF fails (continues processing remaining CFs)
- `TDB_ERR_INVALID_ARGS` if `db` is NULL

:::tip[Purge vs Manual Flush + Compact]
`tidesdb_flush_memtable` and `tidesdb_compact` are non-blocking - they enqueue work and return immediately. `tidesdb_purge_cf` and `tidesdb_purge` are synchronous - they block until all work is complete. Use purge when you need a guarantee that all data is on disk and compacted before proceeding.
:::

## Thread Pools

TidesDB uses separate thread pools for flush and compaction operations. Understanding the parallelism model is important for optimal configuration.

**Parallelism semantics**
- Cross-CF parallelism · Multiple flush/compaction workers CAN process different column families in parallel
- Intra-CF flush parallelism · A single column family can have multiple memtables flushing concurrently up to the global `max_concurrent_flushes` cap, so a hot CF drains its immutable queue at the speed of the worker pool rather than serially
- Within-CF compaction serialization · Compaction is still one-per-CF (enforced by the atomic `is_compacting` flag) so level invariants and manifest ordering stay consistent
- Global flush semaphore · `max_concurrent_flushes` (default 4) caps total in-flight flushes across all CFs combined, so deployments with many column families bound transient memory and queue depth

**Thread pool sizing guidance**
- Single column family with sustained write pressure · Increase `num_flush_threads` toward `max_concurrent_flushes` to drain the immutable queue faster, since multiple flushes per CF are now allowed
- Multiple column families · Set flush thread counts up to `min(num_cfs, max_concurrent_flushes)` and compaction thread counts up to the number of column families for maximum parallelism

**Configuration**
```c
tidesdb_config_t config = {
    .db_path = "./mydb",
    .num_flush_threads = 2,                /* Flush thread pool size (default: 2) */
    .num_compaction_threads = 2,           /* Compaction thread pool size (default: 2) */
    .max_concurrent_flushes = 4,           /* Global cap on in-flight flushes (default: 4) */
    .log_level = TDB_LOG_INFO,
    .block_cache_size = 64 * 1024 * 1024,  /* 64MB global block cache (default: 64MB) */
    .max_open_sstables = 256,              /* LRU cache for SSTable objects (default: 256, each has 2 FDs) */
};

tidesdb_t *db = NULL;
tidesdb_open(&config, &db);
```

:::note
`max_open_sstables` is a **storage-engine-level** configuration, not a column family configuration. It controls the LRU cache size for SSTable structures. Each SSTable uses 2 file descriptors (klog + vlog), so 256 SSTables = 512 file descriptors.
:::

See [How does TidesDB work?](/getting-started/how-does-tidesdb-work#75-thread-pool-architecture) for details on thread pool architecture and work distribution.

## Unified Memtable

By default, each column family maintains its own skip list and WAL. A transaction touching N column families performs N WAL writes. Unified memtable mode replaces all per-CF skip lists and WALs with a single shared skip list and a single WAL at the database level, reducing N WAL writes per transaction to exactly one.

### Enabling Unified Memtable

```c
tidesdb_config_t config = tidesdb_default_config();
config.db_path = "./mydb";
config.unified_memtable = 1;  /* Enable unified memtable mode */

tidesdb_t *db = NULL;
if (tidesdb_open(&config, &db) != 0)
{
    return -1;
}
```

**With custom configuration**

```c
tidesdb_config_t config = tidesdb_default_config();
config.db_path = "./mydb";
config.unified_memtable = 1;
config.unified_memtable_write_buffer_size = 128 * 1024 * 1024;  /* 128MB unified write buffer */
config.unified_memtable_skip_list_max_level = 16;               /* Higher max level for larger datasets */
config.unified_memtable_skip_list_probability = 0.25f;          /* Default probability */
config.unified_memtable_sync_mode = TDB_SYNC_FULL;              /* Fsync on every WAL write */

tidesdb_t *db = NULL;
if (tidesdb_open(&config, &db) != 0)
{
    return -1;
}
```

### Configuration Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `unified_memtable` | `int` | `0` | Enable unified memtable mode (0 = per-CF, 1 = unified) |
| `unified_memtable_write_buffer_size` | `size_t` | `0` (auto) | Write buffer size for unified memtable. 0 = `TDB_DEFAULT_WRITE_BUFFER_SIZE` (64MB) |
| `unified_memtable_skip_list_max_level` | `int` | `0` (auto) | Skip list max level. 0 = default 12 |
| `unified_memtable_skip_list_probability` | `float` | `0` (auto) | Skip list probability. 0 = default 0.25 |
| `unified_memtable_sync_mode` | `int` | `0` | WAL sync mode (`TDB_SYNC_NONE`, `TDB_SYNC_FULL`, `TDB_SYNC_INTERVAL`) |
| `unified_memtable_sync_interval_us` | `uint64_t` | `0` | Sync interval in microseconds (only for `TDB_SYNC_INTERVAL`) |

### How It Works

All column families write into a single shared skip list and a single WAL file. Keys in the unified skip list are prefixed with a 4-byte big-endian column family index to maintain isolation between column families.

**Write path** · At transaction commit, all operations across all column families are serialized into a single WAL batch and written as one block. Operations are then applied to the unified skip list with prefixed keys. A transaction touching 5 column families results in 1 WAL write instead of 5.

**Read path** · Reads construct the prefixed key (4-byte CF index + user key) and search the unified active skip list, then unified immutable memtables (newest to oldest), then fall back to per-CF SSTables on disk. Keys from other column families are never visible.

**Flush** · When the unified memtable exceeds the write buffer, a flush worker iterates it in sorted order, demuxing entries by CF prefix into per-CF SSTables. The on-disk format is identical to per-CF mode - SSTables contain user keys without the prefix.

### Usage

All existing transaction, iterator, and column family APIs work identically in unified mode. No application code changes are needed beyond setting `unified_memtable = 1`:

```c
/* Normal transaction -- works identically in both modes */
tidesdb_column_family_t *users = tidesdb_get_column_family(db, "users");
tidesdb_column_family_t *orders = tidesdb_get_column_family(db, "orders");

tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin(db, &txn);

/* In unified mode, both ops write to the same skip list + same WAL (1 WAL write total) */
/* In per-CF mode, each op writes to its own skip list + own WAL (2 WAL writes total) */
tidesdb_txn_put(txn, users, (uint8_t *)"user:1", 6, (uint8_t *)"Alice", 5, -1);
tidesdb_txn_put(txn, orders, (uint8_t *)"order:1", 7, (uint8_t *)"item_A", 6, -1);

tidesdb_txn_commit(txn);
tidesdb_txn_free(txn);
```

### When to Use Unified Memtable

- **Many column families per transaction** · Workloads where each transaction touches multiple CFs (e.g., a table with secondary indexes where each index is a separate CF)
- **Write-heavy multi-CF workloads** · Reduces WAL I/O from N writes to 1 per transaction
- **Plugin/binding scenarios** · Storage engine plugins (e.g., MariaDB) that map SQL tables to column families with automatic secondary index CFs

### Constraints

- All column families sharing the unified memtable must use the same comparator (enforced at CF creation)
- The unified skip list always uses `memcmp` as its comparator for the prefixed keys
- Per-CF backpressure still applies - each CF's L0 queue depth and L1 file count are checked independently at commit time

:::note[SSTables Are Per-CF]
Even in unified mode, SSTables on disk remain per-column-family. The unified memtable only affects the in-memory write path and WAL. Flush, compaction, reads from disk, iterators over SSTables, bloom filters, and block indexes all work identically to per-CF mode.
:::

See [How does TidesDB work?](/getting-started/how-does-tidesdb-work#unified-memtable) for the full design rationale, flush demuxing details, and WAL format.

## Object Store Mode

Object store mode allows TidesDB to store SSTables in a remote object store (S3, MinIO, GCS, or any S3-compatible service) while using local disk as a cache. This separates compute from storage and enables cold start recovery from the remote store. Object store mode requires unified memtable mode and is automatically enforced when a connector is set.

### Enabling Object Store Mode (Filesystem Connector)

```c
#include <tidesdb/tidesdb.h>

/* create a filesystem connector (for testing and local replication) */
tidesdb_objstore_t *store = tidesdb_objstore_fs_create("/mnt/nfs/tidesdb-objects");

tidesdb_objstore_config_t os_cfg = tidesdb_objstore_default_config();

tidesdb_config_t config = tidesdb_default_config();
config.db_path = "./mydb";
config.object_store = store;
config.object_store_config = &os_cfg;

tidesdb_t *db = NULL;
if (tidesdb_open(&config, &db) != 0)
{
    return -1;
}

/* use the database normally -- SSTables are uploaded after flush */

tidesdb_close(db);
```

### Enabling Object Store Mode (S3/MinIO Connector)

Build with `-DTIDESDB_WITH_S3=ON` to enable the S3 connector. This requires libcurl and OpenSSL.

```c
#include <tidesdb/tidesdb.h>

tidesdb_objstore_t *s3 = tidesdb_objstore_s3_create(
    "s3.amazonaws.com",                         /* endpoint */
    "my-tidesdb-bucket",                        /* bucket */
    "production/db1/",                          /* key prefix (or NULL) */
    "AKIAIOSFODNN7EXAMPLE",                     /* access key */
    "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", /* secret key */
    "us-east-1",                                /* region */
    1,                                          /* use_ssl (HTTPS) */
    0                                           /* use_path_style (0 for AWS, 1 for MinIO) */
);

tidesdb_objstore_config_t os_cfg = tidesdb_objstore_default_config();
os_cfg.local_cache_max_bytes = 512 * 1024 * 1024; /* 512MB local cache */
os_cfg.max_concurrent_uploads = 8;

tidesdb_config_t config = tidesdb_default_config();
config.db_path = "./mydb";
config.object_store = s3;
config.object_store_config = &os_cfg;

tidesdb_t *db = NULL;
tidesdb_open(&config, &db);
```

### MinIO Example

```c
tidesdb_objstore_t *minio = tidesdb_objstore_s3_create(
    "localhost:9000",   /* MinIO endpoint */
    "tidesdb-bucket",   /* bucket */
    NULL,               /* no key prefix */
    "minioadmin",       /* access key */
    "minioadmin",       /* secret key */
    NULL,               /* region (NULL for MinIO) */
    0,                  /* no SSL for local dev */
    1                   /* path-style URLs (required for MinIO) */
);
```

### Object Store Configuration

Use `tidesdb_objstore_default_config()` for sensible defaults, then override fields as needed.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `local_cache_path` | `const char *` | `NULL` (uses db_path) | Local directory for cached SSTable files |
| `local_cache_max_bytes` | `size_t` | `0` (unlimited) | Maximum local cache size in bytes |
| `cache_on_read` | `int` | `1` | Cache downloaded files locally |
| `cache_on_write` | `int` | `1` | Keep local copy after upload |
| `max_concurrent_uploads` | `int` | `4` | Number of parallel upload threads |
| `max_concurrent_downloads` | `int` | `8` | Number of parallel download threads |
| `multipart_threshold` | `size_t` | `67108864` (64MB) | Use multipart upload above this size |
| `multipart_part_size` | `size_t` | `8388608` (8MB) | Chunk size for multipart uploads |
| `sync_manifest_to_object` | `int` | `1` | Upload MANIFEST after each compaction |
| `replicate_wal` | `int` | `1` | Upload closed WAL segments for replication |
| `wal_upload_sync` | `int` | `0` | 0 for background WAL upload, 1 to block flush |
| `wal_sync_threshold_bytes` | `size_t` | `1048576` (1MB) | Sync active WAL to object store when it grows by this many bytes since last sync (0 to disable) |
| `wal_sync_on_commit` | `int` | `0` | Upload WAL after every txn commit for RPO=0 replication |
| `replica_mode` | `int` | `0` | Enable read-only replica mode (writes return TDB_ERR_READONLY) |
| `replica_sync_interval_us` | `uint64_t` | `5000000` (5s) | MANIFEST poll interval for replica sync in microseconds |
| `replica_replay_wal` | `int` | `1` | Replay WAL from object store for near-real-time reads on replicas |

### Per-CF Object Store Tuning

Column family configurations include object store tuning fields. These are persisted to config.ini and survive restarts.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `object_target_file_size` | `size_t` | `0` | Reserved for API compatibility. Not used; output SSTable sizing during partitioned merge is derived automatically from level geometry (`file_max = C_X`) per the Spooky algorithm |
| `object_lazy_compaction` | `int` | `0` | 1 to double the L1 file count compaction trigger, reducing compaction frequency and remote I/O at the cost of higher read amplification |
| `object_prefetch_compaction` | `int` | `1` | 1 to download all input SSTables in parallel before the compaction merge begins (uses `max_concurrent_downloads` threads). 0 to download on demand during merge source creation |

### Object Store Statistics

`tidesdb_get_db_stats` includes object store fields when a connector is active.

```c
tidesdb_db_stats_t stats;
tidesdb_get_db_stats(db, &stats);

if (stats.object_store_enabled)
{
    printf("connector: %s\n", stats.object_store_connector);
    printf("total uploads: %" PRIu64 "\n", stats.total_uploads);
    printf("upload failures: %" PRIu64 "\n", stats.total_upload_failures);
    printf("upload queue depth: %" PRIu64 "\n", stats.upload_queue_depth);
    printf("local cache: %zu / %zu bytes\n",
           stats.local_cache_bytes_used, stats.local_cache_bytes_max);
}
```

### Cold Start Recovery

When the local database directory is empty but a connector is configured, TidesDB automatically discovers column families from the object store during recovery. It downloads MANIFEST and config files in parallel (one thread per CF), reconstructs the SSTable inventory, and fetches SSTable data on demand as queries arrive.

```c
/* delete all local state */
remove_directory("./mydb");

/* reopen with the same connector -- cold start recovery */
tidesdb_config_t config = tidesdb_default_config();
config.db_path = "./mydb";
config.object_store = s3;
config.object_store_config = &os_cfg;

tidesdb_t *db = NULL;
tidesdb_open(&config, &db);

/* all data is available -- SSTables are fetched from the object store on demand */
tidesdb_column_family_t *cf = tidesdb_get_column_family(db, "my_cf");
```

### How It Works

- Object store mode requires unified memtable mode. Setting `object_store` on the config automatically enables `unified_memtable`
- After each flush, SSTables are uploaded synchronously to the object store before being tracked in the local cache, ensuring the object store has a copy before cache eviction can delete the local file. Uploads use retry (3 attempts with exponential backoff) and post-upload verification (size check)
- Point lookups on frozen SSTables (not present locally) fetch just the single needed klog block (~64KB) via one HTTP range request using `range_get`, bypassing the full file download. The block is cached in the clock cache so subsequent reads are pure memory hits. If the value is in the vlog, a second range request fetches just that vlog block
- Iterators prefetch all needed SSTable files in parallel at creation time using bounded threads (`max_concurrent_downloads`, default 8), so sequential reads proceed at local disk speed. Prefetch runs at both initial iterator creation and after seek invalidation
- A hash-indexed LRU local file cache manages disk usage, evicting least-recently-used SSTable file pairs (klog + vlog together) when `local_cache_max_bytes` is set
- The MANIFEST is uploaded asynchronously after each flush so cold start recovery can reconstruct the SSTable inventory without blocking the flush worker
- During compaction, the MANIFEST is uploaded after the new merged SSTable is committed, before old input SSTables are cleaned up. This ensures replicas and cold-start nodes see the new SSTable before old inputs are removed
- Compaction prefetches input SSTables in parallel when `object_prefetch_compaction` is enabled (default). Output SSTables are uploaded synchronously after the merge. Old input SSTables are deleted from the object store with retry and exponential backoff when their reference count reaches zero
- The reaper thread periodically syncs the active WAL to the object store based on write volume (`wal_sync_threshold_bytes`, default 1MB). This reads the WAL's atomic file size lock-free and uploads when the delta since last sync exceeds the threshold, bounding the data loss window to write volume rather than wall clock time
- Upload failures are tracked in `total_upload_failures` on `tidesdb_db_stats_t` for operator monitoring

:::note[Build Requirement for S3]
The S3 connector requires libcurl and OpenSSL. Enable it with `-DTIDESDB_WITH_S3=ON` during CMake configuration. The filesystem connector is always available without additional dependencies.
:::

## Replica Mode

Replica mode enables read-only nodes that follow a primary through the object store. The primary handles all writes while replicas poll for MANIFEST updates and replay WAL segments for near-real-time reads.

### Enabling Replica Mode

```c
tidesdb_objstore_config_t os_cfg = tidesdb_objstore_default_config();
os_cfg.replica_mode = 1;
os_cfg.replica_sync_interval_us = 1000000; /* 1 second sync interval */
os_cfg.replica_replay_wal = 1;             /* replay WAL for fresh reads */

tidesdb_config_t config = tidesdb_default_config();
config.db_path = "./mydb_replica";
config.object_store = s3; /* same bucket as the primary */
config.object_store_config = &os_cfg;

tidesdb_t *db = NULL;
tidesdb_open(&config, &db);

/* reads work normally */
tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin(db, &txn);

uint8_t *val = NULL;
size_t val_size = 0;
tidesdb_txn_get(txn, cf, key, key_size, &val, &val_size);

/* writes are rejected */
int rc = tidesdb_txn_put(txn, cf, key, key_size, val, val_size, 0);
/* rc == TDB_ERR_READONLY */
```

### Sync-on-Commit WAL (Primary Side)

For tighter replication lag, enable sync-on-commit on the primary so every committed write is uploaded to the object store immediately.

```c
tidesdb_objstore_config_t os_cfg = tidesdb_objstore_default_config();
os_cfg.wal_sync_on_commit = 1; /* RPO = 0, every commit is durable in S3 */

/* replica sees committed data within one replica_sync_interval_us */
```

### Promoting a Replica to Primary

When the primary fails, promote a replica to accept writes.

```c
/* external health check detects primary is down */

/* promote this replica */
int rc = tidesdb_promote_to_primary(db);
/* rc == TDB_SUCCESS */

/* now writes are accepted */
tidesdb_txn_t *txn = NULL;
tidesdb_txn_begin(db, &txn);
tidesdb_txn_put(txn, cf, key, key_size, val, val_size, 0); /* succeeds */
tidesdb_txn_commit(txn);
```

`tidesdb_promote_to_primary` waits for any in-progress reaper sync cycle to complete, performs a final MANIFEST sync and WAL replay, creates a local WAL for crash recovery, and atomically switches to primary mode. The wait prevents lock contention between the sync thread and the first post-promotion query. The function returns `TDB_ERR_INVALID_ARGS` if the node is already a primary.

### How Replica Sync Works

- Before each MANIFEST sync cycle, the reaper discovers new column families in the object store that do not exist locally and creates them automatically by downloading their config and MANIFEST
- The reaper thread polls the remote MANIFEST for each CF every `replica_sync_interval_us`
- New SSTables from the primary's flushes and compactions are added to the replica's levels
- SSTables compacted away on the primary are removed from the replica's levels
- When `replica_replay_wal` is enabled, all available WAL segments are discovered from the object store via listing and replayed in generation order into the memtable for near-real-time reads
- WAL replay is idempotent using sequence numbers so entries already present are skipped
- SSTable data is not downloaded during sync. It is fetched on demand via range_get for point lookups or prefetch for iterators

## Utility Functions

### tidesdb_free

Use `tidesdb_free` to free memory allocated by TidesDB. This is particularly useful for FFI/language bindings where the caller needs to free memory returned by TidesDB functions (e.g., values from `tidesdb_txn_get`).

```c
uint8_t *value = NULL;
size_t value_size = 0;

if (tidesdb_txn_get(txn, cf, key, key_size, &value, &value_size) == 0)
{
    /* Use value */
    printf("Value: %.*s\n", (int)value_size, value);
    
    /* Free using tidesdb_free (or standard free) */
    tidesdb_free(value);
}
```

:::note[When to use tidesdb_free]
- FFI bindings · Language bindings (Java, Rust, Go, Python) should use `tidesdb_free` to ensure memory is freed by the same allocator that allocated it
- Cross-platform · Ensures correct deallocation on all platforms
- Consistency · Provides a uniform API for memory management

For native C/C++ applications, `free()` works identically since TidesDB uses the standard allocator.
:::
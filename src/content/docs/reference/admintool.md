---
title: TidesDB Admintool Reference
description: Complete Admintool reference for TidesDB
---

<div class="no-print">

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/admintool.md).

<hr/>

</div>

## Overview

Admintool is a command-line utility for managing and inspecting TidesDB databases. It provides interactive and non-interactive modes for database operations, diagnostics, and maintenance.

## Installation

Build from source:
```bash
git clone https://github.com/tidesdb/admintool.git
cd admintool
mkdir build && cd build
cmake ..
make
```

## Usage

```bash
admintool [options]
```

**Options**
| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-v, --version` | Show TidesDB version |
| `-d, --directory <path>` | Open database at path on startup |
| `-c, --command <cmd>` | Execute command and exit |

**Examples**
```bash
# Interactive mode
admintool

# Open database on startup
admintool -d ./mydb

# Execute single command
admintool -d ./mydb -c "cf-list"
```

## Database Operations

### open
Open or create a database.
```
open <path> [options]
```

**Options**
| Option | Description |
|--------|-------------|
| `--unified` | Enable unified memtable mode |
| `--unified-buffer-size <n>` | Unified memtable write buffer size (bytes) |
| `--unified-skip-list-max-level <n>` | Skip list max level for unified memtable (0 = default 12) |
| `--unified-skip-list-probability <f>` | Skip list probability for unified memtable (0 = default 0.25) |
| `--unified-sync <mode>` | Unified WAL sync mode (`none`\|`interval`\|`full`) |
| `--unified-sync-interval <us>` | Unified WAL sync interval (microseconds) |
| `--cache-size <n>` | Block cache size (bytes, 0 to disable) |
| `--max-open-sstables <n>` | Max cached SSTable structures |
| `--flush-threads <n>` | Flush thread pool size |
| `--compaction-threads <n>` | Compaction thread pool size |
| `--max-concurrent-flushes <n>` | Global cap on in-flight memtable flushes across all CFs (0 = default) |
| `--max-memory <n>` | Global memory limit (bytes, 0 = auto) |
| `--log-level <level>` | Log level: `debug`\|`info`\|`warn`\|`error`\|`fatal`\|`none` (default: `none`) |
| `--log-to-file` | Write logs to `<db_path>/LOG` instead of stderr |
| `--log-truncation-at <n>` | Log truncation size in bytes (0 = no truncation) |
| `--object-store-fs <root_dir>` | Enable filesystem object-store connector. Auto-enables unified memtable mode |
| `--obj-cache-path <dir>` | Local cache directory for object store (default: `<db_path>`) |
| `--obj-cache-max-bytes <n>` | Maximum local cache size in bytes (0 = unlimited) |
| `--obj-replica-mode` | Open the database in read-only replica mode |
| `--obj-replica-sync-interval <us>` | Replica MANIFEST poll interval (default: 5000000) |
| `--obj-wal-sync-on-commit` | Upload the WAL to the object store after every commit (RPO=0) |
| `--obj-cache-on-read <0\|1>` | Cache downloaded object files locally (default 1) |
| `--obj-cache-on-write <0\|1>` | Keep a local copy after upload (default 1) |
| `--obj-max-uploads <n>` | Parallel upload threads (default 4) |
| `--obj-max-downloads <n>` | Parallel download threads (default 8) |
| `--obj-multipart-threshold <n>` | Use multipart upload at/above this object size (bytes) |
| `--obj-multipart-part-size <n>` | Multipart chunk size (bytes) |
| `--obj-sync-manifest <0\|1>` | Upload the MANIFEST after each compaction (default 1) |
| `--obj-replicate-wal <0\|1>` | Upload closed WAL segments for node-failure recovery (default 1) |
| `--obj-wal-upload-sync <0\|1>` | Block flush until the WAL is uploaded (default 0 = background) |
| `--obj-wal-sync-threshold <n>` | Sync the active WAL when it grows by this many bytes (0 = off) |
| `--obj-replica-replay-wal <0\|1>` | Replay the WAL for near-real-time replica reads (default 1) |
| `--object-store-s3` | Enable the S3-compatible object-store connector (requires a library built with `TIDESDB_WITH_S3=ON`) |
| `--s3-endpoint <ep>` | S3 endpoint (e.g. `s3.amazonaws.com` or `minio.local:9000`) |
| `--s3-bucket <name>` | S3 bucket name |
| `--s3-prefix <p>` | S3 key prefix (e.g. `production/db1/`) |
| `--s3-access-key <k>` | AWS access key ID (falls back to `$AWS_ACCESS_KEY_ID`) |
| `--s3-secret-key <k>` | AWS secret access key (falls back to `$AWS_SECRET_ACCESS_KEY`) |
| `--s3-region <r>` | AWS region (falls back to `$AWS_REGION`) |
| `--s3-no-ssl` | Use HTTP instead of HTTPS |
| `--s3-path-style` | Use path-style URLs (required for MinIO) |
| `--s3-ca-path <path>` | Custom CA bundle file for TLS verification |
| `--s3-insecure-skip-verify` | Disable TLS verification (test endpoints only; insecure) |
| `--s3-multipart-threshold <n>` | S3 multipart upload threshold (bytes) |
| `--s3-multipart-part-size <n>` | S3 multipart chunk size (bytes) |

**Examples**
```
admintool> open ./mydb
Opened database at './mydb'

admintool> open ./mydb --unified
Opened database at './mydb' (unified memtable)

admintool> open ./mydb --unified --cache-size 134217728 --flush-threads 4
Opened database at './mydb' (unified memtable)

admintool> open ./mydb --log-level info --log-to-file
Opened database at './mydb'

admintool> open ./mydb --object-store-fs /mnt/objects
Opened database at './mydb' (object-store fs:/mnt/objects)

admintool> open ./mydb --object-store-s3 --s3-endpoint minio.local:9000 \
             --s3-bucket tidesdb --s3-path-style --s3-no-ssl \
             --s3-access-key minioadmin --s3-secret-key minioadmin
Opened database at './mydb' (object-store s3:minio.local:9000/tidesdb)
```

:::note[Unified Memtable Mode]
When `--unified` is set, all column families share a single skip list and WAL instead of each column family maintaining its own. A transaction touching N column families results in 1 WAL write instead of N. On-disk SSTables remain per-column-family. This mode is beneficial for write-heavy multi-CF workloads.
:::

:::note[Filesystem Object Store]
`--object-store-fs <root_dir>` attaches a filesystem-backed object-store connector that mirrors objects under the given directory. This is intended for testing and local replication scenarios. Object-store mode automatically enables unified memtable mode. The connector is destroyed when the database is closed. Combine with `--obj-cache-max-bytes`, `--obj-replica-mode`, `--obj-replica-sync-interval`, and `--obj-wal-sync-on-commit` to tune behavior.
:::

:::note[S3 Object Store]
`--object-store-s3` attaches an S3-compatible connector (AWS S3, MinIO, etc.). It is only available when the linked TidesDB library was built with `TIDESDB_WITH_S3=ON`; otherwise the command reports `This TidesDB library was built without S3 support` and the open is rejected (the connector symbol is resolved at runtime, so the tool still runs against an S3-off library). At a minimum supply `--s3-endpoint` and `--s3-bucket`; credentials may be passed with `--s3-access-key`/`--s3-secret-key` or left to the standard `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_REGION` environment variables. Use `--s3-path-style` for MinIO. The shared `--obj-*` tuning flags apply to both the filesystem and S3 connectors.
:::

### close
Close the current database.
```
close
```

### info
Show database information including column families, cache stats, and mode.
```
info
```

**Output includes**
- Database path
- Column family list
- Block cache statistics (entries, size, hits, misses, hit rate, partitions)
- Unified memtable status (enabled/disabled)
- Object store status and connector type (if active)
- Replica mode status (if active)

### backup
Create a backup of the open database.
```
backup <destination_path>
```

### version
Show TidesDB version.
```
version
```

## Column Family Operations

### cf-list
List all column families.
```
cf-list
```

### cf-create
Create a new column family.
```
cf-create <name> [options]
```

**Options**
| Option | Description |
|--------|-------------|
| `--btree` | Use B+tree format for klog (faster point lookups) |
| `--compression <algo>` | Compression algorithm: `none`\|`lz4`\|`lz4-fast`\|`zstd`\|`snappy` |
| `--bloom-fpr <rate>` | Bloom filter false positive rate (e.g., `0.01` for 1%) |
| `--no-bloom` | Disable bloom filters |
| `--sync <mode>` | WAL sync mode: `none`\|`interval`\|`full` |
| `--sync-interval <us>` | Sync interval in microseconds (for `interval` mode) |
| `--comparator <name>` | Key comparator: `memcmp`\|`lexicographic`\|`uint64`\|`int64`\|`reverse`\|`case_insensitive` |
| `--write-buffer-size <n>` | Memtable flush threshold (bytes) |
| `--klog-value-threshold <n>` | Value size threshold for vlog storage (bytes) |
| `--block-index-prefix-len <n>` | Block index prefix length |
| `--index-sample-ratio <n>` | Block index sample ratio |
| `--no-block-indexes` | Disable block indexes |
| `--skip-list-max-level <n>` | Skip list max level |
| `--skip-list-probability <f>` | Skip list probability |
| `--isolation <level>` | Default transaction isolation level |
| `--min-disk-space <n>` | Minimum required disk space (bytes) |
| `--l1-trigger <n>` | L1 file count compaction trigger |
| `--l0-stall <n>` | L0 queue stall threshold |
| `--level-size-ratio <n>` | Level size multiplier |
| `--min-levels <n>` | Minimum LSM levels |
| `--dividing-level-offset <n>` | Compaction dividing level offset |
| `--tombstone-density-trigger <ratio>` | Tombstone density above which compaction priority escalates (`0.0` to `1.0`, `0` disables) |
| `--tombstone-density-min-entries <n>` | Minimum entry count for an SSTable to be considered by the density trigger |
| `--object-lazy-compaction` / `--no-object-lazy-compaction` | Lazy compaction in object-store mode (doubles the L1 trigger, reducing remote I/O) |
| `--object-prefetch-compaction` / `--no-object-prefetch-compaction` | Prefetch all input SSTables in parallel before a compaction merge (default: enabled) |

**Examples**
```
cf-create users
cf-create cache --btree
cf-create logs --compression zstd --sync full --bloom-fpr 0.001
cf-create events --comparator reverse --write-buffer-size 134217728
```

**Compression algorithms**

| Algorithm | Description | Use case |
|-----------|-------------|----------|
| `none` | No compression | Pre-compressed data, max write throughput |
| `lz4` | LZ4 standard (default) | General purpose, balanced |
| `lz4-fast` | LZ4 fast mode | Write-heavy, speed over ratio |
| `zstd` | Zstandard | Best compression ratio, storage-constrained |
| `snappy` | Snappy | Legacy compatibility (not available on SunOS) |

**Sync modes**

| Mode | Description | Use case |
|------|-------------|----------|
| `none` | No explicit sync, relies on OS page cache | Caches, temporary data |
| `interval` | Periodic background syncing | Most production workloads |
| `full` | Fsync on every write | Financial transactions, audit logs |

**Built-in comparators**

| Name | Description |
|------|-------------|
| `memcmp` | Binary byte-by-byte comparison (default) |
| `lexicographic` | Null-terminated string comparison |
| `uint64` | Unsigned 64-bit integer comparison |
| `int64` | Signed 64-bit integer comparison |
| `reverse` | Reverse binary comparison (descending order) |
| `case_insensitive` | Case-insensitive ASCII comparison |

### cf-drop
Drop a column family.
```
cf-drop <name>
```

### cf-rename
Rename a column family.
```
cf-rename <old_name> <new_name>
```

### cf-clone
Clone a column family. Creates a complete copy of an existing column family with a new name, including all data.
```
cf-clone <source_name> <destination_name>
```

**Behavior**
- Flushes the source column family's memtable to ensure all data is on disk
- Waits for any in-progress flush or compaction to complete
- Copies all SSTable files (`.klog` and `.vlog`) to the new directory
- Copies manifest and configuration files
- The clone is completely independent; modifications to one do not affect the other

**Use cases**
- Testing with a copy of production data
- Creating a snapshot before experimental changes
- Data migration before configuration changes

**Example**
```
admintool(./mydb)> cf-clone users users_backup
Cloned column family 'users' to 'users_backup'
```

### cf-stats
Show column family statistics and configuration.
```
cf-stats <name>
```

**Output includes**
- Memtable size, levels, total keys
- Data size, avg key/value sizes
- Read amplification, cache hit rate
- Full configuration (compression, bloom filter, sync mode, dividing level offset, tombstone density trigger and minimum, object-store lazy/prefetch compaction, etc.)
- Per-level SSTable counts, sizes, key counts, and tombstone counts
- Tombstone observability: total tombstones, database-wide ratio, and the worst single-SSTable tombstone density (with the level it lives on)
- B+tree statistics (if enabled)

### cf-status
Show flush/compaction status.
```
cf-status <name>
```

### cf-update
Update runtime-safe configuration settings for a column family. Changes apply to new operations only; existing SSTables and memtables retain their original settings.
```
cf-update <name> [options]
```

**Options**

All options from `cf-create` are supported except `--btree` and `--comparator` (these cannot be changed after creation). Additionally:

| Option | Description |
|--------|-------------|
| `--persist` | Save changes to disk (default) |
| `--no-persist` | Apply changes in-memory only |

**Updatable settings**
- `--compression` · Compression for new SSTables (existing SSTables retain their original compression)
- `--bloom-fpr`, `--no-bloom` · Bloom filter settings for new SSTables
- `--sync`, `--sync-interval` · Durability mode (also updates the active WAL immediately)
- `--write-buffer-size` · Memtable flush threshold
- `--klog-value-threshold` · Value log threshold for new writes
- `--block-index-prefix-len`, `--index-sample-ratio`, `--no-block-indexes` · Block index settings for new SSTables
- `--skip-list-max-level`, `--skip-list-probability` · Skip list settings for new memtables
- `--isolation` · Default transaction isolation level
- `--level-size-ratio`, `--min-levels`, `--dividing-level-offset` · LSM level sizing
- `--l1-trigger`, `--l0-stall` · Compaction and backpressure thresholds
- `--tombstone-density-trigger`, `--tombstone-density-min-entries` · Tombstone-density compaction escalation
- `--object-lazy-compaction` / `--no-object-lazy-compaction`, `--object-prefetch-compaction` / `--no-object-prefetch-compaction` · Object-store mode tuning
- `--min-disk-space` · Minimum disk space required

**Non-updatable settings**
- `--comparator` · Cannot change sort order after creation (would corrupt key ordering)
- `--btree` · Cannot change klog format after creation (existing SSTables use the original format)

**Examples**
```
admintool(./mydb)> cf-update users --compression zstd --bloom-fpr 0.001
Configuration updated for 'users' (persisted to disk)

admintool(./mydb)> cf-update cache --write-buffer-size 268435456 --no-persist
Configuration updated for 'cache' (in-memory only)
```

### cf-config-save
Save the current column family configuration to an INI file. The optional `section_name` defaults to the column family name.
```
cf-config-save <cf> <ini_file> [section_name]
```

**Example**
```
admintool(./mydb)> cf-config-save users ./users.ini
Saved configuration of 'users' to './users.ini' (section [users])
```

### cf-config-load
Create a column family by loading its configuration from an INI file section. Useful for replicating a tuned configuration across databases or for templating column families.
```
cf-config-load <ini_file> <section_name> <cf_name>
```

**Example**
```
admintool(./mydb)> cf-config-load ./users.ini users users_replica
Created column family 'users_replica' from './users.ini' [users]
```

## Key-Value Operations

### put
Insert or update a key-value pair.
```
put <cf> <key> <value> [--ttl <seconds>]
```
- `--ttl <seconds>` · Set time-to-live in seconds from now. The key expires after the specified duration. If omitted, the key does not expire.

**Examples**
```
admintool(./mydb)> put users user:1 "John Doe"
OK

admintool(./mydb)> put sessions sess:abc "token123" --ttl 3600
OK (expires at 1711584000)
```

### get
Retrieve a value by key.
```
get <cf> <key>
```

### delete
Delete a key.
```
delete <cf> <key>
```

### single-delete
Tombstone a key with single-delete semantics. Compaction can drop the put and the tombstone together as soon as both appear in the same merge input, rather than carrying the tombstone forward to the largest level.
```
single-delete <cf> <key>
```

:::caution[When to use]
`single-delete` is only safe when each key is put at most once between any two single-deletes (and at most once before the first single-delete on that key). Violating the contract can leave older puts visible after the tombstone. Prefer `delete` for any workload that issues repeated updates to the same key.
:::

**Example**
```
admintool(./mydb)> single-delete users user:1
OK
```

### scan
Scan all keys in a column family.
```
scan <cf> [limit] [--reverse] [--isolation <level>]
```
Default limit: 100

**Options**
| Option | Description |
|--------|-------------|
| `--reverse` | Iterate from the last key to the first (descending order) |
| `--isolation <level>` | Open the read transaction at a specific isolation level: `read_uncommitted`\|`read_committed`\|`repeatable_read`\|`snapshot`\|`serializable` |

**Examples**
```
admintool(./mydb)> scan users 10 --reverse
1) "user:9" -> "..."
2) "user:8" -> "..."
...
(10 entries, reverse)

admintool(./mydb)> scan users --isolation snapshot
```

### range
Scan keys within a range.
```
range <cf> <start_key> <end_key> [limit]
```

### prefix
Scan keys with a prefix.
```
prefix <cf> <prefix> [limit]
```

## SSTable Inspection

### sstable-list
List all SSTables in a column family.
```
sstable-list <cf>
```

### sstable-info
Show SSTable file information.
```
sstable-info <klog_path>
```

:::note[On-disk format handling]
The SSTable inspectors parse the klog directly off disk: they read the trailing metadata block to find how many leading blocks are key/value data blocks (the remaining blocks are the block-index, bloom and metadata blobs), skip each data block's header, and decompress data blocks with the column family's compression algorithm before decoding entries. Entries written by `single-delete` are labelled `[SINGLE-DEL]`; plain tombstones are labelled `[DEL]`.
:::

### sstable-dump
Dump SSTable entries (keys and values). Tombstones are shown as `[DEL]`, single-deletes as `[SINGLE-DEL]`, expiring keys as `[TTL:<expiry>]`, and vlog-stored values as `[VLOG:<offset>]`.
```
sstable-dump <klog_path> [limit]
```
Default limit: 1000

### sstable-dump-full
Dump SSTable entries with vlog value resolution. When `vlog_path` is supplied, values stored in the vlog are read back and decompressed (using the SSTable's compression algorithm) instead of being shown as `(in vlog, N bytes)`.
```
sstable-dump-full <klog_path> [vlog_path] [limit]
```

### sstable-stats
Show SSTable statistics, including total entries, tombstones (and how many are single-deletes), TTL entries, vlog references, sequence range, and key/value size distribution.
```
sstable-stats <klog_path>
```

### sstable-keys
List only keys from an SSTable. Single-delete and plain tombstones are flagged inline.
```
sstable-keys <klog_path> [limit]
```

### sstable-checksum
Verify SSTable block checksums.
```
sstable-checksum <klog_path>
```

### bloom-stats
Show bloom filter statistics for an SSTable, including the filter size, hash function count, hash version (1 = legacy, 2 = fmix-finalized), fill ratio, and estimated false-positive rate.
```
bloom-stats <klog_path>
```

## WAL Inspection

### wal-list
List WAL files in a column family.
```
wal-list <cf>
```

### wal-info
Show WAL file information.
```
wal-info <wal_path>
```

### wal-dump
Dump WAL entries. Automatically detects per-CF and unified WAL formats.
```
wal-dump <wal_path> [limit]
```
Default limit: 1000

For unified WAL files (created when using `--unified` mode), each entry is prefixed with `[CF:<index>]` showing which column family the entry belongs to. Both WAL formats pack every operation of a committed transaction into a single block, so one block can hold many entries — `wal-dump` decodes them all. Entries are labelled `[PUT]`, `[DELETE]`, or `[SINGLE-DELETE]`.

**Example (per-CF WAL)**
```
admintool(./mydb)> wal-dump ./mydb/users/wal_1.log 5
WAL Entries (limit: 5):
1) [PUT] seq=1 key="user:1" value="John Doe"
2) [PUT] [TTL:1711584000] seq=2 key="sess:abc" value="token123"
3) [DELETE] seq=3 key="user:2"

(3 WAL entries dumped)
```

**Example (unified WAL)**
```
admintool(./mydb)> wal-dump ./mydb/uwal_0.log 5
WAL Entries (limit: 5):
1) [CF:0] [PUT] seq=10 key="user:1" value="Alice"
2) [CF:1] [PUT] seq=10 key="order:1" value="item_A"
3) [CF:0] [PUT] seq=11 key="user:2" value="Bob"

(3 WAL entries dumped)
```

### wal-verify
Verify WAL integrity. Automatically detects per-CF and unified WAL formats and reports the format type.
```
wal-verify <wal_path>
```

**Example**
```
admintool(./mydb)> wal-verify ./mydb/users/wal_1.log
Verifying WAL: ./mydb/users/wal_1.log
  File Size: 4096 bytes
  Format: Per-CF WAL
  Valid Entries: 42
  Corrupted Entries: 0
  Sequence Range: 1 - 42
  Last Valid Position: 3840
  Status: OK
```

### wal-checksum
Verify WAL block checksums.
```
wal-checksum <wal_path>
```

## Maintenance

### level-info
Show per-level SSTable details.
```
level-info <cf>
```

### verify
Verify column family integrity.
```
verify <cf>
```

### compact
Trigger compaction on a column family.
```
compact <cf>
```

### compact-range
Run a synchronous compaction over a specific key range. Only SSTables whose minimum and maximum keys overlap the requested range participate in the merge, so the work and I/O are bounded to the affected portion of the LSM tree rather than the whole column family.
```
compact-range <cf> <start_key> <end_key>
```

**Behavior**
- Synchronous, blocks the caller until the merge commits or fails
- Selects only SSTables whose key range overlaps `[start_key, end_key)`
- Applies the same emit-loop logic as background compactions (tombstone reclamation, single-delete pair cancellation, sequence-based deduplication, value recompression)
- Output SSTables are committed to the manifest atomically and old inputs are marked for deletion

**Use cases**
- Bulk reclaim after a large range delete, where waiting for natural compaction would leave tombstones on disk
- Tenant eviction or sliding-window expiration that does not fit TTL semantics
- Post-import cleanup of a known key range
- Operational counterpart to the automatic tombstone density trigger when an operator wants reclaim now rather than at the next threshold crossing

**Example**
```
admintool(./mydb)> compact-range users tenant_42: tenant_42;
Compacting range 'users' [tenant_42: .. tenant_42;)...
Range compaction completed for 'users'
```

### flush
Flush memtable to disk.
```
flush <cf>
```

### purge-cf
Purge a single column family. Forces a synchronous flush and aggressive compaction, blocking until all I/O is complete.
```
purge-cf <name>
```

**Behavior**
1. Waits for any in-progress flush to complete
2. Force-flushes the active memtable (even if below threshold)
3. Waits for flush I/O to fully complete
4. Waits for any in-progress compaction to complete
5. Triggers synchronous compaction inline (bypasses the compaction queue)
6. Waits for any queued compaction to drain

**Use cases**
- Before backup or checkpoint to ensure all data is on disk and compacted
- After bulk deletes to reclaim space immediately
- Manual maintenance during a maintenance window
- Pre-shutdown to ensure all pending work is complete

**Example**
```
admintool(./mydb)> purge-cf users
Purging column family 'users' (synchronous flush + compaction)...
Purge completed for 'users'
```

### purge
Purge all column families. Forces a synchronous flush and aggressive compaction for every column family, then drains both the global flush and compaction queues.
```
purge
```

**Behavior**
- Calls `purge-cf` on each column family
- Drains the global flush queue
- Drains the global compaction queue

**Example**
```
admintool(./mydb)> purge
Purging all column families (synchronous flush + compaction)...
Database purge completed.
```

### sync-wal
Force an immediate fsync of the active write-ahead log for a column family. Useful for explicit durability control when using `TDB_SYNC_NONE` or `TDB_SYNC_INTERVAL` modes.
```
sync-wal <cf>
```

**Use cases**
- Application-controlled durability at specific points
- Pre-checkpoint to ensure all buffered WAL data is on disk
- Graceful shutdown to flush WAL buffers
- Force durability for specific high-value writes

**Example**
```
admintool(./mydb)> sync-wal users
WAL synced for 'users'
```

### checkpoint
Create a lightweight, near-instant snapshot of the open database using hard links instead of copying SSTable data.
```
checkpoint <destination_path>
```

**Behavior**
- Requires destination to be a non-existent or empty directory
- Flushes active memtables so all data is in SSTables
- Halts compactions to ensure a consistent view
- Hard links all SSTable files (`.klog` and `.vlog`) into the checkpoint directory
- Copies small metadata files (manifest, config)
- Resumes compactions
- Falls back to file copy if hard linking fails (e.g., cross-filesystem)

**Checkpoint vs Backup**

| | `backup` | `checkpoint` |
|--|---|---|
| Speed | Copies every SSTable byte-by-byte | Near-instant (hard links) |
| Disk usage | Full independent copy | No extra disk until compaction removes old SSTables |
| Portability | Can be moved to another filesystem or machine | Same filesystem only |
| Use case | Archival, disaster recovery | Fast local snapshots, point-in-time reads |

**Example**
```
admintool(./mydb)> checkpoint ./mydb_checkpoint
Creating checkpoint at './mydb_checkpoint'...
Checkpoint completed successfully.
```

### db-stats
Show aggregate statistics across the entire database instance.
```
db-stats
```

**Output includes**
- Column family count
- System total and available memory
- Resolved memory limit and memory pressure level (normal/elevated/high/critical)
- Global sequence number
- Flush queue size and pending count
- Compaction queue size
- Total SSTables, total data size
- Open SSTable handles
- In-flight transaction memory
- Immutable memtable count and total memtable bytes
- Unified memtable section (if enabled): memtable bytes, immutable count, flushing status, WAL generation, next CF index
- Object store section (if enabled): connector type, replica mode, local cache usage, upload stats

**Example**
```
admintool(./mydb)> db-stats
Database Statistics:
  Path: ./mydb
  Column Families: 2
  Total Memory: 16777216000 bytes (16000.00 MB)
  Available Memory: 8388608000 bytes (8000.00 MB)
  Resolved Memory Limit: 8388608000 bytes (8000.00 MB)
  Memory Pressure Level: 0 (normal)
  Global Sequence: 1042
  Flush Queue Size: 0
  Flush Pending Count: 0
  Compaction Queue Size: 0
  Total SSTables: 5
  Total Data Size: 1048576 bytes (1.00 MB)
  Open SSTable Handles: 5
  In-Flight Txn Memory: 0 bytes
  Immutable Memtables: 0
  Total Memtable Bytes: 2048
  Unified Memtable:
    Enabled: yes
    Memtable Bytes: 4096
    Immutable Count: 0
    Is Flushing: no
    Next CF Index: 3
    WAL Generation: 7
```

**Example with object store**
```
admintool(./mydb)> db-stats
...
  Object Store:
    Enabled: yes
    Connector: s3
    Replica Mode: no
    Local Cache: 524288000 / 1073741824 bytes (42 files)
    Last Uploaded Generation: 6
    Upload Queue Depth: 0
    Total Uploads: 156
    Total Upload Failures: 0
```

### cache-stats
Show detailed block cache statistics.
```
cache-stats
```

**Output includes**
- Whether cache is enabled
- Total cached entries and size (bytes and MB)
- Cache hits and misses
- Hit rate percentage
- Number of cache partitions

**Example**
```
admintool(./mydb)> cache-stats
Block Cache Statistics:
  Enabled: yes
  Entries: 128
  Size: 8388608 bytes (8.00 MB)
  Hits: 5432
  Misses: 312
  Hit Rate: 94.57%
  Partitions: 8
```

### range-cost
Estimate the computational cost of iterating between two keys in a column family. Uses only in-memory metadata with no disk I/O. The returned value is a relative scalar, meaningful only for comparison with other `range-cost` results.
```
range-cost <cf> <key_a> <key_b>
```

**Example**
```
admintool(./mydb)> range-cost users user:0000 user:0999
Range cost for 'users' [user:0000 .. user:0999]: 42.500000

admintool(./mydb)> range-cost users user:1000 user:1099
Range cost for 'users' [user:1000 .. user:1099]: 8.250000
```

**Use cases**
- Query planning: compare candidate key ranges to find the cheapest to scan
- Load balancing: distribute range scan work across threads
- Monitoring: track data distribution changes across key ranges

:::note[Cost Values]
A cost of 0.0 means no overlapping SSTables or memtable entries were found. Key order does not matter -- the function normalizes the range.
:::

### promote
Promote a read-only replica to primary. This performs a final MANIFEST sync and WAL replay, creates a local WAL for crash recovery, and atomically switches to primary mode.
```
promote
```

**Example**
```
admintool(./mydb_replica)> promote
Promoted to primary successfully.
```

**Behavior**
- Only valid when the database is in replica mode
- Performs a final MANIFEST sync and WAL replay
- Atomically transitions from replica to primary mode
- After promotion, writes are accepted normally
- Returns an error if the database is already a primary

### cancel-background-work
Cancel background compaction across the whole database for a fast shutdown. In-flight merges bail out safely and queued compaction is skipped; flushes are left untouched so durability is preserved. The cancellation is sticky for the session and is reset on the next `open` — typically issued right before `close`.
```
cancel-background-work
```

**Example**
```
admintool(./mydb)> cancel-background-work
Background compaction cancelled (flushes preserved). Sticky until next open.
```

### raise-open-file-limit
Raise this process's open-file ceiling so the engine can keep more SSTables open. Because the engine sizes `max_open_sstables` to fit the ceiling at open time, run this **before** `open`. With no argument (or a non-positive one) it just reports the current ceiling.
```
raise-open-file-limit [n]
```

**Example**
```
admintool> raise-open-file-limit 100000
Requested open-file ceiling 100000; effective ceiling now 100000.
admintool> open ./mydb
```

## Transactions

admintool can hold a single transaction open across interactive prompts, which makes the isolation, savepoint, and reset APIs reachable from the command line. Begin a transaction with `txn-begin`, stage operations with the `txn-*` commands, then finish with `txn-commit` or `txn-rollback`. Closing the database (or leaving admintool) automatically rolls back an open transaction.

### txn-begin
Begin a transaction, optionally at a specific isolation level (default `read_committed`).
```
txn-begin [read_uncommitted|read_committed|repeatable_read|snapshot|serializable]
```

### txn-status
Show whether a transaction is active and its isolation level.
```
txn-status
```

### txn-put
Stage a put in the active transaction.
```
txn-put <cf> <key> <value> [--ttl <seconds>]
```

### txn-get
Read a key through the active transaction (sees the transaction's own uncommitted writes).
```
txn-get <cf> <key>
```

### txn-delete
Stage a delete in the active transaction.
```
txn-delete <cf> <key>
```

### txn-single-delete
Stage a single-delete in the active transaction (see [single-delete](#single-delete) for the contract).
```
txn-single-delete <cf> <key>
```

### txn-savepoint
Create a named savepoint within the active transaction.
```
txn-savepoint <name>
```

### txn-rollback-to
Roll the transaction back to a previously created savepoint, discarding everything staged after it.
```
txn-rollback-to <name>
```

### txn-release
Release (drop) a savepoint without rolling back.
```
txn-release <name>
```

### txn-reset
Reset the active transaction for reuse, optionally changing the isolation level.
```
txn-reset [read_uncommitted|read_committed|repeatable_read|snapshot|serializable]
```

### txn-commit
Commit the active transaction.
```
txn-commit
```

### txn-rollback
Roll back and discard the active transaction.
```
txn-rollback
```

**Example**
```
admintool(./mydb)> txn-begin snapshot
Transaction started (isolation: snapshot).
admintool(./mydb)> txn-put users user:1 "John"
Staged put in transaction.
admintool(./mydb)> txn-savepoint sp1
Savepoint 'sp1' created.
admintool(./mydb)> txn-put users user:2 "Jane"
Staged put in transaction.
admintool(./mydb)> txn-rollback-to sp1
Rolled back to savepoint 'sp1'.
admintool(./mydb)> txn-commit
Transaction committed.
```

## Interactive Mode

When run without `-c`, admintool enters interactive mode with a prompt:
```
admintool>
```

When a database is open:
```
admintool(./mydb)>
```

Type `help` for available commands, `quit` or `exit` to leave.

## Examples

**Create database and column family**
```
admintool> open ./mydb
Opened database at './mydb'
admintool(./mydb)> cf-create users
Created column family 'users'
```

**Create database with unified memtable**
```
admintool> open ./mydb --unified --cache-size 134217728
Opened database at './mydb' (unified memtable)
```

**Create column family with custom settings**
```
admintool(./mydb)> cf-create logs --compression zstd --sync interval --sync-interval 100000 --bloom-fpr 0.001
Created column family 'logs'
```

**Update column family configuration at runtime**
```
admintool(./mydb)> cf-update users --compression zstd --write-buffer-size 268435456
Configuration updated for 'users' (persisted to disk)
```

**Insert and retrieve data**
```
admintool(./mydb)> put users user:1 "John Doe"
OK
admintool(./mydb)> get users user:1
John Doe
```

**Insert with TTL**
```
admintool(./mydb)> put sessions sess:abc "token123" --ttl 3600
OK (expires at 1711584000)
```

**Inspect column family**
```
admintool(./mydb)> cf-stats users
Column Family: users
  Memtable Size: 1024 bytes
  Levels: 5
  Total Keys: 1
  ...
```

**Scan with prefix**
```
admintool(./mydb)> prefix users user: 10
1) "user:1" -> "John Doe"
(1 entries with prefix)
```

**Compare range scan costs**
```
admintool(./mydb)> range-cost users user:0000 user:0999
Range cost for 'users' [user:0000 .. user:0999]: 42.500000
admintool(./mydb)> range-cost users user:1000 user:1099
Range cost for 'users' [user:1000 .. user:1099]: 8.250000
```

**Verify integrity**
```
admintool(./mydb)> verify users
Verifying column family 'users'...
Verification passed.
```

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
open <path>
```

### close
Close the current database.
```
close
```

### info
Show database information including column families and cache stats.
```
info
```

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
cf-create <name> [--btree]
```
- `--btree` · Use B+tree format for klog (faster point lookups)

**Example**
```
cf-create users
cf-create cache --btree
```

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
- Full configuration (compression, bloom filter, sync mode, etc.)
- Per-level SSTable counts and sizes
- B+tree statistics (if enabled)

### cf-status
Show flush/compaction status.
```
cf-status <name>
```

## Key-Value Operations

### put
Insert or update a key-value pair.
```
put <cf> <key> <value>
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

### scan
Scan all keys in a column family.
```
scan <cf> [limit]
```
Default limit: 100

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

### sstable-dump
Dump SSTable entries (keys and values).
```
sstable-dump <klog_path> [limit]
```
Default limit: 1000

### sstable-dump-full
Dump SSTable entries with vlog value resolution.
```
sstable-dump-full <klog_path> [vlog_path] [limit]
```

### sstable-stats
Show SSTable statistics.
```
sstable-stats <klog_path>
```

### sstable-keys
List only keys from an SSTable.
```
sstable-keys <klog_path> [limit]
```

### sstable-checksum
Verify SSTable block checksums.
```
sstable-checksum <klog_path>
```

### bloom-stats
Show bloom filter statistics for an SSTable.
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
Dump WAL entries.
```
wal-dump <wal_path> [limit]
```

### wal-verify
Verify WAL integrity.
```
wal-verify <wal_path>
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

**Insert and retrieve data**
```
admintool(./mydb)> put users user:1 "John Doe"
OK
admintool(./mydb)> get users user:1
John Doe
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

**Verify integrity**
```
admintool(./mydb)> verify users
Verifying column family 'users'...
Verification passed.
```
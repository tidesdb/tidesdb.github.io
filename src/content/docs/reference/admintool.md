---
title: TidesDB Admintool Reference
description: Complete Admintool reference for TidesDB
---

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/admintool.md).

<hr/>

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
- `--btree` — Use B+tree format for klog (faster point lookups)

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

### cf-stats
Show column family statistics and configuration.
```
cf-stats <name>
```

**Output includes:**
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
---
title: TidesDB C# API Reference
description: C# API reference for TidesDB
---

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/csharp.md).

<hr/>

## Getting Started

### Prerequisites

You **must** have the TidesDB shared C library installed on your system.  You can find the installation instructions [here](/reference/building/#_top).

### Installation

```bash
dotnet add package TidesDB
```

### Custom Installation Paths

If you installed TidesDB to a non-standard location, you can specify custom paths using environment variables:

```bash
# Linux
export LD_LIBRARY_PATH="/custom/path/lib:$LD_LIBRARY_PATH"

# macOS
export DYLD_LIBRARY_PATH="/custom/path/lib:$DYLD_LIBRARY_PATH"

# Windows (add to PATH)
set PATH=C:\custom\path\bin;%PATH%
```

**Custom prefix installation**
```bash
# Install TidesDB to custom location
cd tidesdb
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/opt/tidesdb
cmake --build build
sudo cmake --install build

# Configure environment to use custom location
export LD_LIBRARY_PATH="/opt/tidesdb/lib:$LD_LIBRARY_PATH"  # Linux
# or
export DYLD_LIBRARY_PATH="/opt/tidesdb/lib:$DYLD_LIBRARY_PATH"  # macOS

dotnet add package TidesDB
```

## Usage

### Opening and Closing a Database

```csharp
using TidesDB;

var db = TidesDB.Open(new Config
{
    DbPath = "./mydb",
    NumFlushThreads = 2,
    NumCompactionThreads = 2,
    LogLevel = LogLevel.Info,
    BlockCacheSize = 64 * 1024 * 1024,
    MaxOpenSSTables = 256
});

Console.WriteLine("Database opened successfully");

// When done
db.Close();
```

### Creating and Dropping Column Families

Column families are isolated key-value stores with independent configuration.

```csharp
using TidesDB;

// Create with default configuration
db.CreateColumnFamily("my_cf");

// Create with custom configuration
db.CreateColumnFamily("my_cf", new ColumnFamilyConfig
{
    WriteBufferSize = 128 * 1024 * 1024,
    LevelSizeRatio = 10,
    MinLevels = 5,
    CompressionAlgorithm = CompressionAlgorithm.Lz4,
    EnableBloomFilter = true,
    BloomFpr = 0.01,
    EnableBlockIndexes = true,
    SyncMode = SyncMode.Interval,
    SyncIntervalUs = 128000,
    DefaultIsolationLevel = IsolationLevel.ReadCommitted
});

db.DropColumnFamily("my_cf");
```

### CRUD Operations

All operations in TidesDB are performed through transactions for ACID guarantees.

#### Writing Data

```csharp
var cf = db.GetColumnFamily("my_cf");

using var txn = db.BeginTransaction();

// Put a key-value pair (TTL -1 means no expiration)
txn.Put(cf, Encoding.UTF8.GetBytes("key"), Encoding.UTF8.GetBytes("value"));

txn.Commit();
```

#### Writing with TTL

```csharp
var cf = db.GetColumnFamily("my_cf");

using var txn = db.BeginTransaction();

// Set expiration time (Unix timestamp in seconds)
var ttl = DateTimeOffset.UtcNow.ToUnixTimeSeconds() + 10; // Expire in 10 seconds

txn.Put(cf, Encoding.UTF8.GetBytes("temp_key"), Encoding.UTF8.GetBytes("temp_value"), ttl);

txn.Commit();
```

**TTL Examples**
```csharp
// No expiration
long ttl = -1;

// Expire in 5 minutes
long ttl = DateTimeOffset.UtcNow.ToUnixTimeSeconds() + 5 * 60;

// Expire in 1 hour
long ttl = DateTimeOffset.UtcNow.ToUnixTimeSeconds() + 60 * 60;

// Expire at specific time
long ttl = new DateTimeOffset(2026, 12, 31, 23, 59, 59, TimeSpan.Zero).ToUnixTimeSeconds();
```

#### Reading Data

```csharp
var cf = db.GetColumnFamily("my_cf");

using var txn = db.BeginTransaction();

var value = txn.Get(cf, Encoding.UTF8.GetBytes("key"));
Console.WriteLine($"Value: {Encoding.UTF8.GetString(value)}");
```

#### Deleting Data

```csharp
var cf = db.GetColumnFamily("my_cf");

using var txn = db.BeginTransaction();

txn.Delete(cf, Encoding.UTF8.GetBytes("key"));

txn.Commit();
```

#### Multi-Operation Transactions

```csharp
var cf = db.GetColumnFamily("my_cf");

using var txn = db.BeginTransaction();

try
{
    // Multiple operations in one transaction, across column families as well
    txn.Put(cf, Encoding.UTF8.GetBytes("key1"), Encoding.UTF8.GetBytes("value1"));
    txn.Put(cf, Encoding.UTF8.GetBytes("key2"), Encoding.UTF8.GetBytes("value2"));
    txn.Delete(cf, Encoding.UTF8.GetBytes("old_key"));

    // Commit atomically -- all or nothing
    txn.Commit();
}
catch
{
    txn.Rollback();
    throw;
}
```

### Iterating Over Data

Iterators provide efficient bidirectional traversal over key-value pairs.

#### Forward Iteration

```csharp
var cf = db.GetColumnFamily("my_cf");

using var txn = db.BeginTransaction();
using var iter = txn.NewIterator(cf);

iter.SeekToFirst();

while (iter.IsValid())
{
    var key = Encoding.UTF8.GetString(iter.Key());
    var value = Encoding.UTF8.GetString(iter.Value());
    
    Console.WriteLine($"Key: {key}, Value: {value}");
    
    iter.Next();
}
```

#### Backward Iteration

```csharp
var cf = db.GetColumnFamily("my_cf");

using var txn = db.BeginTransaction();
using var iter = txn.NewIterator(cf);

iter.SeekToLast();

while (iter.IsValid())
{
    var key = Encoding.UTF8.GetString(iter.Key());
    var value = Encoding.UTF8.GetString(iter.Value());
    
    Console.WriteLine($"Key: {key}, Value: {value}");
    
    iter.Prev();
}
```

### Getting Column Family Statistics

Retrieve detailed statistics about a column family.

```csharp
var cf = db.GetColumnFamily("my_cf");

var stats = cf.GetStats();

Console.WriteLine($"Number of Levels: {stats.NumLevels}");
Console.WriteLine($"Memtable Size: {stats.MemtableSize} bytes");

if (stats.Config != null)
{
    Console.WriteLine($"Write Buffer Size: {stats.Config.WriteBufferSize}");
    Console.WriteLine($"Compression: {stats.Config.CompressionAlgorithm}");
    Console.WriteLine($"Bloom Filter: {stats.Config.EnableBloomFilter}");
    Console.WriteLine($"Sync Mode: {stats.Config.SyncMode}");
}
```

### Listing Column Families

```csharp
var cfList = db.ListColumnFamilies();

Console.WriteLine("Available column families:");
foreach (var name in cfList)
{
    Console.WriteLine($"  - {name}");
}
```

### Compaction

#### Manual Compaction

```csharp
var cf = db.GetColumnFamily("my_cf");

// Manually trigger compaction (queues compaction from L1+)
cf.Compact();
```

#### Manual Memtable Flush

```csharp
var cf = db.GetColumnFamily("my_cf");

// Manually trigger memtable flush (queues memtable for sorted run to disk (L1))
cf.FlushMemtable();
```

### Sync Modes

Control the durability vs performance tradeoff.

```csharp
using TidesDB;

// SyncNone -- Fastest, least durable (OS handles flushing)
db.CreateColumnFamily("fast_cf", new ColumnFamilyConfig
{
    SyncMode = SyncMode.None
});

// SyncInterval -- Balanced (periodic background syncing)
db.CreateColumnFamily("balanced_cf", new ColumnFamilyConfig
{
    SyncMode = SyncMode.Interval,
    SyncIntervalUs = 128000 // Sync every 128ms
});

// SyncFull -- Most durable (fsync on every write)
db.CreateColumnFamily("durable_cf", new ColumnFamilyConfig
{
    SyncMode = SyncMode.Full
});
```

### Compression Algorithms

TidesDB supports multiple compression algorithms:

```csharp
using TidesDB;

db.CreateColumnFamily("no_compress", new ColumnFamilyConfig
{
    CompressionAlgorithm = CompressionAlgorithm.None
});

db.CreateColumnFamily("lz4_cf", new ColumnFamilyConfig
{
    CompressionAlgorithm = CompressionAlgorithm.Lz4
});

db.CreateColumnFamily("lz4_fast_cf", new ColumnFamilyConfig
{
    CompressionAlgorithm = CompressionAlgorithm.Lz4Fast
});

db.CreateColumnFamily("zstd_cf", new ColumnFamilyConfig
{
    CompressionAlgorithm = CompressionAlgorithm.Zstd
});
```

## Error Handling

```csharp
using TidesDB;

var cf = db.GetColumnFamily("my_cf");

using var txn = db.BeginTransaction();

try
{
    txn.Put(cf, Encoding.UTF8.GetBytes("key"), Encoding.UTF8.GetBytes("value"));
    txn.Commit();
}
catch (TidesDBException ex)
{
    Console.WriteLine($"Error code: {ex.Code}");
    Console.WriteLine($"Error message: {ex.Message}");
    Console.WriteLine($"Context: {ex.Context}");
    
    // Example error message:
    // "failed to put key-value pair: memory allocation failed (code: -1)"
    
    txn.Rollback();
}
```

**Error Codes**
- `ErrorCode.Success` (0) -- Operation successful
- `ErrorCode.Memory` (-1) -- Memory allocation failed
- `ErrorCode.InvalidArgs` (-2) -- Invalid arguments
- `ErrorCode.NotFound` (-3) -- Key not found
- `ErrorCode.IO` (-4) -- I/O error
- `ErrorCode.Corruption` (-5) -- Data corruption
- `ErrorCode.Exists` (-6) -- Resource already exists
- `ErrorCode.Conflict` (-7) -- Transaction conflict
- `ErrorCode.TooLarge` (-8) -- Key or value too large
- `ErrorCode.MemoryLimit` (-9) -- Memory limit exceeded
- `ErrorCode.InvalidDb` (-10) -- Invalid database handle
- `ErrorCode.Unknown` (-11) -- Unknown error
- `ErrorCode.Locked` (-12) -- Database is locked

## Complete Example

```csharp
using System.Text;
using TidesDB;

var db = TidesDB.Open(new Config
{
    DbPath = "./example_db",
    NumFlushThreads = 1,
    NumCompactionThreads = 1,
    LogLevel = LogLevel.Info,
    BlockCacheSize = 64 * 1024 * 1024,
    MaxOpenSSTables = 256
});

try
{
    db.CreateColumnFamily("users", new ColumnFamilyConfig
    {
        WriteBufferSize = 64 * 1024 * 1024,
        CompressionAlgorithm = CompressionAlgorithm.Lz4,
        EnableBloomFilter = true,
        BloomFpr = 0.01,
        SyncMode = SyncMode.Interval,
        SyncIntervalUs = 128000
    });

    var cf = db.GetColumnFamily("users");

    // Write data
    using (var txn = db.BeginTransaction())
    {
        txn.Put(cf, Encoding.UTF8.GetBytes("user:1"), Encoding.UTF8.GetBytes("Alice"));
        txn.Put(cf, Encoding.UTF8.GetBytes("user:2"), Encoding.UTF8.GetBytes("Bob"));

        // Temporary session with 30 second TTL
        var ttl = DateTimeOffset.UtcNow.ToUnixTimeSeconds() + 30;
        txn.Put(cf, Encoding.UTF8.GetBytes("session:abc"), Encoding.UTF8.GetBytes("temp_data"), ttl);

        txn.Commit();
    }

    // Read data
    using var readTxn = db.BeginTransaction();

    var value = readTxn.Get(cf, Encoding.UTF8.GetBytes("user:1"));
    Console.WriteLine($"user:1 = {Encoding.UTF8.GetString(value)}");

    // Iterate over all entries
    using var iter = readTxn.NewIterator(cf);

    Console.WriteLine("\nAll entries:");
    iter.SeekToFirst();
    while (iter.IsValid())
    {
        var key = Encoding.UTF8.GetString(iter.Key());
        var val = Encoding.UTF8.GetString(iter.Value());
        Console.WriteLine($"  {key} = {val}");
        iter.Next();
    }

    var stats = cf.GetStats();

    Console.WriteLine("\nColumn Family Statistics:");
    Console.WriteLine($"  Number of Levels: {stats.NumLevels}");
    Console.WriteLine($"  Memtable Size: {stats.MemtableSize} bytes");

    // Cleanup
    db.DropColumnFamily("users");
}
finally
{
    db.Close();
}
```

## Isolation Levels

TidesDB supports five MVCC isolation levels:

```csharp
using var txn = db.BeginTransactionWithIsolation(IsolationLevel.ReadCommitted);

// ... perform operations

txn.Commit();
```

**Available Isolation Levels**
- `IsolationLevel.ReadUncommitted` -- Sees all data including uncommitted changes
- `IsolationLevel.ReadCommitted` -- Sees only committed data (default)
- `IsolationLevel.RepeatableRead` -- Consistent snapshot, phantom reads possible
- `IsolationLevel.Snapshot` -- Write-write conflict detection
- `IsolationLevel.Serializable` -- Full read-write conflict detection (SSI)

## Savepoints

Savepoints allow partial rollback within a transaction:

```csharp
var cf = db.GetColumnFamily("my_cf");

using var txn = db.BeginTransaction();

txn.Put(cf, Encoding.UTF8.GetBytes("key1"), Encoding.UTF8.GetBytes("value1"));

txn.Savepoint("sp1");
txn.Put(cf, Encoding.UTF8.GetBytes("key2"), Encoding.UTF8.GetBytes("value2"));

// Rollback to savepoint -- key2 is discarded, key1 remains
txn.RollbackToSavepoint("sp1");

// Commit -- only key1 is written
txn.Commit();
```

## Cache Statistics

```csharp
var cacheStats = db.GetCacheStats();

Console.WriteLine($"Cache enabled: {cacheStats.Enabled}");
Console.WriteLine($"Total entries: {cacheStats.TotalEntries}");
Console.WriteLine($"Total bytes: {cacheStats.TotalBytes}");
Console.WriteLine($"Hits: {cacheStats.Hits}");
Console.WriteLine($"Misses: {cacheStats.Misses}");
Console.WriteLine($"Hit rate: {cacheStats.HitRate:P1}");
Console.WriteLine($"Partitions: {cacheStats.NumPartitions}");
```

## Testing

```bash
# Run all tests
dotnet test

# Run specific test
dotnet test --filter "FullyQualifiedName~OpenAndClose"

# Run with verbose output
dotnet test --verbosity normal
```

## C# Types

The package exports all necessary types for full C# support:

```csharp
using TidesDB;

// Main classes
TidesDB db;
ColumnFamily cf;
Transaction txn;
Iterator iter;
TidesDBException ex;

// Configuration classes
Config config;
ColumnFamilyConfig cfConfig;
Stats stats;
CacheStats cacheStats;

// Enums
CompressionAlgorithm compression;
SyncMode syncMode;
LogLevel logLevel;
IsolationLevel isolation;
ErrorCode errorCode;
```

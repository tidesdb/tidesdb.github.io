---
title: TidesDB Kafka Streams Plugin Reference
description: Official TidesDB state store plugin for Apache Kafka Streams reference
---

<div class="no-print">

If you want to download the source of this document, you can find it [here](https://github.com/tidesdb/tidesdb.github.io/blob/master/src/content/docs/reference/kafka.md).

<hr/>

</div>

## Overview

The TidesDB Kafka Streams plugin is a drop-in replacement for the default RocksDB state stores in <a href="https://kafka.apache.org/documentation/streams/">Apache Kafka Streams</a>. It provides a `KeyValueStore` implementation backed by TidesDB, giving Kafka Streams applications access to TidesDB's ACID transactions, MVCC concurrency, LSM-tree storage, configurable compression, bloom filters, block indexes, B+tree klog format, TTL-based expiration, commit hooks for change data capture, online backups, and lightweight checkpoints, all through the standard Kafka Streams state store interface.

Switching from RocksDB to TidesDB requires no changes to your stream topology. You replace the store supplier or builder, and the plugin handles the rest. The underlying TidesDB database is managed automatically, the plugin creates and opens the database in Kafka Streams' state directory, manages column families, handles transactions, and closes the database on shutdown.


## Getting Started

### Prerequisites

- Java 11 or higher
- Maven 3.6+
- TidesDB native C library installed on the system (see [Building](/reference/building/))
- TidesDB Java bindings installed (`com.tidesdb:tidesdb-java`)

### Adding to Your Project

**Maven**
```xml
<dependency>
    <groupId>com.tidesdb</groupId>
    <artifactId>tidesdb-kafka</artifactId>
    <version>0.3.1</version>
</dependency>
```

You must also ensure the TidesDB JNI shared library is on the Java library path at runtime:

```bash
-Djava.library.path=/usr/local/lib
```


## Usage

### Basic Usage with Materialized

The simplest way to use TidesDB as a state store is through `Materialized.as()` with the store supplier:

```java
import com.tidesdb.kafka.store.TidesDBStoreSupplier;

StreamsBuilder builder = new StreamsBuilder();

KStream<String, String> input = builder.stream("input-topic");

KTable<String, Long> counts = input
    .groupByKey()
    .count(Materialized.as(new TidesDBStoreSupplier("my-counts")));

counts.toStream().to("output-topic");
```

This creates a TidesDB-backed state store with default configuration: LZ4 compression, bloom filters enabled at 1% FPR, block indexes enabled, `SYNC_NONE` durability mode, 64 MB write buffer, and 64 MB block cache.

### Usage with StoreBuilder

For topology-level state stores, use the builder:

```java
import com.tidesdb.kafka.store.TidesDBStoreBuilder;

StoreBuilder<TidesDBStore> storeBuilder = new TidesDBStoreBuilder("my-store")
    .withLoggingEnabled(Collections.emptyMap());

builder.addStateStore(storeBuilder);

builder.stream("input-topic")
    .process(() -> new MyProcessor(), "my-store");
```

### Custom Configuration

Both the supplier and builder accept a `TidesDBStoreConfig` for fine-grained control over every TidesDB database and column family parameter:

```java
import com.tidesdb.kafka.store.TidesDBStoreConfig;
import com.tidesdb.kafka.store.TidesDBStoreSupplier;
import com.tidesdb.*;

TidesDBStoreConfig config = TidesDBStoreConfig.builder()
    .compressionAlgorithm(CompressionAlgorithm.ZSTD_COMPRESSION)
    .enableBloomFilter(true)
    .bloomFPR(0.001)
    .writeBufferSize(128 * 1024 * 1024)  // 128 MB
    .blockCacheSize(128 * 1024 * 1024)   // 128 MB
    .syncMode(SyncMode.SYNC_NONE)
    .enableBlockIndexes(true)
    .numFlushThreads(4)
    .numCompactionThreads(4)
    .build();

KTable<String, Long> counts = input
    .groupByKey()
    .count(Materialized.as(new TidesDBStoreSupplier("my-counts", config)));
```

Or with the builder:

```java
TidesDBStoreBuilder storeBuilder = TidesDBStoreBuilder.create("my-store", config)
    .withCachingEnabled()
    .withLoggingEnabled(Collections.emptyMap());
```


## Configuration Reference

### Database Configuration

These settings control the TidesDB database instance that backs the state store. Each Kafka Streams state store opens its own independent TidesDB database.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `numFlushThreads` | int | 2 | Number of background threads flushing memtables to SSTables |
| `numCompactionThreads` | int | 2 | Number of background threads performing LSM compaction |
| `logLevel` | LogLevel | INFO | TidesDB internal log level (DEBUG, INFO, WARN, ERROR, FATAL, NONE) |
| `blockCacheSize` | long | 64 MB | Size of the block cache shared across all column families |
| `maxOpenSSTables` | long | 256 | Maximum number of SSTable file handles cached in the LRU |
| `maxMemoryUsage` | long | 0 (auto) | Global memory limit in bytes; 0 lets TidesDB auto-detect (50% of system RAM) |
| `logToFile` | boolean | false | Write TidesDB logs to a file instead of stderr |
| `logTruncationAt` | long | 24 MB | Log file truncation size; 0 disables truncation |
| `objectStoreFsPath` | String | null | Filesystem path for object store connector; null disables object store mode |
| `objectStoreConfig` | ObjectStoreConfig | null | Object store behavior configuration; null uses defaults |
| `unifiedMemtable` | boolean | false | Enable unified memtable mode (single memtable + WAL for all CFs) |
| `unifiedMemtableWriteBufferSize` | long | 0 (auto) | Unified memtable write buffer size; 0 uses 64 MB default |
| `unifiedMemtableSkipListMaxLevel` | int | 0 (default 12) | Skip list max level for unified memtable |
| `unifiedMemtableSkipListProbability` | float | 0 (default 0.25) | Skip list probability for unified memtable |
| `unifiedMemtableSyncMode` | int | 0 (SYNC_NONE) | Sync mode for unified WAL |
| `unifiedMemtableSyncIntervalUs` | long | 0 | Sync interval for unified WAL in microseconds |

### Column Family Configuration

Each state store maps to a single TidesDB column family. These settings control the column family's storage behavior.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `columnFamilyName` | String | "default" | Name of the column family |
| `writeBufferSize` | long | 64 MB | Memtable flush threshold |
| `compressionAlgorithm` | CompressionAlgorithm | LZ4_COMPRESSION | Compression algorithm for SSTables |
| `enableBloomFilter` | boolean | true | Enable bloom filters for point lookups |
| `bloomFPR` | double | 0.01 | Bloom filter false positive rate (1%) |
| `enableBlockIndexes` | boolean | true | Enable compact block indexes for efficient seeking |
| `indexSampleRatio` | int | 1 | Sample every Nth block for the index |
| `blockIndexPrefixLen` | int | 16 | Block index prefix length in bytes |
| `syncMode` | SyncMode | SYNC_NONE | Durability mode for WAL writes |
| `syncIntervalUs` | long | 128000 | Sync interval in microseconds (for SYNC_INTERVAL mode) |
| `useBtree` | boolean | false | Use B+tree klog format instead of block-based SSTables |
| `minLevels` | int | 5 | Minimum number of LSM levels |
| `levelSizeRatio` | long | 10 | Level size multiplier for LSM compaction |
| `skipListMaxLevel` | int | 12 | Skip list max level for memtables |
| `skipListProbability` | float | 0.25 | Skip list promotion probability |
| `defaultIsolationLevel` | IsolationLevel | READ_COMMITTED | Default transaction isolation level |
| `klogValueThreshold` | long | 512 | Values larger than this go to the value log |
| `l0QueueStallThreshold` | int | 20 | Number of L0 immutable memtables before stalling writes |
| `l1FileCountTrigger` | int | 4 | Number of L1 files that triggers compaction |
| `dividingLevelOffset` | int | 2 | Compaction dividing level offset |
| `minDiskSpace` | long | 100 MB | Minimum free disk space required before writes are rejected |
| `comparatorName` | String | "" (memcmp) | Custom comparator name; empty uses default binary comparison |
| `objectLazyCompaction` | boolean | false | Compact less aggressively in object store mode |
| `objectPrefetchCompaction` | boolean | true | Download all inputs before merge in object store mode |

### Store Behavior

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `defaultTtlSeconds` | long | -1 (disabled) | Default TTL in seconds applied to all put operations; -1 means no expiration |

### Compression Algorithms

| Algorithm | Description |
|-----------|-------------|
| `NO_COMPRESSION` | No compression |
| `SNAPPY_COMPRESSION` | Snappy compression |
| `LZ4_COMPRESSION` | LZ4 standard compression (default) |
| `ZSTD_COMPRESSION` | Zstandard compression (best ratio) |
| `LZ4_FAST_COMPRESSION` | LZ4 fast mode (higher throughput, lower ratio) |

### Sync Modes

| Mode | Description |
|------|-------------|
| `SYNC_NONE` | No explicit sync; relies on OS page cache (fastest, default for Kafka plugin) |
| `SYNC_FULL` | Fsync on every write (most durable) |
| `SYNC_INTERVAL` | Periodic background syncing at configurable intervals |

The default sync mode for the Kafka plugin is `SYNC_NONE`. This is appropriate because Kafka Streams' changelog topics provide durability, and state can always be rebuilt from the changelog. If your application requires local durability guarantees beyond what Kafka provides, set `SYNC_FULL` or `SYNC_INTERVAL`.

### Transaction Isolation Levels

| Level | Description |
|-------|-------------|
| `READ_UNCOMMITTED` | Sees all data including uncommitted changes |
| `READ_COMMITTED` | Sees only committed data (default) |
| `REPEATABLE_READ` | Consistent snapshot; phantom reads possible |
| `SNAPSHOT` | Write-write conflict detection |
| `SERIALIZABLE` | Full read-write conflict detection (SSI) |

For most Kafka Streams workloads, `READ_COMMITTED` (the default) is sufficient. Higher isolation levels add overhead and are only needed when external threads access the store concurrently with custom logic.

### Object Store Configuration

When `objectStoreFsPath` is set, TidesDB operates in object store mode, storing SSTables in an external object store with a local file cache. The `ObjectStoreConfig` controls cache behavior, upload concurrency, WAL replication, and replica mode.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `localCachePath` | String | null (use db_path) | Local directory for cached SSTable files |
| `localCacheMaxBytes` | long | 0 (unlimited) | Maximum local cache size in bytes |
| `cacheOnRead` | boolean | true | Cache downloaded files locally |
| `cacheOnWrite` | boolean | true | Keep local copy after upload |
| `maxConcurrentUploads` | int | 4 | Parallel upload threads |
| `maxConcurrentDownloads` | int | 8 | Parallel download threads |
| `multipartThreshold` | long | 64 MB | Use multipart upload above this size |
| `multipartPartSize` | long | 8 MB | Multipart chunk size |
| `syncManifestToObject` | boolean | true | Upload MANIFEST after each compaction |
| `replicateWal` | boolean | true | Upload closed WAL segments for recovery |
| `walUploadSync` | boolean | false | Block flush until WAL is uploaded |
| `walSyncThresholdBytes` | long | 1 MB | Sync active WAL when it grows by this many bytes; 0 disables |
| `walSyncOnCommit` | boolean | false | Upload WAL after every commit for RPO=0 replication |
| `replicaMode` | boolean | false | Enable read-only replica mode |
| `replicaSyncIntervalUs` | long | 5000000 | MANIFEST poll interval in microseconds for replicas |
| `replicaReplayWal` | boolean | true | Replay WAL for near-real-time reads on replicas |


## TTL Support

TidesDB supports time-to-live (TTL) on individual key-value pairs. Expired entries are removed during compaction. The plugin exposes TTL in two ways.

### Default TTL

Set a default TTL that applies to all `put` operations automatically:

```java
TidesDBStoreConfig config = TidesDBStoreConfig.builder()
    .defaultTtlSeconds(3600)  // 1 hour
    .build();

KTable<String, Long> counts = input
    .groupByKey()
    .count(Materialized.as(new TidesDBStoreSupplier("expiring-counts", config)));
```

Every entry written through `put`, `putIfAbsent`, and `putAll` will expire after the configured duration.

### Per-Key TTL

For fine-grained control, use `putWithTtl` directly on the store:

```java
TidesDBStore store = (TidesDBStore) context.getStateStore("my-store");
store.putWithTtl(key, value, 300);  // expires in 5 minutes
```

A TTL of -1 means no expiration.


## B+tree KLog Format

Column families can optionally use a B+tree structure for the key log instead of the default block-based SSTable format. The B+tree format offers faster point lookups through O(log N) tree traversal at the cost of slightly higher write amplification.

```java
TidesDBStoreConfig config = TidesDBStoreConfig.builder()
    .useBtree(true)
    .build();
```

**When to use B+tree format**
- Read-heavy Kafka Streams workloads with frequent key lookups
- Interactive queries where read latency matters more than write throughput
- Large state stores where block scanning becomes expensive

**Tradeoffs**
- Slightly higher write amplification during flush
- Larger metadata overhead per node
- Block-based format may be faster for full iteration and range scans

The format is set at column family creation time and cannot be changed afterward. If you need to switch formats, delete the state store directory and let Kafka Streams rebuild from the changelog.


## Change Data Capture with Commit Hooks

TidesDB supports commit hooks, callbacks that fire synchronously after every transaction commit. This enables real-time change data capture without WAL parsing.

```java
TidesDBStore store = (TidesDBStore) context.getStateStore("my-store");

store.setCommitHook((ops, commitSeq) -> {
    for (CommitOp op : ops) {
        if (op.isDelete()) {
            System.out.println("DELETE key=" + new String(op.getKey()));
        } else {
            System.out.println("PUT key=" + new String(op.getKey()));
        }
    }
    return 0;  // 0 = success
});
```

Each `CommitOp` contains `getKey()`, `getValue()` (null for deletes), `getTtl()` (-1 for no expiry), and `isDelete()`. The `commitSeq` is monotonically increasing and can be used as a replication cursor.

To detach the hook:

```java
store.clearCommitHook();
```

Hooks execute synchronously on the committing thread. Keep the callback fast to avoid stalling writers.


## Operations and Maintenance

### Statistics

The store exposes TidesDB statistics at three levels:

**Column family statistics**
```java
TidesDBStore store = (TidesDBStore) context.getStateStore("my-store");
Stats stats = store.getStats();

System.out.println("Total keys: " + stats.getTotalKeys());
System.out.println("Data size: " + stats.getTotalDataSize());
System.out.println("Memtable size: " + stats.getMemtableSize());
System.out.println("Read amplification: " + stats.getReadAmp());
System.out.println("Cache hit rate: " + stats.getHitRate());
```

**Database-level statistics**
```java
DbStats dbStats = store.getDbStats();

System.out.println("Column families: " + dbStats.getNumColumnFamilies());
System.out.println("Memory pressure: " + dbStats.getMemoryPressureLevel());
System.out.println("Flush queue: " + dbStats.getFlushQueueSize());
System.out.println("Compaction queue: " + dbStats.getCompactionQueueSize());
System.out.println("Total SSTables: " + dbStats.getTotalSstableCount());
```

**Block cache statistics**
```java
CacheStats cacheStats = store.getCacheStats();

System.out.println("Cache enabled: " + cacheStats.isEnabled());
System.out.println("Hit rate: " + cacheStats.getHitRate());
System.out.println("Entries: " + cacheStats.getTotalEntries());
```

### Compaction and Flush

```java
// Non-blocking compaction
store.compact();

// Non-blocking flush
store.flush();

// Synchronous flush + aggressive compaction (blocks until complete)
store.purge();

// Purge all column families and drain all queues
store.purgeAll();

// Check background activity
boolean flushing = store.isFlushing();
boolean compacting = store.isCompacting();
```

Use `purge()` before backup, after bulk deletes, or during maintenance windows. Use `compact()` and `flush()` for non-blocking background work.

### WAL Sync

Force an immediate fsync of the write-ahead log:

```java
store.syncWal();
```

This is useful when running with `SYNC_NONE` or `SYNC_INTERVAL` and you need to guarantee durability at a specific point.

### Backup and Checkpoint

Online backup · copies all data to a new directory without blocking reads or writes:
```java
store.backup("/path/to/backup");
```

Lightweight checkpoint · uses hard links for near-instant snapshots (same filesystem only):
```java
store.checkpoint("/path/to/checkpoint");
```

| | `backup()` | `checkpoint()` |
|--|---|---|
| Speed | Copies every SSTable byte-by-byte | Near-instant (hard links) |
| Disk usage | Full independent copy | No extra disk until compaction removes old SSTables |
| Portability | Can be moved to another filesystem or machine | Same filesystem only |
| Use case | Archival, disaster recovery | Fast local snapshots |

### Runtime Configuration Updates

Update runtime-safe column family settings without restarting:

```java
ColumnFamilyConfig newConfig = ColumnFamilyConfig.builder()
    .writeBufferSize(256 * 1024 * 1024)
    .bloomFPR(0.001)
    .syncMode(SyncMode.SYNC_INTERVAL)
    .syncIntervalUs(100000)
    .build();

store.updateRuntimeConfig(newConfig, true);
```

Updatable settings include `writeBufferSize`, `skipListMaxLevel`, `skipListProbability`, `bloomFPR`, `indexSampleRatio`, `syncMode`, and `syncIntervalUs`.

### Range Cost Estimation

Estimate the cost of iterating between two keys without performing any disk I/O:

```java
double costA = store.rangeCost("user:0000".getBytes(), "user:0999".getBytes());
double costB = store.rangeCost("user:1000".getBytes(), "user:1099".getBytes());
```

This is useful for query planning, load balancing range scan work across threads, and monitoring data distribution changes over time.


## Unified Memtable Mode

Enable unified memtable mode to share a single memtable and WAL across all column families. This reduces write amplification for workloads with many small column families.

```java
TidesDBStoreConfig config = TidesDBStoreConfig.builder()
    .unifiedMemtable(true)
    .unifiedMemtableWriteBufferSize(0)       // 0 = auto (64 MB default)
    .unifiedMemtableSkipListMaxLevel(0)      // 0 = default (12)
    .unifiedMemtableSkipListProbability(0)   // 0 = default (0.25)
    .unifiedMemtableSyncMode(0)              // 0 = SYNC_NONE
    .unifiedMemtableSyncIntervalUs(0)        // 0 = default
    .build();

KTable<String, Long> counts = input
    .groupByKey()
    .count(Materialized.as(new TidesDBStoreSupplier("unified-counts", config)));
```

When unified memtable is enabled, all column families in the database instance share a single memtable and write-ahead log. This is useful when you have many column families with small write volumes, as it avoids per-CF WAL overhead.


## Object Store Mode

TidesDB supports storing SSTables in an external object store (filesystem-backed or S3-compatible) with a local file cache. This enables tiered storage, remote replication, and read-only replicas.

### Basic Object Store Setup

```java
import com.tidesdb.ObjectStoreConfig;

TidesDBStoreConfig config = TidesDBStoreConfig.builder()
    .objectStoreFsPath("/mnt/shared/tidesdb-objects")
    .objectStoreConfig(ObjectStoreConfig.builder()
        .localCacheMaxBytes(1024 * 1024 * 1024)   // 1 GB local cache
        .maxConcurrentUploads(8)
        .maxConcurrentDownloads(16)
        .syncManifestToObject(true)
        .replicateWal(true)
        .build())
    .build();

KTable<String, Long> counts = input
    .groupByKey()
    .count(Materialized.as(new TidesDBStoreSupplier("object-store-counts", config)));
```

### Replica Mode

Open a state store as a read-only replica that polls for updates from the object store:

```java
TidesDBStoreConfig config = TidesDBStoreConfig.builder()
    .objectStoreFsPath("/mnt/shared/tidesdb-objects")
    .objectStoreConfig(ObjectStoreConfig.builder()
        .replicaMode(true)
        .replicaSyncIntervalUs(5000000)   // poll every 5 seconds
        .replicaReplayWal(true)           // near-real-time reads
        .build())
    .build();
```

To switch a replica to primary mode at runtime:

```java
TidesDBStore store = (TidesDBStore) context.getStateStore("my-store");
store.promoteToPrimary();
```

### Column Family Object Store Options

Per-column-family options control SSTable sizing and compaction behavior in object store mode:

```java
TidesDBStoreConfig config = TidesDBStoreConfig.builder()
    .objectStoreFsPath("/mnt/shared/tidesdb-objects")
    .objectLazyCompaction(true)                // compact less aggressively
    .objectPrefetchCompaction(true)            // download all inputs before merge
    .build();
```


## Column Family Management

The store exposes column family management operations for advanced use cases.

### Listing Column Families

```java
TidesDBStore store = (TidesDBStore) context.getStateStore("my-store");
String[] cfNames = store.listColumnFamilies();
for (String name : cfNames) {
    System.out.println("Column family: " + name);
}
```

### Cloning a Column Family

Create a complete, independent copy of an existing column family:

```java
store.cloneColumnFamily("default", "snapshot_cf");
```

The clone contains all data from the source at the time of cloning. Modifications to one do not affect the other.

### Renaming a Column Family

Atomically rename a column family. Waits for any in-progress flush or compaction to complete before renaming:

```java
store.renameColumnFamily("old_name", "new_name");
```

### Dropping a Column Family

```java
store.dropColumnFamily("old_cf");
```

### Custom Comparators

Register a custom comparator for use with column families. Built-in comparators include `"memcmp"` (default), `"lexicographic"`, `"uint64"`, `"int64"`, `"reverse"`, and `"case_insensitive"`.

```java
TidesDBStoreConfig config = TidesDBStoreConfig.builder()
    .comparatorName("reverse")
    .build();

KTable<String, Long> counts = input
    .groupByKey()
    .count(Materialized.as(new TidesDBStoreSupplier("reverse-sorted", config)));
```

Comparators are set at column family creation time and cannot be changed afterward.


## Replica Promotion

If the database was opened in replica mode, switch to primary mode:

```java
TidesDBStore store = (TidesDBStore) context.getStateStore("my-store");
store.promoteToPrimary();
```


## Benchmarking

The plugin includes a comprehensive benchmark suite comparing TidesDB against RocksDB across multiple workload types. Benchmarks are fully configurable via system properties.

### Running Benchmarks

```bash
# Run with default settings
mvn test -Dtest=StateStoreBenchmark \
    -DargLine="-Djava.library.path=/usr/local/lib"

# Run with custom data directory (e.g., fast SSD)
mvn test -Dtest=StateStoreBenchmark \
    -DargLine="-Djava.library.path=/usr/local/lib -Dbenchmark.data.dir=/mnt/ssd/bench"

# Run with custom parameters
mvn test -Dtest=StateStoreBenchmark \
    -DargLine="-Djava.library.path=/usr/local/lib \
               -Dbenchmark.sizes=1000,10000,100000 \
               -Dbenchmark.value.size=256 \
               -Dbenchmark.mixed.ratio=80 \
               -Dbenchmark.percentiles=true"
```

Or use the included runner script:

```bash
./run.sh -b                          # Run benchmarks
./run.sh -b -d /mnt/fast-ssd/bench  # Run on specific directory
./run.sh -a                          # Run tests, benchmarks, and generate charts
```

### Benchmark Parameters

All parameters are configurable via `-D` system properties:

| Property | Default | Description |
|----------|---------|-------------|
| `benchmark.data.dir` | (temp) | Data directory for benchmark databases |
| `benchmark.sizes` | 1000,5000,10000,50000,100000 | Comma-separated operation counts for standard benchmarks |
| `benchmark.large.sizes` | 100000,...,25000000 | Sizes for large dataset benchmarks |
| `benchmark.threads` | 1,2,4,8,16 | Thread counts for concurrent access benchmarks |
| `benchmark.value.size` | 64 | Value size in bytes for standard benchmarks |
| `benchmark.large.value.size` | 10240 | Value size in bytes for large-value benchmarks |
| `benchmark.warmup` | 3 | Number of warmup iterations before measurement |
| `benchmark.iterations` | 5 | Number of measurement iterations (for statistical accuracy) |
| `benchmark.compaction.batch` | 50000 | Batch size for compaction pressure test |
| `benchmark.compaction.batches` | 5 | Number of batches for compaction pressure test |
| `benchmark.range.data` | 50000 | Data size for range scan benchmark |
| `benchmark.range.sizes` | 10,100,1000,5000,10000 | Comma-separated range sizes |
| `benchmark.mixed.ratio` | 50 | Read percentage for mixed workload (0-100) |
| `benchmark.seed` | 42 | Random seed for reproducibility |
| `benchmark.percentiles` | true | Enable per-operation latency percentile tracking |

### Benchmark Workloads

The suite runs the following workloads:

- Sequential Writes · ordered key insertion
- Random Writes · random key insertion
- Sequential Reads · ordered key lookups
- Random Reads · random key lookups
- Mixed Workload · configurable read/write ratio
- Range Scans · iterator-based range queries
- Bulk Writes · batched `putAll` operations
- Update Workload · overwriting existing keys
- Large Values · configurable large value sizes
- Full Iteration · complete store scan
- Delete Workload · sequential key deletion
- Large Datasets · up to 25M keys with warmup and statistical analysis (mean, stddev)
- Concurrent Access · multi-threaded mixed workload with throughput and scalability analysis
- Compaction Pressure · accumulated data over multiple batches to stress compaction
- Memory/CPU Metrics · write/read performance with heap memory and CPU usage tracking
- Latency Percentiles · per-operation nanosecond latencies with p50, p90, p95, p99, p99.9, and max

### Generating Charts

After running benchmarks, generate visualizations:

```bash
./run.sh -c
```

This creates PNG charts in a timestamped `charts_*` directory including performance comparisons, speedup charts, throughput comparisons, error bar plots for large datasets, concurrent scalability curves, compaction pressure plots, memory usage comparisons, and a summary table.

Requirements for chart generation, Python 3, pandas, matplotlib, seaborn (installed automatically into a virtual environment by the runner script).


## Running Tests

```bash
# Run unit tests
mvn test -Dtest=TidesDBStoreTest \
    -DargLine="-Djava.library.path=/usr/local/lib"

# Run all tests
mvn test -DargLine="-Djava.library.path=/usr/local/lib"
```


## Performance Tuning

### Write-Heavy Workloads

For workloads that prioritize write throughput:

```java
TidesDBStoreConfig config = TidesDBStoreConfig.builder()
    .compressionAlgorithm(CompressionAlgorithm.LZ4_FAST_COMPRESSION)
    .syncMode(SyncMode.SYNC_NONE)
    .writeBufferSize(128 * 1024 * 1024)
    .enableBloomFilter(true)
    .bloomFPR(0.01)
    .numFlushThreads(4)
    .numCompactionThreads(4)
    .build();
```

### Read-Heavy Workloads

For workloads that prioritize read latency:

```java
TidesDBStoreConfig config = TidesDBStoreConfig.builder()
    .useBtree(true)
    .blockCacheSize(256 * 1024 * 1024)
    .enableBloomFilter(true)
    .bloomFPR(0.001)
    .enableBlockIndexes(true)
    .compressionAlgorithm(CompressionAlgorithm.LZ4_COMPRESSION)
    .build();
```

### Memory-Constrained Environments

For environments with limited memory:

```java
TidesDBStoreConfig config = TidesDBStoreConfig.builder()
    .blockCacheSize(16 * 1024 * 1024)
    .writeBufferSize(16 * 1024 * 1024)
    .maxMemoryUsage(256 * 1024 * 1024)
    .maxOpenSSTables(64)
    .build();
```

### Fair Benchmarking Against RocksDB

The benchmark suite configures both engines with equivalent settings to ensure a fair comparison:

| Setting | TidesDB | RocksDB |
|---------|---------|--------|
| Compression | LZ4 | LZ4 |
| Bloom filter | 1% FPR | 10 bits/key (~1% FPR) |
| Block cache | 64 MB | 64 MB (LRU) |
| Write buffer | 64 MB | 64 MB |
| Background threads | 2 flush + 2 compaction | 4 (maxBackgroundJobs) |
| Sync / durability | SYNC_NONE | sync=false, WAL enabled |
| Block indexes | Enabled | Binary search |
| LSM levels | 5 | 5 |
| Bulk writes | Single transaction | WriteBatch |

The one structural difference that cannot be eliminated is transaction overhead. TidesDB requires all operations to go through transactions (begin -> op -> commit), while RocksDB supports direct `db.put()`/`db.get()` calls. The plugin mitigates this with transaction reuse via `reset()`, but there is still a per-operation cost that is inherent to TidesDB's MVCC architecture. This cost is most visible on small-data read benchmarks; at larger dataset sizes, disk I/O dominates and the gap closes.


## Architecture

### Store Lifecycle

1. Creation · `TidesDBStoreSupplier.get()` or `TidesDBStoreBuilder.build()` creates a `TidesDBStore` instance with the provided configuration.
2. Initialization · `init()` is called by Kafka Streams with the state directory. The plugin opens a TidesDB database at `<stateDir>/<storeName>`, creates or opens the configured column family, and initializes a reusable transaction for the hot path.
3. Operation · `get`, `put`, `delete`, `putAll`, `range`, and `all` map directly to TidesDB transactions. Single-operation calls (`get`, `put`) reuse a pooled transaction via `reset()` to avoid allocation overhead. Multi-operation calls (`putAll`, `putIfAbsent`, `delete`) use fresh transactions for atomicity.
4. Flush · `flush()` triggers a non-blocking memtable flush to disk.
5. Close · `close()` frees the reusable transaction and closes the TidesDB database.

### Transaction Reuse

The plugin maintains a single reusable transaction for the `get` and `put` hot path. After each commit, the transaction is reset via `reset()` instead of being freed and reallocated. This retains internal buffers and avoids repeated allocation overhead, which matters in Kafka Streams where every record processed may trigger a state store read or write.

When the reusable transaction is unavailable (e.g., concurrent access from a punctuator), the plugin falls back to creating a new transaction.

### Direct Access

For advanced use cases, the store exposes direct access to the underlying TidesDB objects:

```java
TidesDBStore store = (TidesDBStore) context.getStateStore("my-store");
TidesDB db = store.getDb();
ColumnFamily cf = store.getColumnFamily();
```

Use with caution · operations on these objects bypass the store's transaction management.


## Examples

### Word Count

```java
import com.tidesdb.kafka.store.TidesDBStoreSupplier;

StreamsBuilder builder = new StreamsBuilder();

KStream<String, String> lines = builder.stream("text-input");

KTable<String, Long> wordCounts = lines
    .flatMapValues(line -> Arrays.asList(line.toLowerCase().split("\\W+")))
    .groupBy((key, word) -> word)
    .count(Materialized.as(new TidesDBStoreSupplier("word-counts")));

wordCounts.toStream()
    .to("word-counts-output", Produced.with(Serdes.String(), Serdes.Long()));
```

### Windowed Aggregation

```java
KStream<String, String> events = builder.stream("events");

events
    .groupByKey()
    .windowedBy(TimeWindows.ofSizeWithNoGrace(Duration.ofMinutes(5)))
    .count()
    .toStream()
    .to("windowed-output");
```

### Custom Aggregation with Config

```java
TidesDBStoreConfig config = TidesDBStoreConfig.builder()
    .compressionAlgorithm(CompressionAlgorithm.ZSTD_COMPRESSION)
    .defaultTtlSeconds(86400)  // 24-hour expiration
    .useBtree(true)
    .build();

activities
    .groupByKey()
    .aggregate(
        UserStats::new,
        (userId, activity, stats) -> { stats.addActivity(activity); return stats; },
        Materialized.<String, UserStats>as(new TidesDBStoreSupplier("user-stats", config))
            .withKeySerde(Serdes.String())
            .withValueSerde(new UserStatsSerde())
    );
```

--

TidesDB Kafka Streams plugin repository: <https://github.com/tidesdb/tidesdb-kafka>

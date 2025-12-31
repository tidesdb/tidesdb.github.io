---
title: "Using TidesDB with Java via JExtract"
description: "Step-by-step guide to using TidesDB with Java via JExtract. Learn how v7.0.6's simplified db.h header enables seamless Java bindings for high performance key-value storage."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-ifreestock-585753.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-ifreestock-585753.jpg
---

<div class="article-image">

![Using TidesDB with Java Using JExtract](/pexels-ifreestock-585753.jpg)

</div>

*by Alex Gaetano Padula*

*published on December 31th, 2025*

It's come to my attention recently that TidesDB had issues being binded to.  This was brought up by an awesome user on the TidesDB <a href="https://discord.gg/tWEmjR66cy">Discord server</a>.  

The main issue was that the main tidesdb.h header contained too many unrequired structs, and types for an FFI. The generator could not handle the structure definitions and ended up with up errors such like below:

```
source.h:200:1: warning: Skipping _dispatch_source_type_vnode (type Declared(dispatch_source_type_s) is not supported)
source.h:211:1: warning: Skipping _dispatch_source_type_write (type Declared(dispatch_source_type_s) is not supported)
data.h:55:40: warning: Skipping _dispatch_data_empty (type Declared(dispatch_data_s) is not supported)
math.h:65:15: warning: Skipping HUGE_VALL (type LongDouble is not supported)
fatal: Unexpected exception java.lang.IllegalArgumentException: Type not supported: ATOMIC = (typedef Optional[queue_node_t] = Declared(queue_node_t))* occurred
```

To fix the issue I created a new db.h header file that only contains opaque pointers for all structs (avoiding the problematic internal atomic fields).  I've exposed only the public API functions that are absolutely necessary.  No _Atomic types which seemed to be unsupported by jextract.

With that, the layout of the db.h is simpler for a generator to take and parse.  

You can find the `db.h` header file <a href="https://github.com/tidesdb/tidesdb/blob/master/src/db.h">here</a>.  This update has been merged and is part of the v7.0.6 PATCH.

If you are going to follow along you will need **Java 21 or later** as it is required for Foreign Function & Memory API, the TidesDB shared library, and the jextract tool.  I am using Ubuntu for this example.

Now let's get into how you can utilize TidesDB's C API with Java.

Once I've built and installed the TidesDB shared library, I can do the following in a specific directory in my case i used _tidesdb-java_.
```bash
jextract -t com.tidesdb.tidesdb -l tidesdb --output src /usr/local/include/tidesdb/db.h
```

_jextract [options] <header-file\>_

- t <package\> · Target package name
- l <library\> · Native/Shared library to link against
- output <dir\> · Output directory

What this will do is generate a set of java files in the src directory that can be used to bind to the TidesDB shared library.  

_/tidesdb-java/src/com/tidesdb/tidesdb$_
```bash
db_h.java             tidesdb_column_family_config_t.java  tidesdb_stats_t.java
__fsid_t.java         tidesdb_column_family_t.java         tidesdb_t.java
itimerspec.java       tidesdb_comparator_fn.java           tidesdb_txn_t.java
__locale_struct.java  tidesdb_config_t.java                timespec.java
max_align_t.java      tidesdb_iter_t.java                  tm.java
```

_db_h.java is the main entry point with all the native functions._

Now we are going to go through how you can use TidesDB with Java.

### Opening a Database

```java
import com.tidesdb.tidesdb.*;
import java.lang.foreign.*;

public class TidesDBExample {
    public static void main(String[] args) {
        try (Arena arena = Arena.ofConfined()) {

            MemorySegment config = db_h.tidesdb_default_config(arena);
            
            // Set database path
            MemorySegment dbPath = arena.allocateUtf8String("/path/to/database");
            tidesdb_config_t.db_path(config, dbPath);
            
            // Configure threads and cache
            tidesdb_config_t.num_flush_threads(config, 4);
            tidesdb_config_t.num_compaction_threads(config, 2);
            tidesdb_config_t.block_cache_size(config, 1024 * 1024 * 100); // 100MB
            tidesdb_config_t.max_open_sstables(config, 100);
            
            MemorySegment dbPtr = arena.allocate(ValueLayout.ADDRESS);
            int result = db_h.tidesdb_open(config, dbPtr);
            
            if (result != db_h.TDB_SUCCESS()) {
                System.err.println("Failed to open database");
                return;
            }
            
            MemorySegment db = dbPtr.get(ValueLayout.ADDRESS, 0);
            
            // Use the database...

            db_h.tidesdb_close(db);
        }
    }
}
```

### Creating a Column Family

```java
// Get default column family configuration, is optimized for performance
MemorySegment cfConfig = db_h.tidesdb_default_column_family_config(arena);

// Configure a column family 
tidesdb_column_family_config_t.write_buffer_size(cfConfig, 1024 * 1024 * 64); // 64MB
tidesdb_column_family_config_t.level_size_ratio(cfConfig, 10);
tidesdb_column_family_config_t.min_levels(cfConfig, 3);
tidesdb_column_family_config_t.enable_bloom_filter(cfConfig, 1); // Enable
tidesdb_column_family_config_t.bloom_fpr(cfConfig, 0.01); // 1% false positive rate
tidesdb_column_family_config_t.compression_algo(cfConfig, 1); // Compression algorithm
tidesdb_column_family_config_t.enable_block_indexes(cfConfig, 1);

// Create a new column family
MemorySegment cfName = arena.allocateUtf8String("my_column_family");
int result = db_h.tidesdb_create_column_family(db, cfName, cfConfig);

if (result != db_h.TDB_SUCCESS()) {
    System.err.println("Failed to create column family");
}
```

### Getting a Column Family

```java
MemorySegment cfName = arena.allocateUtf8String("my_column_family");
MemorySegment cf = db_h.tidesdb_get_column_family(db, cfName);

if (cf.address() == 0) {
    System.err.println("Column family not found");
}
```

### Working with Transactions

#### Begin a Transaction

```java
// Begin transaction with default isolation level (TDB_ISOLATION_READ_COMMITTED)
MemorySegment txnPtr = arena.allocate(ValueLayout.ADDRESS);
int result = db_h.tidesdb_txn_begin(db, txnPtr);

if (result != db_h.TDB_SUCCESS()) {
    System.err.println("Failed to begin transaction");
    return;
}

MemorySegment txn = txnPtr.get(ValueLayout.ADDRESS, 0);
```

#### Put Operation (Insert/Update)

```java
// Prepare key and value
String keyStr = "user:1001";
String valueStr = "John Doe";

MemorySegment key = arena.allocateUtf8String(keyStr);
MemorySegment value = arena.allocateUtf8String(valueStr);

// Put with TTL (0 = no expiration)
long ttl = 0;
int result = db_h.tidesdb_txn_put(
    txn,
    cf,
    key,
    keyStr.length(),
    value,
    valueStr.length(),
    ttl
);

if (result != db_h.TDB_SUCCESS()) {
    System.err.println("Failed to put key-value");
}
```

#### Get Operation (Retrieve)

```java
String keyStr = "user:1001";
MemorySegment key = arena.allocateUtf8String(keyStr);

// Allocate pointers for output
MemorySegment valuePtr = arena.allocate(ValueLayout.ADDRESS);
MemorySegment valueSizePtr = arena.allocate(ValueLayout.JAVA_LONG);

int result = db_h.tidesdb_txn_get(
    txn,
    cf,
    key,
    keyStr.length(),
    valuePtr,
    valueSizePtr
);

if (result == db_h.TDB_SUCCESS()) {
    MemorySegment valueData = valuePtr.get(ValueLayout.ADDRESS, 0);
    long valueSize = valueSizePtr.get(ValueLayout.JAVA_LONG, 0);
    
    // Read the value
    byte[] valueBytes = new byte[(int) valueSize];
    MemorySegment.copy(valueData, ValueLayout.JAVA_BYTE, 0, valueBytes, 0, (int) valueSize);
    String value = new String(valueBytes);
    
    System.out.println("Retrieved value: " + value);
    
} else {
    System.err.println("Key not found or error occurred");
}
```

#### Delete Operation

```java
String keyStr = "user:1001";
MemorySegment key = arena.allocateUtf8String(keyStr);

int result = db_h.tidesdb_txn_delete(
    txn,
    cf,
    key,
    keyStr.length()
);

if (result != db_h.TDB_SUCCESS()) {
    System.err.println("Failed to delete key");
}
```

#### Commit Transaction

```java
int result = db_h.tidesdb_txn_commit(txn);

if (result != db_h.TDB_SUCCESS()) {
    System.err.println("Failed to commit transaction");
}
```

#### Rollback Transaction

```java
int result = db_h.tidesdb_txn_rollback(txn);

if (result != db_h.TDB_SUCCESS()) {
    System.err.println("Failed to rollback transaction");
}
```

### Transaction with Custom Isolation Level

```java
// - TDB_ISOLATION_READ_UNCOMMITTED (0)
// - TDB_ISOLATION_READ_COMMITTED (1)
// - TDB_ISOLATION_REPEATABLE_READ (2)
// - TDB_ISOLATION_SNAPSHOT (3)
// - TDB_ISOLATION_SERIALIZABLE (4)
int isolationLevel = db_h.TDB_ISOLATION_SERIALIZABLE();
MemorySegment txnPtr = arena.allocate(ValueLayout.ADDRESS);

int result = db_h.tidesdb_txn_begin_with_isolation(db, isolationLevel, txnPtr);

if (result != db_h.TDB_SUCCESS()) {
    System.err.println("Failed to begin transaction with isolation level");
    return;
}

MemorySegment txn = txnPtr.get(ValueLayout.ADDRESS, 0);
```

## Full Example

```java
import com.tidesdb.tidesdb.*;
import java.lang.foreign.*;

public class TidesDBCompleteExample {
    public static void main(String[] args) {
        try (Arena arena = Arena.ofConfined()) {
            // Open a new database
            MemorySegment config = db_h.tidesdb_default_config(arena);
            MemorySegment dbPath = arena.allocateUtf8String("./mydb");
            tidesdb_config_t.db_path(config, dbPath);
            
            MemorySegment dbPtr = arena.allocate(ValueLayout.ADDRESS);
            if (db_h.tidesdb_open(config, dbPtr) != db_h.TDB_SUCCESS()) {
                System.err.println("Failed to open database");
                return;
            }
            MemorySegment db = dbPtr.get(ValueLayout.ADDRESS, 0);
            
            MemorySegment cfConfig = db_h.tidesdb_default_column_family_config(arena);
            MemorySegment cfName = arena.allocateUtf8String("users");
            
            if (db_h.tidesdb_create_column_family(db, cfName, cfConfig) != db_h.TDB_SUCCESS()) {
                System.out.println("Column family might already exist");
            }
            

            MemorySegment cf = db_h.tidesdb_get_column_family(db, cfName);
            
            // Begin transaction
            MemorySegment txnPtr = arena.allocate(ValueLayout.ADDRESS);
            if (db_h.tidesdb_txn_begin(db, txnPtr) != db_h.TDB_SUCCESS()) {
                System.err.println("Failed to begin transaction");
                db_h.tidesdb_close(db);
                return;
            }
            MemorySegment txn = txnPtr.get(ValueLayout.ADDRESS, 0);
            
            // Write data
            String key = "user:1";
            String value = "Alice";
            MemorySegment keyMem = arena.allocateUtf8String(key);
            MemorySegment valueMem = arena.allocateUtf8String(value);
            
            if (db_h.tidesdb_txn_put(txn, cf, keyMem, key.length(), 
                                      valueMem, value.length(), 0) == db_h.TDB_SUCCESS()) {
                System.out.println("Put successful");
            }
            
            // Retrieve data
            MemorySegment valuePtr = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment valueSizePtr = arena.allocate(ValueLayout.JAVA_LONG);
            
            if (db_h.tidesdb_txn_get(txn, cf, keyMem, key.length(), 
                                      valuePtr, valueSizePtr) == db_h.TDB_SUCCESS()) {
                MemorySegment valueData = valuePtr.get(ValueLayout.ADDRESS, 0);
                long valueSize = valueSizePtr.get(ValueLayout.JAVA_LONG, 0);
                
                byte[] valueBytes = new byte[(int) valueSize];
                MemorySegment.copy(valueData, ValueLayout.JAVA_BYTE, 0, 
                                  valueBytes, 0, (int) valueSize);
                System.out.println("Retrieved: " + new String(valueBytes));
            }
            
      
            if (db_h.tidesdb_txn_commit(txn) == db_h.TDB_SUCCESS()) {
                System.out.println("Transaction committed");
            }
            
            db_h.tidesdb_close(db);
            
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
```

## Configuration Options

### Database Configuration

- `db_path` · Path to database directory
- `num_flush_threads` · Number of threads for flushing memtables
- `num_compaction_threads` · Number of threads for compaction
- `log_level` · Logging level
- `block_cache_size` · Size of block cache in bytes
- `max_open_sstables` · Maximum number of open SSTable files

### Column Family Configuration

- `write_buffer_size` · Size of write buffer (memtable)
- `level_size_ratio` · Size ratio between levels
- `min_levels` · Minimum number of levels
- `dividing_level_offset` · Level offset for dividing
- `klog_value_threshold` · Threshold for key-log values
- `compression_algo` · Compression algorithm to use
- `enable_bloom_filter` · Enable/disable bloom filters
- `bloom_fpr` · Bloom filter false positive rate
- `enable_block_indexes` · Enable/disable block indexes
- `index_sample_ratio` · Index sampling ratio
- `block_index_prefix_len` · Block index prefix length
- `sync_mode` · Synchronization mode
- `sync_interval_us` · Sync interval in microseconds
- `skip_list_max_level` · Maximum skip list level
- `skip_list_probability` · Skip list probability
- `default_isolation_level` · Default transaction isolation level
- `min_disk_space` · Minimum required disk space
- `l1_file_count_trigger` · L1 compaction trigger
- `l0_queue_stall_threshold` · L0 queue stall threshold

## Error Handling

All TidesDB functions return an integer status code:
- `TDB_SUCCESS` (0) · Operation succeeded
- Non-zero · Error occurred (check TidesDB documentation <a href="reference/c/#:~:text=also%20prevents%20collisions.-,Error%20Codes,-TidesDB%20provides%20detailed" target="_blank">here</a>)

Always check return values
```java
int result = db_h.tidesdb_open(config, dbPtr);
if (result != db_h.TDB_SUCCESS()) {
    // Handle error
}
```

_A little note, arena manages native memory allocation. Using try-with-resources ensures all native memory allocated through the arena is automatically freed when the block exits, preventing memory leaks. This is crucial when working with native libraries._

## Running Your Application

Compile and run with Java 21+
```bash
javac --enable-preview -cp . YourApp.java
java --enable-preview -Djava.library.path=/path/to/tidesdb/lib YourApp
```

### End

As you can see it's not too hard to get going with TidesDB and Java, I'd imagine as I've seen this done with TidesDB in other languages like Rust (bindgen), this process is fast and easy.  Maybe down the line I'll work on a Rust version of this article.

---

*Thanks for reading!*
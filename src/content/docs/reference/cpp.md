---
title: TidesDB C++ Reference
description: TidesDB C++ FFI Library reference.
---

> You must make sure you have the TidesDB shared C library installed on your system. Be sure to also compile with `TIDESDB_WITH_SANITIZER` and `TIDESDB_BUILD_TESTS` OFF. You will also require a *C++11* compatible compiler.

## Build and install
```bash
cmake -S . -B build
cmake --build build
cmake --install build
```

### Linking
```cmake
# Find the TidesDB C library
find_library(LIBRARY_TIDEDB NAMES tidesdb REQUIRED)

# Find the TidesDB C++ binding
find_library(LIBRARY_TIDEDB_CPP NAMES tidesdb_cpp REQUIRED)

# Link with your target
target_link_libraries(your_target PRIVATE ${LIBRARY_TIDEDB_CPP} ${LIBRARY_TIDEDB})
```

## Usage
### Open and Close
```cpp
#include <tidesdb.hpp>

int main() {
    TidesDB::DB db;
    db.Open("your_db_directory");

    /* Database operations... */

    db.Close();
    return 0;
}
```

### Column Family Management
```cpp
/* Create a column family with custom parameters */
db.CreateColumnFamily(
    "users",                           /* Column family name       */
    (1024 * 1024) * 64,                /* Flush threshold (64MB)   */
    TDB_DEFAULT_SKIP_LIST_MAX_LEVEL,   /* Max level for skip list  */
    TDB_DEFAULT_SKIP_LIST_PROBABILITY, /* Skip list probability    */
    true,                              /* Enable compression       */
    TIDESDB_COMPRESSION_LZ4,           /* Use LZ4 compression      */
    true                               /* Enable bloom filter      */
);

/* List all column families */
std::vector<std::string> families;
db.ListColumnFamilies(&families);
for (const auto& family : families) {
    std::cout << "Found column family: " << family << std::endl;
}

/* Get column family statistics */
TidesDB::ColumnFamilyStat stat;
db.GetColumnFamilyStat("users", &stat);
std::cout << "Memtable size: " << stat.memtable_size << " bytes" << std::endl;
std::cout << "Number of SSTables: " << stat.num_sstables << std::endl;

/* Drop a column family */
db.DropColumnFamily("users");
```

### Basic Key-Value Operations
```cpp
/* Create binary key and value */
std::vector<uint8_t> key = {1, 2, 3, 4};
std::vector<uint8_t> value = {10, 20, 30, 40};

/* Insert with no TTL */
db.Put("users", &key, &value, std::chrono::seconds(0));

/* Insert with 1 hour TTL */
db.Put("users", &key, &value, std::chrono::seconds(3600));

/* Retrieve a value */
std::vector<uint8_t> retrieved_value;
db.Get("users", &key, &retrieved_value);

/* Delete a key */
db.Delete("users", &key);
```

### Range Queries
```cpp
std::vector<uint8_t> start_key = {1, 0, 0};
std::vector<uint8_t> end_key = {1, 255, 255};
std::vector<std::pair<std::vector<uint8_t>, std::vector<uint8_t>>> results;

db.Range("users", &start_key, &end_key, &results);

for (const auto& [k, v] : results) {
    /* Process key-value pairs.... */
}

/* Delete a range of keys */
db.DeleteByRange("users", &start_key, &end_key);
```

### Transactions
```cpp
TidesDB::Txn txn(&db);
txn.Begin();

/* Perform multiple operations atomically */
std::vector<uint8_t> key1 = {1, 1};
std::vector<uint8_t> value1 = {10, 10};
txn.Put(&key1, &value1, std::chrono::seconds(0));

std::vector<uint8_t> key2 = {2, 2};
std::vector<uint8_t> value2 = {20, 20};
txn.Put(&key2, &value2, std::chrono::seconds(0));

/* Read within the transaction */
std::vector<uint8_t> read_value;
txn.Get(&key1, &read_value);

/* Delete within the transaction */
txn.Delete(&key1);

/* Commit the transaction */
txn.Commit();

/* Or roll back if needed
 * txn.Rollback(); */
```

### Cursors
```cpp
TidesDB::Cursor cursor(&db, "users");
cursor.Init();

std::vector<uint8_t> key, value;
while (cursor.Get(key, value) == 0) {
    /* Process key and value */

    /* Move to next entry */
    cursor.Next();

    /* Or move to previous entry
    * cursor.Prev(); */
}

```

### Compaction Management
```cpp
/* Manual compaction with 4 threads */
db.CompactSSTables("users", 4);

/* Automated incremental merges (run every 60 seconds if at least 5 SSTables exist) */
db.StartIncrementalMerges("users", std::chrono::seconds(60), 5);
```

### Exception Handling Example
```cpp
try {
    db.Open("non_existent_directory");
} catch (const std::runtime_error& e) {
    std::cerr << "Database error: " << e.what() << std::endl;
    /* The error message will contain both the error code and description
     * Format: "Error {code}: {message}" */
}
```
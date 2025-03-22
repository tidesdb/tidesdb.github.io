---
title: TidesDB GO Reference
description: TidesDB GO FFI Library reference.
---

> You must make sure you have the TidesDB shared C library installed on your system. Be sure to also compile with `TIDESDB_WITH_SANITIZER` and `TIDESDB_BUILD_TESTS` OFF.

## Installing
```go
go get github.com/tidesdb/tidesdb-go
```

## Usage

### Opening and closing
```go
db, err := tidesdb_go.Open("/path/to/db") // will reopen the database if it already exists
if err != nil {
...
}
defer db.Close() // Closes TidesDB gracefully
```

### Creating and dropping a column family
Column families are used to store data in TidesDB. You can create a column family using the `CreateColumnFamily` method.
```go
err := db.CreateColumnFamily("example_cf", 1024*1024*64, 12, 0.24, true, int(tidesdb_go.TDB_COMPRESS_SNAPPY), true)
if err != nil {
...
}

// You can also drop a column family using the `DropColumnFamily` method.
err = db.DropColumnFamily("example_cf")
if err != nil {
...
}
```

### CRUD operations

#### Writing data
```go
err := db.Put("example_cf", []byte("key"), []byte("value"), -1)
if err != nil {
...
}
```

With TTL
```go
err := db.Put("example_cf", []byte("key"), []byte("value"), time.Now().Add(10*time.Second).Unix())
if err != nil {
...
}
```

#### Reading data
```go
value, err := db.Get("example_cf", []byte("key"))
if err != nil {
...
}
fmt.Println(string(value))
```

#### Deleting data
```go
err := db.Delete("example_cf", []byte("key"))
if err != nil {
...
}
```

##### Deleting by range
```go
// Delete all key-value pairs between "start_key" and "end_key" atomically
err := db.DeleteByRange("example_cf", []byte("start_key"), []byte("end_key"))
if err != nil {
...
}
```

### Iterating over data
```go
cursor, err := db.CursorInit("example_cf")
if err != nil {
...
}
defer cursor.Free()

for {
key, value, err := cursor.Get()
if err != nil {
    break
}
fmt.Printf("Key: %s, Value: %s\n", key, value)

cursor.Next() // or cursor.Prev()
}
```

### Transactions
```go
txn, err := db.BeginTxn("example_cf")
if err != nil {
...
}
defer txn.Free()

err = txn.Put([]byte("key"), []byte("value"), 0)
if err != nil {
...
}

// You can also use txn.Delete(), txn.Get()

err = txn.Commit()
if err != nil {
...
}
```

### Range queries
```go
// Get all key-value pairs between "start_key" and "end_key"
pairs, err := db.Range("example_cf", []byte("start_key"), []byte("end_key"))
if err != nil {
...
}

for _, pair := range pairs {
    key := pair[0]
    value := pair[1]
    fmt.Printf("Key: %s, Value: %s\n", key, value)
}
```

### Compaction
Compaction is done manually or in background incrementally.

Merging operations, pair and merge sstables, removing expired keys if TTL set and tombstoned data.

#### Manual
```go
err := db.CompactSSTables("example_cf", 4) // 4 is the number of threads to use for compaction. Each thread will compact a pair of sstables.
if err != nil {
    ...
}
```

#### Background
```go
err := db.StartIncrementalMerge("example_cf", 60, 1000) // merge a pair of sstables starting at oldest pair every 60 seconds only when we have a minimum of 1000 sstables
if err != nil {
...
}
```
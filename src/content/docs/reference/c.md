---
title: TidesDB C Reference
description: TidesDB C FFI Library reference.
---

## Error Handling
All TidesDB methods return a `tidesdb_err_t*` which contains an error code and message. If no error occurs, NULL is returned.

```c
typedef struct
{
    int code;
    char *message;
} tidesdb_err_t;
```

## Public Methods Reference

### Database Operations

#### Opening a Database
Opens a TidesDB database instance at the specified path.
```c
tidesdb_t *tdb = NULL;
tidesdb_err_t *err = tidesdb_open("your_tdb_directory", &tdb);
if (err != NULL) {
    printf("Error: %s (code: %d)\n", err->message, err->code);
    tidesdb_err_free(err);
    return 1;
}

/* 
 * If we get here, TidesDB opened successfully.
 * We can now perform operations.
 */
printf("TidesDB opened successfully\n");
```

#### Closing a Database
Gracefully closes a TidesDB database instance.

```c
tidesdb_err_t *err = tidesdb_close(tdb);
if (err != NULL) {
   printf("Error closing TidesDB: %s (code: %d)\n", err->message, err->code);
   tidesdb_err_free(err);
   return 1;
}

/*
* At this point, we have successfully closed TidesDB
* and released all associated resources. Any further
* operations on tdb would be invalid.
*/
printf("TidesDB closed successfully\n");
```

### Column Family Operations
#### Creating a Column Family
Creates a new column family with specified configuration.
```c
/* 
 * Create a column family with Snappy compression and bloom filters
 * This will optimize read performance while still maintaining
 * good compression ratios for storage efficiency
 */
tidesdb_err_t *err = tidesdb_create_column_family(
    tdb,                               /* TidesDB instance                */
    "users",                           /* Column family name               */
    (1024 * 1024) * 128,               /* Memtable flush threshold (128MB) */
    TDB_DEFAULT_SKIP_LIST_MAX_LEVEL,   /* Skip list max level              */
    TDB_DEFAULT_SKIP_LIST_PROBABILITY, /* Skip list probability            */
    true,                              /* Enable compression               */
    TDB_COMPRESS_SNAPPY,               /* Use Snappy compression           */
    true                               /* Enable bloom filters             */
);

if (err != NULL) {
    printf("Error creating column family: %s (code: %d)\n", err->message, err->code);
    tidesdb_err_free(err);
    return 1;
}
printf("Column family 'users' created successfully\n");
```

#### Dropping a Column Family
Deletes a column family and all its associated data.
```c
/*
 * Dropping a Column Family
 * Deletes a column family and all its associated data.
 * WARNING: This operation cannot be undone and will
 * permanently remove all data in this family.
 */
tidesdb_err_t *err = tidesdb_drop_column_family(tdb, "users");
if (err != NULL) {
    printf("Error dropping column family: %s (code: %d)\n", err->message, err->code);
    tidesdb_err_free(err);
    return 1;
}
printf("Column family 'users' dropped successfully\n");
```

#### Listing Column Families
Gets a list of all column families in the TidesDB instance.

```c
/*
* List all column families in the TidesDB instance
* The function allocates memory for the result,
* which must be freed by the caller
*/
char *column_families = NULL;
tidesdb_err_t *err = tidesdb_list_column_families(tdb, &column_families);
if (err != NULL) {
   printf("Error listing column families: %s (code: %d)\n", err->message, err->code);
   tidesdb_err_free(err);
   return 1;
}

printf("Column families: %s\n", column_families);
free(column_families); /* Don't forget to free the memory */
```

#### Getting Column Family Statistics
Retrieves detailed information about a column family.
```c
/*
* Get statistics for a column family
* This provides detailed information about the state of
* the specified column family within the TidesDB instance 
*/
tidesdb_column_family_stat_t *stat = NULL;
tidesdb_err_t *err = tidesdb_get_column_family_stat(tdb, "users", &stat);
if (err != NULL) {
   printf("Error getting column family stats: %s (code: %d)\n", err->message, err->code);
   tidesdb_err_free(err);
   return 1;
}

/* Display the column family statistics */
printf("Column family: %s\n", stat->cf_name);
printf("Number of SSTables: %d\n", stat->num_sstables);
printf("Memtable size: %zu bytes\n", stat->memtable_size);
printf("Memtable entries: %zu\n", stat->memtable_entries_count);
printf("Incremental merging: %s\n", stat->incremental_merging ? "Yes" : "No");
printf("Flush threshold: %d bytes\n", stat->config.flush_threshold);

/* Free the stats when done to prevent memory leaks */
tidesdb_free_column_family_stat(stat);
```

### Key-Value Operations
#### Putting a Key-Value Pair
Stores a key-value pair in a column family.
```c
/*
* Store a simple key-value pair with no expiration
* This associates a JSON user profile with the key "user:1001"
* in the "users" column family
*/
uint8_t key[] = "user:1001";
uint8_t value[] = "{\"name\":\"Alice\",\"email\":\"alice@example.com\"}";

tidesdb_err_t *err = tidesdb_put(
   tdb,              /* TidesDB instance            */
   "users",          /* Column family name           */
   key,              /* Key                          */
   sizeof(key),      /* Key size                     */
   value,            /* Value                        */
   sizeof(value),    /* Value size                   */
   -1                /* TTL (-1 means no expiration) */
);

if (err != NULL) {
   printf("Error putting key-value pair: %s (code: %d)\n", err->message, err->code);
   tidesdb_err_free(err);
   return 1;
}
printf("Key-value pair stored successfully\n");
```

#### Putting a Key-Value Pair with TTL
Stores a key-value pair that will expire after a specified time.
```c
/*
* Store a key-value pair with expiration (TTL)
* This associates a session with user ID 1001
* The session will expire automatically after 1 hour
*/
uint8_t key[] = "session:12345";
uint8_t value[] = "{\"user_id\":\"1001\",\"authenticated\":true}";

/* Set TTL to 1 hour from now */
time_t ttl = time(NULL) + (60 * 60);

tidesdb_err_t *err = tidesdb_put(
   tdb,              /* TidesDB instance     */
   "sessions",       /* Column family name    */
   key,              /* Key                   */
   sizeof(key),      /* Key size              */
   value,            /* Value                 */
   sizeof(value),    /* Value size            */
   ttl               /* TTL (1 hour from now) */
);

if (err != NULL) {
   printf("Error putting key-value pair with TTL: %s (code: %d)\n", err->message, err->code);
   tidesdb_err_free(err);
   return 1;
}
printf("Key-value pair with TTL stored successfully\n");
```

#### Getting a Key-Value Pair
Retrieves a value by its key from a column family.
```c
/*
* Retrieve a key-value pair from the TidesDB instance
* Looks up the value associated with the key "user:1001"
* The function allocates memory for the result,
* which must be freed by the caller
*/
uint8_t key[] = "user:1001";
uint8_t *value_out = NULL;
size_t value_len = 0;

tidesdb_err_t *err = tidesdb_get(
   tdb,              /* TidesDB instance  */
   "users",          /* Column family name */
   key,              /* Key                */
   sizeof(key),      /* Key size           */
   &value_out,       /* Output value       */
   &value_len        /* Output value size  */
);

if (err != NULL) {
   printf("Error getting key-value pair: %s (code: %d)\n", err->message, err->code);
   tidesdb_err_free(err);
   return 1;
}

printf("Retrieved value: %.*s\n", (int)value_len, value_out);

/* Don't forget to free the value when done to prevent memory leaks */
free(value_out);
```

#### Deleting a Key-Value Pair
Removes a key-value pair from a column family.

```c
/*
* Delete a key-value pair from the TidesDB instance
* This completely removes the entry for "user:1001"
* from the "users" column family
*/
uint8_t key[] = "user:1001";

tidesdb_err_t *err = tidesdb_delete(
   tdb,              /* TidesDB instance  */
   "users",          /* Column family name */
   key,              /* Key                */
   sizeof(key)       /* Key size           */
);

if (err != NULL) {
   printf("Error deleting key-value pair: %s (code: %d)\n", err->message, err->code);
   tidesdb_err_free(err);
   return 1;
}
printf("Key-value pair deleted successfully\n");
```

#### Range and Filter Operations
##### Range Queries
Retrieves a range of key-value pairs between two keys.
```c
/*
* Perform a range query to retrieve all users with IDs between 1000 and 2000
* This returns all key-value pairs where the key is lexicographically
* between start_key and end_key (inclusive)
*/
uint8_t start_key[] = "user:1000";
uint8_t end_key[] = "user:2000";
tidesdb_key_value_pair_t **result = NULL;
size_t result_size = 0;

tidesdb_err_t *err = tidesdb_range(
   tdb,                /* TidesDB instance   */
   "users",            /* Column family name  */
   start_key,          /* Start key           */
   sizeof(start_key),  /* Start key size      */
   end_key,            /* End key             */
   sizeof(end_key),    /* End key size        */
   &result,            /* Output result array */
   &result_size        /* Output result size  */
);

if (err != NULL) {
   printf("Error in range query: %s (code: %d)\n", err->message, err->code);
   tidesdb_err_free(err);
   return 1;
}

printf("Found %zu key-value pairs in range\n", result_size);

/* Process results */
for (size_t i = 0; i < result_size; i++) {
   printf("Key: %.*s, Value: %.*s\n", 
       (int)result[i]->key_size, result[i]->key,
       (int)result[i]->value_size, result[i]->value);
   
   /* Free each key-value pair when done */
   _tidesdb_free_key_value_pair(result[i]);
}

/* Free the result array */
free(result);
```

##### Filter Queries
Retrieves key-value pairs that match a specific filter function.
```c
/*
* Define a filter function to find users with "admin" in their value
* This will search through all users and return only those that match
* our criteria (containing the string "admin" in their value)
*/
bool is_admin_user(const tidesdb_key_value_pair_t *kv) {
   /* Check if "admin" is in the value */
   for (uint32_t i = 0; i <= kv->value_size - 5; i++) {
       if (memcmp(kv->value + i, "admin", 5) == 0) {
           return true;
       }
   }
   return false;
}

tidesdb_key_value_pair_t **result = NULL;
size_t result_size = 0;

tidesdb_err_t *err = tidesdb_filter(
   tdb,               /* TidesDB instance */
   "users",           /* Column family name */
   is_admin_user,     /* Filter function */
   &result,           /* Output result array */
   &result_size       /* Output result size */
);

if (err != NULL) {
   printf("Error in filter query: %s (code: %d)\n", err->message, err->code);
   tidesdb_err_free(err);
   return 1;
}

printf("Found %zu admin users\n", result_size);

/* Process results */
for (size_t i = 0; i < result_size; i++) {
   printf("Admin user - Key: %.*s, Value: %.*s\n", 
       (int)result[i]->key_size, result[i]->key,
       (int)result[i]->value_size, result[i]->value);
   
   /* Free each key-value pair when done */
   _tidesdb_free_key_value_pair(result[i]);
}

/* Free the result array */
free(result);
```

### Transactions
Transactions allow you to perform multiple operations atomically.

#### Beginning a Transaction
```c
/*
* Begin a transaction on the 'users' column family
* Transactions allow multiple operations to be executed atomically
* Either all operations succeed, or none of them are applied
*/
tidesdb_txn_t *txn = NULL;
tidesdb_err_t *err = tidesdb_txn_begin(
   tdb,          /* TidesDB instance */
   &txn,         /* Transaction pointer */
   "users"       /* Column family name */
);

if (err != NULL) {
   printf("Error beginning transaction: %s (code: %d)\n", err->message, err->code);
   tidesdb_err_free(err);
   return 1;
}
printf("Transaction started successfully\n");

/*
* Adding Operations to a Transaction
* We can add multiple operations that will be executed atomically
*/

/* Put operation - add or update a user */
uint8_t key1[] = "user:1001";
uint8_t value1[] = "{\"name\":\"Alice\",\"role\":\"admin\"}";
err = tidesdb_txn_put(
   txn,              /* Transaction */
   key1,             /* Key         */
   sizeof(key1),     /* Key size    */
   value1,           /* Value       */
   sizeof(value1),   /* Value size  */
   -1                /* TTL         */
);

if (err != NULL) {
   printf("Error adding put operation to transaction: %s (code: %d)\n", err->message, err->code);
   tidesdb_err_free(err);
   tidesdb_txn_rollback(txn);
   tidesdb_txn_free(txn);
   return 1;
}

/* Delete operation - remove a user */
uint8_t key2[] = "user:1002";
err = tidesdb_txn_delete(
   txn,             /* Transaction */
   key2,            /* Key         */
   sizeof(key2)     /* Key size    */
);

if (err != NULL) {
   printf("Error adding delete operation to transaction: %s (code: %d)\n", err->message, err->code);
   tidesdb_err_free(err);
   tidesdb_txn_rollback(txn);
   tidesdb_txn_free(txn);
   return 1;
}
```

#### Getting a Value in a Transaction
```c
/*
* Read a value within the transaction context
* This allows you to see the effects of previous operations
* in the transaction before it is committed
*/
uint8_t key[] = "user:1001";
uint8_t *value_out = NULL;
size_t value_len = 0;

err = tidesdb_txn_get(
   txn,             /* Transaction       */
   key,             /* Key               */
   sizeof(key),     /* Key size          */
   &value_out,      /* Output value      */
   &value_len       /* Output value size */
);

if (err != NULL) {
   printf("Error getting value in transaction: %s (code: %d)\n", err->message, err->code);
   tidesdb_err_free(err);
} else {
   printf("Value in transaction: %.*s\n", (int)value_len, value_out);
   free(value_out); /* Free the allocated memory */
}
```

#### Committing a Transaction
```c
err = tidesdb_txn_commit(txn);
if (err != NULL) {
    printf("Error committing transaction: %s (code: %d)\n", err->message, err->code);
    tidesdb_err_free(err);
    tidesdb_txn_rollback(txn);
    tidesdb_txn_free(txn);
    return 1;
}
printf("Transaction committed successfully\n");
```

#### Rolling Back a Transaction
```c
err = tidesdb_txn_rollback(txn);
if (err != NULL) {
    printf("Error rolling back transaction: %s (code: %d)\n", err->message, err->code);
    tidesdb_err_free(err);
    tidesdb_txn_free(txn);
    return 1;
}
printf("Transaction rolled back successfully\n");
```

#### Freeing a Transaction
```c
tidesdb_txn_free(txn);
```

### Cursor Operations
Cursors allow you to iterate through key-value pairs in a column family.

#### Initializing a Cursor
```c
/*
* Initialize a cursor to iterate through key-value pairs
* A cursor allows bi-directional sequential access to the TidesDB isntance contents
*/
tidesdb_cursor_t *cursor = NULL;
tidesdb_err_t *err = tidesdb_cursor_init(
   tdb,          /* TidesDB instance  */
   "users",      /* Column family name */
   &cursor       /* Cursor pointer     */
);

if (err != NULL) {
   printf("Error initializing cursor: %s (code: %d)\n", err->message, err->code);
   tidesdb_err_free(err);
   return 1;
}
printf("Cursor initialized successfully\n");
```

#### Iterating Forward
```c
uint8_t *key = NULL;
size_t key_size = 0;
uint8_t *value = NULL;
size_t value_size = 0;

/* Iterate forward through key-value pairs */
while ((err = tidesdb_cursor_next(cursor)) == NULL) {
   err = tidesdb_cursor_get(
       cursor,     /* Cursor            */
       &key,       /* Output key        */
       &key_size,  /* Output key size   */
       &value,     /* Output value      */
       &value_size /* Output value size */
   );
   
   if (err != NULL) {
       printf("Error getting cursor value: %s (code: %d)\n", err->message, err->code);
       tidesdb_err_free(err);
       break;
   }
   
   printf("Key: %.*s, Value: %.*s\n", (int)key_size, key, (int)value_size, value);
   
   /* Free the key and value when done to prevent memory leaks */
   free(key);
   free(value);
}

/* 
* Check if we reached the end of the cursor or if there was an error
* TIDESDB_ERR_AT_END_OF_CURSOR is a special error code that indicates
* we've processed all items in the TidesDB instance
*/
if (err != NULL && err->code != TIDESDB_ERR_AT_END_OF_CURSOR) {
   printf("Error iterating cursor: %s (code: %d)\n", err->message, err->code);
   tidesdb_err_free(err);
}
```

#### Iterating Backward
```c
/* Iterate backward through key-value pairs */
while ((err = tidesdb_cursor_prev(cursor)) == NULL) {
    err = tidesdb_cursor_get(
        cursor,     /* Cursor            */
        &key,       /* Output key        */
        &key_size,  /* Output key size   */
        &value,     /* Output value      */
        &value_size /* Output value size */
    );
    
    if (err != NULL) {
        printf("Error getting cursor value: %s (code: %d)\n", err->message, err->code);
        tidesdb_err_free(err);
        break;
    }
    
    printf("Key: %.*s, Value: %.*s\n", (int)key_size, key, (int)value_size, value);
    
    /* Free the key and value when done */
    free(key);
    free(value);
}

/* Check if we reached the start of the cursor or if there was an error */
if (err != NULL && err->code != TIDESDB_ERR_AT_START_OF_CURSOR) {
    printf("Error iterating cursor: %s (code: %d)\n", err->message, err->code);
    tidesdb_err_free(err);
}
```

#### Freeing a Cursor
```c
tidesdb_cursor_free(cursor);
```

### Compaction Operations
#### Manual Compaction
Compacts SSTables to improve read performance and reduce storage space.
```c
tidesdb_err_t *err = tidesdb_compact_sstables(
    tdb,         /* TidesDB instance                       */
    "users",     /* Column family name                      */
    4            /* Number of threads to use for compaction */
);

if (err != NULL) {
    printf("Error compacting SSTables: %s (code: %d)\n", err->message, err->code);
    tidesdb_err_free(err);
    return 1;
}
printf("SSTables compacted successfully\n");
```

#### Automatic Incremental Compaction
Starts a background thread that incrementally merges SSTables.
```c
tidesdb_err_t *err = tidesdb_start_incremental_merge(
    tdb,         /* TidesDB instance                             */
    "users",     /* Column family name                            */
    30,          /* Merge interval in seconds                     */
    10           /* Minimum number of SSTables to trigger a merge */
);

if (err != NULL) {
    printf("Error starting incremental merge: %s (code: %d)\n", err->message, err->code);
    tidesdb_err_free(err);
    return 1;
}
printf("Incremental merge started successfully\n");
```

### Range Deletion Operations
Deletes all key-value pairs within a specified range.
```c
uint8_t start_key[] = "session:1000";
uint8_t end_key[] = "session:2000";

tidesdb_err_t *err = tidesdb_delete_by_range(
    tdb,                /* TidesDB instance   */
    "sessions",         /* Column family name  */
    start_key,          /* Start key           */
    sizeof(start_key),  /* Start key size      */
    end_key,            /* End key             */
    sizeof(end_key)     /* End key size        */
);

if (err != NULL) {
    printf("Error deleting by range: %s (code: %d)\n", err->message, err->code);
    tidesdb_err_free(err);
    return 1;
}
printf("Range deleted successfully\n");
```

### Deleting by Filter
Deletes all key-value pairs that match a specific filter function.
```c
/* Define a filter function to find expired sessions */
bool is_expired_session(const tidesdb_key_value_pair_t *kv) {
    /* Check if "expired" is in the value */
    for (uint32_t i = 0; i <= kv->value_size - 7; i++) {
        if (memcmp(kv->value + i, "expired", 7) == 0) {
            return true;
        }
    }
    return false;
}

tidesdb_err_t *err = tidesdb_delete_by_filter(
    tdb,                /* TidesDB instance  */
    "sessions",         /* Column family name */
    is_expired_session  /* Filter function    */
);

if (err != NULL) {
    printf("Error deleting by filter: %s (code: %d)\n", err->message, err->code);
    tidesdb_err_free(err);
    return 1;
}
printf("Filtered items deleted successfully\n");
```


### Complete Example
```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <tidesdb/tidesdb.h>

int main() {
    tidesdb_t *tdb = NULL;
    tidesdb_err_t *err = NULL;
    
    /* Open a new TidesDB instance */
    err = tidesdb_open("./my_tidesdb", &tdb);
    if (err != NULL) {
        printf("Error opening TidesDB: %s (code: %d)\n", err->message, err->code);
        tidesdb_err_free(err);
        return 1;
    }
    printf("TidesDB opened successfully\n");
    
    /* Create a column family */
    err = tidesdb_create_column_family(
        tdb,
        "users",
        (1024 * 1024) * 64,  /* 64MB flush threshold */
        TDB_DEFAULT_SKIP_LIST_MAX_LEVEL,
        TDB_DEFAULT_SKIP_LIST_PROBABILITY,
        true,
        TDB_COMPRESS_SNAPPY,
        true
    );
    
    if (err != NULL) {
        printf("Error creating column family: %s (code: %d)\n", err->message, err->code);
        tidesdb_err_free(err);
        tidesdb_close(tdb);
        return 1;
    }
    printf("Column family 'users' created successfully\n");
    
    /* Put some key-value pairs */
    uint8_t key1[] = "user:1001";
    uint8_t value1[] = "{\"name\":\"Alice\",\"email\":\"alice@example.com\"}";
    
    err = tidesdb_put(tdb, "users", key1, sizeof(key1), value1, sizeof(value1), -1);
    if (err != NULL) {
        printf("Error putting key-value pair: %s (code: %d)\n", err->message, err->code);
        tidesdb_err_free(err);
        tidesdb_close(tdb);
        return 1;
    }
    
    uint8_t key2[] = "user:1002";
    uint8_t value2[] = "{\"name\":\"Bob\",\"email\":\"bob@example.com\"}";
    
    err = tidesdb_put(tdb, "users", key2, sizeof(key2), value2, sizeof(value2), -1);
    if (err != NULL) {
        printf("Error putting key-value pair: %s (code: %d)\n", err->message, err->code);
        tidesdb_err_free(err);
        tidesdb_close(tdb);
        return 1;
    }
    printf("Key-value pairs stored successfully\n");
    
    /* Get a value */
    uint8_t *value_out = NULL;
    size_t value_len = 0;
    
    err = tidesdb_get(tdb, "users", key1, sizeof(key1), &value_out, &value_len);
    if (err != NULL) {
        printf("Error getting key-value pair: %s (code: %d)\n", err->message, err->code);
        tidesdb_err_free(err);
        tidesdb_close(tdb);
        return 1;
    }
    
    printf("Retrieved value for user:1001: %.*s\n", (int)value_len, value_out);
    free(value_out);
    
    /* Use a transaction */
    tidesdb_txn_t *txn = NULL;
    err = tidesdb_txn_begin(tdb, &txn, "users");
    if (err != NULL) {
        printf("Error beginning transaction: %s (code: %d)\n", err->message, err->code);
        tidesdb_err_free(err);
        tidesdb_close(tdb);
        return 1;
    }
    
    uint8_t key3[] = "user:1003";
    uint8_t value3[] = "{\"name\":\"Charlie\",\"email\":\"charlie@example.com\"}";
    
    err = tidesdb_txn_put(txn, key3, sizeof(key3), value3, sizeof(value3), -1);
    if (err != NULL) {
        printf("Error adding put operation to transaction: %s (code: %d)\n", err->message, err->code);
        tidesdb_err_free(err);
        tidesdb_txn_rollback(txn);
        tidesdb_txn_free(txn);
        tidesdb_close(tdb);
        return 1;
    }
    
    err = tidesdb_txn_commit(txn);
    if (err != NULL) {
        printf("Error committing transaction: %s (code: %d)\n", err->message, err->code);
        tidesdb_err_free(err);
        tidesdb_txn_rollback(txn);
        tidesdb_txn_free(txn);
        tidesdb_close(tdb);
        return 1;
    }
    printf("Transaction committed successfully\n");
    tidesdb_txn_free(txn);
    
    /* Use a cursor to iterate through all key-value pairs */
    tidesdb_cursor_t *cursor = NULL;
    err = tidesdb_cursor_init(tdb, "users", &cursor);
    if (err != NULL) {
        printf("Error initializing cursor: %s (code: %d)\n", err->message, err->code);
        tidesdb_err_free(err);
        tidesdb_close(tdb);
        return 1;
    }
    
    printf("\nAll users:\n");
    uint8_t *key = NULL;
    size_t key_size = 0;
    value_out = NULL;
    value_len = 0;
    
    while ((err = tidesdb_cursor_next(cursor)) == NULL) {
        err = tidesdb_cursor_get(cursor, &key, &key_size, &value_out, &value_len);
        if (err != NULL) {
            printf("Error getting cursor value: %s (code: %d)\n", err->message, err->code);
            tidesdb_err_free(err);
            break;
        }
        
        printf("Key: %.*s, Value: %.*s\n", (int)key_size, key, (int)value_len, value_out);
        
        free(key);
        free(value_out);
    }
    
    if (err != NULL && err->code != TIDESDB_ERR_AT_END_OF_CURSOR) {
        printf("Error iterating cursor: %s (code: %d)\n", err->message, err->code);
        tidesdb_err_free(err);
    }
    
    tidesdb_cursor_free(cursor);
    
    /* Close TidesDB */
    err = tidesdb_close(tdb);
    if (err != NULL) {
        printf("Error closing TidesDB: %s (code: %d)\n", err->message, err->code);
        tidesdb_err_free(err);
        return 1;
    }
    printf("TidesDB closed successfully\n");
    
    return 0;
}
```

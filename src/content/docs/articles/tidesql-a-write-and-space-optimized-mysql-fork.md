---
title: "TideSQL - A Write and Space Optimized MySQL Fork"
description: "TideSQL is a MySQL fork using TidesDB as its default storage engine, providing LSM-tree based storage with excellent write performance and space efficiency."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-neil-harvey-85161620-8962363.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-neil-harvey-85161620-8962363.jpg
---

<div class="article-image">

![TideSQL - A Write-Space Optimized MySQL Fork](/pexels-neil-harvey-85161620-8962363.jpg)

</div>

*by Alex Gaetano Padula*

*published on January 24th, 2026*

It's been a while since I've written a new article, but I'm back with something new. I wanted to use TidesDB as a storage engine in a relational database. It took a while to decide which database, and then which version of that database. I eventually settled on MySQL 5.1, specifically <a href="https://github.com/facebookarchive/mysql-5.1">Facebook's fork</a>. This fork is admittedly old, but it had most features needed for a relational database and decent documentation. More importantly, I found examples of storage engines within the code, which made getting started considerably easier.

The result is TideSQL, a write-space optimized relational database that uses TidesDB as its default storage engine. The code is available on <a href="https://github.com/tidesdb/tidesql">GitHub</a>.

## The Case for LSM-Trees

Traditional MySQL storage engines like InnoDB use B-tree structures. B-trees provide excellent read performance because any record can be located in O(log n) disk seeks. However, this comes at a cost: every write must update the tree in place, which means random I/O. On spinning disks, random writes are orders of magnitude slower than sequential writes. Even on SSDs, random writes cause write amplification and reduce device lifespan.

TidesDB uses a different approach called a Log-Structured Merge-tree, or LSM-tree. The idea is rather simple, instead of updating records in place, we append all writes to an in-memory buffer called a memtable. When the memtable fills up, we flush it to disk as a sorted file called an SSTable. Reads must check the memtable and all SSTables, but we use bloom filters to skip SSTables that definitely don't contain a key. Periodically, background compaction merges SSTables together, discarding old versions and reclaiming space.

This design has several advantages. Writes are always sequential, which is fast on any storage medium. Data compresses well because SSTables are sorted. And the system naturally handles write-heavy workloads because writes never block on disk I/O.

## What TideSQL Provides

TideSQL supports ACID transactions with four isolation levels: READ UNCOMMITTED, READ COMMITTED, REPEATABLE READ, and SERIALIZABLE. The implementation uses multi-version concurrency control, so readers don't block writers and vice versa. You can use savepoints to partially roll back a transaction, which is useful for complex operations where you want to undo some changes but keep others.

The engine supports secondary indexes, which are stored in separate column families. When you create an index on a column, TideSQL maintains a mapping from that column's values to primary keys. The query optimizer uses these indexes when appropriate, as you can verify with EXPLAIN.

Fulltext search is implemented using an inverted index. When you create a FULLTEXT index on a column, TideSQL tokenizes the text and stores a mapping from each word to the primary keys of rows containing that word. You can search using the standard MATCH...AGAINST syntax.

One feature that's particularly useful for caching and session management is time-to-live support. If you add a column named TTL to your table, TideSQL will automatically expire rows when their TTL value (in seconds) elapses. Rows with a TTL of 0 never expire.

The engine supports LZ4, Zstd, and Snappy compression. Bloom filters are enabled by default with a 1% false positive rate, which dramatically reduces disk reads for point lookups. You can perform hot backups using the BACKUP TABLE command without blocking writes.

## A Tour of the System

Let's look at how TideSQL works in practice. When you start the server and check the available engines, you'll see that TidesDB is the default:

```sql
mysql> SHOW ENGINES;
+------------+---------+-----------------------------------------------+--------------+------+------------+
| Engine     | Support | Comment                                       | Transactions | XA   | Savepoints |
+------------+---------+-----------------------------------------------+--------------+------+------------+
| TidesDB    | DEFAULT | TidesDB LSM-based storage engine with ACID... | YES          | NO   | YES        |
| MRG_MYISAM | YES     | Collection of identical MyISAM tables         | NO           | NO   | NO         |
| MEMORY     | YES     | Hash based, stored in memory...               | NO           | NO   | NO         |
| MyISAM     | YES     | Default engine as of MySQL 3.23...            | NO           | NO   | NO         |
| CSV        | YES     | CSV storage engine                            | NO           | NO   | NO         |
+------------+---------+-----------------------------------------------+--------------+------+------------+
```

Creating tables and inserting data works exactly as you'd expect. The ENGINE=TidesDB clause is optional since TidesDB is the default:

```sql
CREATE TABLE users (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(100),
  email VARCHAR(200)
) ENGINE=TidesDB;

INSERT INTO users (name, email) VALUES 
  ('Alice Johnson', 'alice@example.com'),
  ('Bob Smith', 'bob@example.com'),
  ('Charlie Brown', 'charlie@example.com');

SELECT * FROM users;
+----+-----------------+---------------------+
| id | name            | email               |
+----+-----------------+---------------------+
|  1 | Alice Johnson   | alice@example.com   |
|  2 | Bob Smith       | bob@example.com     |
|  3 | Charlie Brown   | charlie@example.com |
+----+-----------------+---------------------+
```

Transactions work as you'd expect from any ACID-compliant database. What's more interesting is savepoint support, which lets you partially roll back a transaction. Consider a banking scenario where you want to withdraw from one account and deposit to another, but something goes wrong with the deposit:

```sql
CREATE TABLE accounts (
  id INT PRIMARY KEY,
  name VARCHAR(50),
  balance DECIMAL(10,2)
) ENGINE=TidesDB;

INSERT INTO accounts VALUES (1, 'Checking', 1000.00), (2, 'Savings', 5000.00);

BEGIN;
UPDATE accounts SET balance = balance - 200 WHERE id = 1;
SAVEPOINT after_withdrawal;
UPDATE accounts SET balance = balance + 200 WHERE id = 2;
ROLLBACK TO after_withdrawal;
COMMIT;

SELECT * FROM accounts;
+----+----------+---------+
| id | name     | balance |
+----+----------+---------+
|  1 | Checking |  800.00 |
|  2 | Savings  | 5000.00 |
+----+----------+---------+
```

The withdrawal went through, but the deposit was rolled back. The savepoint gave us a checkpoint to return to without abandoning the entire transaction.

Fulltext search uses an inverted index under the hood. When you insert a row, TideSQL tokenizes the text, normalizes each word to lowercase, and stores a mapping from each word to the row's primary key. Searching is then a matter of looking up words and intersecting the results:

```sql
CREATE TABLE articles (
  id INT PRIMARY KEY AUTO_INCREMENT,
  title VARCHAR(200),
  body TEXT,
  FULLTEXT INDEX ft_body (body)
) ENGINE=TidesDB;

INSERT INTO articles (title, body) VALUES 
  ('Getting Started with TidesDB', 'TidesDB is a high-performance LSM-tree storage engine'),
  ('MySQL Storage Engines', 'MySQL supports multiple storage engines including TidesDB'),
  ('Database Performance', 'Optimizing database performance requires understanding workloads'),
  ('LSM-Tree Architecture', 'Log-structured merge trees provide excellent write performance');

SELECT id, title FROM articles WHERE MATCH(body) AGAINST('performance');
+----+------------------------+
| id | title                  |
+----+------------------------+
|  1 | Getting Started...     |
|  3 | Database Performance   |
|  4 | LSM-Tree Architecture  |
+----+------------------------+
```

The TTL feature is useful for data that should automatically expire. Session tokens are a classic example. Add a column named TTL to your table, and TideSQL will delete rows when their TTL (in seconds) elapses:

```sql
CREATE TABLE sessions (
  id INT PRIMARY KEY,
  user_id INT,
  token VARCHAR(100),
  TTL INT DEFAULT 0
) ENGINE=TidesDB;

INSERT INTO sessions VALUES 
  (1, 100, 'abc123token', 3600),   -- Expires in 1 hour
  (2, 101, 'def456token', 7200),   -- Expires in 2 hours
  (3, 102, 'ghi789token', 0);      -- Never expires

SELECT id, user_id, TTL as expires_in_seconds FROM sessions;
+----+---------+--------------------+
| id | user_id | expires_in_seconds |
+----+---------+--------------------+
|  1 |     100 |               3600 |
|  2 |     101 |               7200 |
|  3 |     102 |                  0 |
+----+---------+--------------------+
```

Secondary indexes work as they do in other MySQL engines. The optimizer will use them when appropriate, which you can verify with EXPLAIN:

```sql
CREATE TABLE products (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(100),
  category VARCHAR(50),
  price DECIMAL(10,2),
  INDEX idx_category (category)
) ENGINE=TidesDB;

INSERT INTO products (name, category, price) VALUES 
  ('Laptop', 'Electronics', 999.99),
  ('Phone', 'Electronics', 699.99),
  ('Desk', 'Furniture', 299.99);

EXPLAIN SELECT * FROM products WHERE category = 'Electronics';
+----+-------------+----------+------+---------------+--------------+---------+-------+------+-------------+
| id | select_type | table    | type | possible_keys | key          | key_len | ref   | rows | Extra       |
+----+-------------+----------+------+---------------+--------------+---------+-------+------+-------------+
|  1 | SIMPLE      | products | ref  | idx_category  | idx_category | 53      | const |    1 | Using where |
+----+-------------+----------+------+---------------+--------------+---------+-------+------+-------------+
```

The type column shows "ref" rather than "ALL", indicating an index lookup rather than a full table scan.

You can inspect the engine's internal state with SHOW ENGINE TIDESDB STATUS. This displays cache statistics, configuration, and storage information:

```sql
mysql> SHOW ENGINE TIDESDB STATUS\G
*************************** 1. row ***************************
  Type: TidesDB
  Name: 
Status: 
=====================================
TIDESDB ENGINE STATUS
=====================================

-----------
BLOCK CACHE
-----------
Enabled:           YES
Total entries:     0
Total size:        0.00 MB
Cache hits:        0
Cache misses:      0
Hit rate:          0.00%
Partitions:        32

-------------
CONFIGURATION
-------------
Flush threads:     2
Compaction threads:2
Block cache size:  64.00 MB
Write buffer size: 64.00 MB
Compression:       ON (lz4)
Bloom filter:      ON (FPR: 1.00%)
Sync mode:         interval
Default isolation: read_committed
Default TTL:       0 seconds

-------
STORAGE
-------
Open tables:       5

----------------------------
END OF TIDESDB ENGINE STATUS
----------------------------
```

## Tuning

TideSQL exposes several configuration variables. The most important ones control memory usage: `tidesdb_block_cache_size` sets the size of the read cache (default 64 MB), and `tidesdb_write_buffer_size` controls how much data accumulates in memory before flushing to disk (also 64 MB by default). Larger values improve performance but consume more memory.

Background work is handled by dedicated threads. The `tidesdb_flush_threads` variable controls how many threads flush memtables to disk, while `tidesdb_compaction_threads` controls how many threads merge SSTables. The defaults of 2 each are reasonable for most workloads.

Compression is enabled by default using LZ4, which provides a good balance between compression ratio and CPU overhead. You can disable it with `tidesdb_enable_compression=OFF` if CPU is more constrained than disk space. Bloom filters are also enabled by default with a 1% false positive rate, controlled by `tidesdb_bloom_fpr`.

The `tidesdb_sync_mode` variable controls durability. The default value of INTERVAL syncs data periodically, which provides good performance with reasonable durability. Setting it to FULL syncs after every write for maximum durability at the cost of performance. Setting it to NONE disables syncing entirely, which is only appropriate for ephemeral data.

## Implementation Notes

The storage engine integrates with MySQL through the handler API. Each table is stored in a TidesDB column family, with secondary indexes stored in separate column families. The primary key is used as the key in the LSM-tree, and the entire row is serialized as the value.

Transactions are implemented using TidesDB's native transaction support. When you BEGIN a transaction, we create a TidesDB transaction object and associate it with the MySQL thread. All subsequent operations on that thread use the same transaction until you COMMIT or ROLLBACK. Savepoints are implemented using TidesDB's savepoint API.

The fulltext index uses a simple inverted index structure. Each word maps to a list of primary keys. For multi-word searches, we look up each word and either union the results (natural language mode) or intersect them (boolean mode). The intersection algorithm uses a hash set for O(n+m) complexity rather than the naive O(n*m) approach.

## Current Status

The code is in beta. It passes comprehensive tests covering basic CRUD operations, transactions, savepoints, secondary indexes, fulltext search, TTL expiration, TRUNCATE, bulk operations, JOINs, and aggregates. I plan to continue cleaning up the code and adding features over time.

*Thanks for reading.*

---

The code is available at https://github.com/tidesdb/tidesql. For more information about TidesDB itself, see https://github.com/tidesdb/tidesdb and the design documentation at https://tidesdb.com/getting-started/how-does-tidesdb-work.

Join the TidesDB Discord at https://discord.gg/tWEmjR66cy for updates and discussion.

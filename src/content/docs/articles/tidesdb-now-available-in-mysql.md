---
title: "TidesDB now available for MySQL 9.x, 26.x"
description: "TidesDB becomes available under project TideSQL for MySQL."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-charmain-33529218.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-charmain-33529218.jpg
---

<div class="article-image">

![TidesDB now available for MySQL 9.x, 26.x](/pexels-charmain-33529218.jpg)
<a target="_blank" href="https://www.instagram.com/jvrs_photography">Charmain Jansen van Rensburg</a>
</div>

*by <a target="_blank" href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on October 5th, 2026*


Maybe most don't know, but originally TideSQL started as a <a target="_blank"  href="https://github.com/tidesdb/tidesql/tree/3ef20028f1a184112019b9767e7cd70e88667368">MySQL fork</a> in which I started to implement the TidesDB library as a plugin, making its powerful storage engine available to MySQL users, but at the time the MySQL community had no way for us to make this possible.  Almost a year has passed and lots has changed. A <a target="_blank"  href="https://github.com/mysql/mysql-community/issues/82">proposal</a> was created for TidesDB to become available for MySQL and well, this has happened, TidesDB is <a target="_blank" href="https://github.com/tidesdb/tidesql-mysql">now available</a> as an external plugin storage engine for MySQL v9.x.x, v26.x.x with a wonderful set of features and more to come.

Currently the way to access the TidesDB plugin engine is through the `install.sh` script in the repository which you either point to your build or let the installer build the bundle for you.   Going down the line we'd like this to be easier for you the users and are in discussions with appropriate parties in regards to that.

TidesDB is a write and space optimized storage engine which can keep up very well on reads.

It's a plugin, not a fork.  You run a stock MySQL and load the engine into it, and a TidesDB table can sit next to an InnoDB one in the same server.  TideSQL v2.0.0 is paired with TidesDB v10.1.1 and tested against MySQL 9.7.0 and 26.7.0.

```sql
INSTALL PLUGIN TidesDB SONAME 'ha_tidesdb.so';
CREATE TABLE events (id BIGINT PRIMARY KEY, body TEXT) ENGINE=TIDESDB;
```

MySQL has no engine-specific `CREATE TABLE` grammar, so a table names its TidesDB options in `ENGINE_ATTRIBUTE`, a JSON object the server stores and hands to the engine without reading it.  The engine defines those names so the engine checks them, and a misspelled option fails the statement instead of being stored and ignored.  Every option has a `tidesdb_default_*` session variable behind it, so you can set the policy once and let every `CREATE TABLE` inherit it.  What a table does not name is resolved when it is created and stays with it.

```sql
CREATE TABLE archive (id INT PRIMARY KEY, data TEXT) ENGINE=TIDESDB
  ENGINE_ATTRIBUTE='{"compression": "ZSTD", "bloom_fpr": 50}';
```

Compression is on by default.  The choices are `NONE`, `SNAPPY`, `LZ4`, `ZSTD` and `LZ4_FAST`, the default is `LZ4`, and `ZSTD` is there when you want the ratio more than the speed.

Large values stay out of compaction.  Each SSTable has its own key log and the whole database shares one segmented value log.  A value at or above `tidesdb_value_separation_threshold` goes to the value log with a pointer left in the key log, so every later merge rewrites the pointer and not the value.  That costs one value-log read per row on a scan, so a table you scan far more than you merge can set `{"keep_values_inline": true}` and keep every value in the key log whatever its size.

The shape of the LSM is yours to set.  `level_size_ratio` is how much larger each level is than the last, `min_levels` is the minimum depth, and `l1_file_count_trigger` is how many SSTables may gather at level 1 before compaction merges them down.  There is no compaction policy to choose, the engine picks among full preemptive merge, dividing merge and partitioned merge from the state of the tree.  For a table that deletes heavily, `tombstone_density_trigger` escalates compaction for a level-1 SSTable whose tombstones outgrow a ratio you set.

```sql
CREATE TABLE tuned (id INT PRIMARY KEY, v VARCHAR(200)) ENGINE=TIDESDB
  ENGINE_ATTRIBUTE='{"level_size_ratio": 8, "min_levels": 3,
                     "l1_file_count_trigger": 4}';
```

Durability is one setting, `tidesdb_memtable_sync_mode`, and it governs every commit because every table shares the library's write-ahead log.  `FULL` is the default and means a committed write has reached the device and survives power loss.  `INTERVAL` hands each commit to the operating system and reaches the device within the interval, so a process crash loses nothing and a machine crash loses at most that window.  `NONE` does nothing at commit time, so an acknowledged commit sits in a buffer until a later batch writes it out and a process crash loses it.  `NONE` is for data you can rebuild.

Rows can expire on their own, at the table level, the row level or the session level, and they resolve in that order.  Encryption at rest is per row with a two-tier key arrangement, so rotating the master key touches no row data.  An encrypted table's rows are ciphertext by the time the library sees them, so compression is forced off for that column family, while its secondary indexes hold unencrypted comparable keys and keep whatever algorithm you picked.

The rest of what works today:

- `FULLTEXT` indexes with natural-language and boolean modes, BM25 ranking, stop words and blend characters
- foreign keys enforced inside the engine, `ON DELETE` and `ON UPDATE` with `CASCADE`, `SET NULL` and `RESTRICT`, and self-references
- spatial indexes, generated columns and JSON
- vector columns store and read back, there is no similarity search over them
- instant `ADD COLUMN` and `DROP COLUMN`, the packed row carries a self-describing header so the deserializer adapts to rows written under an earlier schema
- statistics the optimizer can use without running `ANALYZE TABLE`, sampled the first time a populated table is asked for them
- online backup and checkpoints, and `SHOW ENGINE TIDESDB STATUS` for what the tree is doing

Concurrency is optimistic MVCC.  There are no pessimistic row locks, so there are no lock waits and no lock-wait deadlocks to tune.  A write conflict shows up at commit rather than inside the statement, as `ER_ERROR_DURING_COMMIT` (1180), and an application using explicit `BEGIN ... COMMIT` at `REPEATABLE READ` or higher should retry on it.  Autocommit statements run at `READ COMMITTED` where the library does no write-write checking, and a transaction that wrote nothing never conflicts.

I ran <a target="_blank" href="https://github.com/akopytov/sysbench">sysbench</a> 1.0.20 against both engines on the same server, 8 tables of 5 million rows, each engine on its own defaults.  The only two changes from stock are `READ COMMITTED` and the durability mode, matched across the two so neither gets a free pass on writes.  Transactions per second at 24 threads, which is where this box peaked.

The box:
- Intel i9-13900, 24 threads online, 8 P-core (5.3-5.6 GHz) + 16 E-core (4.2 GHz)
- the 8 P-cores isolated for the run
- Ubuntu 24.04.4 LTS (6.8.0-136-generic)
- 125.5 GiB DDR5, no ECC
- NVMe Micron 7450, xfs, separate from the OS disk
- gcc 13.3.0
- jemalloc for library and server


| workload | TidesDB | InnoDB | |
|---|---:|---:|---|
| point select | 246,410 | 95,760 | 2.6x |
| read write | 5,993 | 2,989 | 2.0x |
| update index | 102,273 | 18,962 | 5.4x |
| write only | 31,839 | 6,878 | 4.6x |
| delete | 154,048 | 25,792 | 6.0x |

![point select, transactions per second](/tidesql-mysql-v2-0-0/point_select_tps.png)

![read write, transactions per second](/tidesql-mysql-v2-0-0/read_write_tps.png)

![update index, transactions per second](/tidesql-mysql-v2-0-0/update_index_tps.png)

![write only, transactions per second](/tidesql-mysql-v2-0-0/write_only_tps.png)

![delete, transactions per second](/tidesql-mysql-v2-0-0/delete_tps.png)

The bytes tell you why.  These come from `/proc/diskstats` rather than from either engine's own accounting, so both are measured the same way below the engine, and each run is followed by a settle so writes an engine defers are still charged to the run that caused them.

| workload | TidesDB | InnoDB | |
|---|---:|---:|---|
| update index | 3,000 B | 56,461 B | 19x less |
| write only | 9,290 B | 155,398 B | 17x less |
| read write | 11,196 B | 192,741 B | 17x less |
| delete | 916 B | 42,910 B | 47x less |

Bytes written to the device per operation.

![bytes written to the device per operation](/tidesql-mysql-v2-0-0/write_bytes_per_op.png)

The dataset is about 8 GB against the 256 MB block cache and 256 MB memtable TidesDB ships with, and InnoDB's 128 MB buffer pool, so neither engine is holding it in memory.  An InnoDB update of a random row has to find a 16 KB page that is usually not resident, read it, change it and write all 16 KB back through the doublewrite buffer with redo on top.  TidesDB appends a few hundred bytes and sorts it out later.

Nothing in the standard sysbench set touches the value log.  An `sbtest` row is about 188 bytes and a value goes to the log above 1024, so every workload above stays in the key logs.  Large values are the case the design is for, so I ran a separate script against 4 tables of 200,000 rows with a 4 KB text column, built out of a small vocabulary of field names and words so it compresses the way a log line or a JSON document does rather than the way random digits do.  Three configurations, the third being TidesDB with `keep_values_inline` set, which holds every value in the key log whatever its size.  That one is a control.  Without it a gap between TidesDB and InnoDB could be anything about the engine; with it the value log is the only thing that changed.

| 4 KB values | TidesDB | TidesDB inline | InnoDB |
|---|---:|---:|---:|
| insert | 100,613 | 32,330 | 32,562 |
| select | 255,606 | 74,996 | 98,979 |

![4 KB values, peak transactions per second](/tidesql-mysql-v2-0-0/bigvalue_tps.png)

Inline and InnoDB land on the same insert number, and value separation is three times both.  So the gain on large writes is not that this is an LSM, it is that compaction rewrites the keys and leaves the values where they are.  The reads say it from the other side.  A 4 KB value held in the key log means few rows to a page, and while inline has the fastest median read of the three at 0.07 ms, its average is 0.38 ms and its worst case is over 40 ms, because compaction is hauling those values around underneath the reads.  The default averages 0.09 ms with a worst case of 6 ms.

The same 3.05 GiB of payload lands as 4.24 GiB on InnoDB and 1.19 GiB on TidesDB, which is LZ4 at defaults on data that compresses like text.  Loading it took 17 seconds against 8.

![same dataset, bytes on disk after load](/tidesql-mysql-v2-0-0/bigvalue_space.png)

That's all for this article, do give TideSQL for MySQL a try!

--

Raw data and scripts: <a href="/tidesql-mysql-v2-0-0/data.zip">data.zip</a> (sha256: 95fec38d5b14dc9673f1c5b3351f0cb0f469c8c7a6c584428b064c8a1a96fa2e)
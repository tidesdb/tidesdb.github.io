---
title: "TTL (Time to live) using TideSQL in MariaDB"
description: "TTL, what is it? how to use it, in MariaDB using TidesDB's TideSQL plugin engine."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-sami-aksu-48867324-9213725.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-sami-aksu-48867324-9213725.jpg
---

<div class="article-image">

![](/pexels-sami-aksu-48867324-9213725.jpg)

</div>

*by <a target="_blank" href="https://alexpadula.com">Alex Gaetano Padula</a>*
 
*published on June 17th, 2026*

Some of you may not know but TideSQL has a built in TTL (time to live) capability.  Say I want a row to live only a short amount of time and then disappear, this is what you'd use.  You configure TTL in seconds.  You can set it automatically for every new row in a table, or per insert, and if you want to update a row that hasn't expired yet to live longer, you can do that too.

To do this in TideSQL is rather easy, first, obviously, you need the engine installed and running.

There are three places you can set a TTL, and they stack in a clear order of priority.  A per-row TTL column wins over the session variable, which wins over the table default, and if none of them apply the row just never expires.

The simplest is a table-level default, every row written to the table inherits it.  Here I give a sessions table an 8 second TTL.

```sql
CREATE TABLE sessions (
  id    INT PRIMARY KEY,
  token VARCHAR(40)
) ENGINE=TidesDB TTL=8;

INSERT INTO sessions VALUES (1,'tok-a'), (2,'tok-b'), (3,'tok-c');
SELECT * FROM sessions;
```

Right after the insert all three rows are there.

```
+----+-------+
| id | token |
+----+-------+
|  1 | tok-a |
|  2 | tok-b |
|  3 | tok-c |
+----+-------+
```

Wait eight seconds, run the same select, and they're gone.

```sql
SELECT * FROM sessions;
```
```
Empty set
```

If different rows need different lifetimes, you can point TTL at a column instead.  You mark an integer column with the `TTL` field option and its value becomes that row's lifetime in seconds, with 0 meaning never expire.

```sql
CREATE TABLE events (
  id    INT PRIMARY KEY,
  name  VARCHAR(20),
  ttl_s INT `TTL`=1
) ENGINE=TidesDB;

INSERT INTO events VALUES (1,'short',8), (2,'long',86400), (3,'forever',0);
```

All three rows are visible at first.

```
+----+---------+-------+
| id | name    | ttl_s |
+----+---------+-------+
|  1 | short   |     8 |
|  2 | long    | 86400 |
|  3 | forever |     0 |
+----+---------+-------+
```

Eight seconds later only the long-lived and the never-expiring rows remain, row 1 aged out on its own.

```
+----+---------+
| id | name    |
+----+---------+
|  2 | long    |
|  3 | forever |
+----+---------+
```

And if you don't want to bake TTL into the schema at all, there's a session variable, `tidesdb_ttl`, that applies to whatever you insert while it's set.  Handy for a one-off load, or scoped to a single statement with `SET STATEMENT tidesdb_ttl=N FOR ...`.

```sql
CREATE TABLE apicache (k VARCHAR(20) PRIMARY KEY, v VARCHAR(40)) ENGINE=TidesDB;

SET SESSION tidesdb_ttl = 8;
INSERT INTO apicache VALUES ('a','val-a'), ('b','val-b');

SET SESSION tidesdb_ttl = 0;
INSERT INTO apicache VALUES ('c','permanent');
```

Rows a and b carry the 8 second TTL, c was inserted after I set it back to 0 so it stays.  After the wait only c is left.

```
+---+-----------+
| k | v         |
+---+-----------+
| c | permanent |
+---+-----------+
```

So what's actually happening underneath.  TTL is set through the transaction and lives with the key-value pair within a TidesDB column family, every row in TideSQL is just a key-value pair in the engine, and the expiry rides along with it as an absolute timestamp.

A key-value pair is checked against its TTL in real time, the skip list treats it as expired the moment its time passes, so it reads as gone exactly like a tombstone would, without anything having to delete it.  That's why the rows vanished from the selects above the instant their time was up, nothing ran a DELETE, no event scheduler fired, the engine just stops handing them back.

The bytes themselves are dropped later, when compaction merges the sorted runs.  When a sorted run occurs, taking an l0 file and writing it out as an sstable, that sstable holds the latest version of the key which is now expired, and as compactions occur the system garbage collects it.  The thing to know here is that a single sstable on its own won't shrink, the expired data is only physically removed when two or more sstables get merged together and the expired entries are dropped from the merged output.

You can watch that happen.  Here I load 400,000 rows with a 20 second TTL, with a small write buffer so the load spills into several sstables instead of one.

```sql
CREATE TABLE gc_demo (id INT PRIMARY KEY, payload CHAR(220)) ENGINE=TidesDB TTL=20;
INSERT INTO gc_demo SELECT seq, REPEAT('y',220) FROM seq_1_to_400000;
```

Right after the load the rows are all there, sitting across eight sstables and about 149M on disk.

```
rows visible : 400000
sstables     : 8
on disk      : 149M
```

Once the 20 seconds pass, every row is gone from queries instantly, but the disk hasn't moved, the eight sstables and 149M are still sitting there.  This is the real-time read filter at work, the bytes just haven't been collected yet.

```
rows visible : 0
sstables     : 8
on disk      : 149M
```

Now I force the sstables to merge.  Compaction does this on its own over time, `OPTIMIZE TABLE` just makes it happen right now.  The merge drops every expired entry and the space comes back.

```sql
OPTIMIZE TABLE gc_demo;
```
```
rows visible : 0
sstables     : 3
on disk      : 84K
```

149M down to 84K, the expired rows are physically gone.

And that's TTL in TideSQL.  Set it on the table, on a column, or per session, and the engine handles expiry for you.  Rows drop out of your queries the moment their time is up, and the disk space is reclaimed in the background as compaction runs.  It's a clean fit for sessions, caches, rate limits, anything with a natural shelf life, no cleanup jobs to write and nothing to schedule.

Thanks for reading!
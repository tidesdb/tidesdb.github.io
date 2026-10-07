---
title: "Using TidesDB as a Cache"
description: "Use TidesDB or TideSQL in MySQL and MariaDB as a fast TTL cache you can index, join and query with SQL."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-lachlan-ross-5967958.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-lachlan-ross-5967958.jpg
---

<div class="article-image">

![Using TidesDB as a Cache](/pexels-lachlan-ross-5967958.jpg)

<a target="_blank" href="https://www.instagram.com/lachyross">Lachlan Ross</a>

</div>

*by <a target="_blank" href="https://alexpadula.com">Alex Gaetano Padula</a>*
 
*published on October 7th, 2026*

Sometimes you just need memory, and fast memory, sometimes even transactional!  In this article I'll be guiding you through how you can use TidesDB and its integrations where you can access the library like TideSQL for <a target="_blank" href="https://github.com/tidesdb/tidesql">MariaDB</a> and <a target="_blank"  href="https://github.com/tidesdb/tidesql-mysql">MySQL</a> as a fast cache where persistence becomes a second thought.

A cache wants a handful of things from whatever sits underneath it.  Reads and writes should be fast, entries should go away on their own after a while, a group of related entries should be easy to throw out at once, and losing the whole thing in a crash should be an inconvenience rather than a disaster.  TidesDB covers each of those with something it already has, so let's go through them before writing any code.

Every write lands in the memtable first, a skip list in RAM, so a key you just cached is served without touching the disk.  Once the memtable fills it is flushed to sorted files, and reads of older keys go through the block cache, which keeps the hot blocks of those files resident.  You size both, so as long as your working set fits, the cache behaves as if it never left memory.

Expiry is a TTL on the key itself.  You hand the put a lifetime in seconds, the engine turns it into an absolute deadline once and stores it with the value, and from then on a read compares that deadline against the clock.  An expired key reads as gone without anything having to delete it, and the bytes are dropped later when compaction merges the files they sit in, which I went through in more detail in the [TTL article](/articles/ttl-time-to-live-using-tidesql-in-mariadb).

Clearing a group of entries is a single call.  A prefix delete removes every key starting with a given prefix, it costs one entry in the log however many keys it covers, and it doesn't have to find those keys first.  If you lay your keys out as `user:42:profile`, `user:42:prefs` and so on, invalidating everything about user 42 is a delete of `user:42:`.

Durability you can mostly turn off.  With the sync mode set to `NONE` a commit doesn't wait on the disk at all, which is the fastest setting there is, and a crash can lose the most recent commits, which for a cache only means a few extra misses on the way back up.

What TidesDB won't do is evict on size.  There's no least-recently-used policy dropping entries when memory runs out, so the TTLs you give it are what keep it bounded, and if everything has a lifetime the data settles at whatever you write within one lifetime.  Anything that outlives the memtable is written to disk rather than thrown away, so a cache that is mostly hits stays fast, and one that is mostly cold entries pays a disk read for them like any other store would.

Let's put that together in C.  Here's a small program using TidesDB as a read-through cache in front of something slow.  It applies the settings above, then drops and recreates its column family on every boot, which is the quickest way to start empty.  The family uses read committed isolation, where a read carries no conflict bookkeeping and two writers of the same key simply let the last commit win, the behaviour you'd want from a cache anyway.

```c
#include <tidesdb/db.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static tidesdb_t *db;
static tidesdb_column_family_t *cache;

/* look a key up, returning a copy of its value or NULL on a miss */
static char *cache_get(const char *key)
{
    tidesdb_txn_t *txn = NULL;
    if (tidesdb_txn_begin(db, &txn) != TDB_SUCCESS) return NULL;

    uint8_t *value = NULL;
    size_t size = 0;
    char *out = NULL;
    if (tidesdb_txn_get(txn, cache, (const uint8_t *)key, strlen(key), &value, &size) ==
        TDB_SUCCESS)
    {
        out = malloc(size + 1);
        memcpy(out, value, size);
        out[size] = '\0';
        tidesdb_free(value);
    }
    tidesdb_txn_free(txn);
    return out;
}

/* look a key up and, on a hit, push its expiry out to ttl seconds from now. the refresh runs at
 * snapshot isolation, so if another writer changed the key after we read it the commit is refused
 * with TDB_ERR_CONFLICT, and we skip the refresh rather than write the old value back over theirs */
static char *cache_get_sliding(const char *key, time_t ttl)
{
    tidesdb_txn_t *txn = NULL;
    if (tidesdb_txn_begin_with_isolation(db, TDB_ISOLATION_SNAPSHOT, &txn) != TDB_SUCCESS)
        return NULL;

    uint8_t *value = NULL;
    size_t size = 0;
    char *out = NULL;
    if (tidesdb_txn_get(txn, cache, (const uint8_t *)key, strlen(key), &value, &size) ==
        TDB_SUCCESS)
    {
        out = malloc(size + 1);
        memcpy(out, value, size);
        out[size] = '\0';
        if (tidesdb_txn_put(txn, cache, (const uint8_t *)key, strlen(key), value, size, ttl) ==
            TDB_SUCCESS)
            (void)tidesdb_txn_commit(txn);
        tidesdb_free(value);
    }
    tidesdb_txn_free(txn);
    return out;
}

/* store a value that disappears ttl seconds from now */
static int cache_set(const char *key, const char *value, time_t ttl)
{
    tidesdb_txn_t *txn = NULL;
    int rc = tidesdb_txn_begin(db, &txn);
    if (rc != TDB_SUCCESS) return rc;
    rc = tidesdb_txn_put(txn, cache, (const uint8_t *)key, strlen(key), (const uint8_t *)value,
                         strlen(value), ttl);
    if (rc == TDB_SUCCESS) rc = tidesdb_txn_commit(txn);
    tidesdb_txn_free(txn);
    return rc;
}

/* drop every key starting with prefix in one write */
static int cache_invalidate(const char *prefix)
{
    tidesdb_txn_t *txn = NULL;
    int rc = tidesdb_txn_begin(db, &txn);
    if (rc != TDB_SUCCESS) return rc;
    rc = tidesdb_txn_delete_prefix(txn, cache, (const uint8_t *)prefix, strlen(prefix));
    if (rc == TDB_SUCCESS) rc = tidesdb_txn_commit(txn);
    tidesdb_txn_free(txn);
    return rc;
}

/* the slow thing the cache sits in front of, a database query or a remote call */
static void load_profile_from_origin(int id, char *out, size_t cap)
{
    usleep(200 * 1000);
    snprintf(out, cap, "{\"id\":%d,\"name\":\"user-%d\"}", id, id);
}

/* read through the cache, going to the origin only on a miss */
static char *get_profile(int id)
{
    char key[64];
    snprintf(key, sizeof(key), "user:%d:profile", id);

    char *hit = cache_get(key);
    if (hit)
    {
        printf("hit  %s\n", key);
        return hit;
    }

    printf("miss %s\n", key);
    char value[256];
    load_profile_from_origin(id, value, sizeof(value));
    cache_set(key, value, 2);
    return strdup(value);
}

int main(void)
{
    tidesdb_config_t config = tidesdb_default_config();
    config.db_path = "./cache_db";
    config.log_level = TDB_LOG_NONE;
    config.memtable_sync_mode = TDB_SYNC_NONE;
    config.memtable_write_buffer_size = 256 * 1024 * 1024;
    config.block_cache_size = 512 * 1024 * 1024;
    if (tidesdb_open(&config, &db) != TDB_SUCCESS) return 1;

    /* start empty on every boot, a cache owes nothing to the last run */
    (void)tidesdb_drop_column_family(db, "cache");
    tidesdb_column_family_config_t cf_config = tidesdb_default_column_family_config();
    cf_config.default_isolation_level = TDB_ISOLATION_READ_COMMITTED;
    if (tidesdb_create_column_family(db, "cache", &cf_config) != TDB_SUCCESS) return 1;
    cache = tidesdb_get_column_family(db, "cache");

    free(get_profile(42));
    free(get_profile(42));

    /* two keys that must change together, a session and the user it points at */
    tidesdb_txn_t *txn = NULL;
    tidesdb_txn_begin(db, &txn);
    tidesdb_txn_put(txn, cache, (const uint8_t *)"session:abc", 11, (const uint8_t *)"user:42", 7,
                    60);
    tidesdb_txn_put(txn, cache, (const uint8_t *)"user:42:last_seen", 17,
                    (const uint8_t *)"2026-10-06", 10, 60);
    if (tidesdb_txn_commit(txn) == TDB_SUCCESS) printf("session and last_seen written together\n");
    tidesdb_txn_free(txn);

    sleep(3);
    free(get_profile(42));

    cache_invalidate("user:42:");
    char *seen = cache_get("user:42:last_seen");
    printf("after invalidate, last_seen is %s\n", seen ? seen : "gone");
    free(seen);
    char *session = cache_get("session:abc");
    printf("session:abc is still %s\n", session ? session : "gone");
    free(session);

    /* a session with a two second sliding TTL, kept alive only by being used */
    cache_set("session:xyz", "user:7", 2);
    for (int i = 1; i <= 4; i++)
    {
        usleep(1500 * 1000);
        char *s = cache_get_sliding("session:xyz", 2);
        printf("%.1fs in, session:xyz is %s\n", i * 1.5, s ? "alive" : "expired");
        free(s);
    }
    sleep(3);
    char *idle = cache_get("session:xyz");
    printf("after 3s idle, session:xyz is %s\n", idle ? "alive" : "expired");
    free(idle);

    tidesdb_close(db);
    return 0;
}
```

Running it prints this.

```
miss user:42:profile
hit  user:42:profile
session and last_seen written together
miss user:42:profile
after invalidate, last_seen is gone
session:abc is still user:42
1.5s in, session:xyz is alive
3.0s in, session:xyz is alive
4.5s in, session:xyz is alive
6.0s in, session:xyz is alive
after 3s idle, session:xyz is expired
```

The first lookup misses and goes to the origin, and the second is served straight from the cache.  The profile was cached with a two second TTL, so after the three second sleep it has expired and the next lookup goes back to the origin without anything having removed it.  The session and the last seen time go in together in one transaction, so a reader sees both or neither, which is the transactional part I promised at the start.  The prefix delete then clears everything under `user:42:` in one write, and since `session:abc` sits outside that prefix it survives.

The last part is a sliding TTL, which is where it gets fun at the application level.  A fixed TTL counts down from the write, while a sliding one counts down from the last time anyone asked, so `session:xyz` was given two seconds and stayed alive for six because something kept reading it, then expired three seconds after the reads stopped.  `cache_get_sliding` does that by reading the value and writing it straight back with a fresh TTL in the same transaction.  The transaction runs at snapshot isolation for a reason, if another writer changes the key between our read and our write-back, the commit is refused with `TDB_ERR_CONFLICT` and the refresh is skipped, so we never put the old value back over the new one.  I checked that case on its own, the writer's value survived and the refresh was turned away.  Each hit does become a small write, which an LSM tree takes well, but it's worth keeping in mind for very large values or keys that are read thousands of times a second.

Sliding expiry is the natural fit for anything that should live as long as someone is using it.  Login sessions are the classic one, log out after thirty minutes of inactivity rather than thirty minutes after signing in, and the same goes for shopping carts, API tokens with an idle timeout, and the draft a user is halfway through editing.  Presence works the same way, a client that pings every few seconds keeps its online marker alive, and one that drops off disappears on its own without anyone noticing it left.  Leases do too, a worker holding a job or a lock renews it while it's healthy, and if it crashes the lease runs out and someone else can take it, with the snapshot guard making sure a renewal can't quietly win over a worker that has already taken the lease over.  And for plain caching it keeps popular entries around while cold ones age out, which gets you surprisingly close to the eviction behaviour TidesDB doesn't do on its own.

There's a lot of room to take this further in your application, since the value is yours to shape.  You can store your own expiry time next to the data and only refresh once more than half the TTL has passed, which keeps the sliding behaviour and turns most hits back into plain reads.  You can put a hard ceiling on it by storing when the entry was created and refusing to extend past a maximum age, so an active session still ends after twelve hours, which is usually what security wants.  You can grow the TTL with use, counting hits in the value and giving an entry a longer life the more often it's read, so hot keys stay put and one-off lookups leave quickly, a rough frequency-based eviction built from nothing but TTLs.  Or you can keep two deadlines, a soft one in the value and the hard one as the TTL, and serve a value past its soft deadline while you fetch a fresh one in the background, so readers never wait on the origin.

The same trick works from SQL without any special syntax, because rewriting a row gives it a new deadline.  An `UPDATE sessions SET last_seen = NOW(3) WHERE id = ?` on every request is a sliding TTL, the row lives as long as the session is active.  The one catch is that the update has to actually change something, both MariaDB and MySQL skip the engine entirely for an update that sets a column to the value it already holds, so the row is never rewritten and its clock keeps running, which is why a timestamp makes a good thing to touch.

The sizes in that config are just examples.  Give the memtable enough room for the writes you make between flushes, keeping in mind each entry costs about a hundred bytes of bookkeeping on top of its key and value, and give the block cache as much of your working set as you can afford.

Now if you'd rather stay in SQL, TideSQL is TidesDB through an extended plugin storage engine for MariaDB and MySQL, and the same ideas carry straight over.  The engine settings are server variables read at startup, so they go in your config file, here giving the memtable and block cache 256 MB and 1 GB.

```ini
[mysqld]
tidesdb_memtable_sync_mode = NONE
tidesdb_memtable_write_buffer_size = 256M
tidesdb_block_cache_size = 1G
```

These are server-wide, so if the same server also holds TidesDB tables you care about keeping, leave the sync mode alone and let the cache tables pay the default durability, nothing else here depends on it.

The cache itself is just a key-value table.  In MariaDB the TTL and the isolation level are table options.

```sql
CREATE TABLE kv_cache (
  k VARBINARY(255) PRIMARY KEY,
  v MEDIUMBLOB NOT NULL
) ENGINE=TidesDB TTL=300 ISOLATION_LEVEL='READ_COMMITTED';
```

MySQL has no engine-specific table grammar, so the same options go in `ENGINE_ATTRIBUTE`, and a misspelled one fails the statement instead of being stored and ignored.

```sql
CREATE TABLE kv_cache (
  k VARBINARY(255) PRIMARY KEY,
  v MEDIUMBLOB NOT NULL
) ENGINE=TidesDB ENGINE_ATTRIBUTE='{"ttl": 300, "isolation_level": "READ_COMMITTED"}';
```

Every row now lives five minutes unless you say otherwise.  To give a single write a different lifetime you set `tidesdb_ttl` around it, and MariaDB can scope that to one statement.

```sql
SET STATEMENT tidesdb_ttl=60 FOR
  INSERT INTO kv_cache VALUES ('config:flags', '{"beta":true}');
```

MySQL doesn't have `SET STATEMENT`, so there you set it for the session and put it back after.

```sql
SET SESSION tidesdb_ttl = 60;
INSERT INTO kv_cache VALUES ('config:flags', '{"beta":true}');
SET SESSION tidesdb_ttl = 0;
```

Writing a key again restarts its clock, because the new version carries a new deadline, which makes the usual cache write an upsert.  Here it is in MariaDB with the table's TTL dropped to three seconds so it's easy to watch.

```sql
INSERT INTO kv_cache VALUES
  ('user:42:profile', '{"id":42}'),
  ('user:42:prefs', '{"theme":"dark"}'),
  ('user:7:profile', '{"id":7}');

DO SLEEP(2);
INSERT INTO kv_cache VALUES ('user:7:profile', '{"id":7,"v":2}')
  ON DUPLICATE KEY UPDATE v = VALUES(v);
DO SLEEP(2);

SELECT k, v FROM kv_cache ORDER BY k;
```

In MySQL the upsert is written `INSERT ... AS new ON DUPLICATE KEY UPDATE v = new.v`.  Four seconds in, the rows written at the start have expired, the one rewritten at two seconds is still there with its new value, and `config:flags` is living out its sixty seconds.

```
+----------------+----------------+
| k              | v              |
+----------------+----------------+
| config:flags   | {"beta":true}  |
| user:7:profile | {"id":7,"v":2} |
+----------------+----------------+
```

Invalidating a group of keys is an ordinary delete on the prefix, and since the key is the primary key the server reads it as a range and only touches the rows under it.

```sql
DELETE FROM kv_cache WHERE k LIKE 'user:42:%';
```

Emptying the whole cache, at startup or whenever you like, is a truncate.

```sql
TRUNCATE TABLE kv_cache;
```

And this is where it gets interesting, because the cache is still a real table.  A key-value cache hands you a value for a key and not much else, here you can put secondary indexes on cached rows, scan them by range, and join them against your permanent tables.  Say sessions live for thirty minutes and you want to know how many each user has open right now.

```sql
CREATE TABLE sessions (
  id      VARBINARY(64) PRIMARY KEY,
  user_id INT NOT NULL,
  region  VARCHAR(16) NOT NULL,
  KEY by_user (user_id)
) ENGINE=TidesDB TTL=1800 ISOLATION_LEVEL='READ_COMMITTED';

SELECT u.name, COUNT(s.id) AS live_sessions
FROM users u LEFT JOIN sessions s ON s.user_id = u.id
GROUP BY u.name;
```

The index entries expire along with their rows, so a lookup through `by_user`, a scan of that index on its own, and the join above all stop counting a session the moment its time is up, the same way the base table does.  I watched that happen with a three second TTL, the counts went from two and one down to zero and zero with nothing deleted.

Ranges work the way you'd expect too, on the key or on any index, so `WHERE k >= 'user:40:' AND k < 'user:43:'` walks just those users, and `WHERE hits BETWEEN 5 AND 10` walks a `hits` index if you keep one.  The atomic writes from the C example are here as plain SQL, and a group you change your mind about rolls back without a trace.

```sql
START TRANSACTION;
INSERT INTO kv_cache (k, v) VALUES ('order:9:total', '100'), ('order:9:items', '3');
COMMIT;
```

You can even back the cache up while it's serving.  `SET GLOBAL tidesdb_backup_dir = '/path/to/backup'` takes an online copy of the engine, and because those deadlines are absolute, a server restored from it comes up warm with every entry still due to expire when it always was.

I ran every statement here on MariaDB 11.4 and on MySQL with TideSQL, apart from the backup, and they behave the same on both except for the two spellings I pointed out.

So that's TidesDB as a cache.  Turn the sync mode down, give it whatever memory you can spare, put a TTL on everything, and lay your keys out so a prefix names what belongs together.  What you get back is a cache that cleans up after itself and, from SQL, one you can query like any other table, and the only thing left to plan for is size, so pick your TTLs with the amount of data you write in mind.

Thanks for reading!

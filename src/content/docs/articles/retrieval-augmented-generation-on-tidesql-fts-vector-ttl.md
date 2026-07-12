---
title: "Retrieval-Augmented Generation on TideSQL - Hybrid full-text + vector search with TTL"
description: "Build the retrieval layer of a RAG pipeline on a single TideSQL table using a FULLTEXT index, a MariaDB VECTOR index, and TTL row expiry, with a runnable Python example."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-dmitriy-causelove-218646814-12030822.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-dmitriy-causelove-218646814-12030822.jpg
---

<div class="article-image">

![HammerDB TPC-C TideSQL v4.6.1 & InnoDB Analysis in MariaDB v11.8.6](/pexels-dmitriy-causelove-218646814-12030822.jpg)

</div>

*by <a target="_blank" href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on July 12th, 2026*

Retrieval-Augmented Generation (RAG) is only as good as its retrieval. Before a language model ever sees a prompt, something has to find the passages worth putting in front of it. Most stacks bolt a separate vector database onto their existing SQL database to do that, and then work having to keep the two systems in sync.

In this article I build the entire retrieval layer of a RAG pipeline on one TideSQL table, it gives us three things a RAG index needs, in the same table, under the same transaction:

- a FULLTEXT index for exact keyword, boolean, and phrase search (relevance ranked),
- a MariaDB VECTOR index (MHNSW) for approximate nearest-neighbour semantic search,
- and TTL so stale context expires on its own.

Everything below was run on <a target="_blank" href="https://github.com/MariaDB/server/releases/tag/mariadb-11.8.6">MariaDB v11.8.6</a> with TideSQL v4.6.1 over TidesDB v9.3.13, and there is a *complete*, runnable Python script at the end.

Lexical search and semantic search fail in opposite directions. Keyword search nails exact names, error codes, and identifiers but misses paraphrase. Vector search catches "make rows disappear" ≈ "expire records" but drifts on rare tokens. Serious RAG retrieval is hybrid, run both and fuse the rankings.

Doing that across a SQL database and a separate vector store means two query paths, two consistency models, and a synchronisation job that is always slightly behind. On TideSQL both indexes live on the same row, so an `INSERT` populates them atomically, a transaction sees a consistent view of both, and there is exactly one system to back up and operate. TTL then handles the thing RAG corpora always need and rarely get. Content that has gone stale is evicted automatically, with no cron job deleting rows behind your back.

One table carries the document, both indexes, and a per-row TTL:

```sql
CREATE TABLE docs (
    id        INT NOT NULL PRIMARY KEY,
    title     VARCHAR(200),
    body      TEXT,
    embedding VECTOR(256) NOT NULL,
    ttl_secs  INT `TTL`=1,
    FULLTEXT ft (title, body),
    VECTOR INDEX (embedding) DISTANCE=cosine
) ENGINE=TidesDB;
```

`SHOW CREATE TABLE` confirms TideSQL accepts all three on the same table:

```text
  `embedding` vector(256) NOT NULL,
  `ttl_secs` int(11) DEFAULT NULL `TTL`=1,
  PRIMARY KEY (`id`),
  FULLTEXT KEY `ft` (`title`,`body`),
  VECTOR KEY `embedding` (`embedding`) `DISTANCE`=cosine
) ENGINE=TidesDB
```

The `` `TTL`=1 `` column option marks `ttl_secs` as the per-row lifetime in seconds (`0` means "never expire"). You can also set a table-wide default with `ENGINE=TidesDB TTL=<seconds>`; a per-row value overrides it.

MariaDB's vector index is built for one metric (the default is euclidean), and it is only used when the `VEC_DISTANCE_*` function in the query matches the metric the index was built for. Since we query with `VEC_DISTANCE_COSINE`, the index is declared `DISTANCE=cosine`, and a mismatch silently falls back to a full table scan.

Retrieval needs a vector for every document and for the query. In production that vector comes from an embedding model. To keep this article self-contained and reproducible offline, the example ships a tiny dependency-free embedder. It uses feature hashing over words plus character 3-grams, L2-normalised. The character 3-grams give it enough morphological reach that "expire", "expires", and "expiration" land near each other, which is what lets the vector arm surface passages the exact keyword arm misses.

```python
DIM = 256

def _feature(token):
    h = int(hashlib.md5(token.encode()).hexdigest(), 16)
    return h % DIM, (1.0 if (h >> 40) & 1 else -1.0)

def embed(text):
    vec = [0.0] * DIM
    for w in re.findall(r"[a-z0-9]+", text.lower()):
        feats = [w]
        p = f"#{w}#"
        feats += ["$" + p[i:i + 3] for i in range(len(p) - 2)]
        for f in feats:
            idx, sign = _feature(f)
            vec[idx] += sign
    norm = math.sqrt(sum(x * x for x in vec)) or 1.0
    return [x / norm for x in vec]
```

This is a stand-in, not a good embedding model. Swap `embed()` for `sentence-transformers`, an embedding API, or any model you like, set `DIM` to that model's dimensionality, and nothing else in the pipeline changes. The point of the article is the TideSQL retrieval mechanics, and those are identical whichever embedder you use.

A vector is written with `Vec_FromText('[...]')`, so we format the Python list into that literal:

```python
def vec_literal(v):
    return "[" + ",".join(f"{x:.6f}" for x in v) + "]"
```

Each document is inserted with its embedding computed once at write time. Both the FULLTEXT and VECTOR indexes update as part of the same insert:

```python
cur.execute(
    "INSERT INTO docs (id,title,body,embedding,ttl_secs) "
    "VALUES (%s,%s,%s,Vec_FromText(%s),%s)",
    (doc_id, title, body, vec_literal(embed(f"{title}. {body}")), ttl))
```

The example loads a small knowledge base of twelve database facts (vector search, full-text relevance, TTL, LSM storage, MVCC, and so on).



The two hybrid search arms are two ordinary SQL queries.

Lexical, relevance-ranked by the FULLTEXT index:

```sql
SELECT id, MATCH(title,body) AGAINST(%s) AS s
FROM docs
WHERE MATCH(title,body) AGAINST(%s)
ORDER BY s DESC LIMIT %s;
```

`MATCH ... AGAINST` also supports boolean mode (`+must -not "exact phrase" prefix*`) when you need precise control.

Semantic, nearest neighbours by cosine distance over the VECTOR index:

```sql
SELECT id
FROM docs
ORDER BY VEC_DISTANCE_COSINE(embedding, Vec_FromText(%s)) LIMIT %s;
```

That exact `ORDER BY VEC_DISTANCE_COSINE(embedding, const) LIMIT k` shape, with the function matching the index's `DISTANCE=cosine`, is what triggers the MHNSW index. `EXPLAIN` confirms it with `type=index` and `key=embedding`. Query a metric the index was not built for and the same statement degrades to a full scan, `type=ALL` with `Using filesort`.

The two rankings are fused with Reciprocal Rank Fusion (RRF). A document's score is the sum of `1/(k + rank)` across both lists. RRF is rank-based, so it needs no score normalisation between the FULLTEXT relevance (TidesDB's full-text index ranks with BM25) and the cosine distance:

```python
def rrf(rankings, k=60):
    scores = {}
    for ranking in rankings:
        for rank, doc_id in enumerate(ranking, start=1):
            scores[doc_id] = scores.get(doc_id, 0.0) + 1.0 / (k + rank)
    return sorted(scores, key=scores.get, reverse=True)
```

Running queries against the twelve-document corpus, you can watch the two arms disagree and the fusion reconcile them:

```text
=== query: 'fast similarity search over embeddings'
  FULLTEXT rank : [1, 12]
  vector rank   : [1, 12, 9, 11, 8, 4, 6, 10]
  RRF fused top : [1, 12, 9, 11]
     -> [1]  MariaDB vector search
     -> [12] Hybrid search

=== query: 'how do I make old rows disappear on their own'
  FULLTEXT rank : [3, 11]
  vector rank   : [10, 6, 1, 11, 9, 4, 3, 5]
  RRF fused top : [11, 3, 10, 6]
     -> [11] Retrieval augmented generation
     -> [3]  Row expiration with TTL
```

The first query is the clean case, where the exact hit `MariaDB vector search` tops both arms and the fusion. The second shows the shape of each arm. The FULLTEXT arm is precise but sparse (it returns only `[3, 11]`, the rows whose terms actually match), while the vector arm always returns a full ranked neighbourhood. Fusing them keeps the relevant `Row expiration with TTL` in the results, though the hashing stand-in embedder ranks `Retrieval augmented generation` above it, which a real embedding model would sort out. The fusion code is unchanged either way, which is the point of using a rank-based method.

The fused passages are then packed into a prompt:

```python
def build_prompt(query, docs):
    context = "\n".join(f"[{i}] {t}: {b}" for i, t, b in docs)
    return (f"Answer the question using only the context.\n\n"
            f"Context:\n{context}\n\nQuestion: {query}\nAnswer:")
```

That prompt is the entire handoff to the model. Send it to your LLM of choice and you have RAG. The retrieval that produced it is pure TideSQL.

RAG corpora rot. Prices change, incidents close, announcements expire, and a model grounded in yesterday's context answers with yesterday's facts. TTL makes freshness a property of the data instead of a maintenance job. Insert a volatile note with a short lifetime:

```python
cur.execute("INSERT INTO docs (id,title,body,embedding,ttl_secs) "
            "VALUES (999,%s,%s,Vec_FromText(%s),%s)",
            ("Flash sale", "flash sale ends tonight only",
             vec_literal(embed("flash sale ends tonight only")), 10))
```

and it retrieves immediately, then disappears once its TTL elapses, with no delete and no scheduler:

```text
=== TTL freshness demo ===
  right after insert, 'flash sale' retrieves: ((999, 'Flash sale'),)
  waiting 13s for the row's TTL to expire ...
  after TTL expiry, 'flash sale' retrieves: ()
```

Give ephemeral sources a short TTL and durable knowledge `ttl_secs = 0`, and the index keeps itself current.

**Script**

```python
#!/usr/bin/env python3
"""RAG retrieval on TideSQL: FULLTEXT + VECTOR + TTL on one table."""
import hashlib, math, re, time
import pymysql

DIM = 256

def _feature(token):
    h = int(hashlib.md5(token.encode()).hexdigest(), 16)
    return h % DIM, (1.0 if (h >> 40) & 1 else -1.0)

def embed(text):
    vec = [0.0] * DIM
    for w in re.findall(r"[a-z0-9]+", text.lower()):
        feats = [w]
        p = f"#{w}#"
        feats += ["$" + p[i:i + 3] for i in range(len(p) - 2)]
        for f in feats:
            idx, sign = _feature(f)
            vec[idx] += sign
    norm = math.sqrt(sum(x * x for x in vec)) or 1.0
    return [x / norm for x in vec]

def vec_literal(v):
    return "[" + ",".join(f"{x:.6f}" for x in v) + "]"

CORPUS = [
    ("MariaDB vector search",
     "MariaDB stores embeddings in the VECTOR type and builds an MHNSW graph index "
     "so approximate nearest-neighbour queries over millions of vectors stay fast."),
    ("Full-text relevance",
     "A FULLTEXT index ranks documents by relevance. MATCH ... AGAINST supports "
     "natural language queries, boolean operators, phrases and prefix wildcards."),
    ("Row expiration with TTL",
     "TidesDB expires rows automatically. A table TTL sets a lifetime in seconds and "
     "a per-row TTL column overrides it, so old records vanish without a delete job."),
    # ... your documents here ...
]

def connect():
    # unix socket shown; for TCP use host="127.0.0.1", port=3310
    return pymysql.connect(unix_socket="/path/to/mysql.sock",
                           user="app", password="secret", autocommit=True)

def setup(conn):
    cur = conn.cursor()
    cur.execute("DROP DATABASE IF EXISTS ragkb")
    cur.execute("CREATE DATABASE ragkb")
    cur.execute("USE ragkb")
    cur.execute(f"""
        CREATE TABLE docs (
            id INT NOT NULL PRIMARY KEY, title VARCHAR(200), body TEXT,
            embedding VECTOR({DIM}) NOT NULL, ttl_secs INT `TTL`=1,
            FULLTEXT ft (title, body), VECTOR INDEX (embedding) DISTANCE=cosine
        ) ENGINE=TidesDB""")
    return cur

def ingest(cur, rows):
    for doc_id, title, body, ttl in rows:
        emb = embed(f"{title}. {body}")
        cur.execute("INSERT INTO docs (id,title,body,embedding,ttl_secs) "
                    "VALUES (%s,%s,%s,Vec_FromText(%s),%s)",
                    (doc_id, title, body, vec_literal(emb), ttl))

def fts_rank(cur, query, k):
    cur.execute("SELECT id, MATCH(title,body) AGAINST(%s) AS s FROM docs "
                "WHERE MATCH(title,body) AGAINST(%s) ORDER BY s DESC LIMIT %s",
                (query, query, k))
    return [r[0] for r in cur.fetchall()]

def vector_rank(cur, query, k):
    q = vec_literal(embed(query))
    cur.execute("SELECT id FROM docs "
                "ORDER BY VEC_DISTANCE_COSINE(embedding, Vec_FromText(%s)) LIMIT %s",
                (q, k))
    return [r[0] for r in cur.fetchall()]

def rrf(rankings, k=60):
    scores = {}
    for ranking in rankings:
        for rank, doc_id in enumerate(ranking, start=1):
            scores[doc_id] = scores.get(doc_id, 0.0) + 1.0 / (k + rank)
    return sorted(scores, key=scores.get, reverse=True)

def retrieve(cur, query, k=4, pool=8):
    fused = rrf([fts_rank(cur, query, pool), vector_rank(cur, query, pool)])[:k]
    if not fused:
        return []
    ph = ",".join(["%s"] * len(fused))
    cur.execute(f"SELECT id,title,body FROM docs WHERE id IN ({ph})", fused)
    by_id = {r[0]: r for r in cur.fetchall()}
    return [by_id[i] for i in fused if i in by_id]

def build_prompt(query, docs):
    context = "\n".join(f"[{i}] {t}: {b}" for i, t, b in docs)
    return (f"Answer the question using only the context.\n\nContext:\n{context}"
            f"\n\nQuestion: {query}\nAnswer:")

def main():
    conn = connect()
    cur = setup(conn)
    ingest(cur, [(i + 1, t, b, 0) for i, (t, b) in enumerate(CORPUS)])
    docs = retrieve(cur, "combine keyword and semantic ranking")
    print(build_prompt("combine keyword and semantic ranking", docs))
    # ... hand build_prompt(...) to your LLM ...
    conn.close()

if __name__ == "__main__":
    main()
```

The only dependency is `pymysql`; the vector maths is plain Python and the embedder is standard library. Point `connect()` at your server, drop your own documents into `CORPUS` (or ingest from wherever they live), and swap `embed()` for a real model. The listing here abbreviates `CORPUS` for space, so a copy-paste run returns those few rows; the downloadable script carries the full twelve documents the sample outputs above came from.

**Scaling to object storage**

A real RAG corpus does not stay small. Once the embeddings, text, and indexes outgrow a node's disk, the usual answer is a bigger disk. TidesDB's answer is object-store tiering. The durable copy of every SSTable lives in an object store (S3, MinIO, or a shared filesystem), and local disk keeps only an LRU-bounded cache of the hot working set. The same `docs` table (FULLTEXT, VECTOR, TTL and all) simply spills its cold data to the bucket.

Turning it on is configuration, not schema. Nothing in the table or the queries changes:

```ini
tidesdb_object_store_backend   = FS      # or S3
tidesdb_objstore_fs_path       = /srv/tidesdb-bucket/    # (S3: tidesdb_s3_endpoint / _bucket / _access_key ...)
tidesdb_objstore_local_cache_max = 67108864              # 64 MiB local hot-tier cap
tidesdb_objstore_cache_on_read  = ON
tidesdb_objstore_cache_on_write = ON
```

**How data moves**

The write path stays log-structured; the object store hangs off the end of it:

1. Rows land in the in-memory memtable and the write-ahead log.
2. When the memtable fills it flushes to a local SSTable, which is then uploaded to the object store by a pool of background upload threads (an async queue, so commits never wait on the network).
3. Compaction merges SSTables and re-uploads the results; the `MANIFEST` is re-published after each compaction so the object store always describes a consistent set of files. Closed WAL segments are uploaded too, so the durable history is complete.
4. The *local cache* keeps recently used SSTables on disk up to `local_cache_max`, evicting the least-recently-used files when it fills. Cold files exist only in the object store.
5. On a *read miss* the engine pulls what it needs back from the bucket, and because the connector supports ranged reads, a point lookup fetches just the block it needs rather than the whole SSTable.

**What tiering looks like**

Loading a 100,000-document knowledge base into the table above, with the local cache capped at 64 MiB, the two tiers separate cleanly as the upload queue drains:

```text
                    local SSTable cache   object store (durable)   local footprint
after ingest             ~63 MiB               640 MiB                1307 MiB
draining                 ~63 MiB              1060 MiB                 796 MiB
settled                  ~63 MiB (2 files)   ~1.5 GiB                 ~330 MiB
```

The local SSTable cache never leaves ~63 MiB, flat against its 64 MiB cap for the entire corpus, while the object store grows to hold the full durable set (every SSTable plus the replicated WAL history and the manifest). The node's local footprint peaked while the upload queue was backed up, then fell back as uploads drained and WAL truncated. Hybrid retrieval keeps answering the whole time, reading cold SSTables straight from the bucket while the cache stays bounded:

```text
query: 'how does compaction bound write amplification'
  FTS top: ['storage engines note ...: merge and compaction', ...]
  VEC top: ['storage engines note ...: compaction and structured', ...]
```

On this laptop-class box with the filesystem backend the uploads couldn't quite keep pace with a burst ingest, so there was a drain tail afterward; raising `tidesdb_objstore_max_concurrent_uploads` (and real S3 bandwidth) shortens it. The steady state is the point. Local disk is a cache, and the bucket is the source of truth.

**Replicas and failover from the same bucket**

Because the durable state lives in the object store, a second node can open the same bucket in replica mode (`tidesdb_replica_mode=ON`). It polls the `MANIFEST` files, pulls new SSTables, and optionally replays the WAL for near-real-time reads. That gives you read-only replicas serving the same RAG index, plus failover. A single-writer fence (conditional, ETag/epoch-tagged object writes) ensures only one primary publishes at a time. Set `tidesdb_objstore_wal_sync_on_commit=ON` and the WAL ships on every commit for a near-zero RPO (an in-flight commit is the only window). None of this is free, the fence, the manifest polling, and the WAL shipping are real machinery, but it is machinery you already have once the data lives in the object store, so the same table that answers your RAG queries is also replicated and durable there.

**Wrapping up**

The retrieval layer of a RAG pipeline is usually the operationally heaviest part. It typically means a vector store, a keyword engine, object storage for scale, and glue keeping them all consistent with the system of record. On TideSQL it collapses into one table. `FULLTEXT` gives lexical precision, the `VECTOR` index gives semantic recall, Reciprocal Rank Fusion blends them, `TTL` keeps the corpus fresh, and object-store tiering lets it grow past local disk while a replica can serve or take over from the same bucket, all transactional, all in MariaDB, with one thing to run and back up. The language model is the last, smallest step; the retrieval that makes it trustworthy is a handful of SQL.

*Thanks for reading!*
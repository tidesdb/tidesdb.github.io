---
title: "TideSQL v4.2.0 Full-Text Search, Vector Similarity, Spatial Queries, and Cloud-Native Capabilities"
description: "An article detailing the new features and fixes in TideSQL 4.2.0 MINOR release."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-diva-36783282.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-diva-36783282.jpg
---

<div class="article-image">

![TideSQL v4.2.0 Full-Text Search, Vector Similarity, Spatial Queries, and Cloud-Native Capabilities](/pexels-diva-36783282.jpg)

</div>

*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on March 31st, 2026*

Full-text search and spatial queries have been on the roadmap since TideSQL's earliest days. The ideas were there from the start, now in the latest minor release v4.2.0 the implementations are realized, and vector search came along for the ride. Each feature is accessed through standard SQL.

In this write up I will walk through each feature with working examples run against a live <a href="https://mariadb.org">MariaDB</a> v11.8.6 instance running the plugin with TidesDB v9.0.1.  

---

## Full-Text Search with BM25 Ranking

TideSQL now supports `FULLTEXT` indexes backed by an inverted index stored in its own column family. The ranking model is BM25. The implementation includes natural language mode, boolean mode with operators, exact phrase matching, and prefix wildcards.

```sql
CREATE TABLE articles (
  id    INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(200),
  body  TEXT,
  FULLTEXT ft_content (title, body)
) ENGINE=TidesDB;

INSERT INTO articles (title, body) VALUES
  ('Introduction to Database Systems',
   'A database management system (DBMS) is software that handles the
    storage, retrieval, and updating of data in a computer system.
    Modern relational databases use SQL as their primary query language.'),
  ('The Rise of LSM-Tree Storage',
   'Log-structured merge trees have become the dominant storage
    architecture for write-heavy workloads. Systems like LevelDB,
    RocksDB, and TidesDB use LSM trees to achieve high write throughput
    while maintaining acceptable read performance.'),
  ('ACID Transactions Explained',
   'Atomicity, Consistency, Isolation, and Durability form the four
    guarantees of reliable transaction processing. MVCC allows readers
    to proceed without blocking writers, achieving high concurrency
    without sacrificing correctness.'),
  ('Full-Text Search in Modern Databases',
   'Full-text search enables efficient querying of natural language text.
    BM25 ranking considers term frequency, document frequency, and
    document length to produce relevance scores. Boolean operators allow
    precise control over search results.'),
  ('Spatial Indexing with Space-Filling Curves',
   'R-trees have traditionally been used for spatial indexing, but
    LSM-tree engines require alternative approaches. Hilbert curves map
    two-dimensional coordinates to a one-dimensional key while preserving
    spatial locality, enabling efficient range queries on geographic data.'),
  ('Vector Search and Nearest Neighbors',
   'Approximate nearest neighbor search is essential for modern AI
    applications. HNSW graphs provide sub-linear search time over
    high-dimensional vector spaces, enabling similarity search over
    millions of embeddings.'),
  ('Building Cloud-Native Databases',
   'Object store backends like S3 decouple compute from storage.
    Replicas poll shared storage for updates, and failover requires only
    promoting a replica to primary mode. Schema discovery ensures table
    definitions propagate automatically.'),
  ('Concurrency Control Strategies',
   'Pessimistic locking serializes access to hot rows through lock
    acquisition before data access. Optimistic concurrency control allows
    transactions to proceed without locks and detects conflicts at commit
    time. Each approach has tradeoffs in throughput and latency under
    contention.');
```

### Natural Language Search

A natural language query tokenizes the input, scans the inverted index for each term, and ranks results by BM25 relevance:

```sql
SELECT id, title,
       ROUND(MATCH(title, body) AGAINST('LSM tree storage'), 4) AS score
FROM articles
WHERE MATCH(title, body) AGAINST('LSM tree storage')
ORDER BY score DESC;
```

```
+----+----------------------------------------------+--------+
| id | title                                        | score  |
+----+----------------------------------------------+--------+
|  2 | The Rise of LSM-Tree Storage                 | 4.2010 |
|  5 | Spatial Indexing with Space-Filling Curves   | 2.3735 |
|  7 | Building Cloud-Native Databases              | 1.3041 |
|  1 | Introduction to Database Systems             | 1.0259 |
+----+----------------------------------------------+--------+
```

The top result scores highest because all three query terms appear in its title and body. Documents mentioning only "storage" or "tree" in passing receive lower scores, normalized by document length.

### Boolean Mode

Boolean operators give precise control `+` requires a term, `-` excludes it, `*` matches prefixes, and `"..."` matches exact phrases.

```sql
-- Must contain MVCC AND concurrency
SELECT id, title FROM articles
WHERE MATCH(title, body) AGAINST('+MVCC +concurrency' IN BOOLEAN MODE);
```

```
+----+-----------------------------+
| id | title                       |
+----+-----------------------------+
|  3 | ACID Transactions Explained |
+----+-----------------------------+
```

```sql
-- Must contain database, must NOT contain vector
SELECT id, title FROM articles
WHERE MATCH(title, body) AGAINST('+database -vector' IN BOOLEAN MODE);
```

```
+----+--------------------------------------+
| id | title                                |
+----+--------------------------------------+
|  1 | Introduction to Database Systems     |
+----+--------------------------------------+
```

```sql
-- Prefix wildcard - anything starting with "transact"
SELECT id, title FROM articles
WHERE MATCH(title, body) AGAINST('transact*' IN BOOLEAN MODE);
```

```
+----+----------------------------------+
| id | title                            |
+----+----------------------------------+
|  3 | ACID Transactions Explained      |
|  8 | Concurrency Control Strategies   |
+----+----------------------------------+
```

```sql
-- Exact phrase - "term frequency" must appear as consecutive words
SELECT id, title FROM articles
WHERE MATCH(title, body) AGAINST('"term frequency"' IN BOOLEAN MODE);
```

```
+----+----------------------------------------+
| id | title                                  |
+----+----------------------------------------+
|  4 | Full-Text Search in Modern Databases   |
+----+----------------------------------------+
```

The tokenizer is charset-aware and handles UTF-8, CJK, Cyrillic, and other Unicode scripts. BM25 parameters `k1` and `b` are tunable via system variables for domain-specific ranking.

---

## Spatial Indexes

TideSQL implements spatial indexing using Hilbert curve encoding on the LSM tree, a space-filling curve maps 2D coordinates to a 1D key that preserves spatial locality, enabling geographic queries through sorted range scans.

```sql
CREATE TABLE cities (
  id       INT NOT NULL PRIMARY KEY,
  name     VARCHAR(100),
  country  VARCHAR(50),
  location GEOMETRY NOT NULL,
  SPATIAL INDEX (location)
) ENGINE=TidesDB;

INSERT INTO cities VALUES
  (1,  'New York',      'USA',       ST_GeomFromText('POINT(40.7128 -74.0060)')),
  (2,  'Los Angeles',   'USA',       ST_GeomFromText('POINT(34.0522 -118.2437)')),
  (3,  'Chicago',       'USA',       ST_GeomFromText('POINT(41.8781 -87.6298)')),
  (4,  'London',        'UK',        ST_GeomFromText('POINT(51.5074 -0.1278)')),
  (5,  'Paris',         'France',    ST_GeomFromText('POINT(48.8566 2.3522)')),
  (6,  'Tokyo',         'Japan',     ST_GeomFromText('POINT(35.6762 139.6503)')),
  (7,  'Sydney',        'Australia', ST_GeomFromText('POINT(-33.8688 151.2093)')),
  (8,  'Toronto',       'Canada',    ST_GeomFromText('POINT(43.6532 -79.3832)')),
  (9,  'Berlin',        'Germany',   ST_GeomFromText('POINT(52.5200 13.4050)')),
  (10, 'San Francisco', 'USA',       ST_GeomFromText('POINT(37.7749 -122.4194)')),
  (11, 'Seattle',       'USA',       ST_GeomFromText('POINT(47.6062 -122.3321)')),
  (12, 'Mexico City',   'Mexico',    ST_GeomFromText('POINT(19.4326 -99.1332)')),
  (13, 'Mumbai',        'India',     ST_GeomFromText('POINT(19.0760 72.8777)')),
  (14, 'Sao Paulo',     'Brazil',    ST_GeomFromText('POINT(-23.5505 -46.6333)')),
  (15, 'Moscow',        'Russia',    ST_GeomFromText('POINT(55.7558 37.6173)'));
```

### Geographic Bounding Box Queries

Find cities in the northeastern United States (latitude 39-44, longitude -80 to -70):

```sql
SELECT name, country FROM cities
WHERE MBRIntersects(location,
  ST_GeomFromText('POLYGON((39 -80, 44 -80, 44 -70, 39 -70, 39 -80))'))
ORDER BY name;
```

```
+----------+---------+
| name     | country |
+----------+---------+
| New York | USA     |
| Toronto  | Canada  |
+----------+---------+
```

Find cities in western Europe (latitude 45-56, longitude -5 to 15):

```sql
SELECT name, country FROM cities
WHERE MBRIntersects(location,
  ST_GeomFromText('POLYGON((45 -5, 56 -5, 56 15, 45 15, 45 -5))'))
ORDER BY name;
```

```
+--------+---------+
| name   | country |
+--------+---------+
| Berlin | Germany |
| Paris  | France  |
+--------+---------+
```

Find all cities in the southern hemisphere:

```sql
SELECT name, country FROM cities
WHERE MBRIntersects(location,
  ST_GeomFromText('POLYGON((-90 -180, 0 -180, 0 180, -90 180, -90 -180))'))
ORDER BY name;
```

```
+-----------+-----------+
| name      | country   |
+-----------+-----------+
| Sao Paulo | Brazil    |
| Sydney    | Australia |
+-----------+-----------+
```

Spatial queries use Hilbert range decomposition to avoid scanning the entire index. The query bounding box is mapped to a coarse grid on the Hilbert curve, and only the grid cells overlapping the box are scanned. Each candidate undergoes exact MBR predicate filtering. All standard spatial predicates are supported: `MBRIntersects`, `MBRContains`, `MBRWithin`, `MBREquals`, and `MBRDisjoint`.

---

## Vector Search

TideSQL supports approximate nearest neighbor search through MariaDB's built-in MHNSW (Multi-layer Hierarchical Navigable Small World) vector index. TidesDB provides the storage layer; MariaDB handles graph construction and search.

```sql
CREATE TABLE documents (
  id    INT NOT NULL PRIMARY KEY,
  title VARCHAR(200),
  v     VECTOR(8) NOT NULL,
  VECTOR INDEX (v)
) ENGINE=TidesDB;

INSERT INTO documents VALUES
  (1, 'machine learning basics',     Vec_FromText('[0.9, 0.1, 0.2, 0.8, 0.3, 0.1, 0.7, 0.4]')),
  (2, 'deep neural networks',        Vec_FromText('[0.8, 0.2, 0.3, 0.9, 0.2, 0.1, 0.8, 0.3]')),
  (3, 'database query optimization', Vec_FromText('[0.1, 0.8, 0.7, 0.2, 0.6, 0.9, 0.1, 0.3]')),
  (4, 'SQL performance tuning',      Vec_FromText('[0.2, 0.7, 0.8, 0.1, 0.7, 0.8, 0.2, 0.4]')),
  (5, 'natural language processing', Vec_FromText('[0.7, 0.3, 0.4, 0.7, 0.4, 0.2, 0.6, 0.5]')),
  (6, 'computer vision models',      Vec_FromText('[0.8, 0.1, 0.3, 0.8, 0.1, 0.2, 0.9, 0.2]')),
  (7, 'index data structures',       Vec_FromText('[0.3, 0.6, 0.9, 0.1, 0.8, 0.7, 0.2, 0.5]')),
  (8, 'cloud infrastructure',        Vec_FromText('[0.4, 0.5, 0.5, 0.4, 0.5, 0.5, 0.4, 0.6]'));
```

### Nearest Neighbor Search

Find the 3 documents most similar to an "AI/ML" query vector:

```sql
SELECT id, title,
  ROUND(VEC_DISTANCE_EUCLIDEAN(v,
    Vec_FromText('[0.85, 0.15, 0.25, 0.85, 0.25, 0.15, 0.75, 0.35]')), 4) AS distance
FROM documents
ORDER BY distance
LIMIT 3;
```

```
+----+----------------------------+----------+
| id | title                      | distance |
+----+----------------------------+----------+
|  1 | machine learning basics    |   0.1414 |
|  2 | deep neural networks       |   0.1414 |
|  6 | computer vision models     |   0.2828 |
+----+----------------------------+----------+
```

Find the 3 documents most similar to a "database" query vector:

```sql
SELECT id, title,
  ROUND(VEC_DISTANCE_EUCLIDEAN(v,
    Vec_FromText('[0.15, 0.75, 0.80, 0.15, 0.70, 0.85, 0.15, 0.40]')), 4) AS distance
FROM documents
ORDER BY distance
LIMIT 3;
```

```
+----+------------------------------+----------+
| id | title                        | distance |
+----+------------------------------+----------+
|  4 | SQL performance tuning       |   0.1118 |
|  3 | database query optimization  |   0.2062 |
|  7 | index data structures        |   0.3202 |
+----+------------------------------+----------+
```

The ML-oriented query vector correctly identifies machine learning and neural network documents as nearest neighbors. The database-oriented query vector correctly surfaces SQL and database optimization content. Both Euclidean and cosine distance metrics are supported.

---

## Object Store Fixes

S3-backed replication shipped in 4.1.0 but had gaps that prevented end-to-end operation. 4.2 adds automatic schema discovery via a reserved `__tidesql_schema` column family that replicates table definitions through S3 alongside row data. Replicas now discover databases and tables on their own. Several correctness fixes were also made where `.frm` storage now uses the in-memory image directly (MariaDB skips writing `.frm` to disk for discovery-enabled engines), a discovery retry loop that could hang indefinitely when a data CF hadn't synced yet was resolved.

---

## Summary

With the latest minor release of TideSQL, the engine reaches feature parity with what you would expect from a general-purpose SQL storage engine combined with S3-backed replication and single-command failover, it scales from a single node to a cloud-native deployment where compute is ephemeral and storage is infinite.

TideSQL 4.2 is available now at [github.com/tidesdb/tidesql](https://github.com/tidesdb/tidesql). Full reference  is available  [here](/reference/tidesql/).

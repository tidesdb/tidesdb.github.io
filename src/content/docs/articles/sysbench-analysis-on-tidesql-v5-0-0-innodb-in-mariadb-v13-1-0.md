---
title: "Sysbench 10 Workload Analysis on TideSQL 5 & InnoDB in MariaDB v13.1.0"
description: "A sysbench comparison of TideSQL v5.0.0 and InnoDB on MariaDB v13.1.0, across relaxed durability, full durability, and a matched large cache."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-toon-39376472.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-toon-39376472.jpg
---

<div class="article-image">

![Sysbench 10 Workload Analysis on TideSQL 5 & InnoDB in MariaDB v13.1.0](/pexels-toon-39376472.jpg)

</div>

*by <a target="_blank" href="https://alexpadula.com">Alex Gaetano Padula</a>*
 
*published on September 10th, 2026*

Today <a target="_blank" href="https://github.com/tidesdb/tidesql/releases/tag/v5.0.0">TideSQL v5.0.0</a> is out, an optional storage engine for MariaDB server 11.4 and onward that you install either through MariaDB's Foundry or through our own installer. To mark the release I ran it against InnoDB under sysbench on MariaDB v13.1.0, mostly at each engine's shipped defaults.

Before I jump into the benchmark let me give you an overview on what TideSQL is and what it offers and then explain what MariaDB Foundry is. TideSQL is a storage engine plugin for MariaDB, built on the TidesDB library and reached through the ordinary ENGINE=TidesDB clause, so moving a table onto it is a one-line change and everything above it stays standard SQL. It is fully transactional through the library's multi-version concurrency control, with the SQL isolation levels mapped onto the engine and durability tunable per commit from no fsync through a timed flush to a full sync on every commit. Being log-structured it favors write throughput and lets background compaction keep read cost bounded, which is where it pulls ahead on inserts, updates and deletes. Around that it carries a wide surface, primary and secondary indexes, foreign keys, auto-increment, virtual and stored generated columns and JSON, per-row data-at-rest encryption, compression, TTL expiration, online DDL, partitioning, savepoints, XA, and online backup through a consistent checkpoint. It indexes beyond the ordinary too, with BM25 full-text search, approximate nearest-neighbor vector search, and spatial indexes. And it is a first-class participant in both MariaDB replication and Galera clustering, with engine-level write-set certification and cross-node conflict resolution rather than a generic pass-through. You can read more on TideSQL <a target="_blank" href="https://github.com/tidesdb/tidesql/tree/master/doc">here</a>.

Now, Foundry is MariaDB's own tool for building and packaging plugins. Where the install.sh builder we ship clones and compiles a whole MariaDB server from source with TideSQL linked in, Foundry works the other way around, building the plugin out-of-tree against an already installed MariaDB and turning it into the standard tar.gz, rpm and deb packages a user installs with their package manager. That helps TideSQL in a few ways. It makes the engine accessible to anyone already running a stock MariaDB, who can add TideSQL as a package instead of rebuilding the server. It is also the path MariaDB's own continuous integration uses to build and test the plugin, so every change is exercised against real MariaDB releases across the platforms and architectures Foundry covers, which is how version-specific and architecture-specific behavior surfaces early rather than in the field. And for development it gives contributors the same fast out-of-tree build the CI runs, against a released server, so what passes locally is what passes upstream.

You can download MariaDB <a target="_blank" href="https://mariadb.org/download/?t=repo-config">here</a> through the foundation's website, mind you 11.4 is recommended at this time, otherwise use the TideSQL installer.

The numbers come from one machine.

- Intel Core i7-11700K, 8 cores and 16 threads at 3.6 GHz
- 46.8 GiB DDR4
- Ubuntu 23.03, Linux 6.2.0 x86_64
- WD Blue WDS500G2B0A, ext4
- gcc 12.3.0, linked against jemalloc
- TidesDB library <a target="_blank" href="https://github.com/tidesdb/tidesdb/releases/tag/v10.0.0">v10.0.0</a>
- TideSQL <a target="_blank" href="https://github.com/tidesdb/tidesql/tree/5.0.0">v5.0.0</a>

The workload is sysbench 1.1 against 16 tables of a million rows each, about 3 GB, reloaded fresh per engine, each point 20 measured seconds after a 3 second warmup at 1, 8 and 16 threads, at repeatable read with keys drawn uniformly. Neither engine's memory is tuned, InnoDB on a 128M buffer pool and TidesDB on a 256M block cache and 256M memtable, both far under the set, so both read from disk. Durability starts relaxed, InnoDB at innodb_flush_log_at_trx_commit=2 and TidesDB at sync mode NONE so neither fsyncs per commit, with InnoDB's doublewrite buffer left on and compression off on TidesDB. One quirk matters for reading the numbers, a single autocommit statement runs at read committed on both engines whatever the session asks, so only read_only, write_only and read_write, the three wrapped in BEGIN and COMMIT, really run at repeatable read.

The first chart is TidesDB throughput over InnoDB at 16 threads, so anything right of the line at 1 is a TidesDB win.

![Relative throughput at 16 threads](/sysbench-10-wl-analysis-on-tidesql-v5-0-0-innodb-in-mariadb-v13-1-0/fig2_relative_throughput.png)

The second is throughput against thread count, one panel per workload.

![Throughput vs concurrency](/sysbench-10-wl-analysis-on-tidesql-v5-0-0-innodb-in-mariadb-v13-1-0/fig1_throughput_scaling.png)

The write and update gaps are the widest, and structural. TidesDB puts a write into a memtable and one shared WAL that takes no fsync here and lets compaction sort it out, while InnoDB rewrites pages in a pool it keeps flushing, writes each page twice for the doublewrite buffer, and reads a page in first when the row is not resident. TidesDB needs no doublewrite of its own because every on-disk record is self-delimiting and checksummed, so a torn write is caught on recovery. Secondary-index updates hit the extreme at 60x, where InnoDB maintains two structures to TidesDB's append to both, and inserts run at 155k per second.

The read wins are smaller because both engines are going to disk, 4.1x on point select, 4.0x on read only, 8.9x on random points. Memory changes that, which the last run shows.

The lone InnoDB win is random_ranges, about 2.1x, and it held across all three thread counts. A covering index-range scan is a clustered B-tree at its best, a key range stored together and read in order, where an LSM merges that range across every overlapping level at more cost per row.

write_only and read_write are where TidesDB validates write conflicts optimistically at commit, so under contention it retries, and the retries grow with concurrency. write_only at 16 threads retried on the order of 70,000 times over the run, its 95th percentile latency rising from under a millisecond at 8 threads to about 10 ms at 16. It still ran at 17k per second, well ahead of InnoDB, but the tax is visible.

![95th percentile latency at 16 threads](/sysbench-10-wl-analysis-on-tidesql-v5-0-0-innodb-in-mariadb-v13-1-0/fig3_p95_latency.png)

That is tail latency at 16 threads on a log axis, lower is better. TidesDB sits well below InnoDB on the writes and updates, is comparable where its retries land, and trails only on random_ranges. The commit-time check has one operational catch, the conflict reaches the client as error 1180 wrapping the deadlock rather than the 1213 a lock-based engine returns at the statement, so a driver that only retries 1213 will not retry it.

With fsync on, InnoDB at innodb_flush_log_at_trx_commit=1 and TidesDB at sync mode FULL, reads are unchanged and the write ratios compress, update_index from 60x to 7x, write_only 51x to 13x, delete 57x to 8x, insert 38x to 5x, update_non_index 36x to a little over 2x, most of it on the TidesDB side since its relaxed speed came from skipping the fsync. It still leads nine of ten and again loses only random_ranges.

![Relative throughput at 16 threads, full durability](/sysbench-10-wl-analysis-on-tidesql-v5-0-0-innodb-in-mariadb-v13-1-0/fig4_relative_durable.png)

The cost shows most at one thread, where there is no group commit to amortize it, and TidesDB's insert drops from about 28,900 per second to 1,282 while InnoDB's drops from 1,435 to 696. Both recover with concurrency, TidesDB's durable insert scaling 1,282, 4,455 and 9,157 at 1, 8 and 16 threads.

The defaults leave one fair objection, that a 128M pool is far too small for a 3 GB set and the read numbers say more about a starved InnoDB than about the engine. So I gave both a 4G cache, enough to hold the set, and reran relaxed. This is the fair read comparison, neither engine going to disk for a row it has already seen.

![Relative throughput at 16 threads, matched 4G caches](/sysbench-10-wl-analysis-on-tidesql-v5-0-0-innodb-in-mariadb-v13-1-0/fig5_relative_throughput_4gb.png)

The reads flip. Point select goes from a 4.1x TidesDB win to InnoDB ahead by about 2.9x, read only from 4.0x to about 2x, random points from 8.9x to a dead heat. A fully resident clustered B-tree is the best case there is for a point lookup, the row sitting in a page the pool already holds, and InnoDB's point select jumps from 22k per second to 293k, while TidesDB's rises only from 93k to 100k because it was already served from its block cache and fence pointers rather than a cold file open.

The writes barely move, which is the point of running it. write_only stays 30x, the two updates stay in the low twenties, delete 13x, insert 7.6x, read_write 5.2x. A read cache does little for work whose cost is flushing and fsyncing pages, so the write side survives it and the read side does not.

Reads are where the LSM pays its one structural cost, a transient hit when compaction falls behind and a key range spreads across more files, the read amplification InnoDB's clustered B-tree never pays. Fence pointers and partition and range filters keep that miss path short, and TidesDB holds up well regardless.

A few disclaimers. This is one result from a small server, at each engine's defaults, with the full-durability and 4G runs varying one axis each. It tops out at 16 threads, and each point is a single 20 second run.

More to come on TideSQL, so keep an eye out, thank you for reading.

-- 

You can find raw benchmark data below:
- <a href="/sysbench-10-wl-analysis-on-tidesql-v5-0-0-innodb-in-mariadb-v13-1-0/data.zip">data.zip</a> (sha256: f5b7a3c2fd4376685126c554ea120353dac06cd761f7210d711b72401e19a204)
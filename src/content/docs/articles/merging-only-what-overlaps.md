---
title: "Merging Only What Overlaps"
description: "How TidesDB compacts, from the shared memtable and its flush through partitioned merges, levels that size themselves and every kind of delete, measured."
unlisted: true
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-stijn-dijkstra-1306815-2499791.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-stijn-dijkstra-1306815-2499791.jpg
---

<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>

<div class="article-image">

![Merging Only What Overlaps](/pexels-stijn-dijkstra-1306815-2499791.jpg)
<a target="_blank" href="https://www.instagram.com/furstset">Stijn Dijkstra</a>
</div>

*by <a target="_blank" href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on October 10th, 2026*

Every <a target="_blank" href="https://en.wikipedia.org/wiki/Log-structured_merge-tree">LSM-tree</a> writes your data more than once. It has to, that's how it keeps reads fast and gives deleted space back. The question is how much it rewrites each time, and whether it can stop at the parts that actually changed.

A write never changes anything in place.  It lands in Level 0, the memtable level, and a memtable is two things combined, a sorted index in memory and a log on disk.  The write goes to the log first, so a crash can't lose it, then into the index.  When the memtable is full, the index is written out as a sorted file, a sorted run, its log is removed and a fresh memtable takes over.  Sorted runs live in the levels below, Level 1 for fresh ones, then 2, 3 and so on, each larger than the last.

That makes writing fast, but files pile up, and a read may have to check several of them for the newest copy of a key.  Compaction is the background work that merges sorted runs down a level, dropping the old copies nobody can read anymore.  Too eager and the disk spends all day rewriting data you already wrote, too lazy and reads slow down while deleted data keeps its space.

TidesDB's compaction builds on <a target="_blank" href="https://www.vldb.org/pvldb/vol15/p3071-dayan.pdf">Spooky (Dayan et al., PVLDB 2022)</a>.  In TidesDB it all starts with one memtable shared by every column family.  Each key carries its family's index in front, so the sorted memtable keeps each family's keys together in one contiguous slot.  The commit that fills it seals it onto a queue, still readable, and a fresh one takes over on a new log.

Flush threads each grab the oldest sealed memtable nobody else has taken and build side by side, cutting it into one sorted run per column family for Level 1.  They install in the order they grabbed them, each memtable's runs in a single commit, then its log can go and compaction gets a nudge.

![Sealed memtables queue, flush threads build them in parallel and install them in order, one Level 1 sorted run per family](/merging-only-what-overlaps/pipeline.svg)

From there every column family grows its own levels below the shared Level 0, starting with just Level 1, sharing only the merge threads.

TidesDB sets a fixed size only for the largest level and sizes the others from what it actually holds, dynamic capacity adaptation in the paper's terms, adding a level when the largest fills and giving one back when your data goes away.

![Smaller levels are sized from what the largest holds, and a full largest level adds a new one](/merging-only-what-overlaps/capacity.svg)

The hard part is merging into the largest level, and the paper names the two usual answers.  A Full Merge compacts a whole level at once, so until it finishes the disk needs room for the old copy and the new, roughly twice your data.  A Partial Merge compacts small groups of files, but they rarely line up, so each merge rewrites neighbouring data it didn't need to.  Spooky lines them up.  TidesDB picks a dividing level, two above the largest by default, and every merge into it, a dividing merge, cuts its output at the key boundaries the largest level's files already have.  Each stretch of keys between two boundaries is a partition, and a merge only rewrites the partitions its keys fall into.

![A merge into one large file rewrites all of it, a partitioned merge rewrites only the partition it meets](/merging-only-what-overlaps/partitioned.svg)

Those boundaries are also how compaction uses more cores.  When every file being merged fits inside one partition, each partition becomes its own job, and with no file shared they all run at once.

![Aligned inputs fan out into a job per partition, a spanning flush is one job split across threads](/merging-only-what-overlaps/fanout.svg)

The small levels above the dividing level are folded into the smallest level with room, a preemptive merge in the paper's terms, and no merge writes a level back into itself.

Deletes are where compaction gives space back, and TidesDB has three kinds.  A regular delete writes a tombstone, a marker saying the key is gone, which merges carry down to the largest level, where nothing older can hide, and there it disappears with the old value.  A single-delete promises the key was written only once since its last delete, so it and that one value vanish the moment a merge sees both, at any level.  A range delete rides inside the sorted run it was flushed into and goes away with the merge that finishes it off at the bottom.

![A delete is carried to the largest level, a single-delete drops with its put, a range delete rides with its sorted run](/merging-only-what-overlaps/deletes.svg)

Sorted runs left mostly tombstones move down on their own, expired TTL keys go the same way, and only an open snapshot, a reader still looking at an older point in time, holds any of it back.

To see it happen I wrote a small <a href="/merging-only-what-overlaps/compaction.c">program</a> against TidesDB 10.  With a tiny 4MB memtable so the tree has to get deep, it loads 6 million keys (16 byte keys, 160 byte values) in random order, about a gigabyte, lets compaction settle, then deletes nine in ten.

<div class="not-content" style="margin:2rem 0 2rem;">
  <canvas id="cmp-levels"></canvas>
</div>

About fifteen seconds in, the third level fills and the next merge creates a fourth.  The deletes start at 42 seconds, their tombstones pile up in the small levels, then reach the bottom, and the whole thing drops from 1,055MB to 111MB in about two seconds.

<div class="not-content" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:1rem;margin:2rem 0 2rem;">
  <div style="margin:0"><canvas id="cmp-load"></canvas></div>
  <div style="margin:0"><canvas id="cmp-merges"></canvas></div>
  <div style="margin:0"><canvas id="cmp-largest"></canvas></div>
  <div style="margin:0"><canvas id="cmp-readamp"></canvas></div>
  <div style="margin:0"><canvas id="cmp-threads"></canvas></div>
</div>

<script src="/merging-only-what-overlaps/charts.js"></script>

Moving the dividing level (`dividing_level_offset`) trades many small merges against a few huge ones, and more compaction threads load faster, as the charts show.

Write amplification, the bytes the engine writes for every byte you write, sat around 11 in all those runs.  That's the paper's promise, the write amplification of a Full Merge without needing twice the disk.  With random keys every flushed run holds keys from all over, so every partition of the largest level gets rewritten, as many small jobs instead of one huge one.

In sequential mode the same keys are written in order.  Each new run lands after the last one, falls into the newest partition only, and most of the largest level is never touched again.

<div class="not-content" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:1rem;margin:2rem 0 2rem;">
  <div style="margin:0"><canvas id="cmp-order-wa"></canvas></div>
  <div style="margin:0"><canvas id="cmp-order-written"></canvas></div>
  <div style="margin:0"><canvas id="cmp-order-load"></canvas></div>
</div>

Write amplification dropped from 11.1 to 4.2, compaction wrote 3.4GB instead of 10.7GB, and the load finished in 15.6 seconds instead of 36.  Most real workloads sit somewhere between the two, and the more your writes cluster, the more partitioning saves, while large values <a target="_blank" href="/articles/keys-and-values-dont-always-belong-together/">separated from their keys</a> skip it all.

Thanks for reading!

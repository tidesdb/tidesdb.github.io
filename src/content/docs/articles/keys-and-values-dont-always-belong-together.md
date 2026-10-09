---
title: "Keys and Values Don't Always Belong Together"
description: "Why an LSM tree should keep large values out of compaction, how TidesDB's value log does it, and what it costs."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/pexels-asadphoto-24245330.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/pexels-asadphoto-24245330.jpg
---

<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>

<div class="article-image">

![Keys and Values Don't Always Belong Together](/pexels-asadphoto-24245330.jpg)
<a target="_blank" href="https://www.instagram.com/asad.photo">Asad Photo Maldives</a>
</div>

*by <a target="_blank" href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on October 9th, 2026*

Let's talk keys and values.  Most all databases in the world are built on this foundation, storing raw bytes and indexing them in the form of a key and its value once called upon.  

There are many data structures to achieve this, today we will focus on a normally persisted one called the <a href="https://en.wikipedia.org/wiki/Log-structured_merge-tree">log-structured-merge-tree</a>. 

In an LSM tree engine, writes are buffered at Level 0, flushing to sorted files at Level 1 then compacting up levels. Those sorted files usually have K, V, K, V, side by side often described as inline. That can be fine for small values, but for large values, this can cause severe write overhead.

An LSM tree keeps its levels sorted by merging them as it works, rewriting whatever each merge reads.  Doing that for 16 byte keys is not a big deal, but when the values riding along are 4 KB, every merge writes them out again even though they never change.  That phenomenon is called write amplification, the bytes the engine writes to disk for every byte you wrote, and it's what separating values is meant to cut.

![Values kept inline are rewritten by every merge](/keys-and-values-dont-always-belong-together/inline.svg)

The fix, laid out by the <a target="_blank" href="https://www.usenix.org/system/files/conference/fast16/fast16-papers-lu.pdf">WiscKey paper (Lu et al., FAST '16)</a>, is to keep only keys in the tree and put values somewhere they're written once and left alone.  In TidesDB a value at or above `value_separation_threshold` goes to a value log shared by the whole engine, and the key log(klog) stores a small logical id in its place.  Merges then move keys and ids, never values.

![Separated values stay where they were written while only keys are merged](/keys-and-values-dont-always-belong-together/separated.svg)

In TidesDB, a value is appended to the value log once -- at commit -- and from there onward, every layer just carries the key and the id, so the write-ahead log record, the memtable entry and the key log never copy the value.

![A commit writes the value once and moves only the key and its id after that](/keys-and-values-dont-always-belong-together/commit.svg)

In TidesDB an SSTable (sorted string table) is essentially a klog which in itself is a B+tree. A key log node is 4 KB by default, set with `btree_klog_block_size`, and the default large value threshold is a quarter of it (1 KB) on purpose -- since a 4 KB value kept inline fills a node by itself.

I thought I’d measure inline with 64 KB nodes to see how that plays out! A <a href="/keys-and-values-dont-always-belong-together/separation.c">program</a> against TidesDB 10 loads 250k keys with 4 KB values in random order, overwrites them all once more, waits for compaction to finish, then measures 100,000 point reads and a full scan to see how they perform.

<div class="not-content" style="display:flex;flex-wrap:wrap;gap:1.25rem;justify-content:center;margin:2rem 0 0.5rem;font-size:0.85rem;color:#8792a2;">
  <span><span style="display:inline-block;width:10px;height:10px;border-radius:2px;background:#193EDC;margin-right:6px;"></span>separated</span>
  <span><span style="display:inline-block;width:10px;height:10px;border-radius:2px;background:#809ae0;margin-right:6px;"></span>inline, 4 KB nodes</span>
  <span><span style="display:inline-block;width:10px;height:10px;border-radius:2px;background:#b4dbf7;margin-right:6px;"></span>inline, 64 KB nodes</span>
</div>

<div class="not-content" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:1rem;margin:0 0 2rem;">
  <div style="margin:0"><canvas id="sep-writes"></canvas></div>
  <div style="margin:0"><canvas id="sep-amp"></canvas></div>
  <div style="margin:0"><canvas id="sep-compaction"></canvas></div>
  <div style="margin:0"><canvas id="sep-read"></canvas></div>
  <div style="margin:0"><canvas id="sep-scan"></canvas></div>
  <div style="margin:0"><canvas id="sep-disk"></canvas></div>
</div>

<script>
document.addEventListener('DOMContentLoaded', function () {
  const colors = ['#193EDC', '#809ae0', '#b4dbf7'];
  const names = ['separated', 'inline, 4 KB nodes', 'inline, 64 KB nodes'];
  const ink = '#8792a2';
  const grid = 'rgba(135, 146, 162, 0.2)';

  /* the exact figure or measured range printed over each bar, ranges are drawn at their middle */
  const valueLabels = {
    id: 'valueLabels',
    afterDatasetsDraw(chart, args, opts) {
      const ctx = chart.ctx;
      const top = chart.getDatasetMeta(chart.data.datasets.length - 1).data;
      ctx.save();
      ctx.fillStyle = ink;
      ctx.font = '11px system-ui, sans-serif';
      ctx.textAlign = 'center';
      top.forEach((bar, i) => ctx.fillText(opts.labels[i], bar.x, Math.min(bar.y, chart.chartArea.bottom) - 5));
      ctx.restore();
    }
  };

  const panels = [
    ['sep-writes', 'writes per second, higher is better', [[200000, 74000, 82000]], ['~200k', '~74k', '75k to 89k']],
    ['sep-amp', 'write amplification', [[1.02, 4.35, 4.49]], ['1.02', '4.1 to 4.6', '4.49']],
    ['sep-compaction', 'GB compaction rewrote', [[0, 4.75, 5.1]], ['0', '4.3 to 5.2', '5.1']],
    ['sep-read', 'point read p50, µs', [[2.2, 5, 15]], ['2.2', '~5', '15']],
    ['sep-scan', 'full scan, seconds', [[0.35, 0.555, 0.255]], ['0.35', '0.48 to 0.63', '0.24 to 0.27']],
    ['sep-disk', 'MB on disk, before and after compaction', [[1036, 1036, 1029], [1032, 0, 0]], ['2,068 then 1,036', '1,036', '1,029']]
  ];

  for (const [id, title, series, labels] of panels) {
    const datasets = series.map((data, s) => ({
      data,
      backgroundColor: s === 0 ? colors : colors.map(c => c + '55'),
      borderRadius: 3,
      stack: 'all'
    }));
    new Chart(document.getElementById(id), {
      type: 'bar',
      data: { labels: names, datasets },
      options: {
        responsive: true,
        aspectRatio: 1.25,
        layout: { padding: { top: 18 } },
        plugins: {
          legend: { display: false },
          title: { display: true, text: title, color: ink, font: { size: 13, weight: 'normal' } },
          tooltip: { callbacks: { label: (c) => labels[c.dataIndex] }, filter: (c) => c.datasetIndex === 0 },
          valueLabels: { labels }
        },
        scales: {
          x: { stacked: true, ticks: { display: false }, grid: { display: false } },
          y: { stacked: true, beginAtZero: true, grace: '18%', ticks: { color: ink, font: { size: 10 }, maxTicksLimit: 5 }, grid: { color: grid } }
        }
      },
      plugins: [valueLabels]
    });
  }
});
</script>

Separated writes run almost three times faster, and the compaction panel shows they rewrote nothing.


The 64 KB node run still rewrote 5.1 GB, because compaction pays for the bytes it moves, however large nodes do make scans the fastest of the three, and point reads three times slower, since every lookup now decodes a 64 KB node.

There is a cost of separating, of course, a scan pays a second read per row, and old values stay on disk until compaction drops the keys pointing at them.  Reclaiming that is cheap in TidesDB, since every key log records which value log segments its values live in, thus a segment nothing references is deleted whole and a half empty one is drained by the next compaction that was going to run anyway.

![A segment nothing references is deleted whole, a half live one is drained by the next compaction](/keys-and-values-dont-always-belong-together/reclaim.svg)

So for large values written often and read by key, separating them is a big win, and for tables you mostly scan, `keep_values_inline` with bigger nodes is the better fit.

If you are curious about how TidesDB compares to <a target="_blank" href="https://github.com/facebook/rocksdb">RocksDB</a> utilizing a tool I wrote called <a target="_blank" href="https://github.com/guycipher/keybench">keybench</a>, especially comparing against the BlobDB configuration you can find that <a target="_blank" href="/articles/keybench-analysis-tidesdb-10-0-0-rocksdb-11-8-1">here</a>.  

Thanks for reading!

-- 

Thank you to Amar Sood (<a target="_blank" href="https://x.com/tekacs">@tekacs</a>) for proofreading this article and putting his own twist on it.
#!/usr/bin/env python3
"""Plot batch-constant sweep results. Two-panel layout, log-x batch axis.
Duplicate x values (repeat runs) are collapsed to a single mean point so
labels don't stack. Annotations go on the extrema and chosen values only."""
import csv
import os
from collections import defaultdict

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))


def load(paths):
    rows = []
    for p in paths:
        if not os.path.exists(p):
            continue
        with open(p) as f:
            for r in csv.DictReader(f):
                rows.append(r)
    return rows


def collapse(rows, xkey, phase):
    """Average duplicate x values per phase. Return sorted [(x, sec, rss_mb), ...]."""
    g = defaultdict(list)
    for r in rows:
        if r["phase"] != phase:
            continue
        g[int(r[xkey])].append(
            (float(r["seconds"]), int(r["peak_rss_kb"]))
        )
    out = []
    for x, vs in g.items():
        mean_s = sum(s for s, _ in vs) / len(vs)
        mean_rss = sum(rss for _, rss in vs) / len(vs) / 1024.0  # MB
        out.append((x, mean_s, mean_rss))
    return sorted(out)


rows = load([
    os.path.join(HERE, "sweep-results.csv"),
    os.path.join(HERE, "sweep-results-small.csv"),
    os.path.join(HERE, "sweep-results-tiny.csv"),
    os.path.join(HERE, "sweep-results-micro.csv"),
])

bulk = collapse(rows, "bulk_ops", "bulk")
idx = collapse(rows, "idx_batch", "idx")

def unzip(pts):
    if not pts:
        return [], [], []
    xs, ts, mss = zip(*pts)
    return list(xs), list(ts), list(mss)


bx, bt, bm = unzip(bulk)
ix, it, im = unzip(idx)

BULK_OPT = 500
IDX_OPT = 100

fig, axes = plt.subplots(2, 1, figsize=(13, 9), sharex=True,
                         gridspec_kw={"hspace": 0.08})

BULK_COLOR = "#B34242"
IDX_COLOR = "#2ACE27"

# ---- top: wall clock ----
ax = axes[0]
ax.plot(bx, bt, "o-", color=BULK_COLOR, linewidth=2, markersize=7,
        label=f"Bulk DML (INSERT ... SELECT 1 M rows, 3 sec. idx)  chosen = {BULK_OPT}")
ax.plot(ix, it, "s-", color=IDX_COLOR, linewidth=2, markersize=7,
        label=f"ADD INDEX x3 on a 1 M-row table                  chosen = {IDX_OPT}")

# Highlight chosen values
for x, pts, color, name in [(BULK_OPT, bulk, BULK_COLOR, "bulk"),
                            (IDX_OPT, idx, IDX_COLOR, "idx")]:
    y = dict((p[0], p[1]) for p in pts).get(x)
    if y is not None:
        ax.scatter([x], [y], s=180, facecolor="none",
                   edgecolor=color, linewidth=2, zorder=5)

def annotate_smart(ax, pts, color, fmt="{:.2f}s", chosen=None):
    """Annotate first, last, and chosen points with generous vertical
    offset so labels clearly clear the data line."""
    if not pts:
        return
    anchors = [pts[0], pts[-1]]
    if chosen is not None:
        for p in pts:
            if p[0] == chosen:
                anchors.append(p)
                break
    ymin, ymax = ax.get_ylim()
    yspan = ymax - ymin if ymax > ymin else 1
    for x, t, _ in anchors:
        yfrac = (t - ymin) / yspan
        if yfrac > 0.55:
            dy, va = -22, "top"
        else:
            dy, va = 22, "bottom"
        weight = "bold" if chosen == x else "normal"
        ax.annotate(fmt.format(t), (x, t), textcoords="offset points",
                    xytext=(0, dy), ha="center", va=va, fontsize=9, color=color,
                    fontweight=weight, clip_on=False,
                    bbox=dict(boxstyle="round,pad=0.2", facecolor="white",
                              edgecolor="none", alpha=0.85))


# Pad the axes so end-point labels never crowd the frame.
data_t = bt + it
ymin, ymax = min(data_t), max(data_t)
pad = 0.25 * (ymax - ymin)
ax.set_ylim(ymin - pad, ymax + pad)

all_x = sorted(set(bx + ix))
ax.set_xlim(all_x[0] / 1.8, all_x[-1] * 1.8)

annotate_smart(ax, bulk, BULK_COLOR, chosen=BULK_OPT)
annotate_smart(ax, idx, IDX_COLOR, chosen=IDX_OPT)

ax.set_xscale("log")
ax.set_ylabel("Wall clock (seconds)")
ax.set_title("TideSQL batch constant sweep: wall clock and peak RSS vs batch size", pad=12)
ax.grid(True, which="both", alpha=0.25)
ax.legend(loc="lower right", framealpha=0.9)

# Vertical guides at chosen values (dashed, light)
ax.axvline(BULK_OPT, color=BULK_COLOR, linestyle="--", alpha=0.35, linewidth=1)
ax.axvline(IDX_OPT, color=IDX_COLOR, linestyle="--", alpha=0.35, linewidth=1)

# ---- bottom: peak RSS ----
ax = axes[1]
ax.plot(bx, bm, "o-", color=BULK_COLOR, linewidth=2, markersize=7,
        label="Bulk DML peak RSS")
ax.plot(ix, im, "s-", color=IDX_COLOR, linewidth=2, markersize=7,
        label="ADD INDEX peak RSS")

for x, pts, color in [(BULK_OPT, bulk, BULK_COLOR),
                      (IDX_OPT, idx, IDX_COLOR)]:
    y = dict((p[0], p[2]) for p in pts).get(x)
    if y is not None:
        ax.scatter([x], [y], s=180, facecolor="none",
                   edgecolor=color, linewidth=2, zorder=5)


def annotate_rss_smart(ax, pts, color, chosen=None):
    if not pts:
        return
    anchors = [pts[0], pts[-1]]
    if chosen is not None:
        for p in pts:
            if p[0] == chosen:
                anchors.append(p)
                break
    ymin, ymax = ax.get_ylim()
    yspan = ymax - ymin if ymax > ymin else 1
    for x, _, rss in anchors:
        yfrac = (rss - ymin) / yspan
        if yfrac > 0.55:
            dy, va = -22, "top"
        else:
            dy, va = 22, "bottom"
        weight = "bold" if chosen == x else "normal"
        ax.annotate(f"{rss:.0f} MB", (x, rss), textcoords="offset points",
                    xytext=(0, dy), ha="center", va=va, fontsize=9, color=color,
                    fontweight=weight, clip_on=False,
                    bbox=dict(boxstyle="round,pad=0.2", facecolor="white",
                              edgecolor="none", alpha=0.85))


# Pad y-limits for RSS so labels don't touch the frame
data_rss = bm + im
rmin, rmax = min(data_rss), max(data_rss)
rpad = 0.25 * (rmax - rmin)
ax.set_ylim(rmin - rpad, rmax + rpad)

ax.set_xlim(all_x[0] / 1.8, all_x[-1] * 1.8)

annotate_rss_smart(ax, bulk, BULK_COLOR, chosen=BULK_OPT)
annotate_rss_smart(ax, idx, IDX_COLOR, chosen=IDX_OPT)

ax.axvline(BULK_OPT, color=BULK_COLOR, linestyle="--", alpha=0.3, linewidth=1)
ax.axvline(IDX_OPT, color=IDX_COLOR, linestyle="--", alpha=0.3, linewidth=1)

ax.set_xscale("log")
ax.set_xlabel("Batch constant (ops for bulk DML, rows for ADD INDEX). Log scale.")
ax.set_ylabel("Peak RSS (MB)")
ax.grid(True, which="both", alpha=0.25)
ax.legend(loc="upper left", framealpha=0.9)

plt.subplots_adjust(bottom=0.09, top=0.93, left=0.08, right=0.97)
out = os.path.join(HERE, "plot_batch_sweep.png")
fig.savefig(out, dpi=140)
print(f"wrote {out}")

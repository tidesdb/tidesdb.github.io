#!/usr/bin/env python3
"""Publishable plot for tidesql issue #122.  Two panels, no overlap
between legend / annotation / data / frame.  See prior discussion."""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


HERE = os.path.dirname(os.path.abspath(__file__))


def parse(path):
    t, tps, md = [], [], []
    if not os.path.exists(path):
        return t, tps, md
    with open(path) as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) < 10:
                continue
            if parts[0] in ("i_sec", "Insert", "Delete", "get_min_trxid",
                            "Totals:", "getmin", "Done"):
                continue
            try:
                ts = float(parts[1])
                tpsv = float(parts[3])
                mdv = float(parts[9]) / 1000.0
            except (ValueError, IndexError):
                continue
            t.append(ts)
            tps.append(tpsv)
            md.append(mdv)
    return t, tps, md


def rolling_max(xs, ys, window):
    """Rolling max over xs within +/- window.  Zeros are treated as
    'no data' (iibench reports max_d=0 when no deletes completed in
    that 1-second interval) and excluded, because a literal zero on a
    log scale plot reads as 'latency was instant' which is wrong."""
    out = []
    n = len(xs)
    lo = 0
    last_nonzero = None
    for i in range(n):
        x = xs[i]
        while lo < n and xs[lo] < x - window:
            lo += 1
        hi = i
        while hi + 1 < n and xs[hi + 1] <= x + window:
            hi += 1
        window_vals = [v for v in ys[lo:hi + 1] if v > 0]
        if window_vals:
            val = max(window_vals)
            last_nonzero = val
        else:
            val = last_nonzero if last_nonzero is not None else 0.0
        out.append(val)
    return out


series = [
    {
        "label": "After · TidesDB 9.1.0 / TideSQL 4.3.0 (this run)",
        "path": os.path.join(HERE, "ib.big.l.i1"),
        "color": "#193EDB",
        "zorder": 4,
    },
    {
        "label": "Before · TidesDB 9.0.9 / TideSQL 4.2.6 (gist from issue)",
        "path": os.path.join(HERE, "mark-tidesdb.txt"),
        "color": "#d62728",
        "zorder": 3,
    },
]

parsed = [(s, *parse(s["path"])) for s in series]

fig, axes = plt.subplots(2, 1, figsize=(14, 9), sharex=True,
                         gridspec_kw={"hspace": 0.1, "height_ratios": [1, 1]})

# Reserve space at top of figure for the single shared legend.
fig.subplots_adjust(top=0.87, bottom=0.13, left=0.08, right=0.97)

# ---- Panel 1: cumulative throughput ----
ax = axes[0]
handles = []
for s, t, tps, _ in parsed:
    if not t:
        continue
    h, = ax.plot(t, tps, color=s["color"], linewidth=2.4,
                 zorder=s["zorder"], label=s["label"], solid_capstyle="round")
    handles.append(h)

ax.set_yscale("log")
ax.set_ylabel("Cumulative rows / sec  (log)")
ax.grid(True, which="both", alpha=0.25)
ax.set_ylim(50, 2.5e5)
ax.set_xlim(-15, 1520)

# Shade region where 9.0.9 is still running (after 9.1.0 finished).
ax.axvspan(999, 1500, alpha=0.07, color="#d62728", zorder=1)

# Callout 1: 9.0.9 collapse onset. Place text in the empty mid-left area
# (below red line, above green's climb) so it cannot overlap data or legend.
ax.annotate(
    "9.0.9 collapses near t = 14 s\nand never recovers",
    xy=(16, 34000), xytext=(150, 300),
    color="#d62728", fontsize=10, fontweight="bold", ha="left", va="center",
    arrowprops=dict(arrowstyle="->", color="#d62728", lw=1.3, alpha=0.9,
                    connectionstyle="arc3,rad=-0.15"),
    bbox=dict(boxstyle="round,pad=0.35", facecolor="white",
              edgecolor="#d62728", alpha=0.95, linewidth=1.0),
)

# Callout 2: 9.1.0 completion. Place text below the blue line in empty area.
ax.annotate(
    "9.1.0 completes 16 M rows\nat t = 999 s, 16 k/s average",
    xy=(999, 16010), xytext=(560, 130),
    color="#193EDB", fontsize=10, fontweight="bold", ha="left", va="center",
    arrowprops=dict(arrowstyle="->", color="#193EDB", lw=1.3, alpha=0.9,
                    connectionstyle="arc3,rad=0.15"),
    bbox=dict(boxstyle="round,pad=0.35", facecolor="white",
              edgecolor="#193EDB", alpha=0.95, linewidth=1.0),
)

# Callout 3: label inside the shaded region. Positioned high, in empty space.
ax.text(
    1249, 1.4e5,
    "9.0.9: 1.35 M rows\nprocessed by t = 1437 s",
    color="#d62728", fontsize=9, ha="center", va="top",
    bbox=dict(boxstyle="round,pad=0.3", facecolor="white",
              edgecolor="#d62728", alpha=0.95, linewidth=0.8),
)

# ---- Panel 2: rolling max delete latency (10-s window) ----
ax = axes[1]
for s, t, _, md in parsed:
    if not t:
        continue
    md_roll = rolling_max(t, md, window=5.0)
    ax.plot(t, md_roll, color=s["color"], linewidth=2.0,
            zorder=s["zorder"], label=s["label"], solid_capstyle="round")

ax.set_yscale("log")
ax.set_ylabel("max delete latency  (ms, log, 10-s rolling)")
ax.set_xlabel("time in l.i1 phase  (seconds)")
ax.grid(True, which="both", alpha=0.25)
ax.set_xlim(-15, 1520)
ax.set_ylim(0.2, 2500)

# Issue-documented peaks: two dashed reference lines, combined into a
# single callout box to the right so the two labels can't stack.
ax.axhline(144, color="#d62728", linestyle=":", alpha=0.6, linewidth=1.2)
ax.axhline(171, color="#d62728", linestyle="--", alpha=0.6, linewidth=1.2)
ax.text(1510, 155,
        "reported in issue #122:\n"
        "144 ms at t = 1437 s (dotted)\n"
        "171 ms at t = 2023 s (dashed)",
        color="#d62728", fontsize=9, fontweight="bold",
        ha="right", va="center",
        bbox=dict(boxstyle="round,pad=0.35", facecolor="white",
                  edgecolor="#d62728", alpha=1.0, linewidth=0.9))

ax.axvspan(999, 1500, alpha=0.07, color="#d62728", zorder=1)

# ---- Single shared legend at the top of the figure ----
fig.legend(
    handles=handles,
    loc="upper center",
    bbox_to_anchor=(0.5, 0.965),
    ncol=len(handles), framealpha=0.95, fontsize=10, borderaxespad=0.2,
)

# ---- Title above the legend ----
fig.suptitle(
    "TidesDB 9.1.0 + TideSQL 4.3.0: l.i1 regime shift vs issue #122",
    fontsize=13, fontweight="bold", x=0.5, y=0.99,
)

# ---- Hardware footnote in the bottom margin (below xlabel) ----
fig.text(
    0.5, 0.045,
    "Setup: 1 client, 10 M preload, delete-per-insert, max_rows = 16 M, "
    "3 secondary indexes, SD primary OFF (default).",
    fontsize=8, color="#444", ha="center", va="bottom",
)
fig.text(
    0.5, 0.020,
    "Hardware: this run on 16-core / 48 GB; 9.0.9 gist on reporter's 48-core / 128 GB. "
    "InnoDB omitted because reporter's 23 GB buffer pool vs our 64 MB default would "
    "dominate the comparison. Regime shape is the signal.",
    fontsize=8, color="#444", ha="center", va="bottom",
)

out = os.path.join(HERE, "plot.png")
fig.savefig(out, dpi=150)
print(f"wrote {out}")

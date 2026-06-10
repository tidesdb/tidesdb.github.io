#!/usr/bin/env python3
"""Figures for TidesDB vs InnoDB sysbench comparison.

sysbench OLTP, 16 tables x 5M rows (~18 GB on InnoDB), 16 threads,
uniform random distribution, median of 3 x 120 s runs after 60 s warmup.
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import numpy as np
import pandas as pd

# style
TIDESDB = "#193EDB"
INNODB  = "#E17512"
COLORS  = {"tidesdb": TIDESDB, "innodb": INNODB}
LABELS  = {"tidesdb": "TidesDB", "innodb": "InnoDB"}

plt.rcParams.update({
    "font.family":      "serif",
    "font.serif":       ["DejaVu Serif", "Times New Roman", "Times"],
    "mathtext.fontset": "dejavuserif",
    "font.size":        10,
    "axes.titlesize":   11,
    "axes.labelsize":   10,
    "xtick.labelsize":  9,
    "ytick.labelsize":  9,
    "legend.fontsize":  9,
    "axes.linewidth":   0.8,
    "axes.edgecolor":   "#333333",
    "axes.grid":        True,
    "grid.color":       "#cccccc",
    "grid.linewidth":   0.5,
    "grid.linestyle":   ":",
    "axes.axisbelow":   True,
    "figure.dpi":       100,
    "savefig.dpi":      300,
    "savefig.bbox":     "tight",
    "savefig.pad_inches": 0.02,
})

WL_ORDER = ["oltp_point_select", "oltp_read_write", "oltp_update_index",
            "oltp_update_non_index", "oltp_insert", "oltp_delete"]
WL_PRETTY = {
    "oltp_point_select":     "Point\nSelect",
    "oltp_read_write":       "Read/\nWrite",
    "oltp_update_index":     "Update\n(Index)",
    "oltp_update_non_index": "Update\n(Non-Index)",
    "oltp_insert":           "Insert",
    "oltp_delete":           "Delete",
}
WL_PRETTY_FLAT = {k: v.replace("/\n", "/").replace("\n", " ") for k, v in WL_PRETTY.items()}

df = pd.read_csv("/mnt/user-data/uploads/summary.tsv", sep="\t")
df["workload"] = pd.Categorical(df["workload"], WL_ORDER, ordered=True)
df = df.sort_values(["engine", "workload"])

inno  = df[df.engine == "innodb"].set_index("workload").loc[WL_ORDER]
tides = df[df.engine == "tidesdb"].set_index("workload").loc[WL_ORDER]

x = np.arange(len(WL_ORDER))
W = 0.38

def fmt_val(v):
    if v >= 10000: return f"{v/1000:.1f}k"
    if v >= 1000:  return f"{v/1000:.2f}k"
    if v >= 100:   return f"{v:.0f}"
    return f"{v:.2f}".rstrip("0").rstrip(".")

def bar_pair(ax, a, b, log=True):
    r1 = ax.bar(x - W/2, a, W, color=INNODB,  label="InnoDB",
                edgecolor="black", linewidth=0.5, zorder=3)
    r2 = ax.bar(x + W/2, b, W, color=TIDESDB, label="TidesDB",
                edgecolor="black", linewidth=0.5, zorder=3)
    if log:
        ax.set_yscale("log")
    for rects in (r1, r2):
        for r in rects:
            ax.annotate(fmt_val(r.get_height()),
                        (r.get_x() + r.get_width()/2, r.get_height()),
                        xytext=(0, 2), textcoords="offset points",
                        ha="center", va="bottom", fontsize=7.5)
    ax.set_xticks(x)
    ax.set_xticklabels([WL_PRETTY[w] for w in WL_ORDER])
    ax.grid(axis="x", visible=False)
    return r1, r2

CAPTION = ("sysbench OLTP, 16 tables \u00d7 5M rows (\u224818 GB), 16 threads, "
           "uniform distribution; median of 3 \u00d7 120 s runs after 60 s warmup")

# ================================================== Fig 1: throughput (TPS)
fig, ax = plt.subplots(figsize=(7.0, 3.4))
bar_pair(ax, inno.median_tps, tides.median_tps)
ax.set_ylabel("Throughput (transactions/s, log scale)")
ax.set_ylim(top=ax.get_ylim()[1] * 2.2)
ax.legend(frameon=False, ncol=2, loc="upper left")
ax.set_title("OLTP Throughput: TidesDB vs.\u2009InnoDB", pad=8)
fig.text(0.5, -0.04, CAPTION, ha="center", fontsize=7.5, color="#555555")
fig.savefig("out/fig1_throughput_tps.pdf")
fig.savefig("out/fig1_throughput_tps.png")
plt.close(fig)

# ================================================== Fig 2: p95 latency
fig, ax = plt.subplots(figsize=(7.0, 3.4))
bar_pair(ax, inno.p95_ms, tides.p95_ms)
ax.set_ylabel("95th-percentile latency (ms, log scale)")
ax.set_ylim(top=ax.get_ylim()[1] * 2.2)
ax.legend(frameon=False, ncol=2, loc="upper left")
ax.set_title("Tail Latency (p95): TidesDB vs.\u2009InnoDB", pad=8)
fig.text(0.5, -0.04, CAPTION, ha="center", fontsize=7.5, color="#555555")
fig.savefig("out/fig2_p95_latency.pdf")
fig.savefig("out/fig2_p95_latency.png")
plt.close(fig)

# ================================================== Fig 3: speedup ratios
speed_tps = (tides.median_tps / inno.median_tps).values
speed_p95 = (inno.p95_ms / tides.p95_ms).values   # >1 means TidesDB lower latency

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(7.0, 3.2), sharey=True)
for ax, vals, title in ((ax1, speed_tps, "Throughput ratio\n(TidesDB TPS / InnoDB TPS)"),
                        (ax2, speed_p95, "Latency improvement\n(InnoDB p95 / TidesDB p95)")):
    colors = [TIDESDB if v >= 1 else INNODB for v in vals]
    rects = ax.bar(x, vals, 0.55, color=colors, edgecolor="black",
                   linewidth=0.5, zorder=3)
    ax.axhline(1.0, color="#333333", linewidth=0.8, linestyle="--", zorder=2)
    ax.set_yscale("log")
    ax.set_xticks(x)
    ax.set_xticklabels([WL_PRETTY_FLAT[w] for w in WL_ORDER], fontsize=7.5,
                       rotation=30, ha="right", rotation_mode="anchor")
    ax.set_title(title, fontsize=9.5)
    ax.grid(axis="x", visible=False)
    for r, v in zip(rects, vals):
        ax.annotate(f"{v:.2f}\u00d7" if v < 10 else f"{v:.1f}\u00d7",
                    (r.get_x() + r.get_width()/2, r.get_height()),
                    xytext=(0, 2), textcoords="offset points",
                    ha="center", va="bottom", fontsize=7.5)
ax1.set_ylabel("Ratio (log scale)")
ax1.set_ylim(top=max(speed_tps.max(), speed_p95.max()) * 2.5)
fig.suptitle("TidesDB Relative to InnoDB (values > 1\u00d7 favor TidesDB)", y=1.02, fontsize=11)
fig.text(0.5, -0.05, CAPTION, ha="center", fontsize=7.5, color="#555555")
fig.tight_layout()
fig.savefig("out/fig3_speedup.pdf")
fig.savefig("out/fig3_speedup.png")
plt.close(fig)

# ================================================== Fig 4: combined 2-panel (TPS + p95)
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(7.0, 5.6), sharex=True)
bar_pair(ax1, inno.median_tps, tides.median_tps)
ax1.set_ylabel("Throughput (txn/s)")
ax1.set_ylim(top=ax1.get_ylim()[1] * 2.5)
ax1.legend(frameon=False, ncol=2, loc="upper left")
ax1.set_title("(a) Median throughput", loc="left", fontsize=10)

bar_pair(ax2, inno.p95_ms, tides.p95_ms)
ax2.set_ylabel("p95 latency (ms)")
ax2.set_ylim(top=ax2.get_ylim()[1] * 2.5)
ax2.set_title("(b) 95th-percentile latency", loc="left", fontsize=10)

fig.align_ylabels((ax1, ax2))
fig.text(0.5, -0.015, CAPTION, ha="center", fontsize=7.5, color="#555555")
fig.tight_layout()
fig.savefig("out/fig4_combined.pdf")
fig.savefig("out/fig4_combined.png")
plt.close(fig)

# ================================================== Fig 5: throughput vs latency scatter
fig, ax = plt.subplots(figsize=(5.6, 4.2))
for eng, sub in (("innodb", inno), ("tidesdb", tides)):
    ax.scatter(sub.median_tps, sub.p95_ms, s=55, color=COLORS[eng],
               edgecolor="black", linewidth=0.5, label=LABELS[eng], zorder=4)
# connect same workload across engines
for wl in WL_ORDER:
    ax.plot([inno.loc[wl, "median_tps"], tides.loc[wl, "median_tps"]],
            [inno.loc[wl, "p95_ms"],     tides.loc[wl, "p95_ms"]],
            color="#999999", linewidth=0.7, linestyle="-", zorder=2)
# label each workload at its InnoDB marker (well separated along the diagonal)
offsets = {
    "oltp_point_select":     (-10,  6, "right"),
    "oltp_read_write":       ( 10,  0, "left"),
    "oltp_update_index":     ( 10,  0, "left"),
    "oltp_update_non_index": ( 10,  0, "left"),
    "oltp_insert":           ( 10,  0, "left"),
    "oltp_delete":           (-10, -3, "right"),
}
for wl in WL_ORDER:
    dx, dy, ha = offsets[wl]
    ax.annotate(WL_PRETTY_FLAT[wl],
                (inno.loc[wl, "median_tps"], inno.loc[wl, "p95_ms"]),
                xytext=(dx, dy), textcoords="offset points", ha=ha,
                va="center", fontsize=7.5, color="#444444")
ax.set_xscale("log"); ax.set_yscale("log")
ax.set_xlabel("Median throughput (transactions/s, log scale)")
ax.set_ylabel("p95 latency (ms, log scale)")
ax.set_title("Throughput\u2013Latency Profile by Workload", pad=8)
ax.legend(frameon=False, loc="upper right")
fig.text(0.5, -0.04, "Each line connects the same workload on both engines; "
         "down-and-right is better.", ha="center", fontsize=7.5, color="#555555")
fig.savefig("out/fig5_tput_latency.pdf")
fig.savefig("out/fig5_tput_latency.png")
plt.close(fig)

# quick numeric summary for the console
print("Speedup (TidesDB/InnoDB TPS):")
for wl, v in zip(WL_ORDER, speed_tps):
    print(f"  {WL_PRETTY_FLAT[wl]:22s} {v:8.2f}x")
print("\np95 improvement (InnoDB/TidesDB):")
for wl, v in zip(WL_ORDER, speed_p95):
    print(f"  {WL_PRETTY_FLAT[wl]:22s} {v:8.2f}x")
print("\nDone.")
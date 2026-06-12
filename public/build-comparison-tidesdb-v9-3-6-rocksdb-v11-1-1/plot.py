#!/usr/bin/env python3
"""Simple bar-chart plotter for the TidesDB, RocksDB build-time benchmark.

Usage:
    python3 plot.py <build_times.csv> <out.png> [tidesdb_tag] [rocksdb_tag]

Reads a CSV with header `project,run,seconds`, plots the MEDIAN build time per
project as a bar (with min/max whiskers for honesty), in each project's brand
colour, and writes a PNG.
"""
import csv
import statistics
import sys

import matplotlib
matplotlib.use("Agg")  # headless
import matplotlib.pyplot as plt

# brand colours requested
COLORS = {"tidesdb": "#183CD4", "rocksdb": "#F2B603"}


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    csv_path, out_path = sys.argv[1], sys.argv[2]
    tags = {
        "tidesdb": sys.argv[3] if len(sys.argv) > 3 else "",
        "rocksdb": sys.argv[4] if len(sys.argv) > 4 else "",
    }

    # collect timings per project, preserving first-seen order
    times: dict[str, list[float]] = {}
    with open(csv_path, newline="") as fh:
        for row in csv.DictReader(fh):
            times.setdefault(row["project"], []).append(float(row["seconds"]))

    if not times:
        print(f"no data in {csv_path}", file=sys.stderr)
        return 1

    projects = list(times.keys())
    medians = [statistics.median(times[p]) for p in projects]
    lows = [min(times[p]) for p in projects]
    highs = [max(times[p]) for p in projects]
    # asymmetric whiskers: distance from median down to min / up to max
    yerr = [[m - lo for m, lo in zip(medians, lows)],
            [hi - m for m, hi in zip(medians, highs)]]
    colors = [COLORS.get(p, "#888888") for p in projects]

    labels = [f"{p.replace('tidesdb','TidesDB').replace('rocksdb','RocksDB')}"
              + (f"\n{tags[p]}" if tags.get(p) else "") for p in projects]

    fig, ax = plt.subplots(figsize=(7, 5.5))
    bars = ax.bar(labels, medians, color=colors, width=0.55,
                  yerr=yerr, capsize=8, ecolor="#555555",
                  edgecolor="white", linewidth=1.2, zorder=3)

    runs = max(len(v) for v in times.values())
    stat = "median" if runs > 1 else "single run"
    ax.set_ylabel("Build time (seconds), lower is faster", fontsize=11)
    ax.set_title(f"Core library build time: TidesDB vs RocksDB\n"
                 f"static lib, Release, all cores, {stat} of {runs} run(s)",
                 fontsize=13, fontweight="bold")
    ax.grid(axis="y", linestyle="--", alpha=0.4, zorder=0)
    ax.set_axisbelow(True)
    for spine in ("top", "right"):
        ax.spines[spine].set_visible(False)
    ax.set_ylim(0, max(highs) * 1.18)

    # value labels on top of each bar
    for bar, m in zip(bars, medians):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height(),
                f"{m:.1f}s", ha="center", va="bottom",
                fontsize=12, fontweight="bold")

    # speed-ratio annotation when exactly two projects
    if len(projects) == 2 and min(medians) > 0:
        slow, fast = max(medians), min(medians)
        ax.text(0.5, 0.94, f"{slow/fast:.1f}x difference",
                transform=ax.transAxes, ha="center", fontsize=10,
                color="#444444", style="italic")

    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    print(f"wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

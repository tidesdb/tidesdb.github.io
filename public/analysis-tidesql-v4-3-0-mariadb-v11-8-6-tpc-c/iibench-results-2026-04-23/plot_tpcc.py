#!/usr/bin/env python3
"""Two plots from HammerDB TPROC-C CSV results.
1. plot_tpcc_version.png  -- v4.2.6 vs v4.3.0, both at 64 MB block cache
2. plot_tpcc_cache.png    -- v4.3.0 at 64 MB vs v4.3.0 at 16 GB
Same visual language as the other article plots."""
import csv
import os
import statistics

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = "/home/agpmastersystem/tidesdb.github.io/public/analysis-tidesql-v4-3-0-mariadb-v11-8-6-tpc-c"

# Hard grouping (provided by user):
# 20260423 files = v9.0.9 + v4.2.6 @ 64 MB
# 20260424 files = v9.1.0 + v4.3.0 @ 64 MB,  except _181939 which is 16 GB
BEFORE_64MB = ["hammerdb_results_20260423_181701.csv",
               "hammerdb_results_20260423_182443.csv"]
AFTER_64MB  = ["hammerdb_results_20260424_180146.csv",
               "hammerdb_results_20260424_181053.csv",
               "hammerdb_results_20260424_193644.csv"]
AFTER_16GB  = ["hammerdb_results_20260424_181939.csv"]

FIELDS = ["nopm", "tpm", "neword_avg_ms", "neword_p95_ms",
          "payment_avg_ms", "payment_p95_ms",
          "delivery_avg_ms", "delivery_p95_ms"]


def load_group(files):
    rows = []
    for f in files:
        with open(os.path.join(DATA, f)) as fh:
            for r in csv.DictReader(fh):
                rows.append(r)
    agg = {}
    for k in FIELDS:
        vals = [float(r[k]) for r in rows if r.get(k) not in (None, "")]
        if not vals:
            continue
        agg[k] = {
            "mean": statistics.mean(vals),
            "lo":   min(vals),
            "hi":   max(vals),
            "n":    len(vals),
        }
    return agg


def render(path, groups, title, subtitle, color_before, color_after):
    """groups = [(label, agg_dict, color), ...] in draw order"""
    fig, axes = plt.subplots(1, 2, figsize=(14, 6),
                             gridspec_kw={"width_ratios": [1, 1.2]})
    fig.suptitle(title, fontsize=13, fontweight="bold", y=0.97)
    fig.text(0.5, 0.92, subtitle, fontsize=9.5, color="#444", ha="center")

    # ---- Left: throughput (higher is better) ----
    ax = axes[0]
    metrics = [("nopm", "NOPM"), ("tpm", "TPM")]
    x = list(range(len(metrics)))
    width = 0.85 / len(groups)

    for i, (label, agg, color) in enumerate(groups):
        xs = [xi + (i - (len(groups) - 1) / 2) * width for xi in x]
        means = [agg[m]["mean"] for m, _ in metrics]
        err_lo = [agg[m]["mean"] - agg[m]["lo"] for m, _ in metrics]
        err_hi = [agg[m]["hi"] - agg[m]["mean"] for m, _ in metrics]
        ax.bar(xs, means, width=width * 0.92, color=color, edgecolor="white",
               yerr=[err_lo, err_hi], capsize=4, ecolor="#333", label=label,
               linewidth=0.8)
        for xi, m in zip(xs, means):
            ax.text(xi, m, f"{m:,.0f}", ha="center", va="bottom",
                    fontsize=9, color=color, fontweight="bold",
                    bbox=dict(boxstyle="round,pad=0.2", facecolor="white",
                              edgecolor="none", alpha=0.85))
    ax.set_xticks(x)
    ax.set_xticklabels([lab for _, lab in metrics])
    ax.set_ylabel("Transactions per minute (higher is better)")
    ax.grid(True, axis="y", alpha=0.25)
    ax.legend(loc="upper left", framealpha=0.95, fontsize=9)

    # pad top so value labels clear the frame
    ymax = max(agg[m]["hi"] for _, agg, _ in groups for m, _ in metrics)
    ax.set_ylim(0, ymax * 1.18)

    # ---- Right: p95 latencies (lower is better) ----
    ax = axes[1]
    metrics = [("neword_p95_ms", "neword p95"),
               ("payment_p95_ms", "payment p95"),
               ("delivery_p95_ms", "delivery p95")]
    x = list(range(len(metrics)))
    for i, (label, agg, color) in enumerate(groups):
        xs = [xi + (i - (len(groups) - 1) / 2) * width for xi in x]
        means = [agg[m]["mean"] for m, _ in metrics]
        err_lo = [agg[m]["mean"] - agg[m]["lo"] for m, _ in metrics]
        err_hi = [agg[m]["hi"] - agg[m]["mean"] for m, _ in metrics]
        ax.bar(xs, means, width=width * 0.92, color=color, edgecolor="white",
               yerr=[err_lo, err_hi], capsize=4, ecolor="#333", label=label,
               linewidth=0.8)
        for xi, m in zip(xs, means):
            ax.text(xi, m, f"{m:.2f}", ha="center", va="bottom",
                    fontsize=9, color=color, fontweight="bold",
                    bbox=dict(boxstyle="round,pad=0.2", facecolor="white",
                              edgecolor="none", alpha=0.85))
    ax.set_xticks(x)
    ax.set_xticklabels([lab for _, lab in metrics])
    ax.set_ylabel("p95 latency, ms (lower is better)")
    ax.grid(True, axis="y", alpha=0.25)
    ax.legend(loc="upper left", framealpha=0.95, fontsize=9)

    ymax = max(agg[m]["hi"] for _, agg, _ in groups for m, _ in metrics)
    ax.set_ylim(0, ymax * 1.2)

    plt.subplots_adjust(top=0.87, bottom=0.1, left=0.07, right=0.98, wspace=0.18)
    fig.savefig(path, dpi=150)
    print(f"wrote {path}")


def main():
    before = load_group(BEFORE_64MB)
    after_64 = load_group(AFTER_64MB)
    after_16g = load_group(AFTER_16GB)

    BLUE = "#193EDB"
    RED = "#d62728"
    GREEN = "#2ca02c"
    GRAY = "#888888"

    # Plot 1: version comparison at 64 MB
    render(
        os.path.join(HERE, "plot_tpcc_version.png"),
        groups=[
            (f"Before   v4.2.6 + v9.0.9   64 MB block cache   ({before['tpm']['n']} runs)",
             before, RED),
            (f"After    v4.3.0 + v9.1.0   64 MB block cache   ({after_64['tpm']['n']} runs)",
             after_64, BLUE),
        ],
        title="HammerDB TPROC-C on MariaDB 11.8.6, 40 warehouses, 8 virtual users, 2 min duration",
        subtitle="Version comparison at identical 64 MB block cache and 64 MB unified memtable write buffer",
        color_before=RED, color_after=BLUE,
    )

    # Plot 2: cache scaling at v4.3.0
    render(
        os.path.join(HERE, "plot_tpcc_cache.png"),
        groups=[
            (f"v4.3.0 + v9.1.0   64 MB block cache   ({after_64['tpm']['n']} runs)",
             after_64, BLUE),
            (f"v4.3.0 + v9.1.0   16 GB block cache   (1 run)",
             after_16g, GREEN),
        ],
        title="HammerDB TPROC-C on MariaDB 11.8.6, 40 warehouses, 8 virtual users, 2 min duration",
        subtitle="Block cache sizing on v4.3.0: 64 MB default versus 16 GB",
        color_before=BLUE, color_after=GREEN,
    )


if __name__ == "__main__":
    main()

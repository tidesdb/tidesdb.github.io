#!/usr/bin/env python3
"""
Benchmark Plotting Script
Compares TidesDB (TideSQL v3.3.5) in MariaDB v12.2.2,
InnoDB in MariaDB v12.2.2, and InnoDB in MySQL v9.5.0.

Reads summary and detail CSVs from run1/ and run2/ directories,
generates comparison charts as PNG files.
"""

import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np
import os
import glob

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
RUN1_DIR = os.path.join(BASE_DIR, 'run1')
RUN2_DIR = os.path.join(BASE_DIR, 'run2')
OUTPUT_DIR = BASE_DIR

COLORS = {
    'TidesDB (MariaDB 12.2.2)': '#0077b6',
    'InnoDB (MariaDB 12.2.2)': '#e85d04',
    'InnoDB (MySQL 9.5.0)': '#2d6a4f',
}

WORKLOAD_LABELS = {
    'oltp_read_write': 'OLTP Read/Write',
    'oltp_point_select': 'OLTP Point Select',
    'oltp_insert': 'OLTP Insert',
    'oltp_write_only': 'OLTP Write Only',
}

WORKLOAD_ORDER = ['oltp_read_write', 'oltp_point_select',
                  'oltp_insert', 'oltp_write_only']
ENGINE_ORDER = ['TidesDB (MariaDB 12.2.2)',
                'InnoDB (MariaDB 12.2.2)',
                'InnoDB (MySQL 9.5.0)']
THREAD_COUNTS = [1, 8, 16, 32]

# Matplotlib defaults
plt.rcParams.update({
    'figure.dpi': 150,
    'font.size': 11,
    'axes.titlesize': 13,
    'axes.labelsize': 11,
    'xtick.labelsize': 10,
    'ytick.labelsize': 10,
    'legend.fontsize': 9,
    'figure.titlesize': 15,
    'axes.grid': True,
    'grid.alpha': 0.3,
})


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def find_latest_csv(directory, prefix):
    """Return the latest (by filename) CSV matching *prefix* in *directory*."""
    files = sorted(glob.glob(os.path.join(directory, f'{prefix}_*.csv')))
    for f in reversed(files):
        if os.path.getsize(f) > 300:
            return f
    return files[-1] if files else None


def fmt(x, _pos=None):
    """Format large numbers with K / M suffixes."""
    if abs(x) >= 1_000_000:
        return f'{x / 1_000_000:.1f}M'
    if abs(x) >= 1_000:
        return f'{x / 1_000:.1f}K'
    return f'{x:.0f}'


def fmt_short(v):
    """Short label for bar annotations."""
    if abs(v) >= 1_000_000:
        return f'{v / 1_000_000:.1f}M'
    if abs(v) >= 10_000:
        return f'{v / 1_000:.0f}K'
    if abs(v) >= 1_000:
        return f'{v / 1_000:.1f}K'
    if abs(v) >= 10:
        return f'{v:.0f}'
    return f'{v:.2f}'


# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------
def load_summary():
    """Load and merge summary CSVs from both runs."""
    r1 = pd.read_csv(find_latest_csv(RUN1_DIR, 'summary'))
    r2 = pd.read_csv(find_latest_csv(RUN2_DIR, 'summary'))
    r1.dropna(subset=['engine'], inplace=True)
    r2.dropna(subset=['engine'], inplace=True)

    r1['source'] = r1['engine'].apply(lambda e: f'{e} (MariaDB 12.2.2)')
    r2['source'] = 'InnoDB (MySQL 9.5.0)'

    r1['avg_tps'] = r1['tps'] / r1['total_time_s']
    r2['avg_tps'] = r2['tps'] / r2['total_time_s']
    r1['avg_qps'] = r1['qps'] / r1['total_time_s']
    r2['avg_qps'] = r2['qps'] / r2['total_time_s']

    return pd.concat([r1, r2], ignore_index=True)


def load_detail():
    """Load and merge detail (time-series) CSVs from both runs."""
    r1 = pd.read_csv(find_latest_csv(RUN1_DIR, 'detail'))
    r2 = pd.read_csv(find_latest_csv(RUN2_DIR, 'detail'))

    r1['source'] = r1['engine'].apply(lambda e: f'{e} (MariaDB 12.2.2)')
    r2['source'] = 'InnoDB (MySQL 9.5.0)'

    return pd.concat([r1, r2], ignore_index=True)


# ---------------------------------------------------------------------------
# Plotting helpers
# ---------------------------------------------------------------------------
def _get_values(wl_data, engine, threads, column):
    """Extract a list of *column* values for each thread count."""
    eng = wl_data[wl_data['source'] == engine].sort_values('threads')
    vals = []
    for tc in threads:
        row = eng[eng['threads'] == tc]
        vals.append(row[column].values[0] if len(row) > 0 else 0)
    return vals


def _annotate_bars(ax, bars, values, rotation=45, fontsize=7):
    for bar, v in zip(bars, values):
        if v > 0:
            ax.text(bar.get_x() + bar.get_width() / 2,
                    bar.get_height(), fmt_short(v),
                    ha='center', va='bottom',
                    fontsize=fontsize, rotation=rotation)


# ---------------------------------------------------------------------------
# Chart generators
# ---------------------------------------------------------------------------
def plot_tps_comparison(summary):
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    fig.suptitle(
        'Average TPS by Workload & Thread Count\n'
        'TidesDB (MariaDB 12.2.2)  vs  InnoDB (MariaDB 12.2.2)  vs  InnoDB (MySQL 9.5.0)',
        fontweight='bold')

    bw = 0.25
    x = np.arange(len(THREAD_COUNTS))

    for idx, wl in enumerate(WORKLOAD_ORDER):
        ax = axes[idx // 2][idx % 2]
        wd = summary[summary['workload'] == wl]

        for i, eng in enumerate(ENGINE_ORDER):
            vals = _get_values(wd, eng, THREAD_COUNTS, 'avg_tps')
            bars = ax.bar(x + i * bw, vals, bw,
                          label=eng, color=COLORS[eng],
                          edgecolor='white', linewidth=0.5)
            _annotate_bars(ax, bars, vals)

        ax.set_title(WORKLOAD_LABELS[wl], fontweight='bold')
        ax.set_xlabel('Thread Count')
        ax.set_ylabel('Average TPS')
        ax.set_xticks(x + bw)
        ax.set_xticklabels(THREAD_COUNTS)
        ax.set_yscale('log')
        ax.yaxis.set_major_formatter(ticker.FuncFormatter(fmt))
        ax.legend(loc='upper left', framealpha=0.9)

    plt.tight_layout()
    p = os.path.join(OUTPUT_DIR, 'tps_comparison.png')
    fig.savefig(p, bbox_inches='tight', facecolor='white')
    plt.close(fig)
    print(f'  -> {p}')


def plot_latency_comparison(summary):
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    fig.suptitle(
        'P95 Latency (ms) by Workload & Thread Count\n'
        'TidesDB (MariaDB 12.2.2)  vs  InnoDB (MariaDB 12.2.2)  vs  InnoDB (MySQL 9.5.0)',
        fontweight='bold')

    bw = 0.25
    x = np.arange(len(THREAD_COUNTS))

    for idx, wl in enumerate(WORKLOAD_ORDER):
        ax = axes[idx // 2][idx % 2]
        wd = summary[summary['workload'] == wl]

        for i, eng in enumerate(ENGINE_ORDER):
            vals = _get_values(wd, eng, THREAD_COUNTS, 'latency_p95_ms')
            bars = ax.bar(x + i * bw, vals, bw,
                          label=eng, color=COLORS[eng],
                          edgecolor='white', linewidth=0.5)
            for bar, v in zip(bars, vals):
                if v > 0:
                    ax.text(bar.get_x() + bar.get_width() / 2,
                            bar.get_height(), f'{v:.1f}ms',
                            ha='center', va='bottom',
                            fontsize=7, rotation=45)

        ax.set_title(WORKLOAD_LABELS[wl], fontweight='bold')
        ax.set_xlabel('Thread Count')
        ax.set_ylabel('P95 Latency (ms)')
        ax.set_xticks(x + bw)
        ax.set_xticklabels(THREAD_COUNTS)
        ax.set_yscale('log')
        ax.legend(loc='upper left', framealpha=0.9)

    plt.tight_layout()
    p = os.path.join(OUTPUT_DIR, 'p95_latency_comparison.png')
    fig.savefig(p, bbox_inches='tight', facecolor='white')
    plt.close(fig)
    print(f'  -> {p}')


def plot_scaling_efficiency(summary):
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    fig.suptitle(
        'Scaling Efficiency (Normalised to 1-Thread Performance)\n'
        'TidesDB (MariaDB 12.2.2)  vs  InnoDB (MariaDB 12.2.2)  vs  InnoDB (MySQL 9.5.0)',
        fontweight='bold')

    for idx, wl in enumerate(WORKLOAD_ORDER):
        ax = axes[idx // 2][idx % 2]
        wd = summary[summary['workload'] == wl]

        for eng in ENGINE_ORDER:
            ed = wd[wd['source'] == eng].sort_values('threads')
            if ed.empty:
                continue
            base = ed[ed['threads'] == 1]['avg_tps'].values
            if len(base) == 0 or base[0] == 0:
                continue
            speedup = ed['avg_tps'].values / base[0]
            ax.plot(ed['threads'].values, speedup, marker='o',
                    label=eng, color=COLORS[eng], linewidth=2, markersize=6)

        ax.plot(THREAD_COUNTS, THREAD_COUNTS, '--',
                color='gray', alpha=0.5, label='Ideal Linear', linewidth=1)

        ax.set_title(WORKLOAD_LABELS[wl], fontweight='bold')
        ax.set_xlabel('Thread Count')
        ax.set_ylabel('Speedup (x)')
        ax.set_xticks(THREAD_COUNTS)
        ax.legend(loc='upper left', framealpha=0.9)

    plt.tight_layout()
    p = os.path.join(OUTPUT_DIR, 'scaling_efficiency.png')
    fig.savefig(p, bbox_inches='tight', facecolor='white')
    plt.close(fig)
    print(f'  -> {p}')


def plot_tps_over_time(detail):
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    fig.suptitle(
        'TPS Over Time (32 Threads)\n'
        'TidesDB (MariaDB 12.2.2)  vs  InnoDB (MariaDB 12.2.2)  vs  InnoDB (MySQL 9.5.0)',
        fontweight='bold')

    for idx, wl in enumerate(WORKLOAD_ORDER):
        ax = axes[idx // 2][idx % 2]
        wd = detail[(detail['workload'] == wl) & (detail['threads'] == 32)]

        for eng in ENGINE_ORDER:
            ed = wd[wd['source'] == eng].sort_values('time_s')
            if ed.empty:
                continue
            ax.plot(ed['time_s'], ed['tps'],
                    label=eng, color=COLORS[eng],
                    linewidth=1.5, alpha=0.85)

        ax.set_title(WORKLOAD_LABELS[wl], fontweight='bold')
        ax.set_xlabel('Time (s)')
        ax.set_ylabel('TPS')
        ax.yaxis.set_major_formatter(ticker.FuncFormatter(fmt))
        ax.legend(loc='best', framealpha=0.9)

    plt.tight_layout()
    p = os.path.join(OUTPUT_DIR, 'tps_over_time_32t.png')
    fig.savefig(p, bbox_inches='tight', facecolor='white')
    plt.close(fig)
    print(f'  -> {p}')


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if __name__ == '__main__':
    print('Loading data ...')
    summary = load_summary()
    detail = load_detail()

    print('Generating TPS comparison ...')
    plot_tps_comparison(summary)

    print('Generating P95 latency comparison ...')
    plot_latency_comparison(summary)

    print('Generating scaling efficiency ...')
    plot_scaling_efficiency(summary)

    print('Generating TPS-over-time (32 threads) ...')
    plot_tps_over_time(detail)

    print('Done - all plots saved to', OUTPUT_DIR)

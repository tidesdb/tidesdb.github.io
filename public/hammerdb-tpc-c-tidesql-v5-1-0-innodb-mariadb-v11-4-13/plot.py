#!/usr/bin/env python3
r"""Figures and summary table for the TPROC-C runs.

Captions are built from the run's own files; nothing about the benchmark is
hardcoded. Missing or incomplete inputs are refused rather than guessed.

Inputs (in --dir):
  run.json        mariadb_version, warehouses, rampup_min, duration_min,
                  isolation, durability, host   (required)
  results.csv     engine,phase,vu,iter,nopm,tpm,neword_avg_ms,neword_p50_ms,
                  neword_p95_ms,neword_p99_ms,errors,failed_vus,status
                    phase = sweep|peak, status = ok|failed|timeout
                    only ok is plotted; the rest are listed, never dropped silently
  build_times.csv engine,warehouses,build_vu,build_seconds[,bytes_on_disk]
  data/ts_<engine>_<vu>vu_<phase>_iter<n>.dat   elapsed_sec tpm

Point selection: a VU level with peak runs is the median of those, else its
single sweep run; the caption says which.

    python3 plot.py --dir /root/sqlanalysis/run3000
"""
import argparse, csv, json, os, sys, warnings
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib as mpl
import matplotlib.pyplot as plt
import matplotlib.hatch as mhatch
from matplotlib.path import Path
from matplotlib.ticker import FuncFormatter, LogLocator, NullFormatter, NullLocator

warnings.filterwarnings("ignore", message=r".*hatch must consist of.*")


class WaveHatch(mhatch.HatchPatternBase):
    """Sinusoidal 'tide' hatch, triggered by 'w' in a hatch string."""
    def __init__(self, hatch, density):
        self.num_rows = hatch.count("w") * int(density)
        self.steps = 24
        self.num_vertices = self.num_rows * (self.steps + 1) if self.num_rows else 0

    def set_vertices_and_codes(self, vertices, codes):
        if not self.num_rows:
            return
        xs = np.linspace(0.0, 1.0, self.steps + 1)
        k = 0
        for row in range(self.num_rows):
            y0 = (row + 0.5) / self.num_rows
            ys = y0 + (0.36 / self.num_rows) * np.sin(4.0 * np.pi * xs)
            for j in range(self.steps + 1):
                vertices[k] = (xs[j], ys[j])
                codes[k] = Path.MOVETO if j == 0 else Path.LINETO
                k += 1


mhatch._hatch_types.append(WaveHatch)

mpl.rcParams.update({
    "figure.dpi": 120, "savefig.dpi": 300, "savefig.bbox": "tight",
    "font.family": "serif", "font.serif": ["STIXGeneral", "DejaVu Serif"],
    "mathtext.fontset": "stix", "font.size": 11,
    "axes.titlesize": 12.5, "axes.labelsize": 11, "axes.titlelocation": "left",
    "axes.linewidth": 0.8, "xtick.labelsize": 9.5, "ytick.labelsize": 9.5,
    "xtick.direction": "in", "ytick.direction": "in",
    "legend.fontsize": 10, "legend.frameon": False,
    "axes.grid": True, "axes.axisbelow": True,
    "grid.color": "#9aa0a6", "grid.linewidth": 0.45, "grid.alpha": 0.35,
    "axes.spines.top": False, "axes.spines.right": False,
    "hatch.linewidth": 0.7, "pdf.fonttype": 42, "ps.fonttype": 42,
})

STYLE = {
    "tidesdb": dict(color="#163AC8", hatch="w", bar_hatch="ww", marker="o", ls="-", label="TidesDB"),
    "innodb": dict(color="#E17510", hatch="//", bar_hatch="////", marker="s", ls="--", label="InnoDB"),
}
ORDER = ["tidesdb", "innodb"]
OK = "ok"
REQ_META = ("mariadb_version", "warehouses", "rampup_min", "duration_min", "isolation",
            "durability", "host")
REQ_COLS = ("engine", "phase", "vu", "iter", "nopm", "tpm", "neword_avg_ms", "neword_p50_ms",
            "neword_p95_ms", "neword_p99_ms", "errors", "failed_vus", "status")


def style_for(k, i=0):
    return STYLE.get(k, dict(color="#3a3a3a", hatch="xx", bar_hatch="xxxx", marker="^",
                             ls=":", label=k.capitalize()))


def med(xs):
    xs = sorted(xs); n = len(xs)
    return xs[n // 2] if n % 2 else 0.5 * (xs[n // 2 - 1] + xs[n // 2])


def load_meta(d):
    p = os.path.join(d, "run.json")
    if not os.path.exists(p):
        sys.exit(f"no run.json in {d!r}: captions come from it, refusing to guess")
    m = json.load(open(p))
    miss = [k for k in REQ_META if k not in m]
    if miss:
        sys.exit(f"run.json missing {miss}")
    return m


def load_results(d):
    p = os.path.join(d, "results.csv")
    if not os.path.exists(p):
        sys.exit(f"no results.csv in {d!r}")
    data = {}
    with open(p) as f:
        rd = csv.DictReader(f)
        miss = [c for c in REQ_COLS if c not in (rd.fieldnames or [])]
        if miss:
            sys.exit(f"results.csv missing columns {miss}")
        for r in rd:
            k = r["engine"].strip().lower()
            e = data.setdefault(k, {"label": r["engine"].strip(), "runs": []})
            e["runs"].append(dict(phase=r["phase"].strip(), vu=int(r["vu"]), iter=int(r["iter"]),
                                  status=r["status"].strip(), nopm=float(r["nopm"]),
                                  tpm=float(r["tpm"]), avg=float(r["neword_avg_ms"]),
                                  p50=float(r["neword_p50_ms"]), p95=float(r["neword_p95_ms"]),
                                  p99=float(r["neword_p99_ms"]), errors=int(r["errors"]),
                                  failed_vus=int(r["failed_vus"])))
    return data


def points(e):
    out = {}
    for vu in sorted({r["vu"] for r in e["runs"]}):
        ok = [r for r in e["runs"] if r["vu"] == vu and r["status"] == OK]
        use = [r for r in ok if r["phase"] == "peak"] or [r for r in ok if r["phase"] == "sweep"]
        if use:
            out[vu] = use
    return out


def report_excluded(data):
    bad = [(e["label"], r) for e in data.values() for r in e["runs"] if r["status"] != OK]
    for lab, r in bad:
        print(f"    EXCLUDED {lab:8} {r['vu']:4} VU {r['phase']:5} iter {r['iter']}: {r['status']}"
              f"  failed_vus={r['failed_vus']} errors={r['errors']}")
    return bad


def order(data):
    return [k for k in ORDER if k in data] + [k for k in data if k not in ORDER]


def repeats_caption(data):
    ns = sorted({len(v) for e in data.values() for v in points(e).values()})
    if ns == [1]:
        return "single run per VU level"
    peak = sorted({len(v) for e in data.values() for vu, v in points(e).items()
                   if any(r["phase"] == "peak" for r in v)})
    if peak and 1 in ns:
        return f"1 run per VU level, median of {max(peak)} at the peak"
    return f"median of {ns[-1]}"


def subtitle(meta, data):
    l1 = [f"MariaDB {meta['mariadb_version']}",
          f"HammerDB TPROC-C, {int(meta['warehouses']):,} WH",
          meta["isolation"], meta["durability"]]
    l2 = [f"{meta['rampup_min']:g} min rampup / {meta['duration_min']:g} min measure",
          repeats_caption(data)]
    return r" $\cdot$ ".join(l1) + "\n" + r" $\cdot$ ".join(l2)


def thousands(x, _):
    return f"{x/1000:.0f}k" if x >= 1000 else f"{x:.0f}"


def millis(x, _):
    return f"{x:.0f}" if x >= 10 else (f"{x:.1f}" if x >= 1 else f"{x:.2f}")


def latency_yaxis(ax, vals):
    """Log only when the data spans a decade; below that the decade ticks fall
    outside the view and the axis comes out with no labels at all."""
    pos = [v for v in vals if v > 0]
    if pos and max(pos) / min(pos) >= 10:
        ax.set_yscale("log")
        ax.yaxis.set_major_locator(LogLocator(base=10, subs=(1.0, 2.0, 5.0), numticks=15))
        ax.yaxis.set_minor_locator(LogLocator(base=10, subs=(1.5, 3, 4, 6, 7, 8, 9), numticks=15))
        ax.yaxis.set_minor_formatter(NullFormatter())
        ax.yaxis.set_major_formatter(FuncFormatter(millis))
    else:
        ax.set_ylim(bottom=0)


def vu_axis(ax, vus):
    ax.set_xscale("log", base=2); ax.set_xticks(vus)
    ax.get_xaxis().set_major_formatter(FuncFormatter(lambda v, _: f"{int(round(v))}"))
    ax.xaxis.set_minor_locator(NullLocator())   # x only: y minors may be the only labels
    ax.set_xlabel("Virtual users (concurrency)")
    ax.set_xlim(min(vus) / 1.3, max(vus) * 1.3)


def titleblock(ax, title, sub):
    ax.set_title(title, pad=28, fontweight="bold")
    ax.annotate(sub, xy=(0, 1.012), xycoords="axes fraction", va="bottom",
                fontsize=7.0, color="#5f6368", annotation_clip=False, linespacing=1.4)


def save(fig, outdir, name):
    fd = os.path.join(outdir, "figures"); os.makedirs(fd, exist_ok=True)
    for ext in ("pdf", "png", "svg"):
        fig.savefig(os.path.join(fd, f"{name}.{ext}"))
    plt.close(fig)
    print(f"    figures/{name}.{{pdf,png,svg}}")


def fig_metric(data, outdir, sub, metric, ylabel, title, name, latency=False):
    fig, ax = plt.subplots(figsize=(6.4, 4.2))
    allvus = sorted({vu for k in data for vu in points(data[k])})
    allvals = []
    for i, k in enumerate(order(data)):
        st = style_for(k, i); pts = points(data[k]); vus = sorted(pts)
        if not vus:
            continue
        vals = {v: [r[metric] for r in pts[v]] for v in vus}
        allvals += [x for v in vus for x in vals[v]]
        if any(len(vals[v]) > 1 for v in vus):
            lo = [min(vals[v]) for v in vus]; hi = [max(vals[v]) for v in vus]
            ax.fill_between(vus, lo, hi, facecolor=st["color"], alpha=0.10, lw=0, zorder=1)
            ax.fill_between(vus, lo, hi, facecolor="none", edgecolor=st["color"], alpha=0.45,
                            hatch=st["hatch"], lw=0.0, zorder=1)
            for v in vus:
                if len(vals[v]) > 1:
                    ax.plot([v] * len(vals[v]), vals[v], st["marker"], color=st["color"],
                            ms=3.2, alpha=0.45, mew=0, zorder=2)
        ax.plot(vus, [med(vals[v]) for v in vus], st["ls"], color=st["color"], lw=2.0,
                marker=st["marker"], ms=6, mec="white", mew=1.0, label=st["label"], zorder=3)
    if latency:
        latency_yaxis(ax, allvals)
    else:
        ax.set_ylim(bottom=0); ax.yaxis.set_major_formatter(FuncFormatter(thousands))
    ax.set_ylabel(ylabel); vu_axis(ax, allvus); titleblock(ax, title, sub)
    ax.legend(loc="best"); save(fig, outdir, name)


def fig_errors(data, outdir, sub, meta):
    fig, ax = plt.subplots(figsize=(6.4, 4.2))
    dur = float(meta["duration_min"]) + float(meta["rampup_min"])
    allvus = sorted({vu for k in data for vu in points(data[k])})
    drew = False
    for i, k in enumerate(order(data)):
        st = style_for(k, i); pts = points(data[k]); vus = sorted(pts)
        if not vus:
            continue
        y = [med([r["errors"] for r in pts[v]]) / dur for v in vus]
        ax.plot(vus, y, st["ls"], color=st["color"], lw=2.0, marker=st["marker"], ms=6,
                mec="white", mew=1.0, label=st["label"], zorder=3)
        drew = drew or any(y)
    ax.set_ylim(bottom=0)
    if not drew:
        ax.text(0.5, 0.5, "no transaction errors recorded", transform=ax.transAxes,
                ha="center", va="center", color="#5f6368")
    ax.set_ylabel("Transaction errors per minute\n(rampup + measure window)")
    vu_axis(ax, allvus); titleblock(ax, "Aborted transactions vs concurrency", sub)
    ax.legend(loc="best"); save(fig, outdir, "errors_vs_vu")


def fig_peak(data, outdir, sub):
    keys = [k for k in order(data) if points(data[k])]
    if not keys:
        return
    labels, peaks, at, errs, cols, hats = [], [], [], [], [], []
    for i, k in enumerate(keys):
        st = style_for(k, i); pts = points(data[k])
        pv = max(pts, key=lambda v: med([r["nopm"] for r in pts[v]]))
        vals = [r["nopm"] for r in pts[pv]]; m = med(vals)
        labels.append(st["label"]); peaks.append(m); at.append((pv, len(vals)))
        errs.append([[m - min(vals)], [max(vals) - m]]); cols.append(st["color"]); hats.append(st["bar_hatch"])
    base = min(peaks)
    fig, ax = plt.subplots(figsize=(5.6, 4.4)); xs = np.arange(len(keys))
    bars = ax.bar(xs, peaks, width=0.62, color="white", edgecolor=cols, lw=1.4, zorder=2)
    for b, c, h in zip(bars, cols, hats):
        b.set_hatch(h); b.set_edgecolor(c)
    ax.bar(xs, peaks, width=0.62, color=cols, alpha=0.12, lw=0, zorder=1)
    pad = max(peaks) * 0.015
    for x, m, er in zip(xs, peaks, errs):
        if er[0][0] or er[1][0]:
            ax.errorbar(x, m, yerr=er, fmt="none", ecolor="#333", elinewidth=1.0, capsize=4, zorder=4)
        ax.text(x, m + er[1][0] + pad, f"{m/1000:.0f}k\n{m/base:.2f}$\\times$", ha="center",
                va="bottom", fontsize=10, fontweight="bold")
    ax.set_xticks(xs)
    ax.set_xticklabels([f"{l}\n@ {vu} VU (n={n})" for l, (vu, n) in zip(labels, at)])
    ax.yaxis.set_major_formatter(FuncFormatter(thousands))
    ax.set_ylabel("Peak NOPM (New Orders / minute)")
    ax.set_ylim(top=max(peaks) * 1.25)
    titleblock(ax, "Peak TPROC-C throughput", sub); save(fig, outdir, "peak_nopm")


def fig_build(outdir, sub):
    p = os.path.join(outdir, "build_times.csv")
    if not os.path.exists(p):
        return
    rows = {r["engine"].strip().lower(): r for r in csv.DictReader(open(p))}
    keys = [k for k in ORDER if k in rows] + [k for k in rows if k not in ORDER]
    if not keys:
        return
    vals = [float(rows[k]["build_seconds"]) / 60 for k in keys]
    base = min(vals); wh = int(rows[keys[0]]["warehouses"])
    fig, ax = plt.subplots(figsize=(5.6, 4.4)); xs = np.arange(len(keys))
    cols = [style_for(k, i)["color"] for i, k in enumerate(keys)]
    bars = ax.bar(xs, vals, width=0.62, color="white", edgecolor=cols, lw=1.4, zorder=2)
    for b, c, k, i in zip(bars, cols, keys, range(len(keys))):
        b.set_hatch(style_for(k, i)["bar_hatch"]); b.set_edgecolor(c)
    ax.bar(xs, vals, width=0.62, color=cols, alpha=0.12, lw=0, zorder=1)
    for x, v in zip(xs, vals):
        ax.text(x, v, f"{v:.0f}m\n{v/base:.2f}$\\times$", ha="center", va="bottom",
                fontsize=10, fontweight="bold")
    ax.set_xticks(xs); ax.set_xticklabels([style_for(k, i)["label"] for i, k in enumerate(keys)])
    ax.set_ylabel("Schema build time (minutes, lower is better)")
    ax.set_ylim(top=max(vals) * 1.25)
    titleblock(ax, f"Schema build -- {wh:,} warehouses", sub); save(fig, outdir, "build_time")


def ts_file(d, key, r):
    f = os.path.join(d, "data", f"ts_{key}_{r['vu']}vu_{r['phase']}_iter{r['iter']}.dat")
    return f if os.path.exists(f) else None


def read_ts(f):
    t, y = [], []
    for line in open(f):
        line = line.strip()
        if line and not line.startswith("#"):
            a, b = line.split()[:2]
            t.append(float(a) / 60.0); y.append(float(b))
    return t, y


def smooth(t, y, meta, seconds=10):
    """1 s samples are too spiky to read; a rolling median over ~10 s keeps the
    dips (which are real and interesting) and drops the per-sample jitter."""
    iv = float(meta.get("sample_interval_s", 1)) or 1.0
    w = max(1, int(round(seconds / iv)))
    if w < 2 or len(y) < w:
        return t, y
    out = [float(np.median(y[max(0, i - w + 1):i + 1])) for i in range(len(y))]
    return t, out


def representative(runs):
    m = med([r["nopm"] for r in runs])
    return min(runs, key=lambda r: abs(r["nopm"] - m))


def shade_rampup(ax, meta):
    rm = float(meta["rampup_min"])
    ax.axvspan(0, rm, color="#9aa0a6", alpha=0.12, lw=0)
    ax.text(rm / 2, ax.get_ylim()[1] * 0.03, "rampup", ha="center", va="bottom",
            fontsize=8, color="#5f6368")


def fig_timeline(data, outdir, sub, meta, key):
    st = style_for(key); pts = points(data[key]); series = []
    for vu in sorted(pts):
        f = ts_file(outdir, key, representative(pts[vu]))
        if f:
            series.append((vu, *read_ts(f)))
    if not series:
        return
    fig, ax = plt.subplots(figsize=(7.0, 4.2)); n = len(series)
    base = np.array(mpl.colors.to_rgb(st["color"]))
    for i, (vu, t, y) in enumerate(series):
        f = 0.30 + 0.70 * (i / max(1, n - 1))
        c = tuple(1 - f * (1 - base))
        ts, ys = smooth(t, y, meta)
        ax.plot(t, y, color=c, lw=0.5, alpha=0.18, zorder=1)
        ax.plot(ts, ys, color=c, lw=1.4, label=f"{vu} VU", zorder=3)
    ax.set_ylim(bottom=0); shade_rampup(ax, meta)
    ax.yaxis.set_major_formatter(FuncFormatter(thousands))
    ax.set_xlabel("Elapsed time (minutes)")
    ax.set_ylabel(f"TPM ({meta.get('sample_interval_s', 1)} s samples,\n10 s rolling median)")
    titleblock(ax, f"{st['label']}: throughput over time, per VU level", sub)
    ax.legend(loc="best", ncol=2); save(fig, outdir, f"timeline_{key}")


def fig_timeline_compare(data, outdir, sub, meta):
    keys = [k for k in order(data) if points(data[k])]
    if not keys:
        return
    common = set.intersection(*[set(points(data[k])) for k in keys])
    if not common:
        return
    vu = max(common, key=lambda v: sum(med([r["nopm"] for r in points(data[k])[v]]) for k in keys))
    fig, ax = plt.subplots(figsize=(7.2, 4.2)); drew = False
    for i, k in enumerate(keys):
        st = style_for(k, i)
        f = ts_file(outdir, k, representative(points(data[k])[vu]))
        if not f:
            continue
        t, y = read_ts(f); drew = True
        ts, ys = smooth(t, y, meta)
        ax.plot(t, y, color=st["color"], lw=0.5, alpha=0.15, zorder=1)
        ax.plot(ts, ys, st["ls"], color=st["color"], lw=1.8,
                label=f"{st['label']} ({vu} VU)", zorder=3)
    if not drew:
        plt.close(fig); return
    ax.set_ylim(bottom=0); shade_rampup(ax, meta)
    ax.yaxis.set_major_formatter(FuncFormatter(thousands))
    ax.set_xlabel("Elapsed time (minutes)")
    ax.set_ylabel(f"TPM ({meta.get('sample_interval_s', 1)} s samples,\n10 s rolling median)")
    titleblock(ax, f"Throughput over time at {vu} VU", sub)
    ax.legend(loc="best"); save(fig, outdir, "throughput_over_time")


def write_summary(data, outdir, meta):
    keys = order(data)
    vus = sorted({vu for k in keys for vu in points(data[k])})
    dur = float(meta["duration_min"]) + float(meta["rampup_min"])
    head = "| VU | " + " | ".join(f"{data[k]['label']} NOPM | p99 ms | err/min" for k in keys) + " |"
    lines = [head, "|---:|" + "---:|" * (3 * len(keys))]
    for v in vus:
        cells = []
        for k in keys:
            p = points(data[k]).get(v)
            if not p:
                cells += ["--", "--", "--"]; continue
            n = len(p)
            cells += [f"{med([r['nopm'] for r in p]):,.0f}" + (f" (n={n})" if n > 1 else ""),
                      f"{med([r['p99'] for r in p]):.1f}",
                      f"{med([r['errors'] for r in p]) / dur:.1f}"]
        lines.append(f"| {v} | " + " | ".join(cells) + " |")
    open(os.path.join(outdir, "summary.md"), "w").write("\n".join(lines) + "\n")
    print("    summary.md")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.environ.get("OUTDIR", "."))
    d = ap.parse_args().dir
    meta = load_meta(d); data = load_results(d)
    print("engines:", ", ".join(data[k]["label"] for k in order(data)))
    report_excluded(data)
    sub = subtitle(meta, data)
    print("caption:", sub.replace(r" $\cdot$ ", " | ").replace("\n", " / "))
    fig_metric(data, d, sub, "nopm", "NOPM (New Orders / minute)",
               "TPROC-C throughput vs concurrency", "nopm_vs_vu")
    fig_metric(data, d, sub, "tpm", "MariaDB TPM (commits + rollbacks / min)",
               "Transaction rate vs concurrency", "tpm_vs_vu")
    fig_metric(data, d, sub, "p99", "New-Order p99 latency (ms)",
               "New-Order tail latency vs concurrency", "neworder_p99_vs_vu", latency=True)
    fig_metric(data, d, sub, "p50", "New-Order p50 latency (ms)",
               "New-Order median latency vs concurrency", "neworder_p50_vs_vu", latency=True)
    fig_errors(data, d, sub, meta)
    fig_peak(data, d, sub)
    fig_build(d, sub)
    for k in order(data):
        fig_timeline(data, d, sub, meta, k)
    fig_timeline_compare(data, d, sub, meta)
    write_summary(data, d, meta)
    print("done ->", os.path.join(d, "figures"))


if __name__ == "__main__":
    main()

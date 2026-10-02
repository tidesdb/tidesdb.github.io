#!/usr/bin/env python3
"""Bytes written to the device per New-Order transaction, per run.

Throughput says how much work got done; this says what it cost. Both engines
are measured from their own accounting, taken before and after each run:

  TidesDB   SHOW ENGINE TIDESDB STATUS, "IO Device Writes": sstable + wal + vlog
            bytes. These are the engine's own byte counters.
  InnoDB    SHOW ENGINE INNODB STATUS:
              redo  = log sequence number delta
              data  = (pages written delta) * innodb_page_size
              dblwr = doublewrite pages, counted once more since every page
                      written passes through it

Both therefore count redo/WAL plus data. Neither counts filesystem metadata or
device write amplification below the engine.

    efficiency.py <rundir>            -> table + efficiency.csv
"""
import csv, glob, os, re, sys

PAGE = 16384


def num(pat, text, grp=1, cast=int):
    m = re.search(pat, text)
    return cast(m.group(grp)) if m else None


def tidesdb_bytes(f):
    """sstable + wal + vlog bytes from the IO Device Writes block."""
    if not os.path.exists(f):
        return None
    t = open(f, errors="replace").read()
    tot = 0
    for dev in ("sstable", "wal", "vlog"):
        v = num(rf"{dev}: \d+ writes, (\d+) bytes", t)
        if v is None:
            return None
        tot += v
    return tot


def innodb_bytes(f):
    if not os.path.exists(f):
        return None
    t = open(f, errors="replace").read()
    lsn = num(r"Log sequence number\s+(\d+)", t)
    written = num(r"Pages read \d+, created \d+, written (\d+)", t)
    if lsn is None or written is None:
        return None
    return {"lsn": lsn, "pages": written}


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "."
    rows = list(csv.DictReader(open(os.path.join(d, "results.csv"))))
    meta_dur = None
    try:
        import json
        m = json.load(open(os.path.join(d, "run.json")))
        meta_dur = float(m["duration_min"]) + float(m["rampup_min"])
    except Exception:
        meta_dur = None
    out = [("engine", "phase", "vu", "iter", "nopm", "new_orders", "gb_written", "bytes_per_neworder")]
    print(f"  {'engine':9} {'vu':>4} {'phase':6} {'NOPM':>9} {'GB written':>11} {'bytes/New-Order':>17}")
    for r in rows:
        if r["status"] != "ok":
            continue
        e, vu, ph, it = r["engine"].lower(), r["vu"], r["phase"], r["iter"]
        tag = f"{e}-{vu}vu-{ph}-{it}"
        b4 = os.path.join(d, "logs", f"status-{tag}-before.txt")
        af = os.path.join(d, "logs", f"status-{tag}-after.txt")
        if e == "tidesdb":
            a, b = tidesdb_bytes(b4), tidesdb_bytes(af)
            total = (b - a) if (a is not None and b is not None) else None
        else:
            a, b = innodb_bytes(b4), innodb_bytes(af)
            total = ((b["lsn"] - a["lsn"]) + (b["pages"] - a["pages"]) * PAGE * 2) \
                if (a and b) else None   # x2: every page also goes through doublewrite
        if total is None or total < 0:
            continue
        # new orders completed in the measured window; NOPM is per minute and the
        # engine counters cover rampup + measure, so use the full window
        window = meta_dur or 30.0
        new_orders = float(r["nopm"]) * window
        print(f"  {r['engine']:9} {vu:>4} {ph:6} {float(r['nopm']):9,.0f} {total/1e9:11,.1f} "
              f"{total/new_orders:17,.0f}")
        out.append((r["engine"], ph, vu, it, r["nopm"], f"{new_orders:.0f}",
                    f"{total/1e9:.2f}", f"{total/new_orders:.0f}"))
    with open(os.path.join(d, "efficiency.csv"), "w", newline="") as f:
        csv.writer(f).writerows(out)
    print(f"\n  wrote {os.path.join(d, 'efficiency.csv')}")


if __name__ == "__main__":
    main()

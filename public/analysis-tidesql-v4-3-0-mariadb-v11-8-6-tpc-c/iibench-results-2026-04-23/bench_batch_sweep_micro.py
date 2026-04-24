#!/usr/bin/env python3
"""Micro sweep at 100, 250 to confirm 500 is the floor."""
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from bench_batch_sweep import (  # noqa: E402
    HEADER, HEADER_BAK, run_config,
    stop_mariadbd, rebuild_plugin, start_mariadbd,
)


def main():
    if not os.path.exists(HEADER_BAK):
        shutil.copy(HEADER, HEADER_BAK)
    out = os.path.join(HERE, "sweep-results-micro.csv")
    try:
        with open(out, "w") as logf:
            print("label,bulk_ops,idx_batch,phase,seconds,peak_rss_kb", file=logf)
            for bulk in [100, 250]:
                run_config(f"Au_bulk{bulk}", bulk, 50_000, ["bulk"], logf)
            for idxb in [100, 250]:
                run_config(f"Bu_idx{idxb}", 50_000, idxb, ["idx"], logf)
    finally:
        shutil.copy(HEADER_BAK, HEADER)
        stop_mariadbd()
        rebuild_plugin(tag="restore_micro")
        start_mariadbd()
        print("[bench] restored header to baseline, mariadbd restarted")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Follow-up sweep at the low end of the batch constants.
Uses the same harness as bench_batch_sweep.py."""
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from bench_batch_sweep import (  # noqa: E402
    HEADER, HEADER_BAK, RESULT_FILE, run_config,
    stop_mariadbd, rebuild_plugin, start_mariadbd,
)


def main():
    if not os.path.exists(HEADER_BAK):
        shutil.copy(HEADER, HEADER_BAK)
    small_result = os.path.join(HERE, "sweep-results-small.csv")
    try:
        with open(small_result, "w") as logf:
            print("label,bulk_ops,idx_batch,phase,seconds,peak_rss_kb", file=logf)
            # Sweep A': bulk DML at the low end.
            for bulk in [5_000, 10_000, 25_000]:
                run_config(f"Asm_bulk{bulk}", bulk, 50_000, ["bulk"], logf)
            # Sweep B': ADD INDEX at the low end.
            for idxb in [5_000, 10_000, 25_000]:
                run_config(f"Bsm_idx{idxb}", 50_000, idxb, ["idx"], logf)
    finally:
        shutil.copy(HEADER_BAK, HEADER)
        stop_mariadbd()
        rebuild_plugin(tag="restore_small")
        start_mariadbd()
        print("[bench] restored header to baseline, mariadbd restarted")


if __name__ == "__main__":
    main()

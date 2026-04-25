#!/usr/bin/env python3
"""
Sweep TIDESDB_BULK_INSERT_BATCH_OPS and TIDESDB_INDEX_BUILD_BATCH across
a few values, measure bulk-DML and ADD INDEX wall-clock + peak RSS each.

Assumes libtidesdb with tidesdb_txn_single_delete is already installed at
/usr/local/lib and mariadbd is configured. Uses the bench my.cnf. Rebuilds
the plugin per sweep point via install.sh --rebuild-plugin.
"""
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TIDESQL_SRC = "/home/agpmastersystem/tidesql"
HEADER = os.path.join(TIDESQL_SRC, "tidesdb/ha_tidesdb.h")
HEADER_BAK = os.path.join(HERE, "ha_tidesdb.h.orig")

MARIADB_BIN = "/media/agpmastersystem/c794105c-0cd9-4be9-8369-ee6d6e707d68/home/bench/mariadb/bin"
MYSOCK = "/tmp/mariadb.sock"
MYCNF = "/media/agpmastersystem/c794105c-0cd9-4be9-8369-ee6d6e707d68/home/bench/mariadb/my.cnf"
BUILD_DIR = "/media/agpmastersystem/c794105c-0cd9-4be9-8369-ee6d6e707d68/home/bench/tidesql-build"

DB = "ib"
N_ROWS = 1_000_000

REBUILD_LOG = os.path.join(HERE, "sweep-rebuild.log")
RESULT_FILE = os.path.join(HERE, "sweep-results.csv")


def sh(cmd, check=True, capture=False):
    res = subprocess.run(cmd, shell=True, check=check,
                         capture_output=capture, text=True)
    return res


def mariadb(sql, db=DB, capture=False):
    args = [f"{MARIADB_BIN}/mariadb", "-S", MYSOCK, "-u", "agpmastersystem",
            "-B", "-N", db, "-e", sql]
    if capture:
        return subprocess.run(args, capture_output=True, text=True, check=True).stdout
    subprocess.run(args, check=True)


def mariadbd_pid():
    out = subprocess.run(
        ["pgrep", "-f", "bench/mariadb/bin/mariadbd "],
        capture_output=True, text=True
    ).stdout.strip().splitlines()
    return int(out[0]) if out else None


def stop_mariadbd():
    subprocess.run([f"{MARIADB_BIN}/mariadb-admin", "-S", MYSOCK,
                    "-u", "agpmastersystem", "shutdown"],
                   check=False)
    for _ in range(30):
        if not mariadbd_pid():
            return
        time.sleep(0.5)
    raise RuntimeError("mariadbd did not shut down")


def start_mariadbd():
    subprocess.Popen([f"{MARIADB_BIN}/mariadbd-safe", f"--defaults-file={MYCNF}"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    for _ in range(60):
        time.sleep(0.5)
        try:
            mariadb("SELECT 1", db="mysql", capture=True)
            return
        except Exception:
            pass
    raise RuntimeError("mariadbd did not start")


def patch_header(bulk_ops, idx_batch):
    """Rewrite the two batch constants in ha_tidesdb.h. Idempotent - always starts
    from the pristine header backup."""
    with open(HEADER_BAK) as f:
        src = f.read()
    src = re.sub(
        r"static constexpr ha_rows TIDESDB_INDEX_BUILD_BATCH\s*=\s*\d+;",
        f"static constexpr ha_rows TIDESDB_INDEX_BUILD_BATCH = {idx_batch};",
        src, count=1,
    )
    src = re.sub(
        r"static constexpr ha_rows TIDESDB_BULK_INSERT_BATCH_OPS\s*=\s*\d+;",
        f"static constexpr ha_rows TIDESDB_BULK_INSERT_BATCH_OPS = {bulk_ops};",
        src, count=1,
    )
    with open(HEADER, "w") as f:
        f.write(src)


def rebuild_plugin(tag="last"):
    cmd = (
        f"cd {TIDESQL_SRC} && "
        f"./install.sh --rebuild-plugin "
        f"--tidesdb-prefix /usr/local "
        f"--mariadb-prefix {os.path.dirname(MARIADB_BIN)} "
        f"--build-dir {BUILD_DIR}"
    )
    logpath = os.path.join(HERE, f"sweep-rebuild-{tag}.log")
    with open(logpath, "w") as f:
        subprocess.run(cmd, shell=True, check=True, stdout=f, stderr=subprocess.STDOUT)


def sample_rss(pid, stop_event, samples):
    while not stop_event.is_set():
        try:
            with open(f"/proc/{pid}/status") as f:
                for line in f:
                    if line.startswith("VmRSS:"):
                        samples.append(int(line.split()[1]))
                        break
        except FileNotFoundError:
            return
        stop_event.wait(0.2)


def timed(fn_sql):
    """Run SQL, return (seconds, peak_rss_kb)."""
    pid = mariadbd_pid()
    samples = []
    stop = threading.Event()
    t = threading.Thread(target=sample_rss, args=(pid, stop, samples), daemon=True)
    t.start()
    t0 = time.time()
    mariadb(fn_sql)
    dur = time.time() - t0
    stop.set()
    t.join(timeout=1.0)
    return dur, max(samples) if samples else 0


def ensure_db():
    mariadb(f"CREATE DATABASE IF NOT EXISTS {DB}", db="mysql")


def _seq_select(n):
    """Produce the 5-column SELECT that generates n rows via the SEQUENCE engine."""
    return (
        f"SELECT seq, seq % 10000, seq % 100, (seq * 2) % 1000000, CONCAT('row', seq) "
        f"FROM seq_1_to_{n}"
    )


def bench_bulk_dml():
    mariadb("DROP TABLE IF EXISTS target_bulk")
    mariadb(
        "CREATE TABLE target_bulk ("
        "  pk BIGINT PRIMARY KEY, "
        "  c0 INT, c1 INT, c2 INT, data VARCHAR(32), "
        "  KEY (c0), KEY (c1), KEY (c2)"
        ") ENGINE=TIDESDB"
    )
    return timed(
        f"INSERT INTO target_bulk (pk, c0, c1, c2, data) {_seq_select(N_ROWS)}"
    )


def bench_add_index():
    mariadb("DROP TABLE IF EXISTS target_idx")
    mariadb(
        "CREATE TABLE target_idx ("
        "  pk BIGINT PRIMARY KEY, "
        "  c0 INT, c1 INT, c2 INT, data VARCHAR(32)"
        ") ENGINE=TIDESDB"
    )
    mariadb(f"INSERT INTO target_idx (pk, c0, c1, c2, data) {_seq_select(N_ROWS)}")
    return timed(
        "ALTER TABLE target_idx "
        "ADD INDEX k0 (c0), ADD INDEX k1 (c1), ADD INDEX k2 (c2)"
    )


def run_config(label, bulk_ops, idx_batch, phases, logf):
    stop_mariadbd()
    patch_header(bulk_ops, idx_batch)
    rebuild_plugin(tag=label)
    start_mariadbd()
    ensure_db()
    for phase in phases:
        if phase == "bulk":
            dur, rss = bench_bulk_dml()
        elif phase == "idx":
            dur, rss = bench_add_index()
        row = f"{label},{bulk_ops},{idx_batch},{phase},{dur:.3f},{rss}"
        print(f"[bench] {row}", flush=True)
        print(row, file=logf, flush=True)


def main():
    if not os.path.exists(HEADER_BAK):
        shutil.copy(HEADER, HEADER_BAK)
    try:
        with open(RESULT_FILE, "w") as logf:
            print("label,bulk_ops,idx_batch,phase,seconds,peak_rss_kb", file=logf)
            # Sweep A: bulk DML. Fix index batch at current default.
            for bulk in [50_000, 250_000, 1_000_000, 5_000_000]:
                run_config(f"A_bulk{bulk}", bulk, 50_000, ["bulk"], logf)
            # Sweep B: ADD INDEX commit batch.
            for idxb in [50_000, 250_000, 500_000, 2_000_000]:
                run_config(f"B_idx{idxb}", 50_000, idxb, ["idx"], logf)
    finally:
        shutil.copy(HEADER_BAK, HEADER)
        stop_mariadbd()
        rebuild_plugin(tag="restore")
        start_mariadbd()
        print("[bench] restored header to baseline, mariadbd restarted")


if __name__ == "__main__":
    main()

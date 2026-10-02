#!/usr/bin/env python3
"""Pull one run's results out of the HammerDB jobs DB into results.csv.

    extract.py <jobs.db> <outdir> <engine> <phase> <vu> <iter> <jobid|-> <timed_out 0|1>

status: ok | failed (a VU died, or no TEST RESULT) | timeout (watchdog killed it).
Transaction errors HammerDB logs and continues past do NOT fail a run: they are
counted in `errors` and are part of the result.
"""
import collections, datetime, os, re, sqlite3, sys

HEADER = ("engine,phase,vu,iter,nopm,tpm,neword_avg_ms,neword_p50_ms,neword_p95_ms,"
          "neword_p99_ms,errors,failed_vus,status,jobid")
ERR_RE = re.compile(r"(?i)(deadlock|lock wait timeout|during commit|error)")

def main():
    db, outdir, engine, phase, vu, it, jobid, timed_out = sys.argv[1:9]
    vu, it, timed_out = int(vu), int(it), timed_out == "1"
    os.makedirs(os.path.join(outdir, "data"), exist_ok=True)
    os.makedirs(os.path.join(outdir, "logs"), exist_ok=True)
    tag = f"{engine.lower()}_{vu}vu_{phase}_iter{it}"
    nopm = tpm = 0
    lat = dict(avg=0.0, p50=0.0, p95=0.0, p99=0.0)
    errors = failed = 0
    have = False
    if jobid not in ("", "-") and os.path.exists(db):
        c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        outs = [r[0] or "" for r in c.execute("SELECT output FROM JOBOUTPUT WHERE jobid=?", (jobid,))]
        for o in outs:
            m = re.search(r"achieved (\d+) NOPM from (\d+)", o)
            if m:
                nopm, tpm, have = int(m.group(1)), int(m.group(2)), True
        failed = sum("FINISHED FAILED" in o for o in outs)
        kinds = collections.Counter()
        for o in outs:
            if "FINISHED" in o or "TEST RESULT" in o:
                continue
            if ERR_RE.search(o):
                errors += 1
                kinds[re.sub(r"\d+", "#", o.strip())[:160]] += 1
        with open(os.path.join(outdir, "logs", f"errors_{tag}.txt"), "w") as f:
            for k, n in kinds.most_common():
                f.write(f"{n:8}  {k}\n")
        row = c.execute("SELECT avg_ms,p50_ms,p95_ms,p99_ms FROM JOBTIMING "
                        "WHERE jobid=? AND procname='NEWORD' AND summary=1 LIMIT 1", (jobid,)).fetchone()
        if row:
            lat = dict(zip(("avg", "p50", "p95", "p99"), (float(x or 0) for x in row)))
        series = c.execute("SELECT counter,timestamp FROM JOBTCOUNT WHERE jobid=? AND metric='tpm' "
                           "ORDER BY timestamp", (jobid,)).fetchall()
        if series:
            fmt = "%Y-%m-%d %H:%M:%S"
            t0 = datetime.datetime.strptime(series[0][1], fmt)
            with open(os.path.join(outdir, "data", f"ts_{tag}.dat"), "w") as f:
                f.write(f"# elapsed_sec tpm   (job {jobid})\n")
                for cnt, ts in series:
                    t = datetime.datetime.strptime(ts, fmt)
                    f.write(f"{int((t - t0).total_seconds())} {cnt}\n")
    status = "timeout" if timed_out else ("failed" if failed or not have else "ok")
    path = os.path.join(outdir, "results.csv")
    new = not os.path.exists(path)
    with open(path, "a") as f:
        if new:
            f.write(HEADER + "\n")
        f.write(f"{engine},{phase},{vu},{it},{nopm},{tpm},{lat['avg']:.2f},{lat['p50']:.2f},"
                f"{lat['p95']:.2f},{lat['p99']:.2f},{errors},{failed},{status},{jobid}\n")
    print(f"{engine} {phase} {vu}VU iter{it}: status={status} nopm={nopm} tpm={tpm} "
          f"p99={lat['p99']:.2f}ms errors={errors} failed_vus={failed}")

if __name__ == "__main__":
    main()

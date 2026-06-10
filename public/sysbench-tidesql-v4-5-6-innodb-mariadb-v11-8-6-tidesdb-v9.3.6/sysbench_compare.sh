#!/usr/bin/env bash
#
# sysbench_compare.sh -- TidesDB vs InnoDB comparison harness.
#
# Sequential per engine: prepare -> warmup -> N measured runs -> drop.
# Reports the MEDIAN of N runs for TPS, QPS, p95 latency, and -- crucially for
# a fair OCC-vs-pessimistic comparison -- the rate of retriable errors that
# sysbench had to restart (1213 conflict/deadlock, 1205 lock-wait, etc).
#
# Both engines run with the same --mysql-ignore-errors list so a write-write
# conflict restarts the transaction on either engine instead of aborting the
# run. The ignored-errors/sec column shows how often that happened.
#
# Usage:
#   ./sysbench_compare.sh                 # full run, both engines, default size
#   ENGINES=tidesdb ./sysbench_compare.sh # one engine only
#   TABLE_SIZE=12000000 ./sysbench_compare.sh   # ~42GB on InnoDB
#   SKIP_PREPARE=1 ./sysbench_compare.sh  # reuse existing tables (skip load+drop)
#
set -uo pipefail

# ----------------------------- configuration -----------------------------
MDB="${MDB:-/media/agpmastersystem/c794105c-0cd9-4be9-8369-ee6d6e707d68/home/bench/mariadb}"
SOCKET="${SOCKET:-/tmp/mariadb.sock}"
DB_USER="${DB_USER:-agpmastersystem}"
DB_NAME="${DB_NAME:-sbtest}"

ENGINES="${ENGINES:-innodb tidesdb}"     # space-separated; order = run order

TABLES="${TABLES:-16}"
TABLE_SIZE="${TABLE_SIZE:-5000000}"      # rows per table. 16x5M = 80M ~= 18GB InnoDB
THREADS="${THREADS:-16}"
PREPARE_THREADS="${PREPARE_THREADS:-16}"

RUNS="${RUNS:-3}"                        # measured runs per workload (median)
RUN_TIME="${RUN_TIME:-120}"             # seconds per measured run
WARMUP_TIME="${WARMUP_TIME:-60}"        # seconds, discarded, once per engine
REPORT_INTERVAL="${REPORT_INTERVAL:-10}"
RAND_TYPE="${RAND_TYPE:-uniform}"       # uniform = spread across full dataset (disk-bound)

# Retriable / ignorable codes -- restart the transaction instead of aborting:
#   1213 deadlock / OCC conflict, 1205 lock-wait timeout (incl TidesDB backpressure),
#   1062 dup key (insert test with random ids), 1020 record changed, 2013 lost conn.
IGNORE_ERRORS="${IGNORE_ERRORS:-1213,1205,1062,1020,2013}"

# read-only first so destructive workloads do not drift the median runs
WORKLOADS="${WORKLOADS:-oltp_point_select oltp_read_write oltp_update_index oltp_update_non_index oltp_insert oltp_delete}"

SKIP_PREPARE="${SKIP_PREPARE:-0}"       # 1 = reuse tables, do not load or drop
KEEP_DATA="${KEEP_DATA:-0}"             # 1 = do not drop tables after the engine's runs

SB_SHARE="${SB_SHARE:-/usr/local/share/sysbench}"
OUTDIR="${OUTDIR:-$(dirname "$0")/results_$(date +%Y%m%d_%H%M%S)}"

# ----------------------------- helpers -----------------------------
MARIADB="${MDB}/bin/mariadb"

log()  { printf '\033[0;36m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
die()  { printf '\033[0;31m[FATAL]\033[0m %s\n' "$*" >&2; exit 1; }

sql() { "${MARIADB}" -S "${SOCKET}" -u "${DB_USER}" -N -B -e "$1"; }

# median of the numeric args (handles empty -> 0)
median() {
  [ "$#" -eq 0 ] && { echo 0; return; }
  printf '%s\n' "$@" | sort -n | awk '
    {a[NR]=$1}
    END{ if(NR==0){print 0} else if(NR%2){print a[(NR+1)/2]} else {printf "%.2f", (a[NR/2]+a[NR/2+1])/2} }'
}

sb_common=(
  --db-driver=mysql
  --mysql-socket="${SOCKET}"
  --mysql-user="${DB_USER}"
  --mysql-db="${DB_NAME}"
  --tables="${TABLES}"
  --table-size="${TABLE_SIZE}"
  --rand-type="${RAND_TYPE}"
  --mysql-ignore-errors="${IGNORE_ERRORS}"
)

# extract a per-second metric or latency from a sysbench log
# $1 = logfile, $2 = one of: tps qps p95 ignerr
parse() {
  local f="$1" what="$2"
  case "$what" in
    tps)    grep -oP 'transactions:\s+\d+\s+\(\K[0-9.]+' "$f" | head -1 ;;
    qps)    grep -oP '^\s*queries:\s+\d+\s+\(\K[0-9.]+'   "$f" | head -1 ;;
    p95)    grep -oP '95th percentile:\s+\K[0-9.]+'        "$f" | head -1 ;;
    ignerr) grep -oP 'ignored errors:\s+\d+\s+\(\K[0-9.]+' "$f" | head -1 ;;
  esac
}

# ----------------------------- preflight -----------------------------
command -v sysbench >/dev/null || die "sysbench not found in PATH"
[ -S "${SOCKET}" ] || die "no server socket at ${SOCKET} -- is mariadbd up?"
"${MARIADB}" -S "${SOCKET}" -u "${DB_USER}" -e 'SELECT 1' >/dev/null 2>&1 || die "cannot connect"
mkdir -p "${OUTDIR}"

log "results -> ${OUTDIR}"
log "engines: ${ENGINES} | tables=${TABLES} size=${TABLE_SIZE} threads=${THREADS} runs=${RUNS} time=${RUN_TIME}s"
log "ignore-errors: ${IGNORE_ERRORS}"
sql "CREATE DATABASE IF NOT EXISTS ${DB_NAME}"

SUMMARY="${OUTDIR}/summary.tsv"
printf 'engine\tworkload\tmedian_tps\tmedian_qps\tp95_ms\tign_err_per_s\n' > "${SUMMARY}"

# ----------------------------- main loop -----------------------------
for engine in ${ENGINES}; do
  log "==================== ENGINE: ${engine} ===================="

  if [ "${SKIP_PREPARE}" != "1" ]; then
    log "[${engine}] dropping any existing sbtest tables..."
    for t in $(seq 1 "${TABLES}"); do sql "DROP TABLE IF EXISTS ${DB_NAME}.sbtest${t}" 2>/dev/null; done
    log "[${engine}] preparing ${TABLES}x${TABLE_SIZE} rows (this is the 20-50GB load)..."
    sysbench "${SB_SHARE}/oltp_common.lua" "${sb_common[@]}" \
      --threads="${PREPARE_THREADS}" \
      --mysql-storage-engine="${engine}" \
      prepare 2>&1 | tee "${OUTDIR}/${engine}_prepare.log" \
      || die "[${engine}] prepare failed"
    sql "ANALYZE TABLE ${DB_NAME}.sbtest1" >/dev/null 2>&1 || true
  else
    log "[${engine}] SKIP_PREPARE=1 -- reusing existing tables"
  fi

  log "[${engine}] warmup ${WARMUP_TIME}s (discarded)..."
  sysbench "${SB_SHARE}/oltp_read_write.lua" "${sb_common[@]}" \
    --threads="${THREADS}" --time="${WARMUP_TIME}" --report-interval="${REPORT_INTERVAL}" \
    run > "${OUTDIR}/${engine}_warmup.log" 2>&1 || true

  for wl in ${WORKLOADS}; do
    log "[${engine}] workload ${wl} -- ${RUNS} runs x ${RUN_TIME}s"
    tps=(); qps=(); p95=(); ign=()
    for r in $(seq 1 "${RUNS}"); do
      rlog="${OUTDIR}/${engine}_${wl}_run${r}.log"
      sysbench "${SB_SHARE}/${wl}.lua" "${sb_common[@]}" \
        --threads="${THREADS}" --time="${RUN_TIME}" --report-interval="${REPORT_INTERVAL}" \
        run > "${rlog}" 2>&1 || log "  run ${r} returned nonzero (see ${rlog})"
      v_tps=$(parse "${rlog}" tps);    tps+=("${v_tps:-0}")
      v_qps=$(parse "${rlog}" qps);    qps+=("${v_qps:-0}")
      v_p95=$(parse "${rlog}" p95);    p95+=("${v_p95:-0}")
      v_ign=$(parse "${rlog}" ignerr); ign+=("${v_ign:-0}")
      log "  run ${r}: tps=${v_tps:-0} qps=${v_qps:-0} p95=${v_p95:-0}ms ign/s=${v_ign:-0}"
    done
    m_tps=$(median "${tps[@]}"); m_qps=$(median "${qps[@]}")
    m_p95=$(median "${p95[@]}"); m_ign=$(median "${ign[@]}")
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${engine}" "${wl}" "${m_tps}" "${m_qps}" "${m_p95}" "${m_ign}" >> "${SUMMARY}"
    log "  MEDIAN ${wl}: tps=${m_tps} qps=${m_qps} p95=${m_p95}ms ign/s=${m_ign}"
  done

  if [ "${SKIP_PREPARE}" != "1" ] && [ "${KEEP_DATA}" != "1" ]; then
    log "[${engine}] dropping tables to free disk for next engine..."
    for t in $(seq 1 "${TABLES}"); do sql "DROP TABLE IF EXISTS ${DB_NAME}.sbtest${t}"; done
  fi
done

# ----------------------------- report -----------------------------
echo
log "==================== SUMMARY (median of ${RUNS} runs) ===================="
column -t -s $'\t' "${SUMMARY}"
echo
log "raw logs + summary.tsv in ${OUTDIR}"

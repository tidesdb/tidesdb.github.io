#!/usr/bin/env bash
set -euo pipefail


# defaults (small smoke-test values)
TABLES=${TABLES:-4}
TABLE_SIZE=${TABLE_SIZE:-1000}
THREADS=${THREADS:-8}
TIME=${TIME:-10}
REPORT_INT=${REPORT_INT:-5}
SETTLE=${SETTLE:-60}
ENGINE_SELECT=${ENGINE_SELECT:-both}
PERF_RECORD=${PERF_RECORD:-0}
PERF_FREQ=${PERF_FREQ:-99}
MYSQL_USER=${MYSQL_USER:-agpmastersystem}
MYSQL_SOCKET=${MYSQL_SOCKET:-/tmp/mariadb.sock}
MYSQL_DB=${MYSQL_DB:-sbtest}
SYSBENCH_LUA=${SYSBENCH_LUA:-/usr/share/sysbench/oltp_read_write.lua}
SYSBENCH_DIR=${SYSBENCH_DIR:-/usr/share/sysbench}
WORKLOADS=${WORKLOADS:-}
PLOT_ONLY=""

if sudo -n true 2>/dev/null; then
    SUDO="sudo -n"
elif [[ $EUID -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CSV_FILE="bench_results_${TIMESTAMP}.csv"
LOG_DIR="bench_logs_${TIMESTAMP}"
mkdir -p "$LOG_DIR"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -t, --tables       NUM   Number of tables          (default: $TABLES)
  -s, --table-size   NUM   Rows per table             (default: $TABLE_SIZE)
  -T, --threads      NUM   Concurrent threads         (default: $THREADS)
  -d, --time         NUM   Duration in seconds        (default: $TIME)
  -r, --report-int   NUM   Report interval (sec)      (default: $REPORT_INT)
  -w, --settle       NUM   Post-prepare settle (sec)  (default: $SETTLE)
  -e, --engine       STR   Engine: tidesdb|rocksdb|both (default: $ENGINE_SELECT)
  -W, --workloads    LIST  Comma-separated workload names (default: single SYSBENCH_LUA)
                           e.g. oltp_read_write,oltp_read_only,oltp_write_only
                           Names are resolved under $SYSBENCH_DIR/
  -p, --perf               Enable perf record on mariadbd during run
  -F, --perf-freq    NUM   perf sampling frequency Hz  (default: $PERF_FREQ)
  -u, --user         STR   MySQL user                 (default: $MYSQL_USER)
  -S, --socket       PATH  MySQL socket               (default: $MYSQL_SOCKET)
  -D, --db           STR   Database name              (default: $MYSQL_DB)
  -P, --plot-only    FILE  Skip benchmarks, generate charts from existing CSV
  -h, --help               Show this help

Examples:
  # Quick smoke test both engines
  ./tidesdb_rocksdb_sysbench.sh

  # Run all five OLTP workloads
  ./tidesdb_rocksdb_sysbench.sh -W oltp_read_write,oltp_read_only,oltp_write_only,oltp_update_non_index,oltp_delete

  # Generate charts from a previous run
  ./tidesdb_rocksdb_sysbench.sh --plot-only bench_results_20260321_003440.csv

  # TidesDB only with perf profiling
  ./tidesdb_rocksdb_sysbench.sh -e tidesdb -s 250000 -t 8 -T 8 -d 120 -p

  # RocksDB only, big run
  ./tidesdb_rocksdb_sysbench.sh -e rocksdb -t 8 -s 500000 -T 16 -d 120

  # Both engines, skip settle for small data
  ./tidesdb_rocksdb_sysbench.sh -e both -s 1000 -w 0

  # Perf with higher sampling rate
  ./tidesdb_rocksdb_sysbench.sh -e tidesdb -p -F 999 -s 250000 -t 8 -d 60

  # Full benchmark suite via env vars
  TABLES=8 TABLE_SIZE=500000 THREADS=8 TIME=120 \\
    WORKLOADS=oltp_read_write,oltp_read_only,oltp_write_only,oltp_update_non_index,oltp_delete \\
    ./tidesdb_rocksdb_sysbench.sh
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--tables)      TABLES="$2";        shift 2 ;;
        -s|--table-size)  TABLE_SIZE="$2";     shift 2 ;;
        -T|--threads)     THREADS="$2";        shift 2 ;;
        -d|--time)        TIME="$2";           shift 2 ;;
        -r|--report-int)  REPORT_INT="$2";     shift 2 ;;
        -w|--settle)      SETTLE="$2";         shift 2 ;;
        -e|--engine)      ENGINE_SELECT="$2";  shift 2 ;;
        -W|--workloads)   WORKLOADS="$2";      shift 2 ;;
        -p|--perf)        PERF_RECORD=1;       shift ;;
        -F|--perf-freq)   PERF_FREQ="$2";      shift 2 ;;
        -u|--user)        MYSQL_USER="$2";     shift 2 ;;
        -S|--socket)      MYSQL_SOCKET="$2";   shift 2 ;;
        -D|--db)          MYSQL_DB="$2";       shift 2 ;;
        -P|--plot-only)   PLOT_ONLY="$2";      shift 2 ;;
        -h|--help)        usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# ---------- plot-only mode ----------
if [[ -n "$PLOT_ONLY" ]]; then
    if [[ ! -f "$PLOT_ONLY" ]]; then
        echo "ERROR: CSV file not found: $PLOT_ONLY"
        exit 1
    fi
    CSV_FILE="$PLOT_ONLY"
    CHART_DIR="$(dirname "$CSV_FILE")/charts_$(basename "$CSV_FILE" .csv)"
    mkdir -p "$CHART_DIR"

    echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
    echo "  PLOT-ONLY MODE"
    echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
    echo "  CSV:    $CSV_FILE"
    echo "  Charts: $CHART_DIR/"
    echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
    echo ""

    echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
    echo "  RESULTS SUMMARY"
    echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
    column -t -s',' "$CSV_FILE" 2>/dev/null || cat "$CSV_FILE"
    echo ""

    LOG_DIR="$CHART_DIR"
    # jump to chart generation (shared with normal mode)
    SKIP_BENCH=1
fi
# ---------- end plot-only setup ----------

if [[ "${SKIP_BENCH:-0}" -ne 1 ]]; then

if [[ "$PERF_RECORD" -eq 1 ]]; then
    if ! command -v perf &>/dev/null; then
        echo "ERROR: perf not found. Install with: sudo apt install linux-tools-\$(uname -r)"
        exit 1
    fi
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        echo "WARNING: sudo requires a password. Caching credentials now..."
        sudo true
    fi
    echo "Perf preflight OK (sudo: ${SUDO:-root})"
    echo ""
fi

case "${ENGINE_SELECT,,}" in
    tidesdb)   ENGINES=("TidesDB") ;;
    rocksdb)   ENGINES=("RocksDB") ;;
    both)      ENGINES=("TidesDB" "RocksDB") ;;
    *)         echo "ERROR: --engine must be tidesdb, rocksdb, or both"; exit 1 ;;
esac

# build workload list
WORKLOAD_PATHS=()
if [[ -n "$WORKLOADS" ]]; then
    IFS=',' read -ra _names <<< "$WORKLOADS"
    for name in "${_names[@]}"; do
        name="${name// /}"
        [[ "$name" != *.lua ]] && name="${name}.lua"
        if [[ "$name" == /* ]]; then
            lua_path="$name"
        else
            lua_path="${SYSBENCH_DIR}/${name}"
        fi
        if [[ ! -f "$lua_path" ]]; then
            echo "ERROR: workload not found: $lua_path"
            exit 1
        fi
        WORKLOAD_PATHS+=("$lua_path")
    done
else
    WORKLOAD_PATHS=("$SYSBENCH_LUA")
fi

WORKLOAD_NAMES=()
for p in "${WORKLOAD_PATHS[@]}"; do
    WORKLOAD_NAMES+=("$(basename "$p" .lua)")
done

find_mariadbd_pid() {
    local pid
    pid=$(pgrep -x mariadbd || pgrep -x mysqld || true)
    if [[ -z "$pid" ]]; then
        echo "WARNING: Could not find mariadbd/mysqld PID for perf" >&2
        return 1
    fi
    echo "$pid"
}

parse_results() {
    local file="$1"
    local tps qps reads writes others lat_avg lat_95 lat_max errs

    tps=$(grep "transactions:" "$file" | awk -F'[()]' '{gsub(/ per sec\./,"",$2); gsub(/ /,"",$2); print $2}')
    qps=$(grep "queries:" "$file" | head -1 | awk -F'[()]' '{gsub(/ per sec\./,"",$2); gsub(/ /,"",$2); print $2}')
    reads=$(grep "read:" "$file" | awk '{print $2}')
    writes=$(grep "write:" "$file" | awk '{print $2}')
    others=$(grep "other:" "$file" | awk '{print $2}')
    lat_avg=$(grep "avg:" "$file" | awk '{print $2}')
    lat_95=$(grep "95th percentile:" "$file" | awk '{print $3}')
    lat_max=$(grep "max:" "$file" | awk '{print $2}')
    errs=$(grep "ignored errors:" "$file" | awk -F'[(:)]' '{gsub(/ /,"",$2); print $2}')

    echo "${tps},${qps},${reads},${writes},${others},${lat_avg},${lat_95},${lat_max},${errs}"
}

cat > "$CSV_FILE" <<EOF
workload,engine,tables,table_size,threads,duration_sec,settle_sec,prepare_sec,tps,qps,reads,writes,others,lat_avg_ms,lat_p95_ms,lat_max_ms,errors_total
EOF

TOTAL_RUNS=$(( ${#WORKLOAD_PATHS[@]} * ${#ENGINES[@]} ))
TOTAL_TIME_EST=$(( TOTAL_RUNS * (TIME + SETTLE + 10) ))

echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
echo "  sysbench OLTP bench - ${ENGINE_SELECT}"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
echo "  Workload(s):  ${WORKLOAD_NAMES[*]}"
echo "  Engine(s):    ${ENGINES[*]}"
echo "  Tables:       $TABLES"
echo "  Rows/table:   $TABLE_SIZE"
echo "  Threads:      $THREADS"
echo "  Duration:     ${TIME}s"
echo "  Settle:       ${SETTLE}s (post-prepare compaction window)"
echo "  Total runs:   $TOTAL_RUNS (est ~$((TOTAL_TIME_EST / 60))m)"
echo "  Perf:         $([ "$PERF_RECORD" -eq 1 ] && echo "ON (${PERF_FREQ} Hz)" || echo "OFF")"
echo "  Socket:       $MYSQL_SOCKET"
echo "  Database:     $MYSQL_DB"
echo "  CSV output:   $CSV_FILE"
echo "  Logs:         $LOG_DIR/"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
echo ""

echo ">>> Creating database '$MYSQL_DB' if needed..."
mysql -u "$MYSQL_USER" -S "$MYSQL_SOCKET" -e "CREATE DATABASE IF NOT EXISTS $MYSQL_DB;" 2>/dev/null || true
echo ""

RUN_NUM=0
for WL_IDX in "${!WORKLOAD_PATHS[@]}"; do
    CURRENT_LUA="${WORKLOAD_PATHS[$WL_IDX]}"
    CURRENT_NAME="${WORKLOAD_NAMES[$WL_IDX]}"

    COMMON=(
        "$CURRENT_LUA"
        --db-driver=mysql
        --mysql-user="$MYSQL_USER"
        --mysql-socket="$MYSQL_SOCKET"
        --mysql-db="$MYSQL_DB"
        --tables="$TABLES"
        --table-size="$TABLE_SIZE"
    )

    echo "######################################################"
    echo "  WORKLOAD: $CURRENT_NAME  ($(( WL_IDX + 1 ))/${#WORKLOAD_PATHS[@]})"
    echo "######################################################"
    echo ""

    for ENGINE in "${ENGINES[@]}"; do
        RUN_NUM=$(( RUN_NUM + 1 ))
        LOG_PREFIX="${LOG_DIR}/${CURRENT_NAME}_${ENGINE}"
        LOG_FILE="${LOG_PREFIX}_run.log"
        PERF_DATA="${LOG_PREFIX}_perf.data"
        PERF_REPORT="${LOG_PREFIX}_perf_report.txt"
        PERF_FLAMEGRAPH_FOLDED="${LOG_PREFIX}_perf.folded"
        PERF_PID=""

        echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
        echo "  [$RUN_NUM/$TOTAL_RUNS] $CURRENT_NAME + $ENGINE"
        echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"

        echo "[$(date +%H:%M:%S)] Preparing tables with $ENGINE..."
        PREPARE_START=$(date +%s)
        sysbench "${COMMON[@]}" \
            --mysql-storage-engine="$ENGINE" \
            --threads="$THREADS" \
            prepare 2>&1 | tee "${LOG_PREFIX}_prepare.log"
        PREPARE_END=$(date +%s)
        PREPARE_ELAPSED=$(( PREPARE_END - PREPARE_START ))
        echo "[$(date +%H:%M:%S)] Prepare completed in ${PREPARE_ELAPSED}s"
        echo ""

        if [[ "$SETTLE" -gt 0 ]]; then
            echo "[$(date +%H:%M:%S)] Settling ${SETTLE}s..."
            for ((i=SETTLE; i>0; i-=10)); do
                remaining=$((i < 10 ? i : 10))
                sleep "$remaining"
                left=$((i - remaining))
                if [[ "$left" -gt 0 ]]; then
                    echo "  ... ${left}s remaining"
                fi
            done
            echo "[$(date +%H:%M:%S)] Settle complete, starting benchmark"
        fi
        echo ""

        if [[ "$PERF_RECORD" -eq 1 ]]; then
            MARIADBD_PID=$(find_mariadbd_pid) || true
            if [[ -n "$MARIADBD_PID" ]]; then
                echo "[$(date +%H:%M:%S)] Starting perf record on mariadbd (PID $MARIADBD_PID, ${PERF_FREQ} Hz)..."
                $SUDO perf record \
                    -F "$PERF_FREQ" \
                    -p "$MARIADBD_PID" \
                    -g \
                    --call-graph dwarf,16384 \
                    -o "$PERF_DATA" &
                PERF_PID=$!
                sleep 1  
                echo "[$(date +%H:%M:%S)] perf recording (background PID $PERF_PID)"
            else
                echo "[$(date +%H:%M:%S)] WARNING: Skipping perf - mariadbd PID not found"
            fi
        fi
        echo ""

        echo "[$(date +%H:%M:%S)] Running benchmark ($CURRENT_NAME + $ENGINE, ${TIME}s)..."
        sysbench "${COMMON[@]}" \
            --threads="$THREADS" \
            --time="$TIME" \
            --report-interval="$REPORT_INT" \
            --mysql-ignore-errors=1180,1213 \
            run 2>&1 | tee "$LOG_FILE"
        echo ""

        if [[ -n "$PERF_PID" ]] && kill -0 "$PERF_PID" 2>/dev/null; then
            echo "[$(date +%H:%M:%S)] Stopping perf..."
            $SUDO kill -INT "$PERF_PID"
            wait "$PERF_PID" 2>/dev/null || true

            echo "[$(date +%H:%M:%S)] Generating perf report..."

            $SUDO perf report \
                -i "$PERF_DATA" \
                --stdio \
                --no-children \
                --sort=dso,symbol \
                --percent-limit=1 \
                > "$PERF_REPORT" 2>/dev/null || true

            $SUDO perf report \
                -i "$PERF_DATA" \
                --stdio \
                --sort=symbol \
                --percent-limit=2 \
                > "${LOG_PREFIX}_perf_callers.txt" 2>/dev/null || true

            if command -v stackcollapse-perf.pl &>/dev/null; then
                echo "[$(date +%H:%M:%S)] Generating flamegraph..."
                $SUDO perf script -i "$PERF_DATA" | stackcollapse-perf.pl > "$PERF_FLAMEGRAPH_FOLDED" 2>/dev/null || true
                if command -v flamegraph.pl &>/dev/null && [[ -s "$PERF_FLAMEGRAPH_FOLDED" ]]; then
                    flamegraph.pl "$PERF_FLAMEGRAPH_FOLDED" > "${LOG_PREFIX}_flamegraph.svg" 2>/dev/null || true
                    echo "  Flamegraph: ${LOG_PREFIX}_flamegraph.svg"
                fi
            else
                echo "  TIP: Install FlameGraph tools for SVG flamegraphs:"
                echo "    git clone https://github.com/brendangregg/FlameGraph.git"
                echo "    export PATH=\$PATH:\$(pwd)/FlameGraph"
            fi

            $SUDO chown "$(id -u):$(id -g)" "$PERF_DATA" "${PERF_REPORT}" \
                "${LOG_PREFIX}_perf_callers.txt" 2>/dev/null || true
            [[ -f "$PERF_FLAMEGRAPH_FOLDED" ]] && $SUDO chown "$(id -u):$(id -g)" "$PERF_FLAMEGRAPH_FOLDED" 2>/dev/null || true
            [[ -f "${LOG_PREFIX}_flamegraph.svg" ]] && $SUDO chown "$(id -u):$(id -g)" "${LOG_PREFIX}_flamegraph.svg" 2>/dev/null || true

            echo "  perf data:    $PERF_DATA"
            echo "  perf report:  $PERF_REPORT"
            echo "  perf callers: ${LOG_PREFIX}_perf_callers.txt"
            echo ""
        fi

        METRICS=$(parse_results "$LOG_FILE")
        echo "${CURRENT_NAME},${ENGINE},${TABLES},${TABLE_SIZE},${THREADS},${TIME},${SETTLE},${PREPARE_ELAPSED},${METRICS}" >> "$CSV_FILE"

        echo "[$(date +%H:%M:%S)] Cleaning up $ENGINE tables..."
        sysbench "${COMMON[@]}" cleanup 2>&1 | tee "${LOG_PREFIX}_cleanup.log"
        echo ""

        echo "[$(date +%H:%M:%S)] Cooldown (3s)..."
        sleep 3
        echo ""
    done
done

echo ""
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
echo "  RESULTS SUMMARY"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
column -t -s',' "$CSV_FILE" 2>/dev/null || cat "$CSV_FILE"
echo ""
echo "CSV saved to: $CSV_FILE"
echo "Full logs in: $LOG_DIR/"
if [[ "$PERF_RECORD" -eq 1 ]]; then
    echo ""
    echo ">> Perf outputs >>"
    for name in "${WORKLOAD_NAMES[@]}"; do
        for ENGINE in "${ENGINES[@]}"; do
            prefix="${LOG_DIR}/${name}_${ENGINE}"
            echo "  ${name} + ${ENGINE}:"
            [[ -f "${prefix}_perf.data" ]]         && echo "    Raw:        ${prefix}_perf.data"
            [[ -f "${prefix}_perf_report.txt" ]]   && echo "    Report:     ${prefix}_perf_report.txt"
            [[ -f "${prefix}_perf_callers.txt" ]]  && echo "    Callers:    ${prefix}_perf_callers.txt"
            [[ -f "${prefix}_flamegraph.svg" ]]    && echo "    Flamegraph: ${prefix}_flamegraph.svg"
        done
    done
    echo ""
    echo "Quick analysis:"
    echo "  perf report -i ${LOG_DIR}/<workload>_<ENGINE>_perf.data"
    echo "  perf annotate -i ${LOG_DIR}/<workload>_<ENGINE>_perf.data -s <symbol>"
fi
echo ""

fi  # end SKIP_BENCH

echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
echo "  GENERATING CHARTS"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
echo ""

if command -v python3 &>/dev/null; then
    python3 - "$CSV_FILE" "$LOG_DIR" <<'PYEOF'
import sys, os
import csv
from collections import defaultdict

csv_path = sys.argv[1]
out_dir  = sys.argv[2]

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import matplotlib.ticker as ticker
except ImportError:
    print("  WARNING: matplotlib not found, skipping charts")
    print("  Install with: pip install matplotlib")
    sys.exit(0)

# ---------- read csv ----------
rows = []
with open(csv_path) as f:
    reader = csv.DictReader(f)
    for r in reader:
        if not r.get("workload"):
            continue
        rows.append(r)

if not rows:
    print("  No data rows in CSV, skipping charts")
    sys.exit(0)

# ---------- style ----------
plt.rcParams.update({
    "font.family":       "serif",
    "font.size":         11,
    "axes.titlesize":    13,
    "axes.titleweight":  "bold",
    "axes.labelsize":    11,
    "axes.spines.top":   False,
    "axes.spines.right": False,
    "axes.grid":         True,
    "grid.alpha":        0.3,
    "grid.linewidth":    0.5,
    "figure.facecolor":  "white",
    "savefig.facecolor": "white",
    "savefig.dpi":       200,
    "savefig.bbox":      "tight",
})

ENGINE_COLORS = {
    "TidesDB": "#6FA8DC",
    "RocksDB": "#B0B0B0",
}
ENGINE_EDGE = {
    "TidesDB": "#4A7FB5",
    "RocksDB": "#808080",
}

# ---------- organize data ----------
workloads = []
seen = set()
for r in rows:
    wl = r["workload"]
    if wl not in seen:
        workloads.append(wl)
        seen.add(wl)

engines = []
seen = set()
for r in rows:
    e = r["engine"]
    if e not in seen:
        engines.append(e)
        seen.add(e)

data = {}
for r in rows:
    data[(r["workload"], r["engine"])] = r

def short_name(wl):
    return wl.replace("oltp_", "").replace("_", " ")

def smart_format(val):
    if val >= 1_000_000:
        return f"{val/1_000_000:.1f}M"
    if val >= 1_000:
        return f"{val/1_000:.0f}K"
    return f"{val:.0f}"

# ---------- chart helpers ----------
def grouped_bar(metric, title, ylabel, filename, fmt_func=None, lower_better=False):
    import numpy as np

    labels = [short_name(w) for w in workloads]
    x = np.arange(len(workloads))
    n = len(engines)
    width = 0.32
    offsets = np.linspace(-(n-1)*width/2, (n-1)*width/2, n)

    fig, ax = plt.subplots(figsize=(max(6, len(workloads) * 2.2), 4.5))

    for i, eng in enumerate(engines):
        vals = []
        for wl in workloads:
            key = (wl, eng)
            if key in data and data[key].get(metric):
                try:
                    vals.append(float(data[key][metric]))
                except ValueError:
                    vals.append(0)
            else:
                vals.append(0)

        bars = ax.bar(
            x + offsets[i], vals, width,
            label=eng,
            color=ENGINE_COLORS.get(eng, "#CCCCCC"),
            edgecolor=ENGINE_EDGE.get(eng, "#999999"),
            linewidth=0.6,
            zorder=3,
        )

        for bar, v in zip(bars, vals):
            if v > 0:
                label = fmt_func(v) if fmt_func else f"{v:,.0f}"
                ax.text(
                    bar.get_x() + bar.get_width() / 2,
                    bar.get_height(),
                    label,
                    ha="center", va="bottom",
                    fontsize=8, fontweight="bold",
                    color="#333333",
                )

    qualifier = "(lower is better)" if lower_better else "(higher is better)"
    ax.set_title(f"{title}  {qualifier}", pad=12)
    ax.set_ylabel(ylabel)
    ax.set_xticks(x)
    ax.set_xticklabels(labels)
    ax.legend(frameon=True, framealpha=0.9, edgecolor="#CCCCCC")
    ax.set_axisbelow(True)

    ymax = ax.get_ylim()[1]
    ax.set_ylim(0, ymax * 1.15)

    fig.tight_layout()
    path = os.path.join(out_dir, filename)
    fig.savefig(path)
    plt.close(fig)
    print(f"  Chart: {path}")

# ---------- generate charts ----------
grouped_bar(
    "tps", "Transactions per second", "TPS",
    "chart_tps.png", fmt_func=smart_format,
)

grouped_bar(
    "qps", "Queries per second", "QPS",
    "chart_qps.png", fmt_func=smart_format,
)

grouped_bar(
    "lat_p95_ms", "P95 latency", "Latency (ms)",
    "chart_p95_latency.png",
    fmt_func=lambda v: f"{v:.2f}",
    lower_better=True,
)

grouped_bar(
    "lat_avg_ms", "Average latency", "Latency (ms)",
    "chart_avg_latency.png",
    fmt_func=lambda v: f"{v:.2f}",
    lower_better=True,
)

grouped_bar(
    "lat_max_ms", "Max latency (tail)", "Latency (ms)",
    "chart_max_latency.png",
    fmt_func=lambda v: f"{v:.1f}",
    lower_better=True,
)

grouped_bar(
    "prepare_sec", "Prepare time (data load)", "Seconds",
    "chart_prepare_time.png",
    fmt_func=lambda v: f"{v:.0f}s",
    lower_better=True,
)

# ---------- combined summary figure ----------
import numpy as np

if len(workloads) >= 2:
    fig, axes = plt.subplots(1, 3, figsize=(max(10, len(workloads) * 3.5), 4.5))
    metrics_combo = [
        ("tps",       "Transactions / sec",  False, smart_format),
        ("lat_p95_ms","P95 latency (ms)",     True,  lambda v: f"{v:.2f}"),
        ("prepare_sec","Prepare time (s)",    True,  lambda v: f"{v:.0f}"),
    ]

    labels = [short_name(w) for w in workloads]
    x = np.arange(len(workloads))
    n = len(engines)
    width = 0.32
    offsets = np.linspace(-(n-1)*width/2, (n-1)*width/2, n)

    for ax, (metric, title, lower_better, fmt_fn) in zip(axes, metrics_combo):
        for i, eng in enumerate(engines):
            vals = []
            for wl in workloads:
                key = (wl, eng)
                if key in data and data[key].get(metric):
                    try:
                        vals.append(float(data[key][metric]))
                    except ValueError:
                        vals.append(0)
                else:
                    vals.append(0)

            bars = ax.bar(
                x + offsets[i], vals, width,
                label=eng,
                color=ENGINE_COLORS.get(eng, "#CCCCCC"),
                edgecolor=ENGINE_EDGE.get(eng, "#999999"),
                linewidth=0.6, zorder=3,
            )

            for bar, v in zip(bars, vals):
                if v > 0:
                    ax.text(
                        bar.get_x() + bar.get_width() / 2,
                        bar.get_height(),
                        fmt_fn(v),
                        ha="center", va="bottom",
                        fontsize=7, fontweight="bold", color="#333333",
                    )

        qualifier = "lower =" if lower_better else "higher ="
        ax.set_title(f"{title}\n({qualifier} better)", fontsize=10)
        ax.set_xticks(x)
        ax.set_xticklabels(labels, fontsize=8, rotation=30, ha="right")
        ax.set_axisbelow(True)
        ymax = ax.get_ylim()[1]
        ax.set_ylim(0, ymax * 1.18)

    axes[0].legend(frameon=True, framealpha=0.9, edgecolor="#CCCCCC", fontsize=9)
    fig.suptitle("TidesDB vs RocksDB - sysbench OLTP", fontsize=14, fontweight="bold", y=1.02)
    fig.tight_layout()
    path = os.path.join(out_dir, "chart_summary.png")
    fig.savefig(path)
    plt.close(fig)
    print(f"  Chart: {path}")

print("")
print("  All charts saved to: " + out_dir)
PYEOF
    echo ""
else
    echo "  WARNING: python3 not found, skipping chart generation"
    echo "  Install with: sudo apt install python3 python3-matplotlib"
fi

echo "Done."
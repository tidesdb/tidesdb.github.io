#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  TidesDB vs RocksDB - HammerDB TPC-C / TPC-H benchmark
#  Requires: HammerDB 5.0, MariaDB with TidesDB+RocksDB engines
# ============================================================

# ---------- defaults ----------
HAMMERDB_DIR=${HAMMERDB_DIR:-/opt/HammerDB-5.0}
ENGINE_SELECT=${ENGINE_SELECT:-both}
BENCH_SELECT=${BENCH_SELECT:-both}
MYSQL_USER=${MYSQL_USER:-root}
MYSQL_PASS=${MYSQL_PASS:-}
MYSQL_HOST=${MYSQL_HOST:-localhost}
MYSQL_PORT=${MYSQL_PORT:-3306}
MYSQL_SOCKET=${MYSQL_SOCKET:-/tmp/mariadb.sock}
SETTLE=${SETTLE:-60}
DEBUG_RUN=0
PERF_RECORD=${PERF_RECORD:-0}
PERF_FREQ=${PERF_FREQ:-99}
PLOT_ONLY=""

if sudo -n true 2>/dev/null; then
    SUDO="sudo -n"
elif [[ $EUID -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
fi

# TPC-C defaults
TPCC_WAREHOUSES=${TPCC_WAREHOUSES:-20}
TPCC_BUILD_VU=${TPCC_BUILD_VU:-4}
TPCC_VU=${TPCC_VU:-8}
TPCC_RAMPUP=${TPCC_RAMPUP:-2}
TPCC_DURATION=${TPCC_DURATION:-5}
TPCC_DBASE=${TPCC_DBASE:-tpcc}

# TPC-H defaults
TPCH_SCALE=${TPCH_SCALE:-1}
TPCH_BUILD_THREADS=${TPCH_BUILD_THREADS:-4}
TPCH_VU=${TPCH_VU:-1}
TPCH_QUERYSETS=${TPCH_QUERYSETS:-1}
TPCH_DEGREE=${TPCH_DEGREE:-2}
TPCH_DBASE=${TPCH_DBASE:-tpch}

HAMMERDBCLI="${HAMMERDB_DIR}/hammerdbcli"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
WORK_DIR="$(pwd)"
CSV_FILE="${WORK_DIR}/hammerdb_results_${TIMESTAMP}.csv"
LOG_DIR="${WORK_DIR}/hammerdb_logs_${TIMESTAMP}"
mkdir -p "$LOG_DIR"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

HammerDB TPC-C / TPC-H benchmark: TidesDB vs RocksDB

Options:
  -e, --engine       STR   Engine: tidesdb|rocksdb|innodb|both (default: $ENGINE_SELECT)
                           "both" runs tidesdb and rocksdb
  -b, --bench        STR   Benchmark: tpcc|tpch|both       (default: $BENCH_SELECT)
  -H, --hammerdb-dir PATH  HammerDB install directory       (default: $HAMMERDB_DIR)
  -w, --settle       NUM   Post-build settle seconds        (default: $SETTLE)

  TPC-C options:
  --warehouses       NUM   Number of warehouses             (default: $TPCC_WAREHOUSES)
  --tpcc-vu          NUM   Virtual users for TPC-C run      (default: $TPCC_VU)
  --tpcc-build-vu    NUM   Virtual users for schema build   (default: $TPCC_BUILD_VU)
  --rampup           NUM   Rampup time in minutes           (default: $TPCC_RAMPUP)
  --duration         NUM   Test duration in minutes         (default: $TPCC_DURATION)
  --tpcc-db          STR   TPC-C database name              (default: $TPCC_DBASE)

  TPC-H options:
  --scale            NUM   TPC-H scale factor               (default: $TPCH_SCALE)
  --tpch-vu          NUM   Virtual users for TPC-H run      (default: $TPCH_VU)
  --tpch-threads     NUM   Build threads                    (default: $TPCH_BUILD_THREADS)
  --querysets         NUM   Total query sets                 (default: $TPCH_QUERYSETS)
  --degree           NUM   Degree of parallelism            (default: $TPCH_DEGREE)
  --tpch-db          STR   TPC-H database name              (default: $TPCH_DBASE)

  Connection:
  -u, --user         STR   MySQL/MariaDB user               (default: $MYSQL_USER)
  --pass             STR   MySQL/MariaDB password           (default: empty)
  --host             STR   MySQL/MariaDB host               (default: $MYSQL_HOST)
  --port             NUM   MySQL/MariaDB port               (default: $MYSQL_PORT)
  -S, --socket       PATH  MySQL/MariaDB socket             (default: $MYSQL_SOCKET)

  -P, --plot-only    FILE  Skip benchmarks, plot from CSV
  -p, --perf               Enable perf record on mariadbd during run
  -F, --perf-freq    NUM   perf sampling frequency Hz    (default: $PERF_FREQ)
  --debug-run              Run a short diagnostic (2 VU, raiseerror=true)
                           before benchmarking to check for lock conflicts
  -h, --help               Show this help

Examples:
  # Quick smoke test both benchmarks, both engines
  ./tidesdb_rocksdb_hammerdb.sh

  # Debug run first to check for errors, then full benchmark
  ./tidesdb_rocksdb_hammerdb.sh --debug-run -b tpcc --warehouses 20

  # TPC-C only, 40 warehouses, 5 min duration
  ./tidesdb_rocksdb_hammerdb.sh -b tpcc --warehouses 40 --duration 5

  # TPC-H only, scale factor 10
  ./tidesdb_rocksdb_hammerdb.sh -b tpch --scale 10

  # Plot existing results
  ./tidesdb_rocksdb_hammerdb.sh --plot-only hammerdb_results_20260321.csv
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -e|--engine)         ENGINE_SELECT="$2";    shift 2 ;;
        -b|--bench)          BENCH_SELECT="$2";     shift 2 ;;
        -H|--hammerdb-dir)   HAMMERDB_DIR="$2"; HAMMERDBCLI="${2}/hammerdbcli"; shift 2 ;;
        -w|--settle)         SETTLE="$2";           shift 2 ;;
        --warehouses)        TPCC_WAREHOUSES="$2";  shift 2 ;;
        --tpcc-vu)           TPCC_VU="$2";          shift 2 ;;
        --tpcc-build-vu)     TPCC_BUILD_VU="$2";    shift 2 ;;
        --rampup)            TPCC_RAMPUP="$2";      shift 2 ;;
        --duration)          TPCC_DURATION="$2";    shift 2 ;;
        --tpcc-db)           TPCC_DBASE="$2";       shift 2 ;;
        --scale)             TPCH_SCALE="$2";       shift 2 ;;
        --tpch-vu)           TPCH_VU="$2";          shift 2 ;;
        --tpch-threads)      TPCH_BUILD_THREADS="$2"; shift 2 ;;
        --querysets)         TPCH_QUERYSETS="$2";    shift 2 ;;
        --degree)            TPCH_DEGREE="$2";      shift 2 ;;
        --tpch-db)           TPCH_DBASE="$2";       shift 2 ;;
        -u|--user)           MYSQL_USER="$2";       shift 2 ;;
        --pass)              MYSQL_PASS="$2";       shift 2 ;;
        --host)              MYSQL_HOST="$2";       shift 2 ;;
        --port)              MYSQL_PORT="$2";       shift 2 ;;
        -S|--socket)         MYSQL_SOCKET="$2";     shift 2 ;;
        --debug-run)         DEBUG_RUN=1;           shift ;;
        -p|--perf)           PERF_RECORD=1;         shift ;;
        -F|--perf-freq)      PERF_FREQ="$2";        shift 2 ;;
        -P|--plot-only)      PLOT_ONLY="$2";        shift 2 ;;
        -h|--help)           usage ;;
        *)                   echo "Unknown option: $1"; usage ;;
    esac
done

# ---------- plot-only mode ----------
if [[ -n "$PLOT_ONLY" ]]; then
    if [[ ! -f "$PLOT_ONLY" ]]; then
        echo "ERROR: CSV file not found: $PLOT_ONLY"
        exit 1
    fi
    CSV_FILE="$(cd "$(dirname "$PLOT_ONLY")" && pwd)/$(basename "$PLOT_ONLY")"
    CHART_DIR="$(dirname "$CSV_FILE")/charts_$(basename "$CSV_FILE" .csv)"
    mkdir -p "$CHART_DIR"
    echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
    echo "  PLOT-ONLY MODE"
    echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
    echo "  CSV:    $CSV_FILE"
    echo "  Charts: $CHART_DIR/"
    echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
    echo ""
    column -t -s',' "$CSV_FILE" 2>/dev/null || cat "$CSV_FILE"
    echo ""
    LOG_DIR="$CHART_DIR"
    SKIP_BENCH=1
fi

if [[ "${SKIP_BENCH:-0}" -ne 1 ]]; then

# ---------- validate ----------
if [[ ! -x "$HAMMERDBCLI" ]]; then
    echo "ERROR: hammerdbcli not found at $HAMMERDBCLI"
    echo "Set HAMMERDB_DIR or use --hammerdb-dir"
    exit 1
fi

case "${ENGINE_SELECT,,}" in
    tidesdb)   ENGINES=("TidesDB") ;;
    rocksdb)   ENGINES=("RocksDB") ;;
    innodb)    ENGINES=("InnoDB") ;;
    both)      ENGINES=("TidesDB" "RocksDB") ;;
    all)       ENGINES=("TidesDB" "RocksDB" "InnoDB") ;;
    *)         echo "ERROR: --engine must be tidesdb, rocksdb, innodb, both, or all"; exit 1 ;;
esac

# ---------- perf preflight ----------
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

find_mariadbd_pid() {
    local pid
    pid=$(pgrep -x mariadbd || pgrep -x mysqld || true)
    if [[ -z "$pid" ]]; then
        echo "WARNING: Could not find mariadbd/mysqld PID for perf" >&2
        return 1
    fi
    echo "$pid"
}

BENCHMARKS=()
case "${BENCH_SELECT,,}" in
    tpcc|tpc-c)   BENCHMARKS=("TPC-C") ;;
    tpch|tpc-h)   BENCHMARKS=("TPC-H") ;;
    both)         BENCHMARKS=("TPC-C" "TPC-H") ;;
    *)            echo "ERROR: --bench must be tpcc, tpch, or both"; exit 1 ;;
esac

# validate TPC-H scale factor
if [[ " ${BENCHMARKS[*]} " == *"TPC-H"* ]]; then
    case "$TPCH_SCALE" in
        1|10|30|100|300|1000|3000|10000|30000|100000) ;;
        *) echo "ERROR: --scale must be one of: 1, 10, 30, 100, 300, 1000, 3000, 10000, 30000, 100000"; exit 1 ;;
    esac
fi

export TMP="${LOG_DIR}/hammerdb_tmp"
mkdir -p "$TMP"

# ---------- conditional password lines for Tcl scripts ----------
# HammerDB's diset requires a value - omit the line entirely if empty
if [[ -n "$MYSQL_PASS" ]]; then
    DISET_TPCC_PASS="diset tpcc maria_pass $MYSQL_PASS"
    DISET_TPCH_PASS="diset tpch maria_tpch_pass $MYSQL_PASS"
else
    DISET_TPCC_PASS="# password not set"
    DISET_TPCH_PASS="# password not set"
fi

# ---------- CSV header ----------
cat > "$CSV_FILE" <<EOF
benchmark,engine,nopm,tpm,warehouses,virtual_users,rampup_min,duration_min,scale_factor,querysets,build_sec,settle_sec,neword_avg_ms,neword_p95_ms,payment_avg_ms,payment_p95_ms,delivery_avg_ms,delivery_p95_ms,tpch_geomean_sec,tpch_total_sec
EOF

TOTAL_RUNS=$(( ${#BENCHMARKS[@]} * ${#ENGINES[@]} ))
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
echo "  HammerDB TPC-C / TPC-H bench"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
echo "  Benchmark(s): ${BENCHMARKS[*]}"
echo "  Engine(s):    ${ENGINES[*]}"
echo "  Total runs:   $TOTAL_RUNS"
if [[ " ${BENCHMARKS[*]} " == *"TPC-C"* ]]; then
    echo "  TPC-C:        ${TPCC_WAREHOUSES} warehouses, ${TPCC_VU} VU, ${TPCC_RAMPUP}m ramp, ${TPCC_DURATION}m run"
fi
if [[ " ${BENCHMARKS[*]} " == *"TPC-H"* ]]; then
    echo "  TPC-H:        SF${TPCH_SCALE}, ${TPCH_VU} VU, ${TPCH_QUERYSETS} querysets, degree=${TPCH_DEGREE}"
fi
echo "  Settle:       ${SETTLE}s"
echo "  Debug run:    $([ "$DEBUG_RUN" -eq 1 ] && echo "ON (raiseerror=true pre-check)" || echo "OFF")"
echo "  Perf:         $([ "$PERF_RECORD" -eq 1 ] && echo "ON (${PERF_FREQ} Hz)" || echo "OFF")"
echo "  Socket:       $MYSQL_SOCKET"
echo "  HammerDB:     $HAMMERDB_DIR"
echo "  CSV output:   $CSV_FILE"
echo "  Logs:         $LOG_DIR/"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
echo ""

# ---------- helper: generate tcl scripts ----------

gen_tpcc_build() {
    local engine="$1" outfile="$2"
    local partition="false"
    [[ "$TPCC_WAREHOUSES" -ge 200 ]] && partition="true"
    cat > "$outfile" <<TCLEOF
puts "SETTING CONFIGURATION"
dbset db maria
dbset bm TPC-C
diset connection maria_host $MYSQL_HOST
diset connection maria_port $MYSQL_PORT
diset connection maria_socket $MYSQL_SOCKET
diset tpcc maria_count_ware $TPCC_WAREHOUSES
diset tpcc maria_num_vu $TPCC_BUILD_VU
diset tpcc maria_user $MYSQL_USER
$DISET_TPCC_PASS
diset tpcc maria_dbase $TPCC_DBASE
diset tpcc maria_storage_engine [string tolower $engine]
diset tpcc maria_partition $partition
puts "SCHEMA BUILD STARTED"
buildschema
puts "SCHEMA BUILD COMPLETED"
TCLEOF
}

gen_tpcc_run() {
    local outfile="$1"
    cat > "$outfile" <<TCLEOF
set tmpdir \$::env(TMP)
puts "SETTING CONFIGURATION"
dbset db maria
dbset bm TPC-C
diset connection maria_host $MYSQL_HOST
diset connection maria_port $MYSQL_PORT
diset connection maria_socket $MYSQL_SOCKET
diset tpcc maria_user $MYSQL_USER
$DISET_TPCC_PASS
diset tpcc maria_dbase $TPCC_DBASE
diset tpcc maria_driver timed
diset tpcc maria_rampup $TPCC_RAMPUP
diset tpcc maria_duration $TPCC_DURATION
diset tpcc maria_allwarehouse true
diset tpcc maria_timeprofile true
loadscript
puts "TEST STARTED"
vuset vu $TPCC_VU
vucreate
tcstart
tcstatus
set jobid [ vurun ]
vudestroy
tcstop
puts "TEST COMPLETE"
set of [ open \$tmpdir/maria_tprocc w ]
puts \$of \$jobid
close \$of
TCLEOF
}

gen_tpcc_result() {
    local outfile="$1"
    cat > "$outfile" <<TCLEOF
set tmpdir \$::env(TMP)
set ::outputfile \$tmpdir/maria_tprocc
source $HAMMERDB_DIR/scripts/tcl/generic/generic_tprocc_result.tcl
TCLEOF
}

gen_tpcc_delete() {
    local outfile="$1"
    cat > "$outfile" <<TCLEOF
puts "SETTING CONFIGURATION"
dbset db maria
dbset bm TPC-C
diset connection maria_host $MYSQL_HOST
diset connection maria_port $MYSQL_PORT
diset connection maria_socket $MYSQL_SOCKET
diset tpcc maria_user $MYSQL_USER
$DISET_TPCC_PASS
diset tpcc maria_dbase $TPCC_DBASE
puts "DROP SCHEMA STARTED"
deleteschema
puts "DROP SCHEMA COMPLETED"
TCLEOF
}

gen_tpch_build() {
    local outfile="$1"
    cat > "$outfile" <<TCLEOF
puts "SETTING CONFIGURATION"
dbset db maria
dbset bm TPC-H
diset connection maria_host $MYSQL_HOST
diset connection maria_port $MYSQL_PORT
diset connection maria_socket $MYSQL_SOCKET
diset tpch maria_scale_fact $TPCH_SCALE
diset tpch maria_num_tpch_threads $TPCH_BUILD_THREADS
diset tpch maria_tpch_user $MYSQL_USER
$DISET_TPCH_PASS
diset tpch maria_tpch_dbase $TPCH_DBASE
puts "SCHEMA BUILD STARTED"
buildschema
puts "SCHEMA BUILD COMPLETED"
TCLEOF
}

gen_tpch_run() {
    local outfile="$1"
    cat > "$outfile" <<TCLEOF
set tmpdir \$::env(TMP)
puts "SETTING CONFIGURATION"
dbset db maria
dbset bm TPC-H
diset connection maria_host $MYSQL_HOST
diset connection maria_port $MYSQL_PORT
diset connection maria_socket $MYSQL_SOCKET
diset tpch maria_tpch_user $MYSQL_USER
$DISET_TPCH_PASS
diset tpch maria_tpch_dbase $TPCH_DBASE
diset tpch maria_total_querysets $TPCH_QUERYSETS
diset tpch maria_raise_query_error true
diset tpch maria_verbose true
loadscript
puts "TEST STARTED"
vuset vu $TPCH_VU
vucreate
set jobid [ vurun ]
vudestroy
puts "TEST COMPLETE"
set of [ open \$tmpdir/tpch_jobid w ]
puts \$of \$jobid
close \$of
TCLEOF
}

gen_tpch_delete() {
    local outfile="$1"
    cat > "$outfile" <<TCLEOF
puts "SETTING CONFIGURATION"
dbset db maria
dbset bm TPC-H
diset connection maria_host $MYSQL_HOST
diset connection maria_port $MYSQL_PORT
diset connection maria_socket $MYSQL_SOCKET
diset tpch maria_tpch_user $MYSQL_USER
$DISET_TPCH_PASS
diset tpch maria_tpch_dbase $TPCH_DBASE
puts "DROP SCHEMA STARTED"
deleteschema
puts "DROP SCHEMA COMPLETED"
TCLEOF
}

# ---------- helper: parse TPC-C results ----------
parse_tpcc() {
    local logfile="$1"
    local nopm tpm
    local line
    line=$(grep "TEST RESULT" "$logfile" | tail -1 || true)
    nopm=$(echo "$line" | grep -oP 'achieved \K[0-9]+' || echo "0")
    tpm=$(echo "$line" | grep -oP 'from \K[0-9]+' || echo "0")
    echo "${nopm},${tpm}"
}

parse_tpcc_timing() {
    local logfile="$1"
    local neword_avg neword_p95 pay_avg pay_p95 del_avg del_p95
    neword_avg=$(grep -A20 '"NEWORD"' "$logfile" | grep '"avg_ms"' | head -1 | grep -oP ':\s*"\K[0-9.]+' || echo "0")
    neword_p95=$(grep -A20 '"NEWORD"' "$logfile" | grep '"p95_ms"' | head -1 | grep -oP ':\s*"\K[0-9.]+' || echo "0")
    pay_avg=$(grep -A20 '"PAYMENT"' "$logfile" | grep '"avg_ms"' | head -1 | grep -oP ':\s*"\K[0-9.]+' || echo "0")
    pay_p95=$(grep -A20 '"PAYMENT"' "$logfile" | grep '"p95_ms"' | head -1 | grep -oP ':\s*"\K[0-9.]+' || echo "0")
    del_avg=$(grep -A20 '"DELIVERY"' "$logfile" | grep '"avg_ms"' | head -1 | grep -oP ':\s*"\K[0-9.]+' || echo "0")
    del_p95=$(grep -A20 '"DELIVERY"' "$logfile" | grep '"p95_ms"' | head -1 | grep -oP ':\s*"\K[0-9.]+' || echo "0")
    echo "${neword_avg},${neword_p95},${pay_avg},${pay_p95},${del_avg},${del_p95}"
}

parse_tpch() {
    local logfile="$1"
    local -a qtimes=()
    local total=0 count=0 geomean=0
    while IFS= read -r line; do
        local secs
        secs=$(echo "$line" | grep -oP 'completed in \K[0-9.]+' || true)
        if [[ -n "$secs" ]]; then
            qtimes+=("$secs")
            total=$(echo "$total + $secs" | bc -l)
            count=$((count + 1))
        fi
    done < <(grep "query.*completed in" "$logfile" || true)

    if [[ $count -gt 0 ]]; then
        local log_sum=0
        for t in "${qtimes[@]}"; do
            log_sum=$(echo "$log_sum + l($t)" | bc -l)
        done
        geomean=$(echo "e($log_sum / $count)" | bc -l)
        geomean=$(printf "%.3f" "$geomean")
        total=$(printf "%.3f" "$total")
    fi
    echo "${geomean},${total}"
}

# ---------- settle helper ----------
do_settle() {
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
        echo "[$(date +%H:%M:%S)] Settle complete"
    fi
}

# ---------- set default storage engine ----------
set_default_engine() {
    local engine_lower
    engine_lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    echo "[$(date +%H:%M:%S)] Setting default_storage_engine=$engine_lower..."
    mysql -u "$MYSQL_USER" ${MYSQL_PASS:+-p"$MYSQL_PASS"} -S "$MYSQL_SOCKET" \
        -e "SET GLOBAL default_storage_engine='$engine_lower';" 2>/dev/null || true
}

# ============================================================
#  DEBUG RUN (optional) - short test with raiseerror=true
# ============================================================
if [[ "$DEBUG_RUN" -eq 1 ]]; then
    DEBUG_VU=2

    echo "######################################################"
    echo "  DEBUG RUN - checking for lock conflicts"
    echo "  VUs: $DEBUG_VU  |  Duration: 1 min (0 ramp)"
    echo "  raiseerror: TRUE  |  driver: timed"
    echo "######################################################"
    echo ""

    for ENGINE in "${ENGINES[@]}"; do
        DBG_PREFIX="${LOG_DIR}/debug_${ENGINE}"

        echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
        echo "  DEBUG: $ENGINE"
        echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"

        set_default_engine "$ENGINE"

        # -- build small schema --
        gen_tpcc_build "$ENGINE" "${DBG_PREFIX}_build.tcl"
        echo "[$(date +%H:%M:%S)] Building debug schema ($ENGINE, ${TPCC_WAREHOUSES} warehouses)..."
        (cd "$HAMMERDB_DIR" && "$HAMMERDBCLI" auto "${DBG_PREFIX}_build.tcl") 2>&1 | tee "${DBG_PREFIX}_build.log" || true
        echo ""

        sleep 5

        # -- run with raiseerror=true, timed driver (short) --
        cat > "${DBG_PREFIX}_run.tcl" <<TCLEOF
puts "DEBUG RUN CONFIGURATION"
dbset db maria
dbset bm TPC-C
diset connection maria_host $MYSQL_HOST
diset connection maria_port $MYSQL_PORT
diset connection maria_socket $MYSQL_SOCKET
diset tpcc maria_user $MYSQL_USER
$DISET_TPCC_PASS
diset tpcc maria_dbase $TPCC_DBASE
diset tpcc maria_driver timed
diset tpcc maria_rampup 0
diset tpcc maria_duration 1
diset tpcc maria_raiseerror true
diset tpcc maria_allwarehouse true
diset tpcc maria_timeprofile false
loadscript
puts "DEBUG TEST STARTED"
vuset vu $DEBUG_VU
vucreate
tcstart
tcstatus
set jobid [ vurun ]
vudestroy
tcstop
puts "DEBUG TEST COMPLETE"
TCLEOF

        echo "[$(date +%H:%M:%S)] Running debug test ($ENGINE, $DEBUG_VU VU, 1 min timed, raiseerror=true)..."
        (cd "$HAMMERDB_DIR" && TMP="$TMP" "$HAMMERDBCLI" auto "${DBG_PREFIX}_run.tcl") 2>&1 | tee "${DBG_PREFIX}_run.log" || true
        echo ""

        # -- count errors --
        DEADLOCKS=$(grep -ciE "deadlock|lock wait timeout|Error 1213|Error 1180" "${DBG_PREFIX}_run.log" 2>/dev/null) || DEADLOCKS=0
        PROC_ERRORS=$(grep -ciE "Procedure Error" "${DBG_PREFIX}_run.log" 2>/dev/null) || PROC_ERRORS=0
        ABORTS=$(grep -ciE "FINISHED FAILED" "${DBG_PREFIX}_run.log" 2>/dev/null) || ABORTS=0

        echo "  ========================================="
        echo "  DEBUG RESULTS: $ENGINE"
        echo "  ========================================="
        echo "  Deadlock/lock-wait hits:  $DEADLOCKS"
        echo "  Procedure errors:         $PROC_ERRORS"
        echo "  VUs finished failed:      $ABORTS"
        if [[ "$DEADLOCKS" -gt 0 || "$PROC_ERRORS" -gt 0 || "$ABORTS" -gt 0 ]]; then
            echo ""
            echo "  Issues detected for $ENGINE."
            if [[ "$DEADLOCKS" -gt 0 || "$PROC_ERRORS" -gt 0 ]]; then
                echo "  Lock conflicts found - the timed benchmark uses"
                echo "  raiseerror=false (default) so these will be silently"
                echo "  caught and skipped. High rates may deflate TPM."
            fi
            if [[ "$ABORTS" -gt 0 ]]; then
                echo "  Some VUs FINISHED FAILED - check log for details."
            fi
            echo ""
            echo "  Relevant lines:"
            grep -iE "deadlock|lock wait|Error 1213|Error 1180|Procedure Error|FINISHED FAILED" "${DBG_PREFIX}_run.log" | head -10 || true
        else
            echo "  No lock conflicts detected - clean run."
        fi
        echo "  ========================================="
        echo ""

        # -- cleanup --
        gen_tpcc_delete "${DBG_PREFIX}_delete.tcl"
        echo "[$(date +%H:%M:%S)] Cleaning up debug schema..."
        (cd "$HAMMERDB_DIR" && "$HAMMERDBCLI" auto "${DBG_PREFIX}_delete.tcl") 2>&1 | tee "${DBG_PREFIX}_delete.log" || true
        echo ""

        sleep 3
    done

    echo "######################################################"
    echo "  DEBUG RUN COMPLETE - proceeding to benchmark"
    echo "######################################################"
    echo ""
fi

# ============================================================
#  MAIN BENCHMARK LOOP
# ============================================================
RUN_NUM=0
for BENCH in "${BENCHMARKS[@]}"; do
    for ENGINE in "${ENGINES[@]}"; do
        RUN_NUM=$((RUN_NUM + 1))
        LOG_PREFIX="${LOG_DIR}/${BENCH}_${ENGINE}"

        echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
        echo "  [$RUN_NUM/$TOTAL_RUNS] $BENCH + $ENGINE"
        echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
        echo ""

        set_default_engine "$ENGINE"

        if [[ "$BENCH" == "TPC-C" ]]; then
            # ---- TPC-C BUILD ----
            gen_tpcc_build "$ENGINE" "${LOG_PREFIX}_build.tcl"
            echo "[$(date +%H:%M:%S)] Building TPC-C schema ($ENGINE, ${TPCC_WAREHOUSES} warehouses)..."
            BUILD_START=$(date +%s)
            (cd "$HAMMERDB_DIR" && "$HAMMERDBCLI" auto "${LOG_PREFIX}_build.tcl") 2>&1 | tee "${LOG_PREFIX}_build.log" || true
            BUILD_END=$(date +%s)
            BUILD_ELAPSED=$((BUILD_END - BUILD_START))
            echo "[$(date +%H:%M:%S)] Build completed in ${BUILD_ELAPSED}s"
            echo ""

            do_settle

            # ---- PERF START ----
            PERF_PID=""
            if [[ "$PERF_RECORD" -eq 1 ]]; then
                MARIADBD_PID=$(find_mariadbd_pid) || true
                if [[ -n "$MARIADBD_PID" ]]; then
                    echo "[$(date +%H:%M:%S)] Starting perf record on mariadbd (PID $MARIADBD_PID, ${PERF_FREQ} Hz)..."
                    $SUDO perf record \
                        -F "$PERF_FREQ" \
                        -p "$MARIADBD_PID" \
                        -g \
                        --call-graph dwarf,16384 \
                        -o "${LOG_PREFIX}_perf.data" &
                    PERF_PID=$!
                    sleep 1
                    echo "[$(date +%H:%M:%S)] perf recording (background PID $PERF_PID)"
                else
                    echo "[$(date +%H:%M:%S)] WARNING: Skipping perf - mariadbd PID not found"
                fi
            fi

            # ---- TPC-C RUN ----
            gen_tpcc_run "${LOG_PREFIX}_run.tcl"
            echo "[$(date +%H:%M:%S)] Running TPC-C ($ENGINE, ${TPCC_DURATION}m, ${TPCC_VU} VU)..."
            (cd "$HAMMERDB_DIR" && TMP="$TMP" "$HAMMERDBCLI" auto "${LOG_PREFIX}_run.tcl") 2>&1 | tee "${LOG_PREFIX}_run.log" || true
            echo ""

            # ---- PERF STOP ----
            if [[ -n "$PERF_PID" ]] && kill -0 "$PERF_PID" 2>/dev/null; then
                echo "[$(date +%H:%M:%S)] Stopping perf..."
                $SUDO kill -INT "$PERF_PID"
                wait "$PERF_PID" 2>/dev/null || true

                echo "[$(date +%H:%M:%S)] Generating perf report..."

                $SUDO perf report \
                    -i "${LOG_PREFIX}_perf.data" \
                    --stdio \
                    --no-children \
                    --sort=dso,symbol \
                    --percent-limit=1 \
                    > "${LOG_PREFIX}_perf_report.txt" 2>/dev/null || true

                $SUDO perf report \
                    -i "${LOG_PREFIX}_perf.data" \
                    --stdio \
                    --sort=symbol \
                    --percent-limit=2 \
                    > "${LOG_PREFIX}_perf_callers.txt" 2>/dev/null || true

                if command -v stackcollapse-perf.pl &>/dev/null; then
                    echo "[$(date +%H:%M:%S)] Generating flamegraph..."
                    $SUDO perf script -i "${LOG_PREFIX}_perf.data" | stackcollapse-perf.pl > "${LOG_PREFIX}_perf.folded" 2>/dev/null || true
                    if command -v flamegraph.pl &>/dev/null && [[ -s "${LOG_PREFIX}_perf.folded" ]]; then
                        flamegraph.pl "${LOG_PREFIX}_perf.folded" > "${LOG_PREFIX}_flamegraph.svg" 2>/dev/null || true
                        echo "  Flamegraph: ${LOG_PREFIX}_flamegraph.svg"
                    fi
                else
                    echo "  TIP: Install FlameGraph tools for SVG flamegraphs:"
                    echo "    git clone https://github.com/brendangregg/FlameGraph.git"
                    echo "    export PATH=\$PATH:\$(pwd)/FlameGraph"
                fi

                $SUDO chown "$(id -u):$(id -g)" "${LOG_PREFIX}_perf.data" "${LOG_PREFIX}_perf_report.txt" \
                    "${LOG_PREFIX}_perf_callers.txt" 2>/dev/null || true
                [[ -f "${LOG_PREFIX}_perf.folded" ]] && $SUDO chown "$(id -u):$(id -g)" "${LOG_PREFIX}_perf.folded" 2>/dev/null || true
                [[ -f "${LOG_PREFIX}_flamegraph.svg" ]] && $SUDO chown "$(id -u):$(id -g)" "${LOG_PREFIX}_flamegraph.svg" 2>/dev/null || true

                echo "  perf data:    ${LOG_PREFIX}_perf.data"
                echo "  perf report:  ${LOG_PREFIX}_perf_report.txt"
                echo "  perf callers: ${LOG_PREFIX}_perf_callers.txt"
                echo ""
            fi

            # ---- TPC-C RESULT ----
            gen_tpcc_result "${LOG_PREFIX}_result.tcl"
            echo "[$(date +%H:%M:%S)] Querying TPC-C results..."
            (cd "$HAMMERDB_DIR" && TMP="$TMP" "$HAMMERDBCLI" auto "${LOG_PREFIX}_result.tcl") 2>&1 | tee "${LOG_PREFIX}_result.log" || true
            echo ""

            # ---- PARSE ----
            NOPM_TPM=$(parse_tpcc "${LOG_PREFIX}_run.log")
            TIMING=$(parse_tpcc_timing "${LOG_PREFIX}_result.log" 2>/dev/null) || TIMING="0,0,0,0,0,0"

            echo "${BENCH},${ENGINE},${NOPM_TPM},${TPCC_WAREHOUSES},${TPCC_VU},${TPCC_RAMPUP},${TPCC_DURATION},,,${BUILD_ELAPSED},${SETTLE},${TIMING},,," >> "$CSV_FILE"

            # ---- TPC-C DELETE ----
            gen_tpcc_delete "${LOG_PREFIX}_delete.tcl"
            echo "[$(date +%H:%M:%S)] Deleting TPC-C schema..."
            (cd "$HAMMERDB_DIR" && "$HAMMERDBCLI" auto "${LOG_PREFIX}_delete.tcl") 2>&1 | tee "${LOG_PREFIX}_delete.log" || true
            echo ""

        elif [[ "$BENCH" == "TPC-H" ]]; then
            # ---- TPC-H BUILD ----
            gen_tpch_build "${LOG_PREFIX}_build.tcl"
            echo "[$(date +%H:%M:%S)] Building TPC-H schema ($ENGINE, SF${TPCH_SCALE})..."
            BUILD_START=$(date +%s)
            (cd "$HAMMERDB_DIR" && "$HAMMERDBCLI" auto "${LOG_PREFIX}_build.tcl") 2>&1 | tee "${LOG_PREFIX}_build.log" || true
            BUILD_END=$(date +%s)
            BUILD_ELAPSED=$((BUILD_END - BUILD_START))
            echo "[$(date +%H:%M:%S)] Build completed in ${BUILD_ELAPSED}s"
            echo ""

            do_settle

            # ---- TPC-H RUN ----
            gen_tpch_run "${LOG_PREFIX}_run.tcl"
            echo "[$(date +%H:%M:%S)] Running TPC-H ($ENGINE, SF${TPCH_SCALE}, ${TPCH_VU} VU)..."
            (cd "$HAMMERDB_DIR" && TMP="$TMP" "$HAMMERDBCLI" auto "${LOG_PREFIX}_run.tcl") 2>&1 | tee "${LOG_PREFIX}_run.log" || true
            echo ""

            # ---- PARSE ----
            TPCH_METRICS=$(parse_tpch "${LOG_PREFIX}_run.log")

            echo "${BENCH},${ENGINE},,,,,,,${TPCH_SCALE},${TPCH_QUERYSETS},${BUILD_ELAPSED},${SETTLE},,,,,,${TPCH_METRICS}" >> "$CSV_FILE"

            # ---- TPC-H DELETE ----
            gen_tpch_delete "${LOG_PREFIX}_delete.tcl"
            echo "[$(date +%H:%M:%S)] Deleting TPC-H schema..."
            (cd "$HAMMERDB_DIR" && "$HAMMERDBCLI" auto "${LOG_PREFIX}_delete.tcl") 2>&1 | tee "${LOG_PREFIX}_delete.log" || true
            echo ""
        fi

        echo "[$(date +%H:%M:%S)] Cooldown (5s)..."
        sleep 5
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
    for ENGINE in "${ENGINES[@]}"; do
        for BENCH in "${BENCHMARKS[@]}"; do
            prefix="${LOG_DIR}/${BENCH}_${ENGINE}"
            if [[ -f "${prefix}_perf.data" ]]; then
                echo "  ${BENCH} + ${ENGINE}:"
                echo "    Raw:        ${prefix}_perf.data"
                [[ -f "${prefix}_perf_report.txt" ]]  && echo "    Report:     ${prefix}_perf_report.txt"
                [[ -f "${prefix}_perf_callers.txt" ]] && echo "    Callers:    ${prefix}_perf_callers.txt"
                [[ -f "${prefix}_flamegraph.svg" ]]   && echo "    Flamegraph: ${prefix}_flamegraph.svg"
            fi
        done
    done
    echo ""
    echo "Quick analysis:"
    echo "  perf report -i ${LOG_DIR}/<BENCH>_<ENGINE>_perf.data"
    echo "  perf annotate -i ${LOG_DIR}/<BENCH>_<ENGINE>_perf.data -s <symbol>"
fi
echo ""

fi  # end SKIP_BENCH

# ============================================================
#  CHART GENERATION
# ============================================================
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
echo "  GENERATING CHARTS"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
echo ""

if command -v python3 &>/dev/null; then
    python3 - "$CSV_FILE" "$LOG_DIR" <<'PYEOF'
import sys, os, csv

csv_path = sys.argv[1]
out_dir  = sys.argv[2]

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np
except ImportError:
    print("  WARNING: matplotlib not found, skipping charts")
    print("  Install with: pip install matplotlib")
    sys.exit(0)

rows = []
with open(csv_path) as f:
    for r in csv.DictReader(f):
        if r.get("benchmark"):
            rows.append(r)

if not rows:
    print("  No data rows, skipping charts")
    sys.exit(0)

plt.rcParams.update({
    "font.family": "serif", "font.size": 11,
    "axes.titlesize": 13, "axes.titleweight": "bold",
    "axes.labelsize": 11, "axes.spines.top": False, "axes.spines.right": False,
    "axes.grid": True, "grid.alpha": 0.3, "grid.linewidth": 0.5,
    "figure.facecolor": "white", "savefig.facecolor": "white",
    "savefig.dpi": 200, "savefig.bbox": "tight",
})

EC = {"TidesDB": "#6FA8DC", "RocksDB": "#B0B0B0"}
EE = {"TidesDB": "#4A7FB5", "RocksDB": "#808080"}

tpcc_rows = [r for r in rows if r["benchmark"] == "TPC-C"]
tpch_rows = [r for r in rows if r["benchmark"] == "TPC-H"]

def safe_float(v):
    try: return float(v) if v else 0
    except: return 0

# ---- TPC-C charts ----
if tpcc_rows:
    engines = []
    seen = set()
    for r in tpcc_rows:
        if r["engine"] not in seen:
            engines.append(r["engine"])
            seen.add(r["engine"])

    # NOPM bar chart
    fig, ax = plt.subplots(figsize=(max(4, len(engines) * 2), 4.5))
    x = np.arange(len(engines))
    nopm_vals = [safe_float(next((r["nopm"] for r in tpcc_rows if r["engine"] == e), 0)) for e in engines]
    bars = ax.bar(x, nopm_vals, 0.5,
        color=[EC.get(e, "#CCC") for e in engines],
        edgecolor=[EE.get(e, "#999") for e in engines],
        linewidth=0.6, zorder=3)
    for bar, v in zip(bars, nopm_vals):
        if v > 0:
            ax.text(bar.get_x() + bar.get_width()/2, bar.get_height(),
                f"{v:,.0f}", ha="center", va="bottom", fontsize=9, fontweight="bold", color="#333")
    ax.set_title("TPC-C: New Order transactions/min (NOPM)  (higher is better)", pad=12)
    ax.set_ylabel("NOPM")
    ax.set_xticks(x)
    ax.set_xticklabels(engines)
    ax.set_axisbelow(True)
    ax.set_ylim(0, max(nopm_vals) * 1.18 if max(nopm_vals) > 0 else 1)
    fig.tight_layout()
    path = os.path.join(out_dir, "chart_tpcc_nopm.png")
    fig.savefig(path); plt.close(fig)
    print(f"  Chart: {path}")

    # TPM bar chart
    fig, ax = plt.subplots(figsize=(max(4, len(engines) * 2), 4.5))
    tpm_vals = [safe_float(next((r["tpm"] for r in tpcc_rows if r["engine"] == e), 0)) for e in engines]
    bars = ax.bar(x, tpm_vals, 0.5,
        color=[EC.get(e, "#CCC") for e in engines],
        edgecolor=[EE.get(e, "#999") for e in engines],
        linewidth=0.6, zorder=3)
    for bar, v in zip(bars, tpm_vals):
        if v > 0:
            ax.text(bar.get_x() + bar.get_width()/2, bar.get_height(),
                f"{v:,.0f}", ha="center", va="bottom", fontsize=9, fontweight="bold", color="#333")
    ax.set_title("TPC-C: Transactions/min (TPM)  (higher is better)", pad=12)
    ax.set_ylabel("TPM")
    ax.set_xticks(x)
    ax.set_xticklabels(engines)
    ax.set_axisbelow(True)
    ax.set_ylim(0, max(tpm_vals) * 1.18 if max(tpm_vals) > 0 else 1)
    fig.tight_layout()
    path = os.path.join(out_dir, "chart_tpcc_tpm.png")
    fig.savefig(path); plt.close(fig)
    print(f"  Chart: {path}")

    # Transaction response times (grouped bar)
    tx_types = ["neword", "payment", "delivery"]
    tx_labels = ["New Order", "Payment", "Delivery"]
    has_timing = any(safe_float(r.get("neword_avg_ms", 0)) > 0 for r in tpcc_rows)
    if has_timing:
        fig, axes = plt.subplots(1, 2, figsize=(10, 4.5))
        for ax_idx, (metric_suffix, title) in enumerate([("avg_ms", "Average response time"), ("p95_ms", "P95 response time")]):
            ax = axes[ax_idx]
            lx = np.arange(len(tx_types))
            width = 0.32
            n = len(engines)
            offsets = np.linspace(-(n-1)*width/2, (n-1)*width/2, n)
            for i, eng in enumerate(engines):
                row = next((r for r in tpcc_rows if r["engine"] == eng), {})
                vals = [safe_float(row.get(f"{t}_{metric_suffix}", 0)) for t in tx_types]
                bars = ax.bar(lx + offsets[i], vals, width, label=eng,
                    color=EC.get(eng, "#CCC"), edgecolor=EE.get(eng, "#999"),
                    linewidth=0.6, zorder=3)
                for bar, v in zip(bars, vals):
                    if v > 0:
                        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height(),
                            f"{v:.1f}", ha="center", va="bottom", fontsize=7, fontweight="bold", color="#333")
            ax.set_title(f"{title} (ms)\n(lower = better)", fontsize=10)
            ax.set_ylabel("Latency (ms)")
            ax.set_xticks(lx)
            ax.set_xticklabels(tx_labels, fontsize=9)
            ax.set_axisbelow(True)
            ymax = ax.get_ylim()[1]
            ax.set_ylim(0, ymax * 1.18)
            if i == 0:
                ax.legend(frameon=True, framealpha=0.9, edgecolor="#CCC", fontsize=9)
        fig.suptitle("TPC-C transaction response times", fontsize=13, fontweight="bold", y=1.02)
        fig.tight_layout()
        path = os.path.join(out_dir, "chart_tpcc_latency.png")
        fig.savefig(path); plt.close(fig)
        print(f"  Chart: {path}")

# ---- TPC-H charts ----
if tpch_rows:
    engines = []
    seen = set()
    for r in tpch_rows:
        if r["engine"] not in seen:
            engines.append(r["engine"])
            seen.add(r["engine"])

    fig, axes = plt.subplots(1, 2, figsize=(10, 4.5))

    # Geometric mean
    ax = axes[0]
    x = np.arange(len(engines))
    geomean_vals = [safe_float(next((r["tpch_geomean_sec"] for r in tpch_rows if r["engine"] == e), 0)) for e in engines]
    bars = ax.bar(x, geomean_vals, 0.5,
        color=[EC.get(e, "#CCC") for e in engines],
        edgecolor=[EE.get(e, "#999") for e in engines],
        linewidth=0.6, zorder=3)
    for bar, v in zip(bars, geomean_vals):
        if v > 0:
            ax.text(bar.get_x() + bar.get_width()/2, bar.get_height(),
                f"{v:.2f}s", ha="center", va="bottom", fontsize=9, fontweight="bold", color="#333")
    ax.set_title("Geometric mean query time\n(lower = better)", fontsize=10)
    ax.set_ylabel("Seconds")
    ax.set_xticks(x)
    ax.set_xticklabels(engines)
    ax.set_axisbelow(True)
    ax.set_ylim(0, max(geomean_vals) * 1.2 if max(geomean_vals) > 0 else 1)

    # Total time
    ax = axes[1]
    total_vals = [safe_float(next((r["tpch_total_sec"] for r in tpch_rows if r["engine"] == e), 0)) for e in engines]
    bars = ax.bar(x, total_vals, 0.5,
        color=[EC.get(e, "#CCC") for e in engines],
        edgecolor=[EE.get(e, "#999") for e in engines],
        linewidth=0.6, zorder=3)
    for bar, v in zip(bars, total_vals):
        if v > 0:
            ax.text(bar.get_x() + bar.get_width()/2, bar.get_height(),
                f"{v:.1f}s", ha="center", va="bottom", fontsize=9, fontweight="bold", color="#333")
    ax.set_title("Total query execution time\n(lower = better)", fontsize=10)
    ax.set_ylabel("Seconds")
    ax.set_xticks(x)
    ax.set_xticklabels(engines)
    ax.set_axisbelow(True)
    ax.set_ylim(0, max(total_vals) * 1.2 if max(total_vals) > 0 else 1)

    fig.suptitle("TPC-H: TidesDB vs RocksDB", fontsize=13, fontweight="bold", y=1.02)
    fig.tight_layout()
    path = os.path.join(out_dir, "chart_tpch.png")
    fig.savefig(path); plt.close(fig)
    print(f"  Chart: {path}")

# ---- Build time chart (all benchmarks) ----
if len(rows) >= 2:
    labels = [f"{r['benchmark']}\n{r['engine']}" for r in rows]
    build_vals = [safe_float(r.get("build_sec", 0)) for r in rows]
    colors = [EC.get(r["engine"], "#CCC") for r in rows]
    edges = [EE.get(r["engine"], "#999") for r in rows]

    fig, ax = plt.subplots(figsize=(max(5, len(rows) * 1.8), 4.5))
    x = np.arange(len(rows))
    bars = ax.bar(x, build_vals, 0.5, color=colors, edgecolor=edges, linewidth=0.6, zorder=3)
    for bar, v in zip(bars, build_vals):
        if v > 0:
            ax.text(bar.get_x() + bar.get_width()/2, bar.get_height(),
                f"{v:.0f}s", ha="center", va="bottom", fontsize=8, fontweight="bold", color="#333")
    ax.set_title("Schema build time  (lower is better)", pad=12)
    ax.set_ylabel("Seconds")
    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=9)
    ax.set_axisbelow(True)
    ax.set_ylim(0, max(build_vals) * 1.18 if max(build_vals) > 0 else 1)
    fig.tight_layout()
    path = os.path.join(out_dir, "chart_build_time.png")
    fig.savefig(path); plt.close(fig)
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
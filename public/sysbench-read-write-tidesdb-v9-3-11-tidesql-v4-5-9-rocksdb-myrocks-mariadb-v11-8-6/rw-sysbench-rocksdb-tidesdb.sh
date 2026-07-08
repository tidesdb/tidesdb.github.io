#!/usr/bin/env bash
#
# rw-sysbench-rocksdb-tidesdb.sh
#
#
set -euo pipefail

MYSQL_SOCKET="${MYSQL_SOCKET:-/tmp/mariadb.sock}"  
MYSQL_HOST="${MYSQL_HOST:-}"                      
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
MYSQL_DB="${MYSQL_DB:-sbtest}"

ENGINES="${ENGINES:-rocksdb tidesdb}"              
TABLES="${TABLES:-4}"
TABLE_SIZE="${TABLE_SIZE:-1000000}"                
THREADS="${THREADS:-512}"
TIME="${TIME:-60}"                                
REPORT_INTERVAL="${REPORT_INTERVAL:-5}"           
WARMUP="${WARMUP:-0}"                             
RAND_TYPE="${RAND_TYPE:-zipfian}"
RAND_ZIPFIAN_EXP="${RAND_ZIPFIAN_EXP:-0.8}"

RAND_SEED="${RAND_SEED:-2024}"

IGNORE_ERRORS="${IGNORE_ERRORS:-1213,1020,1205,1180}"

MARIADB_BIN="${MARIADB_BIN:-/media/agpmastersystem/c794105c-0cd9-4be9-8369-ee6d6e707d68/home/bench/mariadb/bin/mariadb}"
OUTDIR="${OUTDIR:-results/$(date +%Y%m%d_%H%M%S)}"

DATADIR_ROOT="${DATADIR_ROOT:-/media/agpmastersystem/c794105c-0cd9-4be9-8369-ee6d6e707d68/home/bench/mariadb}"
ROCKSDB_DIR="${ROCKSDB_DIR:-$DATADIR_ROOT/data/#rocksdb}"
TIDESDB_DIR="${TIDESDB_DIR:-$DATADIR_ROOT/tidesdb_data}"
DISK_SAMPLE_INTERVAL="${DISK_SAMPLE_INTERVAL:-3}"  

engine_dir(){ case "$1" in
  rocksdb) echo "$ROCKSDB_DIR";;
  tidesdb) echo "$TIDESDB_DIR";;
  *)       echo "";;
esac; }

c_g='\033[0;32m'; c_y='\033[0;33m'; c_r='\033[0;31m'; c_n='\033[0m'
info(){ printf "${c_g}[*]${c_n} %s\n" "$*"; }
warn(){ printf "${c_y}[!]${c_n} %s\n" "$*"; }
die(){  printf "${c_r}[x]${c_n} %s\n" "$*" >&2; exit 1; }
trap 'die "failed at line $LINENO"' ERR

# --plot-only <dir>: skip the benchmark entirely and just (re)generate plots from
# an existing results directory's CSVs. Recovers plots from a run that produced
# its data but never plotted -- e.g. gnuplot was missing at the time, or the tail
# was interrupted. Needs no server.
PLOT_ONLY_DIR=""
if [[ "${1:-}" == "--plot-only" ]]; then
  PLOT_ONLY_DIR="${2:-}"
  [[ -n "$PLOT_ONLY_DIR" ]] || die "usage: $0 --plot-only <results_dir>"
  [[ -d "$PLOT_ONLY_DIR" ]] || die "no such results dir: $PLOT_ONLY_DIR"
  OUTDIR="$PLOT_ONLY_DIR"
fi

if [[ -n "$MYSQL_HOST" ]]; then
  SB_CONN=(--mysql-host="$MYSQL_HOST" --mysql-port="$MYSQL_PORT")
  CLI_CONN=(-h "$MYSQL_HOST" -P "$MYSQL_PORT")
else
  SB_CONN=(--mysql-socket="$MYSQL_SOCKET")
  CLI_CONN=(-S "$MYSQL_SOCKET")
fi
[[ -x "$MARIADB_BIN" ]] || MARIADB_BIN="$(command -v mariadb || command -v mysql || true)"
[[ -n "$MARIADB_BIN" ]] || die "no mariadb/mysql client found (set MARIADB_BIN)"

mysql_cli(){ "$MARIADB_BIN" "${CLI_CONN[@]}" -u "$MYSQL_USER" \
             ${MYSQL_PASSWORD:+-p"$MYSQL_PASSWORD"} --skip-ssl -N "$@"; }

sb(){ sysbench oltp_read_write --db-driver=mysql "${SB_CONN[@]}" \
        --mysql-user="$MYSQL_USER" \
        ${MYSQL_PASSWORD:+--mysql-password="$MYSQL_PASSWORD"} \
        --mysql-db="$MYSQL_DB" \
        --tables="$TABLES" --table-size="$TABLE_SIZE" "$@"; }

if [[ -z "$PLOT_ONLY_DIR" ]]; then
  command -v sysbench >/dev/null || die "sysbench not found in PATH"
  mysql_cli -e "SELECT 1" >/dev/null 2>&1 || die "cannot reach the server (check socket/host/user)"
  mysql_cli -e "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DB\`" >/dev/null
fi
# Surface a missing plotter now -- not silently at the very end after a long run.
command -v gnuplot >/dev/null || \
  warn "gnuplot not on PATH -- plots will be skipped (CSVs still produced). Re-plot later with: $0 --plot-only $OUTDIR"

engine_ok(){ [[ "$(mysql_cli -e "SELECT COUNT(*) FROM information_schema.ENGINES WHERE engine='$1' AND support IN ('YES','DEFAULT')")" == "1" ]]; }
ensure_engine(){
  local e="$1"
  engine_ok "$e" && return 0
  warn "engine '$e' not loaded; attempting INSTALL SONAME 'ha_$e'"
  mysql_cli -e "INSTALL SONAME 'ha_$e'" 2>/dev/null || true
  engine_ok "$e"
}

INTERVALS="$OUTDIR/intervals.csv"
SUMMARY="$OUTDIR/summary.csv"
DISK="$OUTDIR/disk.csv"
PREPARE_CSV="$OUTDIR/prepare_time.csv"
DISKFINAL="$OUTDIR/disk_final.csv"
# Only create the dir and truncate CSV headers on a real run; --plot-only must
# read the existing CSVs, never clobber them.
if [[ -z "$PLOT_ONLY_DIR" ]]; then
  mkdir -p "$OUTDIR"
  echo "engine,time_s,threads,tps,qps,qps_read,qps_write,qps_other,lat95_ms,err_s" > "$INTERVALS"
  echo "engine,threads,table_size,tables,duration_s,total_txn,tps,qps,lat_min_ms,lat_avg_ms,lat_max_ms,lat_95_ms,errors" > "$SUMMARY"
  echo "engine,phase,elapsed_s,bytes,mb" > "$DISK"
  echo "engine,prepare_s,rows,tables" > "$PREPARE_CSV"
  echo "engine,final_bytes,final_mb,rows,bytes_per_row" > "$DISKFINAL"
fi

dir_bytes(){ [[ -d "$1" ]] && du -sB1 "$1" 2>/dev/null | awk '{print $1}' || echo 0; }

disk_sampler(){
  local e="$1" dir="$2" phase_file="$3" start now elapsed bytes phase
  start=$(date +%s.%N)
  while :; do
    now=$(date +%s.%N)
    elapsed=$(awk -v a="$now" -v b="$start" 'BEGIN{printf "%.1f", a-b}')
    bytes=$(dir_bytes "$dir")
    phase=$(cat "$phase_file" 2>/dev/null || echo "?")
    awk -v e="$e" -v p="$phase" -v t="$elapsed" -v b="${bytes:-0}" \
        'BEGIN{printf "%s,%s,%s,%s,%.1f\n", e, p, t, b, b/1048576}' >> "$DISK"
    sleep "$DISK_SAMPLE_INTERVAL"
  done
}

parse_intervals(){
  awk -v e="$1" '
    /^\[[[:space:]]*[0-9]+s[[:space:]]*\]/ {
      ts=$2; sub(/s/,"",ts)
      rwo=$11; sub(/\)$/,"",rwo); split(rwo,a,"/")
      print e","ts","$5","$7","$9","a[1]","a[2]","a[3]","$14","$16
    }' "$2" >> "$INTERVALS"
}
parse_summary(){
  awk -v e="$1" -v thr="$THREADS" -v ts="$TABLE_SIZE" -v tb="$TABLES" -v dur="$TIME" '
    /transactions:/            { total=$2; gsub(/[()]/,"",$3); tps=$3 }
    /^[[:space:]]*queries:/    { gsub(/[()]/,"",$3); qps=$3 }
    /ignored errors:/          { errs=$3 }
    /^[[:space:]]*min:/        { lmin=$2 }
    /^[[:space:]]*avg:/        { lavg=$2 }
    /^[[:space:]]*max:/        { lmax=$2 }
    /95th percentile:/         { l95=$3 }
    END { printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
                 e,thr,ts,tb,dur,total,tps,qps,lmin,lavg,lmax,l95,errs }' "$2" >> "$SUMMARY"
}

run_engine(){
  local e="$1"
  if ! ensure_engine "$e"; then
    warn "engine '$e' unavailable; skipping"
    return 0
  fi
  local dir; dir="$(engine_dir "$e")"
  local rows=$(( TABLES * TABLE_SIZE ))

  info "=== $e : cleanup any leftovers ==="
  sb --mysql-storage-engine="$e" cleanup >/dev/null 2>&1 || true

  local seed_args=(); [[ "$RAND_SEED" -ne 0 ]] && seed_args+=(--rand-seed="$RAND_SEED")

  local phase_file="$OUTDIR/.phase_${e}"
  echo "prepare" > "$phase_file"
  local sampler_pid=""
  if [[ -n "$dir" ]]; then
    disk_sampler "$e" "$dir" "$phase_file" & sampler_pid=$!
  else
    warn "no data dir mapped for '$e'; disk footprint not monitored"
  fi

  info "=== $e : prepare ($TABLES x $TABLE_SIZE rows) ==="
  local t0 t1 prep_s
  t0=$(date +%s.%N)
  sb "${seed_args[@]}" --mysql-storage-engine="$e" --threads="$THREADS" prepare 2>&1 \
     | tee "$OUTDIR/${e}_prepare.log"
  t1=$(date +%s.%N)
  prep_s=$(awk -v a="$t1" -v b="$t0" 'BEGIN{printf "%.2f", a-b}')
  echo "$e,$prep_s,$rows,$TABLES" >> "$PREPARE_CSV"
  info "$e prepare took ${prep_s}s"

  local run_args=(--rand-type="$RAND_TYPE" --mysql-ignore-errors="$IGNORE_ERRORS" "${seed_args[@]}")
  [[ "$RAND_TYPE" == "zipfian" ]] && run_args+=(--rand-zipfian-exp="$RAND_ZIPFIAN_EXP")

  if [[ "$WARMUP" -gt 0 ]]; then
    echo "warmup" > "$phase_file"
    info "=== $e : warmup ${WARMUP}s (discarded) ==="
    sb "${run_args[@]}" --threads="$THREADS" --time="$WARMUP" --report-interval="$REPORT_INTERVAL" run >/dev/null 2>&1 || true
  fi

  echo "run" > "$phase_file"
  info "=== $e : run ${TIME}s @ ${THREADS} threads (rand=${RAND_TYPE}) ==="
  sb "${run_args[@]}" --threads="$THREADS" --time="$TIME" --report-interval="$REPORT_INTERVAL" run \
     2>&1 | tee "$OUTDIR/${e}_run.log"

  if [[ -n "$sampler_pid" ]]; then
    kill "$sampler_pid" 2>/dev/null || true
    wait "$sampler_pid" 2>/dev/null || true
  fi

  parse_intervals "$e" "$OUTDIR/${e}_run.log"
  parse_summary  "$e" "$OUTDIR/${e}_run.log"

  local fb fmb bpr
  fb=$(dir_bytes "$dir")
  fmb=$(awk -v b="${fb:-0}" 'BEGIN{printf "%.1f", b/1048576}')
  bpr=$(awk -v b="${fb:-0}" -v r="$rows" 'BEGIN{printf "%.1f", (r>0)?b/r:0}')
  echo "$e,${fb:-0},$fmb,$rows,$bpr" >> "$DISKFINAL"
  info "$e final on-disk: ${fmb} MB (${bpr} bytes/row over ${rows} rows)"

  rm -f "$phase_file"
  info "=== $e : cleanup ==="
  sb --mysql-storage-engine="$e" cleanup >/dev/null 2>&1 || true
}

engine_color(){ case "$1" in
  tidesdb) echo "#173ACC";; 
  rocksdb) echo "#F3B802";;  
  *)       echo "#888888";;
esac; }

plot_line(){ 
  printf "plot "
  local first=1 e
  for e in $ENGINES; do
    [[ $first -eq 1 ]] || printf ", "
    printf "'< grep \"^%s,\" %s' using 2:%s with linespoints lw 2 pt 7 ps 0.7 lc rgb '%s' title '%s'" \
           "$e" "$INTERVALS" "$1" "$(engine_color "$e")" "$e"
    first=0
  done
  echo ""
}

disk_plot_elems(){
  printf "plot "
  local first=1 e c
  for e in $ENGINES; do
    c="$(engine_color "$e")"
    [[ $first -eq 1 ]] || printf ", "
    printf "'< grep \"^%s,prepare,\" %s' using 3:5 with lines lw 2 dt 2 lc rgb '%s' title '%s prepare'" \
           "$e" "$DISK" "$c" "$e"
    printf ", '< grep \"^%s,run,\" %s' using 3:5 with lines lw 2 lc rgb '%s' title '%s run'" \
           "$e" "$DISK" "$c" "$e"
    first=0
  done
  echo ""
}

build_bars(){  
  local csv="$1" col="$2" out="$3" i=0 e v hex dec
  : > "$out"
  for e in $ENGINES; do
    v=$(awk -F, -v e="$e" -v c="$col" '$1==e{print $c}' "$csv")
    [[ -z "$v" ]] && continue
    hex="$(engine_color "$e")"; dec=$((16#${hex#\#}))
    echo "$i $e $v $dec" >> "$out"
    i=$((i+1))
  done
  echo "$i" 
}

make_plots(){
  command -v gnuplot >/dev/null || { warn "gnuplot not found; skipping plots (CSVs are in $OUTDIR)"; return 0; }
  local prep_bars="$OUTDIR/bars_prepare.dat" disk_bars="$OUTDIR/bars_diskfinal.dat"
  local nprep ndisk
  nprep=$(build_bars "$PREPARE_CSV" 2 "$prep_bars")
  ndisk=$(build_bars "$DISKFINAL"   3 "$disk_bars")
  local gp="$OUTDIR/plot.gp"
  {
    echo "set datafile separator ','"
    echo "set terminal pngcairo size 1100,600 font ',11'"
    echo "set grid lc rgb '#dddddd'; set border lc rgb '#666666'"
    echo "set key top right; set xlabel 'time (s)'"
    echo "set output '$OUTDIR/tps_over_time.png'"
    echo "set title 'sysbench oltp\\_read\\_write - transactions/sec (higher is better)'"
    echo "set ylabel 'transactions/sec'"
    plot_line 4
    echo "set output '$OUTDIR/qps_over_time.png'"
    echo "set title 'sysbench oltp\\_read\\_write - queries/sec (higher is better)'"
    echo "set ylabel 'queries/sec'"
    plot_line 5
    echo "set output '$OUTDIR/lat95_over_time.png'"
    echo "set title 'sysbench oltp\\_read\\_write - p95 latency (lower is better)'"
    echo "set ylabel 'p95 latency (ms)'"
    plot_line 9

    echo "set output '$OUTDIR/disk_over_time.png'"
    echo "set title 'on-disk footprint over time (prepare dashed, run solid)'"
    echo "set xlabel 'elapsed since prepare start (s)'"
    echo "set ylabel 'data directory size (MB)'"
    echo "set key top left"
    disk_plot_elems

    echo "set style fill solid 0.85 border -1"
    echo "set boxwidth 0.6"
    echo "unset key"
    echo "set xlabel ''"
    echo "set datafile separator whitespace"

    if [[ "$nprep" -gt 0 ]]; then
      echo "set output '$OUTDIR/prepare_time.png'"
      echo "set title 'prepare time (lower is better)'"
      echo "set ylabel 'prepare time (s)'"
      echo "set yrange [0:*]"; echo "set xrange [-0.7:$((nprep>0?nprep-1:1)).7]"
      echo "plot '$prep_bars' using 1:3:4:xtic(2) with boxes lc rgb variable notitle, \\"
      echo "     '' using 1:3:(sprintf('%.1f s',\$3)) with labels offset 0,0.8 font ',10' notitle"
    fi

    if [[ "$ndisk" -gt 0 ]]; then
      echo "set output '$OUTDIR/disk_final.png'"
      echo "set title 'final on-disk footprint after run (lower is better)'"
      echo "set ylabel 'data directory size (MB)'"
      echo "set yrange [0:*]"; echo "set xrange [-0.7:$((ndisk>0?ndisk-1:1)).7]"
      echo "plot '$disk_bars' using 1:3:4:xtic(2) with boxes lc rgb variable notitle, \\"
      echo "     '' using 1:3:(sprintf('%.0f MB',\$3)) with labels offset 0,0.8 font ',10' notitle"
    fi
  } > "$gp"
  gnuplot "$gp" && info "plots written: tps/qps/lat95_over_time.png, disk_over_time.png, prepare_time.png, disk_final.png (in $OUTDIR)"
}

info "output: $OUTDIR"
if [[ -z "$PLOT_ONLY_DIR" ]]; then
  info "config: engines='$ENGINES' tables=$TABLES table_size=$TABLE_SIZE threads=$THREADS time=${TIME}s interval=${REPORT_INTERVAL}s rand=$RAND_TYPE seed=$RAND_SEED retry_on=$IGNORE_ERRORS"
  info "disk monitor: interval=${DISK_SAMPLE_INTERVAL}s  rocksdb='$ROCKSDB_DIR'  tidesdb='$TIDESDB_DIR'"
  for e in $ENGINES; do
    run_engine "$e"
  done
else
  info "plot-only: regenerating plots from CSVs in $OUTDIR"
fi

trap - ERR
echo
info "=== summary ==="
column -t -s, "$SUMMARY" 2>/dev/null || cat "$SUMMARY"
make_plots
echo
info "=== prepare time & final footprint ==="
column -t -s, "$PREPARE_CSV" 2>/dev/null || cat "$PREPARE_CSV"
echo
column -t -s, "$DISKFINAL" 2>/dev/null || cat "$DISKFINAL"
echo
info "done. artifacts in: $OUTDIR"
info "  intervals.csv     - per-${REPORT_INTERVAL}s samples (engine,time_s,threads,tps,qps,...,lat95_ms,err_s)"
info "  summary.csv       - one row per engine (final tps/qps/latency)"
info "  disk.csv          - per-${DISK_SAMPLE_INTERVAL}s footprint samples (engine,phase,elapsed_s,bytes,mb)"
info "  prepare_time.csv  - prepare wall-clock per engine"
info "  disk_final.csv    - end-of-run footprint per engine (MB, bytes/row)"
info "  *_run.log         - raw sysbench output"

#!/usr/bin/env bash
set -u
SB=/media/agpmastersystem/c794105c-0cd9-4be9-8369-ee6d6e707d68/home/development/sysbench-bench
HOST=127.0.0.1; PORT=3306; DBUSER=root; PASS=maria; DB=sbtest

ENGINES=${ENGINES:-"innodb tidesdb"}
WORKLOADS=${WORKLOADS:-"oltp_point_select oltp_read_only oltp_write_only oltp_read_write oltp_update_index oltp_update_non_index oltp_insert oltp_delete select_random_points select_random_ranges"}
THREADS=${THREADS:-"1 8 16 32"}
TABLES=${TABLES:-16}
TABLE_SIZE=${TABLE_SIZE:-3125000}   # 16 x 3.125M ~= 50M rows ~= 10GB logical (exceeds 8G cache)
TIME=${TIME:-20}
WARMUP=${WARMUP:-3}
FRESH=${FRESH:-1}
IGNORE=${IGNORE:-"1180,1213,1205"}   # retry commit-time conflict (1180 wraps handler 149), deadlock, lock-wait so repeatable-read conflicts don't abort a point
RESULTS=$SB/results
SUMMARY=$RESULTS/summary.tsv
mkdir -p "$RESULTS"

CONN="--db-driver=mysql --mysql-host=$HOST --mysql-port=$PORT --mysql-user=$DBUSER --mysql-password=$PASS --mysql-db=$DB"
SHAPE="--tables=$TABLES --table-size=$TABLE_SIZE"

echo ">>> sysbench sweep  engines=[$ENGINES]  workloads=[$WORKLOADS]  threads=[$THREADS]  ${TABLES}x${TABLE_SIZE} rows  time=${TIME}s"

# server up + db present
"$SB/server.sh" status >/dev/null 2>&1 || { echo ">>> starting server"; "$SB/server.sh" start || exit 1; }
"$SB/server.sh" client -e "CREATE DATABASE IF NOT EXISTS $DB;" >/dev/null 2>&1

[ -s "$SUMMARY" ] || printf "engine\tworkload\tthreads\ttps\tqps\tp95_ms\n" > "$SUMMARY"

# pull "(N per sec.)" from a "transactions:" / "queries:" line
persec() { grep -oE "$1:[^(]*\([0-9.]+ per sec" | grep -oE "[0-9.]+ per sec" | grep -oE "^[0-9.]+" | head -1; }

for eng in $ENGINES; do
  if [ "$FRESH" = "1" ]; then
    echo ">>> engine=$eng: cleanup + prepare ${TABLES}x${TABLE_SIZE} (engine=$eng)"
    sysbench oltp_read_write $CONN $SHAPE --mysql-storage-engine=$eng cleanup >/dev/null 2>&1
    sysbench oltp_read_write $CONN $SHAPE --mysql-storage-engine=$eng --threads=8 prepare >"$RESULTS/prepare_$eng.log" 2>&1 \
      || { echo "!!! prepare failed for $eng, see $RESULTS/prepare_$eng.log"; tail -3 "$RESULTS/prepare_$eng.log"; continue; }
  fi
  for wl in $WORKLOADS; do
    for t in $THREADS; do
      out=$(sysbench "$wl" $CONN $SHAPE --threads=$t --time=$TIME --warmup-time=$WARMUP --mysql-ignore-errors=$IGNORE --report-interval=0 run 2>&1)
      tps=$(echo "$out" | persec "transactions"); qps=$(echo "$out" | persec "queries")
      p95=$(echo "$out" | grep -oE "95th percentile:[[:space:]]*[0-9.]+" | grep -oE "[0-9.]+$" | head -1)
      printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$eng" "$wl" "$t" "${tps:-0}" "${qps:-0}" "${p95:-0}" | tee -a "$SUMMARY"
    done
  done
  [ "$FRESH" = "1" ] && sysbench oltp_read_write $CONN $SHAPE --mysql-storage-engine=$eng cleanup >/dev/null 2>&1
done
echo ">>> done. results in $SUMMARY"

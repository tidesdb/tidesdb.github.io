#!/usr/bin/env bash
# Per-run sampler: engine counters + process RSS + cgroup memory, one row/interval.
#   sample.sh <outfile> <engine> [interval]
set -uo pipefail
OUT=$1; ENG=$2; INT=${3:-1}
M="/data/mariadb/bin/mariadb -uroot --socket=/tmp/mariadb.sock --skip-ssl"
TDB=(Tidesdb_write_stall_ceiling_hits Tidesdb_writes_throttled Tidesdb_writes_blocked
     Tidesdb_write_stall_us Tidesdb_stall_admission Tidesdb_stall_rotate_lock
     Tidesdb_stall_rotate_work Tidesdb_stall_wal_append Tidesdb_stall_manifest_commit
     Tidesdb_open_sstables Tidesdb_flush_pending Tidesdb_compaction_queue
     Tidesdb_immutable_memtables Tidesdb_flush_count Tidesdb_compaction_count
     Tidesdb_flush_bytes_written Tidesdb_compaction_bytes_written Tidesdb_compaction_bytes_read)
INN=(Innodb_buffer_pool_wait_free Innodb_log_waits Innodb_os_log_pending_fsyncs
     Innodb_data_pending_reads Innodb_data_pending_writes Innodb_row_lock_waits
     Innodb_row_lock_time Innodb_buffer_pool_pages_dirty Innodb_buffer_pool_read_requests
     Innodb_buffer_pool_reads Innodb_data_reads Innodb_data_writes Innodb_dblwr_writes)
if [ "$ENG" = tidesdb ]; then VARS=("${TDB[@]}"); LIKE='Tidesdb\_%'; else VARS=("${INN[@]}"); LIKE='Innodb\_%'; fi
printf 'ts,rss_kb,cg_mem_bytes,%s\n' "$(IFS=,; echo "${VARS[*]}")" > "$OUT"
while :; do
    row=$($M -N -B -e "SHOW GLOBAL STATUS LIKE '$LIKE'" 2>/dev/null) || { sleep "$INT"; continue; }
    pid=$(pgrep -x mariadbd | head -1)
    rss=$(awk '/VmRSS/{print $2}' /proc/$pid/status 2>/dev/null)
    cg=$(cat /sys/fs/cgroup/$(awk -F: '{print $3}' /proc/$pid/cgroup 2>/dev/null | head -1)/memory.current 2>/dev/null)
    vals=$(awk -v want="$(IFS=,; echo "${VARS[*]}")" '
        BEGIN{n=split(want,W,",")} {V[$1]=$2}
        END{o=""; for(i=1;i<=n;i++) o=o (i>1?",":"") (W[i] in V ? V[W[i]] : ""); print o}' <<<"$row")
    printf '%s,%s,%s,%s\n' "$(date +%s)" "${rss:-}" "${cg:-}" "$vals" >> "$OUT"
    sleep "$INT"
done

#!/usr/bin/env bash
#
# benchmark.sh - Fair build-time comparison: TidesDB vs RocksDB
#
# Measures ONLY the time to compile each project's core static library, from a
# clean build tree, all cores, Release. Clones are NOT timed. Configure (cmake
# generate) is NOT timed. We time only `cmake --build --target <lib>`.
#
# Decisions (see README.md for rationale):
#   * Scope     : core library target only  (tidesdb / rocksdb), nothing else
#   * Artifact  : STATIC lib for both       (removes shared-vs-static asymmetry)
#   * Build type: Release for both
#   * Parallel  : -j$(nproc) for both       (override with JOBS=1 for raw work)
#   * Runs      : 3, median reported         (fresh build tree each run)
#   * Flags     : each project keeps its own defaults (e.g. RocksDB -march=native)
#
# Everything below is env-overridable, e.g.:
#   RUNS=5 JOBS=1 GENERATOR="Unix Makefiles" ./benchmark.sh
#
set -euo pipefail

# configuration
TIDESDB_TAG=${TIDESDB_TAG:-v9.3.6}
ROCKSDB_TAG=${ROCKSDB_TAG:-v11.1.1}
RUNS=${RUNS:-3}
JOBS=${JOBS:-$(nproc)}
GENERATOR=${GENERATOR:-Ninja}
BUILD_TYPE=${BUILD_TYPE:-Release}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS="$ROOT/repos"
RESULTS="$ROOT/results"
LOGS="$RESULTS/logs"
CSV="$RESULTS/build_times.csv"
META="$RESULTS/environment.txt"

# helpers
c_blue='\033[1;34m'; c_dim='\033[2m'; c_grn='\033[1;32m'; c_rst='\033[0m'
log()  { printf "${c_blue}==>${c_rst} %s\n" "$*"; }
sub()  { printf "${c_dim}    %s${c_rst}\n" "$*"; }
die()  { printf "\033[1;31mERROR:${c_rst} %s\n" "$*" >&2; exit 1; }
now()  { date +%s.%N; }
secs() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.3f", b-a}'; }   # b - a

# clone a tag shallowly if not already present (NOT timed)
clone_repo() {
  local url="$1" tag="$2" dir="$3"
  if [ -d "$dir/.git" ]; then
    sub "already cloned: $(basename "$dir") @ $tag"
  else
    log "Cloning $(basename "$dir") @ $tag (not timed)"
    git clone --quiet --depth 1 --branch "$tag" "$url" "$dir" \
      || die "clone failed for $url @ $tag"
  fi
}

# bench <name> <src_dir> <target> <extra cmake args...>
# Re-configures + rebuilds from scratch RUNS times; times only the build step.
bench() {
  local name="$1" src="$2" target="$3"; shift 3
  local extra=("$@")
  local build="$src/_bench_build"

  log "Benchmarking ${name}  (target: ${target}, ${RUNS} run(s), -j${JOBS}, ${BUILD_TYPE})"
  for run in $(seq 1 "$RUNS"); do
    rm -rf "$build"
    # configure (NOT timed)
    cmake -S "$src" -B "$build" -G "$GENERATOR" \
          -DCMAKE_BUILD_TYPE="$BUILD_TYPE" "${extra[@]}" \
          > "$LOGS/${name}_configure_run${run}.log" 2>&1 \
      || { cat "$LOGS/${name}_configure_run${run}.log"; die "$name configure failed"; }

    sync   # flush dirty pages so each run starts comparably (page cache stays warm)

    # build the library target (TIMED)
    local t0 t1 elapsed
    t0="$(now)"
    cmake --build "$build" --target "$target" -j "$JOBS" \
          > "$LOGS/${name}_build_run${run}.log" 2>&1 \
      || { tail -n 40 "$LOGS/${name}_build_run${run}.log"; die "$name build failed"; }
    t1="$(now)"

    elapsed="$(secs "$t0" "$t1")"
    printf "%s,%d,%s\n" "$name" "$run" "$elapsed" >> "$CSV"
    sub "run ${run}/${RUNS}: ${elapsed}s"
  done
}

# print median of the runs for a project (reads CSV)
median_of() {
  local name="$1"
  awk -F, -v n="$name" '$1==n{print $3}' "$CSV" | sort -n | awk '
    {a[NR]=$1}
    END{ if(NR==0){print "n/a"; exit}
         if(NR%2){printf "%.3f", a[(NR+1)/2]}
         else    {printf "%.3f", (a[NR/2]+a[NR/2+1])/2} }'
}

# main
command -v git   >/dev/null || die "git not found"
command -v cmake >/dev/null || die "cmake not found"
if [ "$GENERATOR" = "Ninja" ]; then command -v ninja >/dev/null || die "ninja not found (or set GENERATOR=\"Unix Makefiles\")"; fi

mkdir -p "$REPOS" "$LOGS"
echo "project,run,seconds" > "$CSV"

# record environment for reproducibility / the article
{
  echo "Build-time benchmark environment"
  echo "date            : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "host kernel     : $(uname -srm)"
  echo "cpu cores       : $(nproc)"
  echo "memory          : $(free -h 2>/dev/null | awk '/^Mem:/{print $2}')"
  echo "cmake           : $(cmake --version | head -1)"
  echo "generator       : $GENERATOR"
  command -v ninja >/dev/null && echo "ninja           : $(ninja --version)"
  echo "cc              : $(${CC:-cc} --version | head -1)"
  echo "cxx             : $(${CXX:-c++} --version | head -1)"
  echo "build type      : $BUILD_TYPE"
  echo "parallel jobs   : $JOBS"
  echo "runs (median)   : $RUNS"
  echo "tidesdb tag     : $TIDESDB_TAG"
  echo "rocksdb tag     : $ROCKSDB_TAG"
  echo "scope           : core static library target only (tidesdb / rocksdb)"
} | tee "$META"
echo

# 1. clone (not timed)
clone_repo "https://github.com/tidesdb/tidesdb.git"  "$TIDESDB_TAG" "$REPOS/tidesdb"
clone_repo "https://github.com/facebook/rocksdb.git" "$ROCKSDB_TAG" "$REPOS/rocksdb"
echo

# 2. benchmark each (force STATIC lib for an apples-to-apples artifact)
bench "tidesdb" "$REPOS/tidesdb" "tidesdb" \
      -DBUILD_SHARED_LIBS=OFF
echo
bench "rocksdb" "$REPOS/rocksdb" "rocksdb" \
      -DROCKSDB_BUILD_SHARED=OFF \
      -DFAIL_ON_WARNINGS=OFF
# FAIL_ON_WARNINGS=OFF drops RocksDB's default -Werror. Necessary: GCC 12 emits a
# spurious -Wrestrict in options_type.h that aborts the stock build. Also fairer --
# TidesDB's default build has no -Werror. It changes neither what is compiled nor
# the optimization level, so the measured build time is unaffected.
echo

# 3. summary
tds_med="$(median_of tidesdb)"; rdb_med="$(median_of rocksdb)"
log "Median build time (lower is faster)"
printf "    ${c_grn}TidesDB %s${c_rst}  : %ss\n" "$TIDESDB_TAG" "$tds_med"
printf "    ${c_grn}RocksDB %s${c_rst}  : %ss\n" "$ROCKSDB_TAG" "$rdb_med"
if awk -v t="$tds_med" -v r="$rdb_med" 'BEGIN{exit !(t>0 && r>0)}'; then
  ratio="$(awk -v t="$tds_med" -v r="$rdb_med" 'BEGIN{printf "%.1f", r/t}')"
  sub "RocksDB takes ~${ratio}x as long as TidesDB to build its core library."
fi
echo
sub "raw timings : $CSV"
sub "environment : $META"
sub "build logs  : $LOGS/"

# 4. plot
if command -v python3 >/dev/null; then
  log "Plotting -> $RESULTS/build_comparison.png"
  python3 "$ROOT/plot.py" "$CSV" "$RESULTS/build_comparison.png" "$TIDESDB_TAG" "$ROCKSDB_TAG" \
    && sub "wrote $RESULTS/build_comparison.png" \
    || sub "plot skipped (see error above)"
else
  sub "python3 not found - skipping plot"
fi

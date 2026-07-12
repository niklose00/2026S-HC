#!/usr/bin/env bash
# Build + Mess-Sweeps fuer Aufgabe 2 (Speicherbandbreite & Latenz) unter WSL2.
# Aufruf aus dem aufgabe2-Verzeichnis:
#   wsl -d Ubuntu -- bash -lc "cd '/mnt/c/.../Ueb2/aufgabe2' && bash run_wsl.sh"
set -e

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$HOME/ueb2a2-build"
mkdir -p "$WORK"
cp "$SRC_DIR/src/bandwidth_bench.cu" "$WORK/bandwidth_bench.cu"

echo "=== build ==="
nvcc -O3 -arch=sm_86 -Xcompiler -fopenmp -o "$WORK/bandwidth_bench" "$WORK/bandwidth_bench.cu"

BIN="$WORK/bandwidth_bench"
mkdir -p "$SRC_DIR/results"
E1="$SRC_DIR/results/e1_patterns.csv"
E2="$SRC_DIR/results/e2_stride.csv"
E3="$SRC_DIR/results/e3_occupancy.csv"
rm -f "$E1" "$E2" "$E3"

NG=67108864   # 2^26 GPU-Elemente (256 MB/Array)
NC=16777216   # 2^24 CPU-Elemente

echo "=== E1: Bandbreite nach Zugriffsmuster ==="
"$BIN" --mode coalesced --n $NG --block 256 --reps 10 --check --header >> "$E1"
"$BIN" --mode strided   --n $NG --stride 8 --block 256 --reps 10 --check >> "$E1"
"$BIN" --mode gather    --n $NG --block 256 --reps 10 --check >> "$E1"
"$BIN" --mode cpu-seq       --n $NC --reps 3 --check >> "$E1"
"$BIN" --mode cpu-rand      --n $NC --reps 2 --check >> "$E1"
"$BIN" --mode cpu-omp-seq   --n $NC --reps 3 --check >> "$E1"
"$BIN" --mode cpu-omp-rand  --n $NC --reps 2 --check >> "$E1"

echo "=== E2: Bandbreite ueber Stride ==="
first=1
for s in 1 2 4 8 16 32 64 128; do
  [ $first -eq 1 ] && hdr="--header" || hdr=""
  "$BIN" --mode strided --n $NG --stride $s --block 256 --reps 10 --check $hdr >> "$E2"
  first=0
done

echo "=== E3: Bandbreite ueber Occupancy (Bloecke/SM) ==="
first=1
for bps in 1 2 3 4 5 6; do
  [ $first -eq 1 ] && hdr="--header" || hdr=""
  "$BIN" --mode coalesced --n $NG --block 256 --bps $bps --reps 10 --check $hdr >> "$E3"
  first=0
done

echo "=== E1 ==="; cat "$E1"
echo "=== E2 ==="; cat "$E2"
echo "=== E3 ==="; cat "$E3"
echo "=== DONE ==="

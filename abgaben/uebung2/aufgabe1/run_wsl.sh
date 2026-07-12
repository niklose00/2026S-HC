#!/usr/bin/env bash
# Build + Mess-Sweeps unter Linux/WSL2 (Linux-nvcc umgeht das Windows-OS-Gate
# des nativen nvcc; die RTX 3070 ist ueber den WSL-GPU-Passthrough nutzbar).
#
# Aufruf aus dem Projektverzeichnis heraus, z. B.:
#   wsl -d Ubuntu -- bash -lc "cd '/mnt/c/.../Ueb2' && bash run_wsl.sh"
#
# Der Bau erfolgt in einem WSL-lokalen Verzeichnis (schneller und ohne Probleme
# mit Leerzeichen/Umlauten im /mnt/c-Pfad); die CSVs werden nach ./results
# zurueckgeschrieben.
set -e

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$HOME/ueb2-build"
mkdir -p "$WORK"
cp "$SRC_DIR/src/divergence_bench.cu" "$WORK/divergence_bench.cu"

echo "=== build (nvcc -arch=sm_86 -Xcompiler -fopenmp) ==="
nvcc -O3 -arch=sm_86 -Xcompiler -fopenmp -o "$WORK/divergence_bench" "$WORK/divergence_bench.cu"

BIN="$WORK/divergence_bench"
mkdir -p "$SRC_DIR/results"
E1="$SRC_DIR/results/e1_scaling.csv"
E2="$SRC_DIR/results/e2_divergence.csv"
rm -f "$E1" "$E2"

echo "=== E1: Skalierung ueber n (d=1, k=4096) ==="
first=1
for n in 1024 4096 16384 65536 262144 1048576 4194304 16777216 67108864; do
  [ $first -eq 1 ] && hdr="--header" || hdr=""
  "$BIN" --mode gpu-intra --n $n --k 4096 --d 1 --reps 10 --check $hdr >> "$E1"
  first=0
done
for n in 1024 4096 16384 65536 262144 1048576 4194304; do
  "$BIN" --mode cpu-omp --n $n --k 4096 --d 1 --reps 3 --check >> "$E1"
done
for n in 1024 4096 16384 65536 262144 1048576; do
  "$BIN" --mode cpu --n $n --k 4096 --d 1 --reps 3 --check >> "$E1"
done

echo "=== E2: Divergenz-Sweep (n=16M, k=4096) ==="
first=1
for d in 1 2 4 8 16 32; do
  [ $first -eq 1 ] && hdr="--header" || hdr=""
  "$BIN" --mode gpu-intra --n 16777216 --k 4096 --d $d --reps 10 --check $hdr >> "$E2"
  first=0
done
for d in 1 2 4 8 16 32; do
  "$BIN" --mode gpu-warpuniform --n 16777216 --k 4096 --d $d --reps 10 --check >> "$E2"
done
for d in 1 2 4 8 16 32; do
  "$BIN" --mode cpu-omp --n 16777216 --k 4096 --d $d --reps 2 --check >> "$E2"
done

echo "Fertig: $E1, $E2"

# Speicherbandbreite & Latenz-Verstecken (Übungsblatt 2, Aufgabe 2)

Speicherintensiver CUDA-Benchmark, der zeigt, wie das Zugriffsmuster über die
erreichte Bandbreite entscheidet und wie die GPU Speicherlatenz über viele
gleichzeitige Warps versteckt. Ergebnisse und Diskussion: [gemeinsamer Bericht](../HC_2.pdf).

## Voraussetzungen

- NVIDIA-GPU (gemessen: GeForce RTX 3070, SM 8.6) + CUDA Toolkit
- Python 3 + matplotlib für die Plots

## Verwendung

Gemessen wurde unter **WSL2** (Linux-`nvcc`); Begründung siehe
[../README.md](../README.md).

```bash
# in WSL2, aus diesem Verzeichnis:
bash run_wsl.sh    # baut src/bandwidth_bench.cu und schreibt results/*.csv
python3 plot.py    # results/*.csv -> plots/*.png
```

Einzelmessung:

```bash
./bandwidth_bench --mode coalesced --n 67108864 --block 256 --reps 10 --check --header
```

| Option | Bedeutung |
|---|---|
| `--mode` | `coalesced` (Stride 1), `strided` (Stride k), `gather` (zufällig), `cpu-seq`, `cpu-rand`, `cpu-omp-seq`, `cpu-omp-rand` |
| `--n` | Problemgröße (Elemente) |
| `--stride` | Stride k für das strided-Muster (muss n teilen) |
| `--block` | Blockgröße (Threads pro Block) |
| `--bps` | residente Blöcke pro SM (0 = volle Occupancy); steuert die Zahl gleichzeitiger Warps |
| `--reps` | Messwiederholungen (Median) |
| `--check` | Korrektheitscheck gegen CPU-Referenz |
| `--header` | CSV-Kopfzeile ausgeben |

Ausgabe (stdout, CSV): `mode,n,stride,block,bps,warps_per_sm,occ_pct,time_ms,gb_s,check`.
Effektive Bandbreite = 8·n / t (a gelesen + b geschrieben); Peak-Bandbreite und
Occupancy werden nach stderr geloggt.

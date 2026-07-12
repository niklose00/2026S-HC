# SIMT & Warp-Divergenz Benchmark (Übungsblatt 2, Aufgabe 1)

Rechenintensiver CUDA-Benchmark, der das SIMT-Ausführungsmodell und die Kosten
von Warp-Divergenz sichtbar macht. Ergebnisse und Diskussion: [gemeinsamer Bericht](../HC_2.pdf).

## Voraussetzungen

- NVIDIA-GPU (gemessen: GeForce RTX 3070, SM 8.6) + CUDA Toolkit
- Python 3 + matplotlib für die Plots

## Verwendung

Gemessen wurde unter **WSL2** (Linux-`nvcc`), weil der native Windows-`nvcc` auf
dem Testrechner mit `Host compiler targets unsupported OS` abbricht (der aktuelle
Windows-Build wird von keiner installierten CUDA-Version akzeptiert). Die RTX 3070
ist über den WSL-GPU-Passthrough voll nutzbar:

```bash
# in WSL2, aus dem Projektverzeichnis:
bash run_wsl.sh    # baut src/divergence_bench.cu und schreibt results/*.csv
python3 plot.py    # results/*.csv -> plots/*.png
```

Auf einer Maschine mit funktionierendem Windows-`nvcc` bauen stattdessen
`./build.ps1` und `./run_all.ps1` dieselben CSVs (siehe `build.ps1` — findet CUDA
und den MSVC-Host-Compiler automatisch).

```powershell
./build.ps1        # kompiliert src/divergence_bench.cu -> divergence_bench.exe
./run_all.ps1      # beide Mess-Sweeps -> results/*.csv (dauert einige Minuten)
python plot.py     # results/*.csv -> plots/*.png
```

Einzelmessung:

```powershell
./divergence_bench.exe --mode gpu-intra --n 16777216 --k 4096 --d 8 --reps 10 --check --header
```

| Option | Bedeutung |
|---|---|
| `--mode` | `gpu-intra` (Divergenz im Warp), `gpu-warpuniform` (Kontrolle: Verzweigung warp-einheitlich), `cpu`, `cpu-omp` |
| `--n` | Problemgröße (1 Element = 1 Thread) |
| `--k` | Arithmetik-Iterationen (FMA-Kette) pro Element |
| `--d` | Divergenzgrad: Anzahl verschiedener Pfade, 1–32 |
| `--reps` | Messwiederholungen (Median wird ausgegeben) |
| `--check` | Stichproben-Korrektheitscheck gegen skalare CPU-Referenz |
| `--header` | CSV-Kopfzeile mit ausgeben |

Ausgabe (stdout, CSV): `mode,n,k,d,time_ms,gflops,check` — GPU-Zeit ist reine
Kernel-Zeit (`cudaEvent`), Transfers sind nicht enthalten; 3 Warm-up-Läufe vor
jeder Messung.

# Übungsblatt 2 — GPU-Ausführungsmodell (SIMT & Speicher)

Lösung zu Aufgabenblatt 2. Zwei CUDA-Benchmarks, die zentrale Eigenschaften der
GPU-Ausführung messbar machen. Der zusammenfassende **Ergebnisbericht** liegt in
[HC_2.pdf](HC_2.pdf).

| Ordner | Thema | Kurzbeschreibung |
|---|---|---|
| [aufgabe1/](aufgabe1/) | SIMT & Warp-Divergenz | Rechenintensiver Kernel, der die Kosten divergenter Verzweigungen innerhalb eines Warps sichtbar macht. |
| [aufgabe2/](aufgabe2/) | Speicherbandbreite & Latenz-Verstecken | Speicherintensiver Kernel; Einfluss des Zugriffsmusters auf die Bandbreite und Latenzverdeckung über gleichzeitige Warps. |

Details zu Bau, Ausführung und den einzelnen Optionen stehen in den READMEs der
jeweiligen Unterordner.

## Messumgebung / WSL2

Gemessen wurde auf einer **GeForce RTX 3070 (SM 8.6)** unter **WSL2** mit dem
Linux-`nvcc`, weil der native Windows-`nvcc` auf dem Testrechner mit
`Host compiler targets unsupported OS` abbricht (der aktuelle Windows-Build wird
von keiner installierten CUDA-Version akzeptiert). Die GPU ist über den
WSL-GPU-Passthrough voll nutzbar. Für Aufgabe 1 existiert zusätzlich ein
Windows-Pfad (`build.ps1` / `run_all.ps1`) für Rechner mit funktionierendem
Windows-`nvcc`.

```bash
# in WSL2, jeweils aus dem Aufgaben-Unterordner:
bash run_wsl.sh    # baut src/*.cu und schreibt results/*.csv
python3 plot.py    # results/*.csv -> plots/*.png
```

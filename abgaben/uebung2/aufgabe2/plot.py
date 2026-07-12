# Erzeugt plots/*.png aus results/*.csv fuer Aufgabe 2 (Speicherbandbreite).
import csv
import os
from collections import defaultdict

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "results")
OUT = os.path.join(HERE, "plots")
os.makedirs(OUT, exist_ok=True)

PEAK_GBS = 448.0  # RTX 3070: 2 * 7001 MHz * 256 bit / 8 (theoretische GDDR6-Bandbreite)

# Referenzpalette
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
MUTED = "#898781"
GRID = "#e1e0d9"
BLUE = "#2a78d6"
AQUA = "#1baf7a"
YELLOW = "#eda100"
RED = "#d1495b"

plt.rcParams.update({
    "font.family": "Segoe UI",
    "text.color": INK,
    "axes.edgecolor": "#c3c2b7",
    "axes.labelcolor": MUTED,
    "xtick.color": MUTED,
    "ytick.color": MUTED,
    "axes.grid": True,
    "grid.color": GRID,
    "grid.linewidth": 0.8,
    "axes.axisbelow": True,
    "figure.facecolor": SURFACE,
    "axes.facecolor": SURFACE,
    "savefig.facecolor": SURFACE,
    "legend.frameon": False,
})


def read_rows(name):
    with open(os.path.join(RES, name), newline="") as f:
        return list(csv.DictReader(f))


def style_axes(ax):
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)


# ---- Plot 1: Bandbreite nach Zugriffsmuster (Balken, log) -------------------
rows = read_rows("e1_patterns.csv")
bw = {r["mode"]: float(r["gb_s"]) for r in rows}
labels = ["coalesced\n(GPU)", "strided k=8\n(GPU)", "gather\n(GPU)",
          "seq 1T\n(CPU)", "rand 1T\n(CPU)", "seq 16T\n(CPU)", "rand 16T\n(CPU)"]
keys = ["coalesced", "strided", "gather",
        "cpu-seq", "cpu-rand", "cpu-omp-seq", "cpu-omp-rand"]
colors = [BLUE, YELLOW, RED, MUTED, MUTED, MUTED, MUTED]
vals = [bw.get(k, 0.0) for k in keys]

fig, ax = plt.subplots(figsize=(9, 5), dpi=150)
bars = ax.bar(labels, vals, color=colors, width=0.7)
ax.axhline(PEAK_GBS, ls="--", lw=1.2, color=INK)
ax.annotate(f"Geräte-Peak {PEAK_GBS:.0f} GB/s", (len(labels) - 1, PEAK_GBS),
            xytext=(0, 4), textcoords="offset points", ha="right", va="bottom",
            fontsize=9, color=INK)
ax.set_yscale("log")
ax.set_ylabel("Effektive Bandbreite (GB/s)")
ax.set_title("Bandbreite nach Zugriffsmuster — Muster entscheidet, GPU >> CPU",
             color=INK, fontsize=12, loc="left", pad=12)
for b, v, k in zip(bars, vals, keys):
    pct = f"\n{100*v/PEAK_GBS:.0f}% Peak" if k in ("coalesced", "strided", "gather") else ""
    ax.annotate(f"{v:.0f}{pct}" if v >= 10 else f"{v:.1f}{pct}",
                (b.get_x() + b.get_width() / 2, v), xytext=(0, 3),
                textcoords="offset points", ha="center", va="bottom",
                fontsize=8.5, color=INK)
ax.set_ylim(0.5, PEAK_GBS * 1.6)
style_axes(ax)
fig.tight_layout()
fig.savefig(os.path.join(OUT, "e1_patterns.png"))
plt.close(fig)

# ---- Plot 2: Bandbreite ueber Stride ----------------------------------------
rows = read_rows("e2_stride.csv")
pts = sorted((int(r["stride"]), float(r["gb_s"])) for r in rows)
xs, ys = zip(*pts)
fig, ax = plt.subplots(figsize=(8, 5), dpi=150)
ax.plot(xs, ys, lw=2, marker="o", ms=6, color=BLUE)
ax.axhline(PEAK_GBS, ls="--", lw=1.0, color=MUTED)
ax.annotate(f"Peak {PEAK_GBS:.0f}", (xs[0], PEAK_GBS), xytext=(4, 3),
            textcoords="offset points", fontsize=9, color=MUTED)
ax.set_xscale("log", base=2)
ax.set_xticks(xs)
ax.set_xticklabels([str(s) for s in xs])
ax.set_xlabel("Stride (Elemente zwischen aufeinanderfolgenden Threads)")
ax.set_ylabel("Effektive Bandbreite (GB/s)")
ax.set_title("Verlust des Coalescing: Bandbreite bricht mit steigendem Stride ein",
             color=INK, fontsize=12, loc="left", pad=12)
ax.set_ylim(0, PEAK_GBS * 1.05)
style_axes(ax)
fig.tight_layout()
fig.savefig(os.path.join(OUT, "e2_stride.png"))
plt.close(fig)

# ---- Plot 3: Bandbreite ueber Occupancy -------------------------------------
rows = read_rows("e3_occupancy.csv")
pts = sorted((float(r["occ_pct"]), float(r["gb_s"]), int(r["warps_per_sm"])) for r in rows)
xs = [p[0] for p in pts]
ys = [p[1] for p in pts]
warps = [p[2] for p in pts]
fig, ax = plt.subplots(figsize=(8, 5), dpi=150)
ax.plot(xs, ys, lw=2, marker="o", ms=6, color=AQUA)
ax.axhline(PEAK_GBS, ls="--", lw=1.0, color=MUTED)
ax.annotate(f"Peak {PEAK_GBS:.0f}", (xs[0], PEAK_GBS), xytext=(4, 3),
            textcoords="offset points", fontsize=9, color=MUTED)
for x, y, w in zip(xs, ys, warps):
    ax.annotate(f"{w} Warps", (x, y), xytext=(0, -14), textcoords="offset points",
                ha="center", fontsize=8, color=MUTED)
ax.set_xlabel("Occupancy (aktive Warps / max. mögliche Warps pro SM)")
ax.set_ylabel("Effektive Bandbreite (GB/s)")
ax.set_title("Latenz verstecken: genügend Warps sättigen die Bandbreite",
             color=INK, fontsize=12, loc="left", pad=12)
ax.set_xticks(xs)
ax.set_xticklabels([f"{x:.0f}%" for x in xs])
ax.set_ylim(0, PEAK_GBS * 1.05)
style_axes(ax)
fig.tight_layout()
fig.savefig(os.path.join(OUT, "e3_occupancy.png"))
plt.close(fig)

print("Plots geschrieben nach", OUT)

# Erzeugt plots/e1_scaling.png und plots/e2_divergence.png aus results/*.csv
import csv
import os
from collections import defaultdict

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import LogLocator, ScalarFormatter

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "results")
OUT = os.path.join(HERE, "plots")
os.makedirs(OUT, exist_ok=True)

# Referenzpalette (dataviz), Light-Mode, feste Slot-Reihenfolge
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
MUTED = "#898781"
GRID = "#e1e0d9"
BASELINE = "#c3c2b7"
SERIES = {"blue": "#2a78d6", "aqua": "#1baf7a", "yellow": "#eda100"}

STYLE = {
    "gpu-intra":       dict(color=SERIES["blue"],   label="GPU (RTX 3070)"),
    "gpu-warpuniform": dict(color=SERIES["aqua"],   label="GPU, warp-uniforme Verzweigung"),
    "cpu-omp":         dict(color=SERIES["yellow"], label="CPU, OpenMP (alle Kerne)"),
    "cpu":             dict(color=SERIES["aqua"],   label="CPU, 1 Thread"),
}

plt.rcParams.update({
    "font.family": "Segoe UI",
    "text.color": INK,
    "axes.edgecolor": BASELINE,
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


def read_csv(name):
    rows = defaultdict(list)  # mode -> [(x, gflops)]
    with open(os.path.join(RES, name), newline="") as f:
        for r in csv.DictReader(f):
            rows[r["mode"]].append((int(r["n"]), int(r["d"]), float(r["gflops"])))
    return rows


def style_axes(ax):
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)


def direct_label(ax, x, y, text, color):
    ax.annotate(text, (x, y), xytext=(8, 0), textcoords="offset points",
                va="center", fontsize=9, color=INK,
                bbox=dict(boxstyle="round,pad=0.25", fc=SURFACE, ec=color, lw=1))


# ---- Plot 1: Durchsatz ueber n ----------------------------------------------
DIRECT = {"gpu-intra": "GPU", "cpu-omp": "CPU 16T", "cpu": "CPU 1T"}


def fmt_n(n):
    if n >= 1 << 20:
        return f"{n >> 20}M"
    if n >= 1 << 10:
        return f"{n >> 10}K"
    return str(n)


e1 = read_csv("e1_scaling.csv")
fig, ax = plt.subplots(figsize=(8, 5), dpi=150)
all_n = sorted({n for pts in e1.values() for n, d, g in pts})
for mode in ("gpu-intra", "cpu-omp", "cpu"):
    if mode not in e1:
        continue
    pts = sorted((n, g) for n, d, g in e1[mode])
    xs, ys = zip(*pts)
    st = STYLE[mode].copy()
    if mode == "gpu-intra":
        st["label"] = "GPU (RTX 3070)"
    ax.plot(xs, ys, lw=2, marker="o", ms=5, **st)
    direct_label(ax, xs[-1], ys[-1], DIRECT[mode], st["color"])
ax.set_xscale("log", base=2)
ax.set_yscale("log")
ax.set_xticks(all_n)
ax.set_xticklabels([fmt_n(n) for n in all_n])
ax.set_xlabel("Problemgröße n (Elemente = Threads)")
ax.set_ylabel("Durchsatz (GFLOP/s)")
ax.set_title("Skalierung über n: GPU braucht Millionen Threads, die CPU nicht",
             color=INK, fontsize=12, loc="left", pad=12)
ax.yaxis.set_major_locator(LogLocator(base=10))
ax.legend(loc="lower right", fontsize=9)
style_axes(ax)
fig.tight_layout()
fig.savefig(os.path.join(OUT, "e1_scaling.png"))
plt.close(fig)

# ---- Plot 2: Divergenz-Sweep (Durchsatz + Slowdown) -------------------------
e2 = read_csv("e2_divergence.csv")
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11, 4.6), dpi=150)

modes2 = ("gpu-intra", "gpu-warpuniform", "cpu-omp")
for mode in modes2:
    if mode not in e2:
        continue
    pts = sorted((d, g) for n, d, g in e2[mode])
    xs, ys = zip(*pts)
    st = STYLE[mode].copy()
    if mode == "gpu-intra":
        st["label"] = "GPU, intra-warp divergent"
    ax1.plot(xs, ys, lw=2, marker="o", ms=5, **st)
    base = ys[0]
    slow = [base / y for y in ys]
    ax2.plot(xs, slow, lw=2, marker="o", ms=5, **st)

# Referenzlinie: ideale 1/d-Serialisierung
ds = sorted({d for pts in e2.values() for n, d, g in pts})
ax2.plot(ds, ds, lw=1.2, ls="--", color=MUTED, label="ideale Serialisierung (Faktor d)")

for ax, ylab, title in (
    (ax1, "Durchsatz (GFLOP/s)", "Durchsatz bricht nur bei Intra-Warp-Divergenz ein"),
    (ax2, "Slowdown-Faktor vs. d = 1", "Einbruch folgt der Pfadanzahl d"),
):
    ax.set_xscale("log", base=2)
    ax.set_xticks(ds)
    ax.set_xticklabels([str(d) for d in ds])
    ax.set_xlabel("Divergenzgrad d (verschiedene Pfade pro Warp)")
    ax.set_ylabel(ylab)
    ax.set_title(title, color=INK, fontsize=11, loc="left", pad=10)
    style_axes(ax)
ax1.set_yscale("log")
ax2.set_yscale("log")
ax2.set_yticks(ds)
ax2.set_yticklabels([f"{d}×" for d in ds])
ax1.legend(loc="lower left", fontsize=9)
ax2.legend(loc="upper left", fontsize=9)
fig.tight_layout()
fig.savefig(os.path.join(OUT, "e2_divergence.png"))
plt.close(fig)

print("Plots geschrieben nach", OUT)

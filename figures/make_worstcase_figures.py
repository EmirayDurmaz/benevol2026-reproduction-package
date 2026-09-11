#!/usr/bin/env python3
"""Regenerate the worst-case seed mutation-score figures of the paper.

Reads the seed-level workbooks in ../results/excel/ and, for every subject
and budget, selects the seed whose mutation score deviates most from the
Full Baseline score. Produces one PDF (and PNG) per subject, matching the
figures in the paper.

Dependencies: pandas, openpyxl, matplotlib
Usage:       python3 make_worstcase_figures.py
"""
import os
import numpy as np
import pandas as pd
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import MultipleLocator

HERE = os.path.dirname(os.path.abspath(__file__))
EXCEL_DIR = os.path.join(HERE, "..", "results", "excel")

BUDGETS = [2, 4, 6, 8, 10, 20, 30, 40, 50]
SUBJECTS = [
    ("HybridFSM", "results_HybridFSM.xlsx", "hybridfsm"),
    ("Cruise Control", "results_CruiseControl.xlsx", "cruisecontrol"),
    ("PID Controller", "results_PIDController.xlsx", "pidcontroller"),
]
METHODS = [
    ("RandomMutant", "Random Mutant", "#2a78d6", "o"),
    ("CoverageBased", "Coverage-Based", "#eb6834", "s"),
]
LEGEND_LOC = {"hybridfsm": "upper right", "cruisecontrol": "center left",
              "pidcontroller": "lower right"}

INK, MUTED, GRID, BASE = "#0b0b0b", "#52514e", "#eceae6", "#333333"
plt.rcParams.update({
    "font.family": "serif", "font.serif": ["DejaVu Serif"],
    "mathtext.fontset": "cm", "font.size": 10.5,
    "axes.edgecolor": MUTED, "axes.linewidth": 0.8, "axes.labelcolor": INK,
    "xtick.color": "#6b6a66", "ytick.color": "#6b6a66", "text.color": INK,
    "figure.facecolor": "white", "axes.facecolor": "white",
})


def worst_case_series(df, baseline, method):
    """Per budget: mutation score of the seed deviating most from baseline."""
    out = []
    for b in BUDGETS:
        scores = df[(df.method == method) & (df.budget_pct == b)
                    ].mutation_score_pct.to_numpy()
        out.append(scores[np.argmax(np.abs(scores - baseline))])
    return np.array(out)


for title, xlsx, slug in SUBJECTS:
    df = pd.read_excel(os.path.join(EXCEL_DIR, xlsx), sheet_name="seed_level")
    baseline = pd.read_excel(os.path.join(EXCEL_DIR, xlsx),
                             sheet_name="full_baseline").mutation_score_pct[0]
    series = {label: worst_case_series(df, baseline, key)
              for key, label, _, _ in METHODS}

    allv = np.concatenate(list(series.values()) + [[baseline]])
    spread = allv.max() - allv.min()
    margin = max(2.0, 0.08 * spread)
    ylo = max(-1.5, allv.min() - margin)
    yhi = allv.max() + (0.16 * spread if slug == "hybridfsm" else margin)

    fig, ax = plt.subplots(figsize=(4.4, 3.1))
    x = np.array(BUDGETS)
    ax.set_xscale("log")
    ax.set_xticks(BUDGETS)
    ax.set_xticklabels(map(str, BUDGETS))
    ax.minorticks_off()
    ax.tick_params(length=3, width=0.8)
    ax.grid(axis="y", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    for sp in ["top", "right"]:
        ax.spines[sp].set_visible(False)
    ax.axhline(baseline, color=BASE, linewidth=1.7, linestyle=(0, (6, 3)),
               zorder=2, label=f"Full Baseline ({baseline:.1f}%)")
    for key, label, color, marker in METHODS:
        ax.plot(x, series[label], color=color, linewidth=2.1, marker=marker,
                markersize=5.5, markerfacecolor="white", markeredgewidth=1.7,
                markeredgecolor=color, label=label, solid_capstyle="round",
                zorder=3)
    ax.set_ylim(ylo, yhi)
    ax.yaxis.set_major_locator(MultipleLocator(10 if spread > 40 else 5))
    ax.set_xlabel("Time budget (% of $T_{\\mathrm{full}}$)", fontsize=10)
    ax.set_ylabel("Mutation score (%)", fontsize=10)
    ax.legend(frameon=False, fontsize=8.7, loc=LEGEND_LOC[slug],
              handlelength=2.2, borderaxespad=0.3)
    fig.tight_layout(pad=0.4)
    for ext in ("pdf", "png"):
        fig.savefig(os.path.join(HERE, f"{slug}_ms_worstcase.{ext}"),
                    dpi=180, bbox_inches="tight")
    plt.close(fig)
    print(f"{title}: figure written")

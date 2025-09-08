#!/usr/bin/env python3
"""
AM215 - Plot helper for Gamma fits (loc=0).

Generates two figures for a given dataset and fitted parameters:
  1) Histogram (density=True) overlaid with Gamma(k, theta) PDF
  2) Log-likelihood contour in (k, theta) around the MLE

CLI example:
  python3 scripts/60_plot_gamma.py \
    --tsv data/lifespans_Alpha.tsv \
    --col lifespan_months \
    --k 2.1 --theta 1.3 \
    --title "Alpha - Gamma MLE fit" \
    --outprefix out/alpha

Outputs:
  out/alpha_hist.png
  out/alpha_llcontour.png
"""

import argparse
import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from scipy.stats import gamma
from scipy.special import gammaln

def _load_values(tsv_path: str, col: str) -> np.ndarray:
    df = pd.read_csv(tsv_path, sep="\t")
    if col not in df.columns:
        num_cols = [c for c in df.columns if pd.api.types.is_numeric_dtype(df[c])]
        if not num_cols:
            raise SystemExit("No numeric column found and --col not present.")
        col = num_cols[0]
    x = pd.to_numeric(df[col], errors="coerce").to_numpy()
    x = x[np.isfinite(x) & (x > 0)]
    if x.size == 0:
        raise SystemExit("No positive finite values to plot.")
    return x

def _loglike_gamma_loc0(x: np.ndarray, k: float, theta: float) -> float:
    # l(k,theta) = (k-1) sum ln x  - (sum x)/theta  - n*k*ln(theta)  - n*ln(Gamma(k))
    n = x.size
    s1 = np.sum(np.log(x))
    s2 = np.sum(x)
    return (k - 1.0) * s1 - (s2 / theta) - n * k * np.log(theta) - n * gammaln(k)

def plot_hist_with_pdf(x: np.ndarray, k: float, theta: float, out_png: str, title: str, bins: int = 40):
    xs_max = max(np.percentile(x, 99.5), x.max())
    grid = np.linspace(0.0, xs_max * 1.15, 400)
    pdf = gamma.pdf(grid, a=k, loc=0.0, scale=theta)

    plt.figure()
    plt.hist(x, bins=bins, density=True, alpha=0.65, edgecolor="none")
    plt.plot(grid, pdf, linewidth=2.0)
    plt.xlabel("months")
    plt.ylabel("density")
    plt.title(title)
    plt.tight_layout()
    os.makedirs(os.path.dirname(out_png) or ".", exist_ok=True)
    plt.savefig(out_png, dpi=150)
    plt.close()

def plot_ll_contour(x: np.ndarray, k_mle: float, th_mle: float, out_png: str, title: str):
    # Build a grid centered near the MLE
    k_lo, k_hi = max(1e-3, k_mle * 0.25), k_mle * 4.0
    th_lo, th_hi = max(1e-6, th_mle * 0.25), th_mle * 4.0

    K = np.linspace(k_lo, k_hi, 180)
    T = np.linspace(th_lo, th_hi, 180)
    KK, TT = np.meshgrid(K, T, indexing="xy")

    n = x.size
    s1 = np.sum(np.log(x))
    s2 = np.sum(x)

    # l(K,T) = (K-1)*s1 - s2/T - n*K*ln(T) - n*ln(Gamma(K))
    ll = (KK - 1.0) * s1 - (s2 / TT) - n * KK * np.log(TT) - n * gammaln(KK)

    ll_max = np.nanmax(ll)
    z = ll - ll_max  # peak at 0
    levels = [-9.21, -5.99, -3.00, -2.00, -1.00, -0.50, -0.10]

    plt.figure()
    cs = plt.contour(K, T, z.T, levels=levels, linewidths=1.2)
    plt.clabel(cs, inline=True, fontsize=8, fmt="dL=%.2f")
    plt.scatter([k_mle], [th_mle], s=40, marker="x")
    plt.xlabel("k (shape)")
    plt.ylabel("theta (scale)")
    plt.title(title + "\nlog-likelihood contours (loc=0)")
    plt.tight_layout()
    os.makedirs(os.path.dirname(out_png) or ".", exist_ok=True)
    plt.savefig(out_png, dpi=150)
    plt.close()

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--tsv", required=True, help="TSV path with numeric column to plot")
    p.add_argument("--col", default="lifespan_months", help="Column name (default lifespan_months)")
    p.add_argument("--k", type=float, required=True, help="Gamma shape (MLE)")
    p.add_argument("--theta", type=float, required=True, help="Gamma scale (MLE)")
    p.add_argument("--title", required=True, help="Title for both plots")
    p.add_argument("--outprefix", required=True, help="Output prefix (no extension)")
    args = p.parse_args()

    x = _load_values(args.tsv, args.col)
    plot_hist_with_pdf(x, args.k, args.theta, out_png=args.outprefix + "_hist.png", title=args.title)
    plot_ll_contour(x, args.k, args.theta, out_png=args.outprefix + "_llcontour.png", title=args.title)
    print("[plot] wrote " + args.outprefix + "_hist.png")
    print("[plot] wrote " + args.outprefix + "_llcontour.png")

if __name__ == "__main__":
    main()

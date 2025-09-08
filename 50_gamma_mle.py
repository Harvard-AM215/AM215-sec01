#!/usr/bin/env python3
"""
AM215 - Fit Gamma(k, theta) with loc=0 from a TSV column and write a short report.

CLI example:
  python3 scripts/50_gamma_mle.py \
    --tsv data/lifespans_Alpha.tsv \
    --col lifespan_months \
    --out out/gamma_Alpha.txt

Stdout:
  Prints one line TSV: k <TAB> theta <TAB> n <TAB> mean
"""

import argparse
import os
import sys
import numpy as np
import pandas as pd
from scipy.stats import gamma


def fit_gamma_loc0(x: np.ndarray):
    x = np.asarray(x, dtype=float)
    x = x[np.isfinite(x) & (x > 0)]
    if x.size == 0:
        raise SystemExit("No positive finite values to fit.")
    k, loc, theta = gamma.fit(x, floc=0)
    return float(k), float(theta), int(x.size), float(x.mean())


def write_report(
    path: str, source: str, col: str, k: float, theta: float, n: int, mean_: float
):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        f.write(
            "Gamma MLE (loc=0)\n"
            "source      : " + source + "\n"
            "column      : " + col + "\n"
            "n           : " + str(n) + "\n"
            "k (shape)   : " + f"{k:.6f}" + "\n"
            "theta(scale): " + f"{theta:.6f}" + "\n"
            "E[X]=k*theta: " + f"{k*theta:.6f} months" + "\n"
            "sample mean : " + f"{mean_:.6f} months" + "\n"
        )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tsv", default="data/lifespans.tsv")
    ap.add_argument("--out", default="out/gamma_fit.txt")
    ap.add_argument("--col", default="lifespan_months")
    args = ap.parse_args()

    df = pd.read_csv(args.tsv, sep="\t")
    col = (
        args.col
        if args.col in df.columns
        else (
            "lifespan_months"
            if "lifespan_months" in df.columns
            else df.select_dtypes("number").columns[0]
        )
    )
    x = pd.to_numeric(df[col], errors="coerce").to_numpy()

    k, theta, n, mean_ = fit_gamma_loc0(x)
    write_report(args.out, args.tsv, col, k, theta, n, mean_)

    # emit k, theta, n, mean to stdout for the shell pipeline
    print(f"{k}\t{theta}\t{n}\t{mean_}")


if __name__ == "__main__":
    sys.exit(main())

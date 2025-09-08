#!/usr/bin/env python3
"""
AM215 - Synthetic battery review data generator.

- Draw lifespans for two brands from Gamma(k, theta) (months), set post_date = purchase_date + lifespan.
- Failure rows: write reviews that clearly imply the battery stopped working.
- Non-failure rows: write reviews about something else (do not imply failure).
- Optionally call an LLM on Hugging Face Inference for richer text; otherwise use templates.

Output TSV columns:
  review_id, brand, date_purchased, date_posted, review_title, review_body,
  stars, verified, order_id, expected_signed_months_token

Notes:
- expected_signed_months_token is the "ground-truth" months-after-purchase for failure rows (positive float).
  For non-failure rows it is an empty string.
"""

import os
import csv
import math
import random
from datetime import datetime, timedelta
from typing import List, Tuple
import numpy as np
import json
import urllib.request

# --------------------------
# Utilities
# --------------------------

def months_to_days(m):
    # Use 30.44 days per month (365.24/12)
    return m * 30.44

def add_months_as_days(start: datetime, months: float) -> datetime:
    return start + timedelta(days=months_to_days(months))

def rand_date_ymd(start_ymd: str, end_ymd: str, rng: random.Random) -> datetime:
    start = datetime.strptime(start_ymd, "%Y-%m-%d")
    end = datetime.strptime(end_ymd, "%Y-%m-%d")
    span_days = (end - start).days
    off = rng.randrange(span_days + 1)
    return start + timedelta(days=off)

def make_order_id(rng: random.Random) -> str:
    return "O" + "".join(rng.choice("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ") for _ in range(9))

def pick_stars_failure(rng: random.Random) -> int:
    # Failures skew low
    return rng.choices([1,2,3], weights=[0.6,0.3,0.1], k=1)[0]

def pick_stars_other(rng: random.Random) -> int:
    # Non-failures are mixed
    return rng.choices([3,4,5,2], weights=[0.2,0.4,0.35,0.05], k=1)[0]

def pick_verified(rng: random.Random) -> str:
    return "true" if rng.random() < 0.85 else "false"

# --------------------------
# Text generation (LLM optional)
# --------------------------

HF_MODEL = os.environ.get("TEXTGEN_MODEL", "google/gemma-2-2b-it")
HF_URL = f"https://api-inference.huggingface.co/models/{HF_MODEL}"
HF_TOKEN = os.environ.get("HF_API_TOKEN")

def _hf_generate(prompt: str, max_new_tokens: int = 80) -> str:
    """Minimal HF Inference call. Falls back to prompt if no token configured."""
    if not HF_TOKEN:
        return ""
    payload = json.dumps({"inputs": prompt, "parameters": {"max_new_tokens": max_new_tokens}})
    req = urllib.request.Request(
        HF_URL,
        data=payload.encode("utf-8"),
        headers={
            "Authorization": f"Bearer {HF_TOKEN}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            # HF can return a list[{"generated_text": "..."}] or dict with "error"
            if isinstance(data, list) and data and "generated_text" in data[0]:
                return str(data[0]["generated_text"]).strip()
            # Some text-generation endpoints return plain string
            if isinstance(data, str):
                return data.strip()
            return ""
    except Exception:
        return ""

# ----- Prompts -----

FAILURE_PROMPT_TEMPLATE = """You are writing a short customer review about a laptop battery that stopped working.
Brand: {brand}
Time since purchase when it stopped working: about {months:.1f} months

Write a concise review title and a concise review body (1-2 sentences). Do not mention exact months every time; vary wording like "stopped working," "gave out," "busted," or "died". It should clearly imply the battery stopped working. Output as:

TITLE: <one short line>
BODY: <one or two short sentences>"""

OTHER_PROMPT_TEMPLATE = """You are writing a short customer review about a laptop battery that does NOT mention it stopped working.
Brand: {brand}

Write a concise review title and a concise review body (1-2 sentences). Mention things like shipping, packaging, price, customer service, or general impressions, but do not imply failure. Output as:

TITLE: <one short line>
BODY: <one or two short sentences>"""

def parse_title_body(llm_text: str) -> Tuple[str, str]:
    """Extract TITLE and BODY lines from the LLM result; otherwise return empty strings."""
    title, body = "", ""
    for line in llm_text.splitlines():
        line = line.strip()
        if line.upper().startswith("TITLE:"):
            title = line.split(":", 1)[1].strip()
        elif line.upper().startswith("BODY:"):
            body = line.split(":", 1)[1].strip()
    return title, body

# Template fallbacks (if no HF token or blank output)
FAILURE_TITLES = [
    "Battery died early", "Stopped holding charge", "Busted after a few months",
    "Gave out too soon", "Power issues returned"
]
FAILURE_BODIES = [
    "Worked fine at first but stopped working after about {m:.1f} months.",
    "Battery died roughly {m:.1f} months in, now it barely powers on.",
    "After around {m:.1f} months, it gave out and will not hold charge.",
    "About {m:.1f} months after buying, it just quit.",
]
OTHER_TITLES = [
    "Arrived fast", "Decent value", "Solid packaging", "As described", "Good service"
]
OTHER_BODIES = [
    "Shipping was quick and packaging was fine.",
    "Price was fair and it fits as expected.",
    "Customer support answered my questions promptly.",
    "Using it daily so far; no complaints.",
    "Seems fine out of the box; will update later."
]

def gen_failure_text(brand: str, months: float, rng: random.Random) -> Tuple[str, str]:
    prompt = FAILURE_PROMPT_TEMPLATE.format(brand=brand, months=months)
    text = _hf_generate(prompt) if HF_TOKEN else ""
    t, b = parse_title_body(text)
    if not t:
        t = rng.choice(FAILURE_TITLES)
    if not b:
        b = rng.choice(FAILURE_BODIES).format(m=months)
    return t, b

def gen_other_text(brand: str, rng: random.Random) -> Tuple[str, str]:
    prompt = OTHER_PROMPT_TEMPLATE.format(brand=brand)
    text = _hf_generate(prompt) if HF_TOKEN else ""
    t, b = parse_title_body(text)
    if not t:
        t = rng.choice(OTHER_TITLES)
    if not b:
        b = rng.choice(OTHER_BODIES)
    return t, b

# --------------------------
# Main generator
# --------------------------

def sample_gamma_lifespans(k: float, theta: float, n: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    # numpy uses shape=k, scale=theta for Gamma
    x = rng.gamma(shape=k, scale=theta, size=n)
    # ensure strictly positive
    x = np.maximum(x, np.finfo(float).eps)
    return x

def make_dataset(
    out_tsv: str,
    n_fail_alpha: int = 20,
    n_fail_beta: int = 20,
    n_other_alpha: int = 10,
    n_other_beta: int = 10,
    k_alpha: float = 2.0,
    th_alpha: float = 4.0,
    k_beta: float = 3.0,
    th_beta: float = 3.0,
    purchase_start: str = "2023-01-01",
    purchase_end: str = "2024-12-31",
    seed: int = 1234,
):
    """
    Create a TSV at out_tsv.

    Failure rows:
      - brand in {"Alpha","Beta"}
      - lifespan ~ Gamma(k, theta) months (per brand)
      - date_purchased ~ Uniform[purchase_start, purchase_end]
      - date_posted = date_purchased + lifespan
      - expected_signed_months_token = +lifespan (positive float)

    Non-failure rows:
      - brand in {"Alpha","Beta"}
      - date_purchased ~ Uniform
      - date_posted = date_purchased + U[0.2, 18] months (harmless variation)
      - expected_signed_months_token = "" (empty)
    """
    rng = random.Random(seed)
    np.random.seed(seed)

    rows = []

    # Failures - Alpha
    lifespans_A = sample_gamma_lifespans(k_alpha, th_alpha, n_fail_alpha, seed=seed + 11)
    for i, m in enumerate(lifespans_A, 1):
        rid = f"rA{i:03d}"
        brand = "Alpha"
        dp = rand_date_ymd(purchase_start, purchase_end, rng)
        dpost = add_months_as_days(dp, float(m))
        # guard: if post goes beyond a reasonable window, still format as date
        title, body = gen_failure_text(brand, float(m), rng)
        stars = pick_stars_failure(rng)
        verified = pick_verified(rng)
        order_id = make_order_id(rng)
        rows.append([
            rid, brand, dp.strftime("%Y-%m-%d"), dpost.strftime("%Y-%m-%d"),
            title, body, str(stars), verified, order_id, f"{float(m):.2f}"
        ])

    # Failures - Beta
    lifespans_B = sample_gamma_lifespans(k_beta, th_beta, n_fail_beta, seed=seed + 22)
    for i, m in enumerate(lifespans_B, 1):
        rid = f"rB{i:03d}"
        brand = "Beta"
        dp = rand_date_ymd(purchase_start, purchase_end, rng)
        dpost = add_months_as_days(dp, float(m))
        title, body = gen_failure_text(brand, float(m), rng)
        stars = pick_stars_failure(rng)
        verified = pick_verified(rng)
        order_id = make_order_id(rng)
        rows.append([
            rid, brand, dp.strftime("%Y-%m-%d"), dpost.strftime("%Y-%m-%d"),
            title, body, str(stars), verified, order_id, f"{float(m):.2f}"
        ])

    # Non-failures (distractors) - Alpha
    for i in range(n_other_alpha):
        rid = f"rAX{i+1:03d}"
        brand = "Alpha"
        dp = rand_date_ymd(purchase_start, purchase_end, rng)
        # arbitrary benign elapsed time
        m = rng.uniform(0.2, 18.0)
        dpost = add_months_as_days(dp, m)
        title, body = gen_other_text(brand, rng)
        stars = pick_stars_other(rng)
        verified = pick_verified(rng)
        order_id = make_order_id(rng)
        rows.append([
            rid, brand, dp.strftime("%Y-%m-%d"), dpost.strftime("%Y-%m-%d"),
            title, body, str(stars), verified, order_id, ""
        ])

    # Non-failures (distractors) - Beta
    for i in range(n_other_beta):
        rid = f"rBX{i+1:03d}"
        brand = "Beta"
        dp = rand_date_ymd(purchase_start, purchase_end, rng)
        m = rng.uniform(0.2, 18.0)
        dpost = add_months_as_days(dp, m)
        title, body = gen_other_text(brand, rng)
        stars = pick_stars_other(rng)
        verified = pick_verified(rng)
        order_id = make_order_id(rng)
        rows.append([
            rid, brand, dp.strftime("%Y-%m-%d"), dpost.strftime("%Y-%m-%d"),
            title, body, str(stars), verified, order_id, ""
        ])

    # Shuffle so failures and non-failures are mixed
    rng.shuffle(rows)

    # Write TSV with header
    os.makedirs(os.path.dirname(out_tsv) or ".", exist_ok=True)
    with open(out_tsv, "w", newline="") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow([
            "review_id","brand","date_purchased","date_posted",
            "review_title","review_body","stars","verified","order_id","expected_signed_months_token"
        ])
        w.writerows(rows)

    print(f"[synth] wrote {out_tsv} ({len(rows)} rows)")

# --------------------------
# CLI
# --------------------------

if __name__ == "__main__":
    import argparse
    p = argparse.ArgumentParser(description="Generate synthetic battery review data.")
    p.add_argument("--out", default="raw/reviews.tsv", help="Output TSV path")
    p.add_argument("--n-fail-alpha", type=int, default=20)
    p.add_argument("--n-fail-beta", type=int, default=20)
    p.add_argument("--n-other-alpha", type=int, default=10)
    p.add_argument("--n-other-beta", type=int, default=10)
    p.add_argument("--k-alpha", type=float, default=2.0)
    p.add_argument("--th-alpha", type=float, default=4.0)
    p.add_argument("--k-beta", type=float, default=3.0)
    p.add_argument("--th-beta", type=float, default=3.0)
    p.add_argument("--purchase-start", default="2023-01-01")
    p.add_argument("--purchase-end", default="2024-12-31")
    p.add_argument("--seed", type=int, default=1234)
    args = p.parse_args()

    make_dataset(
        out_tsv=args.out,
        n_fail_alpha=args.n_fail_alpha,
        n_fail_beta=args.n_fail_beta,
        n_other_alpha=args.n_other_alpha,
        n_other_beta=args.n_other_beta,
        k_alpha=args.k_alpha,
        th_alpha=args.th_alpha,
        k_beta=args.k_beta,
        th_beta=args.th_beta,
        purchase_start=args.purchase_start,
        purchase_end=args.purchase_end,
        seed=args.seed,
    )


#!/usr/bin/env bash
# AM215 — Minimal cleaner
# Input : raw/reviews.tsv (tab-separated with headers)
# Output: 
#   data/reviews_ascii.tsv
#   data/local_dates.tsv            (review_id, brand, date_purchased, date_posted)
#   data/body_for_llm.tsv           (review_id, review_body)

set -euo pipefail

IN="${1:-raw/reviews.tsv}"
OUT_DIR="data"
ASCII="${OUT_DIR}/reviews_ascii.tsv"

mkdir -p "$OUT_DIR"

# 1) ONE sed: strip Windows CRLF -> LF
sed 's/\r$//' "$IN" > "$ASCII"

# 2) Two simple cuts: dates+brand; body for transformer
cut -f1,2,3,4 "$ASCII" > "${OUT_DIR}/local_dates.tsv"
cut -f1,6     "$ASCII" > "${OUT_DIR}/body_for_llm.tsv"

echo "[clean] wrote: ${ASCII}             ($(($(wc -l < "$ASCII") - 1)) data rows)"
echo "[clean] wrote: ${OUT_DIR}/local_dates.tsv"
echo "[clean] wrote: ${OUT_DIR}/body_for_llm.tsv"

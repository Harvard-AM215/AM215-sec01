#!/usr/bin/env bash
# AM215 — Build lifespans.tsv by joining ownership lengths with HF failure probabilities.
#
# What it does (in plain steps):
#   1) Sort two TSVs by review_id (column 1) so `join` can match lines correctly.
#   2) `join` them on review_id. The result has: review_id, brand, ownership_months, prob_failure.
#   3) Keep only rows with prob_failure >= THRESHOLD.
#   4) Write data/lifespans.tsv with exactly: review_id, brand, lifespan_months
#      (here, lifespan_months == ownership_months for the rows we’re keeping).
#
# Inputs (tab-separated):
#   data/ownership_lengths.tsv   -> review_id<TAB>brand<TAB>ownership_months
#   data/failure_probs.tsv       -> review_id<TAB>prob_failure
#
# Output:
#   data/lifespans.tsv           -> review_id<TAB>brand<TAB>lifespan_months
#
# Optional flags:
#   --ownership <path>   (default: data/ownership_lengths.tsv)
#   --probs <path>       (default: data/failure_probs.tsv)
#   --out <path>         (default: data/lifespans.tsv)
#   --thr <float>        (default: 0.9)  # probability threshold to keep a row
#
# Tools explained:
#   set -euo pipefail   -> exit on error/undefined var; safer scripts.
#   tail -n +2          -> skip the header row (start from line 2).
#   sort -k1,1          -> sort by the 1st field (review_id) so `join` can work.
#   mktemp              -> make a guaranteed-unique temp file safely.
#   trap '...' EXIT     -> auto-clean temp files when the script ends.
#   join -t $'\t' -j 1  -> join on field 1 using TAB as the delimiter.
#   awk -F'\t' -v OFS='\t' '...' -> set TAB as input/output delimiter inside awk.
#                                   We use $NF (last field) for prob so it
#                                   works even if you add more columns later.

set -euo pipefail

# -------- defaults --------
OWN="data/ownership_lengths.tsv"
PROB="data/failure_probs.tsv"
OUT="data/lifespans.tsv"
THR="0.85"

# -------- simple flag parser (long options only) --------
# We loop over "$@" and shift as we consume args.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ownership) OWN="$2"; shift 2 ;;
    --probs)     PROB="$2"; shift 2 ;;
    --out)       OUT="$2"; shift 2 ;;
    --thr)       THR="$2"; shift 2 ;;
    -h|--help)
      cat <<USAGE
Usage: $(basename "$0") [--ownership PATH] [--probs PATH] [--out PATH] [--thr FLOAT]

Defaults:
  --ownership $OWN
  --probs     $PROB
  --out       $OUT
  --thr       $THR
USAGE
      exit 0
      ;;
    *)
      echo "[build] Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

# -------- sanity checks --------
[[ -f "$OWN"  ]] || { echo "[build] Missing: $OWN"  >&2; exit 1; }
[[ -f "$PROB" ]] || { echo "[build] Missing: $PROB" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"

# -------- make temp files and ensure cleanup --------
tmp_own="$(mktemp)"; tmp_prob="$(mktemp)"; tmp_join="$(mktemp)"
trap 'rm -f "$tmp_own" "$tmp_prob" "$tmp_join"' EXIT

# -------- Step 1: sort both inputs on the join key (review_id = column 1) --------
# tail -n +2  -> start from line 2 (skip header row)
# sort -k1,1  -> sort by the first field only (the review_id), required by `join`
tail -n +2 "$OWN"  | sort -k1,1 > "$tmp_own"
tail -n +2 "$PROB" | sort -k1,1 > "$tmp_prob"

# -------- Step 2: join on review_id (column 1) using TAB as delimiter --------
# -t $'\t'  -> set TAB as the field delimiter for join output
# -j 1      -> join on field 1 (review_id) in both files
# Output columns will be:
#   1: review_id
#   2: brand                 (from ownership_lengths.tsv)
#   3: ownership_months      (from ownership_lengths.tsv)
#   4: prob_failure          (from failure_probs.tsv)
join -t $'\t' -j 1 "$tmp_own" "$tmp_prob" > "$tmp_join"

# -------- Step 3: write header to the final output --------
printf "review_id\tbrand\tlifespan_months\n" > "$OUT"

# -------- Step 4: filter by probability and keep needed columns --------
# awk:
#   -F'\t'     -> set TAB as the input field separator
#   -v OFS='\t'-> set TAB as the output field separator
#   -v thr=... -> pass the threshold value into awk as a variable named 'thr'
# Inside awk:
#   $1 = review_id
#   $2 = brand
#   $3 = ownership_months
#   $NF = the last field on the line (probability). We use $NF so this works
#         even if additional columns get added later.
#   ($NF+0) >= thr  -> numeric compare: keep row if prob >= thr
#   print $1,$2,$3  -> write review_id, brand, ownership_months (renamed as lifespan)
awk -F'\t' -v OFS='\t' -v thr="$THR" '($NF+0) >= thr { print $1, $2, $3 }' \
  "$tmp_join" >> "$OUT"

echo "[build] wrote $OUT  ($(($(wc -l < "$OUT") - 1)) rows)"


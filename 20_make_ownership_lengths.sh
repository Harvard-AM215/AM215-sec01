#!/usr/bin/env bash
# AM215 — Build ownership lengths (months) from purchase/post dates (no Python).
#
# What this does:
#   - Read:  data/local_dates.tsv  (review_id<TAB>brand<TAB>date_purchased<TAB>date_posted)
#   - Compute: ownership_months ≈ (date_posted - date_purchased) / 30.44
#   - Write: data/ownership_lengths.tsv (review_id<TAB>brand<TAB>ownership_months)
#
# Notes:
#   - We do *not* assume the item failed — this is just elapsed time between dates.
#   - We use `date -d "<YYYY-MM-DD>" +%s` to convert a date to "seconds since epoch".
#   - We use `bc -l` for floating point division (bash only does integers).
#   - We skip rows with missing/bad dates or where post < purchase.
#   - On macOS, `date -d` is not available; run this on Linux (cluster) or use `gdate`.
#
# Optional flags:
#   --in <path>     (default: data/local_dates.tsv)
#   --out <path>    (default: data/ownership_lengths.tsv)
#   --mindays <n>   (default: 0)  require at least this many days elapsed (e.g., 30)
#
# Tools explained:
#   set -euo pipefail   -> safer scripts: exit on error/undefined var or pipe failures.
#   mkdir -p <dir>      -> create output directory if it doesn’t exist (no error if it does).
#   printf "... \n"     -> print with explicit newlines; we use it for headers and rows.
#   tail -n +2          -> start reading from line 2 (skip the header row).
#   IFS=$'\t' read ...  -> set TAB as the input field separator for read (TSV parsing).
#   date -d "<date>" +%s-> parse a date string and output seconds since 1970-01-01.
#   bc -l               -> calculator in "math mode" for floating point (the -l loads libm).
#
set -euo pipefail

# ----- defaults -----
IN="data/local_dates.tsv"
OUT="data/ownership_lengths.tsv"
MINDAYS="0"    # require at least this many days between purchase and post

# ----- simple flag parser (long options only) -----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --in)      IN="$2"; shift 2 ;;
    --out)     OUT="$2"; shift 2 ;;
    --mindays) MINDAYS="$2"; shift 2 ;;
    -h|--help)
      cat <<USAGE
Usage: $(basename "$0") [--in PATH] [--out PATH] [--mindays N]

Defaults:
  --in      $IN
  --out     $OUT
  --mindays $MINDAYS

Input file format (tab-separated):
  review_id<TAB>brand<TAB>date_purchased<TAB>date_posted
USAGE
      exit 0
      ;;
    *)
      echo "[ownership] Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

# ----- sanity checks -----
[[ -f "$IN" ]] || { echo "[ownership] Missing input: $IN" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"

# ----- write header to output (TSV) -----
# printf prints a string; \t is a literal TAB; \n is newline.
printf "review_id\tbrand\townership_months\n" > "$OUT"

# ----- main loop: read each data row and compute elapsed months -----
# tail -n +2     -> start from line 2 (skip header)
# while ... read -> read one line at a time; IFS=$'\t' splits by TAB into variables
tail -n +2 "$IN" | \
while IFS=$'\t' read -r rid brand dp dpost; do
  # Skip if any required field is empty.
  [ -n "${rid:-}" ]   || continue
  [ -n "${brand:-}" ] || continue
  [ -n "${dp:-}" ]    || continue
  [ -n "${dpost:-}" ] || continue

  # Convert ISO dates (YYYY-MM-DD) to seconds since epoch.
  # `date -d "<date>" +%s` parses <date> and prints the timestamp as an integer.
  sp=$(date -d "$dp" +%s)     || continue   # seconds at purchase
  st=$(date -d "$dpost" +%s)  || continue   # seconds at post

  # Ensure chronological order: post must be on or after purchase.
  [ "$st" -ge "$sp" ] || continue

  # Compute the elapsed time in *days*: (seconds difference) / 86400 seconds/day.
  diff_sec=$(( st - sp ))
  days=$(echo "$diff_sec/86400" | bc -l)

  # Enforce a minimum elapsed time if requested (MINDAYS).
  # bc comparison prints 1 if true, 0 if false.
  keep_days=$(echo "$days >= $MINDAYS" | bc -l)
  [ "$keep_days" -eq 1 ] || continue

  # Convert days -> months using a common average (30.44 days/month ≈ 365.24 / 12).
  months=$(echo "$days/30.44" | bc -l)

  # Guardrail: months must be positive and finite.
  ispos=$(echo "$months > 0" | bc -l)
  [ "$ispos" -eq 1 ] || continue

  # Write one TSV row: review_id, brand, ownership_months (formatted to 6 decimals).
  printf "%s\t%s\t%.6f\n" "$rid" "$brand" "$months" >> "$OUT"
done

# ----- finish -----
echo "[ownership] wrote $OUT  ($(($(wc -l < "$OUT") - 1)) rows)"


#!/usr/bin/env bash
# AM215 - Full pipeline driver for Alpha/Beta outputs

set -euo pipefail

# ---- optional flags ----
THR="${THR:-0.9}"
REPORTS_ONLY=0
INPUT_PATH=""
EXTRA_30_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --thr) THR="$2"; shift 2 ;;
    --input) INPUT_PATH="$2"; shift 2 ;;
    --reports-only) REPORTS_ONLY=1; shift ;;
    --use-cached) EXTRA_30_ARGS+=("--use-cached"); shift ;;
    --model) EXTRA_30_ARGS+=("--model" "$2"); shift 2 ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--thr FLOAT] [--input PATH] [--reports-only] [--use-cached] [--model NAME]"
      echo "Defaults: THR=$THR"
      echo "Note: --input not allowed with --reports-only"
      exit 0
      ;;
    *) echo "[pipeline] unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ "$REPORTS_ONLY" -eq 0 ]]; then
  # 10) clean -> reviews_ascii.tsv, local_dates.tsv, body_for_llm.tsv
  if [[ -n "$INPUT_PATH" ]]; then
    ./10_clean.sh "$INPUT_PATH"
  else
    ./10_clean.sh  # uses default
  fi

  # 20) ownership lengths (months) from dates
  ./20_make_ownership_lengths.sh  # or scripts/30_make_ownership_lengths.sh if you kept that name

  # 30) batch HF classification (single label: "device failure")
  ./30_hf_batch.sh "${EXTRA_30_ARGS[@]}"
else
  if [[ -n "$INPUT_PATH" ]]; then
    echo "[pipeline] ERROR: --input not allowed with --reports-only" >&2
    exit 1
  fi
  echo "[pipeline] --reports-only set: skipping steps 10-30"
fi

# 40) build lifespans.tsv by joining ownership + probs (threshold default 0.9)
./40_build_lifespans.sh --thr "$THR"

# --- split by brand into separate TSVs for fitting/plots ---
# lifespans.tsv columns: review_id  brand  lifespan_months
mkdir -p data out
awk -F'\t' 'NR==1 || $2=="Alpha"' data/lifespans.tsv > data/lifespans_Alpha.tsv
awk -F'\t' 'NR==1 || $2=="Beta"'  data/lifespans.tsv > data/lifespans_Beta.tsv

# 50) fit gamma for Alpha; capture k/theta from stdout; write report
read kA tA nA mA < <(python3 ./50_gamma_mle.py --tsv data/lifespans_Alpha.tsv --out out/gamma_Alpha.txt)
# 60) plots for Alpha
python3 ./60_plot_gamma.py \
  --tsv data/lifespans_Alpha.tsv --k "$kA" --theta "$tA" \
  --title "Alpha Brand Battery Failures - Gamma MLE (n=${nA})" \
  --outprefix out/alpha

# 50) fit gamma for Beta
read kB tB nB mB < <(python3 ./50_gamma_mle.py --tsv data/lifespans_Beta.tsv --out out/gamma_Beta.txt)
# 60) plots for Beta
python3 ./60_plot_gamma.py \
  --tsv data/lifespans_Beta.tsv --k "$kB" --theta "$tB" \
  --title "Beta Brand Battery Failures - Gamma MLE (n=${nB})" \
  --outprefix out/beta

echo "[pipeline] Done. Reports in ./out/, plots alpha_*.png and beta_*.png"

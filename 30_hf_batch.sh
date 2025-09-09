#!/usr/bin/env bash
set -euo pipefail

OUT_TSV="data/failure_probs.tsv"
CACHED="data/failure_probs.cached.tsv"
IN_TSV="data/body_for_llm.tsv"
USE_CACHED=0

# default model and presets
DEFAULT_MODEL="facebook/bart-large-mnli"
HF_MODEL="${HF_MODEL:-$DEFAULT_MODEL}"

# parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --use-cached) USE_CACHED=1; shift ;;
    --model)
      arg_model="$2"; shift 2
      if [[ "$arg_model" =~ ^[0-9]+$ ]]; then
        case "$arg_model" in
          1) HF_MODEL="facebook/bart-large-mnli" ;;
          2) HF_MODEL="typeform/distilbert-base-uncased-mnli" ;;
          3) HF_MODEL="MoritzLaurer/mDeBERTa-v3-base-mnli-xnli" ;;
          *) echo "[hf_batch] Unknown model preset: $arg_model" >&2; exit 2 ;;
        esac
      else
        HF_MODEL="$arg_model"
      fi
      ;;
    -h|--help)
      echo "Usage: $0 [--use-cached] [--model {1|2|3|NAME}]"
      exit 0
      ;;
    *) echo "[hf_batch] Unknown option: $1" >&2; exit 2 ;;
  esac
done

HF_URL="https://api-inference.huggingface.co/models/${HF_MODEL}"
: "${HF_API_TOKEN:?export HF_API_TOKEN=...}"

# explicit --use-cached mode
if [[ $USE_CACHED -eq 1 ]]; then
  if [[ -s "$CACHED" ]]; then
    cp "$CACHED" "$OUT_TSV"
    echo "[hf_batch] Using cached $CACHED"
    exit 0
  else
    echo "[hf_batch] Requested --use-cached but $CACHED not found" >&2
    exit 1
  fi
fi

# 1) Build payload: prefix bodies with [RID=...] and use ONE label
jq -R -s '
  split("\n")[1:-1] |
  map(split("\t")) |
  {inputs: (map("[RID=\(.[0])] " + .[1])),
   parameters:{candidate_labels:["device failure"]}}
' data/body_for_llm.tsv > data/inputs.json
echo "[1/3] wrote data/inputs.json"

# 2) Call HF once (batched), save raw JSON
if ! curl -sS --fail -X POST "$HF_URL" \
  -H "Authorization: Bearer $HF_API_TOKEN" \
  -H "Content-Type: application/json" \
  --retry 5 --retry-delay 5 --retry-on-http-error 429,500,502,503,504 \
  --max-time 300 \
  -d @data/inputs.json > data/hf_raw.json; then
  if [[ -s "$CACHED" ]]; then
    cp "$CACHED" "$OUT_TSV"
    echo "[hf_batch] HF API failed, fell back to cached $CACHED"
    exit 0
  else
    echo "[hf_batch] HF API failed and no cache found" >&2
    exit 1
  fi
fi
echo "[2/3] wrote data/hf_raw.json"

# 3) Parse probs -> TSV with header
printf "review_id\tprob_failure\n" > "$OUT_TSV"
jq -r '
  .[] as $o
  | ($o.sequence | capture("\\[RID=(?<rid>[^\\]]+)\\]")).rid as $rid
  | "\($rid)\t\($o.scores[0])"
' data/hf_raw.json >> "$OUT_TSV"
echo "[3/3] wrote $OUT_TSV"


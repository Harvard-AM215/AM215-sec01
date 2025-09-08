#!/usr/bin/env bash
set -euo pipefail
: "${HF_API_TOKEN:?export HF_API_TOKEN=...}"

MODEL="MoritzLaurer/mDeBERTa-v3-base-mnli-xnli"
URL="https://api-inference.huggingface.co/models/${MODEL}"

# 1) Build payload: prefix bodies with [RID=...] and use ONE label
jq -R -s '
  split("\n")[1:-1] |
  map(split("\t")) |
  {inputs: (map("[RID=\(.[0])] " + .[1])),
   parameters:{candidate_labels:["device failure"]}}
' data/body_for_llm.tsv > data/inputs.json
echo "[1/3] wrote data/inputs.json"

# 2) Call HF once (batched), save raw JSON
curl -sS -X POST "$URL" \
  -H "Authorization: Bearer $HF_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d @data/inputs.json > data/hf_raw.json
echo "[2/3] wrote data/hf_raw.json"

# 3) Parse probs -> TSV: review_id<TAB>prob_failure (order recovered via RID)
jq -r '
  .[] as $o
  | ($o.sequence | capture("\\[RID=(?<rid>[^\\]]+)\\]")).rid as $rid
  | "\($rid)\t\($o.scores[0])"
' data/hf_raw.json > data/failure_probs.tsv
echo "[3/3] wrote data/failure_probs.tsv"


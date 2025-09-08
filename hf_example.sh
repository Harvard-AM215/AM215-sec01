#!/usr/bin/env bash
set -euo pipefail
: "${HF_API_TOKEN:?export HF_API_TOKEN=...}"

TEXT="${1:-Failed after 3 months of use.}"   # pass your own review as $1
MODEL="MoritzLaurer/mDeBERTa-v3-base-mnli-xnli"
URL="https://api-inference.huggingface.co/models/${MODEL}"

# Show the exact curl shape students will use
echo "[example] POSTing a single review:"
echo "curl -sS -X POST \"$URL\" \\"
echo "  -H 'Authorization: Bearer \$HF_API_TOKEN' -H 'Content-Type: application/json' \\"
echo "  -d '{\"inputs\":[\"$TEXT\"],\"parameters\":{\"candidate_labels\":[\"device failure\"]}}'"

# Actually run it (build JSON safely with jq -n)
jq -n --arg text "$TEXT" \
  '{"inputs":[ $text ], "parameters":{"candidate_labels":["device failure"]}}' \
| curl -sS -X POST "$URL" \
    -H "Authorization: Bearer $HF_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d @- | tee /tmp/hf_example_raw.json

echo
echo "[example] device-failure probability:"
jq -r '.[0].scores[0] // .scores[0]' /tmp/hf_example_raw.json


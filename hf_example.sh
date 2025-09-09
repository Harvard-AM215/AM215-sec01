#!/usr/bin/env bash
# AM215 — Simple Hugging Face API example
#
# What this does (step by step):
#   1) Take one review text (argument $1); default string if none provided.
#   2) Build a JSON payload with the review text and one candidate label ("device failure").
#   3) Print the example curl command so students can see the raw request.
#   4) Actually POST the payload to the Hugging Face model inference API.
#   5) Save the raw JSON response and extract the device-failure probability.
#
# Inputs:
#   - Environment variable HF_API_TOKEN (must be set).
#   - One optional command-line argument: a review text.
#
# Outputs:
#   - Echoes an example curl command shape to stdout.
#   - Writes raw JSON response to /tmp/hf_example_raw.json.
#   - Prints the extracted failure probability to stdout.
#
# Notes:
#   - Defaults to using: MoritzLaurer/mDeBERTa-v3-base-mnli-xnli
#   - You can edit the MODEL variable to try another Hugging Face model ID.
#   - jq -n is used here to safely construct JSON with proper quoting.
#
# Tools explained:
#   set -euo pipefail   -> safer bash (exit on error/undefined vars/pipefail).
#   jq -n --arg text …  -> construct JSON safely, inserting shell vars.
#   curl -sS -X POST    -> run an HTTPS POST; -sS quiet with errors visible.
#   tee                 -> copy output both to file and stdout.
#   jq -r '…'           -> parse JSON and extract the score field.
set -euo pipefail
: "${HF_API_TOKEN:?export HF_API_TOKEN=...}"

# If no command-line arg is given, fall back to a default review string
TEXT="${1:-Failed after 3 months of use.}"   # pass your own review as $1
# Default model to use; students can edit this to try others
MODEL="MoritzLaurer/mDeBERTa-v3-base-mnli-xnli"
URL="https://api-inference.huggingface.co/models/${MODEL}"

# Print out the curl command so students can see the structure of the HTTP POST
# Includes URL, headers, and the payload with the review text and candidate label.
echo "[example] POSTing a single review:"
echo "curl -sS -X POST \"$URL\" \\"
echo "  -H 'Authorization: Bearer \$HF_API_TOKEN' -H 'Content-Type: application/json' \\"
echo "  -d '{\"inputs\":[\"$TEXT\"],\"parameters\":{\"candidate_labels\":[\"device failure\"]}}'"

# Actually run it
# jq -n builds JSON safely and injects the shell variable $TEXT properly escaped
# The payload has format: {"inputs":[text], "parameters":{"candidate_labels":["device failure"]}}
jq -n --arg text "$TEXT" \
  '{"inputs":[ $text ], "parameters":{"candidate_labels":["device failure"]}}' \
| curl -sS -X POST "$URL" \
    -H "Authorization: Bearer $HF_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d @- \
    | tee /tmp/hf_example_raw.json  # tee saves raw response to a file and echoes to stdout

echo
echo "[example] device-failure probability:"
# jq extracts the first score value; // handles new vs old API formats
jq -r '.[0].scores[0] // .scores[0]' /tmp/hf_example_raw.json


#!/bin/bash
set -e
# Submit Stage05 image smoketest to local Cromwell.
# Inputs:
# - workflowSource: stage05_stage05image_smoketest.wdl
# - workflowInputs: stage05_stage05image_smoketest.json

ROOT_DIR="${PROJECT_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
WDL_PATH="${ROOT_DIR}/stage05_stage05image_smoketest.wdl"
JSON_PATH="${ROOT_DIR}/stage05_stage05image_smoketest.json"

if [ ! -f "$JSON_PATH" ]; then
  echo "Missing $JSON_PATH"
  exit 1
fi

python3 - <<PY
import json, sys
p="${JSON_PATH}"
data=json.load(open(p))
for k,v in data.items():
    if "REPLACE_ME" in str(v):
        print(f"ERROR: {k} is still REPLACE_ME: {v}")
        sys.exit(1)
PY

curl -sS -X POST "http://localhost:8094/api/workflows/v1" \
  -H "accept: application/json" \
  -F workflowSource=@"$WDL_PATH" \
  -F workflowInputs=@"$JSON_PATH"

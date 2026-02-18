#!/bin/bash
set -e
# Submit Hail image smoketest to local Cromwell.
# Inputs:
# - workflowSource: stage03_hail_smoketest.wdl
# - workflowInputs: stage03_hail_smoketest.json

ROOT_DIR="${PROJECT_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
WDL_PATH="${ROOT_DIR}/stage03_hail_smoketest.wdl"
JSON_PATH="${ROOT_DIR}/stage03_hail_smoketest.json"

if [ ! -f "$JSON_PATH" ]; then
  echo "Missing $JSON_PATH"
  exit 1
fi

python3 - <<PY
import json
p="${JSON_PATH}"
data=json.load(open(p))
key="Stage03HailSmokeTest.docker_image"
cur=data.get(key, "")
if (not cur) or ("REPLACE_ME" in str(cur)):
    data[key]="kchewe/mtdna-hail:0.2.128-ubuntu22.04"
    json.dump(data, open(p,"w"), indent=2)
    print("Updated", p, "->", data[key])
PY

curl -sS -X POST "http://localhost:8094/api/workflows/v1" \
  -H "accept: application/json" \
  -F workflowSource=@"$WDL_PATH" \
  -F workflowInputs=@"$JSON_PATH"

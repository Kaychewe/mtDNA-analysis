#!/bin/bash
set -e
# Submit Stage03 combined image smoketest to local Cromwell.
# Inputs:
# - workflowSource: stage03_stage03image_smoketest.wdl
# - workflowInputs: stage03_stage03image_smoketest.json

ROOT_DIR="${PROJECT_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
WDL_PATH="${ROOT_DIR}/stage03_stage03image_smoketest.wdl"
JSON_PATH="${ROOT_DIR}/stage03_stage03image_smoketest.json"

if [ ! -f "$JSON_PATH" ]; then
  echo "Missing $JSON_PATH"
  exit 1
fi

python3 - <<PY
import json
p="${JSON_PATH}"
data=json.load(open(p))
key="Stage03ImageSmokeTest.docker_image"
cur=data.get(key, "")
if (not cur) or ("REPLACE_ME" in str(cur)):
    data[key]="kchewe/mtdna-stage03:0.1.0"
    json.dump(data, open(p,"w"), indent=2)
    print("Updated", p, "->", data[key])
PY

curl -sS -X POST "http://localhost:8094/api/workflows/v1" \
  -H "accept: application/json" \
  -F workflowSource=@"$WDL_PATH" \
  -F workflowInputs=@"$JSON_PATH"

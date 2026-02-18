#!/bin/bash
set -e
# Submit UCSC tools bundle smoketest to local Cromwell.
# Inputs:
# - workflowSource: stage03_ucsc_smoketest.wdl
# - workflowInputs: stage03_ucsc_smoketest.json

ROOT_DIR="${PROJECT_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
WDL_PATH="${ROOT_DIR}/stage03_ucsc_smoketest.wdl"
JSON_PATH="${ROOT_DIR}/stage03_ucsc_smoketest.json"

if [ ! -f "$JSON_PATH" ]; then
  echo "Missing $JSON_PATH"
  exit 1
fi

# Auto-fill bundle path from WORKSPACE_BUCKET if still REPLACE_ME
if [ -n "${WORKSPACE_BUCKET:-}" ]; then
  python3 - <<PY
import json
p="${JSON_PATH}"
data=json.load(open(p))
bundle="gs://fc-secure-76d68a64-00aa-40a7-b2c5-ca956db2719b/tools/ucsc/ucsc-tools-linux-x86_64.tar.gz"
key="Stage03UcscSmokeTest.ucsc_tools_bundle"
cur=data.get(key, "")
if (not cur) or ("REPLACE_ME" in str(cur)):
    data[key]=bundle
    json.dump(data, open(p,"w"), indent=2)
    print("Updated", p, "->", bundle)
PY
fi

curl -sS -X POST "http://localhost:8094/api/workflows/v1" \
  -H "accept: application/json" \
  -F workflowSource=@"$WDL_PATH" \
  -F workflowInputs=@"$JSON_PATH"

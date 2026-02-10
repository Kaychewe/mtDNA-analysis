#!/bin/bash
set -e
# Submit Stage06 merge to local Cromwell.
# Inputs:
# - workflowSource: stage06_merge.wdl
# - workflowInputs: stage06_merge.json

ROOT_DIR="${PROJECT_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
WDL_PATH="${ROOT_DIR}/stage06_merge.wdl"
JSON_PATH="${ROOT_DIR}/stage06_merge.json"

curl -sS -X POST "http://localhost:8094/api/workflows/v1" \
  -H "accept: application/json" \
  -F workflowSource=@"$WDL_PATH" \
  -F workflowInputs=@"$JSON_PATH"

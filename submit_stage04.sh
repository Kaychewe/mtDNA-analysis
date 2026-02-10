#!/bin/bash
set -e
# Submit Stage04 align/call R2 to local Cromwell.
# Inputs:
# - workflowSource: stage04_align_call_r2.wdl
# - workflowInputs: stage04_align_call_r2.json

ROOT_DIR="${PROJECT_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
WDL_PATH="${ROOT_DIR}/stage04_align_call_r2.wdl"
JSON_PATH="${ROOT_DIR}/stage04_align_call_r2.json"

curl -sS -X POST "http://localhost:8094/api/workflows/v1" \
  -H "accept: application/json" \
  -F workflowSource=@"$WDL_PATH" \
  -F workflowInputs=@"$JSON_PATH"

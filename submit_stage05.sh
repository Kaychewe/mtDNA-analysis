#!/bin/bash
set -e
# Submit Stage05 liftover to local Cromwell.
# Inputs:
# - workflowSource: stage05_liftover.wdl
# - workflowInputs: stage05_liftover.json

ROOT_DIR="${PROJECT_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
WDL_PATH="${ROOT_DIR}/stage05_liftover.wdl"
JSON_PATH="${ROOT_DIR}/stage05_liftover.json"

curl -sS -X POST "http://localhost:8094/api/workflows/v1" \
  -H "accept: application/json" \
  -F workflowSource=@"$WDL_PATH" \
  -F workflowInputs=@"$JSON_PATH"

#!/bin/bash
set -e
# Submit UCSC tools diagnostic to local Cromwell.
# Inputs:
# - workflowSource: diagnostic_ucsc_tools.wdl
# - workflowInputs: diagnostic_ucsc_tools.json

ROOT_DIR="${PROJECT_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
WDL_PATH="${ROOT_DIR}/diagnostic_ucsc_tools.wdl"
JSON_PATH="${ROOT_DIR}/diagnostic_ucsc_tools.json"

curl -sS -X POST "http://localhost:8094/api/workflows/v1" \
  -H "accept: application/json" \
  -F workflowSource=@"$WDL_PATH" \
  -F workflowInputs=@"$JSON_PATH"

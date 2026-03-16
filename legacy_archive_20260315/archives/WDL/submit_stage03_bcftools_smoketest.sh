#!/bin/bash
set -e
# Submit bcftools docker smoketest to local Cromwell.
# Inputs:
# - workflowSource: stage03_bcftools_smoketest.wdl
# - workflowInputs: stage03_bcftools_smoketest.json

ROOT_DIR="${PROJECT_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
WDL_PATH="${ROOT_DIR}/stage03_bcftools_smoketest.wdl"
JSON_PATH="${ROOT_DIR}/stage03_bcftools_smoketest.json"

curl -sS -X POST "http://localhost:8094/api/workflows/v1" \
  -H "accept: application/json" \
  -F workflowSource=@"$WDL_PATH" \
  -F workflowInputs=@"$JSON_PATH"

#!/bin/bash
set -e
# Submit Stage 02 (AlignAndCallR1) to the local Cromwell server.
# Inputs:
# - workflowSource: stage02_align_call_r1.wdl
# - workflowInputs: stage02_align_call_r1.json
# - workflowDependencies: wdl_deps.zip (if present)

ROOT_DIR="${PROJECT_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
WDL_PATH="${ROOT_DIR}/stage02_align_call_r1.wdl"
JSON_PATH="${ROOT_DIR}/stage02_align_call_r1.json"
DEPS_PATH="${ROOT_DIR}/wdl_deps.zip"

DEPS_ARG=()
if [ -f "$DEPS_PATH" ]; then
  DEPS_ARG=(-F workflowDependencies=@"$DEPS_PATH")
fi

curl -sS -X POST "http://localhost:8094/api/workflows/v1" \
  -H "accept: application/json" \
  -F workflowSource=@"$WDL_PATH" \
  -F workflowInputs=@"$JSON_PATH" \
  "${DEPS_ARG[@]}"

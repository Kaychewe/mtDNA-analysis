#!/bin/bash
set -e
# Submit Stage 03 (ProduceSelfReferenceFiles) to the local Cromwell server.
# Inputs:
# - workflowSource: stage03_produce_self_reference.wdl
# - workflowInputs: stage03_produce_self_reference.json
# - workflowDependencies: wdl_deps.zip (if present)

ROOT_DIR="${PROJECT_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
WDL_PATH="${ROOT_DIR}/stage03_produce_self_reference.wdl"
JSON_PATH="${ROOT_DIR}/stage03_produce_self_reference.json"
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

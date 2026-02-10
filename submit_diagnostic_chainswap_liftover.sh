#!/bin/bash
set -e
# Submit ChainSwap/LiftOver isolated diagnostic to local Cromwell.
# Inputs:
# - workflowSource: diagnostic_chainswap_liftover.wdl
# - workflowInputs: diagnostic_chainswap_liftover.json
# - workflowDependencies: wdl_deps.zip

ROOT_DIR="${PROJECT_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
WDL_PATH="${ROOT_DIR}/diagnostic_chainswap_liftover.wdl"
JSON_PATH="${ROOT_DIR}/diagnostic_chainswap_liftover.json"
DEPS_PATH="${ROOT_DIR}/wdl_deps.zip"

curl -sS -X POST "http://localhost:8094/api/workflows/v1" \
  -H "accept: application/json" \
  -F workflowSource=@"$WDL_PATH" \
  -F workflowInputs=@"$JSON_PATH" \
  -F workflowDependencies=@"$DEPS_PATH"

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

if [ ! -f "$JSON_PATH" ]; then
  echo "Missing $JSON_PATH"
  exit 1
fi

# Auto-fill common placeholders
python3 - <<PY
import json, sys
p="${JSON_PATH}"
data=json.load(open(p))

def set_if_placeholder(key, value):
    cur = data.get(key, "")
    if (not cur) or ("REPLACE_ME" in str(cur)):
        data[key] = value
        return True
    return False

changed = False
changed |= set_if_placeholder(
    "StageProduceSelfReferenceFiles.genomes_cloud_docker",
    "kchewe/mtdna-stage03:0.1.0",
)

# UCSC bundle (optional but recommended). Only set if WORKSPACE_BUCKET is defined.
import os
ws = os.environ.get("WORKSPACE_BUCKET")
if ws:
    bundle = f"{ws.rstrip('/')}/tools/ucsc/ucsc-tools-linux-x86_64.tar.gz"
    if set_if_placeholder("StageProduceSelfReferenceFiles.ucsc_tools_bundle", bundle):
        changed = True

if changed:
    json.dump(data, open(p,"w"), indent=2)
    print(f"Updated {p}")

# Fail fast if any REPLACE_ME remains
for k,v in data.items():
    if "REPLACE_ME" in str(v):
        print(f"ERROR: {k} is still REPLACE_ME: {v}")
        sys.exit(1)
PY

DEPS_ARG=()
if [ -f "$DEPS_PATH" ]; then
  # Warn if deps zip is older than any WDL in mtSwirl/WDL/v2.5_MongoSwirl_Single
  WDL_ROOT="${ROOT_DIR}/mtSwirl/WDL/v2.5_MongoSwirl_Single"
  if [ -d "$WDL_ROOT" ]; then
    newest_wdl=$(find "$WDL_ROOT" -name "*.wdl" -type f -printf "%T@ %p\n" | sort -nr | head -n 1 | awk '{print $2}')
    if [ -n "$newest_wdl" ] && [ "$newest_wdl" -nt "$DEPS_PATH" ]; then
      echo "WARNING: $DEPS_PATH is older than $newest_wdl"
      echo "Recreate with: python3 - <<'PY' ... (see README or prior commands)"
    fi
  fi
  DEPS_ARG=(-F workflowDependencies=@"$DEPS_PATH")
else
  echo "WARNING: Missing workflowDependencies: $DEPS_PATH"
fi

curl -sS -X POST "http://localhost:8094/api/workflows/v1" \
  -H "accept: application/json" \
  -F workflowSource=@"$WDL_PATH" \
  -F workflowInputs=@"$JSON_PATH" \
  "${DEPS_ARG[@]}"

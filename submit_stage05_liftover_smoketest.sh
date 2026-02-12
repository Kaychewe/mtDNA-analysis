#!/bin/bash
set -e
# Submit Stage05 liftover smoketest to local Cromwell.
# Inputs:
# - workflowSource: stage05_liftover_smoketest.wdl
# - workflowInputs: stage05_liftover_smoketest.json (auto-derived from stage05_liftover.json if present)

ROOT_DIR="${PROJECT_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
WDL_PATH="${ROOT_DIR}/stage05_liftover_smoketest.wdl"
TEMPLATE_JSON="${ROOT_DIR}/stage05_liftover_smoketest.json"
DEPS_PATH="${ROOT_DIR}/wdl_deps.zip"

JSON_PATH="$TEMPLATE_JSON"

if [ ! -f "$JSON_PATH" ]; then
  echo "Missing $JSON_PATH"
  exit 1
fi

python3 - <<PY
import json, sys
p="${JSON_PATH}"
data=json.load(open(p))
for k,v in data.items():
    if "REPLACE_ME" in str(v):
        print(f"ERROR: {k} is still REPLACE_ME: {v}")
        sys.exit(1)
PY

echo "=== Stage05 Liftover Smoketest Inputs ==="
python3 - <<PY
import json
p="${JSON_PATH}"
data=json.load(open(p))
for k in sorted(data.keys()):
    print(f"{k}: {data[k]}")
PY
echo "=== End Inputs ==="

DEPS_ARG=()
if [ -f "$DEPS_PATH" ]; then
  DEPS_ARG=(-F workflowDependencies=@"$DEPS_PATH")
fi

curl -sS -X POST "http://localhost:8094/api/workflows/v1" \
  -H "accept: application/json" \
  -F workflowSource=@"$WDL_PATH" \
  -F workflowInputs=@"$JSON_PATH" \
  "${DEPS_ARG[@]}"

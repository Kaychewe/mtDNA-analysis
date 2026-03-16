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

for f in "$WDL_PATH" "$JSON_PATH"; do
  if [ ! -f "$f" ]; then
    echo "Missing required file: $f"
    exit 1
  fi
done

# Auto-fill bundle path from WORKSPACE_BUCKET if still REPLACE_ME
if [ -n "${WORKSPACE_BUCKET:-}" ]; then
  python3 - <<PY
import json
p="${JSON_PATH}"
data=json.load(open(p))
bundle="gs://fc-secure-76d68a64-00aa-40a7-b2c5-ca956db2719b/tools/ucsc/ucsc-tools-linux-x86_64.tar.gz"
key="DiagnosticChainSwapLiftover.ucsc_tools_bundle"
cur=data.get(key, "")
if (not cur) or ("REPLACE_ME" in str(cur)):
    data[key]=bundle
    json.dump(data, open(p,"w"), indent=2)
    print("Updated", p, "->", bundle)
PY
fi

python3 - <<PY
import json
p="${JSON_PATH}"
data=json.load(open(p))
bundle=data.get("DiagnosticChainSwapLiftover.ucsc_tools_bundle", "")
img=data.get("DiagnosticChainSwapLiftover.ucsc_docker", "")
if bundle and "REPLACE_ME" not in str(bundle):
    # Always use a Java-capable base image with newer glibc when igvtools is in the bundle.
    java_img="eclipse-temurin:17-jdk"
    if img != java_img:
        data["DiagnosticChainSwapLiftover.ucsc_docker"]=java_img
        json.dump(data, open(p,"w"), indent=2)
        print("Updated", p, "ucsc_docker ->", java_img)
PY

if [ ! -f "$DEPS_PATH" ]; then
  echo "Missing workflowDependencies: $DEPS_PATH"
  echo "Recreate with: python3 - <<'PY' ... (see README or prior commands)"
  exit 1
fi

curl -sS -X POST "http://localhost:8094/api/workflows/v1" \
  -H "accept: application/json" \
  -F workflowSource=@"$WDL_PATH" \
  -F workflowInputs=@"$JSON_PATH" \
  -F workflowDependencies=@"$DEPS_PATH"

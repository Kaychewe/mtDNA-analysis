#!/bin/bash
set -euo pipefail
# Submit Stage06 merge to local Cromwell.
# Inputs:
# - workflowSource: stage06_merge.wdl
# - workflowInputs: stage06_merge.json
# - workflowDependencies: wdl_deps.zip (if present)

ROOT_DIR="${PROJECT_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
WDL_PATH="${ROOT_DIR}/stage06_merge.wdl"
JSON_PATH="${ROOT_DIR}/stage06_merge.json"
DEPS_PATH="${ROOT_DIR}/wdl_deps.zip"

if [ ! -f "$JSON_PATH" ]; then
  echo "Missing $JSON_PATH"
  exit 1
fi

python3 - <<PY
import json, sys
p="${JSON_PATH}"
data=json.load(open(p))

# Fail fast if any REPLACE_ME remains
for k,v in data.items():
    if "REPLACE_ME" in str(v):
        print(f"ERROR: {k} is still REPLACE_ME: {v}")
        sys.exit(1)

required = [
    "StageMerge.sample_name",
    "StageMerge.variant_vcf",
    "StageMerge.coverage_table",
    "StageMerge.statistics",
    "StageMerge.MergePerBatch",
    "StageMerge.genomes_cloud_docker",
]
missing = [k for k in required if not str(data.get(k, "")).strip()]
if missing:
    print("ERROR: Missing required inputs:")
    for k in missing:
        print(f"  - {k}")
    sys.exit(1)

def ensure_list(key):
    v = data.get(key, [])
    if not isinstance(v, list) or len(v) == 0:
        print(f"ERROR: {key} must be a non-empty array")
        sys.exit(1)

for key in ("StageMerge.sample_name","StageMerge.variant_vcf","StageMerge.coverage_table","StageMerge.statistics"):
    ensure_list(key)

if len(data["StageMerge.variant_vcf"]) != len(data["StageMerge.coverage_table"]) or len(data["StageMerge.variant_vcf"]) != len(data["StageMerge.statistics"]):
    print("ERROR: variant_vcf, coverage_table, and statistics arrays must have the same length")
    sys.exit(1)

# Emit GCS paths to verify existence downstream in bash
gcs_paths = []
def collect(v):
    if isinstance(v, str) and v.startswith("gs://"):
        gcs_paths.append(v)
    elif isinstance(v, list):
        for item in v:
            if isinstance(item, str) and item.startswith("gs://"):
                gcs_paths.append(item)

for v in data.values():
    collect(v)

print("=== GCS Inputs To Check ===")
for pth in gcs_paths:
    print(pth)
print("=== End GCS Inputs ===")
PY

echo
echo "=== Verifying GCS Inputs ==="
while IFS= read -r line; do
  [ -z "$line" ] && continue
  if ! gsutil -q stat "$line"; then
    echo "ERROR: Missing GCS input: $line"
    exit 1
  fi
done < <(python3 - <<PY
import json
p="${JSON_PATH}"
data=json.load(open(p))
def emit(v):
    if isinstance(v, str) and v.startswith("gs://"):
        print(v)
    elif isinstance(v, list):
        for item in v:
            if isinstance(item, str) and item.startswith("gs://"):
                print(item)
for v in data.values():
    emit(v)
PY
)
echo "=== GCS Inputs OK ==="

echo "=== Stage06 Submission Params ==="
echo "WDL:  $WDL_PATH"
echo "JSON: $JSON_PATH"
echo "DEPS: $DEPS_PATH"
echo
echo "=== WDL Inputs (stage06_merge.wdl) ==="
awk '
  /workflow[[:space:]]+StageMerge/ {in_wf=1}
  in_wf && /input[[:space:]]*{/ {in_input=1; next}
  in_input {print}
  in_input && /}/ {in_input=0}
' "$WDL_PATH" | sed 's/^/  /'
echo
echo "=== JSON Inputs (stage06_merge.json) ==="
python3 - <<PY
import json
p="${JSON_PATH}"
data=json.load(open(p))
for k in sorted(data.keys()):
    print(f"{k}: {data[k]}")
PY
echo "=== End Params ==="

DEPS_ARG=()
if [ -f "$DEPS_PATH" ]; then
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

if python3 - <<PY
import json
p="${JSON_PATH}"
data=json.load(open(p))
img=str(data.get("StageMerge.genomes_cloud_docker",""))
print(img)
PY
then
  img=$(python3 - <<PY
import json
p="${JSON_PATH}"
data=json.load(open(p))
print(str(data.get("StageMerge.genomes_cloud_docker","")))
PY
)
  if [[ "$img" == *":latest" ]]; then
    echo "WARNING: StageMerge.genomes_cloud_docker is using :latest -> $img"
  fi
fi

curl -sS -X POST "http://localhost:8094/api/workflows/v1" \
  -H "accept: application/json" \
  -F workflowSource=@"$WDL_PATH" \
  -F workflowInputs=@"$JSON_PATH" \
  "${DEPS_ARG[@]}"

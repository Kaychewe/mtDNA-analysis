#!/bin/bash
set -e
# Submit Stage04 align/call R2 to local Cromwell.
# Inputs:
# - workflowSource: stage04_align_call_r2.wdl
# - workflowInputs: stage04_align_call_r2.json
# - workflowDependencies: wdl_deps.zip (if present)

ROOT_DIR="${PROJECT_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
WDL_PATH="${ROOT_DIR}/stage04_align_call_r2.wdl"
JSON_PATH="${ROOT_DIR}/stage04_align_call_r2.json"
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

# Fail fast if required inputs are missing/empty.
required = [
    "StageAlignAndCallR2.sample_name",
    "StageAlignAndCallR2.unmapped_bam",
    "StageAlignAndCallR2.mt_interval_list_self",
    "StageAlignAndCallR2.mt_self",
    "StageAlignAndCallR2.mt_self_index",
    "StageAlignAndCallR2.mt_self_dict",
    "StageAlignAndCallR2.mt_andNuc_self",
    "StageAlignAndCallR2.mt_andNuc_self_index",
    "StageAlignAndCallR2.mt_andNuc_self_dict",
    "StageAlignAndCallR2.mt_shifted_self",
    "StageAlignAndCallR2.mt_shifted_self_index",
    "StageAlignAndCallR2.mt_shifted_self_dict",
    "StageAlignAndCallR2.mt_andNuc_shifted_self",
    "StageAlignAndCallR2.mt_andNuc_shifted_self_index",
    "StageAlignAndCallR2.mt_andNuc_shifted_self_dict",
    "StageAlignAndCallR2.blacklisted_sites_self",
    "StageAlignAndCallR2.blacklisted_sites_index_self",
    "StageAlignAndCallR2.force_call_vcf",
    "StageAlignAndCallR2.force_call_vcf_idx",
    "StageAlignAndCallR2.force_call_vcf_shifted",
    "StageAlignAndCallR2.force_call_vcf_shifted_idx",
    "StageAlignAndCallR2.self_shift_back_chain",
    "StageAlignAndCallR2.non_control_interval_self",
    "StageAlignAndCallR2.control_shifted_self",
    "StageAlignAndCallR2.hasContamination",
    "StageAlignAndCallR2.contamination_major",
    "StageAlignAndCallR2.contamination_minor",
    "StageAlignAndCallR2.compress_output_vcf",
]
missing = [k for k in required if not str(data.get(k, "")).strip()]
if missing:
    print("ERROR: Missing required inputs:")
    for k in missing:
        print(f"  - {k}")
    sys.exit(1)

# Emit GCS paths to verify existence downstream in bash
gcs_paths = []
for k,v in data.items():
    if isinstance(v, str) and v.startswith("gs://"):
        gcs_paths.append(v)
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
for v in data.values():
    if isinstance(v, str) and v.startswith("gs://"):
        print(v)
PY
)
echo "=== GCS Inputs OK ==="

echo "=== Stage04 Submission Params ==="
echo "WDL:  $WDL_PATH"
echo "JSON: $JSON_PATH"
echo "DEPS: $DEPS_PATH"
echo
echo "=== WDL Inputs (stage04_align_call_r2.wdl) ==="
awk '
  /workflow[[:space:]]+StageAlignAndCallR2/ {in_wf=1}
  in_wf && /input[[:space:]]*{/ {in_input=1; next}
  in_input {print}
  in_input && /}/ {in_input=0}
' "$WDL_PATH" | sed 's/^/  /'
echo
echo "=== JSON Inputs (stage04_align_call_r2.json) ==="
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

curl -sS -X POST "http://localhost:8094/api/workflows/v1" \
  -H "accept: application/json" \
  -F workflowSource=@"$WDL_PATH" \
  -F workflowInputs=@"$JSON_PATH" \
  "${DEPS_ARG[@]}"

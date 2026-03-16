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
    "kchewe/mtdna-stage03:0.1.1",
)

# UCSC bundle (optional but recommended). Only set if WORKSPACE_BUCKET is defined.
import os
ws = os.environ.get("WORKSPACE_BUCKET")
if ws:
    bundle = f"{ws.rstrip('/')}/tools/ucsc/ucsc-tools-linux-x86_64.tar.gz"
    if set_if_placeholder("StageProduceSelfReferenceFiles.ucsc_tools_bundle", bundle):
        changed = True

# If using a UCSC bundle, force ucsc_docker to a Java-capable image.
if data.get("StageProduceSelfReferenceFiles.ucsc_tools_bundle"):
    if data.get("StageProduceSelfReferenceFiles.ucsc_docker") != "kchewe/mtdna-stage03:0.1.1":
        data["StageProduceSelfReferenceFiles.ucsc_docker"] = "kchewe/mtdna-stage03:0.1.1"
        changed = True

if changed:
    json.dump(data, open(p,"w"), indent=2)
    print(f"Updated {p}")

# Fail fast if any REPLACE_ME remains
for k,v in data.items():
    if "REPLACE_ME" in str(v):
        print(f"ERROR: {k} is still REPLACE_ME: {v}")
        sys.exit(1)

# Fail fast if required inputs are missing/empty.
required = [
    "StageProduceSelfReferenceFiles.sample_name",
    "StageProduceSelfReferenceFiles.suffix",
    "StageProduceSelfReferenceFiles.mt_dict",
    "StageProduceSelfReferenceFiles.mt_fasta",
    "StageProduceSelfReferenceFiles.mt_fasta_index",
    "StageProduceSelfReferenceFiles.mt_interval_list",
    "StageProduceSelfReferenceFiles.non_control_region_interval_list",
    "StageProduceSelfReferenceFiles.ref_dict",
    "StageProduceSelfReferenceFiles.ref_fasta",
    "StageProduceSelfReferenceFiles.ref_fasta_index",
    "StageProduceSelfReferenceFiles.nuc_interval_list",
    "StageProduceSelfReferenceFiles.reference_name",
    "StageProduceSelfReferenceFiles.blacklisted_sites",
    "StageProduceSelfReferenceFiles.blacklisted_sites_index",
    "StageProduceSelfReferenceFiles.nuc_variants",
    "StageProduceSelfReferenceFiles.mtdna_variants",
    "StageProduceSelfReferenceFiles.FaRenamingScript",
    "StageProduceSelfReferenceFiles.CheckVariantBoundsScript",
    "StageProduceSelfReferenceFiles.CheckHomOverlapScript",
    "StageProduceSelfReferenceFiles.genomes_cloud_docker",
    "StageProduceSelfReferenceFiles.gotc_docker",
    "StageProduceSelfReferenceFiles.ucsc_docker",
]
missing = [k for k in required if not str(data.get(k, "")).strip()]
if missing:
    print("ERROR: Missing required inputs:")
    for k in missing:
        print(f"  - {k}")
    sys.exit(1)

# Emit GCS paths to verify existence downstream in bash
gcs_keys = [
    "StageProduceSelfReferenceFiles.mt_dict",
    "StageProduceSelfReferenceFiles.mt_fasta",
    "StageProduceSelfReferenceFiles.mt_fasta_index",
    "StageProduceSelfReferenceFiles.mt_interval_list",
    "StageProduceSelfReferenceFiles.non_control_region_interval_list",
    "StageProduceSelfReferenceFiles.ref_dict",
    "StageProduceSelfReferenceFiles.ref_fasta",
    "StageProduceSelfReferenceFiles.ref_fasta_index",
    "StageProduceSelfReferenceFiles.nuc_interval_list",
    "StageProduceSelfReferenceFiles.blacklisted_sites",
    "StageProduceSelfReferenceFiles.blacklisted_sites_index",
    "StageProduceSelfReferenceFiles.nuc_variants",
    "StageProduceSelfReferenceFiles.mtdna_variants",
    "StageProduceSelfReferenceFiles.FaRenamingScript",
    "StageProduceSelfReferenceFiles.CheckVariantBoundsScript",
    "StageProduceSelfReferenceFiles.CheckHomOverlapScript",
    "StageProduceSelfReferenceFiles.ucsc_tools_bundle",
]
gcs_paths = [data[k] for k in gcs_keys if str(data.get(k,"")).startswith("gs://")]
print("=== GCS Inputs To Check ===")
for pth in gcs_paths:
    print(pth)
print("=== End GCS Inputs ===")
PY

# Verify key GCS inputs exist before submission
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
gcs_keys = [
    "StageProduceSelfReferenceFiles.mt_dict",
    "StageProduceSelfReferenceFiles.mt_fasta",
    "StageProduceSelfReferenceFiles.mt_fasta_index",
    "StageProduceSelfReferenceFiles.mt_interval_list",
    "StageProduceSelfReferenceFiles.non_control_region_interval_list",
    "StageProduceSelfReferenceFiles.ref_dict",
    "StageProduceSelfReferenceFiles.ref_fasta",
    "StageProduceSelfReferenceFiles.ref_fasta_index",
    "StageProduceSelfReferenceFiles.nuc_interval_list",
    "StageProduceSelfReferenceFiles.blacklisted_sites",
    "StageProduceSelfReferenceFiles.blacklisted_sites_index",
    "StageProduceSelfReferenceFiles.nuc_variants",
    "StageProduceSelfReferenceFiles.mtdna_variants",
    "StageProduceSelfReferenceFiles.FaRenamingScript",
    "StageProduceSelfReferenceFiles.CheckVariantBoundsScript",
    "StageProduceSelfReferenceFiles.CheckHomOverlapScript",
    "StageProduceSelfReferenceFiles.ucsc_tools_bundle",
]
for k in gcs_keys:
    v=data.get(k)
    if isinstance(v, str) and v.startswith("gs://"):
        print(v)
PY
)
echo "=== GCS Inputs OK ==="

echo "=== Stage03 Submission Params ==="
echo "WDL:  $WDL_PATH"
echo "JSON: $JSON_PATH"
echo "DEPS: $DEPS_PATH"
echo
echo "=== WDL Inputs (stage03_produce_self_reference.wdl) ==="
awk '
  /workflow[[:space:]]+StageProduceSelfReferenceFiles/ {in_wf=1}
  in_wf && /input[[:space:]]*{/ {in_input=1; next}
  in_input {print}
  in_input && /}/ {in_input=0}
' "$WDL_PATH" | sed 's/^/  /'
echo
echo "=== JSON Inputs (stage03_produce_self_reference.json) ==="
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

#!/bin/bash
set -e
# Submit Stage05 liftover to local Cromwell.
# Inputs:
# - workflowSource: stage05_liftover.wdl
# - workflowInputs: stage05_liftover.json
# - workflowDependencies: wdl_deps.zip (if present)

ROOT_DIR="${PROJECT_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
WDL_PATH="${ROOT_DIR}/stage05_liftover.wdl"
JSON_PATH="${ROOT_DIR}/stage05_liftover.json"
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
    "StageLiftover.sample_name",
    "StageLiftover.ref_homoplasmies_vcf",
    "StageLiftover.force_call_vcf_filters",
    "StageLiftover.mt_self",
    "StageLiftover.mt_self_index",
    "StageLiftover.mt_self_dict",
    "StageLiftover.mt_self_shifted",
    "StageLiftover.mt_self_shifted_index",
    "StageLiftover.mt_self_shifted_dict",
    "StageLiftover.chain_self_to_ref",
    "StageLiftover.chain_ref_to_self",
    "StageLiftover.self_control_region_shifted_reference_interval_list",
    "StageLiftover.self_non_control_region_interval_list",
    "StageLiftover.new_self_ref_vcf",
    "StageLiftover.input_bam_regular_ref",
    "StageLiftover.input_bam_regular_ref_index",
    "StageLiftover.input_bam_shifted_ref",
    "StageLiftover.input_bam_shifted_ref_index",
    "StageLiftover.ref_fasta",
    "StageLiftover.ref_fasta_index",
    "StageLiftover.ref_dict",
    "StageLiftover.HailLiftover",
    "StageLiftover.major_haplogroup",
    "StageLiftover.contamination",
    "StageLiftover.nuc_variants_pass",
    "StageLiftover.n_reads_unpaired_dropped",
    "StageLiftover.nuc_variants_dropped",
    "StageLiftover.mtdna_consensus_overlaps",
    "StageLiftover.nuc_consensus_overlaps",
    "StageLiftover.mean_coverage",
    "StageLiftover.median_coverage",
    "StageLiftover.genomes_cloud_docker",
    "StageLiftover.ucsc_docker",
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

echo "=== Stage05 Submission Params ==="
echo "WDL:  $WDL_PATH"
echo "JSON: $JSON_PATH"
echo "DEPS: $DEPS_PATH"
echo
echo "=== WDL Inputs (stage05_liftover.wdl) ==="
awk '
  /workflow[[:space:]]+StageLiftover/ {in_wf=1}
  in_wf && /input[[:space:]]*{/ {in_input=1; next}
  in_input {print}
  in_input && /}/ {in_input=0}
' "$WDL_PATH" | sed 's/^/  /'
echo
echo "=== JSON Inputs (stage05_liftover.json) ==="
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

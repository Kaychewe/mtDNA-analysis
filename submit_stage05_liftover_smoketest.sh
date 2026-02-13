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

# Prefer a populated Stage05 JSON if available.
SOURCE_JSON="${STAGE05_JSON:-${ROOT_DIR}/stage05_liftover.json}"
OUT_JSON="${ROOT_DIR}/stage05_liftover_smoketest.inputs.json"

if [ -f "$SOURCE_JSON" ]; then
  python3 - <<PY
import json, sys
src_path = "${SOURCE_JSON}"
out_path = "${OUT_JSON}"
with open(src_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

prefix = "StageLiftover."
out_prefix = "Stage05LiftoverSmokeTest."
want_keys = {
    "HailLiftover",
    "ref_fasta",
    "ref_fasta_index",
    "ref_dict",
    "new_self_ref_vcf",
    "ref_homoplasmies_vcf",
    "force_call_vcf_filters",
    "input_bam_regular_ref",
    "input_bam_regular_ref_index",
    "input_bam_shifted_ref",
    "input_bam_shifted_ref_index",
    "chain_self_to_ref",
    "chain_ref_to_self",
    "mt_self",
    "mt_self_index",
    "mt_self_shifted",
    "mt_self_shifted_index",
    "self_control_region_shifted_reference_interval_list",
    "self_non_control_region_interval_list",
    "genomes_cloud_docker",
}

out = {}
for k, v in data.items():
    if not k.startswith(prefix):
        continue
    short = k[len(prefix):]
    if short in want_keys:
        out[out_prefix + short] = v

if not out:
    print("ERROR: No StageLiftover.* keys found in", src_path)
    sys.exit(1)

    # Build candidate list for overlap testing
    cand = []
    for key in ("StageLiftover.force_call_vcf_filters", "StageLiftover.force_call_vcf_unfiltered", "StageLiftover.force_call_vcf_shifted"):
        v = data.get(key, "")
        if isinstance(v, str) and v.strip() and "REPLACE_ME" not in v:
            cand.append(v)
    out[out_prefix + "candidate_force_call_vcfs"] = cand
else:
    out[out_prefix + "candidate_force_call_vcfs"] = []

with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(out, fh, indent=2, sort_keys=True)
    fh.write("\n")

print("Wrote", out_path)
PY
  JSON_PATH="$OUT_JSON"
else
  JSON_PATH="$TEMPLATE_JSON"
fi

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

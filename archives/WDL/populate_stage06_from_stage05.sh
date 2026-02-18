#!/bin/bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  populate_stage06_from_stage05.sh <stage05_workflow_id> [output_json]

Populates stage06_merge.json using Stage 05 outputs.
Defaults can be overridden via env:
  MERGE_PER_BATCH_DEFAULT, GENOMES_CLOUD_DOCKER_DEFAULT
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

stage05_wf="$1"
out_json="${2:-stage06_merge.json}"

if [ ! -f "$out_json" ]; then
  echo "Missing output JSON template: $out_json; creating a new one."
  echo "{}" > "$out_json"
fi

# Defaults
if [ -n "${WORKSPACE_BUCKET:-}" ]; then
  merge_per_batch_default="${MERGE_PER_BATCH_DEFAULT:-${WORKSPACE_BUCKET}/code/merge_per_batch.py}"
else
  merge_per_batch_default="${MERGE_PER_BATCH_DEFAULT:-gs://REPLACE_ME/merge_per_batch.py}"
fi

genomes_cloud_default="${GENOMES_CLOUD_DOCKER_DEFAULT:-us.gcr.io/broad-gotc-prod/genomes-in-the-cloud:2.4.2-1552931386}"

outputs_tmp="$(mktemp)"

curl -sS "http://localhost:8094/api/workflows/v1/${stage05_wf}/outputs" -o "${outputs_tmp}" || true
if [ ! -s "${outputs_tmp}" ] || ! grep -q '"outputs"' "${outputs_tmp}"; then
  curl -sS "http://localhost:8094/api/workflows/v1/${stage05_wf}/metadata?includeKey=outputs" -o "${outputs_tmp}" || true
fi
if [ ! -s "${outputs_tmp}" ]; then
  echo "ERROR: empty outputs/metadata response for workflow ${stage05_wf}"
  rm -f "${outputs_tmp}"
  exit 1
fi

python3 - <<PY
import json
import sys
import json as _json

with open("${outputs_tmp}", "r", encoding="utf-8") as fh:
    outputs = json.load(fh)
try:
    with open("${out_json}", "r", encoding="utf-8") as fh:
        data = json.load(fh)
except _json.JSONDecodeError:
    print("WARNING: output JSON template is invalid; starting from empty template.", file=sys.stderr)
    data = {}

def get_out(key):
    return outputs.get("outputs", {}).get(key, "")

def replace_if_missing(key, value):
    current = data.get(key, "")
    if not current or "REPLACE_ME" in str(current):
        if value:
            data[key] = value

sample_name = data.get("StageMerge.sample_name", [])
if not sample_name or "REPLACE_ME" in str(sample_name):
    # try to infer from workflow name if present
    sample = get_out("StageLiftover.sample_name")
    if sample:
        data["StageMerge.sample_name"] = [sample]

replace_if_missing("StageMerge.variant_vcf", [get_out("StageLiftover.final_vcf")])
replace_if_missing("StageMerge.coverage_table", [get_out("StageLiftover.final_base_level_coverage_metrics")])
replace_if_missing("StageMerge.statistics", [get_out("StageLiftover.stats_outputs")])

replace_if_missing("StageMerge.MergePerBatch", "${merge_per_batch_default}")
replace_if_missing("StageMerge.genomes_cloud_docker", "${genomes_cloud_default}")

with open("${out_json}", "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY

rm -f "${outputs_tmp}"

printf 'Wrote %s\n' "$out_json"

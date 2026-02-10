#!/bin/bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  populate_diagnostic_chainswap_liftover.sh <stage03_workflow_id> [output_json]

Populates diagnostic_chainswap_liftover.json using Stage03 outputs.
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

stage03_wf="$1"
out_json="${2:-diagnostic_chainswap_liftover.json}"

if [ ! -f "$out_json" ]; then
  echo "Missing output JSON template: $out_json; creating a new one."
  echo "{}" > "$out_json"
fi

outputs_tmp="$(mktemp)"
meta_tmp="$(mktemp)"

curl -sS "http://localhost:8094/api/workflows/v1/${stage03_wf}/outputs" -o "${outputs_tmp}" || true
if [ ! -s "${outputs_tmp}" ] || ! grep -q '"outputs"' "${outputs_tmp}"; then
  curl -sS "http://localhost:8094/api/workflows/v1/${stage03_wf}/metadata?includeKey=outputs" -o "${outputs_tmp}" || true
fi
curl -sS "http://localhost:8094/api/workflows/v1/${stage03_wf}/metadata?includeKey=calls&includeKey=callRoot&includeKey=inputs" -o "${meta_tmp}" || true
if [ ! -s "${meta_tmp}" ]; then
  echo '{"calls": {}}' > "${meta_tmp}"
fi

python3 - <<PY
import json
import sys
import json as _json

with open("${outputs_tmp}", "r", encoding="utf-8") as fh:
    outputs = json.load(fh)
with open("${meta_tmp}", "r", encoding="utf-8") as fh:
    meta = json.load(fh)
try:
    with open("${out_json}", "r", encoding="utf-8") as fh:
        data = json.load(fh)
except _json.JSONDecodeError:
    print("WARNING: output JSON template is invalid; starting from empty template.", file=sys.stderr)
    data = {}

stage03_json_path = "stage03_produce_self_reference.json"
stage03_inputs = {}
try:
    with open(stage03_json_path, "r", encoding="utf-8") as fh:
        stage03_inputs = json.load(fh)
except FileNotFoundError:
    stage03_inputs = {}

def get_out(key):
    return outputs.get("outputs", {}).get(key, "")

def replace_if_missing(key, value):
    current = data.get(key, "")
    if not current or "REPLACE_ME" in str(current):
        if value:
            data[key] = value

replace_if_missing("DiagnosticChainSwapLiftover.source_chain", get_out("StageProduceSelfReferenceFiles.ref_to_self_chain"))
replace_if_missing("DiagnosticChainSwapLiftover.input_target_name", get_out("StageProduceSelfReferenceFiles.sample_name"))
replace_if_missing("DiagnosticChainSwapLiftover.input_bed", get_out("StageProduceSelfReferenceFiles.blacklisted_sites"))
replace_if_missing("DiagnosticChainSwapLiftover.input_bed_index", get_out("StageProduceSelfReferenceFiles.blacklisted_sites_index"))

# Fall back to Stage03 input JSON when outputs are missing.
if stage03_inputs:
    replace_if_missing("DiagnosticChainSwapLiftover.input_target_name", stage03_inputs.get("StageProduceSelfReferenceFiles.sample_name", ""))
    replace_if_missing("DiagnosticChainSwapLiftover.input_bed", stage03_inputs.get("StageProduceSelfReferenceFiles.blacklisted_sites", ""))
    replace_if_missing("DiagnosticChainSwapLiftover.input_bed_index", stage03_inputs.get("StageProduceSelfReferenceFiles.blacklisted_sites_index", ""))

# If source_chain is still missing, try to infer from callRoot.
call_root = ""
calls = meta.get("calls", {}).get("StageProduceSelfReferenceFiles.ProduceSelfReferenceFiles", [])
if calls and isinstance(calls, list):
    call_root = calls[0].get("callRoot", "") or ""
sample = data.get("DiagnosticChainSwapLiftover.input_target_name", "")
if not data.get("DiagnosticChainSwapLiftover.source_chain") and call_root and sample:
    candidate = f\"{call_root}/call-MtConsensus/out/reference_to_{sample}.chain\"
    data[\"DiagnosticChainSwapLiftover.source_chain\"] = candidate

with open("${out_json}", "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY

rm -f "${outputs_tmp}" "${meta_tmp}"

printf 'Wrote %s\n' "$out_json"

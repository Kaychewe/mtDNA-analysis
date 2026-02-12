#!/bin/bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  populate_stage04_from_stage03.sh --stage01 <workflow_id> --stage02 <workflow_id> --stage03 <workflow_id> [options] [output_json]

Options:
  --sample-name <id>   Override sample name
  -h, --help           Show help

Populates stage04_align_call_r2.json using Stage01/02/03 outputs.
Defaults are sourced from stage02_align_call_r1.json when available.
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

stage01_wf=""
stage02_wf=""
stage03_wf=""
sample_name_override=""
out_json="stage04_align_call_r2.json"

while [ $# -gt 0 ]; do
  case "$1" in
    --stage01)
      stage01_wf="${2:-}"
      shift 2
      ;;
    --stage02)
      stage02_wf="${2:-}"
      shift 2
      ;;
    --stage03)
      stage03_wf="${2:-}"
      shift 2
      ;;
    --sample-name)
      sample_name_override="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -* )
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      out_json="$1"
      shift
      ;;
  esac
done

if [ -z "$stage01_wf" ] || [ -z "$stage02_wf" ] || [ -z "$stage03_wf" ]; then
  echo "ERROR: --stage01, --stage02, and --stage03 workflow IDs are required."
  usage
  exit 1
fi

if [ ! -f "$out_json" ]; then
  echo "Missing output JSON template: $out_json; creating a new one."
  echo "{}" > "$out_json"
fi

stage02_json="${STAGE02_JSON:-stage02_align_call_r1.json}"
if [ -f "$stage02_json" ]; then
  echo "Using Stage 02 JSON for defaults: ${stage02_json}"
else
  echo "Stage 02 JSON not found: ${stage02_json}; defaults will use env fallbacks."
fi

fetch_outputs() {
  local wf_id="$1"
  local out_file="$2"
  curl -sS "http://localhost:8094/api/workflows/v1/${wf_id}/outputs" -o "$out_file" || true
  if [ ! -s "$out_file" ] || ! grep -q '"outputs"' "$out_file"; then
    curl -sS "http://localhost:8094/api/workflows/v1/${wf_id}/metadata?includeKey=outputs" -o "$out_file" || true
  fi
  if [ ! -s "$out_file" ]; then
    echo "ERROR: empty outputs/metadata response for workflow ${wf_id}"
    exit 1
  fi
}

s1_tmp="$(mktemp)"
s2_tmp="$(mktemp)"
s3_tmp="$(mktemp)"

fetch_outputs "$stage01_wf" "$s1_tmp"
fetch_outputs "$stage02_wf" "$s2_tmp"
fetch_outputs "$stage03_wf" "$s3_tmp"

unmapped_bam_override=""
sample_name_fallback=""
if [ -n "${WORKSPACE_BUCKET:-}" ]; then
  gcs_out="${WORKSPACE_BUCKET}/workflows/cromwell-executions/StageSubsetBamToChrMAndRevert/${stage01_wf}/call-SubsetBamToChrMAndRevert/out"
  unmapped_bam_override="$(gsutil ls "${gcs_out}"/*.unmap.bam 2>/dev/null | head -n 1 || true)"
  if [ -n "${unmapped_bam_override}" ]; then
    base_name="$(basename "${unmapped_bam_override}")"
    sample_name_fallback="${base_name%.unmap.bam}"
  fi
fi

UNMAPPED_BAM_OVERRIDE="${unmapped_bam_override}" \
SAMPLE_NAME_FALLBACK="${sample_name_fallback}" \
python3 - <<PY
import json
import sys
import json as _json

with open("${s1_tmp}", "r", encoding="utf-8") as fh:
    s1 = json.load(fh)
with open("${s2_tmp}", "r", encoding="utf-8") as fh:
    s2o = json.load(fh)
with open("${s3_tmp}", "r", encoding="utf-8") as fh:
    s3 = json.load(fh)

try:
    with open("${out_json}", "r", encoding="utf-8") as fh:
        data = json.load(fh)
except _json.JSONDecodeError:
    print("WARNING: output JSON template is invalid; starting from empty template.", file=sys.stderr)
    data = {}

s2 = {}
try:
    with open("${stage02_json}", "r", encoding="utf-8") as fh:
        s2 = json.load(fh)
except FileNotFoundError:
    s2 = {}

def get_out(outputs, key):
    return outputs.get("outputs", {}).get(key, "")

def get_any_out(outputs, keys):
    for k in keys:
        v = get_out(outputs, k)
        if v != "":
            return v
    return ""

def replace_if_missing(key, value):
    current = data.get(key, "")
    if not current or "REPLACE_ME" in str(current):
        if value != "":
            data[key] = value

# Stage01 output
unmapped_bam = get_out(s1, "StageSubsetBamToChrMAndRevert.unmapped_bam")
if not unmapped_bam:
    unmapped_bam = "${UNMAPPED_BAM_OVERRIDE:-}"
replace_if_missing("StageAlignAndCallR2.unmapped_bam", unmapped_bam)

# Stage03 outputs
replace_if_missing("StageAlignAndCallR2.mt_interval_list_self", get_out(s3, "StageProduceSelfReferenceFiles.mt_interval_list_self"))
replace_if_missing("StageAlignAndCallR2.mt_self", get_out(s3, "StageProduceSelfReferenceFiles.mt_self"))
replace_if_missing("StageAlignAndCallR2.mt_self_index", get_out(s3, "StageProduceSelfReferenceFiles.mt_self_index"))
replace_if_missing("StageAlignAndCallR2.mt_self_dict", get_out(s3, "StageProduceSelfReferenceFiles.mt_self_dict"))
replace_if_missing("StageAlignAndCallR2.mt_andNuc_self", get_out(s3, "StageProduceSelfReferenceFiles.mt_andNuc_self"))
replace_if_missing("StageAlignAndCallR2.mt_andNuc_self_index", get_out(s3, "StageProduceSelfReferenceFiles.mt_andNuc_self_index"))
replace_if_missing("StageAlignAndCallR2.mt_andNuc_self_dict", get_out(s3, "StageProduceSelfReferenceFiles.mt_andNuc_self_dict"))
replace_if_missing("StageAlignAndCallR2.mt_shifted_self", get_out(s3, "StageProduceSelfReferenceFiles.mt_shifted_self"))
replace_if_missing("StageAlignAndCallR2.mt_shifted_self_index", get_out(s3, "StageProduceSelfReferenceFiles.mt_shifted_self_index"))
replace_if_missing("StageAlignAndCallR2.mt_shifted_self_dict", get_out(s3, "StageProduceSelfReferenceFiles.mt_shifted_self_dict"))
replace_if_missing("StageAlignAndCallR2.mt_andNuc_shifted_self", get_out(s3, "StageProduceSelfReferenceFiles.mt_andNuc_shifted_self"))
replace_if_missing("StageAlignAndCallR2.mt_andNuc_shifted_self_index", get_out(s3, "StageProduceSelfReferenceFiles.mt_andNuc_shifted_self_index"))
replace_if_missing("StageAlignAndCallR2.mt_andNuc_shifted_self_dict", get_out(s3, "StageProduceSelfReferenceFiles.mt_andNuc_shifted_self_dict"))
replace_if_missing("StageAlignAndCallR2.blacklisted_sites_self", get_out(s3, "StageProduceSelfReferenceFiles.blacklisted_sites_self"))
replace_if_missing("StageAlignAndCallR2.blacklisted_sites_index_self", get_out(s3, "StageProduceSelfReferenceFiles.blacklisted_sites_index_self"))
replace_if_missing("StageAlignAndCallR2.force_call_vcf", get_out(s3, "StageProduceSelfReferenceFiles.force_call_vcf"))
replace_if_missing("StageAlignAndCallR2.force_call_vcf_idx", get_out(s3, "StageProduceSelfReferenceFiles.force_call_vcf_idx"))
replace_if_missing("StageAlignAndCallR2.force_call_vcf_shifted", get_out(s3, "StageProduceSelfReferenceFiles.force_call_vcf_shifted"))
replace_if_missing("StageAlignAndCallR2.force_call_vcf_shifted_idx", get_out(s3, "StageProduceSelfReferenceFiles.force_call_vcf_shifted_idx"))
replace_if_missing("StageAlignAndCallR2.self_shift_back_chain", get_out(s3, "StageProduceSelfReferenceFiles.self_shift_back_chain"))
replace_if_missing("StageAlignAndCallR2.non_control_interval_self", get_out(s3, "StageProduceSelfReferenceFiles.non_control_interval_self"))
replace_if_missing("StageAlignAndCallR2.control_shifted_self", get_out(s3, "StageProduceSelfReferenceFiles.control_shifted_self"))

# Stage02 contamination outputs (try multiple possible keys)
has_contam = get_any_out(s2o, [
    "StageAlignAndCallR1.hasContamination",
    "AlignAndCallR1.hasContamination",
    "MitochondriaPipelineWrapper.hasContamination",
])
contam_major = get_any_out(s2o, [
    "StageAlignAndCallR1.contamination_major",
    "AlignAndCallR1.contamination_major",
    "MitochondriaPipelineWrapper.contamination_major",
])
contam_minor = get_any_out(s2o, [
    "StageAlignAndCallR1.contamination_minor",
    "AlignAndCallR1.contamination_minor",
    "MitochondriaPipelineWrapper.contamination_minor",
])

replace_if_missing("StageAlignAndCallR2.hasContamination", has_contam)
replace_if_missing("StageAlignAndCallR2.contamination_major", contam_major)
replace_if_missing("StageAlignAndCallR2.contamination_minor", contam_minor)

# If still missing, set safe defaults (and warn in output JSON)
if not data.get("StageAlignAndCallR2.hasContamination") or "REPLACE_ME" in str(data.get("StageAlignAndCallR2.hasContamination")):
    data["StageAlignAndCallR2.hasContamination"] = "false"
if not str(data.get("StageAlignAndCallR2.contamination_major", "")).strip() or "REPLACE_ME" in str(data.get("StageAlignAndCallR2.contamination_major")):
    data["StageAlignAndCallR2.contamination_major"] = 0.0
if not str(data.get("StageAlignAndCallR2.contamination_minor", "")).strip() or "REPLACE_ME" in str(data.get("StageAlignAndCallR2.contamination_minor")):
    data["StageAlignAndCallR2.contamination_minor"] = 0.0

# Sample name
sample_name = "${sample_name_override}"
if not sample_name:
    sample_name = data.get("StageAlignAndCallR2.sample_name", "")
if not sample_name:
    sample_name = s2.get("StageAlignAndCallR1.sample_name", "")
if not sample_name:
    sample_name = get_out(s2o, "StageAlignAndCallR1.sample_name")
if not sample_name:
    sample_name = get_out(s3, "StageProduceSelfReferenceFiles.sample_name")
if not sample_name:
    sample_name = "${SAMPLE_NAME_FALLBACK:-}"
if not sample_name:
    mt_self = get_out(s3, "StageProduceSelfReferenceFiles.mt_self")
    if mt_self and mt_self.endswith(".self.ref.fasta"):
        base = mt_self.rsplit("/", 1)[-1]
        sample_name = base.replace(".self.ref.fasta", "")
if not sample_name:
    force_vcf = get_out(s3, "StageProduceSelfReferenceFiles.force_call_vcf")
    if force_vcf:
        base = force_vcf.rsplit("/", 1)[-1]
        if ".self.ref" in base:
            sample_name = base.split(".self.ref", 1)[0]
if sample_name:
    data["StageAlignAndCallR2.sample_name"] = sample_name

# Defaults from Stage 02 JSON
replace_if_missing("StageAlignAndCallR2.gatk_version", s2.get("StageAlignAndCallR1.gatk_version", "4.2.6.0"))
replace_if_missing("StageAlignAndCallR2.gatk_docker_override", s2.get("StageAlignAndCallR1.gatk_docker_override", ""))
replace_if_missing("StageAlignAndCallR2.m2_extra_args", s2.get("StageAlignAndCallR1.m2_extra_args", ""))
replace_if_missing("StageAlignAndCallR2.m2_filter_extra_args", s2.get("StageAlignAndCallR1.m2_filter_extra_args", ""))
replace_if_missing("StageAlignAndCallR2.vaf_filter_threshold", s2.get("StageAlignAndCallR1.vaf_filter_threshold", ""))
replace_if_missing("StageAlignAndCallR2.f_score_beta", s2.get("StageAlignAndCallR1.f_score_beta", ""))
replace_if_missing("StageAlignAndCallR2.verifyBamID", s2.get("StageAlignAndCallR1.verifyBamID", ""))
replace_if_missing("StageAlignAndCallR2.max_read_length", s2.get("StageAlignAndCallR1.max_read_length", ""))

# Defaults for docker overrides (Stage04-specific)
replace_if_missing("StageAlignAndCallR2.gatk_docker_override", s2.get("StageAlignAndCallR1.gatk_docker_override", ""))

with open("${out_json}", "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY

rm -f "$s1_tmp" "$s2_tmp" "$s3_tmp"

printf 'Wrote %s\n' "$out_json"

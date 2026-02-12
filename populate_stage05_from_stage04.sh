#!/bin/bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  populate_stage05_from_stage04.sh --stage03 <stage03_workflow_id> --stage04 <stage04_workflow_id> [options] [output_json]

Options:
  --stage02 <workflow_id>   Optional; used for major_haplogroup/contamination/nuc_variants_pass and reference defaults
  --stage01 <workflow_id>   Optional; used for n_reads_unpaired_dropped
  --sample-name <id>        Override sample name
  -h, --help                Show help

Populates stage05_liftover.json using Stage 03 + Stage 04 outputs.
Defaults are sourced from stage02_align_call_r1.json when available and from env vars:
  GENOMES_CLOUD_DOCKER_DEFAULT, UCSC_DOCKER_DEFAULT, UCSC_TOOLS_BUNDLE_DEFAULT,
  HAIL_LIFTOVER_DEFAULT, REF_FASTA_DEFAULT, REF_FASTA_INDEX_DEFAULT, REF_DICT_DEFAULT,
  MAJOR_HAPLOGROUP_DEFAULT
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

stage03_wf=""
stage04_wf=""
stage02_wf=""
stage01_wf=""
sample_name_override=""
out_json="stage05_liftover.json"

while [ $# -gt 0 ]; do
  case "$1" in
    --stage03)
      stage03_wf="${2:-}"
      shift 2
      ;;
    --stage04)
      stage04_wf="${2:-}"
      shift 2
      ;;
    --stage02)
      stage02_wf="${2:-}"
      shift 2
      ;;
    --stage01)
      stage01_wf="${2:-}"
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

if [ -z "$stage03_wf" ] || [ -z "$stage04_wf" ]; then
  echo "ERROR: --stage03 and --stage04 workflow IDs are required."
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

# Defaults
ref_fasta_default="${REF_FASTA_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.fasta}"
ref_fasta_index_default="${REF_FASTA_INDEX_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.fasta.fai}"
ref_dict_default="${REF_DICT_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.dict}"

if [ -n "${WORKSPACE_BUCKET:-}" ]; then
  hail_liftover_default="${HAIL_LIFTOVER_DEFAULT:-${WORKSPACE_BUCKET}/code/fix_liftover.py}"
else
  hail_liftover_default="${HAIL_LIFTOVER_DEFAULT:-gs://REPLACE_ME/code/fix_liftover.py}"
fi

genomes_cloud_default="${GENOMES_CLOUD_DOCKER_DEFAULT:-kchewe/mtdna-stage05:0.1.0}"
ucsc_docker_default="${UCSC_DOCKER_DEFAULT:-kchewe/mtdna-stage04:0.1.3}"
ucsc_tools_bundle_default="${UCSC_TOOLS_BUNDLE_DEFAULT:-gs://fc-secure-76d68a64-00aa-40a7-b2c5-ca956db2719b/tools/ucsc/ucsc-tools-linux-x86_64.tar.gz}"
major_haplogroup_default="${MAJOR_HAPLOGROUP_DEFAULT:-UNKNOWN}"

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

stage03_tmp="$(mktemp)"
stage04_tmp="$(mktemp)"
stage02_tmp="$(mktemp)"
stage01_tmp="$(mktemp)"

fetch_outputs "$stage03_wf" "$stage03_tmp"
fetch_outputs "$stage04_wf" "$stage04_tmp"
if [ -n "$stage02_wf" ]; then
  fetch_outputs "$stage02_wf" "$stage02_tmp"
else
  echo '{"outputs": {}}' > "$stage02_tmp"
fi
if [ -n "$stage01_wf" ]; then
  fetch_outputs "$stage01_wf" "$stage01_tmp"
else
  echo '{"outputs": {}}' > "$stage01_tmp"
fi

python3 - <<PY
import json
import sys
import json as _json

with open("${stage03_tmp}", "r", encoding="utf-8") as fh:
    s3 = json.load(fh)
with open("${stage04_tmp}", "r", encoding="utf-8") as fh:
    s4 = json.load(fh)
with open("${stage02_tmp}", "r", encoding="utf-8") as fh:
    s2o = json.load(fh)
with open("${stage01_tmp}", "r", encoding="utf-8") as fh:
    s1o = json.load(fh)

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

def replace_if_missing(key, value):
    current = data.get(key, "")
    if not current or "REPLACE_ME" in str(current):
        if value != "":
            data[key] = value

# Stage03 outputs
replace_if_missing("StageLiftover.ref_homoplasmies_vcf", get_out(s3, "StageProduceSelfReferenceFiles.ref_homoplasmies_vcf"))
replace_if_missing("StageLiftover.force_call_vcf_filters", get_out(s3, "StageProduceSelfReferenceFiles.force_call_vcf_filters"))

replace_if_missing("StageLiftover.mt_self", get_out(s3, "StageProduceSelfReferenceFiles.mt_self"))
replace_if_missing("StageLiftover.mt_self_index", get_out(s3, "StageProduceSelfReferenceFiles.mt_self_index"))
replace_if_missing("StageLiftover.mt_self_dict", get_out(s3, "StageProduceSelfReferenceFiles.mt_self_dict"))
replace_if_missing("StageLiftover.mt_self_shifted", get_out(s3, "StageProduceSelfReferenceFiles.mt_shifted_self"))
replace_if_missing("StageLiftover.mt_self_shifted_index", get_out(s3, "StageProduceSelfReferenceFiles.mt_shifted_self_index"))
replace_if_missing("StageLiftover.mt_self_shifted_dict", get_out(s3, "StageProduceSelfReferenceFiles.mt_shifted_self_dict"))
replace_if_missing("StageLiftover.chain_self_to_ref", get_out(s3, "StageProduceSelfReferenceFiles.self_to_ref_chain"))
replace_if_missing("StageLiftover.chain_ref_to_self", get_out(s3, "StageProduceSelfReferenceFiles.ref_to_self_chain"))
replace_if_missing("StageLiftover.self_control_region_shifted_reference_interval_list", get_out(s3, "StageProduceSelfReferenceFiles.control_shifted_self"))
replace_if_missing("StageLiftover.self_non_control_region_interval_list", get_out(s3, "StageProduceSelfReferenceFiles.non_control_interval_self"))

replace_if_missing("StageLiftover.nuc_variants_dropped", get_out(s3, "StageProduceSelfReferenceFiles.nuc_variants_dropped"))
replace_if_missing("StageLiftover.mtdna_consensus_overlaps", get_out(s3, "StageProduceSelfReferenceFiles.mtdna_consensus_overlaps"))
replace_if_missing("StageLiftover.nuc_consensus_overlaps", get_out(s3, "StageProduceSelfReferenceFiles.nuc_consensus_overlaps"))

# Stage04 outputs
replace_if_missing("StageLiftover.new_self_ref_vcf", get_out(s4, "StageAlignAndCallR2.split_vcf"))
replace_if_missing("StageLiftover.input_bam_regular_ref", get_out(s4, "StageAlignAndCallR2.mt_aligned_bam"))
replace_if_missing("StageLiftover.input_bam_regular_ref_index", get_out(s4, "StageAlignAndCallR2.mt_aligned_bai"))
replace_if_missing("StageLiftover.input_bam_shifted_ref", get_out(s4, "StageAlignAndCallR2.mt_aligned_shifted_bam"))
replace_if_missing("StageLiftover.input_bam_shifted_ref_index", get_out(s4, "StageAlignAndCallR2.mt_aligned_shifted_bai"))
replace_if_missing("StageLiftover.mean_coverage", get_out(s4, "StageAlignAndCallR2.mean_coverage"))
replace_if_missing("StageLiftover.median_coverage", get_out(s4, "StageAlignAndCallR2.median_coverage"))

# Stage02 outputs for stats
replace_if_missing("StageLiftover.major_haplogroup", get_out(s2o, "StageAlignAndCallR1.major_haplogroup"))
replace_if_missing("StageLiftover.contamination", get_out(s2o, "StageAlignAndCallR1.contamination"))
replace_if_missing("StageLiftover.nuc_variants_pass", get_out(s2o, "StageAlignAndCallR1.nuc_variants_pass"))

# Stage01 outputs
replace_if_missing("StageLiftover.n_reads_unpaired_dropped", get_out(s1o, "StageSubsetBamToChrMAndRevert.reads_dropped"))

# Sample name
sample_name = "${sample_name_override}"
if not sample_name:
    sample_name = data.get("StageLiftover.sample_name", "")
if not sample_name:
    sample_name = get_out(s4, "StageAlignAndCallR2.sample_name")
if not sample_name:
    sample_name = get_out(s3, "StageProduceSelfReferenceFiles.sample_name")
if sample_name:
    data["StageLiftover.sample_name"] = sample_name

# Defaults from Stage02 JSON
replace_if_missing("StageLiftover.ref_fasta", s2.get("StageAlignAndCallR1.ref_fasta", "${ref_fasta_default}"))
replace_if_missing("StageLiftover.ref_fasta_index", s2.get("StageAlignAndCallR1.ref_fasta_index", "${ref_fasta_index_default}"))
replace_if_missing("StageLiftover.ref_dict", s2.get("StageAlignAndCallR1.ref_dict", "${ref_dict_default}"))
replace_if_missing("StageLiftover.HailLiftover", s2.get("StageAlignAndCallR1.HailLiftover", "${hail_liftover_default}"))
replace_if_missing("StageLiftover.genomes_cloud_docker", s2.get("StageAlignAndCallR1.genomes_cloud_docker", "${genomes_cloud_default}"))
replace_if_missing("StageLiftover.ucsc_docker", s2.get("StageAlignAndCallR1.ucsc_docker", "${ucsc_docker_default}"))
replace_if_missing("StageLiftover.ucsc_tools_bundle", "${ucsc_tools_bundle_default}")

# Final fallback for major_haplogroup if still missing
replace_if_missing("StageLiftover.major_haplogroup", "${major_haplogroup_default}")

with open("${out_json}", "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY

# Fallback: if chain paths are still missing and WORKSPACE_BUCKET is set, try gsutil search.
python3 - <<PY
import json, os, sys, subprocess
p="${out_json}"
data=json.load(open(p))

need_ref_to_self = (not str(data.get("StageLiftover.chain_ref_to_self","")).strip()) or ("REPLACE_ME" in str(data.get("StageLiftover.chain_ref_to_self","")))
need_self_to_ref = (not str(data.get("StageLiftover.chain_self_to_ref","")).strip()) or ("REPLACE_ME" in str(data.get("StageLiftover.chain_self_to_ref","")))
need_force_call_filters = (not str(data.get("StageLiftover.force_call_vcf_filters","")).strip()) or ("REPLACE_ME" in str(data.get("StageLiftover.force_call_vcf_filters","")))
need_ref_homoplasmies = (not str(data.get("StageLiftover.ref_homoplasmies_vcf","")).strip()) or ("REPLACE_ME" in str(data.get("StageLiftover.ref_homoplasmies_vcf","")))

ws = os.environ.get("WORKSPACE_BUCKET","").strip()
stage03 = "${stage03_wf}"
if ws and (need_ref_to_self or need_self_to_ref):
    base = f"{ws}/workflows/cromwell-executions/StageProduceSelfReferenceFiles/{stage03}/call-ProduceSelfReferenceFiles/ProduceSelfReferenceFiles"
    if need_ref_to_self:
        try:
            pattern = f"{base}/*/call-MtConsensus/out/reference_to_*.chain"
            out = subprocess.check_output(["gsutil","ls",pattern], text=True).strip().splitlines()
            if out:
                data["StageLiftover.chain_ref_to_self"] = out[0]
        except Exception as e:
            print(f"WARNING: failed to resolve chain_ref_to_self via gsutil: {e}", file=sys.stderr)
    if need_self_to_ref:
        try:
            pattern = f"{base}/*/call-ChainSwapLiftoverBed/out/*_to_reference.chain"
            out = subprocess.check_output(["gsutil","ls",pattern], text=True).strip().splitlines()
            if out:
                data["StageLiftover.chain_self_to_ref"] = out[0]
        except Exception as e:
            print(f"WARNING: failed to resolve chain_self_to_ref via gsutil: {e}", file=sys.stderr)
    if need_force_call_filters:
        try:
            pattern = f"{base}/*/call-ForceCallVcfs/out/*.withfilters*.vcf.bgz"
            out = subprocess.check_output(["gsutil","ls",pattern], text=True).strip().splitlines()
            if out:
                data["StageLiftover.force_call_vcf_filters"] = out[0]
        except Exception as e:
            print(f"WARNING: failed to resolve force_call_vcf_filters via gsutil: {e}", file=sys.stderr)
    if need_ref_homoplasmies:
        try:
            pattern = f"{base}/*/call-RemoveMtOverlaps/cleaned_mt.vcf"
            out = subprocess.check_output(["gsutil","ls",pattern], text=True).strip().splitlines()
            if out:
                data["StageLiftover.ref_homoplasmies_vcf"] = out[0]
        except Exception as e:
            print(f"WARNING: failed to resolve ref_homoplasmies_vcf via gsutil: {e}", file=sys.stderr)

with open(p, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
    fh.write("\\n")
PY

rm -f "$stage03_tmp" "$stage04_tmp" "$stage02_tmp" "$stage01_tmp"

printf 'Wrote %s\n' "$out_json"

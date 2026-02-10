#!/bin/bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  populate_stage03_from_stage02.sh <stage02_workflow_id> [output_json]
  populate_stage03_from_stage02.sh --mtdna-vcf <gs://...split.vcf> \
    --nuc-vcf <gs://...split_nuc.vcf> [--sample-name <id>] [output_json]

Populates stage03_produce_self_reference.json using Stage 02 outputs:
  - split_vcf (mtDNA variants)
  - split_nuc_vcf (nucDNA variants)

Defaults for references, intervals, scripts, and docker images are filled if
values are missing or REPLACE_ME. You can override defaults via environment:
  SELF_REF_SUFFIX_DEFAULT
  REFERENCE_NAME_DEFAULT
  NON_CONTROL_INTERVAL_DEFAULT
  FA_RENAMING_SCRIPT_DEFAULT
  CHECK_VARIANT_BOUNDS_DEFAULT
  CHECK_HOM_OVERLAP_DEFAULT
  GENOMES_CLOUD_DOCKER_DEFAULT
  BCFTOOLS_DOCKER_DEFAULT
  GOTC_DOCKER_DEFAULT
  UCSC_DOCKER_DEFAULT
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

WF_ID=""
mtdna_vcf_override=""
nuc_vcf_override=""
sample_name_override=""
out_json="stage03_produce_self_reference.json"

while [ $# -gt 0 ]; do
  case "$1" in
    --mtdna-vcf)
      mtdna_vcf_override="${2:-}"
      shift 2
      ;;
    --nuc-vcf)
      nuc_vcf_override="${2:-}"
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
    -*)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      if [ -z "${WF_ID}" ] && [ -z "${mtdna_vcf_override}" ] && [ -z "${nuc_vcf_override}" ]; then
        WF_ID="$1"
      else
        out_json="$1"
      fi
      shift
      ;;
  esac
done

if [ -z "${WF_ID}" ] && { [ -z "${mtdna_vcf_override}" ] || [ -z "${nuc_vcf_override}" ]; }; then
  echo "ERROR: provide a workflow ID or both --mtdna-vcf and --nuc-vcf."
  usage
  exit 1
fi

if [ ! -f "$out_json" ]; then
  echo "Missing output JSON template: $out_json"
  exit 1
fi

stage02_json="${STAGE02_JSON:-stage02_align_call_r1.json}"
if [ ! -f "$stage02_json" ]; then
  echo "Missing Stage 02 JSON for defaults: $stage02_json"
  exit 1
fi
echo "Using Stage 02 JSON: ${stage02_json}"

suffix_default="${SELF_REF_SUFFIX_DEFAULT:-.self.ref}"
reference_name_default="${REFERENCE_NAME_DEFAULT:-reference}"
non_control_interval_default="${NON_CONTROL_INTERVAL_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/chrM/non_control_region.chrM.interval_list}"

if [ -n "${WORKSPACE_BUCKET:-}" ]; then
  fa_renaming_default="${FA_RENAMING_SCRIPT_DEFAULT:-${WORKSPACE_BUCKET}/code/compatibilify_fa_intervals_consensus.R}"
  check_bounds_default="${CHECK_VARIANT_BOUNDS_DEFAULT:-${WORKSPACE_BUCKET}/code/check_variant_bounds.R}"
  check_overlap_default="${CHECK_HOM_OVERLAP_DEFAULT:-${WORKSPACE_BUCKET}/code/check_overlapping_homoplasmies.R}"
else
  fa_renaming_default="${FA_RENAMING_SCRIPT_DEFAULT:-gs://REPLACE_ME/compatibilify_fa_intervals_consensus.R}"
  check_bounds_default="${CHECK_VARIANT_BOUNDS_DEFAULT:-gs://REPLACE_ME/check_variant_bounds.R}"
  check_overlap_default="${CHECK_HOM_OVERLAP_DEFAULT:-gs://REPLACE_ME/check_overlapping_homoplasmies.R}"
fi

# Reference defaults (fallback if Stage 02 JSON is missing or still REPLACE_ME)
ref_fasta_default="${REF_FASTA_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.fasta}"
ref_fasta_index_default="${REF_FASTA_INDEX_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.fasta.fai}"
ref_dict_default="${REF_DICT_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.dict}"
mt_fasta_default="${MT_FASTA_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/chrM/Homo_sapiens_assembly38.chrM.fasta}"
mt_fasta_index_default="${MT_FASTA_INDEX_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/chrM/Homo_sapiens_assembly38.chrM.fasta.fai}"
mt_dict_default="${MT_DICT_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/chrM/Homo_sapiens_assembly38.chrM.dict}"
mt_interval_default="${MT_INTERVAL_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/chrM/chrM.hg38.interval_list}"
if [ -n "${WORKSPACE_BUCKET:-}" ]; then
  nuc_interval_default="${NUC_INTERVAL_DEFAULT:-${WORKSPACE_BUCKET}/intervals/NUMTv3_all385.hg38.interval_list}"
else
  nuc_interval_default="${NUC_INTERVAL_DEFAULT:-gs://REPLACE_ME/NUMTv3_all385.hg38.interval_list}"
fi

# Docker defaults
# Note: bcftools_docker is optional in the workflow; leave empty unless overridden.

genomes_cloud_default="${GENOMES_CLOUD_DOCKER_DEFAULT:-us.gcr.io/broad-gotc-prod/genomes-in-the-cloud:2.4.2-1552931386}"
gotc_docker_default="${GOTC_DOCKER_DEFAULT:-${genomes_cloud_default}}"
ucsc_docker_default="${UCSC_DOCKER_DEFAULT:-quay.io/biocontainers/ucsc-bedgraphtobigwig:377--h73cb82a_3}"
bcftools_docker_default="${BCFTOOLS_DOCKER_DEFAULT:-${genomes_cloud_default}}"

outputs_tmp="$(mktemp)"
if [ -n "${WF_ID}" ]; then
  curl -sS "http://localhost:8094/api/workflows/v1/${WF_ID}/outputs" -o "${outputs_tmp}" || true
  if [ ! -s "${outputs_tmp}" ] || ! grep -q '"outputs"' "${outputs_tmp}"; then
    curl -sS "http://localhost:8094/api/workflows/v1/${WF_ID}/metadata?includeKey=outputs" -o "${outputs_tmp}" || true
  fi
  if [ ! -s "${outputs_tmp}" ]; then
    echo "ERROR: empty outputs/metadata response for workflow ${WF_ID}"
    rm -f "${outputs_tmp}"
    exit 1
  fi
else
  echo '{"outputs": {}}' > "${outputs_tmp}"
fi

python3 - <<PY
import json
import sys

with open("${outputs_tmp}", "r", encoding="utf-8") as fh:
    outputs = json.load(fh)
with open("${out_json}", "r", encoding="utf-8") as fh:
    data = json.load(fh)
with open("${stage02_json}", "r", encoding="utf-8") as fh:
    s2 = json.load(fh)

def get_out(key):
    return outputs.get("outputs", {}).get(key, "")

def replace_if_missing(key, value):
    current = data.get(key, "")
    if not current or "REPLACE_ME" in str(current):
        if value:
            data[key] = value

# Stage 02 outputs
mtdna_variants = get_out("StageAlignAndCallR1.split_vcf")
nuc_variants = get_out("StageAlignAndCallR1.split_nuc_vcf")

override_mtdna = "${mtdna_vcf_override}"
override_nuc = "${nuc_vcf_override}"
if override_mtdna:
    mtdna_variants = override_mtdna
if override_nuc:
    nuc_variants = override_nuc

if mtdna_variants:
    data["StageProduceSelfReferenceFiles.mtdna_variants"] = mtdna_variants
if nuc_variants:
    data["StageProduceSelfReferenceFiles.nuc_variants"] = nuc_variants

# Sample name
sample_name = "${sample_name_override}" or s2.get("StageAlignAndCallR1.sample_name", "")
if (not sample_name) or ("REPLACE_ME" in str(sample_name)):
    if mtdna_variants:
        base = mtdna_variants.rsplit("/", 1)[-1]
        if base.endswith(".split.vcf"):
            sample_name = base.replace(".split.vcf", "")
if sample_name:
    data["StageProduceSelfReferenceFiles.sample_name"] = sample_name

# Defaults from Stage 02 JSON
replace_if_missing("StageProduceSelfReferenceFiles.ref_fasta", s2.get("StageAlignAndCallR1.ref_fasta", ""))
replace_if_missing("StageProduceSelfReferenceFiles.ref_fasta_index", s2.get("StageAlignAndCallR1.ref_fasta_index", ""))
replace_if_missing("StageProduceSelfReferenceFiles.ref_dict", s2.get("StageAlignAndCallR1.ref_dict", ""))
replace_if_missing("StageProduceSelfReferenceFiles.mt_fasta", s2.get("StageAlignAndCallR1.mt_fasta", ""))
replace_if_missing("StageProduceSelfReferenceFiles.mt_fasta_index", s2.get("StageAlignAndCallR1.mt_fasta_index", ""))
replace_if_missing("StageProduceSelfReferenceFiles.mt_dict", s2.get("StageAlignAndCallR1.mt_dict", ""))
replace_if_missing("StageProduceSelfReferenceFiles.mt_interval_list", s2.get("StageAlignAndCallR1.mt_interval_list", ""))
replace_if_missing("StageProduceSelfReferenceFiles.nuc_interval_list", s2.get("StageAlignAndCallR1.nuc_interval_list", ""))
replace_if_missing("StageProduceSelfReferenceFiles.blacklisted_sites", s2.get("StageAlignAndCallR1.blacklisted_sites", ""))
replace_if_missing("StageProduceSelfReferenceFiles.blacklisted_sites_index", s2.get("StageAlignAndCallR1.blacklisted_sites_index", ""))

replace_if_missing("StageProduceSelfReferenceFiles.suffix", "${suffix_default}")
replace_if_missing("StageProduceSelfReferenceFiles.reference_name", "${reference_name_default}")
replace_if_missing("StageProduceSelfReferenceFiles.non_control_region_interval_list", "${non_control_interval_default}")
replace_if_missing("StageProduceSelfReferenceFiles.FaRenamingScript", "${fa_renaming_default}")
replace_if_missing("StageProduceSelfReferenceFiles.CheckVariantBoundsScript", "${check_bounds_default}")
replace_if_missing("StageProduceSelfReferenceFiles.CheckHomOverlapScript", "${check_overlap_default}")
replace_if_missing("StageProduceSelfReferenceFiles.genomes_cloud_docker", "${genomes_cloud_default}")
replace_if_missing("StageProduceSelfReferenceFiles.gotc_docker", "${gotc_docker_default}")
replace_if_missing("StageProduceSelfReferenceFiles.ucsc_docker", "${ucsc_docker_default}")
if "StageProduceSelfReferenceFiles.bcftools_docker" in data and "REPLACE_ME" in str(data.get("StageProduceSelfReferenceFiles.bcftools_docker")):
    if "${bcftools_docker_default}":
        data["StageProduceSelfReferenceFiles.bcftools_docker"] = "${bcftools_docker_default}"

# compute_numt_coverage default
if data.get("StageProduceSelfReferenceFiles.compute_numt_coverage") is None:
    data["StageProduceSelfReferenceFiles.compute_numt_coverage"] = False

# Final fallback: if any reference/interval values still have REPLACE_ME, use defaults
replace_if_missing("StageProduceSelfReferenceFiles.ref_fasta", "${ref_fasta_default}")
replace_if_missing("StageProduceSelfReferenceFiles.ref_fasta_index", "${ref_fasta_index_default}")
replace_if_missing("StageProduceSelfReferenceFiles.ref_dict", "${ref_dict_default}")
replace_if_missing("StageProduceSelfReferenceFiles.mt_fasta", "${mt_fasta_default}")
replace_if_missing("StageProduceSelfReferenceFiles.mt_fasta_index", "${mt_fasta_index_default}")
replace_if_missing("StageProduceSelfReferenceFiles.mt_dict", "${mt_dict_default}")
replace_if_missing("StageProduceSelfReferenceFiles.mt_interval_list", "${mt_interval_default}")
replace_if_missing("StageProduceSelfReferenceFiles.nuc_interval_list", "${nuc_interval_default}")

with open("${out_json}", "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")

print("Updated", "${out_json}")
print("  mtdna_variants:", mtdna_variants)
print("  nuc_variants:", nuc_variants)
print("  sample_name:", sample_name)
PY

rm -f "${outputs_tmp}"

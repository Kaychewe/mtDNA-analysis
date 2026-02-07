#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: populate_stage02_from_stage01.sh <stage01_workflow_id> [output_json]

Populates stage02_align_call_r1.json using Stage 01 outputs:
  - output_bam
  - output_bai
  - mean_coverage

Defaults for references and intervals are filled if values are missing or REPLACE_ME.
You can override defaults via environment variables:
  REF_FASTA_DEFAULT, REF_FASTA_INDEX_DEFAULT, REF_DICT_DEFAULT
  MT_FASTA_DEFAULT, MT_FASTA_INDEX_DEFAULT, MT_DICT_DEFAULT
  MT_INTERVAL_LIST_DEFAULT, NUC_INTERVAL_LIST_DEFAULT
  BLACKLIST_SITES_DEFAULT, BLACKLIST_SITES_INDEX_DEFAULT
  HAPLOCHECK_ZIP_DEFAULT
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

if [ -z "${1:-}" ]; then
  usage
  exit 1
fi

WF_ID="$1"
out_json="${2:-stage02_align_call_r1.json}"

if [ ! -f "$out_json" ]; then
  echo "Missing output JSON template: $out_json"
  exit 1
fi

ref_fasta_default="${REF_FASTA_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.fasta}"
ref_fasta_index_default="${REF_FASTA_INDEX_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.fasta.fai}"
ref_dict_default="${REF_DICT_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.dict}"
mt_fasta_default="${MT_FASTA_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/chrM/Homo_sapiens_assembly38.chrM.fasta}"
mt_fasta_index_default="${MT_FASTA_INDEX_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/chrM/Homo_sapiens_assembly38.chrM.fasta.fai}"
mt_dict_default="${MT_DICT_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/chrM/Homo_sapiens_assembly38.chrM.dict}"
mt_interval_list_default="${MT_INTERVAL_LIST_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/chrM/chrM.hg38.interval_list}"

if [ -n "${WORKSPACE_BUCKET:-}" ]; then
  nuc_interval_list_default="${NUC_INTERVAL_LIST_DEFAULT:-${WORKSPACE_BUCKET}/intervals/NUMTv3_all385.hg38.interval_list}"
  blacklist_sites_default="${BLACKLIST_SITES_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/chrM/blacklist_sites.hg38.chrM.bed}"
  blacklist_sites_index_default="${BLACKLIST_SITES_INDEX_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/chrM/blacklist_sites.hg38.chrM.bed.idx}"
  haplocheck_zip_default="${HAPLOCHECK_ZIP_DEFAULT:-${WORKSPACE_BUCKET}/haplocheck.zip}"
else
  nuc_interval_list_default="${NUC_INTERVAL_LIST_DEFAULT:-gs://fc-secure-76d68a64-00aa-40a7-b2c5-ca956db2719b/intervals/NUMTv3_all385.hg38.interval_list}"
  blacklist_sites_default="${BLACKLIST_SITES_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/chrM/blacklist_sites.hg38.chrM.bed}"
  blacklist_sites_index_default="${BLACKLIST_SITES_INDEX_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/chrM/blacklist_sites.hg38.chrM.bed.idx}"
  haplocheck_zip_default="${HAPLOCHECK_ZIP_DEFAULT:-gs://REPLACE_ME/haplocheck.zip}"
fi

stage01_json="${STAGE01_JSON:-stage01_subset_bam.json}"
if [ ! -f "$stage01_json" ]; then
  echo "Missing Stage 01 JSON for sample_name lookup: $stage01_json"
  exit 1
fi

fallback_sample_name=""
if [ -n "${LIST_DIR:-}" ] && [ -d "${LIST_DIR}" ]; then
  sample_list_file="$(ls -1 "${LIST_DIR}"/sample_list*.txt 2>/dev/null | sort | head -n 1 || true)"
  if [ -n "${sample_list_file}" ] && [ -f "${sample_list_file}" ]; then
    fallback_sample_name="$(head -n 1 "${sample_list_file}" | tr -d '\r' || true)"
  fi
fi

outputs_json="$(curl -s "http://localhost:8094/api/workflows/v1/${WF_ID}/outputs")"

python3 - <<PY
import json
import sys

outputs = json.loads("""${outputs_json}""")
data = {}
with open("${out_json}", "r", encoding="utf-8") as fh:
    data = json.load(fh)

def get_out(key):
    return outputs.get("outputs", {}).get(key, "")

output_bam = get_out("StageSubsetBamToChrMAndRevert.output_bam")
output_bai = get_out("StageSubsetBamToChrMAndRevert.output_bai")
mean_cov = get_out("StageSubsetBamToChrMAndRevert.mean_coverage")

with open("${stage01_json}", "r", encoding="utf-8") as fh:
    s1 = json.load(fh)
sample_name = s1.get("StageSubsetBamToChrMAndRevert.sample_name", "")
if not sample_name or "REPLACE_ME" in str(sample_name):
    sample_name = outputs.get("outputs", {}).get("StageSubsetBamToChrMAndRevert.sample_name", "") or sample_name
if not sample_name or "REPLACE_ME" in str(sample_name):
    sample_name = "${fallback_sample_name}" or sample_name

def replace_if_missing(key, value):
    current = data.get(key, "")
    if not current or "REPLACE_ME" in str(current):
        data[key] = value

data["StageAlignAndCallR1.input_bam"] = output_bam or data.get("StageAlignAndCallR1.input_bam", "")
data["StageAlignAndCallR1.input_bai"] = output_bai or data.get("StageAlignAndCallR1.input_bai", "")
if sample_name and "REPLACE_ME" not in str(sample_name):
    data["StageAlignAndCallR1.sample_name"] = sample_name
if isinstance(mean_cov, (int, float)):
    data["StageAlignAndCallR1.mt_mean_coverage"] = int(mean_cov)

replace_if_missing("StageAlignAndCallR1.ref_fasta", "${ref_fasta_default}")
replace_if_missing("StageAlignAndCallR1.ref_fasta_index", "${ref_fasta_index_default}")
replace_if_missing("StageAlignAndCallR1.ref_dict", "${ref_dict_default}")
replace_if_missing("StageAlignAndCallR1.mt_fasta", "${mt_fasta_default}")
replace_if_missing("StageAlignAndCallR1.mt_fasta_index", "${mt_fasta_index_default}")
replace_if_missing("StageAlignAndCallR1.mt_dict", "${mt_dict_default}")
replace_if_missing("StageAlignAndCallR1.mt_interval_list", "${mt_interval_list_default}")
replace_if_missing("StageAlignAndCallR1.nuc_interval_list", "${nuc_interval_list_default}")
replace_if_missing("StageAlignAndCallR1.blacklisted_sites", "${blacklist_sites_default}")
replace_if_missing("StageAlignAndCallR1.blacklisted_sites_index", "${blacklist_sites_index_default}")
replace_if_missing("StageAlignAndCallR1.haplocheck_zip", "${haplocheck_zip_default}")

with open("${out_json}", "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")

print("Updated", "${out_json}")
print("  input_bam:", output_bam)
print("  input_bai:", output_bai)
print("  mt_mean_coverage:", mean_cov)
print("  sample_name:", sample_name)
PY

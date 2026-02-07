#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: populate_stage01_from_lists.sh <cram_list> <crai_list> <sample_list> [output_json]

Populates stage01_subset_bam.json using the first line from each list.
The lists must be plain text files with one entry per line.

Examples:
  ./populate_stage01_from_lists.sh wgs_cram_list.txt wgs_crai_list.txt sample_names.txt
  ./populate_stage01_from_lists.sh wgs_cram_list.txt wgs_crai_list.txt sample_names.txt stage01_subset_bam.json
EOF
}

if [ "$#" -lt 3 ]; then
  usage
  exit 1
fi

cram_list="$1"
crai_list="$2"
sample_list="$3"
out_json="${4:-stage01_subset_bam.json}"

if [ ! -f "$cram_list" ] || [ ! -f "$crai_list" ] || [ ! -f "$sample_list" ]; then
  echo "One or more list files not found."
  exit 1
fi

cram=$(head -n 1 "$cram_list" | tr -d '\r')
crai=$(head -n 1 "$crai_list" | tr -d '\r')
sample=$(head -n 1 "$sample_list" | tr -d '\r')

ref_fasta_default="${REF_FASTA_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.fasta}"
ref_fasta_index_default="${REF_FASTA_INDEX_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.fasta.fai}"
ref_dict_default="${REF_DICT_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.dict}"
mt_interval_list_default="${MT_INTERVAL_LIST_DEFAULT:-gs://gcp-public-data--broad-references/hg38/v0/chrM/chrM.hg38.interval_list}"

if [ -n "${WORKSPACE_BUCKET:-}" ]; then
  nuc_interval_list_default="${NUC_INTERVAL_LIST_DEFAULT:-${WORKSPACE_BUCKET}/intervals/NUMTv3_all385.hg38.interval_list}"
else
  nuc_interval_list_default="${NUC_INTERVAL_LIST_DEFAULT:-gs://fc-secure-76d68a64-00aa-40a7-b2c5-ca956db2719b/intervals/NUMTv3_all385.hg38.interval_list}"
fi

if [ -z "$cram" ] || [ -z "$crai" ] || [ -z "$sample" ]; then
  echo "One or more list files are empty."
  exit 1
fi

python3 - <<PY
import json
import sys

path = "$out_json"
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

data["StageSubsetBamToChrMAndRevert.wgs_aligned_input_bam_or_cram"] = "$cram"
data["StageSubsetBamToChrMAndRevert.wgs_aligned_input_bam_or_cram_index"] = "$crai"
data["StageSubsetBamToChrMAndRevert.sample_name"] = "$sample"

def replace_if_missing(key, value):
    current = data.get(key, "")
    if not current or "REPLACE_ME" in str(current):
        data[key] = value

replace_if_missing("StageSubsetBamToChrMAndRevert.ref_fasta", "$ref_fasta_default")
replace_if_missing("StageSubsetBamToChrMAndRevert.ref_fasta_index", "$ref_fasta_index_default")
replace_if_missing("StageSubsetBamToChrMAndRevert.ref_dict", "$ref_dict_default")
replace_if_missing("StageSubsetBamToChrMAndRevert.mt_interval_list", "$mt_interval_list_default")
replace_if_missing("StageSubsetBamToChrMAndRevert.nuc_interval_list", "$nuc_interval_list_default")

with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY

echo "Updated $out_json with:"
echo "  CRAM:   $cram"
echo "  CRAI:   $crai"
echo "  SAMPLE: $sample"

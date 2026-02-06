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

with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY

echo "Updated $out_json with:"
echo "  CRAM:   $cram"
echo "  CRAI:   $crai"
echo "  SAMPLE: $sample"

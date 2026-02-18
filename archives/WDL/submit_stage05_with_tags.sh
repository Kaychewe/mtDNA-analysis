#!/bin/bash
set -euo pipefail
# Populate + submit Stage05 while enforcing specific docker tags and optional UCSC bundle.
#
# Usage:
#   submit_stage05_with_tags.sh --stage03 <wf_id> --stage04 <wf_id> [options]
#
# Options:
#   --stage02 <wf_id>         Optional
#   --stage01 <wf_id>         Optional
#   --sample-name <id>        Override sample name
#   --genomes-docker <image>  Force genomes_cloud_docker (default: kchewe/mtdna-stage05:0.1.0)
#   --ucsc-docker <image>     Force ucsc_docker (default: kchewe/mtdna-stage04:0.1.3)
#   --ucsc-bundle <gs://...>  UCSC tools bundle tar.gz
#   --output-json <path>      Output JSON path (default: stage05_liftover.json)

ROOT_DIR="${PROJECT_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
STAGE03=""
STAGE04=""
STAGE02=""
STAGE01=""
SAMPLE_NAME=""
OUTPUT_JSON="${ROOT_DIR}/stage05_liftover.json"
GENOMES_DOCKER="kchewe/mtdna-stage05:0.1.0"
UCSC_DOCKER="kchewe/mtdna-stage04:0.1.3"
UCSC_BUNDLE="gs://fc-secure-76d68a64-00aa-40a7-b2c5-ca956db2719b/tools/ucsc/ucsc-tools-linux-x86_64.tar.gz"

while [ $# -gt 0 ]; do
  case "$1" in
    --stage03)
      STAGE03="${2:-}"
      shift 2
      ;;
    --stage04)
      STAGE04="${2:-}"
      shift 2
      ;;
    --stage02)
      STAGE02="${2:-}"
      shift 2
      ;;
    --stage01)
      STAGE01="${2:-}"
      shift 2
      ;;
    --sample-name)
      SAMPLE_NAME="${2:-}"
      shift 2
      ;;
    --genomes-docker)
      GENOMES_DOCKER="${2:-}"
      shift 2
      ;;
    --ucsc-docker)
      UCSC_DOCKER="${2:-}"
      shift 2
      ;;
    --ucsc-bundle)
      UCSC_BUNDLE="${2:-}"
      shift 2
      ;;
    --output-json)
      OUTPUT_JSON="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: submit_stage05_with_tags.sh --stage03 <wf_id> --stage04 <wf_id> [--stage02 <wf_id>] [--stage01 <wf_id>] [--sample-name <id>] [--genomes-docker <image>] [--ucsc-docker <image>] [--ucsc-bundle <gs://...>] [--output-json <path>]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [ -z "$STAGE03" ] || [ -z "$STAGE04" ]; then
  echo "ERROR: --stage03 and --stage04 are required."
  exit 1
fi

populate_args=(--stage03 "$STAGE03" --stage04 "$STAGE04")
if [ -n "$STAGE02" ]; then
  populate_args+=(--stage02 "$STAGE02")
fi
if [ -n "$STAGE01" ]; then
  populate_args+=(--stage01 "$STAGE01")
fi
if [ -n "$SAMPLE_NAME" ]; then
  populate_args+=(--sample-name "$SAMPLE_NAME")
fi

bash "${ROOT_DIR}/populate_stage05_from_stage04.sh" "${populate_args[@]}" "$OUTPUT_JSON"

python3 - <<PY
import json
p="${OUTPUT_JSON}"
data=json.load(open(p))
data["StageLiftover.genomes_cloud_docker"] = "${GENOMES_DOCKER}"
data["StageLiftover.ucsc_docker"] = "${UCSC_DOCKER}"
if "${UCSC_BUNDLE}":
    data["StageLiftover.ucsc_tools_bundle"] = "${UCSC_BUNDLE}"
json.dump(data, open(p,"w"), indent=2, sort_keys=True)
print(f"Updated {p} genomes_cloud_docker -> ${GENOMES_DOCKER}")
print(f"Updated {p} ucsc_docker -> ${UCSC_DOCKER}")
if "${UCSC_BUNDLE}":
    print(f"Updated {p} ucsc_tools_bundle -> ${UCSC_BUNDLE}")
PY

bash "${ROOT_DIR}/submit_stage05.sh"

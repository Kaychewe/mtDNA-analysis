#!/bin/bash
set -euo pipefail
# Populate + submit Stage04 while enforcing specific docker tags.
#
# Usage:
#   submit_stage04_with_tags.sh --stage01 <wf_id> --stage02 <wf_id> --stage03 <wf_id> [options]
#
# Options:
#   --sample-name <id>     Override sample name
#   --gatk-docker <image>  Force GATK image tag (default: us.gcr.io/broad-gatk/gatk:4.2.6.0)
#   --output-json <path>   Output JSON path (default: stage04_align_call_r2.json)

ROOT_DIR="${PROJECT_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
STAGE01=""
STAGE02=""
STAGE03=""
SAMPLE_NAME=""
OUTPUT_JSON="${ROOT_DIR}/stage04_align_call_r2.json"
GATK_DOCKER="kchewe/mtdna-stage04:0.1.2"
GOTC_DOCKER="kchewe/mtdna-stage04:0.1.2"

while [ $# -gt 0 ]; do
  case "$1" in
    --stage01)
      STAGE01="${2:-}"
      shift 2
      ;;
    --stage02)
      STAGE02="${2:-}"
      shift 2
      ;;
    --stage03)
      STAGE03="${2:-}"
      shift 2
      ;;
    --sample-name)
      SAMPLE_NAME="${2:-}"
      shift 2
      ;;
    --gatk-docker)
      GATK_DOCKER="${2:-}"
      shift 2
      ;;
    --gotc-docker)
      GOTC_DOCKER="${2:-}"
      shift 2
      ;;
    --output-json)
      OUTPUT_JSON="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: submit_stage04_with_tags.sh --stage01 <wf_id> --stage02 <wf_id> --stage03 <wf_id> [--sample-name <id>] [--gatk-docker <image>] [--gotc-docker <image>] [--output-json <path>]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [ -z "$STAGE01" ] || [ -z "$STAGE02" ] || [ -z "$STAGE03" ]; then
  echo "ERROR: --stage01, --stage02, and --stage03 are required."
  exit 1
fi

populate_args=(--stage01 "$STAGE01" --stage02 "$STAGE02" --stage03 "$STAGE03")
if [ -n "$SAMPLE_NAME" ]; then
  populate_args+=(--sample-name "$SAMPLE_NAME")
fi

bash "${ROOT_DIR}/populate_stage04_from_stage03.sh" "${populate_args[@]}" "$OUTPUT_JSON"

python3 - <<PY
import json
p="${OUTPUT_JSON}"
data=json.load(open(p))
data["StageAlignAndCallR2.gatk_docker_override"] = "${GATK_DOCKER}"
data["StageAlignAndCallR2.gotc_docker_override"] = "${GOTC_DOCKER}"
json.dump(data, open(p,"w"), indent=2, sort_keys=True)
print(f"Updated {p} gatk_docker_override -> ${GATK_DOCKER}")
print(f"Updated {p} gotc_docker_override -> ${GOTC_DOCKER}")
PY

bash "${ROOT_DIR}/submit_stage04.sh"

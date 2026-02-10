#!/bin/bash


DEBUG=0
REUSE_STAGE01=""
REUSE_STAGE02=""
REUSE_STAGE03=""
REUSE_STAGE04=""
REUSE_STAGE05=""
REUSE_STAGE06=""
SAMPLE_NAME=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --debug)
      DEBUG=1
      shift
      ;;
    --reuse-stage01)
      REUSE_STAGE01="${2:-}"
      shift 2
      ;;
    --reuse-stage02)
      REUSE_STAGE02="${2:-}"
      shift 2
      ;;
    --reuse-stage03)
      REUSE_STAGE03="${2:-}"
      shift 2
      ;;
    --reuse-stage04)
      REUSE_STAGE04="${2:-}"
      shift 2
      ;;
    --reuse-stage05)
      REUSE_STAGE05="${2:-}"
      shift 2
      ;;
    --reuse-stage06)
      REUSE_STAGE06="${2:-}"
      shift 2
      ;;
    --sample-name)
      SAMPLE_NAME="${2:-}"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $(basename "$0") [--debug] [--sample-name <id>] [--reuse-stage01 <workflow_id>] [--reuse-stage02 <workflow_id>] [--reuse-stage03 <workflow_id>] [--reuse-stage04 <workflow_id>] [--reuse-stage05 <workflow_id>] [--reuse-stage06 <workflow_id>]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done
if [ "$DEBUG" = "1" ]; then
  set -x
fi
export DEBUG

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

load_env
log "Cromwell status URL: ${CROMWELL_STATUS_URL}"
ensure_dirs
make_run_dir
check_cromwell
ensure_wdl_deps
init_samples_status

list_dir="${LIST_DIR}"
if [ ! -d "$list_dir" ]; then
  log "List directory not found: ${list_dir}. Falling back to PROJECT_ROOT."
  list_dir="${PROJECT_ROOT}"
fi

sample_list="$(pick_first_list sample_list*.txt "$list_dir")"
cram_list="$(pick_first_list cram_file_list*.txt "$list_dir")"
crai_list="$(pick_first_list crai_file_list*.txt "$list_dir")"
if [ -z "$sample_list" ] || [ -z "$cram_list" ] || [ -z "$crai_list" ]; then
  log "Missing list files in ${list_dir}. Expected sample_list*.txt, cram_file_list*.txt, crai_file_list*.txt"
  exit 1
fi

mapfile -t samples < "$sample_list"
mapfile -t crams < "$cram_list"
mapfile -t crais < "$crai_list"

if [ "${#samples[@]}" -ne "${#crams[@]}" ] || [ "${#samples[@]}" -ne "${#crais[@]}" ]; then
  log "List files length mismatch (samples=${#samples[@]}, crams=${#crams[@]}, crais=${#crais[@]})."
  exit 1
fi

for i in "${!samples[@]}"; do
  sample_name="$(echo "${samples[$i]}" | tr -d '\r')"
  cram="$(echo "${crams[$i]}" | tr -d '\r')"
  crai="$(echo "${crais[$i]}" | tr -d '\r')"

  if [ -n "${SAMPLE_NAME}" ] && [ "${sample_name}" != "${SAMPLE_NAME}" ]; then
    continue
  fi

  if sample_stage_succeeded "${sample_name}" "stage06"; then
    log "Sample ${sample_name} already has Stage06 success; skipping."
    continue
  fi

  log "=== Processing sample ${sample_name} (index ${i}) ==="

  # Stage01
  if [ -n "$REUSE_STAGE01" ] && [ -z "${SAMPLE_NAME}" ]; then
    log "WARNING: --reuse-stage01 provided but multiple samples are present; ignoring reuse."
    REUSE_STAGE01=""
  fi

  if [ -n "$REUSE_STAGE01" ]; then
    wf_id_stage01="$REUSE_STAGE01"
    log "Reusing Stage 01 workflow ID: ${wf_id_stage01}"
  else
    python3 - <<PY
import json
path = "${PROJECT_ROOT}/stage01_subset_bam.json"
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
data["StageSubsetBamToChrMAndRevert.wgs_aligned_input_bam_or_cram"] = "${cram}"
data["StageSubsetBamToChrMAndRevert.wgs_aligned_input_bam_or_cram_index"] = "${crai}"
data["StageSubsetBamToChrMAndRevert.sample_name"] = "${sample_name}"
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\\n")
PY

    log "Submitting Stage 01 workflow."
    wf_id_stage01="$(submit_stage01)"
    append_sample_status "${sample_name}" "stage01" "${wf_id_stage01}" "Submitted"
    log "Stage 01 submitted: ${wf_id_stage01}"
    log "Stage 01 status URL: http://localhost:8094/api/workflows/v1/${wf_id_stage01}/status"
    log "Stage 01 metadata URL: http://localhost:8094/api/workflows/v1/${wf_id_stage01}/metadata"
    watch_status "$wf_id_stage01"
  fi

  stage01_status="$(get_wf_status "${wf_id_stage01}")"
  append_sample_status "${sample_name}" "stage01" "${wf_id_stage01}" "${stage01_status}"
  if [ "$stage01_status" != "Succeeded" ]; then
    log "Stage 01 did not succeed (status=${stage01_status}). Skipping sample ${sample_name}."
    continue
  fi

  # Stage02
  if [ -n "$REUSE_STAGE02" ] && [ -z "${SAMPLE_NAME}" ]; then
    log "WARNING: --reuse-stage02 provided but multiple samples are present; ignoring reuse."
    REUSE_STAGE02=""
  fi
  if [ -n "$REUSE_STAGE02" ]; then
    wf_id_stage02="$REUSE_STAGE02"
    log "Reusing Stage 02 workflow ID: ${wf_id_stage02}"
    watch_status "$wf_id_stage02"
  else
    log "Populating Stage 02 inputs from Stage 01 outputs."
    bash "${PROJECT_ROOT}/populate_stage02_from_stage01.sh" "$wf_id_stage01" "${PROJECT_ROOT}/stage02_align_call_r1.json"
    log "Running Stage 02 diagnostics."
    bash "${PROJECT_ROOT}/main_analysis/scripts/diagnose_stage02.sh"
    log "Submitting Stage 02 workflow."
    wf_id_stage02="$(bash "${PROJECT_ROOT}/submit_stage02.sh")"
    wf_id_stage02="$(echo "$wf_id_stage02" | python3 -c 'import json,sys
try:
    data = json.load(sys.stdin)
    print(data.get("id",""))
except Exception:
    print("")
')"
    if [ -z "$wf_id_stage02" ]; then
      log "Failed to parse Stage 02 workflow ID."
      exit 1
    fi
    append_sample_status "${sample_name}" "stage02" "${wf_id_stage02}" "Submitted"
    log "Stage 02 submitted: ${wf_id_stage02}"
    log "Stage 02 status URL: http://localhost:8094/api/workflows/v1/${wf_id_stage02}/status"
    log "Stage 02 metadata URL: http://localhost:8094/api/workflows/v1/${wf_id_stage02}/metadata"
    watch_status "$wf_id_stage02"
  fi

  stage02_status="$(get_wf_status "${wf_id_stage02}")"
  append_sample_status "${sample_name}" "stage02" "${wf_id_stage02}" "${stage02_status}"
  if [ "$stage02_status" != "Succeeded" ]; then
    log "Stage 02 did not succeed (status=${stage02_status}). Skipping sample ${sample_name}."
    continue
  fi

  # Stage03
  if [ -n "$REUSE_STAGE03" ] && [ -z "${SAMPLE_NAME}" ]; then
    log "WARNING: --reuse-stage03 provided but multiple samples are present; ignoring reuse."
    REUSE_STAGE03=""
  fi
  if [ -n "$REUSE_STAGE03" ]; then
    wf_id_stage03="$REUSE_STAGE03"
    log "Reusing Stage 03 workflow ID: ${wf_id_stage03}"
    watch_status "$wf_id_stage03"
  else
    log "Populating Stage 03 inputs from Stage 02 outputs."
    bash "${PROJECT_ROOT}/populate_stage03_from_stage02.sh" "$wf_id_stage02" "${PROJECT_ROOT}/stage03_produce_self_reference.json"
    log "Running Stage 03 diagnostics."
    bash "${PROJECT_ROOT}/main_analysis/scripts/diagnose_stage03.sh"
    log "Submitting Stage 03 workflow."
    wf_id_stage03="$(bash "${PROJECT_ROOT}/submit_stage03.sh")"
    wf_id_stage03="$(echo "$wf_id_stage03" | python3 -c 'import json,sys
try:
    data = json.load(sys.stdin)
    print(data.get("id",""))
except Exception:
    print("")
')"
    if [ -z "$wf_id_stage03" ]; then
      log "Failed to parse Stage 03 workflow ID."
      exit 1
    fi
    append_sample_status "${sample_name}" "stage03" "${wf_id_stage03}" "Submitted"
    log "Stage 03 submitted: ${wf_id_stage03}"
    log "Stage 03 status URL: http://localhost:8094/api/workflows/v1/${wf_id_stage03}/status"
    log "Stage 03 metadata URL: http://localhost:8094/api/workflows/v1/${wf_id_stage03}/metadata"
    watch_status "$wf_id_stage03"
  fi

  stage03_status="$(get_wf_status "${wf_id_stage03}")"
  append_sample_status "${sample_name}" "stage03" "${wf_id_stage03}" "${stage03_status}"
  if [ "$stage03_status" != "Succeeded" ]; then
    log "Stage 03 did not succeed (status=${stage03_status}). Skipping sample ${sample_name}."
    continue
  fi

  # Stage04
  if [ -n "$REUSE_STAGE04" ] && [ -z "${SAMPLE_NAME}" ]; then
    log "WARNING: --reuse-stage04 provided but multiple samples are present; ignoring reuse."
    REUSE_STAGE04=""
  fi
  if [ -n "$REUSE_STAGE04" ]; then
    wf_id_stage04="$REUSE_STAGE04"
    log "Reusing Stage 04 workflow ID: ${wf_id_stage04}"
    watch_status "$wf_id_stage04"
  else
    log "Populating Stage 04 inputs from Stage 01/02/03 outputs."
    bash "${PROJECT_ROOT}/populate_stage04_from_stage03.sh" --stage01 "$wf_id_stage01" --stage02 "$wf_id_stage02" --stage03 "$wf_id_stage03" "${PROJECT_ROOT}/stage04_align_call_r2.json"
    log "Submitting Stage 04 workflow."
    wf_id_stage04="$(bash "${PROJECT_ROOT}/submit_stage04.sh")"
    wf_id_stage04="$(echo "$wf_id_stage04" | python3 -c 'import json,sys
try:
    data = json.load(sys.stdin)
    print(data.get("id",""))
except Exception:
    print("")
')"
    if [ -z "$wf_id_stage04" ]; then
      log "Failed to parse Stage 04 workflow ID."
      exit 1
    fi
    append_sample_status "${sample_name}" "stage04" "${wf_id_stage04}" "Submitted"
    log "Stage 04 submitted: ${wf_id_stage04}"
    log "Stage 04 status URL: http://localhost:8094/api/workflows/v1/${wf_id_stage04}/status"
    log "Stage 04 metadata URL: http://localhost:8094/api/workflows/v1/${wf_id_stage04}/metadata"
    watch_status "$wf_id_stage04"
  fi

  stage04_status="$(get_wf_status "${wf_id_stage04}")"
  append_sample_status "${sample_name}" "stage04" "${wf_id_stage04}" "${stage04_status}"
  if [ "$stage04_status" != "Succeeded" ]; then
    log "Stage 04 did not succeed (status=${stage04_status}). Skipping sample ${sample_name}."
    continue
  fi

  # Stage05
  if [ -n "$REUSE_STAGE05" ] && [ -z "${SAMPLE_NAME}" ]; then
    log "WARNING: --reuse-stage05 provided but multiple samples are present; ignoring reuse."
    REUSE_STAGE05=""
  fi
  if [ -n "$REUSE_STAGE05" ]; then
    wf_id_stage05="$REUSE_STAGE05"
    log "Reusing Stage 05 workflow ID: ${wf_id_stage05}"
    watch_status "$wf_id_stage05"
  else
    log "Populating Stage 05 inputs from Stage 03/04 outputs."
    bash "${PROJECT_ROOT}/populate_stage05_from_stage04.sh" --stage03 "$wf_id_stage03" --stage04 "$wf_id_stage04" --stage02 "$wf_id_stage02" --stage01 "$wf_id_stage01" "${PROJECT_ROOT}/stage05_liftover.json"
    log "Submitting Stage 05 workflow."
    wf_id_stage05="$(bash "${PROJECT_ROOT}/submit_stage05.sh")"
    wf_id_stage05="$(echo "$wf_id_stage05" | python3 -c 'import json,sys
try:
    data = json.load(sys.stdin)
    print(data.get("id",""))
except Exception:
    print("")
')"
    if [ -z "$wf_id_stage05" ]; then
      log "Failed to parse Stage 05 workflow ID."
      exit 1
    fi
    append_sample_status "${sample_name}" "stage05" "${wf_id_stage05}" "Submitted"
    log "Stage 05 submitted: ${wf_id_stage05}"
    log "Stage 05 status URL: http://localhost:8094/api/workflows/v1/${wf_id_stage05}/status"
    log "Stage 05 metadata URL: http://localhost:8094/api/workflows/v1/${wf_id_stage05}/metadata"
    watch_status "$wf_id_stage05"
  fi

  stage05_status="$(get_wf_status "${wf_id_stage05}")"
  append_sample_status "${sample_name}" "stage05" "${wf_id_stage05}" "${stage05_status}"
  if [ "$stage05_status" != "Succeeded" ]; then
    log "Stage 05 did not succeed (status=${stage05_status}). Skipping sample ${sample_name}."
    continue
  fi

  # Stage06
  if [ -n "$REUSE_STAGE06" ] && [ -z "${SAMPLE_NAME}" ]; then
    log "WARNING: --reuse-stage06 provided but multiple samples are present; ignoring reuse."
    REUSE_STAGE06=""
  fi
  if [ -n "$REUSE_STAGE06" ]; then
    wf_id_stage06="$REUSE_STAGE06"
    log "Reusing Stage 06 workflow ID: ${wf_id_stage06}"
    watch_status "$wf_id_stage06"
  else
    log "Populating Stage 06 inputs from Stage 05 outputs."
    bash "${PROJECT_ROOT}/populate_stage06_from_stage05.sh" "$wf_id_stage05" "${PROJECT_ROOT}/stage06_merge.json"
    log "Submitting Stage 06 workflow."
    wf_id_stage06="$(bash "${PROJECT_ROOT}/submit_stage06.sh")"
    wf_id_stage06="$(echo "$wf_id_stage06" | python3 -c 'import json,sys
try:
    data = json.load(sys.stdin)
    print(data.get("id",""))
except Exception:
    print("")
')"
    if [ -z "$wf_id_stage06" ]; then
      log "Failed to parse Stage 06 workflow ID."
      exit 1
    fi
    append_sample_status "${sample_name}" "stage06" "${wf_id_stage06}" "Submitted"
    log "Stage 06 submitted: ${wf_id_stage06}"
    log "Stage 06 status URL: http://localhost:8094/api/workflows/v1/${wf_id_stage06}/status"
    log "Stage 06 metadata URL: http://localhost:8094/api/workflows/v1/${wf_id_stage06}/metadata"
    watch_status "$wf_id_stage06"
  fi

  stage06_status="$(get_wf_status "${wf_id_stage06}")"
  append_sample_status "${sample_name}" "stage06" "${wf_id_stage06}" "${stage06_status}"
  if [ "$stage06_status" != "Succeeded" ]; then
    log "Stage 06 did not succeed (status=${stage06_status}) for sample ${sample_name}."
    continue
  fi

  log "Sample ${sample_name} completed through Stage06."
done

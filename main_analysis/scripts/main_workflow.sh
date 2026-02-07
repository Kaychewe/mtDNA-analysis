#!/bin/bash


DEBUG=0
for arg in "$@"; do
  case "$arg" in
    --debug)
      DEBUG=1
      ;;
    --help|-h)
      echo "Usage: $(basename "$0") [--debug]"
      exit 0
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

list_dir="${LIST_DIR}"
if [ ! -d "$list_dir" ]; then
  log "List directory not found: ${list_dir}. Falling back to PROJECT_ROOT."
  list_dir="${PROJECT_ROOT}"
fi

log "Populating Stage 01 inputs from list files in ${list_dir}."
populate_stage01_json "$list_dir"

log "Submitting Stage 01 workflow."
wf_id="$(submit_stage01)"
log "Stage 01 submitted: ${wf_id}"
log "Workflow status URL: http://localhost:8094/api/workflows/v1/${wf_id}/status"
log "Workflow metadata URL: http://localhost:8094/api/workflows/v1/${wf_id}/metadata"

watch_status "$wf_id"
log "Stage 01 complete."

stage01_status="$(curl -s "http://localhost:8094/api/workflows/v1/${wf_id}/status" | python3 -c 'import json,sys
try:
    data = json.load(sys.stdin)
    print(data.get("status",""))
except Exception:
    print("")
')"
if [ "$stage01_status" != "Succeeded" ]; then
  log "Stage 01 did not succeed (status=${stage01_status}). Skipping Stage 02."
  exit 1
fi

log "Populating Stage 02 inputs from Stage 01 outputs."
bash "${PROJECT_ROOT}/populate_stage02_from_stage01.sh" "$wf_id" "${PROJECT_ROOT}/stage02_align_call_r1.json"

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
log "Stage 02 submitted: ${wf_id_stage02}"
log "Stage 02 status URL: http://localhost:8094/api/workflows/v1/${wf_id_stage02}/status"
log "Stage 02 metadata URL: http://localhost:8094/api/workflows/v1/${wf_id_stage02}/metadata"

watch_status "$wf_id_stage02"
log "Stage 02 complete."

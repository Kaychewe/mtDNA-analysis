#!/bin/bash


DEBUG=0
REUSE_STAGE01=""
REUSE_STAGE02=""
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
    --help|-h)
      echo "Usage: $(basename "$0") [--debug] [--reuse-stage01 <workflow_id>] [--reuse-stage02 <workflow_id>]"
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

if [ -n "$REUSE_STAGE02" ]; then
  wf_id_stage02="$REUSE_STAGE02"
  log "Reusing Stage 02 workflow ID: ${wf_id_stage02}"
  log "Stage 02 status URL: http://localhost:8094/api/workflows/v1/${wf_id_stage02}/status"
  log "Stage 02 metadata URL: http://localhost:8094/api/workflows/v1/${wf_id_stage02}/metadata"
  watch_status "$wf_id_stage02"
  log "Stage 02 complete."
else
  if [ -n "$REUSE_STAGE01" ]; then
    wf_id="$REUSE_STAGE01"
    log "Reusing Stage 01 workflow ID: ${wf_id}"
  else
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
  fi

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
  log "Stage 02 submitted: ${wf_id_stage02}"
  log "Stage 02 status URL: http://localhost:8094/api/workflows/v1/${wf_id_stage02}/status"
  log "Stage 02 metadata URL: http://localhost:8094/api/workflows/v1/${wf_id_stage02}/metadata"

  watch_status "$wf_id_stage02"
  log "Stage 02 complete."
fi

stage02_status="$(curl -s "http://localhost:8094/api/workflows/v1/${wf_id_stage02}/status" | python3 -c 'import json,sys
try:
    data = json.load(sys.stdin)
    print(data.get("status",""))
except Exception:
    print("")
')"
if [ "$stage02_status" != "Succeeded" ]; then
  log "Stage 02 did not succeed (status=${stage02_status}). Skipping Stage 03."
  exit 1
fi

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
log "Stage 03 submitted: ${wf_id_stage03}"
log "Stage 03 status URL: http://localhost:8094/api/workflows/v1/${wf_id_stage03}/status"
log "Stage 03 metadata URL: http://localhost:8094/api/workflows/v1/${wf_id_stage03}/metadata"

watch_status "$wf_id_stage03"
log "Stage 03 complete."

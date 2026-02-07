#!/bin/bash

set -x

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

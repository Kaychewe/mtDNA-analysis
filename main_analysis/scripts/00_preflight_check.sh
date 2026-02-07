#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

load_env
enable_lists_dir="${LIST_DIR}"
ensure_dirs
make_run_dir

log "Preflight: verifying Cromwell and dependencies."
check_cromwell
ensure_wdl_deps

if [ "${AUTO_UPLOAD_STAGE02_INPUTS:-0}" = "1" ]; then
  log "Preflight: uploading Stage 02 inputs."
  bash "${SCRIPT_DIR}/upload_stage02_inputs.sh"
else
  log "Preflight: Stage 02 upload disabled (AUTO_UPLOAD_STAGE02_INPUTS=0)."
fi

if [ ! -d "$enable_lists_dir" ]; then
  log "List directory not found: ${enable_lists_dir}. Will fall back to PROJECT_ROOT."
  enable_lists_dir="${PROJECT_ROOT}"
fi

log "Preflight complete. List directory: ${enable_lists_dir}"

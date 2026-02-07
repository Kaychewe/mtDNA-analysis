#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

load_env

: "${WORKSPACE_BUCKET:?Missing WORKSPACE_BUCKET}"

DEST_CODE="${WORKSPACE_BUCKET}/code"
FA_RENAMING_DEST="${DEST_CODE}/compatibilify_fa_intervals_consensus.R"
CHECK_BOUNDS_DEST="${DEST_CODE}/check_variant_bounds.R"
CHECK_OVERLAP_DEST="${DEST_CODE}/check_overlapping_homoplasmies.R"

log "Uploading Stage 03 inputs to ${WORKSPACE_BUCKET}."

upload_file() {
  local src="$1"
  local dest="$2"
  local label="$3"

  if gsutil -q stat "${dest}"; then
    log "${label} already exists: ${dest}"
    return 0
  fi
  if [ -z "${src}" ] || [ ! -f "${src}" ]; then
    die "${label} local file not found: ${src}"
  fi
  gsutil cp "${src}" "${dest}"
  log "Uploaded ${label}"
}

upload_file "${FA_RENAMING_SCRIPT_LOCAL:-}" "${FA_RENAMING_DEST}" "FaRenamingScript"
upload_file "${CHECK_VARIANT_BOUNDS_LOCAL:-}" "${CHECK_BOUNDS_DEST}" "CheckVariantBoundsScript"
upload_file "${CHECK_HOM_OVERLAP_LOCAL:-}" "${CHECK_OVERLAP_DEST}" "CheckHomOverlapScript"

log "Stage 03 input upload complete."

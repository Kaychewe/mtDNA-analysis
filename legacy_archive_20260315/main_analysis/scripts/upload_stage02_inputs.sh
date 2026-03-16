#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

load_env

: "${WORKSPACE_BUCKET:?Missing WORKSPACE_BUCKET}"

DEST_INTERVALS="${WORKSPACE_BUCKET}/intervals"
DEST_BED="${DEST_INTERVALS}/blacklist_sites.hg38.chrM.bed"
DEST_BED_IDX="${DEST_INTERVALS}/blacklist_sites.hg38.chrM.bed.idx"
DEST_HAPLOCHECK="${WORKSPACE_BUCKET}/haplocheck.zip"

log "Uploading Stage 02 inputs to ${WORKSPACE_BUCKET}."

# haplocheck.zip
if gsutil -q stat "${DEST_HAPLOCHECK}"; then
  log "haplocheck.zip already exists: ${DEST_HAPLOCHECK}"
else
  if [ -z "${HAPLOCHECK_ZIP_LOCAL:-}" ] || [ ! -f "${HAPLOCHECK_ZIP_LOCAL}" ]; then
    die "HAPLOCHECK_ZIP_LOCAL not found: ${HAPLOCHECK_ZIP_LOCAL}"
  fi
  gsutil cp "${HAPLOCHECK_ZIP_LOCAL}" "${DEST_HAPLOCHECK}"
  log "Uploaded haplocheck.zip"
fi

# blacklist bed
if gsutil -q stat "${DEST_BED}"; then
  log "blacklist bed already exists: ${DEST_BED}"
else
  if [ -z "${BLACKLIST_BED_LOCAL:-}" ] || [ ! -f "${BLACKLIST_BED_LOCAL}" ]; then
    die "BLACKLIST_BED_LOCAL not found. Set BLACKLIST_BED_LOCAL in run.env."
  fi
  gsutil cp "${BLACKLIST_BED_LOCAL}" "${DEST_BED}"
  log "Uploaded blacklist bed"
fi

# blacklist bed idx
if gsutil -q stat "${DEST_BED_IDX}"; then
  log "blacklist bed idx already exists: ${DEST_BED_IDX}"
else
  if [ -z "${BLACKLIST_BED_IDX_LOCAL:-}" ] || [ ! -f "${BLACKLIST_BED_IDX_LOCAL}" ]; then
    die "BLACKLIST_BED_IDX_LOCAL not found. Set BLACKLIST_BED_IDX_LOCAL in run.env."
  fi
  gsutil cp "${BLACKLIST_BED_IDX_LOCAL}" "${DEST_BED_IDX}"
  log "Uploaded blacklist bed idx"
fi

log "Stage 02 input upload complete."

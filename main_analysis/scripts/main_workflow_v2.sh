#!/bin/bash
# Author: Kasonde Chewe 
# Pipeline: 
# Stage01-only, batch-aware workflow runner (manifest-driven).

DEBUG=0
SKIP_ALREADY_PROCESSED="${SKIP_ALREADY_PROCESSED:-1}"
SAMPLE_NAME=""
BATCH_SIZE="${BATCH_SIZE:-}"
BATCH_INDEX="${BATCH_INDEX:-}"

# ---------
# Arguments
# ---------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --debug)
      DEBUG=1
      shift
      ;;
    --sample-name)
      SAMPLE_NAME="${2:-}"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $(basename "$0") [--debug] [--sample-name <id>]"
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

# ------------
# Dependencies
# ------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

# ------------------------
# Manifest bootstrap helper
# ------------------------
generate_manifest_if_missing() {
  local manifest_path="$1"
  if [ -f "${manifest_path}" ]; then
    return 0
  fi
  if ! command -v gsutil >/dev/null 2>&1; then
    log "Manifest missing and gsutil not found: ${manifest_path}"
    return 1
  fi
  local source_uri=""
  if [ -n "${CDR_STORAGE_PATH:-}" ]; then
    source_uri="${CDR_STORAGE_PATH}/wgs/cram/manifest.csv"
  else
    log "Manifest missing and CDR_STORAGE_PATH not set: ${manifest_path}"
    return 1
  fi
  if [ -n "${GOOGLE_PROJECT:-}" ]; then
    log "Downloading manifest with requester pays: ${source_uri}"
    gsutil -u "${GOOGLE_PROJECT}" cp "${source_uri}" "${manifest_path}"
  else
    log "Downloading manifest: ${source_uri}"
    gsutil cp "${source_uri}" "${manifest_path}"
  fi
  [ -f "${manifest_path}" ]
}

# -------------
# Preflight init
# -------------
load_env
log "Cromwell status URL: ${CROMWELL_STATUS_URL}"
ensure_dirs
make_run_dir
check_cromwell
check_wdl_deps
init_samples_status
SKIP_ALREADY_PROCESSED="${SKIP_ALREADY_PROCESSED:-1}"
BATCH_SIZE="${BATCH_SIZE:-}"
BATCH_INDEX="${BATCH_INDEX:-}"

# --------------------
# Manifest + batching
# --------------------
MANIFEST_CSV="${PROJECT_ROOT}/manifest.csv"
if [ ! -f "${MANIFEST_CSV}" ]; then
  log "Manifest not found: ${MANIFEST_CSV}. Attempting to generate."
  if ! generate_manifest_if_missing "${MANIFEST_CSV}"; then
    log "Manifest still missing after generation attempt: ${MANIFEST_CSV}"
    exit 1
  fi
fi

if { [ -n "${BATCH_SIZE}" ] && [ -z "${BATCH_INDEX}" ]; } || { [ -z "${BATCH_SIZE}" ] && [ -n "${BATCH_INDEX}" ]; }; then
  log "Both BATCH_SIZE and BATCH_INDEX must be set together (env vars in run.env)."
  exit 1
fi

if [ -n "${BATCH_SIZE}" ] && [ -n "${BATCH_INDEX}" ]; then
  if ! [[ "${BATCH_SIZE}" =~ ^[0-9]+$ ]] || ! [[ "${BATCH_INDEX}" =~ ^[0-9]+$ ]]; then
    log "BATCH_SIZE and BATCH_INDEX must be positive integers."
    exit 1
  fi
fi

start_line=2
end_line=999999999
if [ -n "${BATCH_SIZE}" ] && [ -n "${BATCH_INDEX}" ]; then
  start_line=$(( (BATCH_INDEX - 1) * BATCH_SIZE + 2 ))
  end_line=$(( start_line + BATCH_SIZE - 1 ))
  log "Processing batch ${BATCH_INDEX} (size ${BATCH_SIZE}), lines ${start_line}-${end_line} of ${MANIFEST_CSV}."
fi

# ----------------
# Main sample loop
# ----------------
update_stage01_json() {
  local sample_name="$1"
  local cram="$2"
  local crai="$3"
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
}

submit_stage02_for_sample() {
  local wf_id_stage01="$1"
  local sample_name="$2"
  log "Populating Stage 02 inputs from Stage 01 outputs."
  bash "${PROJECT_ROOT}/populate_stage02_from_stage01.sh" "$wf_id_stage01" "${PROJECT_ROOT}/stage02_align_call_r1.json"
  log "Submitting Stage 02 workflow."
  local wf_id_stage02
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
    return 1
  fi
  append_sample_status "${sample_name}" "stage02" "${wf_id_stage02}" "Submitted"
  log "Stage 02 submitted: ${wf_id_stage02}"
  log "Stage 02 status URL: http://localhost:8094/api/workflows/v1/${wf_id_stage02}/status"
  log "Stage 02 metadata URL: http://localhost:8094/api/workflows/v1/${wf_id_stage02}/metadata"
  watch_status "$wf_id_stage02"
  local stage02_status
  stage02_status="$(get_wf_status "${wf_id_stage02}")"
  append_sample_status "${sample_name}" "stage02" "${wf_id_stage02}" "${stage02_status}"
  if [ "$stage02_status" != "Succeeded" ]; then
    log "Stage 02 did not succeed (status=${stage02_status})."
    return 1
  fi
  return 0
}

while IFS=$'\t' read -r sample_name cram crai; do
  sample_name="$(echo "${sample_name}" | tr -d '\r')"
  cram="$(echo "${cram}" | tr -d '\r')"
  crai="$(echo "${crai}" | tr -d '\r')"

  if [ -n "${SAMPLE_NAME}" ] && [ "${sample_name}" != "${SAMPLE_NAME}" ]; then
    continue
  fi

  # Skip if already succeeded (TSV registry or GCS outputs).
  if [ "${SKIP_ALREADY_PROCESSED}" = "1" ] && sample_stage_succeeded "${sample_name}" "stage01"; then
    wf_id_stage01="$(get_last_success_wf_id "${sample_name}" "stage01")"
    if [ -n "${wf_id_stage01}" ]; then
      log "Sample ${sample_name} already has Stage01 success; reusing workflow ID: ${wf_id_stage01}"
      append_sample_status "${sample_name}" "stage01" "${wf_id_stage01}" "Succeeded" "reused"
      continue
    fi
  fi
  if [ "${SKIP_ALREADY_PROCESSED}" = "1" ]; then
    wf_id_stage01="$(find_stage01_success_in_gcs "${sample_name}")"
    if [ -n "${wf_id_stage01}" ]; then
      log "Sample ${sample_name} already has Stage01 outputs in GCS; reusing workflow ID: ${wf_id_stage01}"
      append_sample_status "${sample_name}" "stage01" "${wf_id_stage01}" "Succeeded" "gcs-found"
      continue
    fi
  fi

  log "=== Processing sample ${sample_name} ==="

  # Update Stage01 input JSON for this sample.
  update_stage01_json "${sample_name}" "${cram}" "${crai}"

  # Submit Stage01 and wait for completion.
  log "Submitting Stage 01 workflow."
  wf_id_stage01="$(submit_stage01)"
  append_sample_status "${sample_name}" "stage01" "${wf_id_stage01}" "Submitted"
  log "Stage 01 submitted: ${wf_id_stage01}"
  log "Stage 01 status URL: http://localhost:8094/api/workflows/v1/${wf_id_stage01}/status"
  log "Stage 01 metadata URL: http://localhost:8094/api/workflows/v1/${wf_id_stage01}/metadata"
  watch_status "$wf_id_stage01"

  stage01_status="$(get_wf_status "${wf_id_stage01}")"
  append_sample_status "${sample_name}" "stage01" "${wf_id_stage01}" "${stage01_status}"
  if [ "$stage01_status" != "Succeeded" ]; then
    log "Stage 01 did not succeed (status=${stage01_status})."
    continue
  fi

  # Stage02 chain: populate inputs and submit for this sample.
  if [ "${SKIP_ALREADY_PROCESSED}" = "1" ] && sample_stage_succeeded "${sample_name}" "stage02"; then
    wf_id_stage02="$(get_last_success_wf_id "${sample_name}" "stage02")"
    if [ -n "${wf_id_stage02}" ]; then
      log "Sample ${sample_name} already has Stage02 success; reusing workflow ID: ${wf_id_stage02}"
      append_sample_status "${sample_name}" "stage02" "${wf_id_stage02}" "Succeeded" "reused"
      continue
    fi
  fi

  if ! submit_stage02_for_sample "${wf_id_stage01}" "${sample_name}"; then
    continue
  fi
done < <(
  awk -F',' -v s="${start_line}" -v e="${end_line}" '
    NR>=s && NR<=e { print $1 "\t" $2 "\t" $3 }
  ' "${MANIFEST_CSV}"
)

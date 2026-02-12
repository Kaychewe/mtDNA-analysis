#!/bin/bash
set -euo pipefail

MAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${MAIN_DIR}/config/run.env"
COMMON_SH_VERSION="2026-02-07.v3"

log() {
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $*"
}

log_debug() {
  if [ "${DEBUG:-0}" = "1" ]; then
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $*" >&2
  fi
}

die() {
  log "ERROR: $*"
  exit 1
}

load_env() {
  if [ ! -f "$CONFIG_FILE" ]; then
    die "Missing config file: $CONFIG_FILE"
  fi
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"

  # Auto-correct paths if run.env was generated on a different filesystem.
  if [ -z "${PROJECT_ROOT:-}" ] || [ ! -d "${PROJECT_ROOT}" ]; then
    PROJECT_ROOT="$(cd "${MAIN_DIR}/.." && pwd)"
  fi
  if [ -z "${ANALYSIS_ROOT:-}" ] || [ ! -d "${ANALYSIS_ROOT}" ]; then
    ANALYSIS_ROOT="${MAIN_DIR}"
  fi
  if [ -z "${RUNS_DIR:-}" ]; then
    RUNS_DIR="${ANALYSIS_ROOT}/runs"
  else
    parent_dir="$(dirname "${RUNS_DIR}")"
    if [ ! -d "${parent_dir}" ] || [ ! -w "${parent_dir}" ]; then
      RUNS_DIR="${ANALYSIS_ROOT}/runs"
    fi
  fi
  STAGE01_WDL="${STAGE01_WDL:-${PROJECT_ROOT}/stage01_subset_bam.wdl}"
  STAGE01_JSON="${STAGE01_JSON:-${PROJECT_ROOT}/stage01_subset_bam.json}"
  if [ ! -f "${STAGE01_WDL}" ]; then
    STAGE01_WDL="${PROJECT_ROOT}/stage01_subset_bam.wdl"
  fi
  if [ ! -f "${STAGE01_JSON}" ]; then
    STAGE01_JSON="${PROJECT_ROOT}/stage01_subset_bam.json"
  fi
  WDL_DEPS_ZIP="${WDL_DEPS_ZIP:-${PROJECT_ROOT}/wdl_deps.zip}"
  WDL_DEPS_SRC="${WDL_DEPS_SRC:-${PROJECT_ROOT}/mtSwirl/WDL/v2.5_MongoSwirl_Single}"
  if [ ! -d "${WDL_DEPS_SRC}" ]; then
    WDL_DEPS_SRC="${PROJECT_ROOT}/mtSwirl/WDL/v2.5_MongoSwirl_Single"
  fi
  if [ ! -d "$(dirname "${WDL_DEPS_ZIP}")" ]; then
    WDL_DEPS_ZIP="${PROJECT_ROOT}/wdl_deps.zip"
  fi
  if [ -z "${CROMWELL_RESTART_SCRIPT:-}" ] || [ ! -f "${CROMWELL_RESTART_SCRIPT}" ]; then
    CROMWELL_RESTART_SCRIPT="${PROJECT_ROOT}/cromwell_restart.sh"
  fi
  if [ -z "${LIST_DIR:-}" ] || [ ! -d "${LIST_DIR}" ]; then
    LIST_DIR="${PROJECT_ROOT}/mtDNA_v25_pilot_5"
  fi
  if [ -z "${SAMPLES_STATUS_TSV:-}" ]; then
    SAMPLES_STATUS_TSV="${ANALYSIS_ROOT}/runs/samples_status.tsv"
  fi

  export PROJECT_ROOT ANALYSIS_ROOT RUNS_DIR STAGE01_WDL STAGE01_JSON WDL_DEPS_ZIP WDL_DEPS_SRC LIST_DIR SAMPLES_STATUS_TSV

  : "${PROJECT_ROOT:?Missing PROJECT_ROOT}"
  : "${ANALYSIS_ROOT:?Missing ANALYSIS_ROOT}"
  : "${RUNS_DIR:?Missing RUNS_DIR}"
  : "${STAGE01_WDL:?Missing STAGE01_WDL}"
  : "${STAGE01_JSON:?Missing STAGE01_JSON}"
  : "${CROMWELL_RESTART_SCRIPT:?Missing CROMWELL_RESTART_SCRIPT}"
  : "${CROMWELL_STATUS_URL:?Missing CROMWELL_STATUS_URL}"
  : "${WDL_DEPS_SRC:?Missing WDL_DEPS_SRC}"
  : "${WDL_DEPS_ZIP:?Missing WDL_DEPS_ZIP}"
}

ensure_dirs() {
  mkdir -p "${RUNS_DIR}"
}

init_samples_status() {
  local tsv_dir
  tsv_dir="$(dirname "${SAMPLES_STATUS_TSV}")"
  mkdir -p "${tsv_dir}"
  if [ ! -f "${SAMPLES_STATUS_TSV}" ]; then
    echo -e "sample_id\tstage\tworkflow_id\tstatus\ttimestamp\tnotes" > "${SAMPLES_STATUS_TSV}"
  fi
}

append_sample_status() {
  local sample_id="$1"
  local stage="$2"
  local workflow_id="$3"
  local status="$4"
  local notes="${5:-}"
  local stamp
  stamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  printf "%s\t%s\t%s\t%s\t%s\t%s\n" "${sample_id}" "${stage}" "${workflow_id}" "${status}" "${stamp}" "${notes}" >> "${SAMPLES_STATUS_TSV}"
}

sample_stage_succeeded() {
  local sample_id="$1"
  local stage="$2"
  if [ ! -f "${SAMPLES_STATUS_TSV}" ]; then
    return 1
  fi
  awk -F'\t' -v s="${sample_id}" -v st="${stage}" '
    $1==s && $2==st { last=$4 }
    END { if (last=="Succeeded") exit 0; exit 1 }
  ' "${SAMPLES_STATUS_TSV}"
}

get_last_success_wf_id() {
  local sample_id="$1"
  local stage="$2"
  if [ ! -f "${SAMPLES_STATUS_TSV}" ]; then
    return 0
  fi
  awk -F'\t' -v s="${sample_id}" -v st="${stage}" '
    $1==s && $2==st && $4=="Succeeded" { last=$3 }
    END { if (length(last)) print last }
  ' "${SAMPLES_STATUS_TSV}"
}

get_wf_status() {
  local wf_id="$1"
  curl -s "http://localhost:8094/api/workflows/v1/${wf_id}/status" | python3 -c 'import json,sys
try:
    data = json.load(sys.stdin)
    print(data.get("status",""))
except Exception:
    print("")
' || true
}

make_run_dir() {
  local stamp
  stamp="$(date +"%Y%m%d_%H%M%S")"
  RUN_DIR="${RUNS_DIR}/${stamp}"
  mkdir -p "${RUN_DIR}/logs" "${RUN_DIR}/inputs" "${RUN_DIR}/outputs" "${RUN_DIR}/state"
  cp "$CONFIG_FILE" "${RUN_DIR}/state/run.env"
  export RUN_DIR
  log "Run directory: ${RUN_DIR}"
}

check_cromwell() {
  if curl -sf "${CROMWELL_STATUS_URL}" >/dev/null 2>&1; then
    log "Cromwell is reachable."
    return 0
  fi
  log "Cromwell not reachable; restarting..."
  bash "${CROMWELL_RESTART_SCRIPT}"
  for _ in {1..30}; do
    if curl -sf "${CROMWELL_STATUS_URL}" >/dev/null 2>&1; then
      log "Cromwell is up."
      return 0
    fi
    sleep 2
  done
  die "Cromwell did not become ready within 60s."
}

ensure_wdl_deps() {
  if [ -f "${WDL_DEPS_ZIP}" ]; then
    return 0
  fi
  if [ ! -d "${WDL_DEPS_SRC}" ]; then
    die "WDL deps directory not found: ${WDL_DEPS_SRC}"
  fi
  python3 - <<PY
import os, zipfile
wdl_src = os.environ["WDL_DEPS_SRC"]
out_zip = os.environ["WDL_DEPS_ZIP"]
with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for root, _, files in os.walk(wdl_src):
        for name in files:
            if name.endswith(".wdl"):
                full_path = os.path.join(root, name)
                rel_path = os.path.relpath(full_path, os.path.abspath("."))
                zf.write(full_path, rel_path)
print("Wrote", out_zip)
PY
}

pick_first_list() {
  local pattern="$1"
  local dir="$2"
  ls -1 "${dir}"/${pattern} 2>/dev/null | sort | head -n 1
}

populate_stage01_json() {
  local list_dir="$1"
  local sample_list cram_list crai_list

  sample_list="$(pick_first_list sample_list*.txt "$list_dir")"
  cram_list="$(pick_first_list cram_file_list*.txt "$list_dir")"
  crai_list="$(pick_first_list crai_file_list*.txt "$list_dir")"

  if [ -z "$sample_list" ] || [ -z "$cram_list" ] || [ -z "$crai_list" ]; then
    die "Missing list files in ${list_dir}. Expected sample_list*.txt, cram_file_list*.txt, crai_file_list*.txt"
  fi

  bash "${PROJECT_ROOT}/populate_stage01_from_lists.sh" "$cram_list" "$crai_list" "$sample_list" "$STAGE01_JSON"
}

submit_stage01() {
  local resp wf_id
  resp="$(bash "${PROJECT_ROOT}/submit_stage01.sh" 2>&1 || true)"
  wf_id="$(python3 -c 'import json,sys
try:
    data = json.load(sys.stdin)
    print(data.get("id",""))
except Exception:
    print("")
' <<<"$resp")"
  log_debug "Submit response JSON: ${resp}"
  log_debug "Parsed workflow ID: ${wf_id:-<empty>}"
  if [ -z "$wf_id" ]; then
    log "Submission response:"
    echo "$resp"
    die "Failed to parse workflow ID."
  fi
  echo "$wf_id"
}

watch_status() {
  local wf_id="$1"
  local failure_seen=0
  local unrecognized_seen=0
  while true; do
    local status_json status
    status_json="$(curl -s "http://localhost:8094/api/workflows/v1/${wf_id}/status")"
    status="$(python3 -c 'import json,sys
try:
    data = json.load(sys.stdin)
    print(data.get("status",""))
except Exception:
    print("")
' <<<"$status_json")"
    log "Status: ${status}"
    if [ "$status" = "fail" ]; then
      # Often returned right after submit: "Unrecognized workflow ID".
      if [ "${unrecognized_seen}" -eq 0 ]; then
        if echo "$status_json" | grep -q "Unrecognized workflow ID"; then
          unrecognized_seen=1
          sleep 5
          continue
        fi
      fi
    fi
    if [ "$status" = "Failed" ] || [ "$status" = "Aborted" ]; then
      if [ "${failure_seen}" -eq 0 ]; then
        failure_seen=1
        log "Fetching failure details..."
        curl -s "http://localhost:8094/api/workflows/v1/${wf_id}/metadata?includeKey=failures&includeKey=callRoot" || true
      fi
      break
    fi
    if [ "$status" = "Succeeded" ]; then
      break
    fi
    sleep 30
  done
}

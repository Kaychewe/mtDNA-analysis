#!/bin/bash
set -x

usage() {
  cat <<'EOF'
Usage: main_workflow.sh <command> [args]

Commands:
  list                  List available stage submission scripts.
  stage01               Run Stage 01 end-to-end (auto-pick first sample, submit, and watch status).
  submit <stage>        Submit a stage by name (e.g., stage01).
  status <workflow_id>  Check Cromwell status for a workflow ID.

Examples:
  ./main_workflow.sh list
  ./main_workflow.sh stage01
  ./main_workflow.sh submit stage01
  ./main_workflow.sh status <workflow_id>
EOF
}

check_cromwell() {
  if curl -sf "http://localhost:8094/engine/v1/status" >/dev/null 2>&1; then
    return 0
  fi
  echo "Cromwell not reachable; restarting..."
  bash cromwell_restart.sh
  for i in {1..30}; do
    if curl -sf "http://localhost:8094/engine/v1/status" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "Cromwell did not become ready within 60s."
  exit 1
}

pick_first_list() {
  local pattern="$1"
  local dir="$2"
  ls -1 "${dir}"/${pattern} 2>/dev/null | sort | head -n 1
}

ensure_wdl_deps() {
  if [ -f "wdl_deps.zip" ]; then
    return 0
  fi
  wdl_src="mtSwirl/WDL/v2.5_MongoSwirl_Single"
  if [ ! -d "$wdl_src" ]; then
    echo "WDL deps directory not found: $wdl_src"
    exit 1
  fi
  python3 - <<'PY'
import os, zipfile

wdl_src = "mtSwirl/WDL/v2.5_MongoSwirl_Single"
out_zip = "wdl_deps.zip"
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

run_stage01() {
  check_cromwell
  ensure_wdl_deps

  list_dir="${STAGE01_LIST_DIR:-mtDNA_v25_pilot_5}"
  if [ ! -d "$list_dir" ]; then
    list_dir="."
  fi

  sample_list="$(pick_first_list 'sample_list*.txt' "$list_dir")"
  cram_list="$(pick_first_list 'cram_file_list*.txt' "$list_dir")"
  crai_list="$(pick_first_list 'crai_file_list*.txt' "$list_dir")"

  if [ -z "$sample_list" ] || [ -z "$cram_list" ] || [ -z "$crai_list" ]; then
    echo "Missing list files. Expected sample_list*.txt, cram_file_list*.txt, crai_file_list*.txt in ${list_dir}"
    exit 1
  fi

  bash populate_stage01_from_lists.sh "$cram_list" "$crai_list" "$sample_list" "stage01_subset_bam.json"

  resp="$(bash submit_stage01.sh)"
  wf_id="$(echo "$resp" | python3 - <<'PY'
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("id",""))
except Exception:
    print("")
PY
)"

  if [ -z "$wf_id" ]; then
    echo "Submission response:"
    echo "$resp"
    echo "Failed to parse workflow ID."
    exit 1
  fi

  echo "Submitted Stage 01 workflow: $wf_id"

  # Watch status
  while true; do
    status_json="$(curl -s "http://localhost:8094/api/workflows/v1/${wf_id}/status")"
    status="$(echo "$status_json" | python3 - <<'PY'
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("status",""))
except Exception:
    print("")
PY
)"
    echo "Status: ${status}"
    if [ "$status" = "Succeeded" ] || [ "$status" = "Failed" ] || [ "$status" = "Aborted" ]; then
      break
    fi
    sleep 30
  done
}

cmd="${1:-}"
case "$cmd" in
  list)
    ls -1 submit_stage*.sh 2>/dev/null || echo "No submit_stage*.sh scripts found."
    ;;
  stage01)
    run_stage01
    ;;
  submit)
    stage="${2:-}"
    if [ -z "$stage" ]; then
      echo "Missing stage name (e.g., stage01)."
      exit 1
    fi
    script="submit_${stage}.sh"
    if [ ! -f "$script" ]; then
      echo "Stage submit script not found: $script"
      exit 1
    fi
    bash "$script"
    ;;
  status)
    wf="${2:-}"
    if [ -z "$wf" ]; then
      echo "Missing workflow ID."
      exit 1
    fi
    curl -s "http://localhost:8094/api/workflows/v1/${wf}/status"
    ;;
  *)
    usage
    exit 1
    ;;
esac

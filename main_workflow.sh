#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: main_workflow.sh <command> [args]

Commands:
  list                  List available stage submission scripts.
  submit <stage>        Submit a stage by name (e.g., stage01).
  status <workflow_id>  Check Cromwell status for a workflow ID.

Examples:
  ./main_workflow.sh list
  ./main_workflow.sh submit stage01
  ./main_workflow.sh status <workflow_id>
EOF
}

cmd="${1:-}"
case "$cmd" in
  list)
    ls -1 submit_stage*.sh 2>/dev/null || echo "No submit_stage*.sh scripts found."
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

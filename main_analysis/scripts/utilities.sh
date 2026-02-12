#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

usage() {
  cat <<'EOF'
Usage:
  utilities.sh dry-run --batch-size <n> --batch-index <n> [--manifest <path>]

Examples:
  bash main_analysis/scripts/utilities.sh dry-run --batch-size 10 --batch-index 1
  bash main_analysis/scripts/utilities.sh dry-run --batch-size 10 --batch-index 2 --manifest /path/to/manifest.csv
EOF
}

dry_run_batch() {
  local manifest="$1"
  local batch_size="$2"
  local batch_index="$3"
  if [ ! -f "${manifest}" ]; then
    echo "Manifest not found: ${manifest}" >&2
    exit 1
  fi
  if ! [[ "${batch_size}" =~ ^[0-9]+$ ]] || ! [[ "${batch_index}" =~ ^[0-9]+$ ]]; then
    echo "--batch-size and --batch-index must be positive integers." >&2
    exit 1
  fi

  local start_line end_line
  start_line=$(( (batch_index - 1) * batch_size + 2 ))
  end_line=$(( start_line + batch_size - 1 ))

  echo "Dry run: batch ${batch_index} (size ${batch_size}), lines ${start_line}-${end_line} of ${manifest}"
  awk -F',' -v s="${start_line}" -v e="${end_line}" '
    NR>=s && NR<=e { print $1 }
  ' "${manifest}"
}

cmd="${1:-}"
shift || true

case "${cmd}" in
  dry-run)
    load_env
    manifest="${PROJECT_ROOT}/manifest.csv"
    batch_size=""
    batch_index=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --manifest)
          manifest="${2:-}"
          shift 2
          ;;
        --batch-size)
          batch_size="${2:-}"
          shift 2
          ;;
        --batch-index)
          batch_index="${2:-}"
          shift 2
          ;;
        --help|-h)
          usage
          exit 0
          ;;
        *)
          echo "Unknown argument: $1" >&2
          usage
          exit 1
          ;;
      esac
    done
    if [ -z "${batch_size}" ] || [ -z "${batch_index}" ]; then
      echo "--batch-size and --batch-index are required." >&2
      usage
      exit 1
    fi
    dry_run_batch "${manifest}" "${batch_size}" "${batch_index}"
    ;;
  ""|--help|-h)
    usage
    ;;
  *)
    echo "Unknown command: ${cmd}" >&2
    usage
    exit 1
    ;;
esac

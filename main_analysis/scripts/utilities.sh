#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

usage() {
  cat <<'EOF'
Usage:
  utilities.sh dry-run --batch-size <n> --batch-index <n> [--manifest <path>]
  utilities.sh generate-manifest [--manifest <path>] [--source-uri <gs://.../manifest.csv>] [--project <gcp_project>]
  utilities.sh check-wdl-deps

Examples:
  bash main_analysis/scripts/utilities.sh dry-run --batch-size 10 --batch-index 1
  bash main_analysis/scripts/utilities.sh dry-run --batch-size 10 --batch-index 2 --manifest /path/to/manifest.csv
  bash main_analysis/scripts/utilities.sh generate-manifest
  bash main_analysis/scripts/utilities.sh generate-manifest --source-uri gs://path/to/manifest.csv
  bash main_analysis/scripts/utilities.sh check-wdl-deps
EOF
}

dry_run_batch() {
  local manifest="$1"
  local batch_size="$2"
  local batch_index="$3"
  if [ ! -f "${manifest}" ]; then
    echo "Manifest not found: ${manifest}. Attempting to generate." >&2
    generate_manifest "${manifest}" "" "${GOOGLE_PROJECT:-}"
  fi
  if [ ! -f "${manifest}" ]; then
    echo "Manifest still missing: ${manifest}" >&2
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

generate_manifest() {
  local manifest_path="$1"
  local source_uri="$2"
  local project="$3"

  if [ -z "${source_uri}" ]; then
    if [ -n "${CDR_STORAGE_PATH:-}" ]; then
      source_uri="${CDR_STORAGE_PATH}/wgs/cram/manifest.csv"
    else
      echo "Missing source URI. Set --source-uri or export CDR_STORAGE_PATH." >&2
      exit 1
    fi
  fi

  if [ -n "${project}" ]; then
    gsutil -u "${project}" cp "${source_uri}" "${manifest_path}"
  else
    gsutil cp "${source_uri}" "${manifest_path}"
  fi
  echo "Wrote manifest: ${manifest_path}"
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
  generate-manifest)
    load_env
    manifest="${PROJECT_ROOT}/manifest.csv"
    source_uri=""
    project="${GOOGLE_PROJECT:-}"
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --manifest)
          manifest="${2:-}"
          shift 2
          ;;
        --source-uri)
          source_uri="${2:-}"
          shift 2
          ;;
        --project)
          project="${2:-}"
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
    generate_manifest "${manifest}" "${source_uri}" "${project}"
    ;;
  check-wdl-deps)
    load_env
    check_wdl_deps
    echo "WDL deps zip is ready: ${WDL_DEPS_ZIP}"
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

#!/bin/bash
# Wrapper to run the main workflow entrypoint.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "${ROOT_DIR}/main_analysis/scripts/main_workflow.sh"

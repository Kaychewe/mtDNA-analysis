#!/bin/bash
set -euo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  echo "Usage: $(basename "$0") <workflow_id> [--details]"
  exit 0
fi

if [ -z "${1:-}" ]; then
  echo "ERROR: missing workflow_id"
  echo "Usage: $(basename "$0") <workflow_id> [--details]"
  exit 1
fi

WF_ID="$1"
DETAILS="${2:-}"

echo "Status:"
curl -s "http://localhost:8094/api/workflows/v1/${WF_ID}/status"
echo ""

if [ "${DETAILS}" = "--details" ]; then
  echo "Failures + callRoot:"
  curl -s "http://localhost:8094/api/workflows/v1/${WF_ID}/metadata?includeKey=failures&includeKey=callRoot"
  echo ""
fi

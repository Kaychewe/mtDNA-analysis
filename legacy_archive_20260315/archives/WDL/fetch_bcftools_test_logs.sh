#!/usr/bin/env bash
set -euo pipefail

WF_ID=${1:-}
CROMWELL_URL=${CROMWELL_URL:-http://localhost:8094}
OUT_DIR=${2:-bcftools_binary_test_logs}

if [ -z "$WF_ID" ]; then
  echo "Usage: $0 <workflow_id> [output_dir]"
  exit 1
fi

mkdir -p "$OUT_DIR/$WF_ID"

meta=$(curl -s "${CROMWELL_URL}/api/workflows/v1/${WF_ID}/metadata?includeKey=callRoot")

call_root=$(python3 - <<'PY' "$meta"
import json, sys
j = json.loads(sys.argv[1])
call = j['calls']['DiagnosticBcftoolsBinaryTest.TestBcftoolsBundle'][0]
print(call['callRoot'])
PY
)

echo "Call root: $call_root"

for f in stdout stderr report.txt; do
  gsutil cp "${call_root}/${f}" "$OUT_DIR/$WF_ID/" || true
  echo "Fetched ${f}"
done

echo "Downloaded logs to $OUT_DIR/$WF_ID"

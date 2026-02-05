#!/usr/bin/env bash
set -euo pipefail

WF_ID=${1:-}
CROMWELL_URL=${CROMWELL_URL:-http://localhost:8094}
OUT_DIR=${2:-docker_probe_reports}

if [ -z "$WF_ID" ]; then
  echo "Usage: $0 <workflow_id> [output_dir]"
  exit 1
fi

mkdir -p "$OUT_DIR/$WF_ID"

json=$(curl -s "${CROMWELL_URL}/api/workflows/v1/${WF_ID}/outputs")

python3 - <<'PY' "$json" "$OUT_DIR" "$WF_ID"
import json, sys, os
j = json.loads(sys.argv[1])
out_dir = os.path.join(sys.argv[2], sys.argv[3])

# Collect any output arrays of gs:// paths
paths = []
for key, val in j.get('outputs', {}).items():
    if isinstance(val, list):
        for v in val:
            if isinstance(v, str) and v.startswith('gs://'):
                paths.append(v)
    elif isinstance(val, str) and val.startswith('gs://'):
        paths.append(val)

# Write a manifest of expected paths
manifest = os.path.join(out_dir, 'gs_paths.txt')
os.makedirs(out_dir, exist_ok=True)
with open(manifest, 'w') as f:
    for p in paths:
        f.write(p + "\n")

print("\n".join(paths))
PY

# Copy all listed files to the output directory
if [ -s "$OUT_DIR/$WF_ID/gs_paths.txt" ]; then
  gsutil -m cp -I "$OUT_DIR/$WF_ID" < "$OUT_DIR/$WF_ID/gs_paths.txt"
  echo "Downloaded reports to $OUT_DIR/$WF_ID"
else
  echo "No gs:// outputs found for workflow $WF_ID"
fi

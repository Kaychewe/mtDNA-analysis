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

# Write a manifest with target local paths
manifest = os.path.join(out_dir, 'gs_paths.tsv')
os.makedirs(out_dir, exist_ok=True)
with open(manifest, 'w') as f:
    for p in paths:
        # derive local path from call name and shard
        # example: .../call-ProbeDockerToolsSafe/shard-0/docker_probe_report.txt
        rel = "unknown/docker_probe_report.txt"
        parts = p.split("/")
        call_part = next((x for x in parts if x.startswith("call-")), "call-unknown")
        shard_part = next((x for x in parts if x.startswith("shard-")), "shard-unknown")
        base = parts[-1]
        rel = os.path.join(call_part, shard_part, base)
        f.write(p + "\t" + rel + "\n")

print("\n".join(paths))
PY

# Copy all listed files to the output directory (preserve call/shard structure)
if [ -s "$OUT_DIR/$WF_ID/gs_paths.tsv" ]; then
  while IFS=$'\t' read -r gs_path rel_path; do
    [ -z "$gs_path" ] && continue
    dest_dir="$OUT_DIR/$WF_ID/$(dirname "$rel_path")"
    mkdir -p "$dest_dir"
    gsutil cp "$gs_path" "$dest_dir/$(basename "$rel_path")" >/dev/null
  done < "$OUT_DIR/$WF_ID/gs_paths.tsv"
  echo "Downloaded reports to $OUT_DIR/$WF_ID"
else
  echo "No gs:// outputs found for workflow $WF_ID"
fi

# Build a summary TSV
summary="$OUT_DIR/$WF_ID/summary.tsv"
echo -e "file\timage\tstatus\tok_tools\tmissing_tools" > "$summary"
while IFS= read -r -d '' file; do
  image=$(grep -m1 '^image=' "$file" | sed 's/^image=//')
  status=$(grep -m1 '^status=' "$file" | sed 's/^status=//' )
  [ -z "$status" ] && status="probed"
  ok_tools=$(grep -c '^OK: ' "$file" || true)
  missing_tools=$(grep -c '^MISSING: ' "$file" || true)
  echo -e "${file}\t${image}\t${status}\t${ok_tools}\t${missing_tools}" >> "$summary"
done < <(find "$OUT_DIR/$WF_ID" -name 'docker_probe_report.txt' -print0)

echo "Summary written to $summary"

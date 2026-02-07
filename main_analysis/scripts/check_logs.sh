#!/bin/bash
set -euo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  echo "Usage: $(basename "$0") <workflow_id> [call_name]"
  echo "Example: $(basename "$0") <wf_id> StageAlignAndCallR1.AlignAndCallR1"
  echo "Example: $(basename "$0") <wf_id> AlignAndCallR1.CallMt"
  exit 0
fi

if [ -z "${1:-}" ]; then
  echo "ERROR: missing workflow_id"
  exit 1
fi

WF_ID="$1"
CALL_NAME="${2:-}"

tmp_body="$(mktemp)"
http_code="$(curl -sS -w "%{http_code}" -o "${tmp_body}" "http://localhost:8094/api/workflows/v1/${WF_ID}/metadata" || true)"
metadata="$(cat "${tmp_body}")"
rm -f "${tmp_body}"
if [ -z "$(printf '%s' "${metadata}" | tr -d '[:space:]')" ]; then
  echo "ERROR: empty metadata response for ${WF_ID} (http ${http_code})"
  exit 1
fi
if [ "${http_code}" != "200" ]; then
  echo "ERROR: metadata request failed (http ${http_code})"
  echo "Response body:"
  echo "${metadata}"
  exit 1
fi

CALL_NAME="${CALL_NAME}" python3 -c 'import json, os, sys
raw = sys.stdin.read()
try:
    data = json.loads(raw)
except Exception as exc:
    print("ERROR: failed to parse metadata JSON:", exc)
    print("Response prefix:", raw[:200].replace("\n", "\\n"))
    print("Response length:", len(raw))
    sys.exit(1)

call_name = os.environ.get("CALL_NAME", "")

def print_call(call_key, call):
    call_root = call.get("callRoot", "")
    if call_root:
        print(call_key, call_root)

calls = data.get("calls", {}) or {}
if call_name:
    if call_name in calls and calls[call_name]:
        print_call(call_name, calls[call_name][0])
        sys.exit(0)
    for k, v in calls.items():
        if k.endswith(call_name) and v:
            print_call(k, v[0])
            sys.exit(0)
    print("No matching call found for:", call_name)
else:
    for k, v in calls.items():
        if v:
            print_call(k, v[0])
' <<<"${metadata}"

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

log "Stage 02 diagnostics starting."
log "Using common.sh version: ${COMMON_SH_VERSION:-unknown}"

load_env

STAGE02_WDL="${PROJECT_ROOT}/stage02_align_call_r1.wdl"
STAGE02_JSON="${PROJECT_ROOT}/stage02_align_call_r1.json"

if [ ! -f "${STAGE02_WDL}" ]; then
  die "Missing Stage 02 WDL: ${STAGE02_WDL}"
fi
if [ ! -f "${STAGE02_JSON}" ]; then
  die "Missing Stage 02 JSON: ${STAGE02_JSON}"
fi

log "Validating Stage 02 WDL with womtool (syntax only)."
if [ -f "${PROJECT_ROOT}/womtool-91.jar" ]; then
  java -jar "${PROJECT_ROOT}/womtool-91.jar" validate "${STAGE02_WDL}" >/dev/null
  log "WDL validation: OK"
else
  log "womtool-91.jar not found; skipping WDL validation."
fi

log "Checking Stage 02 inputs for REPLACE_ME placeholders."
if grep -q "REPLACE_ME" "${STAGE02_JSON}"; then
  die "Stage 02 JSON contains REPLACE_ME placeholders."
fi

log "Checking required GCS inputs in Stage 02 JSON (gsutil stat)."
python3 - <<'PY' "${STAGE02_JSON}"
import json, sys, subprocess

json_path = sys.argv[1]
with open(json_path) as fh:
    data = json.load(fh)

# Required file inputs for Stage 02
keys = [
    "StageAlignAndCallR1.input_bam",
    "StageAlignAndCallR1.input_bai",
    "StageAlignAndCallR1.ref_fasta",
    "StageAlignAndCallR1.ref_fasta_index",
    "StageAlignAndCallR1.ref_dict",
    "StageAlignAndCallR1.mt_fasta",
    "StageAlignAndCallR1.mt_fasta_index",
    "StageAlignAndCallR1.mt_dict",
    "StageAlignAndCallR1.mt_interval_list",
    "StageAlignAndCallR1.nuc_interval_list",
    "StageAlignAndCallR1.blacklisted_sites",
    "StageAlignAndCallR1.blacklisted_sites_index",
    "StageAlignAndCallR1.haplocheck_zip",
]

missing = []
not_gs = []
for key in keys:
    val = data.get(key)
    if not val:
        missing.append(key)
        continue
    if not str(val).startswith("gs://"):
        not_gs.append((key, val))

if missing:
    print("ERROR: missing required inputs:")
    for k in missing:
        print("  -", k)
    sys.exit(1)

if not_gs:
    print("ERROR: inputs not on GCS:")
    for k, v in not_gs:
        print(f"  - {k}: {v}")
    sys.exit(1)

# gsutil stat checks
failed = []
for key in keys:
    uri = data[key]
    try:
        subprocess.check_output(["gsutil", "-q", "stat", uri])
    except subprocess.CalledProcessError:
        failed.append((key, uri))

if failed:
    print("ERROR: gsutil stat failed for:")
    for k, v in failed:
        print(f"  - {k}: {v}")
    sys.exit(1)

print("GCS input checks: OK")
PY

log "Stage 02 diagnostics complete."

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

log "Stage 03 diagnostics starting."
log "Using common.sh version: ${COMMON_SH_VERSION:-unknown}"

load_env

STAGE03_WDL="${PROJECT_ROOT}/stage03_produce_self_reference.wdl"
STAGE03_JSON="${PROJECT_ROOT}/stage03_produce_self_reference.json"

if [ ! -f "${STAGE03_WDL}" ]; then
  die "Missing Stage 03 WDL: ${STAGE03_WDL}"
fi
if [ ! -f "${STAGE03_JSON}" ]; then
  die "Missing Stage 03 JSON: ${STAGE03_JSON}"
fi

log "Validating Stage 03 WDL with womtool (syntax only)."
if [ -f "${PROJECT_ROOT}/womtool-91.jar" ]; then
  java -jar "${PROJECT_ROOT}/womtool-91.jar" validate "${STAGE03_WDL}" >/dev/null
  log "WDL validation: OK"
else
  log "womtool-91.jar not found; skipping WDL validation."
fi

log "Checking ProduceSelfReferenceFiles WDL for samtools faidx guard."
SINGLE_WDL="${PROJECT_ROOT}/mtSwirl/WDL/v2.5_MongoSwirl_Single/ProduceSelfReferenceFiles_v2_5_Single.wdl"
if [ -f "${SINGLE_WDL}" ]; then
  if ! grep -q "samtools faidx .*mt_ref_fasta" "${SINGLE_WDL}" || ! grep -q "samtools faidx .*ref_fasta" "${SINGLE_WDL}"; then
    die "Missing samtools faidx guard in ${SINGLE_WDL}. Update WDL and regenerate wdl_deps.zip."
  fi
else
  log "Single WDL not found at ${SINGLE_WDL}; skipping faidx guard check."
fi

log "Checking Stage 03 inputs for REPLACE_ME placeholders."
if grep -q "REPLACE_ME" "${STAGE03_JSON}"; then
  log "Stage 03 JSON contains REPLACE_ME placeholders. Showing keys:"
  python3 - <<'PY' "${STAGE03_JSON}"
import json, sys
path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)
for k, v in data.items():
    if isinstance(v, str) and "REPLACE_ME" in v:
        print(f"  - {k}: {v}")
PY
  die "Stage 03 JSON contains REPLACE_ME placeholders. Run populate_stage03_from_stage02.sh first."
fi

log "Checking required GCS inputs in Stage 03 JSON (gsutil stat)."
python3 - <<'PY' "${STAGE03_JSON}"
import json, sys, subprocess

json_path = sys.argv[1]
with open(json_path) as fh:
    data = json.load(fh)

keys = [
    "StageProduceSelfReferenceFiles.mtdna_variants",
    "StageProduceSelfReferenceFiles.nuc_variants",
    "StageProduceSelfReferenceFiles.mt_fasta",
    "StageProduceSelfReferenceFiles.mt_fasta_index",
    "StageProduceSelfReferenceFiles.mt_dict",
    "StageProduceSelfReferenceFiles.mt_interval_list",
    "StageProduceSelfReferenceFiles.non_control_region_interval_list",
    "StageProduceSelfReferenceFiles.ref_fasta",
    "StageProduceSelfReferenceFiles.ref_fasta_index",
    "StageProduceSelfReferenceFiles.ref_dict",
    "StageProduceSelfReferenceFiles.nuc_interval_list",
    "StageProduceSelfReferenceFiles.blacklisted_sites",
    "StageProduceSelfReferenceFiles.blacklisted_sites_index",
    "StageProduceSelfReferenceFiles.FaRenamingScript",
    "StageProduceSelfReferenceFiles.CheckVariantBoundsScript",
    "StageProduceSelfReferenceFiles.CheckHomOverlapScript",
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

log "Stage 03 diagnostics complete."

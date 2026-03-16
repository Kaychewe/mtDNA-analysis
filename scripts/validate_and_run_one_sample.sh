#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WDL_PATH="${ROOT_DIR}/wdl/aou_mitohpc_single_sample.wdl"
INPUTS_PATH="${ROOT_DIR}/inputs/test_one_sample_aou.json"
LEGACY_DIR="${ROOT_DIR}/legacy_archive_20260315"
TMP_WOMTOOL="${ROOT_DIR}/.tmp/womtool-91.jar"
LEGACY_WOMTOOL="${LEGACY_DIR}/womtool-91.jar"
CONF_PATH="${ROOT_DIR}/config/cromwell.batch.conf"

echo "WDL: ${WDL_PATH}"
echo "Inputs: ${INPUTS_PATH}"
echo "Config: ${CONF_PATH}"

if command -v java >/dev/null 2>&1 && [ -f "${TMP_WOMTOOL}" ]; then
  echo "Validating WDL with ${TMP_WOMTOOL}..."
  java -jar "${TMP_WOMTOOL}" validate "${WDL_PATH}"
elif command -v java >/dev/null 2>&1 && [ -f "${LEGACY_WOMTOOL}" ]; then
  echo "Validating WDL with ${LEGACY_WOMTOOL}..."
  java -jar "${LEGACY_WOMTOOL}" validate "${WDL_PATH}"
else
  echo "Skipping womtool validation because java or womtool-91.jar is unavailable."
fi

cat <<'EOF'
To run a one-sample Cromwell test in an AoU-compatible environment, use:

  python scripts/check_environment.py
  python scripts/write_cromwell_config.py
  python scripts/cromwell_server.py start

  java -Dconfig.file=/path/to/mtDNA-analysis/config/cromwell.batch.conf \
    -jar /path/to/cromwell-91.jar run \
    /path/to/mtDNA-analysis/wdl/aou_mitohpc_single_sample.wdl \
    --inputs /path/to/mtDNA-analysis/inputs/test_one_sample_aou.json

This helper intentionally stops after validation guidance because Cromwell backend
configuration and AoU credentials are environment-specific.
EOF

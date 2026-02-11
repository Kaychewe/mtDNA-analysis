#!/bin/bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Build a UCSC tools bundle (chainSwap, liftOver, igvtools) and optionally upload to GCS.

Usage:
  build_ucsc_bundle.sh [output_tar] [--no-upload]

Environment:
  UCSC_BASE_URL   Base URL for UCSC binaries (default: https://hgdownload.cse.ucsc.edu/admin/exe/linux.x86_64)
  IGVTOOLS_URL    Direct URL to igvtools/IGV zip (default: https://data.broadinstitute.org/igv/projects/downloads/2.16/IGV_2.16.2.zip)
  WORKSPACE_BUCKET  GCS bucket (e.g. gs://...); if set and --no-upload not given, uploads to $WORKSPACE_BUCKET/tools/ucsc/

Examples:
  WORKSPACE_BUCKET="gs://my-bucket" bash build_ucsc_bundle.sh
USAGE
}

out_tar="${1:-ucsc-tools-linux-x86_64.tar.gz}"
shift || true

no_upload="false"
if [ "${1:-}" = "--no-upload" ]; then
  no_upload="true"
  shift
fi

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

UCSC_BASE_URL="${UCSC_BASE_URL:-https://hgdownload.cse.ucsc.edu/admin/exe/linux.x86_64}"
IGVTOOLS_URL="${IGVTOOLS_URL:-https://data.broadinstitute.org/igv/projects/downloads/2.16/IGV_2.16.2.zip}"

workdir="$(mktemp -d)"
cleanup() { rm -rf "${workdir}"; }
trap cleanup EXIT

mkdir -p "${workdir}/ucsc_tools/bin"

echo "Downloading UCSC binaries from ${UCSC_BASE_URL}"
curl -fsSL "${UCSC_BASE_URL}/liftOver" -o "${workdir}/ucsc_tools/bin/liftOver"
curl -fsSL "${UCSC_BASE_URL}/chainSwap" -o "${workdir}/ucsc_tools/bin/chainSwap"
chmod +x "${workdir}/ucsc_tools/bin/liftOver" "${workdir}/ucsc_tools/bin/chainSwap"

echo "Downloading igvtools from ${IGVTOOLS_URL}"
curl -fsSL "${IGVTOOLS_URL}" -o "${workdir}/igvtools.zip"
unzip -q "${workdir}/igvtools.zip" -d "${workdir}/igvtools_unpack"

# Try to locate igvtools jar or wrapper script in the extracted archive
igv_jar="$(find "${workdir}/igvtools_unpack" -type f -name 'igvtools*.jar' | head -n 1 || true)"

if [ -n "${igv_jar}" ]; then
  cp "${igv_jar}" "${workdir}/ucsc_tools/igvtools.jar"
else
  echo "ERROR: could not find igvtools jar in the downloaded zip."
  exit 1
fi

cat > "${workdir}/ucsc_tools/README.txt" <<'TXT'
UCSC tools bundle for AoU Batch usage.
Includes:
  - liftOver
  - chainSwap
  - igvtools (jar or wrapper)
TXT

tar -czf "${out_tar}" -C "${workdir}" ucsc_tools
echo "Wrote ${out_tar}"

if [ "${no_upload}" = "false" ] && [ -n "${WORKSPACE_BUCKET:-}" ]; then
  dest="${WORKSPACE_BUCKET}/tools/ucsc/$(basename "${out_tar}")"
  echo "Uploading to ${dest}"
  gsutil -m cp "${out_tar}" "${dest}"
  echo "Uploaded ${dest}"
else
  echo "Skipping upload (set WORKSPACE_BUCKET to enable, or omit --no-upload)."
fi

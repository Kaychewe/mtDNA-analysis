#!/usr/bin/env bash
set -euo pipefail

BUNDLE="./bcftools_build/bcftools-1.23-linux-x86_64.tar.gz"
BUCKET="${WORKSPACE_BUCKET:-}"
DEST_SUBDIR="tools/bcftools"

if [ -z "$BUCKET" ]; then
  echo "WORKSPACE_BUCKET is not set."
  exit 1
fi

if [ ! -f "$BUNDLE" ]; then
  echo "Missing bundle: $BUNDLE"
  exit 1
fi

# Validate bundle contains bcftools, bgzip, tabix
tmp_dir=$(mktemp -d)
tar -xzf "$BUNDLE" -C "$tmp_dir"
for tool in bcftools bgzip tabix; do
  if [ ! -x "$tmp_dir/bin/$tool" ]; then
    echo "Bundle missing $tool in bin/ (expected $tmp_dir/bin/$tool)"
    rm -rf "$tmp_dir"
    exit 1
  fi
done
rm -rf "$tmp_dir"

DEST="${BUCKET%/}/${DEST_SUBDIR}/"

echo "Uploading $BUNDLE to $DEST"

gsutil cp "$BUNDLE" "$DEST"

echo "Uploaded. Listing destination:"

gsutil ls "$DEST"

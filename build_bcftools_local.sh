#!/usr/bin/env bash
set -e

# Build bcftools locally in workspace and package a self-contained tarball
# Usage: ./build_bcftools_local.sh

VERSION=1.23
TARBALL_URL="https://github.com/samtools/bcftools/releases/download/1.23/bcftools-1.23.tar.bz2"
HTSLIB_URL="https://github.com/samtools/htslib/releases/download/1.23/htslib-1.23.tar.bz2"
TARBALL="bcftools-1.23.tar.bz2"
HTSLIB_TARBALL="htslib-1.23.tar.bz2"
SRC_DIR="bcftools-1.23"
PREFIX_DIR="$PWD/bcftools_build"
OUT_TARBALL="bcftools-${VERSION}-linux-x86_64.tar.gz"

rm -f "$TARBALL" "$HTSLIB_TARBALL"
curl -L -o "$TARBALL" "$TARBALL_URL"
curl -L -o "$HTSLIB_TARBALL" "$HTSLIB_URL"

rm -rf "$SRC_DIR" "$PREFIX_DIR" "$OUT_TARBALL"
mkdir -p "$PREFIX_DIR"

tar -xjf "$TARBALL"
tar -xjf "$HTSLIB_TARBALL"
rm -rf "$SRC_DIR/htslib"
mv htslib-1.23 "$SRC_DIR/htslib"
cd "$SRC_DIR"

# Build with bundled htslib to avoid external dependency mismatch
make -j "$(nproc)" HTSDIR=htslib
make install prefix="$PREFIX_DIR"

cd "$PREFIX_DIR"
# Bundle bin + lib to keep it runnable when staged
# bcftools needs htslib shared libs from lib/
# Include bcftools, bgzip, tabix
if [ ! -x bin/bcftools ]; then
  echo "bcftools build failed: missing bin/bcftools"
  exit 1
fi

tar -czf "$OUT_TARBALL" bin lib

# Smoke test
./bin/bcftools --version | head -n 2

echo "Built $OUT_TARBALL"

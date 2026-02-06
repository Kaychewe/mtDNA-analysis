#!/usr/bin/env bash
set -e

# Build bcftools locally in workspace and package a self-contained tarball
# Usage: ./build_bcftools_local.sh [version]

VERSION=${1:-1.23}
TARBALL="bcftools-${VERSION}.tar.bz2"
SRC_DIR="bcftools-${VERSION}"
PREFIX_DIR="$PWD/bcftools_build"
OUT_TARBALL="bcftools-${VERSION}-linux-x86_64.tar.gz"

if [ ! -f "$TARBALL" ]; then
  echo "Missing $TARBALL in current directory. Download it first."
  exit 1
fi

rm -rf "$SRC_DIR" "$PREFIX_DIR" "$OUT_TARBALL"
mkdir -p "$PREFIX_DIR"

tar -xjf "$TARBALL"
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

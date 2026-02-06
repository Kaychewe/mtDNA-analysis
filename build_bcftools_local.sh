#!/usr/bin/env bash
set -e
# version 1.0 gsutil ls gs://fc-secure-76d68a64-00aa-40a7-b2c5-ca956db2719b/tools/bcftools/
# Build bcftools locally in workspace and package a self-contained tarball
# Usage: ./build_bcftools_local.sh

VERSION=1.23
TARBALL_URL="https://github.com/samtools/bcftools/releases/download/1.23/bcftools-1.23.tar.bz2"
HTSLIB_URL="https://github.com/samtools/htslib/releases/download/1.23/htslib-1.23.tar.bz2"
TARBALL="bcftools-1.23.tar.bz2"
HTSLIB_TARBALL="htslib-1.23.tar.bz2"
SRC_DIR="bcftools-1.23"
ROOT_DIR="$PWD"
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

# Build htslib without libcurl to avoid runtime libcurl dependency in Batch
cd htslib
./configure --disable-libcurl
make -j "$(nproc)"
cd ..

# Build bcftools against bundled htslib
make -j "$(nproc)" HTSDIR=htslib
make install prefix="$PREFIX_DIR"

cd "$PREFIX_DIR"
# Also include bgzip/tabix from htslib build (source tree)
cp "$ROOT_DIR/$SRC_DIR/htslib/bgzip" "$PREFIX_DIR/bin/"
cp "$ROOT_DIR/$SRC_DIR/htslib/tabix" "$PREFIX_DIR/bin/"

# Bundle bin and libexec (plugins). htslib built without libcurl.
# Include bcftools and helper scripts in bin.
if [ ! -x bin/bcftools ]; then
  echo "bcftools build failed: missing bin/bcftools"
  exit 1
fi

tar -czf "$OUT_TARBALL" bin libexec

# Smoke test
./bin/bcftools --version | head -n 2

echo "Built $OUT_TARBALL"

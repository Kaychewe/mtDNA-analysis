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
ZLIB_VERSION=1.3.1
ZLIB_TARBALL="zlib-${ZLIB_VERSION}.tar.gz"
ZLIB_URL="https://zlib.net/${ZLIB_TARBALL}"
ZLIB_SRC="zlib-${ZLIB_VERSION}"
BZIP2_VERSION=1.0.8
BZIP2_TARBALL="bzip2-${BZIP2_VERSION}.tar.gz"
BZIP2_URL="https://sourceware.org/pub/bzip2/${BZIP2_TARBALL}"
BZIP2_SRC="bzip2-${BZIP2_VERSION}"
SRC_DIR="bcftools-1.23"
ROOT_DIR="$PWD"
PREFIX_DIR="$PWD/bcftools_build"
ZLIB_PREFIX="$PWD/zlib_build"
BZIP2_PREFIX="$PWD/bzip2_build"
OUT_TARBALL="bcftools-${VERSION}-linux-x86_64.tar.gz"
MAKE_JOBS="${MAKE_JOBS:-2}"

rm -f "$TARBALL" "$HTSLIB_TARBALL" "$ZLIB_TARBALL" "$BZIP2_TARBALL"
curl -L -o "$TARBALL" "$TARBALL_URL"
curl -L -o "$HTSLIB_TARBALL" "$HTSLIB_URL"
curl -L -o "$ZLIB_TARBALL" "$ZLIB_URL"
curl -L -o "$BZIP2_TARBALL" "$BZIP2_URL"

rm -rf "$SRC_DIR" "$PREFIX_DIR" "$OUT_TARBALL" "$ZLIB_SRC" "$ZLIB_PREFIX" "$BZIP2_SRC" "$BZIP2_PREFIX"
mkdir -p "$PREFIX_DIR"

tar -xjf "$TARBALL"
tar -xjf "$HTSLIB_TARBALL"
tar -xzf "$ZLIB_TARBALL"
tar -xzf "$BZIP2_TARBALL"
rm -rf "$SRC_DIR/htslib"
mv htslib-1.23 "$SRC_DIR/htslib"
cd "$SRC_DIR"

# Build zlib locally to avoid system zlib-dev dependency
cd "$ROOT_DIR/$ZLIB_SRC"
CFLAGS="-fPIC -O3" ./configure --prefix="$ZLIB_PREFIX" --static
make -j "$MAKE_JOBS"
make install
cd "$ROOT_DIR/$SRC_DIR"

# Build bzip2 locally to avoid system libbz2-dev dependency
cd "$ROOT_DIR/$BZIP2_SRC"
make -j "$MAKE_JOBS" CFLAGS="-fPIC -O2 -g -D_FILE_OFFSET_BITS=64"
make install PREFIX="$BZIP2_PREFIX"
cd "$ROOT_DIR/$SRC_DIR"

export CPPFLAGS="-I$ZLIB_PREFIX/include -I$BZIP2_PREFIX/include"
export CFLAGS="${CFLAGS:-} -I$ZLIB_PREFIX/include -I$BZIP2_PREFIX/include"
export LDFLAGS="-L$ZLIB_PREFIX/lib -L$BZIP2_PREFIX/lib"
export LIBS="$ZLIB_PREFIX/lib/libz.a $BZIP2_PREFIX/lib/libbz2.a -llzma -lm"

MAKE_CPPFLAGS="$CPPFLAGS"
MAKE_LDFLAGS="$LDFLAGS"
MAKE_LIBS="$LIBS"

# Build htslib without libcurl and libdeflate to avoid runtime deps in Batch
cd htslib
./configure --disable-libcurl --without-libdeflate
make -j "$MAKE_JOBS" CPPFLAGS="$MAKE_CPPFLAGS" LDFLAGS="$MAKE_LDFLAGS" LIBS="$MAKE_LIBS"
cd ..

# Build bcftools against bundled htslib
make -j "$MAKE_JOBS" HTSDIR=htslib CPPFLAGS="$MAKE_CPPFLAGS" LDFLAGS="$MAKE_LDFLAGS" LIBS="$MAKE_LIBS"
make install prefix="$PREFIX_DIR" CPPFLAGS="$MAKE_CPPFLAGS" LDFLAGS="$MAKE_LDFLAGS" LIBS="$MAKE_LIBS"

cd "$PREFIX_DIR"
# Also include bgzip/tabix from htslib build (source tree)
cp "$ROOT_DIR/$SRC_DIR/htslib/bgzip" "$PREFIX_DIR/bin/"
cp "$ROOT_DIR/$SRC_DIR/htslib/tabix" "$PREFIX_DIR/bin/"

# Do not bundle shared libraries. Use the runtime libs provided by the Batch VM.
# Bundling glibc or other system libs causes GLIBC version conflicts at runtime.
rm -rf "$PREFIX_DIR/lib"

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

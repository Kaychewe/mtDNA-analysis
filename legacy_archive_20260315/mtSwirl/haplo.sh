#!/bin/bash

set -e

workdir="$(mktemp -d)"
cd "$workdir"

wget -q https://github.com/genepi/haplocheck/releases/download/v1.3.3/haplocheck.zip
unzip -q haplocheck.zip

# Print help
java -jar haplocheckCLI.jar --help | head -n 40

# Cleanup (optional)
# cd / && rm -rf "$workdir"

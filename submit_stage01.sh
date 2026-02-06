#!/bin/bash
set -e
# Submit Stage 01 (SubsetBamToChrMAndRevert) to the local Cromwell server.
# Inputs:
# - workflowSource: stage01_subset_bam.wdl
# - workflowInputs: stage01_subset_bam.json
# - workflowDependencies: wdl_deps.zip (if present)

DEPS_ARG=()
if [ -f "wdl_deps.zip" ]; then
  DEPS_ARG=(-F workflowDependencies=@/home/jupyter/workspaces/mtdnaheteroplasmyandaginganalysis/mtDNA-analysis/wdl_deps.zip)
fi

curl -X POST "http://localhost:8094/api/workflows/v1" \
  -H "accept: application/json" \
  -F workflowSource=@/home/jupyter/workspaces/mtdnaheteroplasmyandaginganalysis/mtDNA-analysis/stage01_subset_bam.wdl \
  -F workflowInputs=@/home/jupyter/workspaces/mtdnaheteroplasmyandaginganalysis/mtDNA-analysis/stage01_subset_bam.json \
  "${DEPS_ARG[@]}"

#!/bin/bash
set -e
# Submit Stage 01 (SubsetBamToChrMAndRevert) to the local Cromwell server.
# Inputs:
# - workflowSource: stage01_subset_bam.wdl
# - workflowInputs: stage01_subset_bam.json

curl -X POST "http://localhost:8094/api/workflows/v1" \
  -H "accept: application/json" \
  -F workflowSource=@/home/jupyter/workspaces/mtdnaheteroplasmyandaginganalysis/mtDNA-analysis/stage01_subset_bam.wdl \
  -F workflowInputs=@/home/jupyter/workspaces/mtdnaheteroplasmyandaginganalysis/mtDNA-analysis/stage01_subset_bam.json

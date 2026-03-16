#!/bin/bash
set -e
> batch_submission_ids.txt
> ordered_batch_ids.txt
curl -X POST "http://localhost:8094/api/workflows/v1/batch" -H "accept: application/json" -F workflowSource=@/home/jupyter/workspaces/mtdnaheteroplasmyandaginganalysis/mtDNA-analysis/scatterWrapper_MitoPipeline_v2_5.wdl -F workflowInputs=@/home/jupyter/workspaces/mtdnaheteroplasmyandaginganalysis/mtDNA-analysis/batch_input_allofus.json -F workflowOptions=@/home/jupyter/workspaces/mtdnaheteroplasmyandaginganalysis/mtDNA-analysis/options.json -F workflowDependencies=@/home/jupyter/workspaces/mtdnaheteroplasmyandaginganalysis/mtDNA-analysis/wdl_deps.zip | tee batch_submission_ids.txt
submission_count=$(grep -o 'Submitted' batch_submission_ids.txt | wc -l)
if [ "$submission_count" -ne "$(cat ct_submissions.txt)" ]; then echo "ERROR: submission count is incorrect."; exit 1; fi
cat batch_submission_ids.txt | sed 's/{"id"://g' | sed 's/","status":"Submitted"}//g' | sed 's/"//g' | sed 's/,/\n/g' | sed 's/\[//g' | sed 's/\]//g' > ordered_batch_ids.txt
echo "" >> ordered_batch_ids.txt

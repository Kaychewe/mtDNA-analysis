#!/bin/bash
set -e
output_fold="mtDNA_v25_pilot_5"
success_file_pref="mtDNA_v25_pilot_5_prog_21.39.15"
if [ ! -s "ordered_batch_ids.txt" ]; then
  echo "ERROR: ordered_batch_ids.txt is missing or empty. Run cromwell_submission_script_batch.sh first."
  exit 1
fi
echo "Using batch IDs:"
cat ordered_batch_ids.txt
echo ""
echo "Cromwell status/metadata (per workflow ID):"
while IFS= read -r wf_id; do
  if [ -z "${wf_id}" ]; then
    continue
  fi
  echo "---------------------------------"
  echo "Workflow ID: ${wf_id}"
  echo "Status curl:"
  echo "  curl -s \"http://localhost:8094/api/workflows/v1/${wf_id}/status\""
  curl -s "http://localhost:8094/api/workflows/v1/${wf_id}/status" || true
  echo ""
  echo "Failures curl:"
  echo "  curl -s \"http://localhost:8094/api/workflows/v1/${wf_id}/metadata?includeKey=failures\""
  if command -v jq >/dev/null 2>&1; then
    curl -s "http://localhost:8094/api/workflows/v1/${wf_id}/metadata?includeKey=failures" | jq . || true
  else
    curl -s "http://localhost:8094/api/workflows/v1/${wf_id}/metadata?includeKey=failures" || true
  fi
  echo ""
done < ordered_batch_ids.txt
echo ""
python mtSwirl/generate_mtdna_call_mt/AoU/cromwell_run_monitor.py --run-folder "${output_fold}" --sub-ids ordered_batch_ids.txt --sample-lists "${output_fold}/sample_list{}.txt" --check-success --output "${success_file_pref}"

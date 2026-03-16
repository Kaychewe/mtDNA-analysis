# Simplified AoU mtDNA Pipeline

This directory contains the refactored replacement for the legacy `mtDNA-analysis` pipeline.

## Legacy archive

The previous implementation has been preserved under:

- `legacy_archive_20260315/`

Nothing from that archive is deleted; it is simply moved out of the way so the new pipeline can start from a clean root.

## Refactor goal

The new pipeline keeps the AoU-friendly CRAM/CRAI input model used by `mtSwirl`, but simplifies execution so it behaves more like `MitoHPC`:

- one sample at a time
- one WDL file
- a direct shell-style execution path
- minimal orchestration surface

## Current entry points

- WDL: `wdl/aou_mitohpc_single_sample.wdl`
- One-sample test inputs: `inputs/test_one_sample_aou.json`
- Environment/bootstrap check: `scripts/check_environment.py`
- Cromwell config writer: `scripts/write_cromwell_config.py`
- Cromwell server helper: `scripts/cromwell_server.py`
- Cromwell API helpers: `scripts/cromwell_api.py`
- Submission helper: `scripts/submit_one_sample.py`
- Validation / local run helper: `scripts/validate_and_run_one_sample.sh`
- Single-command test runner: `scripts/run_tests.py`

## Quick preflight

Run these checks before attempting a submission:

```bash
cd /home/kchewe/projects/02.mtDNA/pipelines/mtDNA-analysis

python scripts/run_tests.py
python scripts/check_environment.py
python scripts/write_cromwell_config.py
python scripts/cromwell_server.py status
```

## Run all tests

Use one Python command to run the unit test suite:

```bash
cd /home/kchewe/projects/02.mtDNA/pipelines/mtDNA-analysis
python scripts/run_tests.py
```

This checks the refactor structure, the AoU test inputs, config generation, and the
core Cromwell helper functions without needing a live AoU submission.

## Check commands

### Check the WDL and inputs exist

```bash
ls -lh wdl/aou_mitohpc_single_sample.wdl
ls -lh inputs/test_one_sample_aou.json
```

### Check the AoU metadata file used to derive CRAM/CRAI inputs

```bash
ls -lh /home/kchewe/projects/02.mtDNA/datasets/AoU/metadata/mtdna_mitoclock_aou_dataset_36246309_person_age_gender_crams.tsv
head -n 3 /home/kchewe/projects/02.mtDNA/datasets/AoU/metadata/mtdna_mitoclock_aou_dataset_36246309_person_age_gender_crams.tsv
```

### Check Docker client and daemon

```bash
docker --version
docker info
```

If `docker info` fails, the Docker daemon is not available in the current runtime.

### Check Cromwell config output

```bash
ls -lh config/cromwell.batch.conf
sed -n '1,80p' config/cromwell.batch.conf
```

### Check helper CLIs

```bash
python scripts/run_tests.py
python scripts/submit_one_sample.py --help
python scripts/cromwell_server.py --help
```

## Dry run commands

### Dry run 1: WDL syntax validation

```bash
python scripts/validate_and_run_one_sample.sh
```

This validates the WDL with `womtool` and prints the exact submission command.

### Dry run 2: Environment and config only

```bash
python scripts/run_tests.py
python scripts/check_environment.py
python scripts/write_cromwell_config.py
python scripts/cromwell_server.py status
```

This does not submit a workflow.

### Dry run 3: Submission command preview

```bash
python scripts/submit_one_sample.py --help
```

### Dry run 4: Inspect the one-sample input JSON

```bash
python -m json.tool inputs/test_one_sample_aou.json | sed -n '1,80p'
```

## Design notes

The WDL wraps the `MitoHPC` per-sample method inside a single task and prepares the references explicitly from localized inputs:

- localizes AoU CRAM and CRAI
- localizes the hg38 reference fasta, fai, and dict
- derives `chrM`, circularized mtDNA, rotated mtDNA, and NUMT references
- runs `filter.sh`
- runs `getSummary.sh`
- emits a tarball plus key summary files

This keeps the implementation simple while avoiding the older multi-stage Cromwell choreography.

## AoU configuration layer

The refactor now includes a small AoU-aware configuration layer based on environment
variables such as:

- `WORKSPACE_BUCKET`
- `GOOGLE_PROJECT`
- `PET_SA_EMAIL`
- `PROJECT_ROOT`
- `PORTID`
- `USE_MEM`
- `SQL_DB_NAME`

Typical setup flow:

1. Export the AoU environment variables in your Workbench runtime.
2. Run `python scripts/check_environment.py`
3. Run `python scripts/write_cromwell_config.py`
4. Run `python scripts/cromwell_server.py start`
5. Run `python scripts/submit_one_sample.py --wait`

## Recommended execution sequence

```bash
cd /home/kchewe/projects/02.mtDNA/pipelines/mtDNA-analysis

export WORKSPACE_BUCKET="gs://your-workspace-bucket"
export GOOGLE_PROJECT="your-google-project"
export PET_SA_EMAIL="your-pet-service-account"
export PROJECT_ROOT="/home/jupyter/mtDNA-analysis"
export PORTID=8094
export USE_MEM=32
export SQL_DB_NAME="local_cromwell_run.db"

python scripts/check_environment.py
python scripts/write_cromwell_config.py
python scripts/run_tests.py
python scripts/validate_and_run_one_sample.sh
python scripts/cromwell_server.py start
python scripts/submit_one_sample.py --wait
```

## Notes

- `gsutil` and `gcloud` must be available in the AoU runtime if you want to inspect Batch outputs or fetch task logs from GCS.
- `docker` must be available and the daemon must be running if you want to do local container checks outside Cromwell.
- The current one-sample JSON uses AoU sample `1000000` as the smoke-test sample.

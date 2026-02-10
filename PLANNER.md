# mtDNA Pipeline Planner

Purpose: keep all existing outputs while making the workflow easier to reason about. This document defines inputs, intermediates, and outputs at a high level so we can refactor safely without changing deliverables.

Scope: `scatterWrapper_MitoPipeline_v2_5.wdl` (workflow `MitochondriaPipelineWrapper`) and the merge task `MergeMitoMultiSampleOutputsInternal`. The core per-sample workflow is imported from `mtSwirl/WDL/v2.5_MongoSwirl_Single/fullMitoPipeline_v2_5_Single.wdl`.

## Progress Log (AoU Jupyter)

- Stage 01 (SubsetBamToChrMAndRevert)
  - Success on sample `1000000` using CRAM `gs://fc-aou-datasets-controlled/pooled/wgs/cram/v8_delta/wgs_1000000.cram`.
  - Outputs verified on GCS (proc bam/bai, mean coverage, duplicate metrics).
- Stage 02 (AlignAndCallR1)
  - Success workflow: `d3e371d2-05ab-4412-919b-27f942a6a0f1`.
  - Output roots used to populate Stage 03:
    - FilterContamination: `.../call-FilterContamination/out/1000000.split.vcf`
    - CallNucHCIntegrated: `.../call-CallNucHCIntegrated/out/1000000.nuc.pass.split.vcf`
- Stage 03 (ProduceSelfReferenceFiles)
  - First failure: bcftools bundle shipped glibc/loader -> relocation errors.
  - Second failure: GLIBC version mismatch from bundled shared libs (liblzma/libcurl/etc.).
  - Third failure: Picard ExtractSequences could not find `.fai` next to localized fasta.
  - Fixes in progress:
    - Rebuild bcftools bundle without *any* shared libs in the tarball.
    - Patch `ProduceSelfReferenceFiles_v2_5_Single.wdl` to copy `ref_fasta_index` and `mt_fasta_index` next to localized FASTA before ExtractSequences.
  - Additional findings (Feb 10):
    - `bcftools_docker` from `genomes-in-the-cloud` image does NOT include bcftools (smoketest stderr: `bcftools: command not found`).
    - `quay.io/biocontainers/bcftools:1.17--h3cc50cf_1` failed in Batch (likely blocked/registry pull in VPC-SC); no logs in GCS until delocalization succeeds.
    - GCS logs sometimes missing for failed tasks; need Batch job logs via `gcloud batch jobs describe` and Cloud Logging (`resource.type="batch_task"`).
    - Smoketest WDL + JSON + submit script added to quickly validate candidate docker images before re-running Stage03.

## Current Status (AoU Jupyter)

- Stage02 success: `d3e371d2-05ab-4412-919b-27f942a6a0f1`
- Stage03 failed: `acc1dcf2-4afd-4a2e-8391-492954762a97` (FilterMtVcf stopped before completion)
- bcftools docker smoketests:
  - `f2c39184-6acd-43e4-922f-02cdb9a0933f` (quay bcftools image; no GCS logs, likely blocked pull)
  - `fcc1c004-da4a-4855-9920-d530702fb0e8` (genomes-in-the-cloud image; stderr: `bcftools: command not found`)

## Entry Points

- Batch submission: `cromwell_submission_script_batch.sh`
  - `workflowSource`: `scatterWrapper_MitoPipeline_v2_5.wdl`
  - `workflowInputs`: `batch_input_allofus.json`
  - `workflowOptions`: `options.json`
  - `workflowDependencies`: `wdl_deps.zip`

## Inputs (Workflow-Level)

These are the required/optional inputs declared in `MitochondriaPipelineWrapper`.

Required:
- `wgs_aligned_input_bam_or_cram_list` (File) list of CRAM/BAM paths (one per sample)
- `wgs_aligned_input_bam_or_cram_index_list` (File) list of CRAI/BAI paths (one per sample)
- `sample_name_list` (File) list of sample IDs (one per sample)
- `mt_interval_list` (File)
- `nuc_interval_list` (File)
- `ref_fasta` (File)
- `ref_fasta_index` (File)
- `ref_dict` (File)
- `mt_dict` (File)
- `mt_fasta` (File)
- `mt_fasta_index` (File)
- `blacklisted_sites` (File)
- `blacklisted_sites_index` (File)
- `control_region_shifted_reference_interval_list` (File)
- `non_control_region_interval_list` (File)
- `HailLiftover` (File)
- `FaRenamingScript` (File)
- `CheckVariantBoundsScript` (File)
- `JsonTools` (File)
- `CheckHomOverlapScript` (File)
- `MergePerBatch` (File)
- `force_manual_download` (Boolean)
- `haplocheck_zip` (File)

Optional or with defaults:
- `max_read_length` (Int?)
- `requester_pays_project` (String?)
- `m2_extra_args` (String?)
- `m2_filter_extra_args` (String?)
- `printreads_extra_args` (String?)
- `vaf_filter_threshold` (Float?)
- `f_score_beta` (Float?)
- `verifyBamID` (Float?)
- `compress_output_vcf` (Boolean, default false)
- `compute_numt_coverage` (Boolean, default false)
- `use_haplotype_caller_nucdna` (Boolean, default true)
- `skip_restore_hardclips` (Boolean, default false)
- `haplotype_caller_nucdna_dp_lower_bound` (Int, default 10)
- Docker/version inputs:
  - `gatk_version` (String, default "4.2.6.0")
  - `gatk_override` (File?)
  - `gatk_docker_override` (String?)
  - `ucsc_docker` (String, default public)
  - `gotc_docker` (String, default public)
  - `genomes_cloud_docker` (String, default public bcftools image)
  - `haplochecker_docker` (String, default "eclipse-temurin:17-jdk")
  - `gatk_samtools_docker` (String, default public)
- Runtime knobs:
  - `printreads_mem` (Int?)
  - `lift_coverage_mem` (Int?)
  - `n_cpu_subsetbam` (Int?)
  - `n_cpu_m2_hc_lift` (Int?)
  - `n_cpu_bwa` (Int?)
  - `preemptible_tries` (Int?)

Note: The required input error observed in Cromwell logs referenced `MitochondriaPipelineWrapper.MitochondriaPipeline_v2_5.bcftools_docker` which is not defined in this wrapper. That suggests the imported pipeline expects a docker input not being passed here or in the input JSON. We will resolve this during refactor.

## Intermediates (High-Level)

These are produced within the imported per-sample pipeline and used downstream. We will keep them intact unless explicitly de-scoped.

Per-sample intermediates (arrays in wrapper outputs):
- `subset_bam`, `subset_bai`
- `r1_vcf`, `r1_vcf_index`
- `r1_nuc_vcf`, `r1_nuc_vcf_index`, `r1_nuc_vcf_unfiltered`
- `r1_split_vcf`, `r1_split_vcf_index`
- `self_mt_aligned_bam`, `self_mt_aligned_bai`
- `self_ref_vcf`, `self_ref_vcf_index`, `self_ref_split_vcf`, `self_ref_split_vcf_index`
- `self_base_level_coverage_metrics`
- `self_reference_fasta`
- `reference_to_self_ref_chain`
- `self_control_region_shifted`, `self_non_control_region`
- `liftover_fix_pipeline_log`
- `stats_outputs`
- `input_vcf_for_haplochecker`
- `duplicate_metrics`, `coverage_metrics`, `theoretical_sensitivity_metrics`, `contamination_metrics`

Merge task intermediates:
- `coverage_paths.tsv`, `vcf_paths.tsv`
- temporary `tmp/` directory

## Outputs (Keep Exactly)

Per-sample outputs (arrays):
- Final VCFs and metrics:
  - `final_vcf`, `final_rejected_vcf`, `final_base_level_coverage_metrics`, `numt_base_level_coverage`
- Liftover stats:
  - `success_liftover_variants`, `failed_liftover_variants`, `fixed_liftover_variants`
  - `n_liftover_r2_left_shift`, `n_liftover_r2_injected_from_success`, `n_liftover_r2_ref_insertion_new_haplo`
  - `n_liftover_r2_failed_het_dele_span_insertion_boundary`, `n_liftover_r2_failed_new_dupes_leftshift`
  - `n_liftover_r2_het_ins_sharing_lhs_hom_dele`, `n_liftover_r2_spanning_complex`
  - `n_liftover_r2_spanningfixrhs_sharedlhs`, `n_liftover_r2_spanningfixlhs_upstream`
  - `n_liftover_r2_repaired_success`
- Other stats:
  - `mean_coverage`, `median_coverage`, `major_haplogroup`, `contamination`
  - `nuc_variants_pass`, `n_reads_unpaired_dropped`, `nuc_variants_dropped`
  - `mtdna_consensus_overlaps`, `nuc_consensus_overlaps`

Merged batch outputs (from `MergeMitoMultiSampleOutputsInternal`):
- `batch_analysis_statistics.tsv`
- `batch_merged_mt_coverage.tsv.bgz`
- `batch_merged_mt_calls.vcf.bgz`

## Refactor Strategy (Step-by-Step)

1. Inputs/outputs contract validation
   - Verify that all required inputs used by the imported pipeline are exposed or defaulted in the wrapper and in input JSONs.

2. Separate per-sample pipeline from merging
   - Keep the exact outputs but split the merge step into a distinct workflow to reduce failure coupling.

3. Harden docker inputs and defaults
   - Align docker input names between wrapper and imported workflow (e.g., `bcftools_docker` vs `genomes_cloud_docker`).

4. Add minimal validation
   - Pre-flight checks for missing input keys before submission.

This planner will be updated as we refactor.

## Stage Roadmap (Stage03+)

**Stage03 ProduceSelfReferenceFiles**
- WDL: `stage03_self_reference.wdl` (new)
- Inputs: Stage02 outputs (`out_vcf`, `split_vcf`, `nuc_vcf`, `input_vcf_for_haplochecker`), references (`ref_fasta`, `ref_dict`, `mt_fasta`, `mt_dict`), intervals, blacklist, `haplocheck.zip`.
- Outputs: `self_reference_fasta`, `reference_to_self_ref_chain`, `self_control_region_shifted`, `self_non_control_region`, `self_ref_vcf` + index, `self_ref_split_vcf` + index, `liftover_fix_pipeline_log`.
- Diagnostics: confirm Stage02 outputs exist on GCS, validate required reference inputs, verify haplocheck zip exists in workspace bucket.
- Docker/tooling validation: run `stage03_bcftools_smoketest.wdl` against candidate image; require `bcftools/bgzip/tabix --version` to succeed before Stage03 submit.

**Stage04 AlignAndCallR2**
- WDL: `stage04_align_call_r2.wdl` (new)
- Inputs: Stage03 self-reference outputs, Stage01 subset bam/bai, intervals (self control/non-control), references, blacklist.
- Outputs: `self_mt_aligned_bam` + bai, `self_ref_vcf` + index, `self_ref_split_vcf` + index, R2 stats/metrics.
- Diagnostics: confirm self-reference files exist, confirm GATK docker available.

**Stage05 Liftover**
- WDL: `stage05_liftover.wdl` (new)
- Inputs: Stage04 VCFs, `reference_to_self_ref_chain`, reference/mt dicts, `HailLiftover`, `CheckVariantBoundsScript`, `CheckHomOverlapScript`.
- Outputs: `final_vcf`, `final_rejected_vcf`, liftover stats counters, `nuc_variants_pass`.
- Diagnostics: confirm HailLiftover jar and scripts exist, confirm bcftools bundle availability if required by liftover steps.

**Stage06 Merge**
- WDL: `stage06_merge.wdl` (new)
- Inputs: per-sample final outputs, `MergePerBatch`, `coverage_paths.tsv`, `vcf_paths.tsv`.
- Outputs: `batch_merged_mt_coverage.tsv.bgz`, `batch_merged_mt_calls.vcf.bgz`, `batch_analysis_statistics.tsv`.
- Diagnostics: confirm bgzip/tabix availability (bcftools bundle), confirm paths files are populated.

**Stage Scripts and Reuse**
- For each stage: add `populate_stageXX_from_stageYY.sh`, `submit_stageXX.sh`, and `diagnose_stageXX.sh`.
- Add `--reuse-stageXX <workflow_id>` flags to `main_workflow.sh` so later stages can run without re-submitting earlier stages.

## Tooling/Docker Comparison (mtDNA vs long-read-pipelines 4.0.9)

Goal: identify stable, current container sources and align the mtDNA workflow to a maintained image set without changing outputs.

### mtDNA (current)

Primary images referenced by `scatterWrapper_MitoPipeline_v2_5.wdl` and the imported v2.5 pipeline:
- `ucsc_docker`: `quay.io/biocontainers/ucsc-bedgraphtobigwig:377--h73cb82a_3`
- `gotc_docker`: `us.gcr.io/broad-gotc-prod/genomes-in-the-cloud:2.4.2-1552931386`
- `genomes_cloud_docker`: `quay.io/biocontainers/bcftools:1.17--h3cc50cf_1`
- `haplochecker_docker`: `eclipse-temurin:17-jdk`
- `gatk_samtools_docker`: `docker.io/broadinstitute/gatk:4.2.6.0`

Additional image expectations found elsewhere in this repo:
- `bcftools_docker` appears in v2.5 single pipeline inputs and in `portable_inputs_template.json`, but it is not defined in the wrapper inputs. This mismatch triggers the “Required workflow input … bcftools_docker not specified” error.
- `MongoProduceSelfReference_diagnostics.wdl` uses older/legacy images:
  - `docker.io/rahulg603/genomes_cloud_bcftools`
  - `us.gcr.io/broad-dsp-lrma/lr-basic:0.1.1`

### long-read-pipelines 4.0.9 (reference for modern tooling)

Observed patterns:
- Centralized, versioned images under `us.gcr.io/broad-dsp-lrma/*`
- WDL tasks typically use a `default_attr.docker` and allow overrides via runtime attributes.
- The repository includes `docker/` with Dockerfiles + Makefiles, and `scripts/collect_docker_in_system.sh` to audit image usage and versions.

Representative images in active tasks:
- `us.gcr.io/broad-dsp-lrma/lr-align:0.1.28`
- `us.gcr.io/broad-dsp-lrma/lr-sniffles2:2.0.6`
- `us.gcr.io/broad-dsp-lrma/lr-hifiasm:0.16.1`
- `us.gcr.io/broad-dsp-lrma/lr-nanoplot:1.40.0-1`
- `us.gcr.io/broad-gatk/gatk:4.2.0.0` (utility tasks)
- `ghcr.io/dnanexus-rnd/glnexus:v1.4.1` (variant utils)

### Transition Targets (draft mapping)

The goal is not to replace algorithms, but to consolidate and stabilize image sources.

Candidates for alignment:
- `bcftools`:
  - mtDNA: do not use `bcftools_docker`. Use the verified bcftools bundle from GCS and localize in task commands.
  - long-read: not a single canonical image, but utilities rely on `bcftools` in WDL tasks; consider a dedicated `broad-dsp-lrma` style image or an internal Artifact Registry image.
- `gatk` / `samtools`:
  - mtDNA: `docker.io/broadinstitute/gatk:4.2.6.0`
  - long-read: `us.gcr.io/broad-gatk/gatk:4.2.0.0` and `broadinstitute/gatk:4.2.6.1` in some tasks
- `ucsc` tools:
  - mtDNA: `quay.io/biocontainers/ucsc-bedgraphtobigwig:377--h73cb82a_3`
  - long-read: not a direct match; may be replaced by a custom internal image if needed
- `haplochecker`:
  - mtDNA: `eclipse-temurin:17-jdk` (base only; tools likely installed at runtime)
  - long-read: no direct haplochecker image; may require building a dedicated image in a controlled registry

### Next Steps (no code changes yet)

1. Inventory actual docker usage from mtDNA v2.5 and v2.6 pipelines.
2. Run or replicate `long-read-pipelines` docker audit logic to build a canonical list of images + versions.
3. Define a small, explicit image set for mtDNA and update wrapper inputs to pass required docker parameters consistently.

### Latest Probe Results (2026-02-05, WF: 6be95521-0af4-49c3-9f3a-3aca0d761519)

Probed images (safe list):
- `us.gcr.io/broad-gotc-prod/genomes-in-the-cloud:2.4.2-1552931386`
  - Present: `samtools 1.3.1`, `java 8`, `python 2.7.9`, `python3 3.4.2`, `R 3.1.1`, `bash`
  - Missing: `bcftools`, `gatk`, `bgzip`, `tabix`, `bedGraphToBigWig`
- `eclipse-temurin:17-jdk`
  - Present: `java 17`, `bash`
  - Missing: `bcftools`, `samtools`, `gatk`, `python`, `python3`, `R`, `bgzip`, `tabix`, `bedGraphToBigWig`
- `docker.io/broadinstitute/gatk:4.2.6.0`
  - Present: `gatk 4.2.6.0`, `samtools 1.7`, `java 8`, `python 3.6.10`, `R 3.6.2`, `bgzip`, `tabix`
  - Missing: `bcftools`, `bedGraphToBigWig`
- `us.gcr.io/broad-dsp-lrma/lr-basic:0.1.1`
  - Present: `samtools 1.13`, `bgzip`, `tabix`, `python3 3.6.9`
  - Missing: `bcftools`, `gatk`, `java`, `python`, `R`, `bedGraphToBigWig`
- `us.gcr.io/broad-dsp-lrma/lr-basic:latest`
  - Present: `samtools 1.22.1`
  - Missing: `bcftools`, `gatk`, `java` (not in probe), plus other tools depending on task

Skipped images (policy):
- `quay.io/biocontainers/ucsc-bedgraphtobigwig:377--h73cb82a_3`
- `quay.io/biocontainers/bcftools:1.17--h3cc50cf_1`

Key finding:
- None of the probed “safe” images include `bcftools`. A dedicated bcftools image (or adding bcftools into an approved internal image) is required for robust mtDNA operation.
  - Decision: prefer the validated bcftools bundle in GCS over `bcftools_docker`.

## Progress Log

2026-02-06
- Cromwell 91 restarted successfully; batch backend online.
- Local bcftools bundle rebuilt with `bin/bcftools`, `bin/bgzip`, `bin/tabix` packaged (`bcftools_build/bcftools-1.23-linux-x86_64.tar.gz`).
- Bundle uploaded to `gs://fc-secure-76d68a64-00aa-40a7-b2c5-ca956db2719b/tools/bcftools/bcftools-1.23-linux-x86_64.tar.gz`.
- Submitted bcftools binary test workflows: `f5a7fa42-fab8-4abd-9031-dfd9685013de`, `84b12760-ccac-4b31-90df-02e75ad5b904`.
- Latest report (`84b12760-ccac-4b31-90df-02e75ad5b904`) succeeded: `bcftools`, `bgzip`, `tabix` run correctly using bundled `lib/` via `LD_LIBRARY_PATH`.

## Progress Log

- 2026-02-05: Created diagnostic workflows to probe docker images safely (safe-first strategy).
- 2026-02-05: Ran safe-first probe workflow; confirmed safe images lack `bcftools`, `bgzip`, `tabix` in most images.
- 2026-02-05: Added `us.gcr.io/broad-dsp-lrma/lr-basic:latest` to probes; still no `bcftools` found.
- 2026-02-06: Built `bcftools 1.23` locally in AoU workspace with bundled `htslib` and disabled libcurl.
- 2026-02-06: Packaged bundle with `bcftools`, `bgzip`, `tabix` and uploaded to `$WORKSPACE_BUCKET/tools/bcftools/`.
- 2026-02-06: Re-ran WDL binary test (latest workflow ID to verify bundle on Batch); report fetch pending review.

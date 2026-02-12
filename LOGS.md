# Logs

## 2026-02-12 — Stage 01 (SubsetBamToChrMAndRevert) Succeeded

- Workflow ID: `8007c386-d22d-4496-a072-d66070baa17d`
- Sample: `1000000`
- Status: `Succeeded`

### Tooling
- Docker image: `kchewe/mtdna-stage04:0.1.3`
- Software used inside task:
  - GATK 4.2.6.0 (PrintReads, ValidateSamFile, FilterSamReads, RevertSam, CollectWgsMetrics, MarkDuplicates, SortSam)
  - R (used to compute mean/median coverage from WGS metrics)

### Inputs
- CRAM: `gs://fc-aou-datasets-controlled/pooled/wgs/cram/v8_delta/wgs_1000000.cram`
- CRAI: `gs://fc-aou-datasets-controlled/pooled/wgs/cram/v8_delta/wgs_1000000.cram.crai`
- Sample name: `1000000`
- mt interval list: `gs://gcp-public-data--broad-references/hg38/v0/chrM/chrM.hg38.interval_list`
- NUMT interval list: `gs://fc-secure-76d68a64-00aa-40a7-b2c5-ca956db2719b/intervals/NUMTv3_all385.hg38.interval_list`
- Reference fasta: `gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.fasta`
- Reference fasta index: `gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.fasta.fai`
- Reference dict: `gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.dict`
- Requester pays project: `terra-vpc-sc-17dda7e1`
- force_manual_download: `false`
- max_read_length: `151`

### Outputs (GCS)
- `out/1000000.proc.bam`
- `out/1000000.proc.bai`
- `out/1000000.unmap.bam`
- `out/1000000.duplicate.metrics`
- `out/1000000.mean_coverage.txt`
- `out/1000000.ct_failed.txt`

### Stage 01 Purpose (simple, non-technical)
Stage 01 takes a huge genome file and keeps only the mitochondrial parts we care about. It cleans that smaller file and records basic quality numbers so the next stages can run faster and more reliably.

## 2026-02-12 — Stage 02 (AlignAndCallR1) Succeeded

- Workflow ID: `6a071b3f-8da6-4b8a-85d2-df9915984985`
- Sample: `1000000`
- Status: `Succeeded`

### Tooling
- Docker image (GATK tasks): `kchewe/mtdna-stage04:0.1.3`
- Docker image (haplocheck): `eclipse-temurin:17-jdk`
- Software used inside tasks:
  - GATK 4.2.6.0 (Mutect2, FilterMutectCalls, other GATK utilities)
  - Haplocheck (runs from `haplocheck.zip`)

### Inputs
- Input BAM: Stage01 `1000000.proc.bam` (from workflow `8007c386-d22d-4496-a072-d66070baa17d`)
- Input BAI: Stage01 `1000000.proc.bai`
- Sample name: `1000000`
- Reference fasta: `gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.fasta`
- Reference fasta index: `gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.fasta.fai`
- Reference dict: `gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.dict`
- mt fasta: `gs://gcp-public-data--broad-references/hg38/v0/chrM/Homo_sapiens_assembly38.chrM.fasta`
- mt fasta index: `gs://gcp-public-data--broad-references/hg38/v0/chrM/Homo_sapiens_assembly38.chrM.fasta.fai`
- mt dict: `gs://gcp-public-data--broad-references/hg38/v0/chrM/Homo_sapiens_assembly38.chrM.dict`
- mt interval list: `gs://gcp-public-data--broad-references/hg38/v0/chrM/chrM.hg38.interval_list`
- nuc interval list: `gs://fc-secure-76d68a64-00aa-40a7-b2c5-ca956db2719b/intervals/NUMTv3_all385.hg38.interval_list`
- blacklist sites: `gs://gcp-public-data--broad-references/hg38/v0/chrM/blacklist_sites.hg38.chrM.bed`
- blacklist sites index: `gs://gcp-public-data--broad-references/hg38/v0/chrM/blacklist_sites.hg38.chrM.bed.idx`
- haplocheck zip: `gs://fc-secure-76d68a64-00aa-40a7-b2c5-ca956db2719b/haplocheck.zip`

### Outputs (Cromwell)
- `out_vcf` + index
- `split_vcf` + index
- `nuc_vcf` + index
- `nuc_vcf_unfiltered`
- `split_nuc_vcf` + index
- `input_vcf_for_haplochecker`
- `contamination_metrics`
- `major_haplogroup`, `contamination`, `contamination_major`, `contamination_minor`, `nuc_variants_pass`

### Stage 02 Purpose (simple, non-technical)
Stage 02 takes the cleaned mitochondrial reads from Stage 01, calls variants, and produces the main VCFs plus basic contamination/haplogroup summaries for the sample.

## 2026-02-12 — Stage 03 (ProduceSelfReferenceFiles) Succeeded

- Workflow ID: `c0ac2938-85df-481d-bb5d-8b42b6d6a0e3`
- Sample: `1000000`
- Status: `Succeeded`

### Call Root
- `gs://fc-secure-76d68a64-00aa-40a7-b2c5-ca956db2719b/workflows/cromwell-executions/StageProduceSelfReferenceFiles/c0ac2938-85df-481d-bb5d-8b42b6d6a0e3/call-ProduceSelfReferenceFiles/ProduceSelfReferenceFiles/bec4112e-6567-4e86-bdbe-fb8186687a08/`

### Outputs (GCS, selected)
- `call-ChainSwapLiftoverBed/out/1000000_to_reference.chain`
- `call-ChainSwapLiftoverBed/out/blacklist_sites.hg38.chrM.1000000.liftedOver.bed` + `.idx`
- `call-FinalizeMtFasta/out/1000000.self.ref.fasta` + `.fai` + `.dict`
- `call-FinalizeNucFastas/out/1000000NucOnly.self.ref.fasta` + `.fai` + `.dict`
- `call-FinalizeNucFastas/out/1000000andNuc.self.ref.fasta` + `.fai` + `.dict`
- `call-ForceCallVcfs/out/1000000.self.ref.reversed.selfRef.homoplasmies.vcf.bgz` + `.tbi`
- `call-ForceCallVcfs/out/1000000.self.ref.reversed.withfilters.selfRef.homoplasmies.vcf.bgz` + `.tbi`
- `call-ForceCallVcfs/out/1000000.self.ref.reversed.selfRef.shifted.homoplasmies.vcf.bgz` + `.tbi`
- `call-LiftIntervals/out/chrM.hg38.1000000.SelfRefLiftover.interval_list`
- `call-LiftIntervals/out/control_region_shifted.chrM.1000000.SelfRefLiftover.interval_list`
- `call-LiftIntervals/out/non_control_region.chrM.1000000.SelfRefLiftover.interval_list`
- `call-MtConsensus/out/reference_to_1000000.chain`
- `call-NucConsensus/out/reference_to_1000000NucOnly.chain`
- `call-ShiftMtReference/out/1000000.self.ref.shifted_by_8000_bases.fasta` + `.fai` + `.dict`
- `call-ShiftMtReference/out/1000000.self.ref.shifted_by_8000_bases.shift_back_8000_bases.chain`
- `call-ShiftMtReference/out/1000000.self.ref.shifted_by_8000_bases.shift_fwd_8000_bases.chain`

### Stage 03 Purpose (simple, non-technical)
Stage 03 builds a personalized mitochondrial reference for the sample and prepares the key reference files and variant calls needed for the next alignment and liftover steps.

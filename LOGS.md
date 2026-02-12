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

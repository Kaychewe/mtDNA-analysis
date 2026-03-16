version 1.0

import "mtSwirl/WDL/v2.5_MongoSwirl_Single/MongoTasks_v2_5_Single.wdl" as MongoTasks

workflow StageSubsetBamToChrMAndRevert {
  meta {
    description: "Stage 1: subset WGS BAM/CRAM to chrM/NUMT and revert/mark duplicates."
  }

  input {
    File wgs_aligned_input_bam_or_cram
    File? wgs_aligned_input_bam_or_cram_index
    String sample_name

    File mt_interval_list
    File nuc_interval_list
    File ref_fasta
    File ref_fasta_index
    File ref_dict

    Boolean force_manual_download
    String? requester_pays_project
    Int? max_read_length
    Boolean skip_restore_hardclips = false
    String? printreads_extra_args

    # GATK runtime + image
    String gatk_version = "4.2.6.0"
    File? gatk_override
    String? gatk_samtools_docker

    # Optional runtime knobs
    Int? printreads_mem
    Int? n_cpu_subsetbam
    Int? preemptible_tries
  }

  call MongoTasks.MongoSubsetBamToChrMAndRevert as SubsetBamToChrMAndRevert {
    input:
      input_bam = wgs_aligned_input_bam_or_cram,
      input_bai = wgs_aligned_input_bam_or_cram_index,
      sample_name = sample_name,
      mt_interval_list = mt_interval_list,
      nuc_interval_list = nuc_interval_list,
      ref_fasta = ref_fasta,
      ref_fasta_index = ref_fasta_index,
      ref_dict = ref_dict,
      requester_pays_project = requester_pays_project,
      gatk_override = gatk_override,
      gatk_docker_override = gatk_samtools_docker,
      gatk_version = gatk_version,
      printreads_extra_args = printreads_extra_args,
      force_manual_download = force_manual_download,
      read_length = max_read_length,
      skip_restore_hardclips = skip_restore_hardclips,
      coverage_cap = 100000,
      mem = printreads_mem,
      n_cpu = n_cpu_subsetbam,
      preemptible_tries = preemptible_tries
  }

  output {
    File output_bam = SubsetBamToChrMAndRevert.output_bam
    File output_bai = SubsetBamToChrMAndRevert.output_bai
    File unmapped_bam = SubsetBamToChrMAndRevert.unmapped_bam
    File duplicate_metrics = SubsetBamToChrMAndRevert.duplicate_metrics
    Int reads_dropped = SubsetBamToChrMAndRevert.reads_dropped
    Int mean_coverage = SubsetBamToChrMAndRevert.mean_coverage
  }
}

version 1.0

import "mtSwirl/WDL/v2.5_MongoSwirl_Single/MongoTasks_v2_5_Single.wdl" as MongoTasks_Single

workflow StageLiftover {
  meta {
    description: "Stage 5: liftover R2 calls back to reference and collect final outputs."
  }

  input {
    String sample_name
    String self_suffix = ".self.ref"

    # Stage03 outputs
    File ref_homoplasmies_vcf
    File force_call_vcf_filters

    File mt_self
    File mt_self_index
    File mt_self_dict
    File mt_self_shifted
    File mt_self_shifted_index
    File mt_self_shifted_dict
    File chain_self_to_ref
    File chain_ref_to_self

    File self_control_region_shifted_reference_interval_list
    File self_non_control_region_interval_list

    # Stage04 outputs
    File new_self_ref_vcf

    File input_bam_regular_ref
    File input_bam_regular_ref_index
    File input_bam_shifted_ref
    File input_bam_shifted_ref_index

    # Reference resources
    File ref_fasta
    File ref_fasta_index
    File ref_dict
    File HailLiftover

    # Stage02/01 outputs for stats
    String major_haplogroup
    Float contamination
    Int nuc_variants_pass
    Int n_reads_unpaired_dropped

    # Stage03 stats
    Int nuc_variants_dropped
    Int mtdna_consensus_overlaps
    Int nuc_consensus_overlaps

    # Stage04 stats
    Int mean_coverage
    Float median_coverage

    # Tools
    String genomes_cloud_docker
    String ucsc_docker
    File? ucsc_tools_bundle

    Int? preemptible_tries
    Int? n_cpu
  }

  call MongoTasks_Single.MongoLiftoverVCFAndGetCoverage as LiftOverAfterSelf {
    input:
      sample_name = sample_name,
      original_filtered_vcf = ref_homoplasmies_vcf,
      new_self_ref_vcf = new_self_ref_vcf,
      reversed_hom_ref_vcf = force_call_vcf_filters,

      mt_self = mt_self,
      mt_self_index = mt_self_index,
      mt_self_dict = mt_self_dict,
      mt_self_shifted = mt_self_shifted,
      mt_self_shifted_index = mt_self_shifted_index,
      mt_self_shifted_dict = mt_self_shifted_dict,
      chain_self_to_ref = chain_self_to_ref,
      chain_ref_to_self = chain_ref_to_self,

      input_bam_regular_ref = input_bam_regular_ref,
      input_bam_regular_ref_index = input_bam_regular_ref_index,
      input_bam_shifted_ref = input_bam_shifted_ref,
      input_bam_shifted_ref_index = input_bam_shifted_ref_index,
      self_control_region_shifted_reference_interval_list = self_control_region_shifted_reference_interval_list,
      self_non_control_region_interval_list = self_non_control_region_interval_list,

      ref_fasta = ref_fasta,
      ref_fasta_index = ref_fasta_index,
      ref_dict = ref_dict,
      HailLiftover = HailLiftover,
      self_suffix = self_suffix,

      n_cpu = n_cpu,
      genomes_cloud_docker = genomes_cloud_docker,
      preemptible_tries = preemptible_tries
  }

  call MongoTasks_Single.MongoLiftoverSelfAndCollectOutputs as LiftoverSelfCoverage {
    input:
      sample_name = sample_name,
      self_ref_table = LiftOverAfterSelf.self_coverage_table,
      chain = chain_self_to_ref,
      homoplasmic_deletions_coverage = LiftOverAfterSelf.gap_coverage,

      liftover_table = LiftOverAfterSelf.liftoverStats,
      mean_coverage = mean_coverage,
      median_coverage = median_coverage,
      major_haplogroup = major_haplogroup,
      contamination = contamination,
      nuc_variants_pass = nuc_variants_pass,
      n_reads_unpaired_dropped = n_reads_unpaired_dropped,
      nuc_variants_dropped = nuc_variants_dropped,
      mtdna_consensus_overlaps = mtdna_consensus_overlaps,
      nuc_consensus_overlaps = nuc_consensus_overlaps,
      ucsc_docker = ucsc_docker,
      ucsc_tools_bundle = ucsc_tools_bundle,
      preemptible_tries = preemptible_tries
  }

  output {
    File final_vcf = LiftOverAfterSelf.liftover_r2_final_vcf
    File final_rejected_vcf = LiftOverAfterSelf.liftover_r2_rejected_vcf
    File liftover_fix_pipeline_log = LiftOverAfterSelf.liftover_r2_log

    File self_base_level_coverage_metrics = LiftOverAfterSelf.self_coverage_table
    File final_base_level_coverage_metrics = LiftoverSelfCoverage.reference_coverage
    File stats_outputs = LiftoverSelfCoverage.table

    Int success_liftover_variants = LiftOverAfterSelf.n_liftover_r2_pass
    Int failed_liftover_variants = LiftOverAfterSelf.n_liftover_r2_failed
    Int fixed_liftover_variants = LiftOverAfterSelf.n_liftover_r2_fixed
    Int n_liftover_r2_left_shift = LiftOverAfterSelf.n_liftover_r2_left_shift
    Int n_liftover_r2_injected_from_success = LiftOverAfterSelf.n_liftover_r2_injected_from_success
    Int n_liftover_r2_ref_insertion_new_haplo = LiftOverAfterSelf.n_liftover_r2_ref_insertion_new_haplo
    Int n_liftover_r2_failed_het_dele_span_insertion_boundary = LiftOverAfterSelf.n_liftover_r2_failed_het_dele_span_insertion_boundary
    Int n_liftover_r2_failed_new_dupes_leftshift = LiftOverAfterSelf.n_liftover_r2_failed_new_dupes_leftshift
    Int n_liftover_r2_het_ins_sharing_lhs_hom_dele = LiftOverAfterSelf.n_liftover_r2_het_ins_sharing_lhs_hom_dele
    Int n_liftover_r2_spanning_complex = LiftOverAfterSelf.n_liftover_r2_spanning_complex
    Int n_liftover_r2_spanningfixrhs_sharedlhs = LiftOverAfterSelf.n_liftover_r2_spanningfixrhs_sharedlhs
    Int n_liftover_r2_spanningfixlhs_upstream = LiftOverAfterSelf.n_liftover_r2_spanningfixlhs_upstream
    Int n_liftover_r2_repaired_success = LiftOverAfterSelf.n_liftover_r2_repaired_success
  }
}

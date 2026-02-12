version 1.0

import "mtSwirl/WDL/v2.5_MongoSwirl_Single/MongoTasks_v2_5_Single.wdl" as MongoTasks_Single

workflow Stage05LiftoverSmokeTest {
  meta {
    description: "Stage 05 smoketest: run LiftOverAfterSelf only (MongoLiftoverVCFAndGetCoverage)."
  }

  input {
    String sample_name
    String self_suffix = ".self.ref"

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

    File new_self_ref_vcf

    File input_bam_regular_ref
    File input_bam_regular_ref_index
    File input_bam_shifted_ref
    File input_bam_shifted_ref_index

    File ref_fasta
    File ref_fasta_index
    File ref_dict
    File HailLiftover

    String genomes_cloud_docker
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

      genomes_cloud_docker = genomes_cloud_docker,
      n_cpu = n_cpu,
      preemptible_tries = preemptible_tries
  }

  output {
    File liftover_r2_final_vcf = LiftOverAfterSelf.liftover_r2_final_vcf
    File liftover_r2_log = LiftOverAfterSelf.liftover_r2_log
    File liftover_isec_summary = LiftOverAfterSelf.liftover_isec_summary
    File liftover_private_to_rev_hom_ref_head = LiftOverAfterSelf.liftover_private_to_rev_hom_ref_head
    File self_coverage_table = LiftOverAfterSelf.self_coverage_table
    File liftover_stats = LiftOverAfterSelf.liftoverStats
  }
}

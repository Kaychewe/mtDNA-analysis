version 1.0

import "mtSwirl/WDL/v2.5_MongoSwirl_Single/MongoTasks_v2_5_Single.wdl" as MongoTasks_Single

workflow MongoProduceSelfReferenceTest {
  input {
    String sample_name
    File input_nuc_vcf
    File input_mt_vcf

    String suffix = ".self.ref"
    File ref_fasta
    File ref_fasta_index
    File nuc_interval_list
    File mt_ref_fasta
    File mt_ref_fasta_index
    File mt_interval_list
    File non_control_region_interval_list

    File fa_renaming_script
    File variant_bounds_script
    File check_hom_overlap_script
    Int? preemptible_tries

    Int n_shift = 8000
    String genomes_cloud_docker = "docker.io/rahulg603/genomes_cloud_bcftools"
    String intertext = ""
  }

  call MongoTasks_Single.MongoProduceSelfReference as ProduceSelfReference {
    input:
      sample_name = sample_name,
      input_nuc_vcf = input_nuc_vcf,
      input_mt_vcf = input_mt_vcf,
      suffix = suffix,
      ref_fasta = ref_fasta,
      ref_fasta_index = ref_fasta_index,
      nuc_interval_list = nuc_interval_list,
      mt_ref_fasta = mt_ref_fasta,
      mt_ref_fasta_index = mt_ref_fasta_index,
      mt_interval_list = mt_interval_list,
      non_control_region_interval_list = non_control_region_interval_list,
      fa_renaming_script = fa_renaming_script,
      variant_bounds_script = variant_bounds_script,
      check_hom_overlap_script = check_hom_overlap_script,
      preemptible_tries = preemptible_tries,
      n_shift = n_shift,
      genomes_cloud_docker = genomes_cloud_docker,
      intertext = intertext
  }

  output {
    File mt_self = ProduceSelfReference.self_fasta
    File mt_self_index = ProduceSelfReference.self_fasta_index
    File mt_self_dict = ProduceSelfReference.self_dict
    File mt_and_nuc_self = ProduceSelfReference.self_cat_fasta
    File mt_and_nuc_self_index = ProduceSelfReference.self_cat_fasta_index
    File mt_and_nuc_self_dict = ProduceSelfReference.self_cat_dict
    File shifted_self = ProduceSelfReference.self_shifted_fasta
    File shifted_self_index = ProduceSelfReference.self_shifted_fasta_index
    File shifted_self_dict = ProduceSelfReference.self_shifted_dict
    File lifted_mt_intervals = ProduceSelfReference.lifted_mt_intervals
    File lifted_noncontrol_intervals = ProduceSelfReference.lifted_noncontrol_intervals
    File lifted_control_intervals = ProduceSelfReference.lifted_control_intervals
    Int nuc_variants_dropped = ProduceSelfReference.nuc_variants_dropped
    Int mtdna_consensus_overlaps = ProduceSelfReference.mtdna_consensus_overlaps
    Int nuc_consensus_overlaps = ProduceSelfReference.nuc_consensus_overlaps
  }
}

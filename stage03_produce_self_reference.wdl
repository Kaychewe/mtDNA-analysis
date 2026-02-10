version 1.0

import "mtSwirl/WDL/v2.5_MongoSwirl_Single/ProduceSelfReferenceFiles_v2_5_Single.wdl" as ProduceSelfReferenceFiles_Single

workflow StageProduceSelfReferenceFiles {
  meta {
    description: "Stage 3: produce self-reference files from Stage 02 outputs."
  }

  input {
    String sample_name
    String suffix = ".self.ref"

    File mt_dict
    File mt_fasta
    File mt_fasta_index
    File mt_interval_list
    File non_control_region_interval_list

    File ref_dict
    File ref_fasta
    File ref_fasta_index
    File nuc_interval_list
    String reference_name = "reference"

    File blacklisted_sites
    File blacklisted_sites_index

    Int n_shift = 8000

    File nuc_variants
    File mtdna_variants

    Boolean compute_numt_coverage = false
    File FaRenamingScript
    File CheckVariantBoundsScript
    File CheckHomOverlapScript

    Int? preemptible_tries
    String genomes_cloud_docker
    String bcftools_docker = "us.gcr.io/broad-dsp-lrma/lr-basic:latest"
    String gotc_docker
    String ucsc_docker
  }

  call ProduceSelfReferenceFiles_Single.ProduceSelfReferenceFiles as ProduceSelfReferenceFiles {
    input:
      sample_name = sample_name,
      suffix = suffix,
      mt_dict = mt_dict,
      mt_fasta = mt_fasta,
      mt_fasta_index = mt_fasta_index,
      mt_interval_list = mt_interval_list,
      non_control_region_interval_list = non_control_region_interval_list,
      ref_dict = ref_dict,
      ref_fasta = ref_fasta,
      ref_fasta_index = ref_fasta_index,
      nuc_interval_list = nuc_interval_list,
      reference_name = reference_name,
      blacklisted_sites = blacklisted_sites,
      blacklisted_sites_index = blacklisted_sites_index,
      n_shift = n_shift,
      nuc_variants = nuc_variants,
      mtdna_variants = mtdna_variants,
      compute_numt_coverage = compute_numt_coverage,
      FaRenamingScript = FaRenamingScript,
      CheckVariantBoundsScript = CheckVariantBoundsScript,
      CheckHomOverlapScript = CheckHomOverlapScript,
      genomes_cloud_docker = genomes_cloud_docker,
      bcftools_docker = bcftools_docker,
      gotc_docker = gotc_docker,
      ucsc_docker = ucsc_docker,
      preemptible_tries = preemptible_tries
  }

  output {
    File mt_self = ProduceSelfReferenceFiles.mt_self
    File mt_self_index = ProduceSelfReferenceFiles.mt_self_index
    File mt_self_dict = ProduceSelfReferenceFiles.mt_self_dict

    File mt_shifted_self = ProduceSelfReferenceFiles.mt_shifted_self
    File mt_shifted_self_index = ProduceSelfReferenceFiles.mt_shifted_self_index
    File mt_shifted_self_dict = ProduceSelfReferenceFiles.mt_shifted_self_dict

    File ref_to_self_chain = ProduceSelfReferenceFiles.ref_to_self_chain
    File self_to_ref_chain = ProduceSelfReferenceFiles.self_to_ref_chain
    File self_shift_back_chain = ProduceSelfReferenceFiles.self_shift_back_chain
    File? nuc_self_to_ref_chain = ProduceSelfReferenceFiles.nuc_self_to_ref_chain

    File mt_andNuc_self = ProduceSelfReferenceFiles.mt_andNuc_self
    File mt_andNuc_self_index = ProduceSelfReferenceFiles.mt_andNuc_self_index
    File mt_andNuc_self_dict = ProduceSelfReferenceFiles.mt_andNuc_self_dict

    File mt_andNuc_shifted_self = ProduceSelfReferenceFiles.mt_andNuc_shifted_self
    File mt_andNuc_shifted_self_index = ProduceSelfReferenceFiles.mt_andNuc_shifted_self_index
    File mt_andNuc_shifted_self_dict = ProduceSelfReferenceFiles.mt_andNuc_shifted_self_dict

    File ref_homoplasmies_vcf = ProduceSelfReferenceFiles.ref_homoplasmies_vcf
    File force_call_vcf = ProduceSelfReferenceFiles.force_call_vcf
    File force_call_vcf_idx = ProduceSelfReferenceFiles.force_call_vcf_idx
    File force_call_vcf_filters = ProduceSelfReferenceFiles.force_call_vcf_filters
    File force_call_vcf_filters_idx = ProduceSelfReferenceFiles.force_call_vcf_filters_idx
    File force_call_vcf_shifted = ProduceSelfReferenceFiles.force_call_vcf_shifted
    File force_call_vcf_shifted_idx = ProduceSelfReferenceFiles.force_call_vcf_shifted_idx

    File mt_interval_list_self = ProduceSelfReferenceFiles.mt_interval_list_self
    File? nuc_interval_list_self = ProduceSelfReferenceFiles.nuc_interval_list_self
    File? nuc_interval_list_shifted_self = ProduceSelfReferenceFiles.nuc_interval_list_shifted_self
    File blacklisted_sites_self = ProduceSelfReferenceFiles.blacklisted_sites_self
    File blacklisted_sites_index_self = ProduceSelfReferenceFiles.blacklisted_sites_index_self
    File non_control_interval_self = ProduceSelfReferenceFiles.non_control_interval_self
    File control_shifted_self = ProduceSelfReferenceFiles.control_shifted_self

    Int nuc_variants_dropped = ProduceSelfReferenceFiles.nuc_variants_dropped
    Int mtdna_consensus_overlaps = ProduceSelfReferenceFiles.mtdna_consensus_overlaps
    Int nuc_consensus_overlaps = ProduceSelfReferenceFiles.nuc_consensus_overlaps
  }
}

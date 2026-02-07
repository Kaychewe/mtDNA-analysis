version 1.0

import "mtSwirl/WDL/v2.5_MongoSwirl_Single/AlignAndCallR1_v2_5_Single.wdl" as AlignAndCallR1_Single

workflow StageAlignAndCallR1 {
  meta {
    description: "Stage 2: align to mt reference and call R1 variants."
  }

  input {
    File input_bam
    File input_bai
    String sample_name

    File ref_dict
    File ref_fasta
    File ref_fasta_index

    File mt_dict
    File mt_fasta
    File mt_fasta_index
    File blacklisted_sites
    File blacklisted_sites_index

    File nuc_interval_list
    File mt_interval_list

    Int mt_mean_coverage

    Boolean use_haplotype_caller_nucdna = true
    Int hc_dp_lower_bound = 10
    File? gatk_override
    String? gatk_docker_override
    String gatk_version = "4.2.6.0"
    String? m2_extra_args
    String? m2_filter_extra_args
    Float? vaf_filter_threshold
    Float? f_score_beta
    Boolean compress_output_vcf = false
    Float? verifyBamID

    Int? max_read_length
    String haplochecker_docker = "eclipse-temurin:17-jdk"
    File haplocheck_zip

    Int? preemptible_tries
    Int? n_cpu
  }

  call AlignAndCallR1_Single.AlignAndCallR1 as AlignAndCallR1 {
    input:
      input_bam = input_bam,
      input_bai = input_bai,
      sample_name = sample_name,
      ref_dict = ref_dict,
      ref_fasta = ref_fasta,
      ref_fasta_index = ref_fasta_index,
      mt_dict = mt_dict,
      mt_fasta = mt_fasta,
      mt_fasta_index = mt_fasta_index,
      blacklisted_sites = blacklisted_sites,
      blacklisted_sites_index = blacklisted_sites_index,
      nuc_interval_list = nuc_interval_list,
      mt_interval_list = mt_interval_list,
      mt_mean_coverage = mt_mean_coverage,
      use_haplotype_caller_nucdna = use_haplotype_caller_nucdna,
      hc_dp_lower_bound = hc_dp_lower_bound,
      gatk_override = gatk_override,
      gatk_docker_override = gatk_docker_override,
      gatk_version = gatk_version,
      m2_extra_args = m2_extra_args,
      m2_filter_extra_args = m2_filter_extra_args,
      vaf_filter_threshold = vaf_filter_threshold,
      f_score_beta = f_score_beta,
      compress_output_vcf = compress_output_vcf,
      verifyBamID = verifyBamID,
      max_read_length = max_read_length,
      haplochecker_docker = haplochecker_docker,
      haplocheck_zip = haplocheck_zip,
      preemptible_tries = preemptible_tries,
      n_cpu = n_cpu
  }

  output {
    File out_vcf = AlignAndCallR1.out_vcf
    File out_vcf_index = AlignAndCallR1.out_vcf_index
    File split_vcf = AlignAndCallR1.split_vcf
    File split_vcf_index = AlignAndCallR1.split_vcf_index
    File nuc_vcf = AlignAndCallR1.nuc_vcf
    File nuc_vcf_index = AlignAndCallR1.nuc_vcf_index
    File nuc_vcf_unfiltered = AlignAndCallR1.nuc_vcf_unfiltered
    File split_nuc_vcf = AlignAndCallR1.split_nuc_vcf
    File split_nuc_vcf_index = AlignAndCallR1.split_nuc_vcf_index
    Int nuc_variants_pass = AlignAndCallR1.nuc_variants_pass
    File input_vcf_for_haplochecker = AlignAndCallR1.input_vcf_for_haplochecker
    File contamination_metrics = AlignAndCallR1.contamination_metrics
    String major_haplogroup = AlignAndCallR1.major_haplogroup
    Float contamination = AlignAndCallR1.contamination
    String hasContamination = AlignAndCallR1.hasContamination
    Float contamination_major = AlignAndCallR1.contamination_major
    Float contamination_minor = AlignAndCallR1.contamination_minor
  }
}

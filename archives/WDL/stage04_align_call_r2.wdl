version 1.0

import "mtSwirl/WDL/v2.5_MongoSwirl_Single/AlignAndCallR2_v2_5_Single.wdl" as AlignAndCallR2_Single

workflow StageAlignAndCallR2 {
  meta {
    description: "Stage 4: align to self reference and call R2 variants."
  }

  input {
    # Stage01 outputs
    File unmapped_bam

    # Sample naming
    String sample_name
    String suffix = ".self.ref"

    # Stage03 self-reference outputs
    File mt_interval_list_self

    File mt_self
    File mt_self_index
    File mt_self_dict

    File mt_andNuc_self
    File mt_andNuc_self_index
    File mt_andNuc_self_dict

    File mt_shifted_self
    File mt_shifted_self_index
    File mt_shifted_self_dict

    File mt_andNuc_shifted_self
    File mt_andNuc_shifted_self_index
    File mt_andNuc_shifted_self_dict

    File blacklisted_sites_self
    File blacklisted_sites_index_self

    File force_call_vcf
    File force_call_vcf_idx
    File force_call_vcf_shifted
    File force_call_vcf_shifted_idx

    File self_shift_back_chain

    File non_control_interval_self
    File control_shifted_self

    # Stage02 contamination outputs
    String hasContamination
    Float contamination_major
    Float contamination_minor

    # Parameters
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

    Int? preemptible_tries
    Int? n_cpu
    Int? n_cpu_bwa
    String? gotc_docker_override
  }

  call AlignAndCallR2_Single.AlignAndCallR2 as AlignAndCallR2 {
    input:
      unmapped_bam = unmapped_bam,
      sample_name = sample_name,
      suffix = suffix,

      mt_interval_list = mt_interval_list_self,

      mt_self = mt_self,
      mt_self_index = mt_self_index,
      mt_self_dict = mt_self_dict,

      self_cat = mt_andNuc_self,
      self_cat_index = mt_andNuc_self_index,
      self_cat_dict = mt_andNuc_self_dict,

      mt_self_shifted = mt_shifted_self,
      mt_self_shifted_index = mt_shifted_self_index,
      mt_self_shifted_dict = mt_shifted_self_dict,

      self_shifted_cat = mt_andNuc_shifted_self,
      self_shifted_cat_index = mt_andNuc_shifted_self_index,
      self_shifted_cat_dict = mt_andNuc_shifted_self_dict,

      shift_back_chain = self_shift_back_chain,

      force_call_vcf = force_call_vcf,
      force_call_vcf_idx = force_call_vcf_idx,
      force_call_vcf_shifted = force_call_vcf_shifted,
      force_call_vcf_shifted_idx = force_call_vcf_shifted_idx,

      non_control_interval = non_control_interval_self,
      control_shifted = control_shifted_self,
      blacklisted_sites = blacklisted_sites_self,
      blacklisted_sites_index = blacklisted_sites_index_self,

      gatk_override = gatk_override,
      gatk_docker_override = gatk_docker_override,
      gatk_version = gatk_version,
      m2_extra_args = m2_extra_args,
      m2_filter_extra_args = m2_filter_extra_args,
      vaf_filter_threshold = vaf_filter_threshold,
      f_score_beta = f_score_beta,
      verifyBamID = verifyBamID,
      compress_output_vcf = compress_output_vcf,
      max_read_length = max_read_length,
      preemptible_tries = preemptible_tries,
      hasContamination = hasContamination,
      contamination_major = contamination_major,
      contamination_minor = contamination_minor,
      n_cpu_bwa = n_cpu_bwa,
      n_cpu = n_cpu,
      gotc_docker_override = gotc_docker_override
  }

  output {
    File mt_aligned_bam = AlignAndCallR2.mt_aligned_bam
    File mt_aligned_bai = AlignAndCallR2.mt_aligned_bai
    File mt_aligned_shifted_bam = AlignAndCallR2.mt_aligned_shifted_bam
    File mt_aligned_shifted_bai = AlignAndCallR2.mt_aligned_shifted_bai

    File nuc_mt_aligned_bam = AlignAndCallR2.nuc_mt_aligned_bam
    File nuc_mt_aligned_bai = AlignAndCallR2.nuc_mt_aligned_bai
    File nuc_mt_shifted_aligned_bam = AlignAndCallR2.nuc_mt_shifted_aligned_bam
    File nuc_mt_shifted_aligned_bai = AlignAndCallR2.nuc_mt_shifted_aligned_bai

    File out_vcf = AlignAndCallR2.out_vcf
    File out_vcf_idx = AlignAndCallR2.out_vcf_idx
    File split_vcf = AlignAndCallR2.split_vcf
    File split_vcf_idx = AlignAndCallR2.split_vcf_idx

    File duplicate_metrics = AlignAndCallR2.duplicate_metrics
    File coverage_metrics = AlignAndCallR2.coverage_metrics
    File theoretical_sensitivity_metrics = AlignAndCallR2.theoretical_sensitivity_metrics

    Int mean_coverage = AlignAndCallR2.mean_coverage
    Float median_coverage = AlignAndCallR2.median_coverage
  }
}

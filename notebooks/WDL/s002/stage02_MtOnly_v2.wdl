version 1.0

workflow stage02_MtOnly {
  meta {
    description: "Stage02 (full, single-file): align/call mt + nuc, contamination, haplochecker."
  }

  input {
    File input_bam
    File input_bai
    String sample_id
    String? age
    String? sex

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

    String docker
    File? gatk_override
    String gatk_version = "4.2.6.0"
    String? m2_extra_args
    String? m2_filter_extra_args
    Float? vaf_filter_threshold
    Float? f_score_beta
    Boolean compress_output_vcf = false
    Float? verifyBamID

    Int? max_read_length
    File haplocheck_zip

    Int? preemptible_tries
    Int? n_cpu
  }

  String age_label = select_first([age, "NA"])
  String sex_label = select_first([sex, "NA"])
  String sample_label = sample_id + "_" + age_label + "_" + sex_label

  if (use_haplotype_caller_nucdna) {
    call MongoHC as CallNucHCIntegrated {
      input:
        input_bam = input_bam,
        input_bai = input_bai,
        sample_name = sample_label,
        nuc_interval_list = nuc_interval_list,
        ref_fasta = ref_fasta,
        ref_fai = ref_fasta_index,
        ref_dict = ref_dict,
        suffix = ".nuc",
        compress = compress_output_vcf,
        gatk_override = gatk_override,
        gatk_docker_override = docker,
        gatk_version = gatk_version,
        hc_dp_lower_bound = hc_dp_lower_bound,
        mem = 4,
        preemptible_tries = preemptible_tries,
        n_cpu = n_cpu
    }
  }

  if (!use_haplotype_caller_nucdna) {
    call MongoNucM2 as CallNucM2Integrated {
      input:
        input_bam = input_bam,
        input_bai = input_bai,
        sample_name = sample_label,

        ref_fasta = ref_fasta,
        ref_fai = ref_fasta_index,
        ref_dict = ref_dict,
        suffix = ".nuc",
        mt_interval_list = nuc_interval_list,

        m2_extra_args = select_first([m2_extra_args, ""]),

        max_alt_allele_count = 4,
        vaf_filter_threshold = 0.95,
        verifyBamID = verifyBamID,
        compress = compress_output_vcf,

        gatk_override = gatk_override,
        gatk_docker_override = docker,
        gatk_version = gatk_version,
        mem = 4,
        preemptible_tries = preemptible_tries,
        n_cpu = n_cpu
    }
  }

  Int M2_mem = if mt_mean_coverage > 25000 then 14 else 7

  call MongoRunM2InitialFilterSplit as CallMt {
    input:
      sample_name = sample_label,
      input_bam = input_bam,
      input_bai = input_bai,
      verifyBamID = verifyBamID,
      mt_interval_list = mt_interval_list,
      ref_fasta = mt_fasta,
      ref_fai = mt_fasta_index,
      ref_dict = mt_dict,
      suffix = "",
      compress = compress_output_vcf,
      m2_extra_filtering_args = select_first([m2_filter_extra_args, ""]) + " --min-median-mapping-quality 0",
      max_alt_allele_count = 4,
      vaf_filter_threshold = 0,
      blacklisted_sites = blacklisted_sites,
      blacklisted_sites_index = blacklisted_sites_index,
      f_score_beta = f_score_beta,
      gatk_override = gatk_override,
      gatk_docker_override = docker,
      gatk_version = gatk_version,
      m2_extra_args = select_first([m2_extra_args, ""]),
      mem = M2_mem,
      preemptible_tries = preemptible_tries,
      n_cpu = n_cpu
  }

  call GetContamination {
    input:
      input_vcf = CallMt.vcf_for_haplochecker,
      sample_name = sample_label,
      mean_coverage = mt_mean_coverage,
      preemptible_tries = preemptible_tries,
      haplochecker_docker = docker,
      haplocheck_zip = haplocheck_zip
  }

  call MongoM2FilterContaminationSplit as FilterContamination {
    input:
      raw_vcf = CallMt.filtered_vcf,
      raw_vcf_index = CallMt.filtered_vcf_idx,
      raw_vcf_stats = CallMt.stats,
      sample_name = sample_label,
      hasContamination = GetContamination.hasContamination,
      contamination_major = GetContamination.major_level,
      contamination_minor = GetContamination.minor_level,
      suffix = "",
      run_contamination = true,
      verifyBamID = verifyBamID,
      ref_fasta = mt_fasta,
      ref_fai = mt_fasta_index,
      ref_dict = mt_dict,
      compress = compress_output_vcf,
      gatk_override = gatk_override,
      gatk_docker_override = docker,
      gatk_version = gatk_version,
      m2_extra_filtering_args = select_first([m2_filter_extra_args, ""]) + " --min-median-mapping-quality 0",
      max_alt_allele_count = 4,
      vaf_filter_threshold = vaf_filter_threshold,
      blacklisted_sites = blacklisted_sites,
      blacklisted_sites_index = blacklisted_sites_index,
      f_score_beta = f_score_beta,
      preemptible_tries = preemptible_tries
  }

  output {
    File out_vcf = FilterContamination.filtered_vcf
    File out_vcf_index = FilterContamination.filtered_vcf_idx
    File split_vcf = FilterContamination.split_vcf
    File split_vcf_index = FilterContamination.split_vcf_index
    File nuc_vcf = select_first([CallNucHCIntegrated.full_pass_vcf, CallNucM2Integrated.full_pass_vcf])
    File nuc_vcf_index = select_first([CallNucHCIntegrated.full_pass_vcf_index, CallNucM2Integrated.full_pass_vcf_index])
    File nuc_vcf_unfiltered = select_first([CallNucHCIntegrated.filtered_vcf, CallNucM2Integrated.filtered_vcf])
    File split_nuc_vcf = select_first([CallNucHCIntegrated.split_vcf, CallNucM2Integrated.split_vcf])
    File split_nuc_vcf_index = select_first([CallNucHCIntegrated.split_vcf_index, CallNucM2Integrated.split_vcf_index])
    Int nuc_variants_pass = select_first([CallNucHCIntegrated.post_filt_vars, CallNucM2Integrated.post_filt_vars])
    File input_vcf_for_haplochecker = CallMt.vcf_for_haplochecker
    File contamination_metrics = GetContamination.contamination_file
    String major_haplogroup = GetContamination.major_hg
    Float contamination = FilterContamination.contamination
    String hasContamination = GetContamination.hasContamination
    Float contamination_major = GetContamination.major_level
    Float contamination_minor = GetContamination.minor_level
  }
}

task GetContamination {
  input {
    File input_vcf
    String sample_name
    Int mean_coverage
    File haplocheck_zip
    String haplochecker_docker
    Int? preemptible_tries
  }

  Int disk_size = ceil(size(input_vcf, "GB")) + 20
  String d = "$"

  command <<<
  set -e

  mkdir out
  this_basename=out/"~{sample_name}"
  this_mean_cov="~{mean_coverage}"
  this_vcf="~{input_vcf}"

  this_vcf_nvar=$(cat "~{d}{this_vcf}" | grep ^chrM | wc -l | sed 's/^ *//g')
  echo "~{sample_name} has VCF with ~{d}{this_vcf_nvar} variants for contamination."

  zip_path="~{haplocheck_zip}"
  jar xf "${zip_path}"
  chmod +x haplocheck

  ./haplocheck --out output "~{d}{this_vcf}"

  if [ -s output ]; then
    sed 's/"//g' output > output-noquotes
  else
    : > output-noquotes
  fi

  if grep -q "SampleID" output-noquotes; then
    awk -F "	" 'NR==1{print;next}{$1="~{sample_name}";print}' output-noquotes > output-noquotes.fixed
    mv output-noquotes.fixed output-noquotes
  fi

  cp 'output-noquotes' "~{d}{this_basename}_output_noquotes"

  FORMAT_ERROR="Bad contamination file format"
  if grep -q "SampleID" output-noquotes; then
    grep "SampleID" output-noquotes > headers
    if [ `awk '{print $2}' headers` != "Contamination" ]; then echo $FORMAT_ERROR; fi
    if [ `awk '{print $6}' headers` != "HgMajor" ]; then echo $FORMAT_ERROR; fi
    if [ `awk '{print $8}' headers` != "HgMinor" ]; then echo $FORMAT_ERROR; fi
    if [ `awk '{print $14}' headers` != "MeanHetLevelMajor" ]; then echo $FORMAT_ERROR; fi
    if [ `awk '{print $15}' headers` != "MeanHetLevelMinor" ]; then echo $FORMAT_ERROR; fi
  else
    echo $FORMAT_ERROR
  fi

  if grep -q "SampleID" output-noquotes && grep -v "SampleID" output-noquotes | grep -q . && [ "~{d}{this_mean_cov}" -gt 0 ] && [ "~{d}{this_vcf_nvar}" -gt 0 ]; then
    grep -v "SampleID" output-noquotes > output-data
    awk -F "	" '{print $2}' output-data > "~{d}{this_basename}.contamination.txt"
    awk -F "	" '{print $6}' output-data > "~{d}{this_basename}.major_hg.txt"
    awk -F "	" '{print $8}' output-data > "~{d}{this_basename}.minor_hg.txt"
    awk -F "	" '{print $14}' output-data > "~{d}{this_basename}.mean_het_major.txt"
    awk -F "	" '{print $15}' output-data > "~{d}{this_basename}.mean_het_minor.txt"
  else
    echo "NO" > "~{d}{this_basename}.contamination.txt"
    echo "NONE" > "~{d}{this_basename}.major_hg.txt"
    echo "NONE" > "~{d}{this_basename}.minor_hg.txt"
    echo "0.000" > "~{d}{this_basename}.mean_het_major.txt"
    echo "0.000" > "~{d}{this_basename}.mean_het_minor.txt"
  fi
  >>>
  runtime {
    preemptible: select_first([preemptible_tries, 5])
    memory: "3 GB"
    disks: "local-disk " + disk_size + " HDD"
    docker: haplochecker_docker
  }
  output {
    File contamination_file = "out/~{sample_name}_output_noquotes"
    String hasContamination = read_string("out/~{sample_name}.contamination.txt")
    String major_hg = read_string("out/~{sample_name}.major_hg.txt")
    String minor_hg = read_string("out/~{sample_name}.minor_hg.txt")
    Float major_level = read_float("out/~{sample_name}.mean_het_major.txt")
    Float minor_level = read_float("out/~{sample_name}.mean_het_minor.txt")
  }
}

task MongoHC {
  input {
    File ref_fasta
    File ref_fai
    File ref_dict
    File input_bam
    File input_bai

    String sample_name
    String suffix = ""

    Int max_reads_per_alignment_start = 75
    String? hc_extra_args
    Boolean make_bamout = false

    File? nuc_interval_list
    File? force_call_vcf
    File? force_call_vcf_index

    Boolean compress
    String gatk_version
    File? gatk_override
    String? gatk_docker_override
    Float? contamination

    Int hc_dp_lower_bound

    Int mem
    Int? preemptible_tries
    Int? n_cpu
  }

  Int machine_mem = if defined(mem) then mem * 1000 else 3500
  Int command_mem = machine_mem - 500

  Float ref_size = size(ref_fasta, "GB") + size(ref_fai, "GB") + size(ref_dict, "GB")
  Int disk_size = ceil((size(input_bam, "GB") * 2) + ref_size) + 22

  String d = "$"

  command <<<
    set -e

    mkdir out
    this_sample=out/"~{sample_name}"
    this_basename="~{d}{this_sample}""~{suffix}"
    bamoutfile="~{d}{this_basename}.bamout.bam"
    touch "~{d}{bamoutfile}"

    if [[ ~{make_bamout} == 'true' ]]; then bamoutstr="--bam-output ~{d}{this_basename}.bamout.bam"; else bamoutstr=""; fi

    gatk --java-options "-Xmx~{command_mem}m" HaplotypeCaller       -R ~{ref_fasta}       -I ~{input_bam}       ~{"-L " + nuc_interval_list}       -O "~{d}{this_basename}.raw.vcf"       ~{hc_extra_args}       -contamination ~{default="0" contamination}       ~{"--genotype-filtered-alleles --alleles " + force_call_vcf}       --max-reads-per-alignment-start ~{max_reads_per_alignment_start}       --max-mnp-distance 0       --annotation StrandBiasBySample       -G StandardAnnotation -G StandardHCAnnotation       -GQB 10 -GQB 20 -GQB 30 -GQB 40 -GQB 50 -GQB 60 -GQB 70 -GQB 80 -GQB 90 ~{d}{bamoutstr}

    gatk --java-options "-Xmx~{command_mem}m" SelectVariants -V "~{d}{this_basename}.raw.vcf" -select-type SNP -O snps.vcf
    gatk --java-options "-Xmx~{command_mem}m" VariantFiltration -V snps.vcf       -R ~{ref_fasta}       -O snps_filtered.vcf       -filter "QD < 2.0" --filter-name "QD2"       -filter "QUAL < 30.0" --filter-name "QUAL30"       -filter "SOR > 3.0" --filter-name "SOR3"       -filter "FS > 60.0" --filter-name "FS60"       -filter "MQ < 40.0" --filter-name "MQ40"       -filter "MQRankSum < -12.5" --filter-name "MQRankSum-12.5"       -filter "ReadPosRankSum < -8.0" --filter-name "ReadPosRankSum-8"       --genotype-filter-expression "isHet == 1" --genotype-filter-name "isHetFilt"       --genotype-filter-expression "isHomRef == 1" --genotype-filter-name "isHomRefFilt"       ~{'--genotype-filter-expression "DP < ' + hc_dp_lower_bound + '" --genotype-filter-name "genoDP' + hc_dp_lower_bound + '"'}

    gatk --java-options "-Xmx~{command_mem}m" SelectVariants -V "~{d}{this_basename}.raw.vcf" -select-type INDEL -O indels.vcf
    gatk --java-options "-Xmx~{command_mem}m" VariantFiltration -V indels.vcf       -R ~{ref_fasta}       -O indels_filtered.vcf       -filter "QD < 2.0" --filter-name "QD2"       -filter "QUAL < 30.0" --filter-name "QUAL30"       -filter "FS > 200.0" --filter-name "FS200"       -filter "SOR > 10.0" --filter-name "SOR10"       -filter "ReadPosRankSum < -20.0" --filter-name "ReadPosRankSum-20"       --genotype-filter-expression "isHet == 1" --genotype-filter-name "isHetFilt"       --genotype-filter-expression "isHomRef == 1" --genotype-filter-name "isHomRefFilt"       ~{'--genotype-filter-expression "DP < ' + hc_dp_lower_bound + '" --genotype-filter-name "genoDP' + hc_dp_lower_bound + '"'}

    gatk --java-options "-Xmx~{command_mem}m" MergeVcfs -I snps_filtered.vcf -I indels_filtered.vcf -O "~{d}{this_basename}.vcf"

    gatk --java-options "-Xmx~{command_mem}m" SelectVariants       -V "~{d}{this_basename}.vcf"       --exclude-filtered       --set-filtered-gt-to-nocall       --exclude-non-variants       -O "~{d}{this_basename}.pass.vcf"

    gatk --java-options "-Xmx~{command_mem}m" CountVariants -V $this_basename.pass.vcf | tail -n1 > "~{d}{this_basename}.passvars.txt"

    gatk --java-options "-Xmx~{command_mem}m" LeftAlignAndTrimVariants       -R ~{ref_fasta}       -V "~{d}{this_basename}.pass.vcf"       -O "~{d}{this_basename}.pass.split.vcf"       --split-multi-allelics       --dont-trim-alleles       --keep-original-ac       --create-output-variant-index
  >>>

  runtime {
    docker: select_first([gatk_docker_override, "us.gcr.io/broad-gatk/gatk:"+gatk_version])
    memory: machine_mem + " MB"
    disks: "local-disk " + disk_size + " HDD"
    preemptible: select_first([preemptible_tries, 5])
    cpu: select_first([n_cpu,1])
  }
  output {
    File raw_vcf = "out/~{sample_name}~{suffix}.raw.vcf"
    File raw_vcf_idx = "out/~{sample_name}~{suffix}.raw.vcf.idx"
    File output_bamOut = "out/~{sample_name}~{suffix}.bamout.bam"
    File filtered_vcf = "out/~{sample_name}~{suffix}.vcf"
    File filtered_vcf_idx = "out/~{sample_name}~{suffix}.vcf.idx"
    File full_pass_vcf = "out/~{sample_name}~{suffix}.pass.vcf"
    File full_pass_vcf_index = "out/~{sample_name}~{suffix}.pass.vcf.idx"
    Int post_filt_vars = read_int("out/~{sample_name}~{suffix}.passvars.txt")
    File split_vcf = "out/~{sample_name}~{suffix}.pass.split.vcf"
    File split_vcf_index = "out/~{sample_name}~{suffix}.pass.split.vcf.idx"
  }
}

task MongoNucM2 {
  input {
    File ref_fasta
    File ref_fai
    File ref_dict
    File input_bam
    File input_bai

    String sample_name
    String suffix = ""

    Int max_reads_per_alignment_start = 75
    String? m2_extra_args
    Boolean make_bamout = false
    Boolean compress

    File? mt_interval_list

    Float? vaf_cutoff
    String? m2_extra_filtering_args
    Int max_alt_allele_count
    Float? vaf_filter_threshold
    Float? f_score_beta
    Float? verifyBamID
    File? blacklisted_sites
    File? blacklisted_sites_index

    File? gatk_override
    String gatk_version
    String? gatk_docker_override
    Int mem
    Int? preemptible_tries
    Int? n_cpu
  }

  Float ref_size = size(ref_fasta, "GB") + size(ref_fai, "GB")
  Int disk_size = ceil(size(input_bam, "GB")*2 + ref_size) + 20
  Float defval = 0.0

  Int machine_mem = if defined(mem) then mem * 1000 else 3500
  Int command_mem = machine_mem - 500

  String d = "$"

  command <<<
    set -e

    mkdir out
    this_sample=out/"~{sample_name}"
    this_contamination="~{select_first([verifyBamID, defval])}"
    this_bam="~{input_bam}"
    this_basename="~{d}{this_sample}~{suffix}"
    bamoutfile="~{d}{this_basename}.bamout.bam"
    touch "~{d}{bamoutfile}"
    if [[ ~{make_bamout} == 'true' ]]; then bamoutstr="--bam-output ~{d}{bamoutfile}"; else bamoutstr=""; fi

    gatk --java-options "-Xmx~{command_mem}m" Mutect2       -R ~{ref_fasta}       -I "~{d}{this_bam}"       ~{"-L " + mt_interval_list}       -O "~{d}{this_basename}.raw.vcf"       ~{m2_extra_args}       ~{"--minimum-allele-fraction " + vaf_filter_threshold}       --annotation StrandBiasBySample       --max-reads-per-alignment-start ~{max_reads_per_alignment_start}       --max-mnp-distance 0 ~{d}{bamoutstr}

    gatk --java-options "-Xmx~{command_mem}m" FilterMutectCalls -V "~{d}{this_basename}.raw.vcf"       -R ~{ref_fasta}       -O filtered.vcf       --stats "~{d}{this_basename}.raw.vcf.stats"       ~{m2_extra_filtering_args}       --max-alt-allele-count ~{max_alt_allele_count}       ~{"--min-allele-fraction " + vaf_filter_threshold}       ~{"--f-score-beta " + f_score_beta}       --contamination-estimate "~{d}{this_contamination}"

    ~{"gatk IndexFeatureFile -I " + blacklisted_sites}

    gatk --java-options "-Xmx~{command_mem}m" VariantFiltration -V filtered.vcf       -O "~{d}{this_basename}.vcf"       --apply-allele-specific-filters       ~{"--mask-name 'blacklisted_site' --mask " + blacklisted_sites}

    gatk --java-options "-Xmx~{command_mem}m" SelectVariants       -V "~{d}{this_basename}.vcf"       --exclude-filtered       -O "~{d}{this_basename}.pass.vcf"

    gatk CountVariants -V "~{d}{this_basename}.pass.vcf" | tail -n1 > "~{d}{this_basename}.passvars.txt"

    gatk --java-options "-Xmx~{command_mem}m" LeftAlignAndTrimVariants       -R ~{ref_fasta}       -V "~{d}{this_basename}.pass.vcf"       -O "~{d}{this_basename}.pass.split.vcf"       --split-multi-allelics       --dont-trim-alleles       --keep-original-ac       --create-output-variant-index
  >>>
  runtime {
    docker: select_first([gatk_docker_override, "us.gcr.io/broad-gatk/gatk:"+gatk_version])
    memory: machine_mem + " MB"
    disks: "local-disk " + disk_size + " HDD"
    preemptible: select_first([preemptible_tries, 5])
    cpu: select_first([n_cpu,2])
  }
  output {
    File raw_vcf = "out/~{sample_name}~{suffix}.raw.vcf"
    File raw_vcf_idx = "out/~{sample_name}~{suffix}.raw.vcf.idx"
    File stats = "out/~{sample_name}~{suffix}.raw.vcf.stats"
    File output_bamOut = "out/~{sample_name}~{suffix}.bamout.bam"

    File filtered_vcf = "out/~{sample_name}~{suffix}.vcf"
    File filtered_vcf_idx = "out/~{sample_name}~{suffix}.vcf.idx"

    File full_pass_vcf = "out/~{sample_name}~{suffix}.pass.vcf"
    File full_pass_vcf_index = "out/~{sample_name}~{suffix}.pass.vcf.idx"
    Int post_filt_vars = read_int("out/~{sample_name}~{suffix}.passvars.txt")

    File split_vcf = "out/~{sample_name}~{suffix}.pass.split.vcf"
    File split_vcf_index = "out/~{sample_name}~{suffix}.pass.split.vcf.idx"
  }
}

task MongoRunM2InitialFilterSplit {
  input {
    String sample_name
    File input_bam
    File input_bai
    Float? verifyBamID
    String suffix

    File ref_fasta
    File ref_fai
    File ref_dict
    Int max_reads_per_alignment_start = 75
    String? m2_extra_args
    Boolean make_bamout = false
    Boolean compress

    File? mt_interval_list

    Float? vaf_cutoff
    String? m2_extra_filtering_args
    Int max_alt_allele_count
    Float? vaf_filter_threshold
    Float? f_score_beta

    File? blacklisted_sites
    File? blacklisted_sites_index

    String? gatk_docker_override
    File? gatk_override
    String gatk_version
    Int mem
    Int? preemptible_tries
    Int? n_cpu
  }

  Float ref_size = size(ref_fasta, "GB") + size(ref_fai, "GB")
  Int disk_size = (ceil(size(input_bam, "GB") + ref_size) * 2) + 20
  Float defval = 0.0

  Int machine_mem = if defined(mem) then mem * 1000 else 3500
  Int command_mem = machine_mem - 500

  String d = "$"

  command <<<
    set -e

    mkdir out
    this_sample=out/"~{sample_name}"
    this_contamination="~{select_first([verifyBamID, defval])}"
    this_basename="~{d}{this_sample}~{suffix}"
    bamoutfile="~{d}{this_basename}.bamout.bam"
    touch "~{d}{bamoutfile}"
    if [[ ~{make_bamout} == 'true' ]]; then bamoutstr="--bam-output ~{d}{bamoutfile}"; else bamoutstr=""; fi

    gatk --java-options "-Xmx~{command_mem}m" Mutect2       -R ~{ref_fasta}       -I ~{input_bam}       ~{"-L " + mt_interval_list}       -O "~{d}{this_basename}.raw.vcf"       ~{m2_extra_args}       --annotation StrandBiasBySample       --read-filter MateOnSameContigOrNoMappedMateReadFilter       --read-filter MateUnmappedAndUnmappedReadFilter       --mitochondria-mode       --max-reads-per-alignment-start ~{max_reads_per_alignment_start}       --max-mnp-distance 0 ~{d}{bamoutstr}

    gatk --java-options "-Xmx~{command_mem}m" FilterMutectCalls -V "~{d}{this_basename}.raw.vcf"       -R ~{ref_fasta}       -O filtered.vcf       --stats "~{d}{this_basename}.raw.vcf.stats"       ~{m2_extra_filtering_args}       --max-alt-allele-count ~{max_alt_allele_count}       --mitochondria-mode       ~{"--min-allele-fraction " + vaf_filter_threshold}       ~{"--f-score-beta " + f_score_beta}       --contamination-estimate "~{d}{this_contamination}"

    ~{"gatk IndexFeatureFile -I " + blacklisted_sites}

    gatk --java-options "-Xmx~{command_mem}m" VariantFiltration -V filtered.vcf       -O "~{d}{this_basename}.filtered.vcf"       --apply-allele-specific-filters       ~{"--mask-name 'blacklisted_site' --mask " + blacklisted_sites}

    gatk --java-options "-Xmx~{command_mem}m" LeftAlignAndTrimVariants       -R ~{ref_fasta}       -V "~{d}{this_basename}.filtered.vcf"       -O split.vcf       --split-multi-allelics       --dont-trim-alleles       --keep-original-ac

    gatk --java-options "-Xmx~{command_mem}m" SelectVariants       -V split.vcf       -O "~{d}{this_basename}.splitAndPassOnly.vcf"       --exclude-filtered
  >>>
  runtime {
    docker: select_first([gatk_docker_override, "us.gcr.io/broad-gatk/gatk:"+gatk_version])
    memory: machine_mem + " MB"
    disks: "local-disk " + disk_size + " HDD"
    preemptible: select_first([preemptible_tries, 5])
    cpu: select_first([n_cpu,2])
  }
  output {
    File raw_vcf = "out/~{sample_name}~{suffix}.raw.vcf"
    File raw_vcf_idx = "out/~{sample_name}~{suffix}.raw.vcf.idx"
    File stats = "out/~{sample_name}~{suffix}.raw.vcf.stats"
    File output_bamOut = "out/~{sample_name}~{suffix}.bamout.bam"

    File filtered_vcf = "out/~{sample_name}~{suffix}.filtered.vcf"
    File filtered_vcf_idx = "out/~{sample_name}~{suffix}.filtered.vcf.idx"

    File vcf_for_haplochecker = "out/~{sample_name}~{suffix}.splitAndPassOnly.vcf"
  }
}

task MongoM2FilterContaminationSplit {
  input {
    File raw_vcf
    File raw_vcf_index
    File raw_vcf_stats
    String sample_name
    String hasContamination
    Float contamination_major
    Float contamination_minor
    Float? verifyBamID

    Boolean run_contamination
    File ref_fasta
    File ref_fai
    File ref_dict

    Boolean compress
    Float? vaf_cutoff
    String suffix

    String? m2_extra_filtering_args
    Int max_alt_allele_count
    Float? vaf_filter_threshold
    Float? f_score_beta

    File? blacklisted_sites
    File? blacklisted_sites_index

    File? gatk_override
    String? gatk_docker_override
    String gatk_version

    Int? preemptible_tries
  }

  Float ref_size = size(ref_fasta, "GB") + size(ref_fai, "GB")
  Int disk_size = ceil(size(raw_vcf, "GB") + ref_size) + 20
  Float defval = 0.0
  String d = "$"

  command <<<
    set -e

    mkdir out

    this_sample=out/"~{sample_name}"
    this_raw_vcf="~{raw_vcf}"
    this_raw_stats="~{raw_vcf_stats}"
    this_has_contam="~{hasContamination}"
    this_verifybam="~{select_first([verifyBamID, defval])}"
    this_contam_major="~{contamination_major}"
    this_contam_minor="~{contamination_minor}"

    this_basename="~{d}{this_sample}~{suffix}"
    bamoutfile="~{d}{this_basename}.bamout.bam"
    touch "~{d}{bamoutfile}"

    if [[ "~{d}{this_has_contam}" == 'YES' ]]; then
      if (( $(echo "~{d}{this_contam_major} == 0.0"|bc -l) )); then
        this_hc_contamination="~{d}{this_contam_minor}"
      else
        this_hc_contamination=$( bc <<< "1-~{d}{this_contam_major}" )
      fi
    else
      this_hc_contamination=0.0
    fi

    echo "~{d}{this_hc_contamination}" > "~{d}{this_basename}.hc_contam.txt"

    if (( $(echo "~{d}{this_verifybam} > ~{d}{this_hc_contamination}"|bc -l) )); then
      this_max_contamination="~{d}{this_verifybam}"
    else
      this_max_contamination="~{d}{this_hc_contamination}"
    fi

    gatk --java-options "-Xmx2500m" FilterMutectCalls       -V "~{d}{this_raw_vcf}"       -R ~{ref_fasta}       -O filtered.vcf       --stats "~{d}{this_raw_stats}"       ~{m2_extra_filtering_args}       --max-alt-allele-count ~{max_alt_allele_count}       --mitochondria-mode       ~{"--min-allele-fraction " + vaf_filter_threshold}       ~{"--f-score-beta " + f_score_beta}       --contamination-estimate "~{d}{this_max_contamination}"

    ~{"gatk IndexFeatureFile -I " + blacklisted_sites}

    gatk --java-options "-Xmx2500m" VariantFiltration       -V filtered.vcf       -O "~{d}{this_basename}.vcf"       --apply-allele-specific-filters       ~{"--mask-name 'blacklisted_site' --mask " + blacklisted_sites}

    gatk --java-options "-Xmx2500m" LeftAlignAndTrimVariants       -R ~{ref_fasta}       -V "~{d}{this_basename}.vcf"       -O "~{d}{this_basename}.split.vcf"       --split-multi-allelics       --dont-trim-alleles       --keep-original-ac       --create-output-variant-index
  >>>
  runtime {
    docker: select_first([gatk_docker_override, "us.gcr.io/broad-gatk/gatk:"+gatk_version])
    memory: "4 MB"
    disks: "local-disk " + disk_size + " HDD"
    preemptible: select_first([preemptible_tries, 5])
    cpu: 2
  }
  output {
    File filtered_vcf = "out/~{sample_name}~{suffix}.vcf"
    File filtered_vcf_idx = "out/~{sample_name}~{suffix}.vcf.idx"
    File split_vcf = "out/~{sample_name}~{suffix}.split.vcf"
    File split_vcf_index = "out/~{sample_name}~{suffix}.split.vcf.idx"
    Float contamination = read_float("out/~{sample_name}~{suffix}.hc_contam.txt")
  }
}

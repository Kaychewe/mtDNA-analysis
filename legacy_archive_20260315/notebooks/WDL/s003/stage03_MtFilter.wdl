version 1.0

workflow stage03_MtFilter {
  meta {
    description: "Stage03 simplified: filter mtDNA variants by VAF and emit VCF + TSV."
  }

  input {
    File input_vcf
    File input_vcf_index
    String sample_id
    String? age
    String? sex
    Float vaf_min = 0.01
    String docker
  }

  call FilterToTsv {
    input:
      input_vcf = input_vcf,
      input_vcf_index = input_vcf_index,
      sample_id = sample_id,
      age = age,
      sex = sex,
      vaf_min = vaf_min,
      docker = docker
  }

  output {
    File out_vcf = FilterToTsv.out_vcf
    File out_tsv = FilterToTsv.out_tsv
  }
}

task FilterToTsv {
  input {
    File input_vcf
    File input_vcf_index
    String sample_id
    String? age
    String? sex
    Float vaf_min
    String docker
  }

  String age_label = select_first([age, "NA"])
  String sex_label = select_first([sex, "NA"])
  String prefix = sample_id + "_" + age_label + "_" + sex_label + "_mt"

  command <<<
    set -e
    mkdir -p out

    # Filter by VAF (AF in FORMAT)
    bcftools view -i "FORMAT/AF>=~{vaf_min}" "~{input_vcf}" -Oz -o "out/~{prefix}.vaf~{vaf_min}.vcf.gz"
    tabix -p vcf "out/~{prefix}.vaf~{vaf_min}.vcf.gz"

    # TSV output
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%QUAL\t%FILTER\t%INFO/DP\t%FORMAT/AF\n'       "out/~{prefix}.vaf~{vaf_min}.vcf.gz" > "out/~{prefix}.vaf~{vaf_min}.tsv"
  >>>

  runtime {
    docker: "~{docker}"
    memory: "8 GB"
    cpu: 2
    disks: "local-disk 200 HDD"
    bootDiskSizeGb: 50
  }

  output {
    File out_vcf = "out/~{prefix}.vaf~{vaf_min}.vcf.gz"
    File out_tsv = "out/~{prefix}.vaf~{vaf_min}.tsv"
  }
}

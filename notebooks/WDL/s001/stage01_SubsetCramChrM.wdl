version 1.0

workflow stage01_SubsetCramChrM {
  meta {
    description: "Lightweight samtools chrM-only subset: emit BAM/BAI/SAM."
  }

  input {
    String sample_id
    String? age
    String? sex
    File input_cram
    File input_crai
    File ref_fasta
    String docker
  }

  call SubsetChrM_Samtools {
    input:
      sample_id = sample_id,
      age = age,
      sex = sex,
      input_cram = input_cram,
      input_crai = input_crai,
      ref_fasta = ref_fasta,
      docker = docker
  }

  output {
    File final_bam = SubsetChrM_Samtools.final_bam
    File final_bai = SubsetChrM_Samtools.final_bai
    File final_sam = SubsetChrM_Samtools.final_sam
  }
}

task SubsetChrM_Samtools {
  input {
    String sample_id
    String? age
    String? sex
    File input_cram
    File input_crai
    File ref_fasta
    String docker
  }

  String age_label = select_first([age, "NA"])
  String sex_label = select_first([sex, "NA"])
  String prefix = sample_id + "_" + age_label + "_" + sex_label + "_chrM"

  command <<<
    set -e
    mkdir -p out
    
    # simplify the header 
    # samtools reheader command 

    # Subset chrM by contig name
    samtools view -T "~{ref_fasta}" -b "~{input_cram}" chrM -o "out/~{prefix}.bam"

    # Index BAM
    samtools index "out/~{prefix}.bam"

    # Export SAM
    samtools view -h "out/~{prefix}.bam" > "out/~{prefix}.sam"
  >>>

  runtime {
    docker: "~{docker}"
    memory: "8 GB"
    disks: "local-disk 200 HDD"
    bootDiskSizeGb: 50
  }

  output {
    File final_bam = "out/~{prefix}.bam"
    File final_bai = "out/~{prefix}.bam.bai"
    File final_sam = "out/~{prefix}.sam"
  }
}

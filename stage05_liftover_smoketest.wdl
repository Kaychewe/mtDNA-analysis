version 1.0

workflow Stage05LiftoverSmokeTest {
  meta {
    description: "Stage 05 smoketest: verify inputs localize and report sizes."
  }

  input {
    String genomes_cloud_docker
    File HailLiftover
    File ref_fasta
    File ref_fasta_index
    File ref_dict
    File new_self_ref_vcf
    File ref_homoplasmies_vcf
    File force_call_vcf_filters
    File input_bam_regular_ref
    File input_bam_regular_ref_index
    File input_bam_shifted_ref
    File input_bam_shifted_ref_index
    File chain_self_to_ref
    File chain_ref_to_self
    File mt_self
    File mt_self_index
    File mt_self_shifted
    File mt_self_shifted_index
    File self_control_region_shifted_reference_interval_list
    File self_non_control_region_interval_list
  }

  call Stage05InputsSmoke as InputsSmoke {
    input:
      docker_image = genomes_cloud_docker,
      HailLiftover = HailLiftover,
      ref_fasta = ref_fasta,
      ref_fasta_index = ref_fasta_index,
      ref_dict = ref_dict,
      new_self_ref_vcf = new_self_ref_vcf,
      ref_homoplasmies_vcf = ref_homoplasmies_vcf,
      force_call_vcf_filters = force_call_vcf_filters,
      input_bam_regular_ref = input_bam_regular_ref,
      input_bam_regular_ref_index = input_bam_regular_ref_index,
      input_bam_shifted_ref = input_bam_shifted_ref,
      input_bam_shifted_ref_index = input_bam_shifted_ref_index,
      chain_self_to_ref = chain_self_to_ref,
      chain_ref_to_self = chain_ref_to_self,
      mt_self = mt_self,
      mt_self_index = mt_self_index,
      mt_self_shifted = mt_self_shifted,
      mt_self_shifted_index = mt_self_shifted_index,
      self_control_region_shifted_reference_interval_list = self_control_region_shifted_reference_interval_list,
      self_non_control_region_interval_list = self_non_control_region_interval_list
  }

  output {
    File hello = InputsSmoke.hello
    File file_sizes = InputsSmoke.file_sizes
  }
}

task Stage05InputsSmoke {
  input {
    String docker_image
    File HailLiftover
    File ref_fasta
    File ref_fasta_index
    File ref_dict
    File new_self_ref_vcf
    File ref_homoplasmies_vcf
    File force_call_vcf_filters
    File input_bam_regular_ref
    File input_bam_regular_ref_index
    File input_bam_shifted_ref
    File input_bam_shifted_ref_index
    File chain_self_to_ref
    File chain_ref_to_self
    File mt_self
    File mt_self_index
    File mt_self_shifted
    File mt_self_shifted_index
    File self_control_region_shifted_reference_interval_list
    File self_non_control_region_interval_list
  }

  command <<<
    set -euo pipefail
    mkdir -p out
    echo "hello_world" > out/hello_world.txt
    {
      echo "=== File Sizes ==="
      ls -lh "~{HailLiftover}"
      ls -lh "~{ref_fasta}" "~{ref_fasta_index}" "~{ref_dict}"
      ls -lh "~{new_self_ref_vcf}"
      ls -lh "~{ref_homoplasmies_vcf}" "~{force_call_vcf_filters}"
      ls -lh "~{input_bam_regular_ref}" "~{input_bam_regular_ref_index}"
      ls -lh "~{input_bam_shifted_ref}" "~{input_bam_shifted_ref_index}"
      ls -lh "~{chain_self_to_ref}" "~{chain_ref_to_self}"
      ls -lh "~{mt_self}" "~{mt_self_index}"
      ls -lh "~{mt_self_shifted}" "~{mt_self_shifted_index}"
      ls -lh "~{self_control_region_shifted_reference_interval_list}" "~{self_non_control_region_interval_list}"
      echo "=== Disk Usage ==="
      du -h "~{new_self_ref_vcf}" "~{input_bam_regular_ref}" "~{input_bam_shifted_ref}" || true
    } > out/file_sizes.txt
  >>>

  runtime {
    cpu: 1
    memory: "1 GB"
    disks: "local-disk 10 HDD"
    docker: docker_image
    preemptible: 0
  }

  output {
    File hello = "out/hello_world.txt"
    File file_sizes = "out/file_sizes.txt"
  }
}

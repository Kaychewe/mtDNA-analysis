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
    Array[File] candidate_force_call_vcfs = []
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

  call Stage05LiftoverPreflight as Preflight {
    input:
      docker_image = genomes_cloud_docker,
      new_self_ref_vcf = new_self_ref_vcf,
      force_call_vcf_filters = force_call_vcf_filters,
      candidate_force_call_vcfs = candidate_force_call_vcfs
  }

  output {
    File hello = InputsSmoke.hello
    File file_sizes = InputsSmoke.file_sizes
    File preflight_ok = Preflight.preflight_ok
    File isec_summary = Preflight.isec_summary
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

task Stage05LiftoverPreflight {
  input {
    String docker_image
    File new_self_ref_vcf
    File force_call_vcf_filters
    Array[File] candidate_force_call_vcfs = []
  }

  command <<<
    set -euo pipefail
    mkdir -p out

    for tool in bgzip tabix bcftools picard python3 R; do
      if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not found on PATH: $tool" >&2
        exit 1
      fi
    done

    bgzip -c "~{new_self_ref_vcf}" > "out/new_self_ref.vcf.bgz"
    tabix "out/new_self_ref.vcf.bgz"

    # Always include the primary force_call_vcf_filters in the overlap set
    all_candidates=( "~{force_call_vcf_filters}" ~{sep=' ' candidate_force_call_vcfs} )

    : > out/isec_summary.txt
    mkdir -p out/candidates
    for vcf in "${all_candidates[@]}"; do
      base="$(basename "$vcf")"
      use_vcf="$vcf"

      if [[ "$vcf" == *.bgz ]]; then
        if [[ ! -f "${vcf}.tbi" ]]; then
          # Try indexing in place first; fallback to recompress if needed.
          if ! tabix "$vcf"; then
            cand_bgz="out/candidates/${base}"
            bgzip -c "$vcf" > "$cand_bgz"
            tabix "$cand_bgz"
            use_vcf="$cand_bgz"
          fi
        fi
      else
        cand_bgz="out/candidates/${base}.bgz"
        bgzip -c "$vcf" > "$cand_bgz"
        tabix "$cand_bgz"
        use_vcf="$cand_bgz"
      fi

      outdir="out/isec_${base}"
      bcftools isec -p "$outdir" -Ov "out/new_self_ref.vcf.bgz" "$use_vcf"
      {
        echo "=== ${base} ==="
        echo "vcf_0000_count: $(grep -c '^chrM' ${outdir}/0000.vcf || true)"
        echo "vcf_0001_private_to_rev_hom_ref_count: $(grep -c '^chrM' ${outdir}/0001.vcf || true)"
        echo "vcf_0002_intersection_count: $(grep -c '^chrM' ${outdir}/0002.vcf || true)"
      } >> out/isec_summary.txt
    done

    echo "preflight_ok" > out/preflight_ok.txt
  >>>

  runtime {
    cpu: 1
    memory: "2 GB"
    disks: "local-disk 10 HDD"
    docker: docker_image
    preemptible: 0
  }

  output {
    File preflight_ok = "out/preflight_ok.txt"
    File isec_summary = "out/isec_summary.txt"
  }
}

version 1.0

import "mtSwirl/WDL/v2.5_MongoSwirl_Single/MongoTasks_v2_5_Single.wdl" as MongoTasks_Single

workflow MongoProduceSelfReferenceDiagnostics {
  input {
    String sample_name

    # Use real VCFs or let the workflow generate minimal pseudo VCFs.
    Boolean use_pseudo_vcfs = true
    File? input_nuc_vcf
    File? input_mt_vcf

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
    String gotc_docker = "us.gcr.io/broad-gotc-prod/genomes-in-the-cloud:2.4.2-1552931386"
    String bcftools_docker = "quay.io/biocontainers/bcftools:1.17--h3cc50cf_1"
    String intertext = ""

    # Only run the full ProduceSelfReference task if true.
    Boolean run_full = false
    # Run split diagnostics (multi-image) if true.
    Boolean run_split = true
  }

  if (use_pseudo_vcfs) {
    call MakePseudoVcfs {
      input:
        sample_name = sample_name
    }
  }

  File mt_vcf_to_use = select_first([MakePseudoVcfs.mt_vcf, input_mt_vcf])
  File nuc_vcf_to_use = select_first([MakePseudoVcfs.nuc_vcf, input_nuc_vcf])

  call PreflightCheck {
    input:
      sample_name = sample_name,
      input_mt_vcf = mt_vcf_to_use,
      input_nuc_vcf = nuc_vcf_to_use,
      fa_renaming_script = fa_renaming_script,
      variant_bounds_script = variant_bounds_script,
      check_hom_overlap_script = check_hom_overlap_script
  }

  call ProbeDockerTools {
    input:
      genomes_cloud_docker = genomes_cloud_docker
  }

  call ProbeDockerTools as ProbeGotcDocker {
    input:
      genomes_cloud_docker = gotc_docker
  }

  call ProbeDockerTools as ProbeBcftoolsDocker {
    input:
      genomes_cloud_docker = bcftools_docker
  }

  if (run_split) {
    call BcftoolsFilterMt {
      input:
        mt_vcf = mt_vcf_to_use,
        bcftools_docker = bcftools_docker
    }

    call PicardSmokeTest {
      input:
        mt_ref_fasta = mt_ref_fasta,
        mt_ref_fasta_index = mt_ref_fasta_index,
        mt_interval_list = mt_interval_list,
        gotc_docker = gotc_docker
    }

    call RScriptSmokeTest {
      input:
        fa_renaming_script = fa_renaming_script,
        variant_bounds_script = variant_bounds_script,
        check_hom_overlap_script = check_hom_overlap_script,
        gotc_docker = gotc_docker
    }
  }

  if (run_full) {
    call MongoTasks_Single.MongoProduceSelfReference as ProduceSelfReference {
      input:
        sample_name = sample_name,
        input_nuc_vcf = nuc_vcf_to_use,
        input_mt_vcf = mt_vcf_to_use,
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
  }

  output {
    File preflight_report = PreflightCheck.report
    File docker_probe_report = ProbeDockerTools.report
    File gotc_probe_report = ProbeGotcDocker.report
    File bcftools_probe_report = ProbeBcftoolsDocker.report
    File mt_vcf_used = mt_vcf_to_use
    File nuc_vcf_used = nuc_vcf_to_use
    File? mt_vcf_filtered = BcftoolsFilterMt.filtered_mt_vcf
    File? mt_vcf_filtered_index = BcftoolsFilterMt.filtered_mt_vcf_index
    File? picard_dict = PicardSmokeTest.mt_dict
    File? r_script_report = RScriptSmokeTest.report

    File? mt_self = ProduceSelfReference.self_fasta
    File? mt_self_index = ProduceSelfReference.self_fasta_index
    File? mt_self_dict = ProduceSelfReference.self_dict
    File? mt_and_nuc_self = ProduceSelfReference.self_cat_fasta
    File? mt_and_nuc_self_index = ProduceSelfReference.self_cat_fasta_index
    File? mt_and_nuc_self_dict = ProduceSelfReference.self_cat_dict
    File? shifted_self = ProduceSelfReference.self_shifted_fasta
    File? shifted_self_index = ProduceSelfReference.self_shifted_fasta_index
    File? shifted_self_dict = ProduceSelfReference.self_shifted_dict
    File? lifted_mt_intervals = ProduceSelfReference.lifted_mt_intervals
    File? lifted_noncontrol_intervals = ProduceSelfReference.lifted_noncontrol_intervals
    File? lifted_control_intervals = ProduceSelfReference.lifted_control_intervals
    Int? nuc_variants_dropped = ProduceSelfReference.nuc_variants_dropped
    Int? mtdna_consensus_overlaps = ProduceSelfReference.mtdna_consensus_overlaps
    Int? nuc_consensus_overlaps = ProduceSelfReference.nuc_consensus_overlaps
  }
}

task MakePseudoVcfs {
  input {
    String sample_name
  }

  command <<<
    set -e

    cat > mt.vcf <<'EOF'
    ##fileformat=VCFv4.2
    ##contig=<ID=chrM>
    ##FORMAT=<ID=AF,Number=A,Type=Float,Description="Allele Frequency">
    #CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\t~{sample_name}
    chrM\t100\t.\tA\tG\t60\tPASS\t.\tGT:AF\t0/1:0.99
    EOF

    cat > nuc.vcf <<'EOF'
    ##fileformat=VCFv4.2
    ##contig=<ID=chr1>
    ##FORMAT=<ID=AF,Number=A,Type=Float,Description="Allele Frequency">
    #CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\t~{sample_name}
    chr1\t100\t.\tA\tC\t60\tPASS\t.\tGT:AF\t0/1:0.99
    EOF
  >>>

  output {
    File mt_vcf = "mt.vcf"
    File nuc_vcf = "nuc.vcf"
  }

  runtime {
    # Use a minimal image with /bin/bash to avoid container startup failures.
    docker: "ubuntu:22.04"
    memory: "1 GB"
  }
}

task PreflightCheck {
  input {
    String sample_name
    File input_mt_vcf
    File input_nuc_vcf
    File fa_renaming_script
    File variant_bounds_script
    File check_hom_overlap_script
  }

  command <<<
    set -e

    echo "# MongoProduceSelfReference preflight" > preflight_report.txt
    echo "sample_name=~{sample_name}" >> preflight_report.txt

    echo "## tool availability" >> preflight_report.txt
    for tool in java Rscript samtools bcftools python3; do
      if command -v ${tool} >/dev/null 2>&1; then
        echo "OK: ${tool} -> $(command -v ${tool})" >> preflight_report.txt
      else
        echo "MISSING: ${tool}" >> preflight_report.txt
      fi
    done

    echo "## script inputs" >> preflight_report.txt
    for f in "~{fa_renaming_script}" "~{variant_bounds_script}" "~{check_hom_overlap_script}"; do
      if [ -s "${f}" ]; then
        echo "OK: ${f} ($(wc -c < "${f}") bytes)" >> preflight_report.txt
      else
        echo "MISSING_OR_EMPTY: ${f}" >> preflight_report.txt
      fi
    done

    echo "## mt vcf checks" >> preflight_report.txt
    if grep -q '^#CHROM' "~{input_mt_vcf}"; then
      echo "OK: mt vcf header" >> preflight_report.txt
    else
      echo "MISSING: mt vcf header" >> preflight_report.txt
    fi
    if grep -q '^chrM' "~{input_mt_vcf}"; then
      echo "OK: mt vcf has chrM records" >> preflight_report.txt
    else
      echo "MISSING: mt vcf has no chrM records" >> preflight_report.txt
    fi
    mt_format=$(grep -v '^#' "~{input_mt_vcf}" | head -n1 | awk '{print $9}')
    if echo "${mt_format}" | awk -F":" '{for (i=1;i<=NF;i++) if ($i=="AF") found=1} END{exit found?0:1}'; then
      echo "OK: mt vcf FORMAT includes AF" >> preflight_report.txt
    else
      echo "MISSING: mt vcf FORMAT lacks AF" >> preflight_report.txt
    fi

    echo "## nuc vcf checks" >> preflight_report.txt
    if grep -q '^#CHROM' "~{input_nuc_vcf}"; then
      echo "OK: nuc vcf header" >> preflight_report.txt
    else
      echo "MISSING: nuc vcf header" >> preflight_report.txt
    fi
    nuc_format=$(grep -v '^#' "~{input_nuc_vcf}" | head -n1 | awk '{print $9}')
    if echo "${nuc_format}" | awk -F":" '{for (i=1;i<=NF;i++) if ($i=="AF") found=1} END{exit found?0:1}'; then
      echo "OK: nuc vcf FORMAT includes AF" >> preflight_report.txt
    else
      echo "MISSING: nuc vcf FORMAT lacks AF" >> preflight_report.txt
    fi
  >>>

  output {
    File report = "preflight_report.txt"
  }

  runtime {
    # Use a minimal image with /bin/bash to avoid container startup failures.
    docker: "ubuntu:22.04"
    memory: "1 GB"
  }
}

task ProbeDockerTools {
  input {
    String genomes_cloud_docker
  }

  command <<<
    set -e

    echo "# Docker tool probe" > docker_probe_report.txt
    echo "image=~{genomes_cloud_docker}" >> docker_probe_report.txt

    for tool in java Rscript samtools bcftools python3; do
      if command -v ${tool} >/dev/null 2>&1; then
        echo "OK: ${tool} -> $(command -v ${tool})" >> docker_probe_report.txt
        ${tool} --version >> docker_probe_report.txt 2>&1 || true
      else
        echo "MISSING: ${tool}" >> docker_probe_report.txt
      fi
    done
  >>>

  output {
    File report = "docker_probe_report.txt"
  }

  runtime {
    docker: genomes_cloud_docker
    memory: "1 GB"
  }
}

task BcftoolsFilterMt {
  input {
    File mt_vcf
    String bcftools_docker
  }

  command <<<
    set -e

    bgzip -c "~{mt_vcf}" > mt.vcf.gz
    tabix mt.vcf.gz
    bcftools view -Oz -i 'FORMAT/AF>0.95' mt.vcf.gz > mt.filtered.vcf.gz
    tabix mt.filtered.vcf.gz
  >>>

  output {
    File filtered_mt_vcf = "mt.filtered.vcf.gz"
    File filtered_mt_vcf_index = "mt.filtered.vcf.gz.tbi"
  }

  runtime {
    docker: bcftools_docker
    memory: "1 GB"
  }
}

task PicardSmokeTest {
  input {
    File mt_ref_fasta
    File mt_ref_fasta_index
    File mt_interval_list
    String gotc_docker
  }

  command <<<
    set -e

    java -jar /usr/gitc/picard.jar IntervalListTools \
      SORT=true I=~{mt_interval_list} O=internal_mt.interval_list

    java -jar /usr/gitc/picard.jar CreateSequenceDictionary \
      REFERENCE=~{mt_ref_fasta} \
      OUTPUT=mt_ref.dict

    samtools faidx ~{mt_ref_fasta}
  >>>

  output {
    File mt_dict = "mt_ref.dict"
  }

  runtime {
    docker: gotc_docker
    memory: "1 GB"
  }
}

task RScriptSmokeTest {
  input {
    File fa_renaming_script
    File variant_bounds_script
    File check_hom_overlap_script
    String gotc_docker
  }

  command <<<
    set -e

    echo "# R script probe" > r_script_report.txt
    for f in "~{fa_renaming_script}" "~{variant_bounds_script}" "~{check_hom_overlap_script}"; do
      if [ -s "${f}" ]; then
        echo "OK: ${f}" >> r_script_report.txt
      else
        echo "MISSING_OR_EMPTY: ${f}" >> r_script_report.txt
      fi
    done
    Rscript --vanilla -e 'cat("R_OK\n")' >> r_script_report.txt
  >>>

  output {
    File report = "r_script_report.txt"
  }

  runtime {
    docker: gotc_docker
    memory: "1 GB"
  }
}

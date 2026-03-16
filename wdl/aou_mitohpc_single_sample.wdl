version 1.0

workflow AoUMitoHPCSingleSample {
  input {
    String sample_name
    File wgs_aligned_input_cram
    File wgs_aligned_input_cram_index

    File ref_fasta
    File ref_fasta_index
    File ref_dict

    String numt_regions = "chr1:629084-634672 chr17:22521208-22521639"
    String requester_pays_project = "terra-vpc-sc-17dda7e1"

    Int subsample_mt_reads = 222000
    Int iterations = 2
    Int min_dp = 50
    Int n_cpu = 4
    Int memory_gb = 16
    String mito_caller = "mutect2"
    String docker = "dpuiu1/mitohpc:latest"
  }

  call RunAoUMitoHPCSingleSample {
    input:
      sample_name = sample_name,
      wgs_aligned_input_cram = wgs_aligned_input_cram,
      wgs_aligned_input_cram_index = wgs_aligned_input_cram_index,
      ref_fasta = ref_fasta,
      ref_fasta_index = ref_fasta_index,
      ref_dict = ref_dict,
      numt_regions = numt_regions,
      requester_pays_project = requester_pays_project,
      subsample_mt_reads = subsample_mt_reads,
      iterations = iterations,
      min_dp = min_dp,
      n_cpu = n_cpu,
      memory_gb = memory_gb,
      mito_caller = mito_caller,
      docker = docker
  }

  output {
    File output_bundle = RunAoUMitoHPCSingleSample.output_bundle
    File count_tab = RunAoUMitoHPCSingleSample.count_tab
    File cvg_tab = RunAoUMitoHPCSingleSample.cvg_tab
    File sample_count = RunAoUMitoHPCSingleSample.sample_count
    File sample_cvg_stat = RunAoUMitoHPCSingleSample.sample_cvg_stat
    File first_pass_vcf = RunAoUMitoHPCSingleSample.first_pass_vcf
    File second_pass_vcf = RunAoUMitoHPCSingleSample.second_pass_vcf
    File haplogroup_tab = RunAoUMitoHPCSingleSample.haplogroup_tab
    File haplocheck_tab = RunAoUMitoHPCSingleSample.haplocheck_tab
  }
}

task RunAoUMitoHPCSingleSample {
  input {
    String sample_name
    File wgs_aligned_input_cram
    File wgs_aligned_input_cram_index

    File ref_fasta
    File ref_fasta_index
    File ref_dict

    String numt_regions
    String requester_pays_project

    Int subsample_mt_reads
    Int iterations
    Int min_dp
    Int n_cpu
    Int memory_gb
    String mito_caller
    String docker
  }

  Int disk_gb = ceil(size(wgs_aligned_input_cram, "GB")) + ceil(size(ref_fasta, "GB")) + 80

  command <<<
    set -euo pipefail

    export HP_SDIR=/MitoHPC/scripts
    export HP_HDIR=/MitoHPC
    export HP_BDIR=/MitoHPC/bin
    export HP_JDIR=/MitoHPC/java
    export PATH="${HP_SDIR}:${HP_BDIR}:$PATH"

    . /MitoHPC/scripts/init.sh

    export HP_RDIR="$PWD/ref"
    export HP_RNAME=hs38DH
    export HP_RMT=chrM
    export HP_RNUMT="~{numt_regions}"
    export HP_RCOUNT=3366

    export HP_O=Human
    export HP_MT=chrM
    export HP_MTC=chrMC
    export HP_MTR=chrMR
    export HP_MTLEN=16569
    export HP_NUMT=NUMT

    export HP_CN=1
    export HP_E=300
    export HP_L=~{subsample_mt_reads}
    export HP_M=~{mito_caller}
    export HP_I=~{iterations}
    export HP_T1=03
    export HP_T2=05
    export HP_T3=10
    export HP_DP=~{min_dp}
    export HP_V=
    export HP_GOPT=
    export HP_DOPT="--removeDups"
    export HP_FOPT="-q 15 -e 0"
    export HP_P=~{n_cpu}
    export HP_MM="~{memory_gb}G"
    export HP_JOPT="-Xms~{memory_gb}G -Xmx~{memory_gb}G -XX:ParallelGCThreads=~{n_cpu}"
    export HP_SH=bash
    export HP_SHS=bash
    export HP_FRULE="perl -ane 'print unless(/strict_strand|strand_bias|base_qual|map_qual|weak_evidence|slippage|position|Homopolymer/ and /:0\\.[01234]\\d+\$/);' | bcftools filter -e 'DP<~{min_dp}'"

    export HP_ODIR="$PWD/out"
    export HP_IN="$PWD/in.txt"

    mkdir -p "$HP_RDIR" "$HP_ODIR/~{sample_name}"

    for pattern in "*.bed.gz" "*.bed.gz.tbi" "*.vcf.gz" "*.vcf.gz.tbi"; do
      for f in /MitoHPC/RefSeq/${pattern}; do
        if [ -e "$f" ]; then
          ln -sf "$f" "$HP_RDIR/$(basename "$f")"
        fi
      done
    done

    cp "~{ref_fasta}" "$HP_RDIR/${HP_RNAME}.fa"
    cp "~{ref_fasta_index}" "$HP_RDIR/${HP_RNAME}.fa.fai"
    cp "~{ref_dict}" "$HP_RDIR/${HP_RNAME}.dict"

    cp "~{wgs_aligned_input_cram}" input.cram
    cp "~{wgs_aligned_input_cram_index}" input.cram.crai

    samtools faidx "$HP_RDIR/${HP_RNAME}.fa" "$HP_RMT" > "$HP_RDIR/${HP_MT}.fa"
    samtools faidx "$HP_RDIR/${HP_MT}.fa"
    java $HP_JOPT -jar $HP_JDIR/gatk.jar CreateSequenceDictionary \
      --REFERENCE "$HP_RDIR/${HP_MT}.fa" \
      --OUTPUT "$HP_RDIR/${HP_MT}.dict"

    samtools faidx "$HP_RDIR/${HP_RNAME}.fa" $HP_RNUMT > "$HP_RDIR/${HP_NUMT}.fa"
    bwa index "$HP_RDIR/${HP_NUMT}.fa" -p "$HP_RDIR/${HP_NUMT}"

    circFasta.sh "$HP_MT" "$HP_RDIR/${HP_MT}" "$HP_E" "$HP_RDIR/${HP_MTC}"
    rotateFasta.sh "$HP_MT" "$HP_RDIR/${HP_MT}" "$HP_E" "$HP_RDIR/${HP_MTR}"

    printf "%s\t%s\t%s\n" "~{sample_name}" "$PWD/input.cram" "$HP_ODIR/~{sample_name}/~{sample_name}" > "$HP_IN"

    /MitoHPC/scripts/filter.sh "~{sample_name}" "$PWD/input.cram" "$HP_ODIR/~{sample_name}/~{sample_name}"
    /MitoHPC/scripts/getSummary.sh "$HP_ODIR"

    tar -czf "~{sample_name}.mitohpc.outputs.tgz" out
  >>>

  runtime {
    docker: docker
    cpu: n_cpu
    memory: memory_gb + " GB"
    disks: "local-disk " + disk_gb + " HDD"
  }

  output {
    File output_bundle = "~{sample_name}.mitohpc.outputs.tgz"
    File count_tab = "out/count.tab"
    File cvg_tab = "out/cvg.tab"
    File sample_count = "out/~{sample_name}/~{sample_name}.count"
    File sample_cvg_stat = "out/~{sample_name}/~{sample_name}.cvg.stat"
    File first_pass_vcf = "out/~{sample_name}/~{sample_name}.~{mito_caller}.00.vcf"
    File second_pass_vcf = "out/~{sample_name}/~{sample_name}.~{mito_caller}.~{mito_caller}.00.vcf"
    File haplogroup_tab = "out/~{mito_caller}.haplogroup.tab"
    File haplocheck_tab = "out/~{mito_caller}.haplocheck.tab"
  }
}

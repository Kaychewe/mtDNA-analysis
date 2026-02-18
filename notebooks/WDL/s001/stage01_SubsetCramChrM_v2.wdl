version 1.0

workflow stage01_SubsetCramChrM {
  meta {
    description: "Stage01 (comprehensive): subset to chrM + NUMT, clean, mark duplicates, and emit BAM/BAI/SAM."
  }

  input {
    File input_cram
    File? input_crai
    String sample_id
    String? age
    String? sex

    File mt_interval_list
    File numt_interval_list
    File ref_fasta
    File ref_fasta_index
    File ref_dict

    String docker

    Int? mem_gb
    Int? n_cpu
    Int? preemptible_tries
    String? requester_pays_project
  }

  call SubsetAndProcessChrM {
    input:
      input_cram = input_cram,
      input_crai = input_crai,
      sample_id = sample_id,
      age = age,
      sex = sex,
      mt_interval_list = mt_interval_list,
      numt_interval_list = numt_interval_list,
      ref_fasta = ref_fasta,
      ref_fasta_index = ref_fasta_index,
      ref_dict = ref_dict,
      docker = docker,
      mem_gb = mem_gb,
      n_cpu = n_cpu,
      preemptible_tries = preemptible_tries,
      requester_pays_project = requester_pays_project
  }

  output {
    File final_bam = SubsetAndProcessChrM.final_bam
    File final_bai = SubsetAndProcessChrM.final_bai
    File final_sam = SubsetAndProcessChrM.final_sam
    File unmapped_bam = SubsetAndProcessChrM.unmapped_bam
    File duplicate_metrics = SubsetAndProcessChrM.duplicate_metrics
    Int reads_dropped = SubsetAndProcessChrM.reads_dropped
    Int mean_coverage = SubsetAndProcessChrM.mean_coverage
  }
}

task SubsetAndProcessChrM {
  input {
    File input_cram
    File? input_crai
    String sample_id
    String? age
    String? sex

    File mt_interval_list
    File numt_interval_list
    File ref_fasta
    File ref_fasta_index
    File ref_dict

    String docker

    Int? mem_gb
    Int? n_cpu
    Int? preemptible_tries
    String? requester_pays_project
  }

  String age_label = select_first([age, "NA"])
  String sex_label = select_first([sex, "NA"])
  String prefix = sample_id + "_" + age_label + "_" + sex_label + "_chrM"

  Float ref_size = size(ref_fasta, "GB") + size(ref_fasta_index, "GB") + size(ref_dict, "GB")
  Int disk_size = ceil(ref_size) + ceil(size(input_cram, "GB")) + 20
  Int machine_mem = select_first([mem_gb, 8])
  Int command_mem = (machine_mem * 1000) - 500
  String appended_crai = input_cram + ".crai"

  String d = "$"

  command <<<
    set -euo pipefail

    mkdir -p out

    this_cram="~{input_cram}"
    this_crai="~{select_first([input_crai, appended_crai])}"

    echo "STEP 1: Subset CRAM to chrM + NUMT (PrintReads)"
    gatk --java-options "-Xmx~{command_mem}m" PrintReads       -R ~{ref_fasta}       -L ~{mt_interval_list}       -L ~{numt_interval_list}       ~{"--gcs-project-for-requester-pays " + requester_pays_project}       -I ~{d}{this_cram} --read-index ~{d}{this_crai}       -O "out/~{prefix}.bam"

    echo "STEP 2: Validate + remove broken mates"
    set +e
    gatk --java-options "-Xmx~{command_mem}m" ValidateSamFile       -INPUT "out/~{prefix}.bam"       -O output.txt       -M VERBOSE       -IGNORE_WARNINGS true       -MAX_OUTPUT 9999999
    cat output.txt |       grep "ERROR.*Mate not found for paired read" |       sed -e "s/ERROR::MATE_NOT_FOUND:Read name //g" |       sed -e "s/, Mate not found for paired read//g" > read_list.txt
    cat read_list.txt | wc -l | sed "s/^ *//g" > "out/~{prefix}.ct_failed.txt"
    if [[ $(tr -d "\r\n" < read_list.txt|wc -c) -eq 0 ]]; then
      cp "out/~{prefix}.bam" rescued.bam
    else
      gatk --java-options "-Xmx~{command_mem}m" FilterSamReads         -I "out/~{prefix}.bam"         -O rescued.bam         -READ_LIST_FILE read_list.txt         -FILTER excludeReadList
    fi
    set -e

    echo "STEP 2.5: Remove malformed XQ tag"
    samtools view -h rescued.bam       | sed 's/\tXQ:i:[0-9]\+//g'       | samtools view -b -o cleaned.bam

    echo "STEP 3: Revert to unmapped (cleaned)"
    gatk --java-options "-Xmx~{command_mem}m" RevertSam       -INPUT cleaned.bam       -OUTPUT_BY_READGROUP false       -OUTPUT "out/~{prefix}.unmap.bam"       -VALIDATION_STRINGENCY LENIENT       -ATTRIBUTE_TO_CLEAR FT       -ATTRIBUTE_TO_CLEAR CO       -ATTRIBUTE_TO_CLEAR XQ       -SORT_ORDER queryname       -RESTORE_ORIGINAL_QUALITIES false

    echo "STEP 4: Collect WGS metrics"
    gatk --java-options "-Xmx~{command_mem}m" CollectWgsMetrics       INPUT="out/~{prefix}.bam"       INTERVALS=~{mt_interval_list}       VALIDATION_STRINGENCY=SILENT       REFERENCE_SEQUENCE=~{ref_fasta}       OUTPUT="out/~{prefix}.wgs_metrics.txt"       USE_FAST_ALGORITHM=true       READ_LENGTH=151       COVERAGE_CAP=100000       INCLUDE_BQ_HISTOGRAM=true       THEORETICAL_SENSITIVITY_OUTPUT="out/~{prefix}.theoretical_sensitivity.txt"

    R --vanilla <<CODE
      df = read.table("out/~{prefix}.wgs_metrics.txt",skip=6,header=TRUE,stringsAsFactors=FALSE,sep='\t',nrows=1)
      write.table(floor(df[,"MEAN_COVERAGE"]), "out/~{prefix}.mean_coverage.txt", quote=F, col.names=F, row.names=F)
    CODE

    echo "STEP 5: Mark duplicates"
    gatk --java-options "-Xmx~{command_mem}m" MarkDuplicates       INPUT="out/~{prefix}.bam"       OUTPUT=md.bam       METRICS_FILE="out/~{prefix}.duplicate.metrics"       VALIDATION_STRINGENCY=SILENT       OPTICAL_DUPLICATE_PIXEL_DISTANCE=2500       ASSUME_SORT_ORDER="queryname"       CLEAR_DT="false"       ADD_PG_TAG_TO_READS=false

    echo "STEP 6: Sort + index"
    gatk --java-options "-Xmx~{command_mem}m" SortSam       INPUT=md.bam       OUTPUT="out/~{prefix}.proc.bam"       SORT_ORDER="coordinate"       CREATE_INDEX=true       MAX_RECORDS_IN_RAM=300000

    echo "STEP 7: Export SAM"
    samtools view -h "out/~{prefix}.proc.bam" > "out/~{prefix}.proc.sam"
  >>>

  runtime {
    memory: machine_mem + " GB"
    disks: "local-disk " + disk_size + " HDD"
    docker: docker
    preemptible: select_first([preemptible_tries, 5])
    cpu: select_first([n_cpu, 1])
  }

  output {
    File final_bam = "out/~{prefix}.proc.bam"
    File final_bai = "out/~{prefix}.proc.bai"
    File final_sam = "out/~{prefix}.proc.sam"
    File unmapped_bam = "out/~{prefix}.unmap.bam"
    File duplicate_metrics = "out/~{prefix}.duplicate.metrics"
    Int reads_dropped = read_int("out/~{prefix}.ct_failed.txt")
    Int mean_coverage = read_int("out/~{prefix}.mean_coverage.txt")
  }
}

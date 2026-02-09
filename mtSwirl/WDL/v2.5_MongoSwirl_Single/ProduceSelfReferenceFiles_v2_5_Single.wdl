version 1.0

import "LiftoverTools_v2_5_Single.wdl" as LiftoverTools_Single
import "MongoTasks_v2_5_Single.wdl" as MongoTasks_Single

workflow ProduceSelfReferenceFiles {
  # Running bcftools consensus when an interval file was used upstream to subset the genome
  #  is problematic because the consensus now is a fasta file with blocks per interval,
  #  indexed to 1 as the first base in each interval (so chr1 65000-65050 NUMT -> NUMT 1-51).
  #
  # See documentation for ProduceSelfReference for how we resolve this -- namely,
  #  we manually change the name for each interval to chr#:start-end from the interval file definition.
  #  This results in bcftools consensus producing files that are properly indexed to genomic coordinates,
  #  critical for getting variants in the VCF to apply to the fasta.
  #
  # However this also produces a problem -- the rest of our machinery assumes that nucDNA segments are
  #  1-indexed. This is important because it is not clear that the GATK/Picard tools
  #  can infer positional subsets of genomes based on a FASTA header, and we don't want to carry around
  #  the entire human genome sequence so we want to produce FASTAs with just subsets of the genome. Thus we
  #  revert the renaming within ProduceSelfReference after variants are successfully applied. 
  #
  # We then use CreateSpanIntervalsWithDict to "lift over" the nucDNA and mtDNA intervals files 
  #  by producing the exactly correct intervals that cover each entire region in the consensus FASTA dict (1-indexed).
  #
  # Finally we have to fix the chain files outputted from ProduceSelfReference which
  #  still use genomic coordinates. To do this we use MoveChainToZero, which renames
  #  and shifts each chain file block backwards such that it starts at 0 (correct for 1-indexed regions).
  #
  # In sum here we produce reference files such that variants are applied appropriately
  #  even when we have multiple intervals that do not all start at position 1 of the chromosome.
  #  Outputted files produce "contigs" for each interval, 1-indexed to the start of the interval and not the actual chromosome.
  #  This part is only supported for nucDNA intervals. The machinery is ready for mtDNA intervals but not tested -- we do not support analysis on subsets of the mtDNA.
  meta {
    description: "Produces all relevant self-reference files for version 2.2 of MitochondriaPipeline."
  }

  input {
    String sample_name
    String suffix

    File mt_dict
    File mt_fasta
    File mt_fasta_index
    File mt_interval_list
    File non_control_region_interval_list

    File ref_dict
    File ref_fasta
    File ref_fasta_index
    File nuc_interval_list
    String reference_name = "reference"

    File blacklisted_sites
    File blacklisted_sites_index

    Int n_shift = 8000

    File nuc_variants
    File mtdna_variants

    Boolean compute_numt_coverage
    File FaRenamingScript
    File CheckVariantBoundsScript
    File CheckHomOverlapScript

    File bcftools_bundle

    #Optional runtime arguments
    Int? preemptible_tries
    String genomes_cloud_docker
    String bcftools_docker = genomes_cloud_docker
    String gotc_docker
    String ucsc_docker
  }

  call PrepIntervalsAndRenamedFastas {
    input:
      mt_interval_list = mt_interval_list,
      nuc_interval_list = nuc_interval_list,
      mt_ref_fasta = mt_fasta,
      ref_fasta = ref_fasta,
      fa_renaming_script = FaRenamingScript,
      gotc_docker = gotc_docker,
      preemptible_tries = preemptible_tries
  }

  call FilterMtVcf {
    input:
      input_mt_vcf = mtdna_variants,
      sample_name = sample_name,
      bcftools_docker = bcftools_docker,
      bcftools_bundle = bcftools_bundle
  }

  call DetectMtOverlaps {
    input:
      sample_name = sample_name,
      mt_vcf = FilterMtVcf.filtered_mt_vcf,
      nuc_vcf = nuc_variants,
      check_hom_overlap_script = CheckHomOverlapScript,
      gotc_docker = gotc_docker,
      preemptible_tries = preemptible_tries
  }

  call RemoveMtOverlaps {
    input:
      sample_name = sample_name,
      mt_vcf_gz = FilterMtVcf.filtered_mt_vcf_gz,
      mt_vcf_gz_tbi = FilterMtVcf.filtered_mt_vcf_gz_tbi,
      overlaps_vcf = DetectMtOverlaps.overlaps_vcf,
      bcftools_docker = bcftools_docker,
      bcftools_bundle = bcftools_bundle
  }

  call ValidateMtOverlaps {
    input:
      mt_vcf = RemoveMtOverlaps.cleaned_mt_vcf,
      nuc_vcf = nuc_variants,
      check_hom_overlap_script = CheckHomOverlapScript,
      gotc_docker = gotc_docker,
      preemptible_tries = preemptible_tries
  }

  call NucVariantBounds {
    input:
      nuc_vcf = nuc_variants,
      nuc_interval_list = PrepIntervalsAndRenamedFastas.internal_nuc_interval_list,
      variant_bounds_script = CheckVariantBoundsScript,
      gotc_docker = gotc_docker,
      preemptible_tries = preemptible_tries
  }

  call FilterNucVcf {
    input:
      sample_name = sample_name,
      nuc_vcf = nuc_variants,
      rejected_nuc_vcf = NucVariantBounds.rejected_nuc_vcf,
      bcftools_docker = bcftools_docker,
      bcftools_bundle = bcftools_bundle
  }

  call MtConsensus {
    input:
      sample_name = sample_name,
      suffix = suffix,
      mt_fasta_renamed = PrepIntervalsAndRenamedFastas.mt_fasta_renamed,
      mt_vcf_gz = RemoveMtOverlaps.cleaned_mt_vcf_gz,
      bcftools_docker = bcftools_docker,
      bcftools_bundle = bcftools_bundle
  }

  call FinalizeMtFasta {
    input:
      sample_name = sample_name,
      suffix = suffix,
      mt_fasta_lifted = MtConsensus.mt_fasta_lifted,
      internal_mt_interval_list = PrepIntervalsAndRenamedFastas.internal_mt_interval_list,
      fa_renaming_script = FaRenamingScript,
      gotc_docker = gotc_docker,
      preemptible_tries = preemptible_tries
  }

  call NucConsensus {
    input:
      sample_name = sample_name,
      suffix = suffix,
      nuc_fasta_renamed = PrepIntervalsAndRenamedFastas.nuc_fasta_renamed,
      nuc_vcf_gz = FilterNucVcf.filtered_nuc_vcf_gz,
      bcftools_docker = bcftools_docker,
      bcftools_bundle = bcftools_bundle
  }

  call FinalizeNucFastas {
    input:
      sample_name = sample_name,
      suffix = suffix,
      nuc_fasta_lifted = NucConsensus.nuc_fasta_lifted,
      internal_nuc_interval_list = PrepIntervalsAndRenamedFastas.internal_nuc_interval_list,
      fa_renaming_script = FaRenamingScript,
      mt_fasta = FinalizeMtFasta.mt_fasta,
      gotc_docker = gotc_docker,
      preemptible_tries = preemptible_tries
  }

  call ShiftMtReference {
    input:
      sample_name = sample_name,
      suffix = suffix,
      mt_fasta = FinalizeMtFasta.mt_fasta,
      nuc_only_fasta = FinalizeNucFastas.nuc_only_fasta,
      n_shift = n_shift,
      gotc_docker = gotc_docker,
      preemptible_tries = preemptible_tries
  }

  call LiftIntervals {
    input:
      sample_name = sample_name,
      mt_interval_list = mt_interval_list,
      non_control_region_interval_list = non_control_region_interval_list,
      mt_dict = FinalizeMtFasta.mt_dict,
      shifted_mt_dict = ShiftMtReference.shifted_mt_dict,
      mt_chain = MtConsensus.mt_chain,
      n_shift = n_shift,
      gotc_docker = gotc_docker,
      preemptible_tries = preemptible_tries
  }

  call ForceCallVcfs {
    input:
      sample_name = sample_name,
      suffix = suffix,
      mt_vcf = RemoveMtOverlaps.cleaned_mt_vcf,
      mt_fasta = FinalizeMtFasta.mt_fasta,
      mt_fasta_index = FinalizeMtFasta.mt_fasta_index,
      mt_ref_fasta = mt_fasta,
      mt_ref_fasta_index = mt_fasta_index,
      mt_chain = MtConsensus.mt_chain,
      shift_forward_chain = ShiftMtReference.shift_forward_chain,
      shifted_mt_fasta = ShiftMtReference.shifted_mt_fasta,
      genomes_cloud_docker = genomes_cloud_docker,
      preemptible_tries = preemptible_tries
  }

  call MongoTasks_Single.MongoChainSwapLiftoverBed as ChainSwapLiftoverBed {
    input:
      source_chain = MtConsensus.mt_chain,
      input_target_name = sample_name,

      input_source_name = reference_name,
      input_bed = blacklisted_sites,
      input_bed_index = blacklisted_sites_index,
      ucsc_docker = ucsc_docker,
      preemptible_tries = preemptible_tries
  }

  if (compute_numt_coverage) {
    call CreateSpanIntervalsWithDict as LiftOverNucReference {
      input:
        input_intervals = nuc_interval_list,
        target_dict = FinalizeNucFastas.nuc_mt_dict,
        intertext = '.nuc',
        gotc_docker = gotc_docker,
        preemptible_tries = preemptible_tries
    }

    call CreateSpanIntervalsWithDict as LiftOverNucReferenceShifted {
      input:
        input_intervals = nuc_interval_list,
        target_dict = ShiftMtReference.shifted_cat_dict,
        intertext = '.nuc.shifted',
        gotc_docker = gotc_docker,
        preemptible_tries = preemptible_tries
    }

    call LiftoverTools_Single.ChainSwap as SelfToRefNucLiftoverChain {
      input:
        source_chain = NucConsensus.nuc_chain,
        input_source_name = reference_name,
        input_target_name = sample_name + "_nuc",
        ucsc_docker = ucsc_docker,
        preemptible_tries = preemptible_tries
    }

    call MoveChainToZero {
      input:
        source_chain = SelfToRefNucLiftoverChain.chain,
        ref_intervals = nuc_interval_list,
        gotc_docker = gotc_docker,
        preemptible_tries = preemptible_tries
    }
  }

  output {
    File mt_self = FinalizeMtFasta.mt_fasta
    File mt_self_index = FinalizeMtFasta.mt_fasta_index
    File mt_self_dict = FinalizeMtFasta.mt_dict

    File mt_shifted_self = ShiftMtReference.shifted_mt_fasta
    File mt_shifted_self_index = ShiftMtReference.shifted_mt_fasta_index
    File mt_shifted_self_dict = ShiftMtReference.shifted_mt_dict

    File ref_to_self_chain = MtConsensus.mt_chain
    File self_to_ref_chain = ChainSwapLiftoverBed.chain
    File self_shift_back_chain = ShiftMtReference.shift_back_chain
    File? nuc_self_to_ref_chain = MoveChainToZero.chain

    File mt_andNuc_self = FinalizeNucFastas.nuc_mt_fasta
    File mt_andNuc_self_index = FinalizeNucFastas.nuc_mt_fasta_index
    File mt_andNuc_self_dict = FinalizeNucFastas.nuc_mt_dict

    File mt_andNuc_shifted_self = ShiftMtReference.shifted_cat_fasta
    File mt_andNuc_shifted_self_index = ShiftMtReference.shifted_cat_fasta_index
    File mt_andNuc_shifted_self_dict = ShiftMtReference.shifted_cat_dict

    File ref_homoplasmies_vcf = RemoveMtOverlaps.cleaned_mt_vcf
    File force_call_vcf = ForceCallVcfs.reversed_hom_vcf
    File force_call_vcf_idx = ForceCallVcfs.reversed_hom_vcf_idx
    File force_call_vcf_filters = ForceCallVcfs.reversed_hom_filters_vcf
    File force_call_vcf_filters_idx = ForceCallVcfs.reversed_hom_filters_vcf_idx
    File force_call_vcf_shifted = ForceCallVcfs.reversed_hom_vcf_shifted
    File force_call_vcf_shifted_idx = ForceCallVcfs.reversed_hom_vcf_shifted_idx

    File mt_interval_list_self = LiftIntervals.lifted_mt_intervals
    File? nuc_interval_list_self = LiftOverNucReference.lifted_intervals
    File? nuc_interval_list_shifted_self = LiftOverNucReferenceShifted.lifted_intervals
    File blacklisted_sites_self = ChainSwapLiftoverBed.transformed_bed
    File blacklisted_sites_index_self = ChainSwapLiftoverBed.transformed_bed_index
    File non_control_interval_self = LiftIntervals.lifted_noncontrol_intervals
    File control_shifted_self = LiftIntervals.lifted_control_intervals

    Int nuc_variants_dropped = FilterNucVcf.nuc_variants_dropped
    Int mtdna_consensus_overlaps = DetectMtOverlaps.mtdna_consensus_overlaps
    Int nuc_consensus_overlaps = DetectMtOverlaps.nuc_consensus_overlaps
  }
}

task PrepIntervalsAndRenamedFastas {
  input {
    File mt_interval_list
    File nuc_interval_list
    File mt_ref_fasta
    File ref_fasta
    File fa_renaming_script
    String gotc_docker
    Int? preemptible_tries
  }

  command <<<
    java -jar /usr/gitc/picard.jar IntervalListTools SORT=true I=~{mt_interval_list} O=internal_mt.interval_list
    java -jar /usr/gitc/picard.jar IntervalListTools SORT=true I=~{nuc_interval_list} O=internal_nuc.interval_list

    java -jar /usr/gitc/picard.jar ExtractSequences \
      INTERVAL_LIST=internal_mt.interval_list \
      R=~{mt_ref_fasta} \
      O=mt_fasta.fasta
    Rscript --vanilla ~{fa_renaming_script} mt_fasta.fasta internal_mt.interval_list FALSE mt_fasta_renamed.fasta TRUE
    samtools faidx mt_fasta_renamed.fasta

    java -jar /usr/gitc/picard.jar ExtractSequences \
      INTERVAL_LIST=internal_nuc.interval_list \
      R=~{ref_fasta} \
      O=nuc_fasta.fasta
    Rscript --vanilla ~{fa_renaming_script} nuc_fasta.fasta internal_nuc.interval_list FALSE nuc_fasta_renamed.fasta FALSE
    samtools faidx nuc_fasta_renamed.fasta
  >>>

  output {
    File internal_mt_interval_list = "internal_mt.interval_list"
    File internal_nuc_interval_list = "internal_nuc.interval_list"
    File mt_fasta_renamed = "mt_fasta_renamed.fasta"
    File mt_fasta_renamed_fai = "mt_fasta_renamed.fasta.fai"
    File nuc_fasta_renamed = "nuc_fasta_renamed.fasta"
    File nuc_fasta_renamed_fai = "nuc_fasta_renamed.fasta.fai"
  }

  runtime {
    memory: "2 GB"
    disks: "local-disk 20 HDD"
    docker: gotc_docker
    preemptible: select_first([preemptible_tries, 5])
  }
}

task FilterMtVcf {
  input {
    File input_mt_vcf
    String sample_name
    String bcftools_docker
    File bcftools_bundle
  }

  command <<<
    mkdir -p bcftools_bundle
    tar -xzf "~{bcftools_bundle}" -C bcftools_bundle
    export PATH="$PWD/bcftools_bundle/bin:$PATH"
    export LD_LIBRARY_PATH="$PWD/bcftools_bundle/lib:${LD_LIBRARY_PATH}"
    bgzip -c "~{input_mt_vcf}" > filtered_mt.vcf.gz
    tabix filtered_mt.vcf.gz
    bcftools view -Oz -i 'FORMAT/AF>0.95' filtered_mt.vcf.gz > filtered_mt.homoplasmies.vcf.gz
    tabix filtered_mt.homoplasmies.vcf.gz
    bgzip -cd filtered_mt.homoplasmies.vcf.gz > filtered_mt.homoplasmies.vcf
  >>>

  output {
    File filtered_mt_vcf = "filtered_mt.homoplasmies.vcf"
    File filtered_mt_vcf_gz = "filtered_mt.homoplasmies.vcf.gz"
    File filtered_mt_vcf_gz_tbi = "filtered_mt.homoplasmies.vcf.gz.tbi"
  }

  runtime {
    memory: "2 GB"
    disks: "local-disk 20 HDD"
    docker: bcftools_docker
  }
}

task DetectMtOverlaps {
  input {
    String sample_name
    File mt_vcf
    File nuc_vcf
    File check_hom_overlap_script
    String gotc_docker
    Int? preemptible_tries
  }

  command <<<
    Rscript --vanilla ~{check_hom_overlap_script} "~{sample_name}" "~{mt_vcf}" "~{nuc_vcf}" FALSE
  >>>

  output {
    File overlaps_vcf = "overlapping_variants_to_remove.vcf"
    Int mtdna_consensus_overlaps = read_int("~{sample_name}.mtdna_consensus_overlaps.txt")
    Int nuc_consensus_overlaps = read_int("~{sample_name}.nucdna_consensus_overlaps.txt")
  }

  runtime {
    memory: "1 GB"
    disks: "local-disk 10 HDD"
    docker: gotc_docker
    preemptible: select_first([preemptible_tries, 5])
  }
}

task RemoveMtOverlaps {
  input {
    String sample_name
    File mt_vcf_gz
    File mt_vcf_gz_tbi
    File overlaps_vcf
    String bcftools_docker
    File bcftools_bundle
  }

  command <<<
    mkdir -p bcftools_bundle
    tar -xzf "~{bcftools_bundle}" -C bcftools_bundle
    export PATH="$PWD/bcftools_bundle/bin:$PATH"
    export LD_LIBRARY_PATH="$PWD/bcftools_bundle/lib:${LD_LIBRARY_PATH}"
    bgzip -c "~{overlaps_vcf}" > mt_overlaps_rm.vcf.gz
    tabix mt_overlaps_rm.vcf.gz
    bcftools isec "~{mt_vcf_gz}" mt_overlaps_rm.vcf.gz -p output_isec
    export private_to_rem=$(cat ./output_isec/0001.vcf | grep ^chr | wc -l | sed 's/^ *//g')
    if [ $private_to_rem -ne 0 ]; then
      echo "ERROR: There should not be any variants private to the VCF for removal."
      exit 1;
    fi
    export shared_by_both=$(cat ./output_isec/0002.vcf | grep ^chr | wc -l | sed 's/^ *//g')
    export for_removal=$(cat "~{overlaps_vcf}" | grep ^chr | wc -l | sed 's/^ *//g')
    if [ $shared_by_both -ne $for_removal ]; then
      echo "ERROR: The number of variants shared by both rejected VCF and MT VCF should be the number of variants for removal."
      exit 1;
    fi
    export only_undupe=$(cat ./output_isec/0000.vcf | grep ^chr | wc -l | sed 's/^ *//g')
    export original_nrow=$(bgzip -cd "~{mt_vcf_gz}" | grep ^chr | wc -l | sed 's/^ *//g')
    if [ "$((original_nrow-for_removal))" -ne $only_undupe ]; then
      echo "ERROR: New VCF should be smaller than old VCF by the exact number of records for removal."
      exit 1;
    fi
    cp "output_isec/0000.vcf" cleaned_mt.vcf
    bgzip -c cleaned_mt.vcf > cleaned_mt.vcf.gz && tabix cleaned_mt.vcf.gz
  >>>

  output {
    File cleaned_mt_vcf = "cleaned_mt.vcf"
    File cleaned_mt_vcf_gz = "cleaned_mt.vcf.gz"
    File cleaned_mt_vcf_gz_tbi = "cleaned_mt.vcf.gz.tbi"
  }

  runtime {
    memory: "2 GB"
    disks: "local-disk 10 HDD"
    docker: bcftools_docker
  }
}

task ValidateMtOverlaps {
  input {
    File mt_vcf
    File nuc_vcf
    File check_hom_overlap_script
    String gotc_docker
    Int? preemptible_tries
  }

  command <<<
    Rscript --vanilla ~{check_hom_overlap_script} "temp" "~{mt_vcf}" "~{nuc_vcf}" TRUE
  >>>

  runtime {
    memory: "1 GB"
    disks: "local-disk 5 HDD"
    docker: gotc_docker
    preemptible: select_first([preemptible_tries, 5])
  }
}

task NucVariantBounds {
  input {
    File nuc_vcf
    File nuc_interval_list
    File variant_bounds_script
    String gotc_docker
    Int? preemptible_tries
  }

  command <<<
    Rscript --vanilla ~{variant_bounds_script} "~{nuc_vcf}" "~{nuc_interval_list}" rejected_nuc.vcf
  >>>

  output {
    File rejected_nuc_vcf = "rejected_nuc.vcf"
  }

  runtime {
    memory: "1 GB"
    disks: "local-disk 10 HDD"
    docker: gotc_docker
    preemptible: select_first([preemptible_tries, 5])
  }
}

task FilterNucVcf {
  input {
    String sample_name
    File nuc_vcf
    File rejected_nuc_vcf
    String bcftools_docker
    File bcftools_bundle
  }

  command <<<
    mkdir -p bcftools_bundle
    tar -xzf "~{bcftools_bundle}" -C bcftools_bundle
    export PATH="$PWD/bcftools_bundle/bin:$PATH"
    export LD_LIBRARY_PATH="$PWD/bcftools_bundle/lib:${LD_LIBRARY_PATH}"
    bgzip -c "~{nuc_vcf}" > input_nuc_vcf.gz && tabix input_nuc_vcf.gz
    bgzip -c "~{rejected_nuc_vcf}" > rejected_nuc.vcf.gz && tabix rejected_nuc.vcf.gz
    bcftools isec -p intersected_vcfs -Ov input_nuc_vcf.gz rejected_nuc.vcf.gz
    cat ./intersected_vcfs/0002.vcf | grep ^chr | wc -l | sed 's/^ *//g' > nuc.removed.txt
    cp ./intersected_vcfs/0000.vcf filtered_nuc.vcf
    bgzip -c filtered_nuc.vcf > filtered_nuc.vcf.gz && tabix filtered_nuc.vcf.gz
  >>>

  output {
    File filtered_nuc_vcf = "filtered_nuc.vcf"
    File filtered_nuc_vcf_gz = "filtered_nuc.vcf.gz"
    File filtered_nuc_vcf_gz_tbi = "filtered_nuc.vcf.gz.tbi"
    Int nuc_variants_dropped = read_int("nuc.removed.txt")
  }

  runtime {
    memory: "2 GB"
    disks: "local-disk 10 HDD"
    docker: bcftools_docker
  }
}

task MtConsensus {
  input {
    String sample_name
    String suffix
    File mt_fasta_renamed
    File mt_vcf_gz
    String bcftools_docker
    File bcftools_bundle
  }

  String mt_chain = "reference_to_" + sample_name + ".chain"

  command <<<
    mkdir -p bcftools_bundle
    tar -xzf "~{bcftools_bundle}" -C bcftools_bundle
    export PATH="$PWD/bcftools_bundle/bin:$PATH"
    export LD_LIBRARY_PATH="$PWD/bcftools_bundle/lib:${LD_LIBRARY_PATH}"
    mkdir -p out
    bcftools consensus -f "~{mt_fasta_renamed}" -o mt_fasta_lifted.fasta -c "~{mt_chain}" "~{mt_vcf_gz}"
    mv "~{mt_chain}" "out/~{mt_chain}"
  >>>

  output {
    File mt_fasta_lifted = "mt_fasta_lifted.fasta"
    File mt_chain = "out/reference_to_~{sample_name}.chain"
  }

  runtime {
    memory: "2 GB"
    disks: "local-disk 10 HDD"
    docker: bcftools_docker
  }
}

task FinalizeMtFasta {
  input {
    String sample_name
    String suffix
    File mt_fasta_lifted
    File internal_mt_interval_list
    File fa_renaming_script
    String gotc_docker
    Int? preemptible_tries
  }

  String mt_fasta = "out/" + sample_name + suffix + ".fasta"
  String mt_dict = "out/" + sample_name + suffix + ".dict"

  command <<<
    mkdir -p out
    Rscript --vanilla ~{fa_renaming_script} "~{mt_fasta_lifted}" "~{internal_mt_interval_list}" TRUE "~{mt_fasta}" TRUE
    java -jar /usr/gitc/picard.jar CreateSequenceDictionary REFERENCE="~{mt_fasta}" OUTPUT="~{mt_dict}"
    samtools faidx "~{mt_fasta}"
  >>>

  output {
    File mt_fasta = "out/~{sample_name}~{suffix}.fasta"
    File mt_fasta_index = "out/~{sample_name}~{suffix}.fasta.fai"
    File mt_dict = "out/~{sample_name}~{suffix}.dict"
  }

  runtime {
    memory: "2 GB"
    disks: "local-disk 10 HDD"
    docker: gotc_docker
    preemptible: select_first([preemptible_tries, 5])
  }
}

task NucConsensus {
  input {
    String sample_name
    String suffix
    File nuc_fasta_renamed
    File nuc_vcf_gz
    String bcftools_docker
    File bcftools_bundle
  }

  String nuc_chain = "reference_to_" + sample_name + "NucOnly.chain"

  command <<<
    mkdir -p bcftools_bundle
    tar -xzf "~{bcftools_bundle}" -C bcftools_bundle
    export PATH="$PWD/bcftools_bundle/bin:$PATH"
    export LD_LIBRARY_PATH="$PWD/bcftools_bundle/lib:${LD_LIBRARY_PATH}"
    mkdir -p out
    bcftools consensus -f "~{nuc_fasta_renamed}" -o nuc_fasta_lifted.fasta -c "~{nuc_chain}" "~{nuc_vcf_gz}"
    mv "~{nuc_chain}" "out/~{nuc_chain}"
  >>>

  output {
    File nuc_fasta_lifted = "nuc_fasta_lifted.fasta"
    File nuc_chain = "out/reference_to_~{sample_name}NucOnly.chain"
  }

  runtime {
    memory: "2 GB"
    disks: "local-disk 10 HDD"
    docker: bcftools_docker
  }
}

task FinalizeNucFastas {
  input {
    String sample_name
    String suffix
    File nuc_fasta_lifted
    File internal_nuc_interval_list
    File fa_renaming_script
    File mt_fasta
    String gotc_docker
    Int? preemptible_tries
  }

  String nuc_only_fasta = "out/" + sample_name + "NucOnly" + suffix + ".fasta"
  String nuc_only_dict = "out/" + sample_name + "NucOnly" + suffix + ".dict"
  String nuc_mt_fasta = "out/" + sample_name + "andNuc" + suffix + ".fasta"
  String nuc_mt_dict = "out/" + sample_name + "andNuc" + suffix + ".dict"

  command <<<
    mkdir -p out
    Rscript --vanilla ~{fa_renaming_script} "~{nuc_fasta_lifted}" "~{internal_nuc_interval_list}" TRUE "~{nuc_only_fasta}" FALSE
    cat "~{nuc_only_fasta}" "~{mt_fasta}" > "~{nuc_mt_fasta}"
    java -jar /usr/gitc/picard.jar CreateSequenceDictionary REFERENCE="~{nuc_mt_fasta}" OUTPUT="~{nuc_mt_dict}"
    samtools faidx "~{nuc_mt_fasta}"
    java -jar /usr/gitc/picard.jar CreateSequenceDictionary REFERENCE="~{nuc_only_fasta}" OUTPUT="~{nuc_only_dict}"
    samtools faidx "~{nuc_only_fasta}"
  >>>

  output {
    File nuc_only_fasta = "out/~{sample_name}NucOnly~{suffix}.fasta"
    File nuc_only_fasta_index = "out/~{sample_name}NucOnly~{suffix}.fasta.fai"
    File nuc_only_dict = "out/~{sample_name}NucOnly~{suffix}.dict"
    File nuc_mt_fasta = "out/~{sample_name}andNuc~{suffix}.fasta"
    File nuc_mt_fasta_index = "out/~{sample_name}andNuc~{suffix}.fasta.fai"
    File nuc_mt_dict = "out/~{sample_name}andNuc~{suffix}.dict"
  }

  runtime {
    memory: "2 GB"
    disks: "local-disk 10 HDD"
    docker: gotc_docker
    preemptible: select_first([preemptible_tries, 5])
  }
}

task ShiftMtReference {
  input {
    String sample_name
    String suffix
    File mt_fasta
    File nuc_only_fasta
    Int n_shift
    String gotc_docker
    Int? preemptible_tries
  }

  String shifted_fasta = "out/" + sample_name + suffix + ".shifted_by_" + n_shift + "_bases.fasta"
  String shifted_dict = "out/" + sample_name + suffix + ".shifted_by_" + n_shift + "_bases.dict"
  String shifted_cat_fasta = "out/" + sample_name + suffix + ".shifted_by_" + n_shift + "_bases.cat.fasta"
  String shifted_cat_dict = "out/" + sample_name + suffix + ".shifted_by_" + n_shift + "_bases.cat.dict"
  String shift_back_chain = "out/" + sample_name + suffix + ".shifted_by_" + n_shift + "_bases.shift_back_" + n_shift + "_bases.chain"
  String shift_forward_chain = "out/" + sample_name + suffix + ".shifted_by_" + n_shift + "_bases.shift_fwd_" + n_shift + "_bases.chain"

  command <<<
    mkdir -p out

    R --vanilla <<CODE
      full_fasta <- readLines("~{mt_fasta}")
      topline <- full_fasta[1]
      linelen <- nchar(full_fasta[2])
      n_shift <- ~{n_shift}
      other_lines <- paste0(full_fasta[2:length(full_fasta)],collapse='')
      other_lines_shifted <- paste0(substr(other_lines, n_shift+1, nchar(other_lines)), substr(other_lines, 1, n_shift))
      len_chr <- nchar(other_lines_shifted)
      shifted_split <- substring(other_lines_shifted, seq(1, len_chr, linelen), unique(c(seq(linelen, len_chr, linelen), len_chr)))
      final_data <- c(topline, shifted_split)
      writeLines(final_data, "~{shifted_fasta}")
      
      total_len <- nchar(other_lines)
      sec1 <- paste(c('chain',9999,'chrM',total_len,'+', 0,total_len-n_shift, 'chrM', total_len, '+', n_shift, total_len, 1),collapse=' ')
      sec2 <- paste(c('chain',9999,'chrM',total_len,'+', total_len-n_shift,total_len, 'chrM', total_len, '+', 0, n_shift, 2),collapse=' ')
      writeLines(c(sec1, total_len-n_shift, '', sec2, n_shift, ''), "~{shift_back_chain}")
      
      sec1_f <- paste(c('chain',9999,'chrM',total_len,'+', n_shift,total_len, 'chrM', total_len, '+', 0, total_len-n_shift, 1),collapse=' ')
      sec2_f <- paste(c('chain',9999,'chrM',total_len,'+', 0, n_shift, 'chrM', total_len, '+', total_len-n_shift, total_len, 2),collapse=' ')
      writeLines(c(sec1_f, total_len-n_shift, '', sec2_f, n_shift, ''), "~{shift_forward_chain}")
    CODE

    cat "~{shifted_fasta}" "~{nuc_only_fasta}" > "~{shifted_cat_fasta}"
    java -jar /usr/gitc/picard.jar CreateSequenceDictionary REFERENCE="~{shifted_cat_fasta}" OUTPUT="~{shifted_cat_dict}"
    samtools faidx "~{shifted_cat_fasta}"
    java -jar /usr/gitc/picard.jar CreateSequenceDictionary REFERENCE="~{shifted_fasta}" OUTPUT="~{shifted_dict}"
    samtools faidx "~{shifted_fasta}"
  >>>

  output {
    File shifted_mt_fasta = "out/~{sample_name}~{suffix}.shifted_by_~{n_shift}_bases.fasta"
    File shifted_mt_fasta_index = "out/~{sample_name}~{suffix}.shifted_by_~{n_shift}_bases.fasta.fai"
    File shifted_mt_dict = "out/~{sample_name}~{suffix}.shifted_by_~{n_shift}_bases.dict"
    File shift_back_chain = "out/~{sample_name}~{suffix}.shifted_by_~{n_shift}_bases.shift_back_~{n_shift}_bases.chain"
    File shift_forward_chain = "out/~{sample_name}~{suffix}.shifted_by_~{n_shift}_bases.shift_fwd_~{n_shift}_bases.chain"
    File shifted_cat_fasta = "out/~{sample_name}~{suffix}.shifted_by_~{n_shift}_bases.cat.fasta"
    File shifted_cat_fasta_index = "out/~{sample_name}~{suffix}.shifted_by_~{n_shift}_bases.cat.fasta.fai"
    File shifted_cat_dict = "out/~{sample_name}~{suffix}.shifted_by_~{n_shift}_bases.cat.dict"
  }

  runtime {
    memory: "2 GB"
    disks: "local-disk 10 HDD"
    docker: gotc_docker
    preemptible: select_first([preemptible_tries, 5])
  }
}

task LiftIntervals {
  input {
    String sample_name
    File mt_interval_list
    File non_control_region_interval_list
    File mt_dict
    File shifted_mt_dict
    File mt_chain
    Int n_shift
    String gotc_docker
    Int? preemptible_tries
  }

  String mt_intervals_basename = basename(mt_interval_list, ".interval_list")
  String noncontrol_basename = basename(non_control_region_interval_list, ".interval_list")
  String selfref_intervals_suffix = ".SelfRefLiftover.interval_list"
  String lifted_mt_intervals = "out/" + mt_intervals_basename + "." + sample_name + selfref_intervals_suffix
  String lifted_noncontrol = "out/" + noncontrol_basename + "." + sample_name + selfref_intervals_suffix
  String lifted_control = "out/control_region_shifted.chrM." + sample_name + selfref_intervals_suffix

  command <<<
    mkdir -p out

    R --vanilla <<CODE
      intervals <- readLines("~{mt_interval_list}")
      intervals <- intervals[grep('^@', intervals, invert=T)]
      interval_names <- sapply(strsplit(intervals, '\\t'),function(x)x[5])
      new_header <- readLines("~{mt_dict}")
      lens <- sapply(interval_names, function(x)as.numeric(gsub('LN:','',strsplit(new_header[grep(paste0('^@SQ\\tSN:',x), new_header)[1]], '\\t')[[1]][3])))
      if(any(is.na(lens))) stop('ERROR: Some NUMT intervals were not found in the mt_andNuc sequence dictionary.')
      new_intervals <- c(new_header, paste(interval_names, 1, lens, '+', interval_names, sep='\\t'))
      writeLines(new_intervals, "~{lifted_mt_intervals}")
    CODE

    java -jar /usr/gitc/picard.jar LiftOverIntervalList \
      I="~{non_control_region_interval_list}" \
      O="~{lifted_noncontrol}" \
      SD="~{mt_dict}" \
      CHAIN="~{mt_chain}"

    R --vanilla <<CODE
      full_intervals <- readLines("~{lifted_noncontrol}")
      correct_dict <- readLines("~{shifted_mt_dict}")
      n_shift <- ~{n_shift}
      if (length(full_intervals) > 3) {
        stop('ERROR: there should be only 3 lines in interval list.')
      }
      if ((length(grep('^@', full_intervals)) != 2) | (length(grep('^chrM', full_intervals)) != 1)) {
        stop('ERROR: there should be 2 comment lines and one interval line on chrM')
      }
      out_intervals <- c(full_intervals[1], correct_dict[2])
      split_line2 <- strsplit(out_intervals[2],'\\t')[[1]]
      this_len <- as.numeric(gsub('^LN:','',split_line2[grep('^LN', split_line2)[1]]))

      interval <- strsplit(full_intervals[3],'\\t')[[1]]
      new_end <- as.numeric(interval[2]) - 1 + this_len - n_shift
      new_start <- as.numeric(interval[3]) + 1 - n_shift
      interval[2:3] <- c(as.character(new_start), as.character(new_end))
      out_intervals <- c(out_intervals, paste0(interval, collapse='\\t'))

      writeLines(out_intervals, "~{lifted_control}")
    CODE
  >>>

  output {
    File lifted_mt_intervals = "~{lifted_mt_intervals}"
    File lifted_noncontrol_intervals = "~{lifted_noncontrol}"
    File lifted_control_intervals = "~{lifted_control}"
  }

  runtime {
    memory: "1 GB"
    disks: "local-disk 10 HDD"
    docker: gotc_docker
    preemptible: select_first([preemptible_tries, 5])
  }
}

task ForceCallVcfs {
  input {
    String sample_name
    String suffix
    File mt_vcf
    File mt_fasta
    File mt_fasta_index
    File mt_ref_fasta
    File mt_ref_fasta_index
    File mt_chain
    File shift_forward_chain
    File shifted_mt_fasta
    String genomes_cloud_docker
    Int? preemptible_tries
  }

  String this_vcf_bgz = "out/" + sample_name + suffix + ".reversed.selfRef.homoplasmies.vcf.bgz"
  String this_vcf_filters_bgz = "out/" + sample_name + suffix + ".reversed.withfilters.selfRef.homoplasmies.vcf.bgz"
  String this_vcf_shifted_bgz = "out/" + sample_name + suffix + ".reversed.selfRef.shifted.homoplasmies.vcf.bgz"

  command <<<
    mkdir -p out

    python3 <<CODE
    import hail as hl

    def fai_to_len(fai):
        with open(fai) as f:
            line = f.readline()
        return int(line.split('\\t')[1])

    def check_vcf_integrity(mt):
        if sorted(list(mt.row_key)) != ['alleles', 'locus']:
            raise ValueError('VCFs must always be keyed by locus, alleles.')
        if mt.aggregate_rows(~hl.agg.all(hl.len(mt.alleles) == 2)):
            raise ValueError('This function only supports biallelic sites (run SplitMultiAllelics!)')
        if mt.aggregate_rows(~hl.agg.all(hl.is_defined(mt.locus))):
            raise ValueError('ERROR: locus must always be defined.')
        if mt.aggregate_rows(~hl.agg.all(hl.all(hl.map(hl.is_defined, mt.alleles)))):
            raise ValueError('ERROR: alleles should always be defined.')

    def apply_conversion(mt, liftover_target, skip_flip=False):
        mt_lifted = mt.annotate_rows(new_locus = hl.liftover(mt.locus, liftover_target))
        if skip_flip:
          mt_lifted = mt_lifted.annotate_rows(allele_flip = mt_lifted.alleles)
        else:
          mt_lifted = mt_lifted.annotate_rows(allele_flip = hl.reversed(mt_lifted.alleles))
        mt_lifted = mt_lifted.key_rows_by().rename({'locus':'locus_orig', 'alleles':'alleles_orig'}).rename({'new_locus':'locus', 'allele_flip': 'alleles'}).key_rows_by('locus','alleles')
        mt_lifted = mt_lifted.drop('locus_orig', 'alleles_orig')
        return mt_lifted

    target = hl.ReferenceGenome("target_self", ['chrM'], {'chrM':fai_to_len("~{mt_fasta_index}")}, mt_contigs=['chrM'])
    source = hl.ReferenceGenome('mtGRCh38', ['chrM'], {'chrM':fai_to_len("~{mt_ref_fasta_index}")}, mt_contigs=['chrM'])
    target.add_sequence("~{mt_fasta}", "~{mt_fasta_index}")
    source.add_sequence("~{mt_ref_fasta}", "~{mt_ref_fasta_index}")
    source.add_liftover("~{mt_chain}", "target_self")
    shifted_target = hl.ReferenceGenome("target_self_shifted", ['chrM'], {'chrM':fai_to_len("~{shifted_mt_fasta}.fai")}, mt_contigs=['chrM'])
    shifted_target.add_sequence("~{shifted_mt_fasta}", "~{shifted_mt_fasta}.fai")
    target.add_liftover("~{shift_forward_chain}", shifted_target)

    mt_new = hl.import_vcf("~{mt_vcf}", reference_genome='mtGRCh38').select_entries()
    check_vcf_integrity(mt_new)

    mt_new_1 = mt_new.select_rows()
    mt_lifted_target = apply_conversion(mt_new_1, "target_self")
    check_vcf_integrity(mt_lifted_target)
    hl.export_vcf(mt_lifted_target, "~{this_vcf_bgz}", tabix=True)

    mt_new_2 = mt_new.select_rows('filters')
    this_metadata = hl.get_vcf_metadata("~{mt_vcf}")
    this_metadata = {'filter': this_metadata['filter']}
    mt_lifted_target_withfilter = apply_conversion(mt_new_2, "target_self")
    check_vcf_integrity(mt_lifted_target_withfilter)
    hl.export_vcf(mt_lifted_target_withfilter, "~{this_vcf_filters_bgz}", tabix=True, metadata=this_metadata)
    
    mt_lifted_shifted_target = apply_conversion(mt_lifted_target, "target_self_shifted", skip_flip=True)
    check_vcf_integrity(mt_lifted_shifted_target)
    hl.export_vcf(mt_lifted_shifted_target, "~{this_vcf_shifted_bgz}", tabix=True)
    CODE
  >>>

  output {
    File reversed_hom_vcf = "~{this_vcf_bgz}"
    File reversed_hom_vcf_idx = "~{this_vcf_bgz}.tbi"
    File reversed_hom_filters_vcf = "~{this_vcf_filters_bgz}"
    File reversed_hom_filters_vcf_idx = "~{this_vcf_filters_bgz}.tbi"
    File reversed_hom_vcf_shifted = "~{this_vcf_shifted_bgz}"
    File reversed_hom_vcf_shifted_idx = "~{this_vcf_shifted_bgz}.tbi"
  }

  runtime {
    docker: genomes_cloud_docker
    memory: "16 GB"
    disks: "local-disk 100 HDD"
    cpu: 4
    preemptible: select_first([preemptible_tries, 0])
  }
}

task CreateSpanIntervalsWithDict {
  input {
    File input_intervals
    File target_dict
    String intertext
    String gotc_docker

    Int? preemptible_tries
  }

  Float ref_size = size(target_dict, "GB")
  Int disk_size = ceil(size(input_intervals, "GB")*2 + ref_size)*2 + 10
  String output_intervals = basename(input_intervals, ".interval_list") + intertext + ".SelfRefLiftover.interval_list"

  command <<<
    R --vanilla <<CODE
      intervals <- readLines('~{input_intervals}')
      intervals <- intervals[grep('^@', intervals, invert=T)]
      interval_names <- sapply(strsplit(intervals, '\t'),function(x)x[5])
      new_header <- readLines('~{target_dict}')
      lens <- sapply(interval_names, function(x)as.numeric(gsub('LN:','',strsplit(new_header[grep(paste0('^@SQ\tSN:',x), new_header)[1]], '\t')[[1]][3])))
      if(any(is.na(lens))) stop('ERROR: Some NUMT intervals were not found in the mt_andNuc sequence dictionary.')
      new_intervals <- c(new_header, paste(interval_names, 1, lens, '+', interval_names, sep='\t'))
      writeLines(new_intervals, '~{output_intervals}')
    CODE
  >>>

  output {
    File lifted_intervals = "~{output_intervals}"
  }

  runtime {
    disks: "local-disk " + disk_size + " HDD"
    memory: "500 MB"
    docker: gotc_docker
    preemptible: select_first([preemptible_tries, 5])
  }
}

task MoveChainToZero {
  input {
    File source_chain
    File ref_intervals
    String gotc_docker

    Int? preemptible_tries
  }

  Int disk_size = ceil(size(source_chain, "GB")*2.5)
  String output_chain = basename(source_chain, ".chain") + ".toZero.chain"

  command <<<
    R --vanilla <<CODE
      chain <- readLines('~{source_chain}')
      intervals <- readLines('~{ref_intervals}')
      intervals <- intervals[grep('^@', intervals, invert=T)]
      intervals_split <- strsplit(intervals, '\t')
      target_names <- sapply(intervals_split, function(x)x[5])
      names(target_names) <- sapply(intervals_split, function(x)paste0(x[1], ':', as.numeric(x[2])-1, '-', x[3]))
      to_edit <- grep('^chain', chain)
      this_sep <- ' '
      new_headers <- sapply(chain[to_edit], function(x) {
        this_header <- strsplit(x, this_sep)[[1]]
        this_search <- paste0(this_header[8], ':', this_header[11], '-', this_header[12])
        if (!this_search %in% names(target_names)) stop('ERROR: chain file has a segment not in intervals list.')
        this_name <- target_names[this_search]
        this_header[c(3, 8)] <- this_name
        this_header[c(4, 6, 7)] <- as.numeric(this_header[c(4, 6, 7)]) - as.numeric(this_header[6])
        this_header[c(9, 11, 12)] <- as.numeric(this_header[c(9, 11, 12)]) - as.numeric(this_header[11])
        return(paste0(this_header, collapse=this_sep))
      })
      new_chain <- chain
      new_chain[to_edit] <- new_headers
      writeLines(new_chain, '~{output_chain}')
    CODE
  >>>

  output {
    File chain = "~{output_chain}"
  }

  runtime {
    disks: "local-disk " + disk_size + " HDD"
    memory: "1 MB"
    docker: gotc_docker
    preemptible: select_first([preemptible_tries, 5])
  }
}

version 1.0

import "mtSwirl/WDL/v2.5_MongoSwirl_Single/MongoTasks_v2_5_Single.wdl" as MongoTasks_Single

workflow DiagnosticChainSwapLiftover {
  meta {
    description: "Quick test for chainSwap + liftOver + igvtools in ucsc_docker."
  }

  input {
    File source_chain
    String input_target_name
    String input_source_name
    File input_bed
    File input_bed_index
    String ucsc_docker
    Int? preemptible_tries
  }

  call MongoTasks_Single.MongoChainSwapLiftoverBed as ChainSwapLiftoverBed {
    input:
      source_chain = source_chain,
      input_target_name = input_target_name,
      input_source_name = input_source_name,
      input_bed = input_bed,
      input_bed_index = input_bed_index,
      ucsc_docker = ucsc_docker,
      preemptible_tries = preemptible_tries
  }

  output {
    File chain = ChainSwapLiftoverBed.chain
    File transformed_bed = ChainSwapLiftoverBed.transformed_bed
    File transformed_bed_index = ChainSwapLiftoverBed.transformed_bed_index
    File rejected = ChainSwapLiftoverBed.rejected
  }
}

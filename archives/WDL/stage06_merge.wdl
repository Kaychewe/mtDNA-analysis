version 1.0

import "scatterWrapper_MitoPipeline_v2_5.wdl" as ScatterWrapper

workflow StageMerge {
  meta {
    description: "Stage 6: merge per-sample outputs into batch-level deliverables."
  }

  input {
    Array[String] sample_name
    Array[File] variant_vcf
    Array[File] coverage_table
    Array[File] statistics

    File MergePerBatch
    Int? preemptible_tries
    String genomes_cloud_docker
  }

  call ScatterWrapper.MergeMitoMultiSampleOutputsInternal as MergeMitoMultiSampleOutputsInternal {
    input:
      sample_name = sample_name,
      variant_vcf = variant_vcf,
      coverage_table = coverage_table,
      statistics = statistics,
      MergePerBatch = MergePerBatch,
      preemptible_tries = preemptible_tries,
      genomes_cloud_docker = genomes_cloud_docker
  }

  output {
    File merged_statistics = MergeMitoMultiSampleOutputsInternal.merged_statistics
    File merged_coverage = MergeMitoMultiSampleOutputsInternal.merged_coverage
    File merged_calls = MergeMitoMultiSampleOutputsInternal.merged_calls
  }
}

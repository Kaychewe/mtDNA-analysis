version 1.0

task GetContaminationTest {
  input {
    File input_vcf
    String sample_name
    Int mean_coverage
    File haplocheck_zip
  }

  command <<<
    set -e
    mkdir -p out
    this_vcf="~{input_vcf}"

    zip_path="~{haplocheck_zip}"
    jar xf "${zip_path}"
    chmod +x haplocheck

    ./haplocheck --out output "${this_vcf}"

    if [ -s output ]; then
      sed 's/\"//g' output > output-noquotes
    else
      : > output-noquotes
    fi
    # Force SampleID to match the expected sample_name when possible.
    if grep -q "SampleID" output-noquotes; then
      awk -F "\t" 'NR==1{print;next}{$1="~{sample_name}";print}' output-noquotes > output-noquotes.fixed
      mv output-noquotes.fixed output-noquotes
    else
      echo "SampleID header missing; will fall back to NONE defaults."
    fi
    echo "Haplocheck output file size (bytes):"
    wc -c output || true
    echo "First 5 lines of output-noquotes:"
    head -n 5 output-noquotes || true
    echo "SampleID line (if any):"
    grep -n "SampleID" output-noquotes || true
    cp 'output-noquotes' "out/~{sample_name}_output_noquotes"
  >>>

  runtime {
    docker: "eclipse-temurin:17-jdk"
    memory: "3 GB"
  }

  output {
    File contamination_file = "out/~{sample_name}_output_noquotes"
  }
}

workflow GetContaminationWorkflow {
  input {
    File input_vcf
    String sample_name
    Int mean_coverage
    File haplocheck_zip
    String workspace_bucket
  }

  call GetContaminationTest {
    input:
      input_vcf = input_vcf,
      sample_name = sample_name,
      mean_coverage = mean_coverage,
      haplocheck_zip = haplocheck_zip
  }

  output {
    File contamination_file = GetContaminationTest.contamination_file
  }
}

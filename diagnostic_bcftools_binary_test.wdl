version 1.0

workflow DiagnosticBcftoolsBinaryTest {
  input {
    File bcftools_bundle_tgz
  }

  call TestBcftoolsBundle {
    input:
      bcftools_bundle_tgz = bcftools_bundle_tgz
  }

  output {
    File report = TestBcftoolsBundle.report
  }
}

task TestBcftoolsBundle {
  input {
    File bcftools_bundle_tgz
  }

  command <<<
    set -euo pipefail

    echo "bundle=~{bcftools_bundle_tgz}" > report.txt
    echo "date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" >> report.txt

    mkdir -p bcftools_bundle
    tar -xzf "~{bcftools_bundle_tgz}" -C bcftools_bundle

    export PATH="$PWD/bcftools_bundle/bin:$PATH"
    export LD_LIBRARY_PATH="$PWD/bcftools_bundle/lib:${LD_LIBRARY_PATH:-}"

    which bcftools >> report.txt 2>&1
    bcftools --version >> report.txt 2>&1
    which bgzip >> report.txt 2>&1
    bgzip --version >> report.txt 2>&1 || true
    which tabix >> report.txt 2>&1
    tabix --version >> report.txt 2>&1 || true

    echo "test_status=success" >> report.txt
  >>>

  output {
    File report = "report.txt"
  }

  runtime {
    docker: "ubuntu:22.04"
    memory: "2 GB"
    cpu: 1
  }
}

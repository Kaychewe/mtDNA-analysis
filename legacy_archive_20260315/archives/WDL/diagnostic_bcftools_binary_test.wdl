version 1.0

workflow DiagnosticBcftoolsBinaryTest {
  input {
    File bcftools_bundle_tgz
    String report_out_basename = "bcftools_binary_test_report"
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
    set +e

    echo "bundle=~{bcftools_bundle_tgz}" > report.txt
    echo "date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" >> report.txt

    mkdir -p bcftools_bundle
    tar -xzf "~{bcftools_bundle_tgz}" -C bcftools_bundle >> report.txt 2>&1

    echo "bundle_contents:" >> report.txt
    ls -la bcftools_bundle >> report.txt 2>&1
    ls -la bcftools_bundle/bin >> report.txt 2>&1
    ls -la bcftools_bundle/libexec >> report.txt 2>&1

    export PATH="$PWD/bcftools_bundle/bin:$PATH"
    export LD_LIBRARY_PATH="$PWD/bcftools_bundle/lib:${LD_LIBRARY_PATH:-}"

    echo "which_bcftools:" >> report.txt
    which bcftools >> report.txt 2>&1
    echo "bcftools_version:" >> report.txt
    bcftools --version >> report.txt 2>&1

    echo "ldd_bcftools:" >> report.txt
    ldd "$PWD/bcftools_bundle/bin/bcftools" >> report.txt 2>&1

    echo "which_bgzip:" >> report.txt
    which bgzip >> report.txt 2>&1
    echo "bgzip_version:" >> report.txt
    bgzip --version >> report.txt 2>&1

    echo "which_tabix:" >> report.txt
    which tabix >> report.txt 2>&1
    echo "tabix_version:" >> report.txt
    tabix --version >> report.txt 2>&1

    echo "test_status=done" >> report.txt
    exit 0
  >>>

  output {
    File report = "report.txt"
  }

  runtime {
    docker: "ubuntu:22.04"
    memory: "2 GB"
    cpu: 1
    continueOnReturnCode: [0, 1, 2, 126, 127]
  }
}

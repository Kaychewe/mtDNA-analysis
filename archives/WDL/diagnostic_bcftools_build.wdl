version 1.0

workflow DiagnosticBcftoolsBuild {
  input {
    String bcftools_url = "https://github.com/samtools/bcftools/releases/download/1.23/bcftools-1.23.tar.bz2"
    Int make_threads = 2
  }

  call BuildBcftoolsFromSource {
    input:
      bcftools_url = bcftools_url,
      make_threads = make_threads
  }

  output {
    File report = BuildBcftoolsFromSource.report
    File bcftools_bin = BuildBcftoolsFromSource.bcftools_bin
  }
}

task BuildBcftoolsFromSource {
  input {
    String bcftools_url
    Int make_threads
  }

  command <<<
    # avoid set -euo pipefail 
    set -e

    echo "bcftools_url=~{bcftools_url}" > report.txt
    echo "date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" >> report.txt

    apt-get update -y
    apt-get install -y --no-install-recommends \
      build-essential \
      wget \
      bzip2 \
      ca-certificates \
      zlib1g-dev \
      libbz2-dev \
      liblzma-dev \
      libcurl4-openssl-dev \
      libssl-dev \
      libncurses5-dev

    wget -O bcftools.tar.bz2 "~{bcftools_url}"
    tar -xjf bcftools.tar.bz2
    cd bcftools-1.23
    make -j ~{make_threads}

    ./bcftools --version >> ../report.txt 2>&1

    # Copy binary to task root for output
    cp ./bcftools ../bcftools
    cd ..

    echo "build_status=success" >> report.txt
  >>>

  output {
    File report = "report.txt"
    File bcftools_bin = "bcftools"
  }

  runtime {
    docker: "ubuntu:22.04"
    memory: "4 GB"
    cpu: 2
  }
}

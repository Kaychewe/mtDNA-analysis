version 1.0

task CheckUCSCTools {
  input {
    String ucsc_docker
    Int? preemptible_tries
  }

  command <<<
    set -euo pipefail
    echo "image=${ucsc_docker}" > report.txt
    for tool in chainSwap liftOver igvtools; do
      if command -v "$tool" >/dev/null 2>&1; then
        echo "${tool}=FOUND" >> report.txt
        if "$tool" --version >/dev/null 2>&1; then
          "$tool" --version >> report.txt
        fi
      else
        echo "${tool}=MISSING" >> report.txt
      fi
    done
  >>>

  output {
    File report = "report.txt"
  }

  runtime {
    docker: ucsc_docker
    memory: "1 GB"
    disks: "local-disk 10 HDD"
    preemptible: select_first([preemptible_tries, 0])
  }
}

workflow DiagnosticUCSCTools {
  meta {
    description: "Check UCSC tools availability in the specified docker image."
  }

  input {
    String ucsc_docker
    Int? preemptible_tries
  }

  call CheckUCSCTools {
    input:
      ucsc_docker = ucsc_docker,
      preemptible_tries = preemptible_tries
  }

  output {
    File report = CheckUCSCTools.report
  }
}

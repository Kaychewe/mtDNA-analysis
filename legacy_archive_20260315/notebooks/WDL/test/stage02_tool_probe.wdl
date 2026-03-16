version 1.0

workflow Stage02ToolProbe {
  input {
    # Use the same image you pass to stage02 (e.g. kchewe/mtdna-tools:0.1.0).
    String docker_image
    Int preemptible = 0
  }

  call Probe {
    input:
      docker_image = docker_image,
      preemptible = preemptible
  }

  output {
    File report = Probe.report
  }
}

task Probe {
  input {
    String docker_image
    Int preemptible = 0
  }

  command <<<
    set -euo pipefail

    mkdir -p out

    {
      echo "UTC_DATE: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
      echo "DOCKER_IMAGE: ~{docker_image}"
      echo "UNAME: $(uname -a)"
      echo
      echo "PATH: $PATH"
      echo

      echo "=== COMMAND PRESENCE (Stage02-relevant + common tooling) ==="
      for c in \
        bash sh \
        awk sed grep cat wc tail head sort uniq \
        gzip \
        bc \
        java jar \
        python python3 \
        R Rscript \
        gatk \
        samtools \
        bcftools bgzip tabix \
      ; do
        if command -v "$c" >/dev/null 2>&1; then
          echo "FOUND   $c -> $(command -v "$c")"
        else
          echo "MISSING $c"
        fi
      done
      echo

      echo "=== VERSIONS (best-effort) ==="
      (gatk --version || gatk --help | head -n 5) 2>&1 | sed 's/^/gatk: /' || true
      (java -version) 2>&1 | sed 's/^/java: /' || true
      (python3 --version) 2>&1 | sed 's/^/python3: /' || true
      (python --version) 2>&1 | sed 's/^/python: /' || true
      (R --version | head -n 2) 2>&1 | sed 's/^/R: /' || true
      (Rscript --version) 2>&1 | sed 's/^/Rscript: /' || true
      (samtools --version | head -n 3) 2>&1 | sed 's/^/samtools: /' || true
      (bcftools --version | head -n 3) 2>&1 | sed 's/^/bcftools: /' || true
      (bgzip --version | head -n 2) 2>&1 | sed 's/^/bgzip: /' || true
      (tabix --version | head -n 2) 2>&1 | sed 's/^/tabix: /' || true
      echo

      echo "=== GATK SANITY (does CLI respond?) ==="
      (gatk --list 2>/dev/null | head -n 40) || true
    } | tee out/stage02_tool_probe.txt
  >>>

  output {
    File report = "out/stage02_tool_probe.txt"
  }

  runtime {
    docker: docker_image
    cpu: 1
    memory: "2000 MB"
    disks: "local-disk 10 HDD"
    preemptible: preemptible
  }
}


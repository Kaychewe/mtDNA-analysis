version 1.0

workflow DiagnosticDockerProbeSafe {
  input {
    Array[String] docker_images
    Array[String] tools
    String? extra_cmd
  }

  scatter (img in docker_images) {
    call ProbeDockerToolsSafe {
      input:
        docker_image = img,
        tools = tools,
        extra_cmd = extra_cmd
    }
  }

  output {
    Array[File] reports = ProbeDockerToolsSafe.report
  }
}

task ProbeDockerToolsSafe {
  input {
    String docker_image
    Array[String] tools
    String? extra_cmd
  }

  command <<<
    # Cromwell runs this via /bin/bash. We avoid failing on missing tools and always exit 0.
    set +e

    echo "image=${docker_image}" > docker_probe_report.txt
    echo "date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" >> docker_probe_report.txt
    echo "whoami=$(whoami 2>/dev/null)" >> docker_probe_report.txt
    echo "uname=$(uname -a 2>/dev/null)" >> docker_probe_report.txt
    echo "PATH=${PATH}" >> docker_probe_report.txt
    echo "" >> docker_probe_report.txt

    cat > tools.list <<'TOOLS'
    ~{sep='\n' tools}
TOOLS

    while IFS= read -r tool; do
      if [ -z "$tool" ]; then
        continue
      fi
      if command -v "$tool" >/dev/null 2>&1; then
        echo "OK: ${tool} -> $(command -v ${tool})" >> docker_probe_report.txt
        (${tool} --version || ${tool} -version || ${tool} -V || ${tool} -h || true) >> docker_probe_report.txt 2>&1
      else
        echo "MISSING: ${tool}" >> docker_probe_report.txt
      fi
      echo "" >> docker_probe_report.txt
    done < tools.list

    if [ -n "~{default='' extra_cmd}" ]; then
      echo "EXTRA_CMD:" >> docker_probe_report.txt
      bash -lc "~{extra_cmd}" >> docker_probe_report.txt 2>&1
      echo "EXTRA_CMD_RC=$?" >> docker_probe_report.txt
    fi

    echo "DONE" >> docker_probe_report.txt
    exit 0
  >>>

  output {
    File report = "docker_probe_report.txt"
  }

  runtime {
    docker: docker_image
    memory: "2 GB"
    cpu: 1
    # Treat any non-zero exit as success. This avoids failure on missing tools.
    continueOnReturnCode: [0, 1, 2, 126, 127]
  }
}

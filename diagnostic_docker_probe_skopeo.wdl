version 1.0

workflow DiagnosticDockerProbeSkopeo {
  input {
    Array[String] docker_images
    Array[String] tools
    String? extra_cmd
  }

  scatter (img in docker_images) {
    call DetectBashWithSkopeo {
      input:
        docker_image = img
    }

    if (DetectBashWithSkopeo.has_bash) {
      call ProbeDockerToolsSafe {
        input:
          docker_image = img,
          tools = tools,
          extra_cmd = extra_cmd
      }
    }

    if (!DetectBashWithSkopeo.has_bash) {
      call WriteUnsupportedReport {
        input:
          docker_image = img,
          reason = DetectBashWithSkopeo.reason
      }
    }

    File report = select_first([ProbeDockerToolsSafe.report, WriteUnsupportedReport.report])
  }

  output {
    Array[File] reports = report
  }
}

task DetectBashWithSkopeo {
  input {
    String docker_image
  }

  command <<<
    # Safe detection: do not run the target image. Use skopeo to inspect layers.
    set +e

    echo "image=${docker_image}" > docker_bash_detect_report.txt
    echo "date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" >> docker_bash_detect_report.txt

    mkdir -p oci

    skopeo copy --override-os linux docker://"${docker_image}" oci:./oci:img >> docker_bash_detect_report.txt 2>&1
    if [ $? -ne 0 ]; then
      echo "has_bash=false" > has_bash.txt
      echo "reason=skopeo_copy_failed" > reason.txt
      exit 0
    fi

    RAW=$(skopeo inspect --raw docker://"${docker_image}" 2>> docker_bash_detect_report.txt)
    if [ -z "$RAW" ]; then
      echo "has_bash=false" > has_bash.txt
      echo "reason=skopeo_inspect_failed" > reason.txt
      exit 0
    fi

    echo "$RAW" | grep -o 'sha256:[a-f0-9]\{64\}' | while read -r digest; do
      h=${digest#sha256:}
      blob="oci/blobs/sha256/${h}"
      if [ ! -f "$blob" ]; then
        continue
      fi
      # Try tar listing (plain or gz). Look for /bin/bash or /usr/bin/bash
      tar -tf "$blob" >/dev/null 2>&1
      if [ $? -eq 0 ]; then
        tar -tf "$blob" | grep -E '(^|/)bin/bash$|(^|/)usr/bin/bash$' && echo "FOUND" > bash_found.txt
      else
        tar -tzf "$blob" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
          tar -tzf "$blob" | grep -E '(^|/)bin/bash$|(^|/)usr/bin/bash$' && echo "FOUND" > bash_found.txt
        fi
      fi
    done

    if [ -f bash_found.txt ]; then
      echo "has_bash=true" > has_bash.txt
      echo "reason=ok" > reason.txt
    else
      echo "has_bash=false" > has_bash.txt
      echo "reason=no_bash_in_layers" > reason.txt
    fi

    exit 0
  >>>

  output {
    Boolean has_bash = read_boolean("has_bash.txt")
    String reason = read_string("reason.txt")
    File report = "docker_bash_detect_report.txt"
  }

  runtime {
    docker: "quay.io/skopeo/stable:latest"
    memory: "2 GB"
    cpu: 1
    continueOnReturnCode: [0, 1, 2, 126, 127]
  }
}

task ProbeDockerToolsSafe {
  input {
    String docker_image
    Array[String] tools
    String? extra_cmd
  }

  command <<<
    # Probe tools inside the target image. Always exit 0 and write a report.
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
    continueOnReturnCode: [0, 1, 2, 126, 127]
  }
}

task WriteUnsupportedReport {
  input {
    String docker_image
    String reason
  }

  command <<<
    set +e
    echo "image=${docker_image}" > docker_probe_report.txt
    echo "status=skipped" >> docker_probe_report.txt
    echo "reason=${reason}" >> docker_probe_report.txt
    echo "note=Probe not run because bash was not detected in image layers." >> docker_probe_report.txt
    exit 0
  >>>

  output {
    File report = "docker_probe_report.txt"
  }

  runtime {
    docker: "quay.io/skopeo/stable:latest"
    memory: "1 GB"
    cpu: 1
    continueOnReturnCode: [0, 1, 2, 126, 127]
  }
}

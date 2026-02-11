version 1.0

task UcscToolsSmoke {
  input {
    File ucsc_tools_bundle
    String docker_image = "us.gcr.io/broad-dsp-lrma/lr-basic:latest"
  }

  command <<<
    set -euo pipefail
    tar -xzf "~{ucsc_tools_bundle}" -C .
    export PATH="$PWD/ucsc_tools/bin:$PWD/ucsc_tools:$PATH"

    IGVTOOLS_JAR=""
    if [ -f "$PWD/ucsc_tools/igvtools.jar" ]; then
      IGVTOOLS_JAR="$PWD/ucsc_tools/igvtools.jar"
    fi

    {
      echo "chainSwap:"
      chainSwap 2>&1 | head -n 1 || true
      echo "liftOver:"
      liftOver 2>&1 | head -n 1 || true
      echo "igvtools:"
      if [ -n "${IGVTOOLS_JAR}" ]; then
        java -jar "${IGVTOOLS_JAR}" --version 2>&1 | head -n 1 || true
      else
        igvtools version 2>&1 | head -n 1 || true
      fi
    } > versions.txt

    for tool in chainSwap liftOver igvtools; do
      command -v "$tool" >/dev/null 2>&1
      echo "$tool=OK" >> versions.txt
    done
  >>>

  output {
    File versions = "versions.txt"
  }

  runtime {
    docker: docker_image
    memory: "1 GB"
    disks: "local-disk 10 HDD"
    preemptible: 0
  }
}

workflow Stage03UcscSmokeTest {
  input {
    File ucsc_tools_bundle
    String docker_image = "us.gcr.io/broad-dsp-lrma/lr-basic:latest"
  }

  call UcscToolsSmoke {
    input:
      ucsc_tools_bundle = ucsc_tools_bundle,
      docker_image = docker_image
  }

  output {
    File versions = UcscToolsSmoke.versions
  }
}

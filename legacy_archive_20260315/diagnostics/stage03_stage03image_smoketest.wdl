version 1.0

task Stage03ImageSmoke {
  input {
    String docker_image
  }

  command <<<
    set -euo pipefail

    {
      echo "hail_version:";
      python3 - <<'PY'
import hail as hl
try:
    v = hl.version()
except Exception:
    v = None
print(v or getattr(hl, "__version__", None) or "UNKNOWN")
print(hl.citation())
PY
      echo "bcftools_version:";
      bcftools --version | head -n 1
      echo "bgzip_version:";
      bgzip --version | head -n 1
      echo "tabix_version:";
      tabix --version | head -n 1
      echo "samtools_version:";
      samtools --version | head -n 1
      echo "chainSwap_version:";
      chainSwap 2>&1 | head -n 1 || true
      echo "liftOver_version:";
      liftOver 2>&1 | head -n 1 || true
      echo "igvtools_version:";
      igvtools 2>&1 | head -n 1 || true
      echo "java_version:";
      java -version 2>&1 | head -n 1
      echo "R_version:";
      R --version | head -n 1
    } > stage03_image_versions.txt
  >>>

  output {
    File versions = "stage03_image_versions.txt"
  }

  runtime {
    docker: docker_image
    memory: "2 GB"
    disks: "local-disk 10 HDD"
    preemptible: 0
  }
}

workflow Stage03ImageSmokeTest {
  input {
    String docker_image
  }

  call Stage03ImageSmoke {
    input:
      docker_image = docker_image
  }

  output {
    File versions = Stage03ImageSmoke.versions
  }
}

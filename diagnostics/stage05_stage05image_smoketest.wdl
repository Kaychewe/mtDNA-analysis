version 1.0

task Stage05GenomesCloudSmoke {
  input {
    String genomes_cloud_docker
  }

  command <<<
    set -euo pipefail

    {
      echo "python3_version:";
      python3 --version 2>&1 | head -n 1
      echo "java_version:";
      java -version 2>&1 | head -n 1
      echo "bcftools_version:";
      bcftools --version 2>&1 | head -n 1
      echo "bgzip_version:";
      bgzip --version 2>&1 | head -n 1 || true
      echo "tabix_version:";
      tabix --version 2>&1 | head -n 1 || true
      echo "bedtools_version:";
      bedtools --version 2>&1 | head -n 1
      echo "picard_version:";
      picard --version 2>&1 | head -n 1 || true
      echo "R_version:";
      R --version | head -n 1
      echo "hail_version:";
      python3 - <<'PY'
import hail as hl
print(hl.__version__)
PY
    } > stage05_genomes_cloud_versions.txt
  >>>

  output {
    File versions = "stage05_genomes_cloud_versions.txt"
  }

  runtime {
    docker: genomes_cloud_docker
    memory: "2 GB"
    disks: "local-disk 10 HDD"
    preemptible: 0
  }
}

task Stage05UcscSmoke {
  input {
    String ucsc_docker
    File? ucsc_tools_bundle
  }

  command <<<
    set -euo pipefail

    if [ -n "~{ucsc_tools_bundle}" ] && [ "~{ucsc_tools_bundle}" != "null" ]; then
      tar -xzf "~{ucsc_tools_bundle}" -C .
      export PATH="$PWD/ucsc_tools/bin:$PWD/ucsc_tools:$PATH"
    fi

    {
      echo "liftOver_path:";
      command -v liftOver || true
      echo "liftOver_help:";
      liftOver 2>&1 | head -n 1 || true
      echo "java_version:";
      java -version 2>&1 | head -n 1
      echo "R_version:";
      R --version | head -n 1
    } > stage05_ucsc_versions.txt
  >>>

  output {
    File versions = "stage05_ucsc_versions.txt"
  }

  runtime {
    docker: ucsc_docker
    memory: "2 GB"
    disks: "local-disk 10 HDD"
    preemptible: 0
  }
}

workflow Stage05ImageSmokeTest {
  input {
    String genomes_cloud_docker
    String ucsc_docker
    File? ucsc_tools_bundle
  }

  call Stage05GenomesCloudSmoke {
    input:
      genomes_cloud_docker = genomes_cloud_docker
  }

  call Stage05UcscSmoke {
    input:
      ucsc_docker = ucsc_docker,
      ucsc_tools_bundle = ucsc_tools_bundle
  }

  output {
    File genomes_cloud_versions = Stage05GenomesCloudSmoke.versions
    File ucsc_versions = Stage05UcscSmoke.versions
  }
}

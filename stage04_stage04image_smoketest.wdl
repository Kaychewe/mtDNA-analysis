version 1.0

task Stage04GotcSmoke {
  input {
    String gotc_docker
  }

  command <<<
    set -euo pipefail

    {
      echo "bwa_version:";
      /usr/gitc/bwa 2>&1 | head -n 1 || true
      echo "samtools_version:";
      samtools --version | head -n 1
      echo "picard_version:";
      picard --version 2>&1 | head -n 1 || true
      echo "java_version:";
      java -version 2>&1 | head -n 1
      echo "R_version:";
      R --version | head -n 1
    } > stage04_gotc_versions.txt
  >>>

  output {
    File versions = "stage04_gotc_versions.txt"
  }

  runtime {
    docker: gotc_docker
    memory: "2 GB"
    disks: "local-disk 10 HDD"
    preemptible: 0
  }
}

task Stage04GatkSmoke {
  input {
    String gatk_docker
  }

  command <<<
    set -euo pipefail

    {
      echo "gatk_version:";
      gatk --version 2>&1 | head -n 1
      echo "java_version:";
      java -version 2>&1 | head -n 1
    } > stage04_gatk_versions.txt
  >>>

  output {
    File versions = "stage04_gatk_versions.txt"
  }

  runtime {
    docker: gatk_docker
    memory: "2 GB"
    disks: "local-disk 10 HDD"
    preemptible: 0
  }
}

workflow Stage04ImageSmokeTest {
  input {
    String gotc_docker
    String gatk_docker
  }

  call Stage04GotcSmoke {
    input:
      gotc_docker = gotc_docker
  }

  call Stage04GatkSmoke {
    input:
      gatk_docker = gatk_docker
  }

  output {
    File gotc_versions = Stage04GotcSmoke.versions
    File gatk_versions = Stage04GatkSmoke.versions
  }
}

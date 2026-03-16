version 1.0

workflow Stage05ContainerSmokeTest {
  meta {
    description: "Stage 05: minimal container smoke test to verify the image starts and can write outputs."
  }

  input {
    String genomes_cloud_docker
  }

  call Stage05ContainerStart as StartCheck {
    input:
      docker_image = genomes_cloud_docker
  }

  output {
    File marker = StartCheck.marker
    File listing = StartCheck.listing
  }
}

task Stage05ContainerStart {
  input {
    String docker_image
  }

  command <<<
    set -euo pipefail
    mkdir -p out
    echo "container_ok" > out/container_ok.txt
    ls -la /mnt/disks/cromwell_root > out/root_ls.txt
  >>>

  runtime {
    cpu: 1
    memory: "2 GB"
    disks: "local-disk 20 HDD"
    docker: docker_image
    preemptible: 0
  }

  output {
    File marker = "out/container_ok.txt"
    File listing = "out/root_ls.txt"
  }
}

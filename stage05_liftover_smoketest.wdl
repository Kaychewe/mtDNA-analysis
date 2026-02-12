version 1.0

workflow Stage05LiftoverSmokeTest {
  meta {
    description: "Stage 05 smoketest: minimal hello world to verify Batch execution/logging."
  }

  input {
    String genomes_cloud_docker
  }

  call Stage05HelloWorld as HelloWorld {
    input:
      docker_image = genomes_cloud_docker
  }

  output {
    File marker = HelloWorld.marker
  }
}

task Stage05HelloWorld {
  input {
    String docker_image
  }

  command <<<
    set -euo pipefail
    mkdir -p out
    echo "hello_world" > out/hello_world.txt
  >>>

  runtime {
    cpu: 1
    memory: "1 GB"
    disks: "local-disk 10 HDD"
    docker: docker_image
    preemptible: 0
  }

  output {
    File marker = "out/hello_world.txt"
  }
}

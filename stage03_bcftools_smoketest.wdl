version 1.0

workflow BcftoolsDockerSmokeTest {
  input {
    String bcftools_docker
  }

  call BcftoolsSmoke {
    input:
      bcftools_docker = bcftools_docker
  }

  output {
    File versions_txt = BcftoolsSmoke.versions_txt
  }
}

task BcftoolsSmoke {
  input {
    String bcftools_docker
  }

  command <<< 
    echo "bcftools:" > versions.txt
    bcftools --version >> versions.txt
    echo "" >> versions.txt
    echo "bgzip:" >> versions.txt
    bgzip --version >> versions.txt
    echo "" >> versions.txt
    echo "tabix:" >> versions.txt
    tabix --version >> versions.txt
  >>>

  output {
    File versions_txt = "versions.txt"
  }

  runtime {
    docker: bcftools_docker
  }
}

version 1.0

workflow HelloWorld {
  call HelloTask
  output {
    String msg = HelloTask.out
  }
}

task HelloTask {
  input {
    String name
  }
  command <<<
    echo "Hello, ~{name}!"
  >>>
  output {
    String out = read_string(stdout())
  }
  runtime {
    docker: "ubuntu:22.04"
  }
}

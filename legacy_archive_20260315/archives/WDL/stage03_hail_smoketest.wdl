version 1.0

task HailSmoke {
  input {
    String docker_image
  }

  command <<<
    set -euo pipefail
    python3 - <<'PY' > hail_version.txt
import hail as hl
try:
    v = hl.version()
except Exception:
    v = None
print(v or getattr(hl, "__version__", None) or "UNKNOWN")
print(hl.citation())
PY
  >>>

  output {
    File hail_version = "hail_version.txt"
  }

  runtime {
    docker: docker_image
    memory: "2 GB"
    disks: "local-disk 10 HDD"
    preemptible: 0
  }
}

workflow Stage03HailSmokeTest {
  input {
    String docker_image
  }

  call HailSmoke {
    input:
      docker_image = docker_image
  }

  output {
    File hail_version = HailSmoke.hail_version
  }
}

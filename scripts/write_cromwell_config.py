#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

from aou_config import ensure_dirs, load_settings


def main() -> None:
    settings = load_settings()
    ensure_dirs(settings)

    conf = f"""include required(classpath("application"))

google {{
  application-name = "cromwell"
  auths = [{{
    name = "application_default"
    scheme = "application_default"
  }}]
}}

system {{
  new-workflow-poll-rate = 1
  max-concurrent-workflows = 50
  max-workflow-launch-count = 400
  job-rate-control {{
    jobs = 100
    per = "3 seconds"
  }}
}}

backend {{
  default = "GCPBATCH"
  providers {{
    Local.config.root = "/dev/null"

    GCPBATCH {{
      actor-factory = "cromwell.backend.google.batch.GcpBatchBackendLifecycleActorFactory"
      config {{
        project = "{settings.google_project}"
        concurrent-job-limit = 20
        root = "{settings.workspace_bucket}/workflows/cromwell-executions"

        virtual-private-cloud {{
          network-name = "projects/{settings.google_project}/global/networks/network"
          subnetwork-name = "projects/{settings.google_project}/regions/us-central1/subnetworks/subnetwork"
        }}

        batch {{
          auth = "application_default"
          compute-service-account = "{settings.pet_sa_email}"
          location = "us-central1"
        }}

        default-runtime-attributes {{
          noAddress: true
        }}

        filesystems {{
          gcs {{
            auth = "application_default"
          }}
        }}
      }}
    }}
  }}
}}

database {{
  profile = "slick.jdbc.HsqldbProfile$"
  insert-batch-size = 6000
  db {{
    driver = "org.hsqldb.jdbcDriver"
    url = "jdbc:hsqldb:file:{settings.cromwell_db_path};shutdown=false;hsqldb.default_table_type=cached;hsqldb.tx=mvcc;hsqldb.large_data=true;hsqldb.lob_compressed=true;hsqldb.script_format=3;hsqldb.result_max_memory_rows=20000"
    connectionTimeout = 300000
  }}
}}
"""

    settings.cromwell_conf_path.write_text(conf)
    print(f"Wrote {settings.cromwell_conf_path}")


if __name__ == "__main__":
    main()

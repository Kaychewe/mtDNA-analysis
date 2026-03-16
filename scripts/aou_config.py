#!/usr/bin/env python3
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class AoUSettings:
    workspace_bucket: str
    google_project: str
    pet_sa_email: str
    project_root: Path
    output_fold: str
    port_id: int
    use_mem_gb: int
    sql_db_name: str

    @property
    def cromwell_db_dir(self) -> Path:
        return self.project_root / ".cromwell_db"

    @property
    def cromwell_db_path(self) -> Path:
        return self.cromwell_db_dir / self.sql_db_name

    @property
    def cromwell_conf_path(self) -> Path:
        return self.project_root / "config" / "cromwell.batch.conf"

    @property
    def cromwell_stdout_log(self) -> Path:
        return self.project_root / "logs" / "cromwell_server_stdout.log"

    @property
    def cromwell_stderr_log(self) -> Path:
        return self.project_root / "logs" / "cromwell_server_stderr.log"

    @property
    def cromwell_pid_file(self) -> Path:
        return self.project_root / "logs" / "cromwell_server.pid"


def load_settings() -> AoUSettings:
    project_root_env = os.getenv("PROJECT_ROOT")
    if project_root_env:
        project_root = Path(project_root_env).resolve()
    else:
        project_root = Path(__file__).resolve().parents[1]

    return AoUSettings(
        workspace_bucket=os.getenv("WORKSPACE_BUCKET", "").rstrip("/"),
        google_project=os.getenv("GOOGLE_PROJECT", ""),
        pet_sa_email=os.getenv("PET_SA_EMAIL", ""),
        project_root=project_root,
        output_fold=os.getenv("outputFold", "mtDNA_v25_pilot_5"),
        port_id=int(os.getenv("PORTID", "8094")),
        use_mem_gb=int(os.getenv("USE_MEM", "32")),
        sql_db_name=os.getenv("SQL_DB_NAME", "local_cromwell_run.db"),
    )


def ensure_dirs(settings: AoUSettings) -> None:
    (settings.project_root / "config").mkdir(parents=True, exist_ok=True)
    (settings.project_root / "logs").mkdir(parents=True, exist_ok=True)
    settings.cromwell_db_dir.mkdir(parents=True, exist_ok=True)

#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

from aou_config import ensure_dirs, load_settings


def run(cmd: str, check: bool = True) -> str:
    print(f"$ {cmd}")
    completed = subprocess.run(
        cmd,
        shell=True,
        check=check,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return completed.stdout.strip()


def main() -> None:
    settings = load_settings()
    ensure_dirs(settings)

    print("AoU settings:")
    print("  WORKSPACE_BUCKET:", settings.workspace_bucket or "<unset>")
    print("  GOOGLE_PROJECT :", settings.google_project or "<unset>")
    print("  PET_SA_EMAIL   :", settings.pet_sa_email or "<unset>")
    print("  PROJECT_ROOT   :", settings.project_root)
    print("  PORTID         :", settings.port_id)
    print("  USE_MEM        :", settings.use_mem_gb)

    checks = {
        "python": sys.executable,
        "pip": shutil.which("pip") or shutil.which("pip3") or "",
        "gsutil": shutil.which("gsutil") or "",
        "gcloud": shutil.which("gcloud") or "",
        "java": shutil.which("java") or "",
        "docker": shutil.which("docker") or "",
    }

    print("\nDependency check:")
    for key, value in checks.items():
        print(f"  {key:8s} -> {value if value else 'MISSING'}")

    if checks["java"]:
        print("\nJava version:")
        print(run("java -version", check=False))

    if checks["gcloud"]:
        print("\nGcloud auth:")
        print(run("gcloud auth list --format='value(account)'", check=False))

    try:
        import pyhocon  # noqa: F401

        print("\npyhocon: OK")
    except ImportError:
        print("\npyhocon: missing")

    tmp_dir = settings.project_root / ".tmp"
    tmp_dir.mkdir(parents=True, exist_ok=True)

    cromwell_jar = tmp_dir / "cromwell-91.jar"
    womtool_jar = tmp_dir / "womtool-91.jar"

    if not cromwell_jar.exists():
        print("\nDownloading cromwell-91.jar")
        run(
            f"curl -L https://github.com/broadinstitute/cromwell/releases/download/91/cromwell-91.jar -o {cromwell_jar}",
            check=True,
        )
    else:
        print("\ncromwell-91.jar already present.")

    if not womtool_jar.exists():
        print("Downloading womtool-91.jar")
        run(
            f"curl -L https://github.com/broadinstitute/cromwell/releases/download/91/womtool-91.jar -o {womtool_jar}",
            check=True,
        )
    else:
        print("womtool-91.jar already present.")

    print("\nCROMWELL_HEAP_GB set to", settings.use_mem_gb)


if __name__ == "__main__":
    main()

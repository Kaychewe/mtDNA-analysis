#!/bin/sh
""":"
exec python3 "$0" "$@"
":"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[1]
WDL_PATH = ROOT_DIR / "wdl" / "aou_mitohpc_single_sample.wdl"
INPUTS_PATH = ROOT_DIR / "inputs" / "test_one_sample_aou.json"
CONF_PATH = ROOT_DIR / "config" / "cromwell.batch.conf"
TMP_WOMTOOL = ROOT_DIR / ".tmp" / "womtool-91.jar"
LEGACY_WOMTOOL = ROOT_DIR / "womtool-91.jar"


def run_validation() -> None:
    print(f"WDL: {WDL_PATH}")
    print(f"Inputs: {INPUTS_PATH}")
    print(f"Config: {CONF_PATH}")

    java = shutil.which("java")
    womtool = TMP_WOMTOOL if TMP_WOMTOOL.exists() else LEGACY_WOMTOOL

    if java and womtool.exists():
        print(f"Validating WDL with {womtool}...")
        subprocess.run([java, "-jar", str(womtool), "validate", str(WDL_PATH)], check=True)
    else:
        print("Skipping womtool validation because java or womtool-91.jar is unavailable.")

    print(
        """
To run a one-sample Cromwell test in an AoU-compatible environment, use:

  python scripts/check_environment.py
  python scripts/write_cromwell_config.py
  python scripts/cromwell_server.py start

  python scripts/submit_one_sample.py --wait

This helper intentionally stops after validation guidance because Cromwell backend
configuration and AoU credentials are environment-specific.
""".strip()
    )


if __name__ == "__main__":
    run_validation()

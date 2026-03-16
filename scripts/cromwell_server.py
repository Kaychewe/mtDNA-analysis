#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import signal
import subprocess
import time

from aou_config import ensure_dirs, load_settings
from cromwell_api import cromwell_up


def cromwell_pid_running(pid_file: str) -> bool:
    if not os.path.exists(pid_file):
        return False
    try:
        with open(pid_file) as handle:
            pid = int(handle.read().strip())
        os.kill(pid, 0)
        return True
    except Exception:
        return False


def start_server() -> None:
    settings = load_settings()
    ensure_dirs(settings)

    tmp_dir = settings.project_root / ".tmp"
    cromwell_jar = tmp_dir / "cromwell-91.jar"
    if not cromwell_jar.exists():
        raise SystemExit(f"Missing {cromwell_jar}. Run check_environment.py first.")

    if not settings.cromwell_conf_path.exists():
        raise SystemExit(
            f"Missing {settings.cromwell_conf_path}. Run write_cromwell_config.py first."
        )

    if cromwell_pid_running(str(settings.cromwell_pid_file)) and cromwell_up():
        print("Cromwell already running and healthy.")
        return

    stdout = open(settings.cromwell_stdout_log, "a")
    stderr = open(settings.cromwell_stderr_log, "a")
    process = subprocess.Popen(
        [
            "java",
            f"-Xmx{settings.use_mem_gb}g",
            f"-Dconfig.file={settings.cromwell_conf_path}",
            f"-Dwebservice.port={settings.port_id}",
            "-jar",
            str(cromwell_jar),
            "server",
        ],
        stdout=stdout,
        stderr=stderr,
        cwd=settings.project_root,
        start_new_session=True,
    )

    settings.cromwell_pid_file.write_text(f"{process.pid}\n")

    for _ in range(30):
        if cromwell_up():
            print("Cromwell is up.")
            return
        time.sleep(2)

    raise SystemExit("Cromwell did not start. Check the log files.")


def stop_server() -> None:
    settings = load_settings()
    if not settings.cromwell_pid_file.exists():
        print("No PID file found.")
        return

    try:
        pid = int(settings.cromwell_pid_file.read_text().strip())
        os.kill(pid, signal.SIGTERM)
        print(f"Sent SIGTERM to Cromwell PID {pid}.")
    finally:
        settings.cromwell_pid_file.unlink(missing_ok=True)


def status_server() -> None:
    settings = load_settings()
    print("cromwell_up():", cromwell_up())
    print("cromwell_pid_running():", cromwell_pid_running(str(settings.cromwell_pid_file)))
    print("stdout_log:", settings.cromwell_stdout_log)
    print("stderr_log:", settings.cromwell_stderr_log)


def tail_logs(lines: int) -> None:
    settings = load_settings()
    for label, path in (
        ("stdout", settings.cromwell_stdout_log),
        ("stderr", settings.cromwell_stderr_log),
    ):
        print(f"--- {label}: {path} ---")
        if path.exists():
            print("\n".join(path.read_text().splitlines()[-lines:]))
        else:
            print("<missing>")


def main() -> None:
    parser = argparse.ArgumentParser(description="Manage local Cromwell for AoU mtDNA refactor.")
    parser.add_argument("command", choices=["start", "stop", "status", "tail"])
    parser.add_argument("--lines", type=int, default=50)
    args = parser.parse_args()

    if args.command == "start":
        start_server()
    elif args.command == "stop":
        stop_server()
    elif args.command == "status":
        status_server()
    elif args.command == "tail":
        tail_logs(args.lines)


if __name__ == "__main__":
    main()

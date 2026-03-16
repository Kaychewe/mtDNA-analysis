#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import signal
import subprocess
import time
from pathlib import Path

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


def resolve_cromwell_jar(settings) -> Path:
    for path in (settings.cromwell_jar_path, settings.cromwell_jar_path_legacy):
        if path.exists():
            return path
    raise SystemExit(
        f"Missing Cromwell jar. Checked {settings.cromwell_jar_path} and "
        f"{settings.cromwell_jar_path_legacy}. Run check_environment.py first."
    )


def resolve_cromwell_conf(settings) -> Path:
    for path in (settings.cromwell_conf_path, settings.cromwell_conf_path_legacy):
        if path.exists():
            return path
    raise SystemExit(
        f"Missing Cromwell config. Checked {settings.cromwell_conf_path} and "
        f"{settings.cromwell_conf_path_legacy}. Run write_cromwell_config.py first."
    )


def start_server() -> None:
    settings = load_settings()
    ensure_dirs(settings)

    cromwell_jar = resolve_cromwell_jar(settings)
    cromwell_conf = resolve_cromwell_conf(settings)

    if cromwell_pid_running(str(settings.cromwell_pid_file)) and cromwell_up():
        print("Cromwell already running and healthy.")
        return

    sdkman_init = Path.home() / ".sdkman" / "bin" / "sdkman-init.sh"
    stdout = open(settings.cromwell_stdout_log, "a")
    stderr = open(settings.cromwell_stderr_log, "a")

    if sdkman_init.exists():
        # Use `exec java` so the recorded PID is the long-lived Cromwell JVM, not an
        # intermediate shell process. `start_new_session=True` fully detaches it from
        # the interactive terminal so Ctrl-C in the shell does not tear Cromwell down.
        process = subprocess.Popen(
            [
                "bash",
                "-lc",
                (
                    f"source {sdkman_init} && "
                    f"exec java -Xmx{settings.use_mem_gb}g "
                    f"-Dconfig.file={cromwell_conf} "
                    f"-Dwebservice.port={settings.port_id} "
                    f"-jar {cromwell_jar} server"
                ),
            ],
            stdout=stdout,
            stderr=stderr,
            cwd=settings.project_root,
            start_new_session=True,
        )
    else:
        process = subprocess.Popen(
            [
                "java",
                f"-Xmx{settings.use_mem_gb}g",
                f"-Dconfig.file={cromwell_conf}",
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
    stdout.close()
    stderr.close()

    for _ in range(30):
        if cromwell_up():
            print(f"Cromwell is up in the background (PID {process.pid}).")
            return
        time.sleep(2)

    tail_logs(40)
    raise SystemExit("Cromwell did not start. Check the log files above.")


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
    print("jar_path:", resolve_cromwell_jar(settings))
    print("conf_path:", resolve_cromwell_conf(settings))
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

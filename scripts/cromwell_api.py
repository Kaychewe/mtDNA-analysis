#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import time
from typing import Any

import requests

from aou_config import load_settings


_last_restart = 0.0


def cromwell_status_url() -> str:
    settings = load_settings()
    return f"http://localhost:{settings.port_id}/engine/v1/status"


def cromwell_api_base() -> str:
    settings = load_settings()
    return f"http://localhost:{settings.port_id}/api/workflows/v1"


def pretty(obj: Any) -> None:
    print(json.dumps(obj, indent=2))


def cromwell_up() -> bool:
    try:
        response = requests.get(cromwell_status_url(), timeout=2)
        return response.ok
    except Exception:
        return False


def get_wf_status(wf_id: str, retries: int = 10, sleep_s: int = 2) -> dict[str, Any]:
    url = f"{cromwell_api_base()}/{wf_id}/status"
    last_err = None
    for _ in range(retries):
        response = requests.get(url, timeout=30)
        if response.status_code == 200:
            return response.json()
        if response.status_code == 404:
            time.sleep(sleep_s)
            continue
        last_err = response
        break
    if last_err is not None:
        last_err.raise_for_status()
    raise RuntimeError(f"Workflow {wf_id} not found after {retries} retries.")


def get_wf_metadata(wf_id: str, include_keys: list[str] | None = None) -> dict[str, Any]:
    url = f"{cromwell_api_base()}/{wf_id}/metadata"
    params = []
    if include_keys:
        params = [("includeKey", key) for key in include_keys]
    response = requests.get(url, params=params, timeout=60)
    response.raise_for_status()
    return response.json()


def latest_workflow_id(wdl_name: str | None = None, status: str | None = None) -> str | None:
    params = {"page": 1, "pagesize": 20}
    if wdl_name:
        params["name"] = wdl_name
    if status:
        params["status"] = status

    response = requests.get(f"{cromwell_api_base()}/query", params=params, timeout=30)
    if response.status_code != 200:
        payload = {"page": 1, "pagesize": 20}
        if wdl_name:
            payload["name"] = wdl_name
        if status:
            payload["status"] = status
        response = requests.post(f"{cromwell_api_base()}/query", json=payload, timeout=30)

    response.raise_for_status()
    results = response.json().get("results", [])
    if not results:
        return None
    results.sort(key=lambda item: item.get("submission", ""), reverse=True)
    return results[0].get("id")


def get_callroots(wf_id: str) -> list[tuple[str, str]]:
    metadata = get_wf_metadata(wf_id, include_keys=["callRoot", "calls"])
    callroots: list[tuple[str, str]] = []
    calls = metadata.get("calls", {})
    for call_name, entries in calls.items():
        for entry in entries:
            if "callRoot" in entry:
                callroots.append((call_name, entry["callRoot"]))
    return callroots


def fetch_task_logs_from_gcs(wf_id: str, call_name: str | None = None) -> None:
    callroots = get_callroots(wf_id)
    if not callroots:
        print("No callRoot entries found.")
        return

    for name, root in callroots:
        if call_name and call_name != name:
            continue
        stdout = f"{root}/stdout"
        stderr = f"{root}/stderr"
        print(f"\nCall: {name}")
        print("stdout:", stdout)
        print("stderr:", stderr)
        subprocess.run(f"gsutil cat {stdout} | tail -n 50", shell=True, check=False)
        subprocess.run(f"gsutil cat {stderr} | tail -n 50", shell=True, check=False)


def latest_workflow_id_gcs(workspace_bucket: str, workflow_name: str) -> str | None:
    cmd = f"gsutil ls -l {workspace_bucket}/workflows/cromwell-executions/{workflow_name}/"
    output = subprocess.check_output(cmd, shell=True, text=True)
    lines = [line for line in output.splitlines() if line.strip().startswith("gs://")]
    if not lines:
        return None
    lines.sort()
    latest = lines[-1].split()[-1].rstrip("/")
    return latest.split("/")[-1]


def wait_for_wf(
    wf_id: str,
    poll_s: int = 5,
    timeout_s: int = 600,
    restart_callback: callable | None = None,
) -> str:
    global _last_restart

    deadline = time.time() + timeout_s
    while time.time() < deadline:
        try:
            status = get_wf_status(wf_id).get("status")
            print("Status:", status)
            if status in ("Succeeded", "Failed", "Aborted"):
                return status
        except Exception:
            now = time.time()
            if restart_callback is not None and now - _last_restart > 30:
                print("Cromwell not reachable; restarting...")
                restart_callback()
                _last_restart = now
        time.sleep(poll_s)
    raise TimeoutError(f"Workflow {wf_id} did not finish within {timeout_s}s")

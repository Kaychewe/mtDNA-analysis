#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

import requests

from aou_config import load_settings
from cromwell_api import (
    fetch_task_logs_from_gcs,
    get_wf_metadata,
    pretty,
    wait_for_wf,
)
from cromwell_server import start_server


def submit_workflow(wdl_path: Path, inputs_path: Path, dependencies_path: Path | None = None) -> str:
    settings = load_settings()
    api = f"http://localhost:{settings.port_id}/api/workflows/v1"

    with wdl_path.open("rb") as wdl_handle, inputs_path.open("rb") as inputs_handle:
        files = {
            "workflowSource": (wdl_path.name, wdl_handle, "text/plain"),
            "workflowInputs": (inputs_path.name, inputs_handle, "application/json"),
        }
        if dependencies_path is not None:
            dep_handle = dependencies_path.open("rb")
            files["workflowDependencies"] = (
                dependencies_path.name,
                dep_handle,
                "application/zip",
            )
        else:
            dep_handle = None

        try:
            response = requests.post(api, files=files, timeout=120)
        finally:
            if dep_handle is not None:
                dep_handle.close()

    response.raise_for_status()
    payload = response.json()
    workflow_id = payload["id"]
    print("Submitted workflow:", workflow_id)
    return workflow_id


def main() -> None:
    parser = argparse.ArgumentParser(description="Submit and optionally monitor the AoU one-sample mtDNA WDL.")
    parser.add_argument(
        "--wdl",
        default=str(Path(__file__).resolve().parents[1] / "wdl" / "aou_mitohpc_single_sample.wdl"),
    )
    parser.add_argument(
        "--inputs",
        default=str(Path(__file__).resolve().parents[1] / "inputs" / "test_one_sample_aou.json"),
    )
    parser.add_argument("--dependencies")
    parser.add_argument("--wait", action="store_true")
    parser.add_argument("--timeout-s", type=int, default=7200)
    parser.add_argument("--show-metadata", action="store_true")
    parser.add_argument("--fetch-logs", action="store_true")
    args = parser.parse_args()

    start_server()

    workflow_id = submit_workflow(
        Path(args.wdl),
        Path(args.inputs),
        Path(args.dependencies) if args.dependencies else None,
    )

    if args.wait:
        final_status = wait_for_wf(workflow_id, timeout_s=args.timeout_s, restart_callback=start_server)
        print("Final status:", final_status)

    if args.show_metadata:
        pretty(get_wf_metadata(workflow_id))

    if args.fetch_logs:
        fetch_task_logs_from_gcs(workflow_id)


if __name__ == "__main__":
    main()

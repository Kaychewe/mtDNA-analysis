#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPTS_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPTS_DIR.parent

if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import aou_config
import cromwell_api
import submit_one_sample
import write_cromwell_config


class AoUConfigTests(unittest.TestCase):
    def test_load_settings_defaults_to_project_root(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=True):
            settings = aou_config.load_settings()

        self.assertEqual(settings.project_root, PROJECT_ROOT)
        self.assertEqual(settings.port_id, 8094)
        self.assertEqual(settings.use_mem_gb, 32)
        self.assertEqual(settings.sql_db_name, "local_cromwell_run.db")

    def test_load_settings_respects_environment(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            env = {
                "PROJECT_ROOT": tmpdir,
                "WORKSPACE_BUCKET": "gs://example-bucket/",
                "GOOGLE_PROJECT": "example-project",
                "PET_SA_EMAIL": "pet@example.org",
                "PORTID": "8101",
                "USE_MEM": "48",
                "SQL_DB_NAME": "custom.db",
                "outputFold": "custom_output",
            }
            with mock.patch.dict(os.environ, env, clear=True):
                settings = aou_config.load_settings()

            self.assertEqual(settings.project_root, Path(tmpdir).resolve())
            self.assertEqual(settings.workspace_bucket, "gs://example-bucket")
            self.assertEqual(settings.google_project, "example-project")
            self.assertEqual(settings.pet_sa_email, "pet@example.org")
            self.assertEqual(settings.port_id, 8101)
            self.assertEqual(settings.use_mem_gb, 48)
            self.assertEqual(settings.sql_db_name, "custom.db")
            self.assertEqual(settings.output_fold, "custom_output")

    def test_ensure_dirs_creates_expected_paths(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            settings = aou_config.AoUSettings(
                workspace_bucket="",
                google_project="",
                pet_sa_email="",
                project_root=Path(tmpdir),
                output_fold="x",
                port_id=8094,
                use_mem_gb=32,
                sql_db_name="local.db",
            )
            aou_config.ensure_dirs(settings)

            self.assertTrue((Path(tmpdir) / "config").is_dir())
            self.assertTrue((Path(tmpdir) / "logs").is_dir())
            self.assertTrue((Path(tmpdir) / ".cromwell_db").is_dir())


class InputAndWdlTests(unittest.TestCase):
    def test_inputs_json_has_required_fields(self) -> None:
        inputs_path = PROJECT_ROOT / "inputs" / "test_one_sample_aou.json"
        payload = json.loads(inputs_path.read_text())

        required = {
            "AoUMitoHPCSingleSample.sample_name",
            "AoUMitoHPCSingleSample.wgs_aligned_input_cram",
            "AoUMitoHPCSingleSample.wgs_aligned_input_cram_index",
            "AoUMitoHPCSingleSample.ref_fasta",
            "AoUMitoHPCSingleSample.ref_fasta_index",
            "AoUMitoHPCSingleSample.ref_dict",
            "AoUMitoHPCSingleSample.docker",
        }
        self.assertTrue(required.issubset(payload))
        self.assertTrue(payload["AoUMitoHPCSingleSample.wgs_aligned_input_cram"].startswith("gs://"))
        self.assertTrue(payload["AoUMitoHPCSingleSample.wgs_aligned_input_cram_index"].endswith(".crai"))

    def test_wdl_contains_expected_workflow_shape(self) -> None:
        wdl_path = PROJECT_ROOT / "wdl" / "aou_mitohpc_single_sample.wdl"
        text = wdl_path.read_text()

        self.assertIn("workflow AoUMitoHPCSingleSample", text)
        self.assertIn("task RunAoUMitoHPCSingleSample", text)
        self.assertIn("/MitoHPC/scripts/filter.sh", text)
        self.assertIn("/MitoHPC/scripts/getSummary.sh", text)
        self.assertIn('docker = "dpuiu1/mitohpc:latest"', text)


class ConfigWriterTests(unittest.TestCase):
    def test_write_cromwell_config_generates_batch_conf(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            env = {
                "PROJECT_ROOT": tmpdir,
                "WORKSPACE_BUCKET": "gs://workspace-bucket",
                "GOOGLE_PROJECT": "project-123",
                "PET_SA_EMAIL": "pet@example.org",
            }
            with mock.patch.dict(os.environ, env, clear=True):
                write_cromwell_config.main()
                conf_path = Path(tmpdir) / "config" / "cromwell.batch.conf"

            self.assertTrue(conf_path.exists())
            conf = conf_path.read_text()
            self.assertIn('default = "GCPBATCH"', conf)
            self.assertIn('project = "project-123"', conf)
            self.assertIn('root = "gs://workspace-bucket/workflows/cromwell-executions"', conf)
            self.assertIn('compute-service-account = "pet@example.org"', conf)


class CromwellApiTests(unittest.TestCase):
    def test_get_callroots_extracts_pairs(self) -> None:
        metadata = {
            "calls": {
                "taskA": [{"callRoot": "gs://bucket/a"}],
                "taskB": [{"callRoot": "gs://bucket/b"}, {"other": "skip"}],
            }
        }
        with mock.patch.object(cromwell_api, "get_wf_metadata", return_value=metadata):
            roots = cromwell_api.get_callroots("wf-1")

        self.assertEqual(roots, [("taskA", "gs://bucket/a"), ("taskB", "gs://bucket/b")])

    def test_latest_workflow_id_uses_query_results(self) -> None:
        response = mock.Mock()
        response.status_code = 200
        response.json.return_value = {
            "results": [
                {"id": "older", "submission": "2025-01-01T00:00:00Z"},
                {"id": "newer", "submission": "2025-02-01T00:00:00Z"},
            ]
        }
        response.raise_for_status.return_value = None
        with mock.patch.object(cromwell_api.requests, "get", return_value=response):
            workflow_id = cromwell_api.latest_workflow_id("AoUMitoHPCSingleSample")

        self.assertEqual(workflow_id, "newer")

    def test_wait_for_wf_returns_terminal_status(self) -> None:
        statuses = [{"status": "Running"}, {"status": "Succeeded"}]
        with mock.patch.object(cromwell_api, "get_wf_status", side_effect=statuses):
            with mock.patch.object(cromwell_api.time, "sleep", return_value=None):
                final_status = cromwell_api.wait_for_wf("wf-1", poll_s=0, timeout_s=10)

        self.assertEqual(final_status, "Succeeded")


class SubmissionTests(unittest.TestCase):
    def test_submit_workflow_posts_wdl_and_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            wdl_path = Path(tmpdir) / "test.wdl"
            inputs_path = Path(tmpdir) / "test.json"
            wdl_path.write_text("version 1.0\n")
            inputs_path.write_text("{}\n")

            response = mock.Mock()
            response.raise_for_status.return_value = None
            response.json.return_value = {"id": "wf-123"}

            with mock.patch.dict(os.environ, {"PORTID": "8099"}, clear=True):
                with mock.patch.object(submit_one_sample.requests, "post", return_value=response) as mock_post:
                    workflow_id = submit_one_sample.submit_workflow(wdl_path, inputs_path)

            self.assertEqual(workflow_id, "wf-123")
            self.assertEqual(mock_post.call_args.args[0], "http://localhost:8099/api/workflows/v1")
            files = mock_post.call_args.kwargs["files"]
            self.assertIn("workflowSource", files)
            self.assertIn("workflowInputs", files)


class ReadmeTests(unittest.TestCase):
    def test_readme_mentions_single_command_test_runner(self) -> None:
        readme = (PROJECT_ROOT / "README.md").read_text()
        self.assertIn("python scripts/run_tests.py", readme)


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)

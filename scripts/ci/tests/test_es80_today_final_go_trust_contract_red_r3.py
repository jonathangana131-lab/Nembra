#!/usr/bin/env python3
"""Expected-red V14 regressions for the remaining Final GO trust-contract gaps.

Validation only. This file grants no product, Bluetooth, or physical authority.
"""
from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock
import zipfile

SCRIPT_DIR = Path(__file__).resolve().parents[1]


def _load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPT_DIR / filename)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


trusted = _load("trusted_xcode_red_r3", "es80_today_trusted_capture_xcode_subject.py")
hardened = _load("hardened_red_r3", "es80_today_final_go_hardened.py")


class FinalGoTrustContractRedR3(unittest.TestCase):
    def test_trusted_subject_rejects_ambiguous_schema_drifted_retained_record(self) -> None:
        source = "1" * 40
        workflow_source = "2" * 40
        pr_number = 77
        run_id = 101
        job_id = 202
        artifact_id = 303

        # This record violates the already-merged foundation contract in several independent ways:
        # duplicate authority key, extra field, wrong exact build label/recipe/procedure, malformed
        # build instance, and malformed executable/Info.plist digests. A trust-root migration must
        # not make any of those bytes acceptable merely because the default-branch workflow ran.
        record = (
            '{'
            '"schemaVersion":3,'
            '"buildIdentifier":"Capture Build V14-deadbeefdead",'
            '"buildInstanceID":"not-a-canonical-uuid",'
            f'"sourceCommitSHA":"{source}",'
            f'"sourceCommitSHA":"{source}",'
            '"executableSHA256":"bad",'
            '"infoPlistSHA256":"bad",'
            '"experimentRecipeID":"ES80-FINGERPRINT-v999",'
            '"procedureVersion":"V999",'
            '"extraCallerField":true'
            '}'
        ).encode()

        with tempfile.TemporaryDirectory() as temporary:
            archive_path = Path(temporary) / "trusted.zip"
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr(trusted.EXTERNAL_RECORD_NAME, record)
            archive_raw = archive_path.read_bytes()
            archive_sha = hashlib.sha256(archive_raw).hexdigest()

            payloads = {
                f"/pulls/{pr_number}": {
                    "number": pr_number,
                    "state": "open",
                    "head": {"sha": source, "repo": {"full_name": trusted.REPOSITORY}},
                    "base": {"repo": {"full_name": trusted.REPOSITORY}},
                },
                f"/actions/runs/{run_id}": {
                    "id": run_id,
                    "name": trusted.TRUSTED_WORKFLOW_NAME,
                    "path": trusted.TRUSTED_WORKFLOW_PATH,
                    "event": "issue_comment",
                    "status": "completed",
                    "conclusion": "success",
                    "repository": {"full_name": trusted.REPOSITORY},
                    "head_repository": {"full_name": trusted.REPOSITORY},
                    "head_branch": trusted.DEFAULT_BRANCH,
                    "actor": {"login": trusted.REPOSITORY_OWNER},
                    "triggering_actor": {"login": trusted.REPOSITORY_OWNER},
                    "head_sha": workflow_source,
                    "run_attempt": 1,
                    "run_number": 5,
                },
                f"/actions/jobs/{job_id}": {
                    "id": job_id,
                    "run_id": run_id,
                    "run_attempt": 1,
                    "workflow_name": trusted.TRUSTED_WORKFLOW_NAME,
                    "name": trusted.TRUSTED_JOB_NAME,
                    "head_sha": workflow_source,
                    "status": "completed",
                    "conclusion": "success",
                    "labels": ["xcode-27"],
                    "steps": [
                        {"name": name, "conclusion": "success"}
                        for name in trusted.REQUIRED_SUCCESSFUL_STEPS
                    ],
                },
                f"/actions/artifacts/{artifact_id}": {
                    "id": artifact_id,
                    "name": f"{trusted.TRUSTED_ARTIFACT_PREFIX}{pr_number}-5-1",
                    "expired": False,
                    "digest": f"sha256:{archive_sha}",
                    "size_in_bytes": len(archive_raw),
                    "workflow_run": {"id": run_id, "head_sha": workflow_source},
                },
            }

            def github_get_json(path: str):
                return b"{}", payloads[path]

            with self.assertRaises(trusted.TrustedCaptureXcodeError):
                trusted.verify_trusted_capture_xcode_subject(
                    source_commit_sha=source,
                    expected_pr_number=pr_number,
                    run_id=run_id,
                    job_id=job_id,
                    artifact_id=artifact_id,
                    artifact_archive_path=archive_path,
                    github_get_json=github_get_json,
                    workflow_blob_sha_at_commit=lambda commit, path: trusted.TRUSTED_WORKFLOW_BLOB_SHA,
                )

    def test_workflow_blob_lookup_ignores_caller_git_object_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary) / "repo"
            repo.mkdir()
            subprocess.run(["/usr/bin/git", "init", "-q", str(repo)], check=True)
            workflow = repo / trusted.TRUSTED_WORKFLOW_PATH
            workflow.parent.mkdir(parents=True)
            workflow.write_text("name: trusted-test\n", encoding="utf-8")
            subprocess.run(["/usr/bin/git", "-C", str(repo), "add", "."], check=True)
            subprocess.run(
                [
                    "/usr/bin/git", "-C", str(repo),
                    "-c", "user.name=Nembra QA",
                    "-c", "user.email=nembra-qa@example.invalid",
                    "commit", "-q", "-m", "fixture",
                ],
                check=True,
            )
            commit = subprocess.check_output(
                ["/usr/bin/git", "-C", str(repo), "rev-parse", "HEAD"], text=True
            ).strip()
            expected_blob = subprocess.check_output(
                [
                    "/usr/bin/git", "-C", str(repo), "rev-parse",
                    f"{commit}:{trusted.TRUSTED_WORKFLOW_PATH}",
                ],
                text=True,
            ).strip()
            poison = Path(temporary) / "poison-objects"
            poison.mkdir()

            with mock.patch.dict(
                os.environ,
                {"GIT_OBJECT_DIRECTORY": str(poison)},
                clear=False,
            ):
                actual = hardened._workflow_blob_sha_at_commit(
                    repo,
                    commit,
                    trusted.TRUSTED_WORKFLOW_PATH,
                )

            self.assertEqual(actual, expected_blob)


if __name__ == "__main__":
    unittest.main()

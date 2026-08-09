#!/usr/bin/env python3
"""Expected-red proof that Final GO must consume one immutable downloaded Xcode ZIP snapshot."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import zipfile

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_trusted_capture_xcode_subject.py"
SPEC = importlib.util.spec_from_file_location("trusted_xcode_download_snapshot_redteam", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load trusted Xcode subject verifier")
trusted_xcode = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(trusted_xcode)


class DownloadedArtifactSingleSnapshotCustodyTests(unittest.TestCase):
    SOURCE = "a" * 40
    WORKFLOW_SOURCE = "b" * 40
    PR = 833
    RUN = 1001
    JOB = 2002
    ARTIFACT = 3003
    RUN_NUMBER = 44
    RUN_ATTEMPT = 1
    INSTANCE_A = "11111111-2222-3333-4444-555555555555"
    INSTANCE_B = "66666666-7777-8888-9999-aaaaaaaaaaaa"

    def record(self, build_instance: str) -> bytes:
        value = {
            "schemaVersion": 3,
            "buildIdentifier": "Capture Build V14-" + self.SOURCE[:12],
            "buildInstanceID": build_instance,
            "sourceCommitSHA": self.SOURCE,
            "executableSHA256": "c" * 64,
            "infoPlistSHA256": "d" * 64,
            "experimentRecipeID": "ES80-FINGERPRINT-v1",
            "procedureVersion": "V14",
        }
        return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()

    def make_archive(self, path: Path, build_instance: str) -> bytes:
        with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_STORED) as archive:
            info = zipfile.ZipInfo(trusted_xcode.EXTERNAL_RECORD_NAME)
            info.date_time = (2026, 8, 8, 12, 0, 0)
            info.compress_type = zipfile.ZIP_STORED
            archive.writestr(info, self.record(build_instance))
        return path.read_bytes()

    def github_records(self, archive_sha: str, archive_size: int) -> dict[str, dict]:
        return {
            f"/pulls/{self.PR}": {
                "number": self.PR,
                "state": "open",
                "head": {"sha": self.SOURCE, "repo": {"full_name": trusted_xcode.REPOSITORY}},
                "base": {"repo": {"full_name": trusted_xcode.REPOSITORY}},
            },
            f"/actions/runs/{self.RUN}": {
                "id": self.RUN,
                "name": trusted_xcode.TRUSTED_WORKFLOW_NAME,
                "path": trusted_xcode.TRUSTED_WORKFLOW_PATH,
                "event": "issue_comment",
                "head_sha": self.WORKFLOW_SOURCE,
                "head_branch": trusted_xcode.DEFAULT_BRANCH,
                "status": "completed",
                "conclusion": "success",
                "run_attempt": self.RUN_ATTEMPT,
                "run_number": self.RUN_NUMBER,
                "repository": {"full_name": trusted_xcode.REPOSITORY},
                "head_repository": {"full_name": trusted_xcode.REPOSITORY},
                "actor": {"login": trusted_xcode.REPOSITORY_OWNER},
                "triggering_actor": {"login": trusted_xcode.REPOSITORY_OWNER},
            },
            f"/actions/jobs/{self.JOB}": {
                "id": self.JOB,
                "run_id": self.RUN,
                "run_attempt": self.RUN_ATTEMPT,
                "workflow_name": trusted_xcode.TRUSTED_WORKFLOW_NAME,
                "name": trusted_xcode.TRUSTED_JOB_NAME,
                "head_sha": self.WORKFLOW_SOURCE,
                "status": "completed",
                "conclusion": "success",
                "labels": ["self-hosted", "xcode-27"],
                "steps": [
                    {"name": name, "conclusion": "success"}
                    for name in trusted_xcode.REQUIRED_SUCCESSFUL_STEPS
                ],
            },
            f"/actions/artifacts/{self.ARTIFACT}": {
                "id": self.ARTIFACT,
                "name": (
                    f"{trusted_xcode.TRUSTED_ARTIFACT_PREFIX}{self.PR}-"
                    f"{self.RUN_NUMBER}-{self.RUN_ATTEMPT}"
                ),
                "expired": False,
                "digest": f"sha256:{archive_sha}",
                "size_in_bytes": archive_size,
                "workflow_run": {"id": self.RUN, "head_sha": self.WORKFLOW_SOURCE},
            },
        }

    def test_server_digested_archive_cannot_change_between_hash_and_zip_inspection(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "downloaded.zip"
            replacement = root / "replacement.zip"
            raw_a = self.make_archive(archive, self.INSTANCE_A)
            raw_b = self.make_archive(replacement, self.INSTANCE_B)
            self.assertEqual(len(raw_a), len(raw_b), "fixture must preserve server-declared byte count")
            self.assertNotEqual(raw_a, raw_b, "fixture archives must be distinct byte subjects")

            records = self.github_records(hashlib.sha256(raw_a).hexdigest(), len(raw_a))

            def github_get_json(path: str):
                value = records[path]
                return json.dumps(value, sort_keys=True).encode(), value

            def workflow_blob_at_commit(commit: str, path: str) -> str:
                if path == trusted_xcode.TRUSTED_WORKFLOW_PATH:
                    self.assertEqual(commit, self.WORKFLOW_SOURCE)
                    return trusted_xcode.TRUSTED_WORKFLOW_BLOB_SHA
                if path == trusted_xcode.TRUSTED_SIMULATOR_EVIDENCE_PRODUCER_PATH:
                    self.assertEqual(commit, self.SOURCE)
                    return trusted_xcode.TRUSTED_SIMULATOR_EVIDENCE_PRODUCER_BLOB_SHA
                raise AssertionError(f"unexpected Git blob lookup: {commit}:{path}")

            original_sha256_file = trusted_xcode._sha256_file
            swapped = False

            def hash_then_swap(path: Path) -> str:
                nonlocal swapped
                digest = original_sha256_file(path)
                os.replace(replacement, archive)
                swapped = True
                return digest

            with mock.patch.object(trusted_xcode, "_sha256_file", side_effect=hash_then_swap):
                try:
                    subject = trusted_xcode.verify_trusted_capture_xcode_subject(
                        source_commit_sha=self.SOURCE,
                        expected_pr_number=self.PR,
                        run_id=self.RUN,
                        job_id=self.JOB,
                        artifact_id=self.ARTIFACT,
                        artifact_archive_path=archive,
                        github_get_json=github_get_json,
                        workflow_blob_sha_at_commit=workflow_blob_at_commit,
                    )
                except trusted_xcode.TrustedCaptureXcodeError:
                    return

            self.assertTrue(swapped, "red-team archive swap did not execute")
            self.assertEqual(
                subject["artifactArchiveSHA256"],
                hashlib.sha256(raw_a).hexdigest(),
                "server digest fixture no longer describes archive A",
            )
            self.assertNotEqual(
                subject["externalBuildRecord"]["buildInstanceID"],
                self.INSTANCE_B,
                "Final GO mixed archive A's server digest with archive B's embedded record",
            )
            self.assertEqual(subject["externalBuildRecord"]["buildInstanceID"], self.INSTANCE_A)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Prove trusted Xcode download digest, size, and embedded record share one byte snapshot."""
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
SPEC = importlib.util.spec_from_file_location("trusted_xcode_snapshot_custody", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load trusted Xcode subject verifier")
trusted_xcode = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(trusted_xcode)


class TrustedXcodeDownloadSnapshotCustodyTests(unittest.TestCase):
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

    def verify(self, archive: Path, records: dict[str, dict]):
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

        return trusted_xcode.verify_trusted_capture_xcode_subject(
            source_commit_sha=self.SOURCE,
            expected_pr_number=self.PR,
            run_id=self.RUN,
            job_id=self.JOB,
            artifact_id=self.ARTIFACT,
            artifact_archive_path=archive,
            github_get_json=github_get_json,
            workflow_blob_sha_at_commit=workflow_blob_at_commit,
        )

    def test_path_replacement_after_snapshot_cannot_change_embedded_record(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "downloaded.zip"
            replacement = root / "replacement.zip"
            raw_a = self.make_archive(archive, self.INSTANCE_A)
            raw_b = self.make_archive(replacement, self.INSTANCE_B)
            self.assertEqual(len(raw_a), len(raw_b))
            self.assertNotEqual(raw_a, raw_b)
            records = self.github_records(hashlib.sha256(raw_a).hexdigest(), len(raw_a))

            original_snapshot = trusted_xcode._read_exact_archive
            swapped = False

            def snapshot_then_swap(path: Path) -> bytes:
                nonlocal swapped
                raw = original_snapshot(path)
                os.replace(replacement, archive)
                swapped = True
                return raw

            with mock.patch.object(trusted_xcode, "_read_exact_archive", side_effect=snapshot_then_swap):
                subject = self.verify(archive, records)

            self.assertTrue(swapped)
            self.assertEqual(subject["artifactArchiveSHA256"], hashlib.sha256(raw_a).hexdigest())
            self.assertEqual(subject["artifactArchiveByteCount"], len(raw_a))
            self.assertEqual(subject["externalBuildRecord"]["buildInstanceID"], self.INSTANCE_A)

    def test_descriptor_snapshot_survives_path_replacement_during_read(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "downloaded.zip"
            replacement = root / "replacement.zip"
            raw_a = self.make_archive(archive, self.INSTANCE_A)
            self.make_archive(replacement, self.INSTANCE_B)
            original_read = os.read
            swapped = False

            def read_after_swap(fd: int, count: int) -> bytes:
                nonlocal swapped
                if not swapped:
                    os.replace(replacement, archive)
                    swapped = True
                return original_read(fd, count)

            with mock.patch.object(os, "read", side_effect=read_after_swap):
                observed = trusted_xcode._read_exact_archive(archive)
            self.assertTrue(swapped)
            self.assertEqual(observed, raw_a)

    def test_symlink_archive_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / "target.zip"
            link = root / "downloaded.zip"
            self.make_archive(target, self.INSTANCE_A)
            link.symlink_to(target)
            with self.assertRaises(trusted_xcode.TrustedCaptureXcodeError):
                trusted_xcode._read_exact_archive(link)


if __name__ == "__main__":
    unittest.main()

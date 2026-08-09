#!/usr/bin/env python3
"""Regression coverage for descriptor-bound trusted-Xcode artifact snapshot custody."""
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
SPEC = importlib.util.spec_from_file_location("trusted_xcode_download_snapshot_custody", MODULE_PATH)
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

    def workflow_blob_at_commit(self, commit: str, path: str) -> str:
        if path == trusted_xcode.TRUSTED_WORKFLOW_PATH:
            self.assertEqual(commit, self.WORKFLOW_SOURCE)
            return trusted_xcode.TRUSTED_WORKFLOW_BLOB_SHA
        if path == trusted_xcode.TRUSTED_SIMULATOR_EVIDENCE_PRODUCER_PATH:
            self.assertEqual(commit, self.SOURCE)
            return trusted_xcode.TRUSTED_SIMULATOR_EVIDENCE_PRODUCER_BLOB_SHA
        raise AssertionError(f"unexpected Git blob lookup: {commit}:{path}")

    def test_server_digest_and_external_record_share_one_opened_archive_snapshot(self) -> None:
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

            original_snapshot = trusted_xcode._read_archive_snapshot
            swapped = False

            def snapshot_then_swap(path: Path) -> bytes:
                nonlocal swapped
                raw = original_snapshot(path)
                os.replace(replacement, archive)
                swapped = True
                return raw

            with mock.patch.object(
                trusted_xcode,
                "_read_archive_snapshot",
                side_effect=snapshot_then_swap,
            ):
                subject = trusted_xcode.verify_trusted_capture_xcode_subject(
                    source_commit_sha=self.SOURCE,
                    expected_pr_number=self.PR,
                    run_id=self.RUN,
                    job_id=self.JOB,
                    artifact_id=self.ARTIFACT,
                    artifact_archive_path=archive,
                    github_get_json=github_get_json,
                    workflow_blob_sha_at_commit=self.workflow_blob_at_commit,
                )

            self.assertTrue(swapped, "archive pathname replacement did not execute")
            self.assertEqual(archive.read_bytes(), raw_b, "replacement fixture did not become pathname B")
            self.assertEqual(subject["artifactArchiveSHA256"], hashlib.sha256(raw_a).hexdigest())
            self.assertEqual(subject["artifactArchiveByteCount"], len(raw_a))
            self.assertEqual(subject["externalBuildRecord"]["buildInstanceID"], self.INSTANCE_A)
            self.assertNotEqual(subject["externalBuildRecord"]["buildInstanceID"], self.INSTANCE_B)

    def test_same_inode_same_size_in_place_mutation_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / "downloaded.zip"
            archive.write_bytes(b"A" * (2 * 1024 * 1024))
            before = archive.stat()
            original_read = trusted_xcode.os.read
            mutated = False

            def read_then_mutate(descriptor: int, count: int) -> bytes:
                nonlocal mutated
                chunk = original_read(descriptor, count)
                if chunk and not mutated:
                    with archive.open("r+b", buffering=0) as writer:
                        writer.seek(1024 * 1024)
                        writer.write(b"B" * 4096)
                        os.fsync(writer.fileno())
                    mutated = True
                return chunk

            with mock.patch.object(trusted_xcode.os, "read", side_effect=read_then_mutate):
                with self.assertRaisesRegex(
                    trusted_xcode.TrustedCaptureXcodeError,
                    "changed while reading",
                ):
                    trusted_xcode._read_archive_snapshot(archive)

            after = archive.stat()
            self.assertTrue(mutated, "same-inode mutation fixture did not execute")
            self.assertEqual(
                (before.st_dev, before.st_ino, before.st_size),
                (after.st_dev, after.st_ino, after.st_size),
                "regression must preserve the fields already checked by the verifier",
            )

    @unittest.skipUnless(hasattr(os, "O_NOFOLLOW"), "platform does not expose O_NOFOLLOW")
    def test_downloaded_archive_symlink_is_not_an_admissible_subject(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / "target.zip"
            self.make_archive(target, self.INSTANCE_A)
            alias = root / "downloaded.zip"
            alias.symlink_to(target)

            with self.assertRaises(trusted_xcode.TrustedCaptureXcodeError):
                trusted_xcode._read_archive_snapshot(alias)


if __name__ == "__main__":
    unittest.main()

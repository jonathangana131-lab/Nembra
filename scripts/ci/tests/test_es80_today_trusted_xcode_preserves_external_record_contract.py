#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

MODULE_DIR = Path(__file__).resolve().parents[1]


def _load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, MODULE_DIR / filename)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {filename}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


trusted = _load("nembra_trusted_capture_xcode_subject", "es80_today_trusted_capture_xcode_subject.py")
foundation = _load("nembra_final_go_foundation", "es80_today_final_go_record.py")


class TrustedXcodeExternalRecordContractTests(unittest.TestCase):
    SOURCE = "a" * 40
    WORKFLOW_SOURCE = "b" * 40
    PR_NUMBER = 833
    RUN_ID = 44001
    JOB_ID = 55001
    ARTIFACT_ID = 66001
    RUN_NUMBER = 17
    RUN_ATTEMPT = 1

    def _archive(self, root: Path, external_record: dict[str, object]) -> Path:
        path = root / "trusted-xcode.zip"
        with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr(
                f"evidence/{trusted.EXTERNAL_RECORD_NAME}",
                json.dumps(external_record, sort_keys=True).encode("utf-8"),
            )
        return path

    def _github_get_json(self, archive: Path):
        archive_sha = hashlib.sha256(archive.read_bytes()).hexdigest()
        size = archive.stat().st_size
        mapping = {
            f"/pulls/{self.PR_NUMBER}": {
                "number": self.PR_NUMBER,
                "state": "open",
                "head": {
                    "sha": self.SOURCE,
                    "repo": {"full_name": trusted.REPOSITORY},
                },
                "base": {"repo": {"full_name": trusted.REPOSITORY}},
            },
            f"/actions/runs/{self.RUN_ID}": {
                "id": self.RUN_ID,
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
                "head_sha": self.WORKFLOW_SOURCE,
                "run_attempt": self.RUN_ATTEMPT,
                "run_number": self.RUN_NUMBER,
            },
            f"/actions/jobs/{self.JOB_ID}": {
                "id": self.JOB_ID,
                "run_id": self.RUN_ID,
                "run_attempt": self.RUN_ATTEMPT,
                "workflow_name": trusted.TRUSTED_WORKFLOW_NAME,
                "name": trusted.TRUSTED_JOB_NAME,
                "head_sha": self.WORKFLOW_SOURCE,
                "status": "completed",
                "conclusion": "success",
                "labels": ["self-hosted", "xcode-27"],
                "steps": [
                    {"name": name, "conclusion": "success"}
                    for name in trusted.REQUIRED_SUCCESSFUL_STEPS
                ],
            },
            f"/actions/artifacts/{self.ARTIFACT_ID}": {
                "id": self.ARTIFACT_ID,
                "name": (
                    f"{trusted.TRUSTED_ARTIFACT_PREFIX}{self.PR_NUMBER}-"
                    f"{self.RUN_NUMBER}-{self.RUN_ATTEMPT}"
                ),
                "expired": False,
                "digest": f"sha256:{archive_sha}",
                "size_in_bytes": size,
                "workflow_run": {
                    "id": self.RUN_ID,
                    "head_sha": self.WORKFLOW_SOURCE,
                },
            },
        }

        def get(path: str):
            value = mapping[path]
            return json.dumps(value, sort_keys=True).encode("utf-8"), value

        return get

    def test_default_branch_adapter_preserves_foundation_external_record_schema(self) -> None:
        malformed_record = {
            "sourceCommitSHA": self.SOURCE,
            "buildIdentifier": f"Capture Build V14-{self.SOURCE[:12]}",
            "buildInstanceID": "not-a-canonical-build-instance-uuid",
        }

        with tempfile.TemporaryDirectory() as directory:
            archive = self._archive(Path(directory), malformed_record)

            with self.assertRaises(foundation.FinalGoError):
                foundation._inspect_xcode_archive(archive, self.SOURCE)

            with self.assertRaises(trusted.TrustedCaptureXcodeError):
                trusted.verify_trusted_capture_xcode_subject(
                    source_commit_sha=self.SOURCE,
                    expected_pr_number=self.PR_NUMBER,
                    run_id=self.RUN_ID,
                    job_id=self.JOB_ID,
                    artifact_id=self.ARTIFACT_ID,
                    artifact_archive_path=archive,
                    github_get_json=self._github_get_json(archive),
                    workflow_blob_sha_at_commit=lambda _commit, _path: trusted.TRUSTED_WORKFLOW_BLOB_SHA,
                )


if __name__ == "__main__":
    unittest.main()

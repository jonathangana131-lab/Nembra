#!/usr/bin/env python3
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_trusted_capture_xcode_subject.py"
spec = importlib.util.spec_from_file_location("trusted_xcode", MODULE_PATH)
trusted_xcode = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(trusted_xcode)


class TrustedCaptureXcodeSubjectTests(unittest.TestCase):
    SOURCE = "a" * 40
    WORKFLOW_SOURCE = "b" * 40
    PR = 833
    RUN = 1001
    JOB = 2002
    ARTIFACT = 3003
    RUN_NUMBER = 44
    RUN_ATTEMPT = 1

    def make_archive(self, root: Path, *, source: str | None = None) -> tuple[Path, str, int]:
        record = {
            "schemaVersion": 3,
            "buildIdentifier": "Capture Build V14-" + self.SOURCE[:12],
            "buildInstanceID": "11111111-2222-3333-4444-555555555555",
            "sourceCommitSHA": source or self.SOURCE,
            "executableSHA256": "c" * 64,
            "infoPlistSHA256": "d" * 64,
            "experimentRecipeID": "ES80-FINGERPRINT-v1",
            "procedureVersion": "V14",
        }
        return self.make_raw_archive(
            root,
            (json.dumps(record, sort_keys=True) + "\n").encode(),
        )

    def make_raw_archive(self, root: Path, raw_record: bytes) -> tuple[Path, str, int]:
        path = root / "artifact.zip"
        with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr(trusted_xcode.EXTERNAL_RECORD_NAME, raw_record)
        raw = path.read_bytes()
        return path, hashlib.sha256(raw).hexdigest(), len(raw)

    def trusted_records(self, archive_sha: str, archive_size: int) -> dict[str, dict]:
        pr = {
            "number": self.PR,
            "state": "open",
            "head": {
                "sha": self.SOURCE,
                "repo": {"full_name": trusted_xcode.REPOSITORY},
            },
            "base": {"repo": {"full_name": trusted_xcode.REPOSITORY}},
        }
        run = {
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
        }
        job = {
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
        }
        artifact = {
            "id": self.ARTIFACT,
            "name": f"{trusted_xcode.TRUSTED_ARTIFACT_PREFIX}{self.PR}-{self.RUN_NUMBER}-{self.RUN_ATTEMPT}",
            "expired": False,
            "digest": f"sha256:{archive_sha}",
            "size_in_bytes": archive_size,
            "workflow_run": {"id": self.RUN, "head_sha": self.WORKFLOW_SOURCE},
        }
        return {
            f"/pulls/{self.PR}": pr,
            f"/actions/runs/{self.RUN}": run,
            f"/actions/jobs/{self.JOB}": job,
            f"/actions/artifacts/{self.ARTIFACT}": artifact,
        }

    def verify(self, archive: Path, records: dict[str, dict], *, blob: str | None = None):
        def get(path: str):
            value = records[path]
            return json.dumps(value, sort_keys=True).encode(), value

        def blob_at(commit: str, path: str) -> str:
            self.assertEqual(commit, self.WORKFLOW_SOURCE)
            self.assertEqual(path, trusted_xcode.TRUSTED_WORKFLOW_PATH)
            return blob or trusted_xcode.TRUSTED_WORKFLOW_BLOB_SHA

        return trusted_xcode.verify_trusted_capture_xcode_subject(
            source_commit_sha=self.SOURCE,
            expected_pr_number=self.PR,
            run_id=self.RUN,
            job_id=self.JOB,
            artifact_id=self.ARTIFACT,
            artifact_archive_path=archive,
            github_get_json=get,
            workflow_blob_sha_at_commit=blob_at,
        )

    def test_accepts_owner_issued_default_branch_subject_and_binds_candidate_separately(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive, archive_sha, archive_size = self.make_archive(Path(temporary))
            subject = self.verify(archive, self.trusted_records(archive_sha, archive_size))

        self.assertEqual(subject["authority"], "default-branch-owner-command-v1")
        self.assertEqual(subject["candidateSourceCommitSHA"], self.SOURCE)
        self.assertEqual(subject["workflowSourceCommitSHA"], self.WORKFLOW_SOURCE)
        self.assertEqual(subject["workflowBlobSHA"], trusted_xcode.TRUSTED_WORKFLOW_BLOB_SHA)
        self.assertNotEqual(subject["candidateSourceCommitSHA"], subject["workflowSourceCommitSHA"])

    def test_rejects_candidate_pr_controlled_workflow_even_with_exact_candidate_artifact(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive, archive_sha, archive_size = self.make_archive(Path(temporary))
            records = self.trusted_records(archive_sha, archive_size)
            run = records[f"/actions/runs/{self.RUN}"]
            run.update(
                name="Xcode 27 PR Exact-Head QA",
                path=".github/workflows/xcode27-pr-command.yml",
                event="pull_request",
                head_sha=self.SOURCE,
                head_branch="feature/candidate-controlled",
            )
            job = records[f"/actions/jobs/{self.JOB}"]
            job.update(
                workflow_name="Xcode 27 PR Exact-Head QA",
                name="Build, test, and capture exact PR head",
                head_sha=self.SOURCE,
            )
            records[f"/actions/artifacts/{self.ARTIFACT}"]["workflow_run"]["head_sha"] = self.SOURCE

            with self.assertRaises(trusted_xcode.TrustedCaptureXcodeError):
                self.verify(archive, records)

    def test_rejects_unpinned_default_branch_workflow_blob(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive, archive_sha, archive_size = self.make_archive(Path(temporary))
            records = self.trusted_records(archive_sha, archive_size)
            with self.assertRaisesRegex(
                trusted_xcode.TrustedCaptureXcodeError,
                "workflow implementation blob",
            ):
                self.verify(archive, records, blob="f" * 40)

    def test_rejects_non_owner_command_actor(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive, archive_sha, archive_size = self.make_archive(Path(temporary))
            records = self.trusted_records(archive_sha, archive_size)
            records[f"/actions/runs/{self.RUN}"]["actor"] = {"login": "not-the-owner"}
            with self.assertRaisesRegex(trusted_xcode.TrustedCaptureXcodeError, "command actor"):
                self.verify(archive, records)

    def test_rejects_live_pr_head_movement(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive, archive_sha, archive_size = self.make_archive(Path(temporary))
            records = self.trusted_records(archive_sha, archive_size)
            records[f"/pulls/{self.PR}"]["head"]["sha"] = "e" * 40
            with self.assertRaisesRegex(trusted_xcode.TrustedCaptureXcodeError, "live PR head"):
                self.verify(archive, records)

    def test_rejects_artifact_with_different_candidate_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive, archive_sha, archive_size = self.make_archive(root, source="e" * 40)
            records = self.trusted_records(archive_sha, archive_size)
            with self.assertRaisesRegex(trusted_xcode.TrustedCaptureXcodeError, "different Capture source"):
                self.verify(archive, records)

    def test_rejects_missing_final_head_step_even_when_job_conclusion_is_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive, archive_sha, archive_size = self.make_archive(Path(temporary))
            records = self.trusted_records(archive_sha, archive_size)
            job = records[f"/actions/jobs/{self.JOB}"]
            job["steps"] = [
                step
                for step in job["steps"]
                if step["name"] != "Reject head movement before trusted acceptance completes"
            ]
            with self.assertRaisesRegex(trusted_xcode.TrustedCaptureXcodeError, "required step"):
                self.verify(archive, records)

    def test_rejects_weaker_external_record_shape_instead_of_dropping_foundation_contract(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            weak_record = {
                "sourceCommitSHA": self.SOURCE,
                "buildIdentifier": f"Capture Build V14-{self.SOURCE[:12]}",
                "buildInstanceID": "not-a-canonical-uuid",
            }
            archive, archive_sha, archive_size = self.make_raw_archive(
                root,
                (json.dumps(weak_record, sort_keys=True) + "\n").encode(),
            )
            records = self.trusted_records(archive_sha, archive_size)
            with self.assertRaisesRegex(
                trusted_xcode.TrustedCaptureXcodeError,
                "schema shape",
            ):
                self.verify(archive, records)

    def test_rejects_duplicate_keys_in_retained_external_record(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            raw = (
                "{"
                '"schemaVersion":3,'
                f'"buildIdentifier":"Capture Build V14-{self.SOURCE[:12]}",'
                '"buildInstanceID":"11111111-2222-3333-4444-555555555555",'
                f'"sourceCommitSHA":"{self.SOURCE}",'
                f'"sourceCommitSHA":"{self.SOURCE}",'
                f'"executableSHA256":"{"c" * 64}",'
                f'"infoPlistSHA256":"{"d" * 64}",'
                '"experimentRecipeID":"ES80-FINGERPRINT-v1",'
                '"procedureVersion":"V14"'
                "}\n"
            ).encode()
            archive, archive_sha, archive_size = self.make_raw_archive(root, raw)
            records = self.trusted_records(archive_sha, archive_size)
            with self.assertRaisesRegex(
                trusted_xcode.TrustedCaptureXcodeError,
                "duplicate key",
            ):
                self.verify(archive, records)


if __name__ == "__main__":
    unittest.main()

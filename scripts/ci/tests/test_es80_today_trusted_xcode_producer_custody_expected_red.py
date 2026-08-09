#!/usr/bin/env python3
"""Expected-red: default-branch Xcode authority must also custody evidence-producer bytes.

The trusted workflow definition is only one authority layer. The Simulator evidence producer it
executes can alter Xcode invocation, retained build bytes, the external build record, screenshots,
and the visual-evidence manifest. Final-GO acceptance must therefore bind that producer to
independently trusted Git bytes rather than trusting a candidate checkout by path/step name alone.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

TEST_DIR = Path(__file__).resolve().parent
BASE_TEST_PATH = TEST_DIR / "test_es80_today_trusted_capture_xcode_subject.py"

spec = importlib.util.spec_from_file_location("trusted_xcode_base_tests", BASE_TEST_PATH)
base_tests = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(base_tests)

trusted_xcode = base_tests.trusted_xcode
PRODUCER_PATH = "scripts/ci/xcode27_simulator_capture.sh"


class TrustedXcodeEvidenceProducerCustodyExpectedRedTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = base_tests.TrustedCaptureXcodeSubjectTests(
            methodName="test_accepts_owner_issued_default_branch_subject_and_binds_candidate_separately"
        )

    def verify_with_producer_blob(self, archive: Path, records: dict[str, dict], producer_blob: str):
        calls: list[tuple[str, str]] = []

        def get(path: str):
            value = records[path]
            return json.dumps(value, sort_keys=True).encode(), value

        def blob_at(commit: str, path: str) -> str:
            calls.append((commit, path))
            if path == trusted_xcode.TRUSTED_WORKFLOW_PATH:
                return trusted_xcode.TRUSTED_WORKFLOW_BLOB_SHA
            if path == PRODUCER_PATH:
                return producer_blob
            raise AssertionError(f"unexpected Git-blob authority lookup: {commit}:{path}")

        subject = trusted_xcode.verify_trusted_capture_xcode_subject(
            source_commit_sha=self.fixture.SOURCE,
            expected_pr_number=self.fixture.PR,
            run_id=self.fixture.RUN,
            job_id=self.fixture.JOB,
            artifact_id=self.fixture.ARTIFACT,
            artifact_archive_path=archive,
            github_get_json=get,
            workflow_blob_sha_at_commit=blob_at,
        )
        return subject, calls

    def test_trusted_subject_binds_and_rejects_mutated_simulator_evidence_producer(self):
        approved_blob = getattr(
            trusted_xcode,
            "TRUSTED_SIMULATOR_EVIDENCE_PRODUCER_BLOB_SHA",
            "e" * 40,
        )
        self.assertRegex(approved_blob, r"^[0-9a-f]{40}$")
        mutated_blob = "f" * 40 if approved_blob != "f" * 40 else "d" * 40

        with tempfile.TemporaryDirectory() as temporary:
            archive, archive_sha, archive_size = self.fixture.make_archive(Path(temporary))
            records = self.fixture.trusted_records(archive_sha, archive_size)

            subject, calls = self.verify_with_producer_blob(archive, records, approved_blob)

            self.assertTrue(
                any(path == PRODUCER_PATH for _, path in calls),
                "trusted Xcode verifier never resolved the Simulator evidence-producer Git blob",
            )
            rendered_subject = json.dumps(subject, sort_keys=True)
            self.assertIn(
                PRODUCER_PATH,
                rendered_subject,
                "trusted Xcode subject does not preserve which evidence-producer path was accepted",
            )
            self.assertIn(
                approved_blob,
                rendered_subject,
                "trusted Xcode subject does not preserve the accepted evidence-producer Git blob",
            )

            with self.assertRaisesRegex(
                trusted_xcode.TrustedCaptureXcodeError,
                "producer|harness|custody|Git blob",
            ):
                self.verify_with_producer_blob(archive, records, mutated_blob)


if __name__ == "__main__":
    unittest.main()

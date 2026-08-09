#!/usr/bin/env python3
"""Adversarial composition tests for fresh signed-candidate reinspection in Final GO."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_hardened.py"
spec = importlib.util.spec_from_file_location("hardened_signed_candidate_composition", MODULE_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError("could not load hardened Final GO entrypoint")
hardened = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hardened)


class SignedCandidateCompositionTests(unittest.TestCase):
    SOURCE = "a" * 40
    WORKFLOW_SOURCE = "b" * 40
    RECEIPT_SHA = "c" * 64
    IPA_SHA = "d" * 64
    EXTERNAL_SHA = "e" * 64
    FIELD_SHA = "f" * 64
    INSPECTION_SHA = "1" * 64
    RUNNER_BLOB = "2" * 40
    INSPECTOR_BLOB = "3" * 40

    def kwargs(self, root: Path):
        return {
            "candidate_root": root / "candidate",
            "expected_source_sha": self.SOURCE,
            "expected_pr_number": 833,
            "trusted_xcode_run_id": 1001,
            "trusted_xcode_job_id": 2002,
            "trusted_xcode_artifact_id": 3003,
            "trusted_xcode_artifact_archive": root / "artifact.zip",
            "independent_crosscheck_receipt": root / "crosscheck.json",
            "frozen_source_repo": root / "source",
            "tooling_repo": root / "tooling",
            "operator_attestation": root / "attestation.json",
            "github_get_json": lambda path: (b"{}", {}),
            "intended_device_udid_file": root / "private-device-id",
        }

    def crosscheck_subject(self):
        return {
            "receiptSHA256": self.RECEIPT_SHA,
            "toolCommit": hardened.foundation.PINNED_CROSSCHECK_COMMIT,
            "toolGitBlob": hardened.foundation.PINNED_CROSSCHECK_BLOB,
            "executionCustody": "fresh-pinned-tool-exact-stdout-v1",
        }

    def reinspection_subject(self):
        return {
            "executionCustody": hardened.signed_candidate_reinspection.REINSPECTION_CUSTODY,
            "inspectorSourceCommitSHA": self.SOURCE,
            "privateRunnerGitBlob": self.RUNNER_BLOB,
            "canonicalInspectorGitBlob": self.INSPECTOR_BLOB,
            "retainedIPASHA256": self.IPA_SHA,
            "retainedIPAByteCount": 12345,
            "externalBuildRecordSHA256": self.EXTERNAL_SHA,
            "fieldBuildEvidenceRecordSHA256": self.FIELD_SHA,
            "signedArtifactInspectionSHA256": self.INSPECTION_SHA,
        }

    def trusted_xcode_subject(self):
        return {
            "authority": "default-branch-owner-command-v1",
            "candidateSourceCommitSHA": self.SOURCE,
            "workflowSourceCommitSHA": self.WORKFLOW_SOURCE,
        }

    def foundation_record(self, **kwargs):
        xcode = hardened.foundation._trusted_xcode_subject(
            source=kwargs["expected_source_sha"],
            expected_pr_number=kwargs["expected_pr_number"],
            run_id=kwargs["trusted_xcode_run_id"],
            job_id=kwargs["trusted_xcode_job_id"],
            artifact_id=kwargs["trusted_xcode_artifact_id"],
            artifact_archive_path=kwargs["trusted_xcode_artifact_archive"],
            github_get_json=kwargs["github_get_json"],
        )
        crosscheck = self.crosscheck_subject()
        return {
            "acceptedSourceCommitSHA": kwargs["expected_source_sha"],
            "trustedXcodeAcceptance": xcode,
            "independentRetainedCandidateCrosscheck": {
                "receiptSHA256": crosscheck["receiptSHA256"],
                "toolCommit": crosscheck["toolCommit"],
                "toolGitBlob": crosscheck["toolGitBlob"],
            },
            "acceptedSignedFieldCandidate": {
                "retainedIPASHA256": self.IPA_SHA,
                "retainedIPAByteCount": 12345,
                "externalBuildRecordSHA256": self.EXTERNAL_SHA,
                "fieldBuildEvidenceRecordSHA256": self.FIELD_SHA,
                "signedArtifactInspectionSHA256": self.INSPECTION_SHA,
            },
        }

    def patches(self, events: list[str]):
        def crosscheck(**kwargs):
            events.append("crosscheck")
            return self.crosscheck_subject()

        def reinspection(**kwargs):
            events.append("reinspection")
            return self.reinspection_subject()

        def foundation(**kwargs):
            events.append("foundation")
            return self.foundation_record(**kwargs)

        return (
            mock.patch.object(hardened.crosscheck_custody, "verify_crosscheck_receipt_custody", side_effect=crosscheck),
            mock.patch.object(hardened.signed_candidate_reinspection, "verify_signed_candidate_reinspection", side_effect=reinspection),
            mock.patch.object(hardened.foundation, "build_final_go_record", side_effect=foundation),
            mock.patch.object(hardened.trusted_xcode, "verify_trusted_capture_xcode_subject", return_value=self.trusted_xcode_subject()),
        )

    def test_fresh_signed_reinspection_precedes_foundation_and_is_cross_bound(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            events: list[str] = []
            p1, p2, p3, p4 = self.patches(events)
            with p1, p2 as reinspection, p3, p4:
                record = hardened.build_final_go_record(**self.kwargs(root))

        self.assertEqual(events, ["crosscheck", "reinspection", "foundation"])
        reinspection.assert_called_once()
        call = reinspection.call_args.kwargs
        self.assertEqual(call["candidate_root"], root / "candidate")
        self.assertEqual(call["frozen_source_repo"], root / "source")
        self.assertEqual(call["intended_device_udid_file"], root / "private-device-id")
        self.assertEqual(call["private_runner_path"], hardened.foundation.PRIVATE_RUNNER_PATH)
        self.assertEqual(call["inspector_path"], hardened.foundation.INSPECTOR_PATH)

        candidate = record["acceptedSignedFieldCandidate"]
        custody = candidate["freshSignedArtifactReinspection"]
        self.assertEqual(custody["executionCustody"], hardened.signed_candidate_reinspection.REINSPECTION_CUSTODY)
        self.assertEqual(custody["inspectorSourceCommitSHA"], self.SOURCE)
        self.assertEqual(custody["privateRunnerGitBlob"], self.RUNNER_BLOB)
        self.assertEqual(custody["canonicalInspectorGitBlob"], self.INSPECTOR_BLOB)
        self.assertNotIn("private-device-id", repr(record))

    def test_reinspection_failure_stops_before_foundation_authority(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with mock.patch.object(
                hardened.crosscheck_custody,
                "verify_crosscheck_receipt_custody",
                return_value=self.crosscheck_subject(),
            ), mock.patch.object(
                hardened.signed_candidate_reinspection,
                "verify_signed_candidate_reinspection",
                side_effect=hardened.signed_candidate_reinspection.SignedCandidateReinspectionError("invalid retained IPA"),
            ), mock.patch.object(hardened.foundation, "build_final_go_record") as foundation:
                with self.assertRaisesRegex(hardened.FinalGoError, "invalid retained IPA"):
                    hardened.build_final_go_record(**self.kwargs(root))
            foundation.assert_not_called()

    def test_foundation_candidate_must_match_fresh_reinspection_digest(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            changed = self.reinspection_subject()
            changed["signedArtifactInspectionSHA256"] = "9" * 64
            with mock.patch.object(
                hardened.crosscheck_custody,
                "verify_crosscheck_receipt_custody",
                return_value=self.crosscheck_subject(),
            ), mock.patch.object(
                hardened.signed_candidate_reinspection,
                "verify_signed_candidate_reinspection",
                return_value=changed,
            ), mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
                side_effect=self.foundation_record,
            ), mock.patch.object(
                hardened.trusted_xcode,
                "verify_trusted_capture_xcode_subject",
                return_value=self.trusted_xcode_subject(),
            ):
                with self.assertRaisesRegex(hardened.FinalGoError, "signedArtifactInspectionSHA256"):
                    hardened.build_final_go_record(**self.kwargs(root))


if __name__ == "__main__":
    unittest.main()

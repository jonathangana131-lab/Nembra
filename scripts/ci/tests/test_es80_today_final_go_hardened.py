#!/usr/bin/env python3
import importlib.util
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_hardened.py"
spec = importlib.util.spec_from_file_location("hardened", MODULE_PATH)
hardened = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(hardened)


class HardenedFinalGoCompositionTests(unittest.TestCase):
    SOURCE = "a" * 40
    WORKFLOW_SOURCE = "b" * 40
    IPA_SHA = "c" * 64
    EXTERNAL_SHA = "d" * 64
    FIELD_SHA = "e" * 64
    INSPECTION_SHA = "f" * 64
    RUNNER_BLOB = "1" * 40
    INSPECTOR_BLOB = "2" * 40

    def setUp(self):
        self.reinspection_patcher = mock.patch.object(
            hardened.signed_candidate_reinspection,
            "verify_signed_candidate_reinspection",
            return_value=self.reinspection_subject(),
        )
        self.reinspection_verify = self.reinspection_patcher.start()

    def tearDown(self):
        self.reinspection_patcher.stop()

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

    def candidate_subject(self):
        return {
            "retainedIPASHA256": self.IPA_SHA,
            "retainedIPAByteCount": 12345,
            "externalBuildRecordSHA256": self.EXTERNAL_SHA,
            "fieldBuildEvidenceRecordSHA256": self.FIELD_SHA,
            "signedArtifactInspectionSHA256": self.INSPECTION_SHA,
        }

    def fake_foundation(self, **kwargs):
        subject = hardened.foundation._trusted_xcode_subject(
            source=kwargs["expected_source_sha"],
            expected_pr_number=kwargs["expected_pr_number"],
            run_id=kwargs["trusted_xcode_run_id"],
            job_id=kwargs["trusted_xcode_job_id"],
            artifact_id=kwargs["trusted_xcode_artifact_id"],
            artifact_archive_path=kwargs["trusted_xcode_artifact_archive"],
            github_get_json=kwargs["github_get_json"],
        )
        return {
            "acceptedSourceCommitSHA": kwargs["expected_source_sha"],
            "trustedXcodeAcceptance": subject,
            "acceptedSignedFieldCandidate": self.candidate_subject(),
        }

    def trusted_subject(self):
        return {
            "authority": "default-branch-owner-command-v1",
            "candidateSourceCommitSHA": self.SOURCE,
            "workflowSourceCommitSHA": self.WORKFLOW_SOURCE,
        }

    def test_composition_requires_fresh_signed_reinspection_then_replaces_xcode_seam(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original = hardened.foundation._trusted_xcode_subject
            with mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
                side_effect=self.fake_foundation,
            ), mock.patch.object(
                hardened.trusted_xcode,
                "verify_trusted_capture_xcode_subject",
                return_value=self.trusted_subject(),
            ) as verify:
                record = hardened.build_final_go_record(**self.kwargs(root))

            self.assertIs(hardened.foundation._trusted_xcode_subject, original)
            self.assertEqual(record["trustedXcodeAcceptance"], self.trusted_subject())
            custody = record["acceptedSignedFieldCandidate"]["freshSignedArtifactReinspection"]
            self.assertEqual(custody["executionCustody"], hardened.signed_candidate_reinspection.REINSPECTION_CUSTODY)
            self.assertEqual(custody["privateRunnerGitBlob"], self.RUNNER_BLOB)
            self.reinspection_verify.assert_called_once()
            reinspection_call = self.reinspection_verify.call_args.kwargs
            self.assertEqual(reinspection_call["candidate_root"], root / "candidate")
            self.assertEqual(reinspection_call["frozen_source_repo"], root / "source")
            self.assertEqual(reinspection_call["intended_device_udid_file"], root / "private-device-id")
            self.assertEqual(reinspection_call["private_runner_path"], hardened.foundation.PRIVATE_RUNNER_PATH)
            self.assertEqual(reinspection_call["inspector_path"], hardened.foundation.INSPECTOR_PATH)
            verify.assert_called_once()

    def test_reinspection_failure_stops_before_foundation_builder(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with mock.patch.object(
                hardened.signed_candidate_reinspection,
                "verify_signed_candidate_reinspection",
                side_effect=hardened.signed_candidate_reinspection.SignedCandidateReinspectionError("fake signed IPA"),
            ), mock.patch.object(hardened.foundation, "build_final_go_record") as foundation_builder:
                with self.assertRaisesRegex(hardened.FinalGoError, "fake signed IPA"):
                    hardened.build_final_go_record(**self.kwargs(root))
            foundation_builder.assert_not_called()

    def test_reinspection_subject_must_cross_bind_foundation_candidate(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            changed = self.reinspection_subject()
            changed["signedArtifactInspectionSHA256"] = "0" * 64
            with mock.patch.object(
                hardened.signed_candidate_reinspection,
                "verify_signed_candidate_reinspection",
                return_value=changed,
            ), mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
                side_effect=self.fake_foundation,
            ), mock.patch.object(
                hardened.trusted_xcode,
                "verify_trusted_capture_xcode_subject",
                return_value=self.trusted_subject(),
            ):
                with self.assertRaisesRegex(hardened.FinalGoError, "signedArtifactInspectionSHA256"):
                    hardened.build_final_go_record(**self.kwargs(root))

    def test_missing_private_device_file_fails_before_reinspection(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            values = self.kwargs(root)
            values.pop("intended_device_udid_file")
            with mock.patch.dict(os.environ, {}, clear=True):
                with self.assertRaisesRegex(hardened.FinalGoError, hardened.PRIVATE_DEVICE_FILE_ENV):
                    hardened.build_final_go_record(**values)

    def test_private_device_file_can_come_from_existing_private_env_contract(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            values = self.kwargs(root)
            values.pop("intended_device_udid_file")
            private_file = root / "private-device-id"
            with mock.patch.dict(
                os.environ,
                {hardened.PRIVATE_DEVICE_FILE_ENV: str(private_file)},
                clear=False,
            ), mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
                side_effect=self.fake_foundation,
            ), mock.patch.object(
                hardened.trusted_xcode,
                "verify_trusted_capture_xcode_subject",
                return_value=self.trusted_subject(),
            ):
                hardened.build_final_go_record(**values)
            self.assertEqual(
                self.reinspection_verify.call_args.kwargs["intended_device_udid_file"],
                private_file,
            )

    def test_trusted_subject_failure_becomes_foundation_final_go_error_and_restores_seam(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original = hardened.foundation._trusted_xcode_subject
            with mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
                side_effect=self.fake_foundation,
            ), mock.patch.object(
                hardened.trusted_xcode,
                "verify_trusted_capture_xcode_subject",
                side_effect=hardened.trusted_xcode.TrustedCaptureXcodeError("untrusted workflow"),
            ):
                with self.assertRaisesRegex(hardened.FinalGoError, "untrusted workflow"):
                    hardened.build_final_go_record(**self.kwargs(root))
            self.assertIs(hardened.foundation._trusted_xcode_subject, original)

    def test_rejects_subject_that_aliases_workflow_source_to_candidate_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            aliased = self.trusted_subject()
            aliased["workflowSourceCommitSHA"] = self.SOURCE
            with mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
                side_effect=self.fake_foundation,
            ), mock.patch.object(
                hardened.trusted_xcode,
                "verify_trusted_capture_xcode_subject",
                return_value=aliased,
            ):
                with self.assertRaisesRegex(hardened.FinalGoError, "remain independent"):
                    hardened.build_final_go_record(**self.kwargs(root))

    def test_workflow_blob_lookup_reuses_foundation_closed_git_boundary(self):
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            with mock.patch.object(
                hardened.foundation,
                "_git",
                return_value="e" * 40,
            ) as git:
                value = hardened._workflow_blob_sha_at_commit(
                    repository,
                    "a" * 40,
                    hardened.trusted_xcode.TRUSTED_WORKFLOW_PATH,
                )

            self.assertEqual(value, "e" * 40)
            git.assert_called_once_with(
                repository,
                "rev-parse",
                f"{'a' * 40}:{hardened.trusted_xcode.TRUSTED_WORKFLOW_PATH}",
            )

    def test_workflow_blob_lookup_does_not_trust_caller_path_git(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            fake_git = fake_bin / "git"
            fake_git.write_text(
                "#!/bin/sh\n"
                f"printf '%s\\n' '{hardened.trusted_xcode.TRUSTED_WORKFLOW_BLOB_SHA}'\n",
                encoding="utf-8",
            )
            fake_git.chmod(fake_git.stat().st_mode | stat.S_IXUSR)
            tooling_repo = root / "tooling-repo"
            tooling_repo.mkdir()

            with mock.patch.dict(os.environ, {"PATH": str(fake_bin)}, clear=False):
                with self.assertRaises(hardened.FinalGoError):
                    hardened._workflow_blob_sha_at_commit(
                        tooling_repo,
                        "c" * 40,
                        hardened.trusted_xcode.TRUSTED_WORKFLOW_PATH,
                    )

    def test_publication_delegates_only_to_failure_atomic_primitive(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "FinalGO.json"
            raw = b'{"decision":"GO"}\n'
            with mock.patch.object(
                hardened.publication,
                "publish_record_no_replace",
                return_value="c" * 64,
            ) as publish:
                self.assertEqual(hardened.publish_record_no_replace(output, raw), "c" * 64)
            publish.assert_called_once_with(output, raw)


if __name__ == "__main__":
    unittest.main()

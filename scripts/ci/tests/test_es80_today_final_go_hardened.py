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

    def candidate_subject(self):
        return {
            "buildIdentifier": f"Capture Build V14-{self.SOURCE[:12]}",
            "buildInstanceID": "12345678-1234-4abc-8def-1234567890ab",
            "sourceCommitSHA": self.SOURCE,
            "retainedIPASHA256": "1" * 64,
            "retainedIPAByteCount": 1234,
            "externalBuildRecordSHA256": "2" * 64,
            "fieldBuildEvidenceRecordSHA256": "3" * 64,
            "signedArtifactInspectionSHA256": "4" * 64,
            "executableSHA256": "5" * 64,
            "infoPlistSHA256": "6" * 64,
            "teamIdentifier": "ABCDE12345",
            "provisioningProfileSHA256": "7" * 64,
            "provisioningProfileUUID": "PROFILE-UUID",
            "provisioningProfileExpirationUTC": "2099-01-01T00:00:00Z",
            "codeDirectoryHash": "8" * 40,
        }

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
            "intended_device_udid_file": root / "private-device-id",
            "github_get_json": lambda path: (b"{}", {}),
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

    def test_composition_requires_fresh_signed_candidate_and_restores_xcode_seam(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original = hardened.foundation._trusted_xcode_subject
            with mock.patch.object(
                hardened,
                "_fresh_signed_candidate_subject",
                return_value=self.candidate_subject(),
            ) as reinspect, mock.patch.object(
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
            self.assertEqual(record["acceptedSignedFieldCandidate"], self.candidate_subject())
            reinspect.assert_called_once()
            self.assertEqual(
                reinspect.call_args.kwargs["intended_device_udid_file"],
                root / "private-device-id",
            )
            verify.assert_called_once()
            call = verify.call_args.kwargs
            self.assertEqual(call["source_commit_sha"], self.SOURCE)
            self.assertEqual(call["expected_pr_number"], 833)

    def test_rejects_foundation_candidate_that_diverges_from_fresh_apple_reinspection(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            forged = self.candidate_subject()
            forged["teamIdentifier"] = "ZZZZZ99999"

            def forged_foundation(**kwargs):
                record = self.fake_foundation(**kwargs)
                record["acceptedSignedFieldCandidate"] = forged
                return record

            with mock.patch.object(
                hardened,
                "_fresh_signed_candidate_subject",
                return_value=self.candidate_subject(),
            ), mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
                side_effect=forged_foundation,
            ), mock.patch.object(
                hardened.trusted_xcode,
                "verify_trusted_capture_xcode_subject",
                return_value=self.trusted_subject(),
            ):
                with self.assertRaisesRegex(
                    hardened.FinalGoError,
                    "diverged from fresh reviewed Apple reinspection",
                ):
                    hardened.build_final_go_record(**self.kwargs(root))

    def test_fresh_reinspection_failure_becomes_final_go_error_before_foundation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with mock.patch.object(
                hardened.trusted_signed_candidate,
                "trusted_reinspection_candidate_root",
                side_effect=hardened.trusted_signed_candidate.TrustedSignedCandidateReinspectionError(
                    "Apple inspection rejected retained IPA"
                ),
            ), mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
            ) as foundation_builder:
                with self.assertRaisesRegex(
                    hardened.FinalGoError,
                    "Apple inspection rejected retained IPA",
                ):
                    hardened.build_final_go_record(**self.kwargs(root))
            foundation_builder.assert_not_called()

    def test_trusted_subject_failure_becomes_foundation_final_go_error_and_restores_seam(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original = hardened.foundation._trusted_xcode_subject
            with mock.patch.object(
                hardened,
                "_fresh_signed_candidate_subject",
                return_value=self.candidate_subject(),
            ), mock.patch.object(
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
                hardened,
                "_fresh_signed_candidate_subject",
                return_value=self.candidate_subject(),
            ), mock.patch.object(
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

    def test_hardened_cli_requires_private_intended_device_input(self):
        minimal = [
            "--candidate-root", "/tmp/candidate",
            "--expected-source-sha", self.SOURCE,
            "--expected-pr-number", "833",
            "--trusted-xcode-run-id", "1",
            "--trusted-xcode-job-id", "2",
            "--trusted-xcode-artifact-id", "3",
            "--trusted-xcode-artifact-archive", "/tmp/xcode.zip",
            "--independent-crosscheck-receipt", "/tmp/crosscheck.json",
            "--frozen-source-repo", "/tmp/source",
            "--tooling-repo", "/tmp/tooling",
            "--operator-attestation", "/tmp/attestation.json",
            "--output", "/tmp/FinalGO.json",
        ]
        with self.assertRaises(SystemExit):
            hardened._args(minimal)
        parsed = hardened._args(
            minimal + ["--intended-device-udid-file", "/private/device-id"]
        )
        self.assertEqual(parsed.intended_device_udid_file, Path("/private/device-id"))

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

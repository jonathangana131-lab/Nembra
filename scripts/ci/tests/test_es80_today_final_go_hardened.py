#!/usr/bin/env python3
from contextlib import contextmanager
from datetime import datetime, timezone
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
    CROSSCHECK_RECEIPT_SHA = "c" * 64

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

    def crosscheck_execution(self):
        return {
            "receiptSHA256": self.CROSSCHECK_RECEIPT_SHA,
            "toolCommit": hardened.foundation.PINNED_CROSSCHECK_COMMIT,
            "toolGitBlob": hardened.foundation.PINNED_CROSSCHECK_BLOB,
            "executionCustody": "pinned-git-object-stdout-v1",
        }

    def candidate_subject(self):
        return {
            "buildIdentifier": f"Capture Build V14-{self.SOURCE[:12]}",
            "buildInstanceID": "11111111-2222-3333-4444-555555555555",
            "sourceCommitSHA": self.SOURCE,
            "retainedIPASHA256": "1" * 64,
            "retainedIPAByteCount": 12345,
            "externalBuildRecordSHA256": "2" * 64,
            "fieldBuildEvidenceRecordSHA256": "3" * 64,
            "signedArtifactInspectionSHA256": "4" * 64,
            "executableSHA256": "5" * 64,
            "infoPlistSHA256": "6" * 64,
            "teamIdentifier": "ABCDE12345",
            "provisioningProfileSHA256": "7" * 64,
            "provisioningProfileUUID": "PROFILE-UUID",
            "provisioningProfileExpirationUTC": "2027-08-08T12:00:00Z",
            "codeDirectoryHash": "8" * 40,
        }

    def native_subject(self):
        candidate = self.candidate_subject()
        return {
            "authority": hardened.native_signed_candidate.REINSPECTION_AUTHORITY,
            "inspectionRecordSHA256": candidate["signedArtifactInspectionSHA256"],
            "signedInstallableSHA256": candidate["retainedIPASHA256"],
            "ipaByteCount": candidate["retainedIPAByteCount"],
            "bundleIdentifier": "com.jonathangana131.nembra",
            "platformName": "iphoneos",
            "supportedPlatforms": ["iPhoneOS"],
            "teamIdentifier": candidate["teamIdentifier"],
            "signingAuthorities": ["Apple Development: Test (ABCDE12345)"],
            "codeDirectoryHash": candidate["codeDirectoryHash"],
            "provisioningProfileSHA256": candidate["provisioningProfileSHA256"],
            "provisioningProfileUUID": candidate["provisioningProfileUUID"],
            "provisioningProfileExpirationUTC": candidate["provisioningProfileExpirationUTC"],
            "provisioningApplicationIdentifier": "ABCDE12345.com.jonathangana131.nembra",
            "executableSHA256": candidate["executableSHA256"],
            "infoPlistSHA256": candidate["infoPlistSHA256"],
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
        crosscheck = self.crosscheck_execution()
        crosscheck.pop("executionCustody")
        return {
            "acceptedSourceCommitSHA": kwargs["expected_source_sha"],
            "acceptedSignedFieldCandidate": self.candidate_subject(),
            "trustedXcodeAcceptance": subject,
            "independentRetainedCandidateCrosscheck": crosscheck,
        }

    def trusted_subject(self):
        return {
            "authority": "default-branch-owner-command-v1",
            "candidateSourceCommitSHA": self.SOURCE,
            "workflowSourceCommitSHA": self.WORKFLOW_SOURCE,
        }

    @contextmanager
    def fresh_candidate_root(self, root: Path):
        yield root / "fresh-candidate"

    def test_fresh_signed_candidate_cross_binds_native_and_intended_device_reinspection(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = self.candidate_subject()
            with mock.patch.object(
                hardened.native_signed_candidate,
                "verify_signed_candidate_reinspection",
                return_value=self.native_subject(),
            ) as native, mock.patch.object(
                hardened.trusted_signed_candidate,
                "trusted_reinspection_candidate_root",
                return_value=self.fresh_candidate_root(root),
            ) as trusted, mock.patch.object(
                hardened.foundation,
                "_candidate_subject",
                return_value=(candidate, {}),
            ):
                result = hardened._fresh_signed_candidate_subject(
                    candidate_root=root / "candidate",
                    expected_source_sha=self.SOURCE,
                    frozen_source_repo=root / "source",
                    intended_device_udid_file=root / "private-device-id",
                    now_utc=datetime(2026, 8, 9, tzinfo=timezone.utc),
                )
            self.assertEqual(result, candidate)
            native.assert_called_once_with(candidate_root=root / "candidate")
            trusted.assert_called_once_with(
                candidate_root=root / "candidate",
                expected_source_sha=self.SOURCE,
                frozen_source_repo=root / "source",
                intended_device_udid_file=root / "private-device-id",
            )

    def test_fresh_signed_candidate_rejects_native_divergence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            native = self.native_subject()
            native["codeDirectoryHash"] = "9" * 40
            with mock.patch.object(
                hardened.native_signed_candidate,
                "verify_signed_candidate_reinspection",
                return_value=native,
            ), mock.patch.object(
                hardened.trusted_signed_candidate,
                "trusted_reinspection_candidate_root",
                return_value=self.fresh_candidate_root(root),
            ), mock.patch.object(
                hardened.foundation,
                "_candidate_subject",
                return_value=(self.candidate_subject(), {}),
            ):
                with self.assertRaisesRegex(hardened.FinalGoError, "codeDirectoryHash"):
                    hardened._fresh_signed_candidate_subject(
                        candidate_root=root / "candidate",
                        expected_source_sha=self.SOURCE,
                        frozen_source_repo=root / "source",
                        intended_device_udid_file=root / "private-device-id",
                        now_utc=datetime(2026, 8, 9, tzinfo=timezone.utc),
                    )

    def test_composition_replaces_foundation_trust_seam_and_requires_fresh_candidate_equality(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original = hardened.foundation._trusted_xcode_subject
            crosscheck = self.crosscheck_execution()
            with mock.patch.object(
                hardened,
                "_fresh_signed_candidate_subject",
                return_value=self.candidate_subject(),
            ) as fresh, mock.patch.object(
                hardened.crosscheck_custody,
                "verify_crosscheck_receipt_custody",
                return_value=crosscheck,
            ) as verify_crosscheck, mock.patch.object(
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
            self.assertEqual(record["acceptedSignedFieldCandidate"], self.candidate_subject())
            self.assertEqual(record["trustedXcodeAcceptance"], self.trusted_subject())
            self.assertEqual(
                record["independentRetainedCandidateCrosscheck"]["executionCustody"],
                crosscheck["executionCustody"],
            )
            fresh.assert_called_once()
            verify_crosscheck.assert_called_once()
            verify.assert_called_once()

    def test_rejects_foundation_candidate_that_diverges_from_fresh_reinspection(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            divergent = self.candidate_subject()
            divergent["retainedIPASHA256"] = "f" * 64

            def divergent_foundation(**kwargs):
                record = self.fake_foundation(**kwargs)
                record["acceptedSignedFieldCandidate"] = divergent
                return record

            with mock.patch.object(
                hardened,
                "_fresh_signed_candidate_subject",
                return_value=self.candidate_subject(),
            ), mock.patch.object(
                hardened.crosscheck_custody,
                "verify_crosscheck_receipt_custody",
                return_value=self.crosscheck_execution(),
            ), mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
                side_effect=divergent_foundation,
            ), mock.patch.object(
                hardened.trusted_xcode,
                "verify_trusted_capture_xcode_subject",
                return_value=self.trusted_subject(),
            ):
                with self.assertRaisesRegex(hardened.FinalGoError, "fresh native \+ intended-device"):
                    hardened.build_final_go_record(**self.kwargs(root))

    def test_trusted_subject_failure_becomes_foundation_final_go_error_and_restores_seam(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original = hardened.foundation._trusted_xcode_subject
            with mock.patch.object(
                hardened,
                "_fresh_signed_candidate_subject",
                return_value=self.candidate_subject(),
            ), mock.patch.object(
                hardened.crosscheck_custody,
                "verify_crosscheck_receipt_custody",
                return_value=self.crosscheck_execution(),
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

    def test_rejects_crosscheck_execution_divergence_from_foundation_subject(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            diverged = self.crosscheck_execution()
            diverged["receiptSHA256"] = "d" * 64
            with mock.patch.object(
                hardened,
                "_fresh_signed_candidate_subject",
                return_value=self.candidate_subject(),
            ), mock.patch.object(
                hardened.crosscheck_custody,
                "verify_crosscheck_receipt_custody",
                return_value=diverged,
            ), mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
                side_effect=self.fake_foundation,
            ), mock.patch.object(
                hardened.trusted_xcode,
                "verify_trusted_capture_xcode_subject",
                return_value=self.trusted_subject(),
            ):
                with self.assertRaisesRegex(
                    hardened.FinalGoError,
                    "fresh pinned crosscheck execution diverged.*receiptSHA256",
                ):
                    hardened.build_final_go_record(**self.kwargs(root))

    def test_crosscheck_custody_failure_becomes_final_go_error_before_foundation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with mock.patch.object(
                hardened,
                "_fresh_signed_candidate_subject",
                return_value=self.candidate_subject(),
            ), mock.patch.object(
                hardened.crosscheck_custody,
                "verify_crosscheck_receipt_custody",
                side_effect=hardened.crosscheck_custody.CrosscheckReceiptCustodyError(
                    "unpinned crosscheck execution"
                ),
            ), mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
            ) as foundation_builder:
                with self.assertRaisesRegex(hardened.FinalGoError, "unpinned crosscheck execution"):
                    hardened.build_final_go_record(**self.kwargs(root))
            foundation_builder.assert_not_called()

    def test_workflow_blob_lookup_reuses_foundation_closed_git_boundary(self):
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            with mock.patch.object(hardened.foundation, "_git", return_value="e" * 40) as git:
                value = hardened._workflow_blob_sha_at_commit(
                    repository, "a" * 40, hardened.trusted_xcode.TRUSTED_WORKFLOW_PATH
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

    def test_cli_requires_private_intended_device_file_not_raw_udid(self):
        help_text = ""
        with self.assertRaises(SystemExit):
            hardened._args(["--help"])
        parser_source = MODULE_PATH.read_text(encoding="utf-8")
        self.assertIn('"--intended-device-udid-file"', parser_source)
        self.assertNotIn('"--intended-device-udid"', parser_source.replace('"--intended-device-udid-file"', ''))


if __name__ == "__main__":
    unittest.main()

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
    CROSSCHECK_RECEIPT_SHA = "c" * 64

    def setUp(self):
        self.fresh_signed_patcher = mock.patch.object(
            hardened,
            "_fresh_signed_candidate_subject",
            return_value=self.signed_candidate(),
        )
        self.fresh_signed = self.fresh_signed_patcher.start()

    def tearDown(self):
        self.fresh_signed_patcher.stop()

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
            "intended_device_udid_file": root / "device-id",
            "github_get_json": lambda path: (b"{}", {}),
        }

    def signed_candidate(self):
        return {
            "sourceCommitSHA": self.SOURCE,
            "retainedIPASHA256": "1" * 64,
            "retainedIPAByteCount": 123,
            "signedArtifactInspectionSHA256": "2" * 64,
        }

    def crosscheck_execution(self):
        return {
            "receiptSHA256": self.CROSSCHECK_RECEIPT_SHA,
            "toolCommit": hardened.foundation.PINNED_CROSSCHECK_COMMIT,
            "toolGitBlob": hardened.foundation.PINNED_CROSSCHECK_BLOB,
            "executionCustody": "pinned-git-object-stdout-v1",
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
            "acceptedSignedFieldCandidate": self.signed_candidate(),
            "trustedXcodeAcceptance": subject,
            "independentRetainedCandidateCrosscheck": crosscheck,
        }

    def trusted_subject(self):
        return {
            "authority": "default-branch-owner-command-v1",
            "candidateSourceCommitSHA": self.SOURCE,
            "workflowSourceCommitSHA": self.WORKFLOW_SOURCE,
        }

    def test_composition_replaces_foundation_trust_seam_and_restores_it(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original = hardened.foundation._trusted_xcode_subject
            crosscheck = self.crosscheck_execution()
            with mock.patch.object(
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
            self.assertEqual(record["trustedXcodeAcceptance"], self.trusted_subject())
            self.assertEqual(record["acceptedSignedFieldCandidate"], self.signed_candidate())
            self.assertEqual(
                record["independentRetainedCandidateCrosscheck"]["executionCustody"],
                crosscheck["executionCustody"],
            )
            verify_crosscheck.assert_called_once()
            custody_call = verify_crosscheck.call_args.kwargs
            self.assertEqual(custody_call["expected_source_sha"], self.SOURCE)
            self.assertEqual(
                custody_call["expected_tool_commit"],
                hardened.foundation.PINNED_CROSSCHECK_COMMIT,
            )
            self.assertEqual(
                custody_call["expected_tool_blob"],
                hardened.foundation.PINNED_CROSSCHECK_BLOB,
            )
            self.fresh_signed.assert_called_once()
            fresh_call = self.fresh_signed.call_args.kwargs
            self.assertEqual(fresh_call["candidate_root"], root / "candidate")
            self.assertEqual(fresh_call["expected_source_sha"], self.SOURCE)
            self.assertEqual(fresh_call["frozen_source_repo"], root / "source")
            self.assertEqual(fresh_call["intended_device_udid_file"], root / "device-id")
            self.assertIn("now_utc", fresh_call)
            verify.assert_called_once()
            call = verify.call_args.kwargs
            self.assertEqual(call["source_commit_sha"], self.SOURCE)
            self.assertEqual(call["expected_pr_number"], 833)

    def test_trusted_subject_failure_becomes_foundation_final_go_error_and_restores_seam(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original = hardened.foundation._trusted_xcode_subject
            with mock.patch.object(
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

    def test_rejects_subject_that_aliases_workflow_source_to_candidate_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            aliased = self.trusted_subject()
            aliased["workflowSourceCommitSHA"] = self.SOURCE
            with mock.patch.object(
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
                return_value=aliased,
            ):
                with self.assertRaisesRegex(hardened.FinalGoError, "remain independent"):
                    hardened.build_final_go_record(**self.kwargs(root))

    def test_rejects_crosscheck_execution_divergence_from_foundation_subject(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            diverged = self.crosscheck_execution()
            diverged["receiptSHA256"] = "d" * 64
            with mock.patch.object(
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
            self.fresh_signed.reset_mock()
            with mock.patch.object(
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
            self.fresh_signed.assert_not_called()

    def test_fresh_signed_candidate_failure_stops_before_foundation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fresh_signed.side_effect = hardened.FinalGoError("fresh signed reject")
            with mock.patch.object(
                hardened.crosscheck_custody,
                "verify_crosscheck_receipt_custody",
                return_value=self.crosscheck_execution(),
            ), mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
            ) as foundation_builder:
                with self.assertRaisesRegex(hardened.FinalGoError, "fresh signed reject"):
                    hardened.build_final_go_record(**self.kwargs(root))
            foundation_builder.assert_not_called()

    def test_rejects_foundation_candidate_divergent_from_fresh_reviewed_reinspection(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            divergent = self.signed_candidate()
            divergent["retainedIPASHA256"] = "9" * 64
            self.fresh_signed.return_value = divergent
            with mock.patch.object(
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
                return_value=self.trusted_subject(),
            ):
                with self.assertRaisesRegex(
                    hardened.FinalGoError,
                    "diverged from fresh reviewed Apple reinspection",
                ):
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

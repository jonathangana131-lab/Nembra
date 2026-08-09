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
    IPA = "c" * 64
    INSTANCE = "12345678-1234-1234-1234-123456789abc"

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
            "operator_attestation_comment_id": 4004,
            "github_get_json": lambda path: (b"{}", {}),
        }

    def candidate(self):
        return {
            "sourceCommitSHA": self.SOURCE,
            "retainedIPASHA256": self.IPA,
            "buildInstanceID": self.INSTANCE,
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
        candidate = self.candidate()
        operator = hardened.foundation._operator_attestation(
            kwargs["operator_attestation"], candidate, None
        )
        return {
            "acceptedSourceCommitSHA": kwargs["expected_source_sha"],
            "trustedXcodeAcceptance": subject,
            "acceptedSignedFieldCandidate": candidate,
            "exactRetainedIPAInstallAndRuntimeAttestation": operator,
        }

    def trusted_subject(self):
        return {
            "authority": "default-branch-owner-command-v1",
            "candidateSourceCommitSHA": self.SOURCE,
            "workflowSourceCommitSHA": self.WORKFLOW_SOURCE,
        }

    def trusted_operator_subject(self):
        return {
            "authority": hardened.trusted_operator.AUTHORITY,
            "classification": hardened.trusted_operator.CLASSIFICATION,
            "candidateBinding": {
                "sourceCommitSHA": self.SOURCE,
                "retainedIPASHA256": self.IPA,
                "buildInstanceID": self.INSTANCE,
                "recipe": hardened.trusted_operator.RECIPE,
                "procedure": hardened.trusted_operator.PROCEDURE,
            },
        }

    def patch_operator(self):
        return mock.patch.object(
            hardened.trusted_operator,
            "verify_trusted_operator_attestation_subject",
            return_value=self.trusted_operator_subject(),
        )

    def test_composition_replaces_both_authority_seams_and_restores_them(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original_xcode = hardened.foundation._trusted_xcode_subject
            original_operator = hardened.foundation._operator_attestation
            with mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
                side_effect=self.fake_foundation,
            ), mock.patch.object(
                hardened.foundation,
                "_operator_attestation",
                return_value={"recordSHA256": "d" * 64},
            ) as original_operator_parser, mock.patch.object(
                hardened.trusted_xcode,
                "verify_trusted_capture_xcode_subject",
                return_value=self.trusted_subject(),
            ) as verify_xcode, self.patch_operator() as verify_operator:
                # Capture the parser object after patching because the hardened function must restore
                # exactly the seam it received, not the module's import-time implementation.
                patched_operator = hardened.foundation._operator_attestation
                record = hardened.build_final_go_record(**self.kwargs(root))
                self.assertIs(hardened.foundation._operator_attestation, patched_operator)

            self.assertIs(hardened.foundation._trusted_xcode_subject, original_xcode)
            self.assertIs(hardened.foundation._operator_attestation, original_operator)
            self.assertEqual(record["trustedXcodeAcceptance"], self.trusted_subject())
            self.assertEqual(
                record["exactRetainedIPAInstallAndRuntimeAttestation"],
                self.trusted_operator_subject(),
            )
            verify_xcode.assert_called_once()
            xcode_call = verify_xcode.call_args.kwargs
            self.assertEqual(xcode_call["source_commit_sha"], self.SOURCE)
            self.assertEqual(xcode_call["expected_pr_number"], 833)
            original_operator_parser.assert_called_once()
            verify_operator.assert_called_once()
            operator_call = verify_operator.call_args.kwargs
            self.assertEqual(operator_call["expected_pr_number"], 833)
            self.assertEqual(operator_call["comment_id"], 4004)
            self.assertEqual(operator_call["candidate"], self.candidate())

    def test_plain_local_operator_record_without_trusted_owner_subject_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original_xcode = hardened.foundation._trusted_xcode_subject
            original_operator = hardened.foundation._operator_attestation
            with mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
                side_effect=self.fake_foundation,
            ), mock.patch.object(
                hardened.foundation,
                "_operator_attestation",
                return_value={"recordSHA256": "d" * 64},
            ) as patched_parser, mock.patch.object(
                hardened.trusted_xcode,
                "verify_trusted_capture_xcode_subject",
                return_value=self.trusted_subject(),
            ), mock.patch.object(
                hardened.trusted_operator,
                "verify_trusted_operator_attestation_subject",
                side_effect=hardened.trusted_operator.TrustedOperatorAttestationError(
                    "owner attestation unavailable"
                ),
            ):
                patched_operator = hardened.foundation._operator_attestation
                with self.assertRaisesRegex(hardened.FinalGoError, "owner attestation unavailable"):
                    hardened.build_final_go_record(**self.kwargs(root))
                self.assertIs(hardened.foundation._operator_attestation, patched_operator)
                patched_parser.assert_called_once()
            self.assertIs(hardened.foundation._trusted_xcode_subject, original_xcode)
            self.assertIs(hardened.foundation._operator_attestation, original_operator)

    def test_trusted_subject_failure_becomes_foundation_final_go_error_and_restores_seams(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original_xcode = hardened.foundation._trusted_xcode_subject
            original_operator = hardened.foundation._operator_attestation
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
            self.assertIs(hardened.foundation._trusted_xcode_subject, original_xcode)
            self.assertIs(hardened.foundation._operator_attestation, original_operator)

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
                hardened.foundation,
                "_operator_attestation",
                return_value={"recordSHA256": "d" * 64},
            ), mock.patch.object(
                hardened.trusted_xcode,
                "verify_trusted_capture_xcode_subject",
                return_value=aliased,
            ), self.patch_operator():
                with self.assertRaisesRegex(hardened.FinalGoError, "remain independent"):
                    hardened.build_final_go_record(**self.kwargs(root))

    def test_rejects_operator_subject_detached_from_candidate(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            detached = self.trusted_operator_subject()
            detached["candidateBinding"] = dict(detached["candidateBinding"])
            detached["candidateBinding"]["retainedIPASHA256"] = "e" * 64
            with mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
                side_effect=self.fake_foundation,
            ), mock.patch.object(
                hardened.foundation,
                "_operator_attestation",
                return_value={"recordSHA256": "d" * 64},
            ), mock.patch.object(
                hardened.trusted_xcode,
                "verify_trusted_capture_xcode_subject",
                return_value=self.trusted_subject(),
            ), mock.patch.object(
                hardened.trusted_operator,
                "verify_trusted_operator_attestation_subject",
                return_value=detached,
            ):
                with self.assertRaisesRegex(hardened.FinalGoError, "retained IPA diverged"):
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

    def test_operator_comment_id_environment_is_required_and_positive(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(hardened.FinalGoError, "is required"):
                hardened._operator_comment_id_from_environment()
        with mock.patch.dict(
            os.environ,
            {hardened.OPERATOR_COMMENT_ID_ENV: "0"},
            clear=True,
        ):
            with self.assertRaisesRegex(hardened.FinalGoError, "positive integer"):
                hardened._operator_comment_id_from_environment()
        with mock.patch.dict(
            os.environ,
            {hardened.OPERATOR_COMMENT_ID_ENV: "123"},
            clear=True,
        ):
            self.assertEqual(hardened._operator_comment_id_from_environment(), 123)

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

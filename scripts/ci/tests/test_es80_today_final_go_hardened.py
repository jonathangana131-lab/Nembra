#!/usr/bin/env python3
import hashlib
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
            "independentRetainedCandidateCrosscheck": {
                "toolCommit": hardened.foundation.PINNED_CROSSCHECK_COMMIT,
                "toolGitBlob": hardened.foundation.PINNED_CROSSCHECK_BLOB,
            },
        }

    def fake_foundation_with_crosscheck(self, **kwargs):
        subject = hardened.foundation._trusted_xcode_subject(
            source=kwargs["expected_source_sha"],
            expected_pr_number=kwargs["expected_pr_number"],
            run_id=kwargs["trusted_xcode_run_id"],
            job_id=kwargs["trusted_xcode_job_id"],
            artifact_id=kwargs["trusted_xcode_artifact_id"],
            artifact_archive_path=kwargs["trusted_xcode_artifact_archive"],
            github_get_json=kwargs["github_get_json"],
        )
        crosscheck = hardened.foundation._crosscheck_subject(
            kwargs["independent_crosscheck_receipt"],
            {"sourceCommitSHA": kwargs["expected_source_sha"]},
            kwargs["frozen_source_repo"],
            kwargs["tooling_repo"],
        )
        return {
            "acceptedSourceCommitSHA": kwargs["expected_source_sha"],
            "trustedXcodeAcceptance": subject,
            "independentRetainedCandidateCrosscheck": crosscheck,
        }

    def trusted_subject(self):
        return {
            "authority": "default-branch-owner-command-v1",
            "candidateSourceCommitSHA": self.SOURCE,
            "workflowSourceCommitSHA": self.WORKFLOW_SOURCE,
        }

    def trusted_crosscheck_subject(self, raw: bytes):
        return {
            "toolCommit": hardened.foundation.PINNED_CROSSCHECK_COMMIT,
            "toolGitBlob": hardened.foundation.PINNED_CROSSCHECK_BLOB,
            "receiptSHA256": hashlib.sha256(raw).hexdigest(),
        }

    def test_composition_replaces_foundation_trust_seam_and_restores_it(self):
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
            verify.assert_called_once()
            call = verify.call_args.kwargs
            self.assertEqual(call["source_commit_sha"], self.SOURCE)
            self.assertEqual(call["expected_pr_number"], 833)

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

    def test_pinned_crosscheck_executes_in_isolated_python_and_matches_exact_receipt(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tooling = root / "tooling"
            candidate = root / "candidate"
            tooling.mkdir()
            candidate.mkdir()
            receipt = root / "crosscheck.json"
            receipt.write_bytes(b"trusted\n")
            source = (
                "import os\n"
                "print('poisoned' if os.environ.get('PYTHONPATH') or os.environ.get('BASH_ENV') "
                "else 'trusted')\n"
            ).encode()

            with mock.patch.object(
                hardened.foundation,
                "_git",
                return_value=hardened.foundation.PINNED_CROSSCHECK_BLOB,
            ), mock.patch.object(
                hardened,
                "_closed_git_blob_bytes",
                return_value=source,
            ), mock.patch.dict(
                os.environ,
                {"PYTHONPATH": "/tmp/poison", "BASH_ENV": "/tmp/poison.sh"},
                clear=False,
            ):
                raw = hardened._verified_independent_crosscheck_receipt(
                    receipt_path=receipt,
                    candidate_root=candidate,
                    expected_source_sha=self.SOURCE,
                    tooling_repo=tooling,
                )

            self.assertEqual(raw, b"trusted\n")

    def test_pinned_crosscheck_rejects_caller_receipt_that_differs_from_producer_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tooling = root / "tooling"
            candidate = root / "candidate"
            tooling.mkdir()
            candidate.mkdir()
            receipt = root / "crosscheck.json"
            receipt.write_bytes(b"caller-forged\n")
            with mock.patch.object(
                hardened.foundation,
                "_git",
                return_value=hardened.foundation.PINNED_CROSSCHECK_BLOB,
            ), mock.patch.object(
                hardened,
                "_closed_git_blob_bytes",
                return_value=b"print('trusted')\n",
            ):
                with self.assertRaisesRegex(
                    hardened.FinalGoError,
                    "were not produced by the pinned producer",
                ):
                    hardened._verified_independent_crosscheck_receipt(
                        receipt_path=receipt,
                        candidate_root=candidate,
                        expected_source_sha=self.SOURCE,
                        tooling_repo=tooling,
                    )

    def test_composition_replaces_crosscheck_seam_with_pinned_execution_and_restores_it(self):
        raw = b'{"status":"PASS_NOT_FINAL_GO"}\n'
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original_crosscheck = hardened.foundation._crosscheck_subject
            with mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
                side_effect=self.fake_foundation_with_crosscheck,
            ), mock.patch.object(
                hardened.foundation,
                "_crosscheck_subject",
                return_value=self.trusted_crosscheck_subject(raw),
            ) as original_subject, mock.patch.object(
                hardened.trusted_xcode,
                "verify_trusted_capture_xcode_subject",
                return_value=self.trusted_subject(),
            ), mock.patch.object(
                hardened,
                "_verified_independent_crosscheck_receipt",
                return_value=raw,
            ) as verify_crosscheck:
                patched_original = hardened.foundation._crosscheck_subject
                record = hardened.build_final_go_record(**self.kwargs(root))
                self.assertIs(hardened.foundation._crosscheck_subject, patched_original)

            self.assertIs(hardened.foundation._crosscheck_subject, original_crosscheck)
            verify_crosscheck.assert_called_once()
            original_subject.assert_called_once()
            self.assertEqual(
                record["independentRetainedCandidateCrosscheck"]["receiptSHA256"],
                hashlib.sha256(raw).hexdigest(),
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

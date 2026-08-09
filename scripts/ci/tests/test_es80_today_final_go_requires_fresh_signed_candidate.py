#!/usr/bin/env python3
"""Validation-only contract for canonical Final-GO signed-candidate composition."""
from __future__ import annotations

import importlib.util
import inspect
from pathlib import Path
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_hardened.py"
spec = importlib.util.spec_from_file_location("hardened_signed_candidate_validation", MODULE_PATH)
hardened = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(hardened)


class FreshSignedCandidateCompositionTests(unittest.TestCase):
    SOURCE = "a" * 40
    WORKFLOW_SOURCE = "b" * 40
    RECEIPT_SHA = "c" * 64

    def test_malformed_retained_ipa_cannot_return_go_without_fresh_reinspection(self) -> None:
        """Caller-consistent foundation evidence must not become GO without fresh IPA truth."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate = root / "candidate"
            inspection = candidate / "inspection"
            build_evidence = inspection / "build-evidence"
            build_evidence.mkdir(parents=True)

            # Deliberately not an IPA. The mocked private foundation below represents a malicious
            # or bypassed caller-consistent candidate path. The hardened composer may authenticate
            # a candidate seam *inside* the foundation, but it must never return GO when that seam
            # is bypassed and these malformed bytes were not freshly reinspected.
            (build_evidence / "NembraField.ipa").write_bytes(b"caller-forged-not-an-ipa")
            (inspection / "NembraCaptureSignedFieldArtifactInspection.json").write_text(
                '{"signedInstallableKind":"ipa"}\n',
                encoding="utf-8",
            )

            kwargs = {
                "candidate_root": candidate,
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

            # A stronger successor may make intended-device membership an explicit private input.
            # Supply a mode-0600 placeholder only when that contract exists; malformed IPA bytes
            # must still be unable to produce GO regardless of the chosen composition architecture.
            parameters = inspect.signature(hardened.build_final_go_record).parameters
            if "intended_device_udid_file" in parameters:
                device_file = root / "intended-device.txt"
                device_file.write_text("0000000000000000000000000000000000000000\n", encoding="utf-8")
                device_file.chmod(0o600)
                kwargs["intended_device_udid_file"] = device_file

            trusted_subject = {
                "authority": "default-branch-owner-command-v1",
                "candidateSourceCommitSHA": self.SOURCE,
                "workflowSourceCommitSHA": self.WORKFLOW_SOURCE,
            }
            crosscheck_execution = {
                "receiptSHA256": self.RECEIPT_SHA,
                "toolCommit": hardened.foundation.PINNED_CROSSCHECK_COMMIT,
                "toolGitBlob": hardened.foundation.PINNED_CROSSCHECK_BLOB,
                "executionCustody": "pinned-git-object-stdout-v1",
            }
            foundation_record = {
                "decision": "GO",
                "acceptedSourceCommitSHA": self.SOURCE,
                "trustedXcodeAcceptance": trusted_subject,
                "independentRetainedCandidateCrosscheck": {
                    key: value
                    for key, value in crosscheck_execution.items()
                    if key != "executionCustody"
                },
                # Deliberately caller-constructible placeholder. A hardened composer may enter the
                # foundation, but it must detect that authenticated native reinspection was bypassed
                # before allowing this GO-shaped record to escape.
                "acceptedSignedFieldCandidate": {"authority": "caller-consistent-placeholder"},
            }

            with mock.patch.object(
                hardened.crosscheck_custody,
                "verify_crosscheck_receipt_custody",
                return_value=crosscheck_execution,
            ), mock.patch.object(
                hardened.trusted_xcode,
                "verify_trusted_capture_xcode_subject",
                return_value=trusted_subject,
            ), mock.patch.object(
                hardened.foundation,
                "build_final_go_record",
                return_value=foundation_record,
            ) as foundation_builder:
                with self.assertRaises(hardened.FinalGoError):
                    hardened.build_final_go_record(**kwargs)

            foundation_builder.assert_called_once()


if __name__ == "__main__":
    unittest.main()

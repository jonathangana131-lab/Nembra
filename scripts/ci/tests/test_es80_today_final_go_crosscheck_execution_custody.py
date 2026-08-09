#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

CI_DIR = Path(__file__).resolve().parents[1]
FOUNDATION_PATH = CI_DIR / "es80_today_final_go_foundation.py"
spec = importlib.util.spec_from_file_location("final_go_crosscheck_custody", FOUNDATION_PATH)
final_go = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(final_go)


class FinalGoCrosscheckExecutionCustodyTests(unittest.TestCase):
    SOURCE = "a" * 40
    BUILD = f"Capture Build V14-{SOURCE[:12]}"
    INSTANCE = "11111111-2222-3333-4444-555555555555"

    def candidate(self) -> dict:
        return {
            "sourceCommitSHA": self.SOURCE,
            "buildIdentifier": self.BUILD,
            "buildInstanceID": self.INSTANCE,
            "retainedIPASHA256": "3" * 64,
            "retainedIPAByteCount": 12345,
            "externalBuildRecordSHA256": "4" * 64,
            "fieldBuildEvidenceRecordSHA256": "5" * 64,
            "signedArtifactInspectionSHA256": "6" * 64,
            "executableSHA256": "7" * 64,
            "infoPlistSHA256": "8" * 64,
            "teamIdentifier": "ABCDE12345",
            "provisioningProfileSHA256": "9" * 64,
            "provisioningProfileUUID": "PROFILE-UUID",
            "provisioningProfileExpirationUTC": "2030-08-09T00:00:00Z",
        }

    def receipt(self) -> dict:
        candidate = self.candidate()
        return {
            "schemaVersion": 1,
            "authority": final_go.CROSSCHECK_AUTHORITY,
            "status": "PASS_NOT_FINAL_GO",
            "sourceCommitSHA": self.SOURCE,
            "buildIdentifier": self.BUILD,
            "buildInstanceID": self.INSTANCE,
            "experimentRecipeID": final_go.RECIPE,
            "procedureVersion": final_go.PROCEDURE,
            "researchCompileMode": final_go.RESEARCH_COMPILE_MODE,
            "researchCompileAuthority": final_go.RESEARCH_COMPILE_AUTHORITY,
            "researchCompileCondition": final_go.RESEARCH_COMPILE_CONDITION,
            "signedInstallableSHA256": candidate["retainedIPASHA256"],
            "signedInstallableByteCount": candidate["retainedIPAByteCount"],
            "externalBuildRecordSHA256": candidate["externalBuildRecordSHA256"],
            "fieldBuildEvidenceRecordSHA256": candidate["fieldBuildEvidenceRecordSHA256"],
            "signedFieldArtifactInspectionSHA256": candidate["signedArtifactInspectionSHA256"],
            "executableSHA256": candidate["executableSHA256"],
            "infoPlistSHA256": candidate["infoPlistSHA256"],
            "exportOptionsSHA256": "f" * 64,
            "teamIdentifier": candidate["teamIdentifier"],
            "allowProvisioningUpdates": "0",
            "privateRunnerSourceGitBlobClaim": "1" * 40,
            "canonicalInspectorSourceGitBlobClaim": "2" * 40,
            "xcodeVersion": "Xcode 27.0",
            "xcodeBuildVersion": "Build version 18A123",
            "provisioningProfileSHA256": candidate["provisioningProfileSHA256"],
            "provisioningProfileUUID": candidate["provisioningProfileUUID"],
            "provisioningProfileExpirationUTC": candidate["provisioningProfileExpirationUTC"],
            "singleRetainedIPA": True,
            "crossRecordDigestLinksVerified": True,
            "researchCompileTupleVerified": True,
            "producerPhysicalAuthorizationRemainsNotGranted": True,
            "appleSigningInspectionRequired": True,
            "toolBlobClaimsRequireRepositoryCrossCheck": True,
            "exactRetainedIPAInstallHandoffRequired": True,
            "physicalExperimentAuthorization": "not-granted",
        }

    @staticmethod
    def canonical(value: dict) -> bytes:
        return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()

    def write_receipt(self, root: Path, value: dict | None = None) -> Path:
        path = root / "crosscheck.json"
        path.write_bytes(self.canonical(value or self.receipt()))
        return path

    def test_internal_crosscheck_without_exact_candidate_root_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            receipt = self.write_receipt(root)
            source_repo = root / "source"
            tooling_repo = root / "tooling"
            source_repo.mkdir()
            tooling_repo.mkdir()
            with self.assertRaisesRegex(final_go.FinalGoError, "exact retained candidate root"):
                final_go._crosscheck_subject(
                    receipt,
                    self.candidate(),
                    source_repo,
                    tooling_repo,
                )

    def test_pinned_executor_loads_git_blob_bytes_and_executes_exact_crosscheck_entrypoint(self):
        synthetic_source = b'''\nclass CrosscheckError(RuntimeError):\n    pass\n\ndef crosscheck(candidate_dir, *, expected_source_sha, now=None):\n    return {"candidate": str(candidate_dir), "source": expected_source_sha, "now": str(now)}\n'''
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            tooling = root / "tooling"
            candidate = root / "candidate"
            tooling.mkdir()
            candidate.mkdir()

            def git_result(repository: Path, *arguments: str) -> str:
                subject = arguments[-1]
                if subject == f"{final_go.PINNED_CROSSCHECK_COMMIT}^{{commit}}":
                    return final_go.PINNED_CROSSCHECK_COMMIT
                if subject == f"{final_go.PINNED_CROSSCHECK_COMMIT}:{final_go.CROSSCHECK_PATH}":
                    return final_go.PINNED_CROSSCHECK_BLOB
                raise AssertionError((repository, arguments))

            with mock.patch.object(final_go, "_git", side_effect=git_result), mock.patch.object(
                final_go,
                "_closed_git_blob_bytes",
                return_value=synthetic_source,
            ) as read_blob:
                derived, raw, blob = final_go._trusted_crosscheck_execution(
                    receipt_path=root / "unused.json",
                    candidate_root=candidate,
                    expected_source_sha=self.SOURCE,
                    tooling_repo=tooling,
                    now_utc="NOW",
                )

            self.assertEqual(blob, final_go.PINNED_CROSSCHECK_BLOB)
            self.assertEqual(derived["source"], self.SOURCE)
            self.assertEqual(derived["candidate"], str(candidate.absolute()))
            self.assertEqual(raw, self.canonical(derived))
            read_blob.assert_called_once_with(tooling, final_go.PINNED_CROSSCHECK_BLOB)

    def test_caller_receipt_must_match_reexecuted_pinned_tool_semantics_and_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            receipt_path = self.write_receipt(root)
            source_repo = root / "source"
            tooling_repo = root / "tooling"
            candidate_root = root / "candidate"
            source_repo.mkdir()
            tooling_repo.mkdir()
            candidate_root.mkdir()
            supplied = self.receipt()
            supplied_raw = self.canonical(supplied)
            legacy = {"receiptSHA256": hashlib.sha256(supplied_raw).hexdigest(), "status": "PASS_NOT_FINAL_GO"}
            forged_derived = dict(supplied)
            forged_derived["xcodeVersion"] = "Xcode 27.1"

            with mock.patch.object(final_go, "_ORIGINAL_CROSSCHECK_SUBJECT", return_value=legacy), mock.patch.object(
                final_go,
                "_trusted_crosscheck_execution",
                return_value=(forged_derived, self.canonical(forged_derived), final_go.PINNED_CROSSCHECK_BLOB),
            ):
                with self.assertRaisesRegex(final_go.FinalGoError, "not reproduced"):
                    final_go._crosscheck_subject(
                        receipt_path,
                        self.candidate(),
                        source_repo,
                        tooling_repo,
                        candidate_root=candidate_root,
                    )

            noncanonical_path = root / "noncanonical.json"
            noncanonical_path.write_text(json.dumps(supplied, sort_keys=True), encoding="utf-8")
            noncanonical_raw = noncanonical_path.read_bytes()
            noncanonical_legacy = {
                "receiptSHA256": hashlib.sha256(noncanonical_raw).hexdigest(),
                "status": "PASS_NOT_FINAL_GO",
            }
            with mock.patch.object(final_go, "_ORIGINAL_CROSSCHECK_SUBJECT", return_value=noncanonical_legacy), mock.patch.object(
                final_go,
                "_trusted_crosscheck_execution",
                return_value=(supplied, supplied_raw, final_go.PINNED_CROSSCHECK_BLOB),
            ):
                with self.assertRaisesRegex(final_go.FinalGoError, "exact canonical"):
                    final_go._crosscheck_subject(
                        noncanonical_path,
                        self.candidate(),
                        source_repo,
                        tooling_repo,
                        candidate_root=candidate_root,
                    )

    def test_canonical_reproduced_receipt_gains_execution_custody_subject(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            receipt_path = self.write_receipt(root)
            source_repo = root / "source"
            tooling_repo = root / "tooling"
            candidate_root = root / "candidate"
            source_repo.mkdir()
            tooling_repo.mkdir()
            candidate_root.mkdir()
            supplied = self.receipt()
            supplied_raw = self.canonical(supplied)
            digest = hashlib.sha256(supplied_raw).hexdigest()
            legacy = {"receiptSHA256": digest, "status": "PASS_NOT_FINAL_GO"}

            with mock.patch.object(final_go, "_ORIGINAL_CROSSCHECK_SUBJECT", return_value=legacy), mock.patch.object(
                final_go,
                "_trusted_crosscheck_execution",
                return_value=(supplied, supplied_raw, final_go.PINNED_CROSSCHECK_BLOB),
            ):
                subject = final_go._crosscheck_subject(
                    receipt_path,
                    self.candidate(),
                    source_repo,
                    tooling_repo,
                    candidate_root=candidate_root,
                )

            self.assertEqual(subject["producerExecutionAuthority"], "pinned-crosscheck-git-blob-execution-v1")
            self.assertEqual(subject["executedToolCommit"], final_go.PINNED_CROSSCHECK_COMMIT)
            self.assertEqual(subject["executedToolGitBlob"], final_go.PINNED_CROSSCHECK_BLOB)
            self.assertEqual(subject["executedReceiptSHA256"], digest)

    def test_builder_installs_crosscheck_seam_and_restores_implementation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            receipt_path = self.write_receipt(root)
            source_repo = root / "source"
            tooling_repo = root / "tooling"
            candidate_root = root / "candidate"
            source_repo.mkdir()
            tooling_repo.mkdir()
            candidate_root.mkdir()
            supplied = self.receipt()
            supplied_raw = self.canonical(supplied)
            legacy = {"receiptSHA256": hashlib.sha256(supplied_raw).hexdigest(), "status": "PASS_NOT_FINAL_GO"}
            original_impl_crosscheck = final_go._impl._crosscheck_subject

            def fake_impl_builder(**kwargs):
                return final_go._impl._crosscheck_subject(
                    kwargs["independent_crosscheck_receipt"],
                    self.candidate(),
                    kwargs["frozen_source_repo"],
                    kwargs["tooling_repo"],
                )

            kwargs = {
                "candidate_root": candidate_root,
                "expected_source_sha": self.SOURCE,
                "expected_pr_number": 833,
                "trusted_xcode_run_id": 1,
                "trusted_xcode_job_id": 2,
                "trusted_xcode_artifact_id": 3,
                "trusted_xcode_artifact_archive": root / "artifact.zip",
                "independent_crosscheck_receipt": receipt_path,
                "frozen_source_repo": source_repo,
                "tooling_repo": tooling_repo,
                "operator_attestation": root / "operator.json",
                "now_utc": None,
            }

            with mock.patch.object(final_go._impl, "build_final_go_record", side_effect=fake_impl_builder), mock.patch.object(
                final_go,
                "_ORIGINAL_CROSSCHECK_SUBJECT",
                return_value=legacy,
            ), mock.patch.object(
                final_go,
                "_trusted_crosscheck_execution",
                return_value=(supplied, supplied_raw, final_go.PINNED_CROSSCHECK_BLOB),
            ):
                subject = final_go.build_final_go_record(**kwargs)

            self.assertIs(final_go._impl._crosscheck_subject, original_impl_crosscheck)
            self.assertEqual(subject["producerExecutionAuthority"], "pinned-crosscheck-git-blob-execution-v1")


if __name__ == "__main__":
    unittest.main()

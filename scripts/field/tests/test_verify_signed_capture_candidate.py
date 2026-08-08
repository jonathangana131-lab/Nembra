#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MODULE_PATH = ROOT / "scripts" / "field" / "verify_signed_capture_candidate.py"
SPEC = importlib.util.spec_from_file_location("verify_signed_capture_candidate", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
VERIFIER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFIER)


class SignedCaptureCandidateVerifierTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.artifact_dir = Path(self.temp.name) / "Artifacts" / "Xcode27FieldCandidate"
        self.evidence_dir = self.artifact_dir / "build-evidence"
        self.evidence_dir.mkdir(parents=True)

        self.build_identifier = "Capture Build V14-0123456789ab"
        self.build_instance = "01234567-89ab-cdef-0123-456789abcdef"
        self.source_sha = "0123456789abcdef0123456789abcdef01234567"
        self.team_id = "ABCDE12345"
        self.executable_bytes = b"signed-mach-o-placeholder-v14"
        self.plist_bytes = plistlib.dumps(
            {
                "CFBundleExecutable": "Nembra",
                "CFBundleIdentifier": VERIFIER.EXPECTED_BUNDLE_ID,
                "NembraCaptureBuildIdentifier": self.build_identifier,
                "NembraCaptureBuildInstanceID": self.build_instance,
                "NembraCaptureBuildCommitSHA": self.source_sha,
            },
            fmt=plistlib.FMT_BINARY,
            sort_keys=True,
        )

        (self.evidence_dir / "Nembra").write_bytes(self.executable_bytes)
        (self.evidence_dir / "Info.plist").write_bytes(self.plist_bytes)
        self._write_app_archive(self.executable_bytes, self.plist_bytes)
        self._write_records()

    def tearDown(self) -> None:
        self.temp.cleanup()

    @staticmethod
    def _sha(data: bytes) -> str:
        return hashlib.sha256(data).hexdigest()

    @property
    def app_archive_path(self) -> Path:
        return self.evidence_dir / "Nembra.signed-app.zip"

    @property
    def external_path(self) -> Path:
        return self.artifact_dir / "NembraCaptureExternalBuildRecord.json"

    @property
    def field_path(self) -> Path:
        return self.artifact_dir / "NembraCaptureSignedFieldCandidateEvidence.json"

    def _write_app_archive(self, executable: bytes, plist: bytes, extra_name: str | None = None) -> None:
        with zipfile.ZipFile(self.app_archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("Nembra.app/Nembra", executable)
            archive.writestr("Nembra.app/Info.plist", plist)
            if extra_name is not None:
                archive.writestr(extra_name, b"extra")

    def _records(self) -> tuple[dict[str, object], dict[str, object]]:
        executable_sha = self._sha((self.evidence_dir / "Nembra").read_bytes())
        plist_sha = self._sha((self.evidence_dir / "Info.plist").read_bytes())
        archive_sha = self._sha(self.app_archive_path.read_bytes())
        external: dict[str, object] = {
            "schemaVersion": 3,
            "buildIdentifier": self.build_identifier,
            "buildInstanceID": self.build_instance,
            "sourceCommitSHA": self.source_sha,
            "executableSHA256": executable_sha,
            "infoPlistSHA256": plist_sha,
            "experimentRecipeID": VERIFIER.EXPECTED_RECIPE_ID,
            "procedureVersion": VERIFIER.EXPECTED_PROCEDURE_VERSION,
        }
        field: dict[str, object] = {
            "schemaVersion": 1,
            "evidenceClass": VERIFIER.EXPECTED_EVIDENCE_CLASS,
            "buildIdentifier": self.build_identifier,
            "buildInstanceID": self.build_instance,
            "sourceCommitSHA": self.source_sha,
            "executableSHA256": executable_sha,
            "infoPlistSHA256": plist_sha,
            "signedAppArchiveSHA256": archive_sha,
            "bundleIdentifier": VERIFIER.EXPECTED_BUNDLE_ID,
            "developmentTeam": self.team_id,
            "experimentRecipeID": VERIFIER.EXPECTED_RECIPE_ID,
            "procedureVersion": VERIFIER.EXPECTED_PROCEDURE_VERSION,
        }
        return external, field

    def _write_records(self, external_mutation=None, field_mutation=None) -> None:
        external, field = self._records()
        if external_mutation is not None:
            external_mutation(external)
        if field_mutation is not None:
            field_mutation(field)
        self.external_path.write_text(json.dumps(external, indent=2, sort_keys=True) + "\n")
        self.field_path.write_text(json.dumps(field, indent=2, sort_keys=True) + "\n")

    def assert_verification_fails(self, expected_fragment: str) -> None:
        with self.assertRaises(VERIFIER.VerificationError) as context:
            VERIFIER.verify_candidate(self.artifact_dir)
        self.assertIn(expected_fragment, str(context.exception))

    def test_valid_candidate_proves_self_consistency_but_not_authenticity(self) -> None:
        result = VERIFIER.verify_candidate(self.artifact_dir)
        self.assertEqual(result["verification"], "self-consistent-byte-provenance")
        self.assertEqual(result["authenticity"], "not-established-by-portable-verifier")
        self.assertEqual(result["fieldAuthorization"], "NO-GO")
        self.assertEqual(result["codeSignatureVerification"], "not-reperformed-by-portable-verifier")
        self.assertEqual(result["buildInstanceID"], self.build_instance)

    def test_retained_executable_tamper_is_rejected(self) -> None:
        (self.evidence_dir / "Nembra").write_bytes(self.executable_bytes + b"-tampered")
        self.assert_verification_fails("Retained signed executable bytes")

    def test_archive_tamper_is_rejected_even_if_retained_files_are_unchanged(self) -> None:
        self._write_app_archive(self.executable_bytes + b"-archive-tamper", self.plist_bytes)
        _, field = self._records()
        self.field_path.write_text(json.dumps(field, indent=2, sort_keys=True) + "\n")
        self.assert_verification_fails("archive executable differs")

    def test_external_unknown_authority_field_is_rejected(self) -> None:
        self._write_records(external_mutation=lambda value: value.__setitem__("physicalGO", True))
        self.assert_verification_fails("external build record key set mismatch")

    def test_field_unknown_authority_field_is_rejected(self) -> None:
        self._write_records(field_mutation=lambda value: value.__setitem__("fieldAuthorized", True))
        self.assert_verification_fails("signed field candidate evidence key set mismatch")

    def test_build_instance_mismatch_between_records_is_rejected(self) -> None:
        self._write_records(
            field_mutation=lambda value: value.__setitem__(
                "buildInstanceID", "fedcba98-7654-3210-fedc-ba9876543210"
            )
        )
        self.assert_verification_fails("disagree on buildInstanceID")

    def test_padded_source_sha_is_rejected_instead_of_repaired(self) -> None:
        self._write_records(
            external_mutation=lambda value: value.__setitem__("sourceCommitSHA", f" {self.source_sha}"),
            field_mutation=lambda value: value.__setitem__("sourceCommitSHA", f" {self.source_sha}"),
        )
        self.assert_verification_fails("external sourceCommitSHA has a noncanonical value")

    def test_plist_build_identity_mismatch_is_rejected(self) -> None:
        bad_plist = plistlib.dumps(
            {
                "CFBundleExecutable": "Nembra",
                "CFBundleIdentifier": VERIFIER.EXPECTED_BUNDLE_ID,
                "NembraCaptureBuildIdentifier": self.build_identifier,
                "NembraCaptureBuildInstanceID": "fedcba98-7654-3210-fedc-ba9876543210",
                "NembraCaptureBuildCommitSHA": self.source_sha,
            },
            fmt=plistlib.FMT_BINARY,
            sort_keys=True,
        )
        (self.evidence_dir / "Info.plist").write_bytes(bad_plist)
        self._write_app_archive(self.executable_bytes, bad_plist)
        self._write_records()
        self.assert_verification_fails("build-instance ID does not match")

    def test_parent_directory_zip_entry_is_rejected(self) -> None:
        self._write_app_archive(self.executable_bytes, self.plist_bytes, "../escape")
        self._write_records()
        self.assert_verification_fails("parent-directory traversal")


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import plistlib
import sys
import tempfile
import unittest
import uuid
import zipfile
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_field_candidate_verify.py"
spec = importlib.util.spec_from_file_location("field_verify", MODULE_PATH)
assert spec and spec.loader
field_verify = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = field_verify
spec.loader.exec_module(field_verify)

HEAD = "1" * 40
INSTANCE = str(uuid.UUID("12345678-1234-4234-8234-123456789abc"))


def fake_signing_probe(app_path: Path, bundle_id: str):
    if not app_path.name.endswith(".app"):
        raise AssertionError("expected extracted app bundle")
    if bundle_id != field_verify.EXPECTED_BUNDLE_ID:
        raise AssertionError("unexpected bundle id")
    return field_verify.SigningEvidence(
        team_identifier="ABCDEFGHIJ",
        code_directory_hash="a" * 40,
        provisioning_profile_uuid="profile-uuid",
        provisioning_profile_expiration_utc="2030-01-01T00:00:00Z",
    )


def make_ipa(path: Path, *, source_sha: str = HEAD, instance: str = INSTANCE, extra_plist=None):
    plist = {
        "CFBundleExecutable": "Nembra",
        "CFBundleIdentifier": field_verify.EXPECTED_BUNDLE_ID,
        "NembraCaptureBuildIdentifier": "Capture Field V14-111111111111",
        "NembraCaptureBuildInstanceID": instance,
        "NembraCaptureBuildCommitSHA": source_sha,
    }
    if extra_plist:
        plist.update(extra_plist)
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("Payload/Nembra.app/Info.plist", plistlib.dumps(plist))
        archive.writestr("Payload/Nembra.app/Nembra", b"signed executable bytes")
        archive.writestr("Payload/Nembra.app/embedded.mobileprovision", b"profile")


class FieldCandidateVerifierTests(unittest.TestCase):
    def test_valid_candidate_emits_closed_candidate_only_record(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(ipa)
            evidence = field_verify.inspect_candidate(ipa, HEAD, signing_probe=fake_signing_probe)
            record = field_verify.build_record(evidence)
            self.assertEqual(record["schemaVersion"], 1)
            self.assertEqual(record["status"], "candidate-only-no-go")
            self.assertEqual(record["platform"], "ios-device")
            self.assertEqual(record["buildInstanceID"], INSTANCE)
            self.assertEqual(record["sourceCommitSHA"], HEAD)
            self.assertNotIn("physicalGO", record)
            self.assertNotIn("authorized", record)

    def test_mismatched_embedded_source_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(ipa, source_sha="2" * 40)
            with self.assertRaisesRegex(field_verify.VerificationError, "does not equal"):
                field_verify.inspect_candidate(ipa, HEAD, signing_probe=fake_signing_probe)

    def test_padded_or_uppercase_build_instance_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(ipa, instance=INSTANCE.upper())
            with self.assertRaisesRegex(field_verify.VerificationError, "canonical lowercase"):
                field_verify.inspect_candidate(ipa, HEAD, signing_probe=fake_signing_probe)

    def test_wrong_bundle_identifier_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(ipa, extra_plist={"CFBundleIdentifier": "example.wrong"})
            with self.assertRaisesRegex(field_verify.VerificationError, "bundle identifier"):
                field_verify.inspect_candidate(ipa, HEAD, signing_probe=fake_signing_probe)

    def test_unsafe_archive_path_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(ipa)
            with zipfile.ZipFile(ipa, "a") as archive:
                archive.writestr("../escape", b"nope")
            with self.assertRaisesRegex(field_verify.VerificationError, "unsafe archive path"):
                field_verify.inspect_candidate(ipa, HEAD, signing_probe=fake_signing_probe)

    def test_duplicate_app_payload_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(ipa)
            other = {
                "CFBundleExecutable": "Other",
                "CFBundleIdentifier": field_verify.EXPECTED_BUNDLE_ID,
                "NembraCaptureBuildIdentifier": "Capture Field V14-111111111111",
                "NembraCaptureBuildInstanceID": INSTANCE,
                "NembraCaptureBuildCommitSHA": HEAD,
            }
            with zipfile.ZipFile(ipa, "a") as archive:
                archive.writestr("Payload/Other.app/Info.plist", plistlib.dumps(other))
                archive.writestr("Payload/Other.app/Other", b"other")
            with self.assertRaisesRegex(field_verify.VerificationError, "exactly one"):
                field_verify.inspect_candidate(ipa, HEAD, signing_probe=fake_signing_probe)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import plistlib
import sys
import tempfile
import unittest
import uuid
import warnings
import zipfile
from datetime import datetime, timezone
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_signed_field_artifact_evidence.py"
spec = importlib.util.spec_from_file_location("signed_field_evidence", MODULE_PATH)
assert spec and spec.loader
signed_field_evidence = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = signed_field_evidence
spec.loader.exec_module(signed_field_evidence)

SOURCE_SHA = "1" * 40
BUILD_INSTANCE_ID = str(uuid.UUID("12345678-1234-4234-8234-123456789abc"))
TEAM_ID = "ABCDEFGHIJ"
BUNDLE_ID = signed_field_evidence.BUNDLE_ID
CDHASH = "c" * 40


def valid_codesign_metadata() -> str:
    return "\n".join(
        [
            "Executable=/tmp/Payload/Nembra.app/Nembra",
            f"TeamIdentifier={TEAM_ID}",
            "Authority=Apple Development: Nembra",
            "Authority=Apple Worldwide Developer Relations Certification Authority",
            f"CDHash={CDHASH}",
        ]
    )


def valid_profile() -> dict:
    return {
        "TeamIdentifier": [TEAM_ID],
        "UUID": "A1B2C3D4-E5F6-47A8-90BC-DEF123456789",
        "ExpirationDate": datetime(2100, 1, 1, tzinfo=timezone.utc),
        "Entitlements": {"application-identifier": f"{TEAM_ID}.{BUNDLE_ID}"},
    }


def fake_signing_probe(app_path: Path, bundle_identifier: str):
    if not app_path.name.endswith(".app"):
        raise AssertionError("expected extracted app bundle")
    if bundle_identifier != BUNDLE_ID:
        raise AssertionError("unexpected bundle identifier")
    return signed_field_evidence.SigningInspection(
        team_identifier=TEAM_ID,
        signing_authorities=["Apple Development: Nembra"],
        code_directory_hash=CDHASH,
        provisioning_profile_uuid="A1B2C3D4-E5F6-47A8-90BC-DEF123456789",
        provisioning_profile_expiration_utc="2100-01-01T00:00:00Z",
        provisioning_application_identifier=f"{TEAM_ID}.{BUNDLE_ID}",
    )


def make_ipa(path: Path) -> None:
    info = {
        "CFBundleExecutable": "Nembra",
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "DTPlatformName": "iphoneos",
        "NembraCaptureBuildIdentifier": "Capture Build V14-111111111111",
        "NembraCaptureBuildInstanceID": BUILD_INSTANCE_ID,
        "NembraCaptureBuildCommitSHA": SOURCE_SHA,
    }
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", UserWarning)
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("Payload/Nembra.app/Info.plist", plistlib.dumps(info))
            archive.writestr("Payload/Nembra.app/Nembra", b"signed executable bytes")
            archive.writestr("Payload/Nembra.app/embedded.mobileprovision", b"profile placeholder")


class SignedFieldArtifactEvidenceTests(unittest.TestCase):
    def test_pure_signing_parser_accepts_exact_team_cdhash_and_profile_binding(self):
        result = signed_field_evidence.parse_signing_inspection(
            valid_codesign_metadata(),
            valid_profile(),
            BUNDLE_ID,
        )

        self.assertEqual(result.team_identifier, TEAM_ID)
        self.assertEqual(result.code_directory_hash, CDHASH)
        self.assertEqual(result.provisioning_profile_uuid, "A1B2C3D4-E5F6-47A8-90BC-DEF123456789")
        self.assertEqual(result.provisioning_profile_expiration_utc, "2100-01-01T00:00:00Z")
        self.assertEqual(result.provisioning_application_identifier, f"{TEAM_ID}.{BUNDLE_ID}")

    def test_signing_parser_rejects_profile_team_mismatch(self):
        profile = valid_profile()
        profile["TeamIdentifier"] = ["ZZZZZZZZZZ"]
        with self.assertRaisesRegex(signed_field_evidence.EvidenceError, "TeamIdentifier"):
            signed_field_evidence.parse_signing_inspection(valid_codesign_metadata(), profile, BUNDLE_ID)

    def test_signing_parser_rejects_profile_application_identifier_mismatch(self):
        profile = valid_profile()
        profile["Entitlements"] = {"application-identifier": f"{TEAM_ID}.example.wrong"}
        with self.assertRaisesRegex(signed_field_evidence.EvidenceError, "application-identifier"):
            signed_field_evidence.parse_signing_inspection(valid_codesign_metadata(), profile, BUNDLE_ID)

    def test_signing_parser_rejects_expired_profile(self):
        profile = valid_profile()
        profile["ExpirationDate"] = datetime(2000, 1, 1, tzinfo=timezone.utc)
        with self.assertRaisesRegex(signed_field_evidence.EvidenceError, "expired"):
            signed_field_evidence.parse_signing_inspection(valid_codesign_metadata(), profile, BUNDLE_ID)

    def test_signing_parser_rejects_missing_or_malformed_cdhash(self):
        without_cdhash = "\n".join(
            line for line in valid_codesign_metadata().splitlines() if not line.startswith("CDHash=")
        )
        with self.assertRaisesRegex(signed_field_evidence.EvidenceError, "CDHash"):
            signed_field_evidence.parse_signing_inspection(without_cdhash, valid_profile(), BUNDLE_ID)

        malformed = valid_codesign_metadata().replace(CDHASH, "NOT-A-HASH")
        with self.assertRaisesRegex(signed_field_evidence.EvidenceError, "CDHash"):
            signed_field_evidence.parse_signing_inspection(malformed, valid_profile(), BUNDLE_ID)

    def test_inspect_ipa_keeps_package_schema_v1_and_emits_signing_inspection_v2(self):
        with tempfile.TemporaryDirectory() as temporary:
            ipa = Path(temporary) / "Nembra.ipa"
            make_ipa(ipa)
            inspection = signed_field_evidence.inspect_ipa(
                ipa,
                SOURCE_SHA,
                signing_probe=fake_signing_probe,
            )

        field = inspection["field_build_record"]
        signing = inspection["signing_inspection"]
        expected_field_keys = {
            "schemaVersion",
            "externalBuildRecordSHA256",
            "signedInstallableSHA256",
            "signedInstallableKind",
            "buildIdentifier",
            "buildInstanceID",
            "sourceCommitSHA",
            "executableSHA256",
            "infoPlistSHA256",
            "experimentRecipeID",
            "procedureVersion",
        }
        self.assertEqual(set(field), expected_field_keys)
        self.assertEqual(field["schemaVersion"], 1)
        self.assertNotIn("teamIdentifier", field)
        self.assertNotIn("physicalGO", field)
        self.assertNotIn("authorized", field)

        self.assertEqual(signing["schemaVersion"], 2)
        self.assertEqual(signing["authority"], "signed-field-artifact-inspection-not-field-authorization")
        self.assertEqual(signing["teamIdentifier"], TEAM_ID)
        self.assertEqual(signing["codeDirectoryHash"], CDHASH)
        self.assertEqual(signing["provisioningProfileUUID"], "A1B2C3D4-E5F6-47A8-90BC-DEF123456789")
        self.assertEqual(signing["provisioningProfileExpirationUTC"], "2100-01-01T00:00:00Z")
        self.assertEqual(signing["provisioningApplicationIdentifier"], f"{TEAM_ID}.{BUNDLE_ID}")
        self.assertEqual(
            signing["fieldBuildEvidenceRecordSHA256"],
            hashlib.sha256(inspection["field_build_bytes"]).hexdigest(),
        )
        self.assertNotIn("physicalGO", signing)
        self.assertNotIn("authorized", signing)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import importlib.util
import json
import plistlib
import tempfile
import unittest
from unittest import mock
import zipfile
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("verify_es80_field_artifact.py")
spec = importlib.util.spec_from_file_location("verify_es80_field_artifact", MODULE_PATH)
assert spec and spec.loader
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)

COMMIT = "a" * 40
BUILD_ID = "Capture Build V14-aaaaaaaaaaaa"
INSTANCE = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
EXECUTABLE = b"signed-nembra-executable-fixture"
DEVICE_UDID = "00008101-001234567890001E"
TEAM_ID = "ABCDE12345"


class FieldArtifactVerifierTests(unittest.TestCase):
    def make_fixture(self, root: Path, *, platform: str = "iphoneos", extra_record=None, embedded_record=False):
        info = {
            "CFBundleIdentifier": verifier.EXPECTED_BUNDLE_ID,
            "CFBundleExecutable": "Nembra",
            "DTPlatformName": platform,
            verifier.BUILD_IDENTIFIER_KEY: BUILD_ID,
            verifier.BUILD_INSTANCE_ID_KEY: INSTANCE,
            verifier.SOURCE_COMMIT_SHA_KEY: COMMIT,
        }
        info_bytes = plistlib.dumps(info, fmt=plistlib.FMT_BINARY, sort_keys=True)
        record = {
            "schemaVersion": 3,
            "buildIdentifier": BUILD_ID,
            "buildInstanceID": INSTANCE,
            "sourceCommitSHA": COMMIT,
            "executableSHA256": verifier.sha256_bytes(EXECUTABLE),
            "infoPlistSHA256": verifier.sha256_bytes(info_bytes),
            "experimentRecipeID": verifier.EXPECTED_RECIPE_ID,
            "procedureVersion": verifier.EXPECTED_PROCEDURE_VERSION,
        }
        if extra_record:
            record.update(extra_record)
        record_path = root / "NembraCaptureExternalBuildRecord.json"
        record_path.write_text(json.dumps(record, sort_keys=True) + "\n", encoding="utf-8")

        ipa_path = root / "Nembra.ipa"
        with zipfile.ZipFile(ipa_path, "w") as archive:
            archive.writestr("Payload/Nembra.app/Info.plist", info_bytes)
            archive.writestr("Payload/Nembra.app/Nembra", EXECUTABLE)
            archive.writestr("Payload/Nembra.app/embedded.mobileprovision", b"fixture-profile")
            archive.writestr("Payload/Nembra.app/_CodeSignature/CodeResources", b"fixture-seal")
            if embedded_record:
                archive.writestr(
                    "Payload/Nembra.app/NembraCaptureExternalBuildRecord.json",
                    record_path.read_bytes(),
                )
        return ipa_path, record_path

    def verify_static(self, ipa_path: Path, record_path: Path):
        extraction_root = ipa_path.parent / "extract"
        extraction_root.mkdir()
        return verifier.verify_static_artifact(
            ipa_path=ipa_path,
            external_record_path=record_path,
            expected_source_commit=COMMIT,
            extraction_root=extraction_root,
        )

    def make_profile(self, **overrides):
        expiration = datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(days=30)
        profile = {
            "Platform": ["iOS"],
            "TeamIdentifier": [TEAM_ID],
            "ApplicationIdentifierPrefix": [TEAM_ID],
            "ExpirationDate": expiration,
            "ProvisionedDevices": [DEVICE_UDID],
            "Entitlements": {
                "application-identifier": f"{TEAM_ID}.{verifier.EXPECTED_BUNDLE_ID}",
                "com.apple.developer.team-identifier": TEAM_ID,
            },
        }
        profile.update(overrides)
        return profile

    def mock_security_decode(self, profile):
        return mock.patch.object(
            verifier.subprocess,
            "run",
            return_value=mock.Mock(
                returncode=0,
                stdout=plistlib.dumps(profile),
                stderr=b"",
            ),
        )

    def test_exact_signed_artifact_shape_correlates_without_minting_go(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            ipa_path, record_path = self.make_fixture(root)
            evidence, _ = self.verify_static(ipa_path, record_path)
            self.assertEqual(evidence["schemaVersion"], 1)
            self.assertEqual(evidence["signedInstallableKind"], "ipa")
            self.assertEqual(evidence["sourceCommitSHA"], COMMIT)
            self.assertEqual(evidence["buildInstanceID"], INSTANCE)
            self.assertEqual(evidence["signedInstallableSHA256"], verifier.sha256_file(ipa_path))

    def test_authority_looking_record_extension_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            ipa_path, record_path = self.make_fixture(root, extra_record={"physicalGO": True})
            with self.assertRaisesRegex(verifier.VerificationError, "exact schema-v3 key set"):
                self.verify_static(ipa_path, record_path)

    def test_simulator_platform_cannot_be_promoted_as_field_artifact(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            ipa_path, record_path = self.make_fixture(root, platform="iphonesimulator")
            with self.assertRaisesRegex(verifier.VerificationError, "not identified as an iPhoneOS"):
                self.verify_static(ipa_path, record_path)

    def test_embedded_external_authority_record_is_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            ipa_path, record_path = self.make_fixture(root, embedded_record=True)
            with self.assertRaisesRegex(verifier.VerificationError, "must not be embedded"):
                self.verify_static(ipa_path, record_path)

    def test_mutated_executable_cannot_match_record(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            ipa_path, record_path = self.make_fixture(root)
            mutated = root / "Mutated.ipa"
            with zipfile.ZipFile(ipa_path, "r") as source, zipfile.ZipFile(mutated, "w") as dest:
                for item in source.infolist():
                    data = source.read(item.filename)
                    if item.filename == "Payload/Nembra.app/Nembra":
                        data += b"tampered"
                    dest.writestr(item, data)
            extraction_root = root / "extract"
            extraction_root.mkdir()
            with self.assertRaisesRegex(verifier.VerificationError, "executable bytes do not match"):
                verifier.verify_static_artifact(
                    ipa_path=mutated,
                    external_record_path=record_path,
                    expected_source_commit=COMMIT,
                    extraction_root=extraction_root,
                )

    def test_codesign_unavailable_fails_closed(self):
        with mock.patch.object(verifier.shutil, "which", return_value=None):
            with self.assertRaisesRegex(verifier.VerificationError, "codesign is unavailable"):
                verifier.verify_code_signature(Path("/tmp/Nembra.app"))

    def test_codesign_identity_must_match_nembra_and_expose_team(self):
        success_verify = mock.Mock(returncode=0, stdout="", stderr="valid on disk\n")
        wrong_identity = mock.Mock(
            returncode=0,
            stdout="",
            stderr="Identifier=com.example.other\nTeamIdentifier=ABCDE12345\nAuthority=Apple Development\n",
        )
        with mock.patch.object(verifier.shutil, "which", return_value="/usr/bin/codesign"), mock.patch.object(
            verifier.subprocess, "run", side_effect=[success_verify, wrong_identity]
        ):
            with self.assertRaisesRegex(verifier.VerificationError, "identifier does not match"):
                verifier.verify_code_signature(Path("/tmp/Nembra.app"))

    def test_archive_path_traversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            ipa_path, record_path = self.make_fixture(root)
            malicious = root / "Malicious.ipa"
            with zipfile.ZipFile(ipa_path, "r") as source, zipfile.ZipFile(malicious, "w") as dest:
                for item in source.infolist():
                    dest.writestr(item, source.read(item.filename))
                dest.writestr("../escape", b"bad")
            extraction_root = root / "extract"
            extraction_root.mkdir()
            with self.assertRaisesRegex(verifier.VerificationError, "unsafe path"):
                verifier.verify_static_artifact(
                    ipa_path=malicious,
                    external_record_path=record_path,
                    expected_source_commit=COMMIT,
                    extraction_root=extraction_root,
                )

    def test_duplicate_archive_path_is_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            ipa_path, record_path = self.make_fixture(root)
            malicious = root / "Duplicate.ipa"
            with zipfile.ZipFile(ipa_path, "r") as source, zipfile.ZipFile(malicious, "w") as dest:
                for item in source.infolist():
                    dest.writestr(item, source.read(item.filename))
                dest.writestr("Payload/Nembra.app/Nembra", b"ambiguous-second-entry")
            extraction_root = root / "extract"
            extraction_root.mkdir()
            with self.assertRaisesRegex(verifier.VerificationError, "duplicate path"):
                verifier.verify_static_artifact(
                    ipa_path=malicious,
                    external_record_path=record_path,
                    expected_source_commit=COMMIT,
                    extraction_root=extraction_root,
                )

    def test_provisioning_profile_must_cover_exact_target_device(self):
        profile = self.make_profile()
        signature = {"identifier": verifier.EXPECTED_BUNDLE_ID, "teamIdentifier": TEAM_ID}
        with mock.patch.object(verifier.shutil, "which", return_value="/usr/bin/security"), self.mock_security_decode(profile):
            metadata = verifier.verify_provisioning_profile(
                app_path=Path("/tmp/Nembra.app"),
                expected_device_udid=DEVICE_UDID,
                code_signature=signature,
            )
        self.assertTrue(metadata["targetDeviceProvisioningMatched"])
        self.assertEqual(metadata["teamIdentifier"], TEAM_ID)

    def test_provisioning_profile_rejects_wrong_device(self):
        profile = self.make_profile(ProvisionedDevices=["00008101-00FFFFFFFFFFFFFF"])
        signature = {"identifier": verifier.EXPECTED_BUNDLE_ID, "teamIdentifier": TEAM_ID}
        with mock.patch.object(verifier.shutil, "which", return_value="/usr/bin/security"), self.mock_security_decode(profile):
            with self.assertRaisesRegex(verifier.VerificationError, "expected field device"):
                verifier.verify_provisioning_profile(
                    app_path=Path("/tmp/Nembra.app"),
                    expected_device_udid=DEVICE_UDID,
                    code_signature=signature,
                )

    def test_provisioning_profile_rejects_expired_or_wrong_team(self):
        expired = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(days=1)
        profile = self.make_profile(ExpirationDate=expired)
        signature = {"identifier": verifier.EXPECTED_BUNDLE_ID, "teamIdentifier": TEAM_ID}
        with mock.patch.object(verifier.shutil, "which", return_value="/usr/bin/security"), self.mock_security_decode(profile):
            with self.assertRaisesRegex(verifier.VerificationError, "expired"):
                verifier.verify_provisioning_profile(
                    app_path=Path("/tmp/Nembra.app"),
                    expected_device_udid=DEVICE_UDID,
                    code_signature=signature,
                )

        wrong_team_signature = {
            "identifier": verifier.EXPECTED_BUNDLE_ID,
            "teamIdentifier": "ZZZZZ99999",
        }
        profile = self.make_profile()
        with mock.patch.object(verifier.shutil, "which", return_value="/usr/bin/security"), self.mock_security_decode(profile):
            with self.assertRaisesRegex(verifier.VerificationError, "TeamIdentifier"):
                verifier.verify_provisioning_profile(
                    app_path=Path("/tmp/Nembra.app"),
                    expected_device_udid=DEVICE_UDID,
                    code_signature=wrong_team_signature,
                )


if __name__ == "__main__":
    unittest.main()

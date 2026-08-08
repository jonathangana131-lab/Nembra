#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import plistlib
import sys
import tempfile
import unittest
import uuid
import zipfile
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_signed_field_artifact_evidence.py"
spec = importlib.util.spec_from_file_location("signed_field_evidence", MODULE_PATH)
assert spec and spec.loader
signed_field_evidence = importlib.util.module_from_spec(spec)
# dataclasses resolves annotation/module identity through sys.modules during decoration. Register the
# dynamic module before executing it so the focused suite is importable on the trusted Python runner.
sys.modules[spec.name] = signed_field_evidence
spec.loader.exec_module(signed_field_evidence)

HEAD = "1" * 40
INSTANCE = str(uuid.UUID("12345678-1234-4234-8234-123456789abc"))
TEAM = "ABCDEFGHIJ"


def fake_signing_probe(app_path: Path, bundle_id: str):
    if not app_path.name.endswith(".app"):
        raise AssertionError("expected extracted app bundle")
    if bundle_id != signed_field_evidence.BUNDLE_ID:
        raise AssertionError("unexpected bundle id")
    return signed_field_evidence.SigningEvidence(
        team_identifier=TEAM,
        signing_authorities=["Apple Development: Nembra"],
        code_directory_hash="a" * 40,
        provisioning_profile_uuid="12345678-1234-4234-8234-123456789abc",
        provisioning_profile_expiration_utc="2030-01-01T00:00:00Z",
    )


def make_ipa(path: Path, *, source_sha: str = HEAD, instance: str = INSTANCE, extra_plist=None, extra_members=None):
    plist = {
        "CFBundleExecutable": "Nembra",
        "CFBundleIdentifier": signed_field_evidence.BUNDLE_ID,
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "DTPlatformName": "iphoneos",
        "NembraCaptureBuildIdentifier": "Capture Build V14-111111111111",
        "NembraCaptureBuildInstanceID": instance,
        "NembraCaptureBuildCommitSHA": source_sha,
    }
    if extra_plist:
        plist.update(extra_plist)
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("Payload/Nembra.app/Info.plist", plistlib.dumps(plist))
        archive.writestr("Payload/Nembra.app/Nembra", b"signed executable bytes")
        archive.writestr("Payload/Nembra.app/embedded.mobileprovision", b"profile")
        for name, data in extra_members or []:
            archive.writestr(name, data)


def valid_profile_and_entitlements():
    app_identifier = f"{TEAM}.{signed_field_evidence.BUNDLE_ID}"
    profile = {
        "TeamIdentifier": [TEAM],
        "UUID": INSTANCE,
        "ExpirationDate": datetime(2099, 1, 1, tzinfo=timezone.utc),
        "Entitlements": {
            "application-identifier": app_identifier,
            "com.apple.developer.team-identifier": TEAM,
        },
    }
    signed = {
        "application-identifier": app_identifier,
        "com.apple.developer.team-identifier": TEAM,
    }
    return profile, signed


class SignedFieldArtifactEvidenceTests(unittest.TestCase):
    def test_valid_ipa_emits_one_schema_v2_non_authorizing_evidence_format(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(ipa)
            inspection = signed_field_evidence.inspect_ipa(ipa, HEAD, signing_probe=fake_signing_probe)
            evidence = inspection["field_evidence"]
            external_bytes = inspection["external_bytes"]

            self.assertEqual(evidence["schemaVersion"], 2)
            self.assertEqual(evidence["authority"], "signed-field-artifact-evidence-not-field-authorization")
            self.assertEqual(evidence["sourceCommitSHA"], HEAD)
            self.assertEqual(evidence["buildInstanceID"], INSTANCE)
            self.assertEqual(evidence["teamIdentifier"], TEAM)
            self.assertEqual(evidence["codeDirectoryHash"], "a" * 40)
            self.assertEqual(evidence["provisioningProfileUUID"], INSTANCE)
            self.assertEqual(evidence["provisioningProfileExpirationUTC"], "2030-01-01T00:00:00Z")
            self.assertEqual(evidence["externalBuildRecordSHA256"], hashlib.sha256(external_bytes).hexdigest())
            self.assertNotIn("physicalGO", evidence)
            self.assertNotIn("authorized", evidence)

    def test_write_outputs_retains_exact_ipa_and_exact_external_record(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            ipa = root / "Nembra.ipa"
            make_ipa(ipa)
            inspection = signed_field_evidence.inspect_ipa(ipa, HEAD, signing_probe=fake_signing_probe)
            paths = signed_field_evidence.write_outputs(ipa, root / "out", inspection)

            self.assertEqual(paths["retained_ipa"].read_bytes(), ipa.read_bytes())
            self.assertEqual(paths["external_record"].read_bytes(), inspection["external_bytes"])
            emitted = json.loads(paths["field_evidence"].read_text())
            self.assertEqual(emitted, inspection["field_evidence"])

    def test_source_bundle_platform_and_build_label_mismatches_fail_closed(self):
        cases = [
            ({"NembraCaptureBuildCommitSHA": "2" * 40}, "source commit"),
            ({"CFBundleIdentifier": "example.wrong"}, "bundle identifier"),
            ({"DTPlatformName": "iphonesimulator"}, "iphoneos"),
            ({"NembraCaptureBuildIdentifier": "Capture Build V14-deadbeefdead"}, "build identifier"),
        ]
        for overrides, message in cases:
            with self.subTest(overrides=overrides), tempfile.TemporaryDirectory() as temp:
                ipa = Path(temp) / "Nembra.ipa"
                make_ipa(ipa, extra_plist=overrides)
                with self.assertRaisesRegex(signed_field_evidence.EvidenceError, message):
                    signed_field_evidence.inspect_ipa(ipa, HEAD, signing_probe=fake_signing_probe)

    def test_noncanonical_build_instance_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(ipa, instance=INSTANCE.upper())
            with self.assertRaisesRegex(signed_field_evidence.EvidenceError, "canonical lowercase"):
                signed_field_evidence.inspect_ipa(ipa, HEAD, signing_probe=fake_signing_probe)

    def test_unsafe_archive_member_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(ipa, extra_members=[("../escape", b"nope")])
            with self.assertRaisesRegex(signed_field_evidence.EvidenceError, "unsafe ZIP"):
                signed_field_evidence.inspect_ipa(ipa, HEAD, signing_probe=fake_signing_probe)

    def test_duplicate_app_payload_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            other = plistlib.dumps({"CFBundleExecutable": "Other"})
            make_ipa(
                ipa,
                extra_members=[
                    ("Payload/Other.app/Info.plist", other),
                    ("Payload/Other.app/Other", b"other"),
                ],
            )
            with self.assertRaisesRegex(signed_field_evidence.EvidenceError, "exactly one"):
                signed_field_evidence.inspect_ipa(ipa, HEAD, signing_probe=fake_signing_probe)

    def test_duplicate_exact_archive_destination_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(
                ipa,
                extra_members=[("Payload/Nembra.app/Info.plist", plistlib.dumps({"replacement": True}))],
            )
            with self.assertRaisesRegex(signed_field_evidence.EvidenceError, "duplicate normalized"):
                signed_field_evidence.inspect_ipa(ipa, HEAD, signing_probe=fake_signing_probe)

    def test_repeated_separator_and_dot_segment_aliases_fail_before_extraction(self):
        aliases = [
            "Payload//Nembra.app/Info.plist",
            "Payload/./Nembra.app/Info.plist",
        ]
        for alias in aliases:
            with self.subTest(alias=alias), tempfile.TemporaryDirectory() as temp:
                ipa = Path(temp) / "Nembra.ipa"
                make_ipa(ipa, extra_members=[(alias, b"ambiguous")])
                with self.assertRaisesRegex(signed_field_evidence.EvidenceError, "unsafe ZIP"):
                    signed_field_evidence.inspect_ipa(ipa, HEAD, signing_probe=fake_signing_probe)

    def test_case_fold_archive_destination_collision_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(
                ipa,
                extra_members=[("payload/nembra.app/info.plist", b"case collision")],
            )
            with self.assertRaisesRegex(signed_field_evidence.EvidenceError, "case-colliding"):
                signed_field_evidence.inspect_ipa(ipa, HEAD, signing_probe=fake_signing_probe)

    def test_embedded_external_authority_files_fail_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(
                ipa,
                extra_members=[("Payload/Nembra.app/NembraCaptureExternalBuildRecord.json", b"{}")],
            )
            with self.assertRaisesRegex(signed_field_evidence.EvidenceError, "must stay outside"):
                signed_field_evidence.inspect_ipa(ipa, HEAD, signing_probe=fake_signing_probe)

    def test_profile_and_actual_signed_entitlements_must_match_exact_team_and_bundle(self):
        profile, signed = valid_profile_and_entitlements()
        profile_uuid, expiration = signed_field_evidence._validate_signing_contract(
            team_identifier=TEAM,
            bundle_id=signed_field_evidence.BUNDLE_ID,
            profile=profile,
            signed_entitlements=signed,
        )
        self.assertEqual(profile_uuid, INSTANCE)
        self.assertTrue(expiration.endswith("Z"))

        mismatches = [
            ({**signed, "application-identifier": f"{TEAM}.example.wrong"}, "signed app application-identifier"),
            ({**signed, "com.apple.developer.team-identifier": "ZZZZZZZZZZ"}, "signed app developer-team"),
        ]
        for bad_signed, message in mismatches:
            with self.subTest(message=message):
                with self.assertRaisesRegex(signed_field_evidence.EvidenceError, message):
                    signed_field_evidence._validate_signing_contract(
                        team_identifier=TEAM,
                        bundle_id=signed_field_evidence.BUNDLE_ID,
                        profile=profile,
                        signed_entitlements=bad_signed,
                    )

    def test_profile_entitlement_team_must_match_codesign_team(self):
        profile, signed = valid_profile_and_entitlements()
        profile["Entitlements"] = {
            **profile["Entitlements"],
            "com.apple.developer.team-identifier": "ZZZZZZZZZZ",
        }
        with self.assertRaisesRegex(signed_field_evidence.EvidenceError, "provisioning profile developer-team"):
            signed_field_evidence._validate_signing_contract(
                team_identifier=TEAM,
                bundle_id=signed_field_evidence.BUNDLE_ID,
                profile=profile,
                signed_entitlements=signed,
            )


if __name__ == "__main__":
    unittest.main()

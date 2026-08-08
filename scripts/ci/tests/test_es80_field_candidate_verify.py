#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
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
BUILD_ID = f"Capture Build V14-{HEAD[:12]}"


def fake_signing_probe(app_path: Path, bundle_id: str):
    if not app_path.name.endswith(".app"):
        raise AssertionError("expected extracted app bundle")
    if bundle_id != field_verify.EXPECTED_BUNDLE_ID:
        raise AssertionError("unexpected bundle id")
    profile = b"profile-bytes"
    return field_verify.SigningEvidence(
        team_identifier="ABCDEFGHIJ",
        code_directory_hash="a" * 40,
        provisioning_profile_uuid="profile-uuid",
        provisioning_profile_expiration_utc="2030-01-01T00:00:00Z",
        provisioning_profile_sha256=field_verify.sha_bytes(profile),
        provisioning_profile_bytes=profile,
    )


def make_ipa(
    path: Path,
    *,
    source_sha: str = HEAD,
    instance: str = INSTANCE,
    build_identifier: str = BUILD_ID,
    extra_plist=None,
):
    plist = {
        "CFBundleExecutable": "Nembra",
        "CFBundleIdentifier": field_verify.EXPECTED_BUNDLE_ID,
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "DTPlatformName": "iphoneos",
        "NembraCaptureBuildIdentifier": build_identifier,
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
    def inspect_fixture(self, ipa: Path):
        return field_verify.inspect_candidate(
            ipa,
            HEAD,
            signing_probe=fake_signing_probe,
        )

    def test_valid_candidate_emits_exact_package_owned_field_schema(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(ipa)
            evidence = self.inspect_fixture(ipa)
            external_bytes = field_verify.canonical_json_bytes(
                field_verify.external_build_record(evidence)
            )
            record = field_verify.field_build_evidence_record(evidence, external_bytes)

            self.assertEqual(
                set(record),
                {
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
                },
            )
            self.assertEqual(record["schemaVersion"], 1)
            self.assertEqual(record["signedInstallableKind"], "ipa")
            self.assertEqual(record["externalBuildRecordSHA256"], field_verify.sha_bytes(external_bytes))
            self.assertEqual(record["signedInstallableSHA256"], field_verify.sha_file(ipa))
            self.assertEqual(record["buildIdentifier"], BUILD_ID)
            self.assertEqual(record["buildInstanceID"], INSTANCE)
            self.assertEqual(record["sourceCommitSHA"], HEAD)
            self.assertEqual(record["experimentRecipeID"], "ES80-FINGERPRINT-v1")
            self.assertEqual(record["procedureVersion"], "V14")
            self.assertNotIn("status", record)
            self.assertNotIn("physicalGO", record)
            self.assertNotIn("authorized", record)
            self.assertNotIn("teamIdentifier", record)

    def test_signing_metadata_is_separate_supporting_no_go_record(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(ipa)
            evidence = self.inspect_fixture(ipa)
            signing = field_verify.signing_evidence_record(evidence)

            self.assertEqual(signing["status"], "signing-evidence-only-no-go")
            self.assertEqual(signing["teamIdentifier"], "ABCDEFGHIJ")
            self.assertEqual(signing["signedInstallableSHA256"], evidence.ipa_sha256)
            self.assertNotIn("physicalGO", signing)
            self.assertNotIn("authorized", signing)
            self.assertNotIn("accepted", signing)

    def test_retain_candidate_binds_exact_external_record_and_ipa_bytes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            ipa = root / "Nembra.ipa"
            make_ipa(ipa)
            evidence = self.inspect_fixture(ipa)
            output = root / "evidence"
            paths = field_verify.retain_candidate(ipa, output, evidence)

            external = paths["externalBuildRecord"].read_bytes()
            field_record = json.loads(paths["fieldBuildEvidenceRecord"].read_text())
            self.assertEqual(
                field_record["externalBuildRecordSHA256"],
                field_verify.sha_bytes(external),
            )
            self.assertEqual(
                field_record["signedInstallableSHA256"],
                field_verify.sha_file(paths["retainedIPA"]),
            )
            self.assertEqual(
                field_verify.sha_file(output / "build-evidence" / "Info.plist"),
                evidence.info_plist_sha256,
            )
            self.assertIn("NO-GO", paths["boundary"].read_text())

            with self.assertRaisesRegex(field_verify.VerificationError, "refusing to overwrite"):
                field_verify.retain_candidate(ipa, output, evidence)

    def test_mismatched_embedded_source_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(ipa, source_sha="2" * 40)
            with self.assertRaisesRegex(field_verify.VerificationError, "does not equal"):
                self.inspect_fixture(ipa)

    def test_detached_build_identifier_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(ipa, build_identifier="Capture Field V14-111111111111")
            with self.assertRaisesRegex(field_verify.VerificationError, "does not match exact source"):
                self.inspect_fixture(ipa)

    def test_padded_or_uppercase_build_instance_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(ipa, instance=INSTANCE.upper())
            with self.assertRaisesRegex(field_verify.VerificationError, "canonical lowercase"):
                self.inspect_fixture(ipa)

    def test_wrong_bundle_identifier_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(ipa, extra_plist={"CFBundleIdentifier": "example.wrong"})
            with self.assertRaisesRegex(field_verify.VerificationError, "bundle identifier"):
                self.inspect_fixture(ipa)

    def test_simulator_platform_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(
                ipa,
                extra_plist={
                    "DTPlatformName": "iphonesimulator",
                    "CFBundleSupportedPlatforms": ["iPhoneSimulator"],
                },
            )
            with self.assertRaisesRegex(field_verify.VerificationError, "DTPlatformName"):
                self.inspect_fixture(ipa)

    def test_unsafe_archive_path_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(ipa)
            with zipfile.ZipFile(ipa, "a") as archive:
                archive.writestr("../escape", b"nope")
            with self.assertRaisesRegex(field_verify.VerificationError, "unsafe archive path"):
                self.inspect_fixture(ipa)

    def test_duplicate_app_payload_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(ipa)
            other = {
                "CFBundleExecutable": "Other",
                "CFBundleIdentifier": field_verify.EXPECTED_BUNDLE_ID,
                "CFBundleSupportedPlatforms": ["iPhoneOS"],
                "DTPlatformName": "iphoneos",
                "NembraCaptureBuildIdentifier": BUILD_ID,
                "NembraCaptureBuildInstanceID": INSTANCE,
                "NembraCaptureBuildCommitSHA": HEAD,
            }
            with zipfile.ZipFile(ipa, "a") as archive:
                archive.writestr("Payload/Other.app/Info.plist", plistlib.dumps(other))
                archive.writestr("Payload/Other.app/Other", b"other")
            with self.assertRaisesRegex(field_verify.VerificationError, "exactly one"):
                self.inspect_fixture(ipa)

    def test_embedded_external_authority_record_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "Nembra.ipa"
            make_ipa(ipa)
            with zipfile.ZipFile(ipa, "a") as archive:
                archive.writestr(
                    "Payload/Nembra.app/NembraCaptureExternalBuildRecord.json",
                    b"{}",
                )
            with self.assertRaisesRegex(field_verify.VerificationError, "must remain outside"):
                self.inspect_fixture(ipa)


class SignedFieldCandidateProducerSourceTests(unittest.TestCase):
    def test_producer_targets_signed_ios_device_and_injects_exact_identity(self):
        script = (MODULE_PATH.parent / "xcode27_signed_field_candidate.sh").read_text()
        self.assertIn('generic/platform=iOS', script)
        self.assertNotIn('CODE_SIGNING_ALLOWED=NO', script)
        self.assertIn('BUILD_IDENTIFIER="Capture Build V14-', script)
        self.assertIn('INFOPLIST_KEY_NembraCaptureBuildIdentifier', script)
        self.assertIn('INFOPLIST_KEY_NembraCaptureBuildInstanceID', script)
        self.assertIn('INFOPLIST_KEY_NembraCaptureBuildCommitSHA', script)

    def test_producer_delegates_final_ipa_to_canonical_verifier(self):
        script = (MODULE_PATH.parent / "xcode27_signed_field_candidate.sh").read_text()
        self.assertIn('es80_field_candidate_verify.py', script)
        self.assertIn('NembraCaptureFieldBuildEvidenceRecord.json', script)
        self.assertIn('NembraCaptureExternalBuildRecord.json', script)
        self.assertIn('PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN', script)

    def test_producer_contains_no_field_gate_or_runbook_authorization_mutation(self):
        script = (MODULE_PATH.parent / "xcode27_signed_field_candidate.sh").read_text()
        self.assertNotIn('PassiveBluetoothExperimentOneFieldExecutionGate', script)
        self.assertNotIn('ES80_PHYSICAL_CAPTURE_RUNBOOK.md', script)
        self.assertNotIn('physicalGO', script)
        self.assertNotIn('"authorized"', script)


if __name__ == "__main__":
    unittest.main()

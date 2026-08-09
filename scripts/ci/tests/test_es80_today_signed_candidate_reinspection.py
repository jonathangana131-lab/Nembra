#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest import mock
import zipfile

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_signed_candidate_reinspection.py"
spec = importlib.util.spec_from_file_location("reinspection", MODULE_PATH)
reinspection = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(reinspection)


class SignedCandidateReinspectionTests(unittest.TestCase):
    TEAM = "ABCDE12345"
    UUID = "11111111-2222-3333-4444-555555555555"
    EXPIRY = datetime(2027, 8, 8, 12, 0, tzinfo=timezone.utc)
    AUTHORITIES = [
        "Apple Development: Nembra Test (ABCDE12345)",
        "Apple Worldwide Developer Relations Certification Authority",
        "Apple Root CA",
    ]
    CDHASH = "a" * 40

    def make_candidate(self, root: Path, *, claimed_team: str | None = None) -> tuple[Path, dict]:
        candidate = root / "candidate"
        inspection_root = candidate / "inspection"
        evidence = inspection_root / "build-evidence"
        evidence.mkdir(parents=True)

        ipa = evidence / "NembraField.ipa"
        with zipfile.ZipFile(ipa, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("Payload/Nembra.app/placeholder", b"placeholder")
        ipa_raw = ipa.read_bytes()

        app_source = root / "app-source"
        app_source.mkdir()
        info = {
            "CFBundleIdentifier": reinspection.EXPECTED_BUNDLE_ID,
            "CFBundleExecutable": "Nembra",
            "DTPlatformName": "iphoneos",
            "CFBundleSupportedPlatforms": ["iPhoneOS"],
        }
        info_raw = plistlib.dumps(info, fmt=plistlib.FMT_BINARY, sort_keys=True)
        (app_source / "Info.plist").write_bytes(info_raw)
        executable_raw = b"signed-nembra-executable"
        (app_source / "Nembra").write_bytes(executable_raw)
        profile_raw = b"signed-mobileprovision-container"
        (app_source / "embedded.mobileprovision").write_bytes(profile_raw)

        team = claimed_team or self.TEAM
        inspection = {
            "schemaVersion": 2,
            "authority": "signed-field-artifact-inspection-not-field-authorization",
            "fieldBuildEvidenceRecordSHA256": "b" * 64,
            "externalBuildRecordSHA256": "c" * 64,
            "signedInstallableSHA256": hashlib.sha256(ipa_raw).hexdigest(),
            "signedInstallableKind": "ipa",
            "ipaByteCount": len(ipa_raw),
            "buildIdentifier": "Capture Build V14-aaaaaaaaaaaa",
            "buildInstanceID": self.UUID,
            "sourceCommitSHA": "a" * 40,
            "bundleIdentifier": reinspection.EXPECTED_BUNDLE_ID,
            "platformName": "iphoneos",
            "supportedPlatforms": ["iPhoneOS"],
            "teamIdentifier": team,
            "signingAuthorities": self.AUTHORITIES,
            "codeDirectoryHash": self.CDHASH,
            "provisioningProfileSHA256": hashlib.sha256(profile_raw).hexdigest(),
            "provisioningProfileUUID": self.UUID,
            "provisioningProfileExpirationUTC": "2027-08-08T12:00:00Z",
            "provisioningApplicationIdentifier": f"{team}.{reinspection.EXPECTED_BUNDLE_ID}",
            "executableSHA256": hashlib.sha256(executable_raw).hexdigest(),
            "infoPlistSHA256": hashlib.sha256(info_raw).hexdigest(),
            "experimentRecipeID": "ES80-FINGERPRINT-v1",
            "procedureVersion": "V14",
        }
        (inspection_root / reinspection.INSPECTION_NAME).write_text(
            json.dumps(inspection, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        return candidate, {"app_source": app_source, "inspection": inspection}

    def extractor(self, app_source: Path):
        def extract(_ipa_path, _ipa_raw, destination, _runner):
            app = destination / "Payload" / "Nembra.app"
            app.mkdir(parents=True)
            for name in ("Info.plist", "Nembra", "embedded.mobileprovision"):
                (app / name).write_bytes((app_source / name).read_bytes())
            return app
        return extract

    def runner(self, *, team: str | None = None):
        actual_team = team or self.TEAM
        profile = {
            "TeamIdentifier": [actual_team],
            "UUID": self.UUID,
            "ExpirationDate": self.EXPIRY,
            "Entitlements": {
                "application-identifier": f"{actual_team}.{reinspection.EXPECTED_BUNDLE_ID}",
            },
        }
        codesign_details = (
            "\n".join(
                [f"Authority={value}" for value in self.AUTHORITIES]
                + [f"TeamIdentifier={actual_team}", f"CDHash={self.CDHASH}"]
            )
            + "\n"
        ).encode()

        def run(arguments: list[str]):
            if arguments[:2] == ["/usr/bin/codesign", "--verify"]:
                return subprocess.CompletedProcess(arguments, 0, b"", b"")
            if arguments[:3] == ["/usr/bin/codesign", "-d", "--verbose=4"]:
                return subprocess.CompletedProcess(arguments, 0, b"", codesign_details)
            if arguments[:4] == ["/usr/bin/security", "cms", "-D", "-i"]:
                return subprocess.CompletedProcess(
                    arguments,
                    0,
                    plistlib.dumps(profile, fmt=plistlib.FMT_XML, sort_keys=True),
                    b"",
                )
            raise AssertionError(arguments)
        return run

    def test_accepts_only_when_native_signing_facts_match_retained_inspection(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate, fixture = self.make_candidate(root)
            with mock.patch.object(
                reinspection,
                "_extract_ipa",
                side_effect=self.extractor(fixture["app_source"]),
            ):
                subject = reinspection.verify_signed_candidate_reinspection(
                    candidate_root=candidate,
                    runner=self.runner(),
                )
        self.assertEqual(subject["authority"], reinspection.REINSPECTION_AUTHORITY)
        self.assertEqual(subject["teamIdentifier"], self.TEAM)
        self.assertEqual(subject["codeDirectoryHash"], self.CDHASH)
        self.assertEqual(subject["signedInstallableSHA256"], fixture["inspection"]["signedInstallableSHA256"])

    def test_rejects_caller_supplied_signing_json_when_fresh_team_differs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate, fixture = self.make_candidate(root, claimed_team="ZZZZZ99999")
            with mock.patch.object(
                reinspection,
                "_extract_ipa",
                side_effect=self.extractor(fixture["app_source"]),
            ):
                with self.assertRaisesRegex(
                    reinspection.SignedCandidateReinspectionError,
                    "teamIdentifier",
                ):
                    reinspection.verify_signed_candidate_reinspection(
                        candidate_root=candidate,
                        runner=self.runner(team=self.TEAM),
                    )

    def test_rejects_retained_inspection_ipa_digest_forgery_before_apple_tools(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate, fixture = self.make_candidate(root)
            inspection_path = candidate / "inspection" / reinspection.INSPECTION_NAME
            forged = json.loads(inspection_path.read_text(encoding="utf-8"))
            forged["signedInstallableSHA256"] = "f" * 64
            inspection_path.write_text(json.dumps(forged) + "\n", encoding="utf-8")
            runner = mock.Mock()
            with self.assertRaisesRegex(
                reinspection.SignedCandidateReinspectionError,
                "IPA digest",
            ):
                reinspection.verify_signed_candidate_reinspection(
                    candidate_root=candidate,
                    runner=runner,
                )
            runner.assert_not_called()

    def test_rejects_symlinked_retained_ipa(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate, _fixture = self.make_candidate(root)
            ipa = candidate / "inspection" / reinspection.IPA_RELATIVE_PATH
            real = root / "real.ipa"
            ipa.replace(real)
            ipa.symlink_to(real)
            with self.assertRaisesRegex(
                reinspection.SignedCandidateReinspectionError,
                "non-symlink",
            ):
                reinspection.verify_signed_candidate_reinspection(candidate_root=candidate)


if __name__ == "__main__":
    unittest.main()

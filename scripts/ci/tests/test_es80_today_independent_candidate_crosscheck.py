#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "es80_today_independent_candidate_crosscheck.py"
SPEC = importlib.util.spec_from_file_location("candidate_crosscheck", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def canonical_bytes(value: object) -> bytes:
    return json.dumps(value, indent=2, sort_keys=True).encode("utf-8") + b"\n"


class CandidateCrosscheckTests(unittest.TestCase):
    SOURCE = "a" * 40
    BUILD = "Capture Build V14-aaaaaaaaaaaa"
    INSTANCE = "12345678-1234-4abc-8def-1234567890ab"
    TEAM = "ABCDEFGHIJ"

    def make_candidate(self, root: Path) -> Path:
        candidate = root / "candidate"
        inspection_dir = candidate / "inspection"
        evidence = inspection_dir / "build-evidence"
        logs = candidate / "logs"
        evidence.mkdir(parents=True)
        logs.mkdir()

        ipa = evidence / "NembraField.ipa"
        ipa.write_bytes(b"exact retained ipa bytes")
        ipa_sha = hashlib.sha256(ipa.read_bytes()).hexdigest()
        executable_sha = hashlib.sha256(b"executable").hexdigest()
        plist_sha = hashlib.sha256(b"plist").hexdigest()

        external = {
            "schemaVersion": 3,
            "buildIdentifier": self.BUILD,
            "buildInstanceID": self.INSTANCE,
            "sourceCommitSHA": self.SOURCE,
            "executableSHA256": executable_sha,
            "infoPlistSHA256": plist_sha,
            "experimentRecipeID": MODULE.RECIPE_ID,
            "procedureVersion": MODULE.PROCEDURE_VERSION,
        }
        external_bytes = canonical_bytes(external)
        external_sha = hashlib.sha256(external_bytes).hexdigest()
        (inspection_dir / "NembraCaptureExternalBuildRecord.json").write_bytes(external_bytes)

        field = {
            "schemaVersion": 1,
            "externalBuildRecordSHA256": external_sha,
            "signedInstallableSHA256": ipa_sha,
            "signedInstallableKind": "ipa",
            **{
                key: external[key]
                for key in (
                    "buildIdentifier",
                    "buildInstanceID",
                    "sourceCommitSHA",
                    "executableSHA256",
                    "infoPlistSHA256",
                    "experimentRecipeID",
                    "procedureVersion",
                )
            },
        }
        field_bytes = canonical_bytes(field)
        field_sha = hashlib.sha256(field_bytes).hexdigest()
        (inspection_dir / "NembraCaptureFieldBuildEvidenceRecord.json").write_bytes(field_bytes)

        inspection = {
            "schemaVersion": 2,
            "authority": MODULE.INSPECTION_AUTHORITY,
            "fieldBuildEvidenceRecordSHA256": field_sha,
            "externalBuildRecordSHA256": external_sha,
            "signedInstallableSHA256": ipa_sha,
            "signedInstallableKind": "ipa",
            "ipaByteCount": len(ipa.read_bytes()),
            "buildIdentifier": self.BUILD,
            "buildInstanceID": self.INSTANCE,
            "sourceCommitSHA": self.SOURCE,
            "bundleIdentifier": MODULE.BUNDLE_ID,
            "platformName": "iphoneos",
            "supportedPlatforms": ["iPhoneOS"],
            "teamIdentifier": self.TEAM,
            "signingAuthorities": ["Apple Development: Example"],
            "codeDirectoryHash": "b" * 40,
            "provisioningProfileSHA256": "c" * 64,
            "provisioningProfileUUID": "PROFILE-UUID",
            "provisioningProfileExpirationUTC": "2099-01-01T00:00:00Z",
            "provisioningApplicationIdentifier": f"{self.TEAM}.{MODULE.BUNDLE_ID}",
            "executableSHA256": executable_sha,
            "infoPlistSHA256": plist_sha,
            "experimentRecipeID": MODULE.RECIPE_ID,
            "procedureVersion": MODULE.PROCEDURE_VERSION,
        }
        (inspection_dir / "NembraCaptureSignedFieldArtifactInspection.json").write_bytes(
            canonical_bytes(inspection)
        )

        export = candidate / "ExportOptions.plist"
        export.write_bytes(b"<plist>exact export policy</plist>")
        export_sha = hashlib.sha256(export.read_bytes()).hexdigest()
        (logs / "xcodebuild-archive.log").write_text("archive succeeded\n", encoding="utf-8")
        (logs / "xcodebuild-export.log").write_text("export succeeded\n", encoding="utf-8")
        environment = "\n".join(
            [
                f"source_commit_sha={self.SOURCE}",
                f"build_identifier={self.BUILD}",
                f"build_instance_id={self.INSTANCE}",
                f"development_team={self.TEAM}",
                "allow_provisioning_updates=0",
                f"field_launch_recipe_id={MODULE.RECIPE_ID}",
                f"experiment_recipe_id={MODULE.RECIPE_ID}",
                "export_options_file=ExportOptions.plist",
                f"export_options_sha256={export_sha}",
                "archive_log=logs/xcodebuild-archive.log",
                "export_log=logs/xcodebuild-export.log",
                "inspection_directory=inspection",
                "procedure_version=V14",
                f"signing_inspection_authority={MODULE.INSPECTION_AUTHORITY}",
                "physical_authorization=not-granted",
                "Xcode 27.0",
            ]
        ) + "\n"
        (candidate / "field-candidate-environment.txt").write_text(environment, encoding="utf-8")
        return candidate

    def test_valid_candidate_crosschecks_without_granting_go(self):
        with tempfile.TemporaryDirectory() as temporary:
            candidate = self.make_candidate(Path(temporary))
            receipt = MODULE.crosscheck(
                candidate,
                expected_source_sha=self.SOURCE,
                now=datetime(2026, 8, 8, tzinfo=timezone.utc),
            )
            self.assertEqual(receipt["status"], "PASS_NOT_FINAL_GO")
            self.assertEqual(receipt["physicalExperimentAuthorization"], "not-granted")
            self.assertTrue(receipt["crossRecordDigestLinksVerified"])
            self.assertTrue(receipt["singleRetainedIPA"])

    def test_tampered_retained_ipa_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            candidate = self.make_candidate(Path(temporary))
            (candidate / "inspection" / "build-evidence" / "NembraField.ipa").write_bytes(
                b"tampered retained ipa"
            )
            with self.assertRaisesRegex(MODULE.CrosscheckError, "retained IPA bytes"):
                MODULE.crosscheck(candidate, expected_source_sha=self.SOURCE)

    def test_second_ipa_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            candidate = self.make_candidate(Path(temporary))
            (candidate / "other.ipa").write_bytes(b"ambiguous second installable")
            with self.assertRaisesRegex(MODULE.CrosscheckError, "exactly one IPA"):
                MODULE.crosscheck(candidate, expected_source_sha=self.SOURCE)

    def test_source_mismatch_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            candidate = self.make_candidate(Path(temporary))
            with self.assertRaisesRegex(MODULE.CrosscheckError, "sourceCommitSHA"):
                MODULE.crosscheck(candidate, expected_source_sha="d" * 40)

    def test_producer_authorization_must_stay_not_granted(self):
        with tempfile.TemporaryDirectory() as temporary:
            candidate = self.make_candidate(Path(temporary))
            environment = candidate / "field-candidate-environment.txt"
            environment.write_text(
                environment.read_text(encoding="utf-8").replace(
                    "physical_authorization=not-granted",
                    "physical_authorization=granted",
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(MODULE.CrosscheckError, "physical_authorization"):
                MODULE.crosscheck(candidate, expected_source_sha=self.SOURCE)


if __name__ == "__main__":
    unittest.main()

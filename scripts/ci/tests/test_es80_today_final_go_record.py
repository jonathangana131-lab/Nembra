#!/usr/bin/env python3
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_record.py"
spec = importlib.util.spec_from_file_location("final_go", MODULE_PATH)
final_go = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(final_go)


class FinalGoRecordTests(unittest.TestCase):
    SOURCE = "a" * 40
    BUILD = "Capture Build V14-" + SOURCE[:12]
    INSTANCE = "11111111-2222-3333-4444-555555555555"
    EXEC = "b" * 64
    PLIST = "c" * 64
    TEAM = "ABCDE12345"
    RUN_ID = 31292505064
    JOB_ID = 93191996583

    def make_candidate(self, root: Path):
        inspection = root / "inspection"
        evidence = inspection / "build-evidence"
        evidence.mkdir(parents=True)
        ipa = b"exact-retained-ipa"
        (evidence / "NembraField.ipa").write_bytes(ipa)
        ipa_sha = hashlib.sha256(ipa).hexdigest()
        external = {
            "schemaVersion": 3,
            "buildIdentifier": self.BUILD,
            "buildInstanceID": self.INSTANCE,
            "sourceCommitSHA": self.SOURCE,
            "executableSHA256": self.EXEC,
            "infoPlistSHA256": self.PLIST,
            "experimentRecipeID": final_go.RECIPE,
            "procedureVersion": final_go.PROCEDURE,
        }
        external_raw = (json.dumps(external, sort_keys=True) + "\n").encode()
        (inspection / final_go.EXTERNAL_RECORD_NAME).write_bytes(external_raw)
        external_sha = hashlib.sha256(external_raw).hexdigest()
        field = {
            "schemaVersion": 1,
            "externalBuildRecordSHA256": external_sha,
            "signedInstallableSHA256": ipa_sha,
            "signedInstallableKind": "ipa",
            "buildIdentifier": self.BUILD,
            "buildInstanceID": self.INSTANCE,
            "sourceCommitSHA": self.SOURCE,
            "executableSHA256": self.EXEC,
            "infoPlistSHA256": self.PLIST,
            "experimentRecipeID": final_go.RECIPE,
            "procedureVersion": final_go.PROCEDURE,
        }
        field_raw = (json.dumps(field, sort_keys=True) + "\n").encode()
        (inspection / final_go.FIELD_RECORD_NAME).write_bytes(field_raw)
        field_sha = hashlib.sha256(field_raw).hexdigest()
        signed = {
            "schemaVersion": 2,
            "authority": "signed-field-artifact-inspection-not-field-authorization",
            "fieldBuildEvidenceRecordSHA256": field_sha,
            "externalBuildRecordSHA256": external_sha,
            "signedInstallableSHA256": ipa_sha,
            "signedInstallableKind": "ipa",
            "ipaByteCount": len(ipa),
            "buildIdentifier": self.BUILD,
            "buildInstanceID": self.INSTANCE,
            "sourceCommitSHA": self.SOURCE,
            "executableSHA256": self.EXEC,
            "infoPlistSHA256": self.PLIST,
            "experimentRecipeID": final_go.RECIPE,
            "procedureVersion": final_go.PROCEDURE,
            "bundleIdentifier": final_go.BUNDLE_ID,
            "platformName": "iphoneos",
            "supportedPlatforms": ["iPhoneOS"],
            "teamIdentifier": self.TEAM,
            "provisioningApplicationIdentifier": f"{self.TEAM}.{final_go.BUNDLE_ID}",
            "provisioningProfileSHA256": "e" * 64,
            "provisioningProfileUUID": "PROFILE-UUID",
            "provisioningProfileExpirationUTC": "2099-08-09T00:00:00Z",
            "signingAuthorities": ["Apple Development: Nembra"],
            "codeDirectoryHash": "f" * 40,
        }
        inspection_path = inspection / final_go.INSPECTION_NAME
        inspection_path.write_text(json.dumps(signed), encoding="utf-8")
        xcode_artifact = root / "nembra-xcode27-pr-exact-head.zip"
        xcode_record = {
            "schemaVersion": 3,
            "buildIdentifier": self.BUILD,
            "buildInstanceID": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            "sourceCommitSHA": self.SOURCE,
            "executableSHA256": "1" * 64,
            "infoPlistSHA256": "2" * 64,
            "experimentRecipeID": final_go.RECIPE,
            "procedureVersion": final_go.PROCEDURE,
        }
        xcode_record_raw = (json.dumps(xcode_record, sort_keys=True) + "\n").encode()
        with zipfile.ZipFile(xcode_artifact, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr(final_go.EXTERNAL_RECORD_NAME, xcode_record_raw)
            archive.writestr("screenshots/preflight.png", b"simulator screenshot")
        return ipa_sha, xcode_artifact, hashlib.sha256(inspection_path.read_bytes()).hexdigest()

    def kwargs(self, root: Path, ipa_sha: str, xcode_artifact: Path):
        return dict(
            candidate_root=root,
            expected_source_sha=self.SOURCE,
            trusted_xcode_run_id=self.RUN_ID,
            trusted_xcode_job_id=self.JOB_ID,
            trusted_xcode_artifact=xcode_artifact,
            pre_install_ipa_sha256=ipa_sha,
            post_install_ipa_sha256=ipa_sha,
            installation_route=final_go.INSTALL_ROUTE,
            expected_development_team=self.TEAM,
            visible_recipe=final_go.RECIPE,
            visible_build_identifier=self.BUILD,
            visible_source_sha=self.SOURCE,
            visible_build_instance_id=self.INSTANCE,
            installed_without_rebuild=True,
            terminal_software_acceptance=True,
            retained_app_evidence_inspected=True,
            intended_device_membership_accepted=True,
            no_application_write_authority=True,
            observed_device=final_go.BASELINE_DEVICE,
            observed_os=final_go.BASELINE_OS,
            research_admission_live=True,
            canonical_coordinator_permitted=True,
            preflight_healthy=True,
            charger_disconnected=True,
            stationary=True,
        )

    def test_emits_go_with_exact_acceptance_inspection_and_install_subjects(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, xcode_artifact, inspection_sha = self.make_candidate(root)
            record = final_go.build_final_go_record(**self.kwargs(root, ipa_sha, xcode_artifact))
            self.assertEqual(record["schemaVersion"], 2)
            self.assertEqual(record["decision"], "GO")
            self.assertEqual(record["acceptedSourceCommitSHA"], self.SOURCE)
            self.assertEqual(record["retainedIPASHA256"], ipa_sha)
            self.assertEqual(record["trustedXcodeAcceptanceSubject"]["runID"], self.RUN_ID)
            self.assertEqual(record["trustedXcodeAcceptanceSubject"]["jobID"], self.JOB_ID)
            self.assertEqual(
                record["trustedXcodeAcceptanceSubject"]["retainedArtifactSHA256"],
                hashlib.sha256(xcode_artifact.read_bytes()).hexdigest(),
            )
            with zipfile.ZipFile(xcode_artifact, "r") as archive:
                xcode_record_raw = archive.read(final_go.EXTERNAL_RECORD_NAME)
            self.assertEqual(
                record["trustedXcodeAcceptanceSubject"]["retainedExternalBuildRecordSHA256"],
                hashlib.sha256(xcode_record_raw).hexdigest(),
            )
            self.assertEqual(record["signedArtifactInspectionRecordSHA256"], inspection_sha)
            self.assertEqual(
                record["retainedIPAInstallHandoff"]["preInstallRetainedIPASHA256"],
                ipa_sha,
            )
            self.assertEqual(
                record["retainedIPAInstallHandoff"]["postInstallRetainedIPASHA256"],
                ipa_sha,
            )
            self.assertEqual(
                record["retainedIPAInstallHandoff"]["installationRoute"],
                final_go.INSTALL_ROUTE,
            )
            self.assertFalse(record["physicalResultCollected"])

    def test_true_declarations_cannot_replace_missing_xcode_artifact_subject(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, xcode_artifact, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha, xcode_artifact)
            values["trusted_xcode_artifact"] = root / "missing-xcode-artifact.zip"
            with self.assertRaisesRegex(final_go.FinalGoError, "trusted Xcode retained artifact"):
                final_go.build_final_go_record(**values)

    def test_rejects_non_zip_xcode_artifact_subject(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, xcode_artifact, _ = self.make_candidate(root)
            xcode_artifact.write_bytes(b"not a zip")
            with self.assertRaisesRegex(final_go.FinalGoError, "readable ZIP"):
                final_go.build_final_go_record(**self.kwargs(root, ipa_sha, xcode_artifact))

    def test_rejects_xcode_artifact_for_different_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, xcode_artifact, _ = self.make_candidate(root)
            with zipfile.ZipFile(xcode_artifact, "r") as archive:
                record = json.loads(archive.read(final_go.EXTERNAL_RECORD_NAME))
            record["sourceCommitSHA"] = "9" * 40
            record["buildIdentifier"] = "Capture Build V14-" + ("9" * 12)
            replacement = root / "wrong-source.zip"
            with zipfile.ZipFile(replacement, "w") as archive:
                archive.writestr(final_go.EXTERNAL_RECORD_NAME, json.dumps(record))
            values = self.kwargs(root, ipa_sha, replacement)
            with self.assertRaisesRegex(final_go.FinalGoError, "trusted Xcode accepted source SHA mismatch"):
                final_go.build_final_go_record(**values)

    def test_rejects_extra_field_in_closed_world_candidate_record(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, xcode_artifact, _ = self.make_candidate(root)
            path = root / "inspection" / final_go.EXTERNAL_RECORD_NAME
            record = json.loads(path.read_text())
            record["unexpectedAuthority"] = "GO"
            path.write_text(json.dumps(record), encoding="utf-8")
            with self.assertRaisesRegex(final_go.FinalGoError, "exact closed-world schema"):
                final_go.build_final_go_record(**self.kwargs(root, ipa_sha, xcode_artifact))

    def test_rejects_duplicate_json_keys_in_candidate_record(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, xcode_artifact, _ = self.make_candidate(root)
            path = root / "inspection" / final_go.EXTERNAL_RECORD_NAME
            original = json.loads(path.read_text())
            raw = json.dumps(original)
            raw = raw[:-1] + ', "schemaVersion": 3}'
            path.write_text(raw, encoding="utf-8")
            with self.assertRaisesRegex(final_go.FinalGoError, "duplicate JSON key"):
                final_go.build_final_go_record(**self.kwargs(root, ipa_sha, xcode_artifact))

    def test_rejects_nonpositive_xcode_run_or_job_subject(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, xcode_artifact, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha, xcode_artifact)
            values["trusted_xcode_run_id"] = 0
            with self.assertRaisesRegex(final_go.FinalGoError, "trusted Xcode run ID"):
                final_go.build_final_go_record(**values)
            values = self.kwargs(root, ipa_sha, xcode_artifact)
            values["trusted_xcode_job_id"] = -1
            with self.assertRaisesRegex(final_go.FinalGoError, "trusted Xcode job ID"):
                final_go.build_final_go_record(**values)

    def test_rejects_pre_install_ipa_substitution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, xcode_artifact, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha, xcode_artifact)
            values["pre_install_ipa_sha256"] = "d" * 64
            with self.assertRaisesRegex(final_go.FinalGoError, "pre-install retained IPA digest mismatch"):
                final_go.build_final_go_record(**values)

    def test_rejects_post_install_ipa_substitution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, xcode_artifact, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha, xcode_artifact)
            values["post_install_ipa_sha256"] = "d" * 64
            with self.assertRaisesRegex(final_go.FinalGoError, "post-install retained IPA digest mismatch"):
                final_go.build_final_go_record(**values)

    def test_rejects_unaccepted_installation_route(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, xcode_artifact, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha, xcode_artifact)
            values["installation_route"] = "rebuilt-from-xcode"
            with self.assertRaisesRegex(final_go.FinalGoError, "installation route mismatch"):
                final_go.build_final_go_record(**values)

    def test_rejects_visible_build_instance_substitution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, xcode_artifact, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha, xcode_artifact)
            values["visible_build_instance_id"] = "99999999-2222-3333-4444-555555555555"
            with self.assertRaisesRegex(final_go.FinalGoError, "visible pre-scan build-instance ID mismatch"):
                final_go.build_final_go_record(**values)

    def test_rejects_false_preflight_declaration(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, xcode_artifact, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha, xcode_artifact)
            values["charger_disconnected"] = False
            with self.assertRaisesRegex(final_go.FinalGoError, "chargerFreshlyDeclaredDisconnected"):
                final_go.build_final_go_record(**values)

    def test_rejects_mutated_external_record_after_field_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, xcode_artifact, _ = self.make_candidate(root)
            path = root / "inspection" / final_go.EXTERNAL_RECORD_NAME
            external = json.loads(path.read_text())
            external["schemaVersion"] = 4
            path.write_text(json.dumps(external), encoding="utf-8")
            with self.assertRaisesRegex(final_go.FinalGoError, "external schema version mismatch"):
                final_go.build_final_go_record(**self.kwargs(root, ipa_sha, xcode_artifact))

    def test_rejects_missing_terminal_software_acceptance_declaration(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, xcode_artifact, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha, xcode_artifact)
            values["terminal_software_acceptance"] = False
            with self.assertRaisesRegex(
                final_go.FinalGoError,
                "terminalSoftwareAcceptanceForRecordedXcodeSubject",
            ):
                final_go.build_final_go_record(**values)

    def test_rejects_wrong_baseline_device(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, xcode_artifact, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha, xcode_artifact)
            values["observed_device"] = "iPhone 13"
            with self.assertRaisesRegex(final_go.FinalGoError, "observed baseline device mismatch"):
                final_go.build_final_go_record(**values)

    def test_rejects_profile_expired_before_final_go(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, xcode_artifact, _ = self.make_candidate(root)
            path = root / "inspection" / final_go.INSPECTION_NAME
            inspection = json.loads(path.read_text())
            inspection["provisioningProfileExpirationUTC"] = "2020-01-01T00:00:00Z"
            path.write_text(json.dumps(inspection), encoding="utf-8")
            with self.assertRaisesRegex(final_go.FinalGoError, "provisioning profile expired before Final GO"):
                final_go.build_final_go_record(**self.kwargs(root, ipa_sha, xcode_artifact))


if __name__ == "__main__":
    unittest.main()

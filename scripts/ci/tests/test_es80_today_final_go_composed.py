#!/usr/bin/env python3
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import zipfile

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_composed.py"
spec = importlib.util.spec_from_file_location("composed_final_go", MODULE_PATH)
final_go = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(final_go)


class ComposedFinalGoTests(unittest.TestCase):
    SOURCE = "a" * 40
    BUILD = "Capture Build V14-" + SOURCE[:12]
    INSTANCE = "11111111-2222-3333-4444-555555555555"
    EXEC = "b" * 64
    PLIST = "c" * 64
    TEAM = "ABCDE12345"
    RUN_ID = 123456
    JOB_ID = 654321
    ARTIFACT_ID = 777777

    def make_candidate(self, root: Path) -> str:
        inspection = root / "candidate" / "inspection"
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
            "bundleIdentifier": final_go.BUNDLE_ID,
            "platformName": "iphoneos",
            "supportedPlatforms": ["iPhoneOS"],
            "teamIdentifier": self.TEAM,
            "signingAuthorities": ["Apple Development: Nembra"],
            "codeDirectoryHash": "f" * 40,
            "provisioningProfileSHA256": "e" * 64,
            "provisioningProfileUUID": "PROFILE-UUID",
            "provisioningProfileExpirationUTC": "2099-08-09T00:00:00Z",
            "provisioningApplicationIdentifier": f"{self.TEAM}.{final_go.BUNDLE_ID}",
            "executableSHA256": self.EXEC,
            "infoPlistSHA256": self.PLIST,
            "experimentRecipeID": final_go.RECIPE,
            "procedureVersion": final_go.PROCEDURE,
        }
        (inspection / final_go.INSPECTION_NAME).write_text(
            json.dumps(signed, sort_keys=True) + "\n", encoding="utf-8"
        )
        return ipa_sha

    def make_trusted(self, root: Path, source: str | None = None) -> tuple[Path, Path, Path]:
        source = source or self.SOURCE
        trusted = root / "trusted"
        trusted.mkdir(parents=True, exist_ok=True)
        archive = trusted / "accepted-simulator-evidence.zip"
        xcode_record = {
            "schemaVersion": 3,
            "buildIdentifier": "Capture Build V14-" + source[:12],
            "buildInstanceID": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            "sourceCommitSHA": source,
            "executableSHA256": "1" * 64,
            "infoPlistSHA256": "2" * 64,
            "experimentRecipeID": final_go.RECIPE,
            "procedureVersion": final_go.PROCEDURE,
        }
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as zip_file:
            zip_file.writestr(
                final_go.EXTERNAL_RECORD_NAME,
                json.dumps(xcode_record, sort_keys=True) + "\n",
            )
            zip_file.writestr("screenshots/preflight.png", b"simulator screenshot")
        archive_bytes = archive.read_bytes()
        archive_sha = hashlib.sha256(archive_bytes).hexdigest()

        job = {
            "id": self.JOB_ID,
            "run_id": self.RUN_ID,
            "run_attempt": 1,
            "workflow_name": final_go.TRUSTED_WORKFLOW_NAME,
            "name": final_go.TRUSTED_JOB_NAME,
            "head_sha": self.SOURCE,
            "status": "completed",
            "conclusion": "success",
            "run_url": f"https://api.github.com/repos/jonathangana131-lab/Nembra/actions/runs/{self.RUN_ID}",
            "url": f"https://api.github.com/repos/jonathangana131-lab/Nembra/actions/jobs/{self.JOB_ID}",
        }
        job_path = trusted / "trusted-job.json"
        job_path.write_text(json.dumps(job), encoding="utf-8")

        artifact = {
            "id": self.ARTIFACT_ID,
            "name": "nembra-capture-xcode27-833-123-1",
            "size_in_bytes": len(archive_bytes),
            "expired": False,
            "digest": f"sha256:{archive_sha}",
            "archive_download_url": (
                "https://api.github.com/repos/jonathangana131-lab/Nembra/actions/artifacts/"
                f"{self.ARTIFACT_ID}/zip"
            ),
            "workflow_run": {"id": self.RUN_ID, "head_sha": self.SOURCE},
        }
        artifact_path = trusted / "artifact-metadata.json"
        artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
        return job_path, artifact_path, archive

    def kwargs(self, root: Path, ipa_sha: str):
        job, artifact, archive = self.make_trusted(root)
        return dict(
            candidate_root=root / "candidate",
            expected_source_sha=self.SOURCE,
            expected_development_team=self.TEAM,
            trusted_xcode_job_record=job,
            trusted_xcode_artifact_metadata=artifact,
            trusted_xcode_artifact_archive=archive,
            pre_install_ipa_sha256=ipa_sha,
            post_install_ipa_sha256=ipa_sha,
            installation_route=final_go.INSTALL_ROUTE,
            visible_recipe=final_go.RECIPE,
            visible_build_identifier=self.BUILD,
            visible_source_sha=self.SOURCE,
            visible_build_instance_id=self.INSTANCE,
            installed_without_rebuild=True,
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

    def test_both_validators_must_accept_same_exact_subjects(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha = self.make_candidate(root)
            record = final_go.build_final_go_record(**self.kwargs(root, ipa_sha))
            self.assertEqual(record["decision"], "GO")
            self.assertTrue(record["compositionVerification"]["exactGitHubJobAndArtifactSubjectAccepted"])
            self.assertTrue(record["compositionVerification"]["closedWorldCandidateSchemasAccepted"])
            self.assertTrue(record["compositionVerification"]["retainedXcodeArchiveSourceTupleAccepted"])
            self.assertEqual(record["trustedXcodeAcceptance"]["runID"], self.RUN_ID)
            self.assertIn("retainedExternalBuildRecordSHA256", record["trustedXcodeAcceptance"])
            self.assertIn("signedFieldInspectionSubject", record)
            self.assertFalse(record["physicalResultCollected"])

    def test_exact_metadata_digest_cannot_hide_wrong_source_inside_archive(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            _, artifact_path, wrong_archive = self.make_trusted(root, source="9" * 40)
            artifact = json.loads(artifact_path.read_text())
            archive_bytes = wrong_archive.read_bytes()
            artifact["digest"] = "sha256:" + hashlib.sha256(archive_bytes).hexdigest()
            artifact["size_in_bytes"] = len(archive_bytes)
            artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
            values["trusted_xcode_artifact_metadata"] = artifact_path
            values["trusted_xcode_artifact_archive"] = wrong_archive
            with self.assertRaisesRegex(final_go.FinalGoError, "trusted Xcode accepted source SHA mismatch"):
                final_go.build_final_go_record(**values)

    def test_foundation_rejects_duplicate_candidate_json_keys(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            path = root / "candidate" / "inspection" / final_go.EXTERNAL_RECORD_NAME
            original = json.loads(path.read_text())
            raw = json.dumps(original)[:-1] + ', "schemaVersion": 3}'
            path.write_text(raw, encoding="utf-8")
            with self.assertRaisesRegex(final_go.FinalGoError, "duplicate JSON key"):
                final_go.build_final_go_record(**values)

    def test_foundation_rejects_extra_closed_world_candidate_field(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            path = root / "candidate" / "inspection" / final_go.EXTERNAL_RECORD_NAME
            record = json.loads(path.read_text())
            record["callerAuthority"] = "GO"
            path.write_text(json.dumps(record), encoding="utf-8")
            with self.assertRaisesRegex(final_go.FinalGoError, "exact closed-world schema"):
                final_go.build_final_go_record(**values)

    def test_directory_fsync_failure_after_rename_retracts_go_destination(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "FinalGO.json"
            raw = b'{"decision":"GO"}\n'
            real_fsync = final_go.os.fsync
            calls = 0

            def fail_second_fsync(fd: int):
                nonlocal calls
                calls += 1
                if calls == 2:
                    raise OSError("simulated parent-directory fsync failure after rename")
                return real_fsync(fd)

            with mock.patch.object(final_go.os, "fsync", side_effect=fail_second_fsync):
                with self.assertRaisesRegex(OSError, "simulated parent-directory fsync failure"):
                    final_go.publish_record_no_replace(output, raw)
            self.assertFalse(output.exists() or output.is_symlink())
            self.assertEqual(list(root.glob(".FinalGO.json.*.staging")), [])

    def test_post_publish_byte_verification_failure_retracts_go_destination(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "FinalGO.json"
            raw = b'{"decision":"GO"}\n'
            real_regular = final_go.exact._regular
            calls = 0

            def changed_once(path: Path, label: str):
                nonlocal calls
                calls += 1
                value = real_regular(path, label)
                if calls == 2 and label == "published Final GO record":
                    return value + b"substitution"
                return value

            with mock.patch.object(final_go.exact, "_regular", side_effect=changed_once):
                with self.assertRaisesRegex(final_go.FinalGoError, "published Final GO record bytes differ"):
                    final_go.publish_record_no_replace(output, raw)
            self.assertFalse(output.exists() or output.is_symlink())

    def test_pre_publish_failure_leaves_no_authoritative_path_or_staging(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "FinalGO.json"
            raw = b'{"decision":"GO"}\n'

            def fail_before_publish(staging: Path, destination: Path):
                raise OSError("simulated pre-publication failure")

            with self.assertRaisesRegex(OSError, "simulated pre-publication failure"):
                final_go.publish_record_no_replace(output, raw, publisher=fail_before_publish)
            self.assertFalse(output.exists() or output.is_symlink())
            self.assertEqual(list(root.glob(".FinalGO.json.*.staging")), [])


if __name__ == "__main__":
    unittest.main()

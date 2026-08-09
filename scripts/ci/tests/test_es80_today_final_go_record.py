#!/usr/bin/env python3
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

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
    RUN_ID = 123456
    JOB_ID = 654321
    ARTIFACT_ID = 777777

    def make_candidate(self, root: Path) -> tuple[str, str]:
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
            "provisioningProfileExpirationUTC": "2030-08-09T00:00:00Z",
            "signingAuthorities": ["Apple Development: Nembra"],
        }
        inspection_raw = (json.dumps(signed, sort_keys=True) + "\n").encode()
        (inspection / final_go.INSPECTION_NAME).write_bytes(inspection_raw)
        return ipa_sha, hashlib.sha256(inspection_raw).hexdigest()

    def make_trusted(self, root: Path) -> tuple[Path, Path, Path]:
        trusted = root / "trusted"
        trusted.mkdir(parents=True)
        archive = trusted / "accepted-simulator-evidence.zip"
        archive_bytes = b"exact-trusted-xcode-artifact-archive"
        archive.write_bytes(archive_bytes)
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
            "workflow_run": {
                "id": self.RUN_ID,
                "head_sha": self.SOURCE,
            },
        }
        artifact_path = trusted / "artifact-metadata.json"
        artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
        return job_path, artifact_path, archive

    def kwargs(self, root: Path, ipa_sha: str):
        job_path, artifact_path, archive_path = self.make_trusted(root)
        return dict(
            candidate_root=root / "candidate",
            expected_source_sha=self.SOURCE,
            expected_development_team=self.TEAM,
            trusted_xcode_job_record=job_path,
            trusted_xcode_artifact_metadata=artifact_path,
            trusted_xcode_artifact_archive=archive_path,
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

    def test_emits_go_only_for_bound_acceptance_candidate_install_and_runtime_subjects(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, inspection_sha = self.make_candidate(root)
            record = final_go.build_final_go_record(**self.kwargs(root, ipa_sha))
            self.assertEqual(record["decision"], "GO")
            self.assertEqual(record["acceptedSourceCommitSHA"], self.SOURCE)
            self.assertEqual(record["retainedIPASHA256"], ipa_sha)
            self.assertEqual(record["signedArtifactInspectionSHA256"], inspection_sha)
            self.assertEqual(record["trustedXcodeAcceptance"]["runID"], self.RUN_ID)
            self.assertEqual(record["trustedXcodeAcceptance"]["jobID"], self.JOB_ID)
            self.assertEqual(record["installationHandoff"]["preInstallRetainedIPASHA256"], ipa_sha)
            self.assertEqual(record["installationHandoff"]["postInstallRetainedIPASHA256"], ipa_sha)
            self.assertEqual(record["installationHandoff"]["route"], final_go.INSTALL_ROUTE)
            self.assertEqual(record["schemaVersion"], 2)
            self.assertFalse(record["physicalResultCollected"])

    def test_rejects_trusted_xcode_boolean_substitute_without_job_subject(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            values["trusted_xcode_job_record"] = root / "missing-trusted-job.json"
            with self.assertRaisesRegex(final_go.FinalGoError, "trusted Xcode job record is unavailable"):
                final_go.build_final_go_record(**values)

    def test_rejects_non_success_trusted_xcode_job(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            job_path = values["trusted_xcode_job_record"]
            job = json.loads(job_path.read_text())
            job["conclusion"] = "failure"
            job_path.write_text(json.dumps(job), encoding="utf-8")
            with self.assertRaisesRegex(final_go.FinalGoError, "trusted Xcode job conclusion mismatch"):
                final_go.build_final_go_record(**values)

    def test_rejects_trusted_xcode_job_from_other_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            job_path = values["trusted_xcode_job_record"]
            job = json.loads(job_path.read_text())
            job["head_sha"] = "0" * 40
            job_path.write_text(json.dumps(job), encoding="utf-8")
            with self.assertRaisesRegex(final_go.FinalGoError, "trusted Xcode job exact source SHA mismatch"):
                final_go.build_final_go_record(**values)

    def test_rejects_artifact_metadata_detached_from_run(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            artifact_path = values["trusted_xcode_artifact_metadata"]
            artifact = json.loads(artifact_path.read_text())
            artifact["workflow_run"]["id"] = self.RUN_ID + 1
            artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
            with self.assertRaisesRegex(final_go.FinalGoError, "trusted Xcode artifact run ID mismatch"):
                final_go.build_final_go_record(**values)

    def test_rejects_downloaded_acceptance_artifact_substitution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            values["trusted_xcode_artifact_archive"].write_bytes(b"substituted-archive")
            with self.assertRaisesRegex(final_go.FinalGoError, "downloaded artifact archive digest mismatch"):
                final_go.build_final_go_record(**values)

    def test_rejects_pre_install_ipa_substitution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            values["pre_install_ipa_sha256"] = "d" * 64
            with self.assertRaisesRegex(final_go.FinalGoError, "pre-install retained IPA digest mismatch"):
                final_go.build_final_go_record(**values)

    def test_rejects_post_install_ipa_substitution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            values["post_install_ipa_sha256"] = "d" * 64
            with self.assertRaisesRegex(final_go.FinalGoError, "post-install retained IPA digest mismatch"):
                final_go.build_final_go_record(**values)

    def test_rejects_noncanonical_install_route(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            values["installation_route"] = "xcode-run"
            with self.assertRaisesRegex(final_go.FinalGoError, "installation route mismatch"):
                final_go.build_final_go_record(**values)

    def test_rejects_visible_build_instance_substitution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            values["visible_build_instance_id"] = "99999999-2222-3333-4444-555555555555"
            with self.assertRaisesRegex(final_go.FinalGoError, "visible pre-scan build-instance ID mismatch"):
                final_go.build_final_go_record(**values)

    def test_rejects_false_operator_charger_declaration(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            values["charger_disconnected"] = False
            with self.assertRaisesRegex(final_go.FinalGoError, "chargerFreshlyDeclaredDisconnected"):
                final_go.build_final_go_record(**values)

    def test_rejects_mutated_external_record_after_field_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            path = root / "candidate" / "inspection" / final_go.EXTERNAL_RECORD_NAME
            external = json.loads(path.read_text())
            external["schemaVersion"] = 4
            path.write_text(json.dumps(external), encoding="utf-8")
            with self.assertRaisesRegex(final_go.FinalGoError, "external schema version mismatch"):
                final_go.build_final_go_record(**values)

    def test_rejects_mutated_signed_inspection_after_field_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            path = root / "candidate" / "inspection" / final_go.INSPECTION_NAME
            inspection = json.loads(path.read_text())
            inspection["teamIdentifier"] = "ZZZZZ99999"
            path.write_text(json.dumps(inspection), encoding="utf-8")
            with self.assertRaisesRegex(final_go.FinalGoError, "inspection team identifier mismatch"):
                final_go.build_final_go_record(**values)

    def test_rejects_wrong_baseline_device(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            values["observed_device"] = "iPhone 13"
            with self.assertRaisesRegex(final_go.FinalGoError, "observed baseline device mismatch"):
                final_go.build_final_go_record(**values)

    def test_rejects_profile_expired_before_final_go(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ipa_sha, _ = self.make_candidate(root)
            values = self.kwargs(root, ipa_sha)
            path = root / "candidate" / "inspection" / final_go.INSPECTION_NAME
            inspection = json.loads(path.read_text())
            inspection["provisioningProfileExpirationUTC"] = "2020-01-01T00:00:00Z"
            path.write_text(json.dumps(inspection), encoding="utf-8")
            with self.assertRaisesRegex(final_go.FinalGoError, "provisioning profile expired before Final GO"):
                final_go.build_final_go_record(**values)

    def test_publication_failure_leaves_final_absent_and_retry_can_succeed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "FinalGO.json"
            raw = b'{"decision":"GO"}\n'

            def fail_before_publish(staging: Path, destination: Path) -> None:
                raise OSError("simulated publication failure")

            with self.assertRaisesRegex(OSError, "simulated publication failure"):
                final_go.publish_record_no_replace(output, raw, publisher=fail_before_publish)
            self.assertFalse(output.exists())
            self.assertEqual(list(root.glob(".FinalGO.json.*.staging")), [])

            digest = final_go.publish_record_no_replace(output, raw)
            self.assertEqual(output.read_bytes(), raw)
            self.assertEqual(digest, hashlib.sha256(raw).hexdigest())

    def test_preexisting_final_output_is_never_replaced(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "FinalGO.json"
            original = b"already-authoritative\n"
            output.write_bytes(original)
            with self.assertRaisesRegex(final_go.FinalGoError, "output already exists"):
                final_go.publish_record_no_replace(output, b"replacement\n")
            self.assertEqual(output.read_bytes(), original)

    def test_successful_publication_has_exact_bytes_hash_and_no_staging_residue(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "FinalGO.json"
            raw = b'{"authority":"today-final-go-procedural-record-not-physical-result"}\n'
            digest = final_go.publish_record_no_replace(output, raw)
            self.assertEqual(output.read_bytes(), raw)
            self.assertEqual(digest, hashlib.sha256(raw).hexdigest())
            self.assertEqual(list(root.glob(".FinalGO.json.*.staging")), [])
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()

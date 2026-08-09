#!/usr/bin/env python3
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock
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
    SIM_INSTANCE = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    EXEC = "b" * 64
    PLIST = "c" * 64
    TEAM = "ABCDE12345"
    RUN_ID = 123456
    JOB_ID = 654321
    ARTIFACT_ID = 777777
    PR = 833
    NOW = datetime(2026, 8, 9, 4, 0, tzinfo=timezone.utc)
    PRIVATE_BLOB = "1" * 40
    INSPECTOR_BLOB = "2" * 40
    TOOL_BLOB = final_go.PINNED_CROSSCHECK_BLOB

    def external(self, *, instance=None, source=None):
        source = source or self.SOURCE
        return {
            "schemaVersion": 3,
            "buildIdentifier": "Capture Build V14-" + source[:12],
            "buildInstanceID": instance or self.INSTANCE,
            "sourceCommitSHA": source,
            "executableSHA256": self.EXEC,
            "infoPlistSHA256": self.PLIST,
            "experimentRecipeID": final_go.RECIPE,
            "procedureVersion": final_go.PROCEDURE,
        }

    def write_json(self, path: Path, value: dict) -> tuple[bytes, str]:
        raw = (json.dumps(value, sort_keys=True) + "\n").encode()
        path.write_bytes(raw)
        return raw, hashlib.sha256(raw).hexdigest()

    def make_candidate(self, root: Path):
        inspection_dir = root / "candidate" / "inspection"
        evidence = inspection_dir / "build-evidence"
        evidence.mkdir(parents=True)
        ipa = b"exact-retained-ipa"
        (evidence / "NembraField.ipa").write_bytes(ipa)
        ipa_sha = hashlib.sha256(ipa).hexdigest()

        external = self.external()
        _, external_sha = self.write_json(inspection_dir / final_go.EXTERNAL_RECORD_NAME, external)
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
        _, field_sha = self.write_json(inspection_dir / final_go.FIELD_RECORD_NAME, field)
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
            "codeDirectoryHash": "d" * 40,
            "provisioningProfileSHA256": "e" * 64,
            "provisioningProfileUUID": "PROFILE-UUID",
            "provisioningProfileExpirationUTC": "2030-08-09T00:00:00Z",
            "provisioningApplicationIdentifier": f"{self.TEAM}.{final_go.BUNDLE_ID}",
            "executableSHA256": self.EXEC,
            "infoPlistSHA256": self.PLIST,
            "experimentRecipeID": final_go.RECIPE,
            "procedureVersion": final_go.PROCEDURE,
        }
        _, inspection_sha = self.write_json(inspection_dir / final_go.INSPECTION_NAME, signed)
        return {
            "ipa_sha": ipa_sha,
            "ipa_size": len(ipa),
            "external_sha": external_sha,
            "field_sha": field_sha,
            "inspection_sha": inspection_sha,
        }

    def make_xcode_archive(self, root: Path, *, source=None):
        archive_path = root / "trusted-xcode.zip"
        external = self.external(instance=self.SIM_INSTANCE, source=source)
        external_raw = (json.dumps(external, sort_keys=True) + "\n").encode()
        with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr(final_go.EXTERNAL_RECORD_NAME, external_raw)
            archive.writestr("screenshots/AccessibilityXXXL.png", b"png")
        raw = archive_path.read_bytes()
        return archive_path, hashlib.sha256(raw).hexdigest(), len(raw)

    def make_receipt(self, root: Path, candidate: dict):
        receipt = {
            "schemaVersion": 1,
            "authority": final_go.CROSSCHECK_AUTHORITY,
            "status": "PASS_NOT_FINAL_GO",
            "sourceCommitSHA": self.SOURCE,
            "buildIdentifier": self.BUILD,
            "buildInstanceID": self.INSTANCE,
            "experimentRecipeID": final_go.RECIPE,
            "procedureVersion": final_go.PROCEDURE,
            "researchCompileMode": final_go.RESEARCH_COMPILE_MODE,
            "researchCompileAuthority": final_go.RESEARCH_COMPILE_AUTHORITY,
            "researchCompileCondition": final_go.RESEARCH_COMPILE_CONDITION,
            "signedInstallableSHA256": candidate["ipa_sha"],
            "signedInstallableByteCount": candidate["ipa_size"],
            "externalBuildRecordSHA256": candidate["external_sha"],
            "fieldBuildEvidenceRecordSHA256": candidate["field_sha"],
            "signedFieldArtifactInspectionSHA256": candidate["inspection_sha"],
            "executableSHA256": self.EXEC,
            "infoPlistSHA256": self.PLIST,
            "exportOptionsSHA256": "f" * 64,
            "teamIdentifier": self.TEAM,
            "allowProvisioningUpdates": "0",
            "privateRunnerSourceGitBlobClaim": self.PRIVATE_BLOB,
            "canonicalInspectorSourceGitBlobClaim": self.INSPECTOR_BLOB,
            "xcodeVersion": "Xcode 27.0",
            "xcodeBuildVersion": "Build version 17A123",
            "provisioningProfileSHA256": "e" * 64,
            "provisioningProfileUUID": "PROFILE-UUID",
            "provisioningProfileExpirationUTC": "2030-08-09T00:00:00Z",
            "singleRetainedIPA": True,
            "crossRecordDigestLinksVerified": True,
            "researchCompileTupleVerified": True,
            "producerPhysicalAuthorizationRemainsNotGranted": True,
            "appleSigningInspectionRequired": True,
            "toolBlobClaimsRequireRepositoryCrossCheck": True,
            "exactRetainedIPAInstallHandoffRequired": True,
            "physicalExperimentAuthorization": "not-granted",
        }
        path = root / "crosscheck.json"
        self.write_json(path, receipt)
        return path

    def make_attestation(self, root: Path, candidate: dict, *, recorded=None):
        recorded = recorded or self.NOW
        attestation = {
            "schemaVersion": 1,
            "authority": final_go.OPERATOR_AUTHORITY,
            "attestationID": "12345678-1234-1234-1234-123456789abc",
            "recordedAtUTC": recorded.isoformat().replace("+00:00", "Z"),
            "simulatorArtifactReview": "INSPECTED_NO_TODAY_BLOCKER",
            "installationRoute": final_go.INSTALL_ROUTE,
            "preInstallRetainedIPASHA256": candidate["ipa_sha"],
            "postInstallRetainedIPASHA256": candidate["ipa_sha"],
            "installedWithoutRebuildOrSubstitution": True,
            "installedOnIntendedDevice": True,
            "observedDevice": final_go.BASELINE_DEVICE,
            "observedOS": final_go.BASELINE_OS,
            "runtimeVisibleSourceCommitSHA": self.SOURCE,
            "runtimeVisibleBuildIdentifier": self.BUILD,
            "runtimeVisibleBuildInstanceID": self.INSTANCE,
            "runtimeVisibleRecipe": final_go.RECIPE,
            "runtimeResearchAdmission": "OBSERVED_AVAILABLE",
            "canonicalCoordinatorPermission": "OBSERVED_PERMITTED",
            "ordinaryGeneralBuildAuthority": "OBSERVED_NO_GO",
            "preflightHealth": "OBSERVED_READY",
            "chargerState": "DISCONNECTED",
            "motionState": "STATIONARY",
            "explicitOperatorActionRequired": True,
            "noApplicationWriteAuthorityReview": "REVIEWED_NO_APPLICATION_WRITE_OR_COMMAND_PATH",
        }
        path = root / "attestation.json"
        self.write_json(path, attestation)
        return path

    def make_github(self, archive_sha: str, archive_size: int):
        run = {
            "id": self.RUN_ID,
            "name": final_go.TRUSTED_WORKFLOW_NAME,
            "path": final_go.TRUSTED_WORKFLOW_PATH,
            "event": "pull_request",
            "head_sha": self.SOURCE,
            "status": "completed",
            "conclusion": "success",
            "run_attempt": 1,
            "run_number": 42,
            "repository": {"full_name": final_go.REPOSITORY},
            "head_repository": {"full_name": final_go.REPOSITORY},
            "pull_requests": [{"number": self.PR}],
        }
        required = [
            "Reject stale PR head before scarce Mac work",
            "Verify immutable PR head",
            "Build, test, and capture Simulator states",
            "Verify retained Capture build evidence",
            "Reject head movement before acceptance completion",
        ]
        job = {
            "id": self.JOB_ID,
            "run_id": self.RUN_ID,
            "run_attempt": 1,
            "workflow_name": final_go.TRUSTED_WORKFLOW_NAME,
            "name": final_go.TRUSTED_JOB_NAME,
            "head_sha": self.SOURCE,
            "status": "completed",
            "conclusion": "success",
            "labels": ["xcode-27"],
            "run_url": f"https://api.github.com/repos/{final_go.REPOSITORY}/actions/runs/{self.RUN_ID}",
            "url": f"https://api.github.com/repos/{final_go.REPOSITORY}/actions/jobs/{self.JOB_ID}",
            "steps": [{"name": name, "conclusion": "success"} for name in required],
        }
        artifact = {
            "id": self.ARTIFACT_ID,
            "name": f"{final_go.TRUSTED_ARTIFACT_PREFIX}{self.PR}-42-1",
            "expired": False,
            "digest": f"sha256:{archive_sha}",
            "size_in_bytes": archive_size,
            "workflow_run": {"id": self.RUN_ID, "head_sha": self.SOURCE},
        }
        records = {
            f"/actions/runs/{self.RUN_ID}": run,
            f"/actions/jobs/{self.JOB_ID}": job,
            f"/actions/artifacts/{self.ARTIFACT_ID}": artifact,
        }

        def get(path: str):
            value = records[path]
            return json.dumps(value, sort_keys=True).encode(), value

        return records, get

    def git_side_effect(self, repository: Path, *args: str):
        subject = args[-1]
        if subject == f"{self.SOURCE}^{{commit}}":
            return self.SOURCE
        if subject == f"{self.SOURCE}:{final_go.PRIVATE_RUNNER_PATH}":
            return self.PRIVATE_BLOB
        if subject == f"{self.SOURCE}:{final_go.INSPECTOR_PATH}":
            return self.INSPECTOR_BLOB
        if subject == f"{final_go.PINNED_CROSSCHECK_COMMIT}^{{commit}}":
            return final_go.PINNED_CROSSCHECK_COMMIT
        if subject == f"{final_go.PINNED_CROSSCHECK_COMMIT}:{final_go.CROSSCHECK_PATH}":
            return self.TOOL_BLOB
        raise AssertionError(args)

    def setup_case(self, root: Path):
        candidate = self.make_candidate(root)
        archive, archive_sha, archive_size = self.make_xcode_archive(root)
        records, github = self.make_github(archive_sha, archive_size)
        receipt = self.make_receipt(root, candidate)
        attestation = self.make_attestation(root, candidate)
        source_repo = root / "source-repo"
        tooling_repo = root / "tooling-repo"
        source_repo.mkdir()
        tooling_repo.mkdir()
        kwargs = dict(
            candidate_root=root / "candidate",
            expected_source_sha=self.SOURCE,
            expected_pr_number=self.PR,
            trusted_xcode_run_id=self.RUN_ID,
            trusted_xcode_job_id=self.JOB_ID,
            trusted_xcode_artifact_id=self.ARTIFACT_ID,
            trusted_xcode_artifact_archive=archive,
            independent_crosscheck_receipt=receipt,
            frozen_source_repo=source_repo,
            tooling_repo=tooling_repo,
            operator_attestation=attestation,
            github_get_json=github,
            now_utc=self.NOW,
        )
        return candidate, records, kwargs

    def build(self, kwargs):
        with mock.patch.object(final_go, "_git", side_effect=self.git_side_effect):
            return final_go.build_final_go_record(**kwargs)

    def test_valid_exact_subjects_emit_go_but_no_physical_result(self):
        with tempfile.TemporaryDirectory() as temporary:
            _, _, kwargs = self.setup_case(Path(temporary))
            record = self.build(kwargs)
            self.assertEqual(record["decision"], "GO")
            self.assertFalse(record["physicalResultCollected"])
            self.assertEqual(record["trustedXcodeAcceptance"]["workflowName"], final_go.TRUSTED_WORKFLOW_NAME)
            self.assertEqual(record["independentRetainedCandidateCrosscheck"]["status"], "PASS_NOT_FINAL_GO")
            self.assertTrue(record["independentRetainedCandidateCrosscheck"]["researchCompileTupleVerified"])
            self.assertEqual(record["exactRetainedIPAInstallAndRuntimeAttestation"]["authority"], final_go.OPERATOR_AUTHORITY)
            self.assertEqual(record["ordinaryGeneralBuildAuthority"], "NO-GO")

    def test_rejects_failed_live_github_run(self):
        with tempfile.TemporaryDirectory() as temporary:
            _, records, kwargs = self.setup_case(Path(temporary))
            records[f"/actions/runs/{self.RUN_ID}"]["conclusion"] = "failure"
            with self.assertRaisesRegex(final_go.FinalGoError, "trusted Xcode run conclusion mismatch"):
                self.build(kwargs)

    def test_rejects_wrong_workflow_name(self):
        with tempfile.TemporaryDirectory() as temporary:
            _, records, kwargs = self.setup_case(Path(temporary))
            records[f"/actions/runs/{self.RUN_ID}"]["name"] = "Fake Xcode"
            with self.assertRaisesRegex(final_go.FinalGoError, "workflow name mismatch"):
                self.build(kwargs)

    def test_rejects_non_pull_request_run_subject(self):
        with tempfile.TemporaryDirectory() as temporary:
            _, records, kwargs = self.setup_case(Path(temporary))
            records[f"/actions/runs/{self.RUN_ID}"]["event"] = "issue_comment"
            with self.assertRaisesRegex(final_go.FinalGoError, "workflow event mismatch"):
                self.build(kwargs)

    def test_rejects_skipped_exact_head_completion_step(self):
        with tempfile.TemporaryDirectory() as temporary:
            _, records, kwargs = self.setup_case(Path(temporary))
            job = records[f"/actions/jobs/{self.JOB_ID}"]
            job["steps"][-1]["conclusion"] = "skipped"
            with self.assertRaisesRegex(final_go.FinalGoError, "Reject head movement before acceptance completion mismatch"):
                self.build(kwargs)

    def test_rejects_downloaded_artifact_substitution(self):
        with tempfile.TemporaryDirectory() as temporary:
            _, _, kwargs = self.setup_case(Path(temporary))
            kwargs["trusted_xcode_artifact_archive"].write_bytes(b"substituted")
            with self.assertRaisesRegex(final_go.FinalGoError, "archive digest mismatch"):
                self.build(kwargs)

    def test_rejects_xcode_artifact_detached_from_source_even_with_matching_server_digest(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _, records, kwargs = self.setup_case(root)
            archive, sha, size = self.make_xcode_archive(root, source="0" * 40)
            kwargs["trusted_xcode_artifact_archive"] = archive
            artifact = records[f"/actions/artifacts/{self.ARTIFACT_ID}"]
            artifact["digest"] = f"sha256:{sha}"
            artifact["size_in_bytes"] = size
            with self.assertRaisesRegex(final_go.FinalGoError, "embedded source SHA mismatch"):
                self.build(kwargs)

    def test_rejects_crosscheck_that_claims_physical_authority(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _, _, kwargs = self.setup_case(root)
            receipt = json.loads(kwargs["independent_crosscheck_receipt"].read_text())
            receipt["physicalExperimentAuthorization"] = "granted"
            self.write_json(kwargs["independent_crosscheck_receipt"], receipt)
            with self.assertRaisesRegex(final_go.FinalGoError, "physicalExperimentAuthorization mismatch"):
                self.build(kwargs)

    def test_rejects_crosscheck_blob_claim_not_reconciled_to_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _, _, kwargs = self.setup_case(root)
            receipt = json.loads(kwargs["independent_crosscheck_receipt"].read_text())
            receipt["privateRunnerSourceGitBlobClaim"] = "9" * 40
            self.write_json(kwargs["independent_crosscheck_receipt"], receipt)
            with self.assertRaisesRegex(final_go.FinalGoError, "private runner Git-blob claim mismatch"):
                self.build(kwargs)

    def test_rejects_duplicate_json_authority_key(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _, _, kwargs = self.setup_case(root)
            kwargs["independent_crosscheck_receipt"].write_text('{"schemaVersion":1,"schemaVersion":1}\n')
            with self.assertRaisesRegex(final_go.FinalGoError, "duplicate object key"):
                self.build(kwargs)

    def test_rejects_stale_operator_attestation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            candidate, _, kwargs = self.setup_case(root)
            kwargs["operator_attestation"] = self.make_attestation(root, candidate, recorded=self.NOW - timedelta(hours=2))
            with self.assertRaisesRegex(final_go.FinalGoError, "operator attestation is stale"):
                self.build(kwargs)

    def test_rejects_connected_charger_attestation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _, _, kwargs = self.setup_case(root)
            attestation = json.loads(kwargs["operator_attestation"].read_text())
            attestation["chargerState"] = "CONNECTED"
            self.write_json(kwargs["operator_attestation"], attestation)
            with self.assertRaisesRegex(final_go.FinalGoError, "chargerState mismatch"):
                self.build(kwargs)

    def test_rejects_general_build_authority_escalation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _, _, kwargs = self.setup_case(root)
            attestation = json.loads(kwargs["operator_attestation"].read_text())
            attestation["ordinaryGeneralBuildAuthority"] = "OBSERVED_GO"
            self.write_json(kwargs["operator_attestation"], attestation)
            with self.assertRaisesRegex(final_go.FinalGoError, "ordinaryGeneralBuildAuthority mismatch"):
                self.build(kwargs)

    def test_rejects_pre_install_retained_ipa_digest_substitution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _, _, kwargs = self.setup_case(root)
            attestation = json.loads(kwargs["operator_attestation"].read_text())
            attestation["preInstallRetainedIPASHA256"] = "9" * 64
            self.write_json(kwargs["operator_attestation"], attestation)
            with self.assertRaisesRegex(final_go.FinalGoError, "preInstallRetainedIPASHA256 mismatch"):
                self.build(kwargs)

    def test_rejects_profile_expired_before_final_go(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _, _, kwargs = self.setup_case(root)
            path = root / "candidate" / "inspection" / final_go.INSPECTION_NAME
            inspection = json.loads(path.read_text())
            inspection["provisioningProfileExpirationUTC"] = "2020-01-01T00:00:00Z"
            self.write_json(path, inspection)
            with self.assertRaisesRegex(final_go.FinalGoError, "provisioning profile expired"):
                self.build(kwargs)

    def test_publication_failure_leaves_final_absent_and_retry_can_succeed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "FinalGO.json"
            raw = b'{"decision":"GO"}\n'

            def fail(staging: Path, destination: Path):
                raise OSError("injected prepublication failure")

            with self.assertRaises(OSError):
                final_go.publish_record_no_replace(output, raw, publisher=fail)
            self.assertFalse(output.exists())
            digest = final_go.publish_record_no_replace(output, raw)
            self.assertEqual(digest, hashlib.sha256(raw).hexdigest())
            self.assertEqual(output.read_bytes(), raw)

    def test_publication_refuses_existing_final_record(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "FinalGO.json"
            output.write_bytes(b"existing")
            with self.assertRaisesRegex(final_go.FinalGoError, "output already exists"):
                final_go.publish_record_no_replace(output, b"new")


if __name__ == "__main__":
    unittest.main()

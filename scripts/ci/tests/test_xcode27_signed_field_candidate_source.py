#!/usr/bin/env python3
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidateProducerSourceTests(unittest.TestCase):
    def setUp(self):
        self.source = SCRIPT.read_text()

    def test_targets_real_ios_and_injects_exact_build_rendezvous_and_launch_recipe(self):
        self.assertIn('generic/platform=iOS', self.source)
        self.assertIn('-exportArchive', self.source)
        self.assertNotIn('CODE_SIGNING_ALLOWED=NO', self.source)
        self.assertIn('Capture Build V14-${SOURCE_SHA:0:12}', self.source)
        self.assertIn('INFOPLIST_KEY_NembraCaptureBuildIdentifier', self.source)
        self.assertIn('INFOPLIST_KEY_NembraCaptureBuildInstanceID', self.source)
        self.assertIn('INFOPLIST_KEY_NembraCaptureBuildCommitSHA', self.source)
        self.assertIn('FIELD_RECIPE_ID="ES80-FINGERPRINT-v1"', self.source)
        self.assertIn('INFOPLIST_KEY_NembraCaptureFieldRecipe=$FIELD_RECIPE_ID', self.source)
        self.assertIn('info.get("NembraCaptureFieldRecipe") != field_recipe', self.source)
        self.assertIn('raw_info_plist', self.source)
        self.assertIn('field.get("infoPlistSHA256")', self.source)

    def test_forwards_intended_device_privately_to_current_canonical_inspector(self):
        self.assertIn('NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE', self.source)
        self.assertIn('es80_signed_field_artifact_private_runner.py', self.source)
        self.assertIn('--check-private-input', self.source)
        self.assertIn(
            '--intended-device-udid-file "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"',
            self.source,
        )
        self.assertIn('es80_signed_field_artifact_evidence.py', self.source)
        self.assertNotIn('${NEMBRA_INTENDED_FIELD_DEVICE_UDID:', self.source)
        self.assertNotIn('"$NEMBRA_INTENDED_FIELD_DEVICE_UDID"', self.source)
        self.assertNotIn('--intended-device-udid "$NEMBRA_INTENDED_FIELD_DEVICE_UDID"', self.source)
        self.assertNotIn('intended_device_udid=', self.source)
        self.assertNotIn('field_device_udid=', self.source)
        self.assertNotIn('echo "$NEMBRA_INTENDED_FIELD_DEVICE_UDID"', self.source)

    def test_reuses_live_canonical_signed_field_evidence_contract(self):
        self.assertIn('es80_signed_field_artifact_evidence.py', self.source)
        self.assertIn('es80_signed_field_artifact_private_runner.py', self.source)
        self.assertIn('--ipa "$IPA_PATH"', self.source)
        self.assertIn('--expected-source-sha "$SOURCE_SHA"', self.source)
        self.assertIn('--output-dir "$INSPECTION_DIR"', self.source)
        self.assertIn('NembraCaptureExternalBuildRecord.json', self.source)
        self.assertIn('NembraCaptureFieldBuildEvidenceRecord.json', self.source)
        self.assertIn('NembraCaptureSignedFieldArtifactInspection.json', self.source)
        self.assertIn('build-evidence/NembraField.ipa', self.source)
        self.assertIn('signed-field-artifact-inspection-not-field-authorization', self.source)
        self.assertIn('fieldBuildEvidenceRecordSHA256', self.source)
        self.assertIn('externalBuildRecordSHA256', self.source)
        self.assertIn('signedInstallableSHA256', self.source)
        self.assertIn('provisioningProfileSHA256', self.source)
        self.assertIn('provisioningProfileUUID', self.source)
        self.assertIn('provisioningProfileExpirationUTC', self.source)
        self.assertIn('provisioningApplicationIdentifier', self.source)
        self.assertNotIn('provisioningTeamIdentifier', self.source)
        self.assertNotIn('provisionedDeviceCount', self.source)
        self.assertNotIn('embeddedMobileProvisionSHA256', self.source)
        self.assertNotIn('NembraCaptureSignedFieldArtifactEvidence.json', self.source)
        self.assertNotIn('NembraCaptureSignedFieldCandidateEvidence.json', self.source)
        self.assertNotIn('es80_field_candidate_verify.py', self.source)

    def test_keeps_producer_provenance_outside_failure_atomic_inspector_directory(self):
        self.assertIn('INSPECTION_DIR="$ARTIFACTS_DIR/inspection"', self.source)
        self.assertIn('mkdir -p "$ARTIFACTS_DIR/logs"', self.source)
        self.assertNotIn('mkdir -p "$INSPECTION_DIR"', self.source)
        self.assertIn('EXPORT_OPTIONS_SNAPSHOT="$ARTIFACTS_DIR/ExportOptions.plist"', self.source)
        self.assertIn('logs/xcodebuild-archive.log', self.source)
        self.assertIn('logs/xcodebuild-export.log', self.source)
        self.assertIn('inspection_directory=inspection', self.source)
        self.assertNotIn('--output-dir "$ARTIFACTS_DIR"', self.source)

    def test_retains_exact_external_export_policy_and_refuses_output_reuse(self):
        self.assertIn('ARTIFACTS_DIR already exists; refusing to mix or overwrite', self.source)
        self.assertIn('git check-ignore -q', self.source)
        self.assertIn('ExportOptions.plist', self.source)
        self.assertIn('EXPORT_OPTIONS_SHA256', self.source)
        self.assertIn('POST_EXPORT_OPTIONS_SHA256', self.source)
        self.assertIn('teamID', self.source)
        self.assertIn('-exportOptionsPlist "$EXPORT_OPTIONS_SNAPSHOT"', self.source)

    def test_builds_from_fresh_detached_exact_commit_snapshot(self):
        self.assertIn('SOURCE_ROOT="$WORK_ROOT/source"', self.source)
        self.assertIn('git worktree add --detach "$SOURCE_ROOT" "$SOURCE_SHA"', self.source)
        self.assertIn('cd "$SOURCE_ROOT"', self.source)
        self.assertIn('IMMUTABLE_HEAD="$(git rev-parse --verify HEAD^{commit})"', self.source)
        self.assertIn('IMMUTABLE_STATUS="$(git status --porcelain=v1 --untracked-files=all)"', self.source)
        self.assertIn('POST_BUILD_SOURCE_STATUS=', self.source)
        self.assertIn('POST_BUILD_HEAD=', self.source)
        self.assertIn('Archive/export changed immutable source state', self.source)
        self.assertIn('git worktree remove --force "$SOURCE_ROOT"', self.source)

    def test_is_bash_32_safe_for_optional_paths(self):
        self.assertIn('run_xcodebuild()', self.source)
        self.assertIn('NEMBRA_ALLOW_PROVISIONING_UPDATES', self.source)
        self.assertNotIn('PROVISIONING_ARGS=()', self.source)
        self.assertNotIn('IPA_FILES=(', self.source)
        self.assertNotIn('shopt -s nullglob', self.source)
        self.assertNotIn('shopt -u nullglob', self.source)

    def test_never_mutates_physical_authorization(self):
        self.assertIn('Independent acceptance has NOT occurred.', self.source)
        self.assertIn('PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN.', self.source)
        self.assertIn('physical_authorization=not-granted', self.source)
        self.assertNotIn('PassiveBluetoothExperimentOneFieldExecutionGate', self.source)
        self.assertNotIn('ES80_PHYSICAL_CAPTURE_RUNBOOK.md', self.source)


if __name__ == "__main__":
    unittest.main()

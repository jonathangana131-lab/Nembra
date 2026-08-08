#!/usr/bin/env python3
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidateProducerSourceTests(unittest.TestCase):
    def setUp(self):
        self.source = SCRIPT.read_text()

    def test_targets_real_ios_and_injects_exact_build_rendezvous(self):
        self.assertIn('generic/platform=iOS', self.source)
        self.assertIn('-exportArchive', self.source)
        self.assertNotIn('CODE_SIGNING_ALLOWED=NO', self.source)
        self.assertIn('Capture Build V14-${SOURCE_SHA:0:12}', self.source)
        self.assertIn('INFOPLIST_KEY_NembraCaptureBuildIdentifier', self.source)
        self.assertIn('INFOPLIST_KEY_NembraCaptureBuildInstanceID', self.source)
        self.assertIn('INFOPLIST_KEY_NembraCaptureBuildCommitSHA', self.source)
        self.assertIn('FIELD_RECIPE_ID="ES80-FINGERPRINT-v1"', self.source)
        self.assertIn('INFOPLIST_KEY_NembraCaptureFieldRecipe=$FIELD_RECIPE_ID', self.source)

    def test_reuses_live_canonical_signed_field_evidence_contract(self):
        self.assertIn('es80_signed_field_artifact_evidence.py', self.source)
        self.assertIn('--ipa "$IPA_PATH"', self.source)
        self.assertIn('--expected-source-sha "$SOURCE_SHA"', self.source)
        self.assertIn('--intended-device-udid "$NEMBRA_INTENDED_DEVICE_UDID"', self.source)
        self.assertIn('--output-dir "$ARTIFACTS_DIR"', self.source)
        self.assertIn('NembraCaptureExternalBuildRecord.json', self.source)
        self.assertIn('NembraCaptureFieldBuildEvidenceRecord.json', self.source)
        self.assertIn('NembraCaptureSignedFieldArtifactInspection.json', self.source)
        self.assertIn('build-evidence/NembraField.ipa', self.source)
        self.assertIn('signed-field-artifact-inspection-not-field-authorization', self.source)
        self.assertIn('fieldBuildEvidenceRecordSHA256', self.source)
        self.assertIn('externalBuildRecordSHA256', self.source)
        self.assertIn('signedInstallableSHA256', self.source)
        self.assertIn('provisioningProfileSHA256', self.source)
        self.assertNotIn('NembraCaptureSignedFieldArtifactEvidence.json', self.source)
        self.assertNotIn('NembraCaptureSignedFieldCandidateEvidence.json', self.source)
        self.assertNotIn('es80_field_candidate_verify.py', self.source)

    def test_intended_device_is_verification_only(self):
        self.assertIn('NEMBRA_INTENDED_DEVICE_UDID', self.source)
        self.assertIn('does not persist, print, or hash it', self.source)
        self.assertNotIn('intended_device_udid=', self.source)
        self.assertNotIn('intended_device_udid_sha', self.source)
        self.assertNotIn('device_udid=', self.source)

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

    def test_is_bash_32_safe_for_optional_inputs_and_pipeline_status(self):
        self.assertIn('ALLOW_PROVISIONING_UPDATES="${NEMBRA_ALLOW_PROVISIONING_UPDATES:-0}"', self.source)
        self.assertIn('run_xcodebuild()', self.source)
        self.assertIn('if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]', self.source)
        self.assertNotIn('PROVISIONING_ARGS=()', self.source)
        self.assertNotIn('IPA_FILES=(', self.source)
        self.assertNotIn('shopt -s nullglob', self.source)
        self.assertIn('Expected exactly one exported .ipa', self.source)
        self.assertIn('ARCHIVE_PIPESTATUS=("${PIPESTATUS[@]}")', self.source)
        self.assertIn('EXPORT_PIPESTATUS=("${PIPESTATUS[@]}")', self.source)
        self.assertIn('Snapshot PIPESTATUS in one assignment', self.source)

    def test_keeps_canonical_evidence_failure_atomic_and_producer_audit_separate(self):
        self.assertIn('PRODUCER_AUDIT_DIR="${ARTIFACTS_DIR}.producer-audit"', self.source)
        self.assertIn('ARTIFACTS_DIR must still not exist here', self.source)
        self.assertIn('--output-dir "$ARTIFACTS_DIR"', self.source)
        self.assertIn('$PRODUCER_AUDIT_DIR/logs/xcodebuild-archive.log', self.source)
        self.assertIn('$PRODUCER_AUDIT_DIR/logs/xcodebuild-export.log', self.source)
        self.assertIn('ExportOptions.plist', self.source)
        self.assertIn('export_options_sha256=$EXPORT_OPTIONS_SHA256', self.source)
        self.assertIn('INCOMPLETE_NON_AUTHORIZING_PRODUCER_AUDIT', self.source)
        self.assertIn('COMPLETE_NON_AUTHORIZING_PRODUCER_AUDIT', self.source)
        inspector_call = self.source.index('python3 scripts/ci/es80_signed_field_artifact_evidence.py')
        self.assertLess(self.source.index('mkdir -p "$PRODUCER_AUDIT_DIR/logs"'), inspector_call)
        self.assertNotIn('mkdir -p "$ARTIFACTS_DIR', self.source)

    def test_snapshots_exact_export_policy_and_rechecks_its_bytes(self):
        self.assertIn('EXPORT_OPTIONS_SNAPSHOT="$PRODUCER_AUDIT_DIR/ExportOptions.plist"', self.source)
        self.assertIn('cp -p "$EXPORT_OPTIONS_PLIST" "$EXPORT_OPTIONS_SNAPSHOT"', self.source)
        self.assertIn('EXPORT_OPTIONS_SHA256=', self.source)
        self.assertIn('POST_EXPORT_OPTIONS_SHA256=', self.source)
        self.assertIn('Retained ExportOptions.plist changed during archive/export', self.source)
        self.assertIn('-exportOptionsPlist "$EXPORT_OPTIONS_SNAPSHOT"', self.source)
        self.assertIn('Export options teamID does not match NEMBRA_DEVELOPMENT_TEAM', self.source)

    def test_uses_unique_physically_canonicalized_non_overwriting_output(self):
        self.assertIn('Xcode27FieldCandidate-${SOURCE_SHA:0:12}-$BUILD_INSTANCE_ID', self.source)
        self.assertIn('resolve(strict=False)', self.source)
        self.assertIn('ARTIFACTS_DIR already exists; refusing to mix or overwrite field evidence', self.source)
        self.assertIn('Producer audit sidecar already exists', self.source)
        self.assertIn('git check-ignore -q', self.source)

    def test_never_mutates_physical_authorization(self):
        self.assertIn('Independent acceptance has NOT occurred.', self.source)
        self.assertIn('PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN.', self.source)
        self.assertIn('physical_authorization=not-granted', self.source)
        self.assertNotIn('PassiveBluetoothExperimentOneFieldExecutionGate', self.source)
        self.assertNotIn('ES80_PHYSICAL_CAPTURE_RUNBOOK.md', self.source)


if __name__ == "__main__":
    unittest.main()

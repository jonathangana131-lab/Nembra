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

    def test_reuses_live_canonical_signed_field_evidence_contract(self):
        self.assertIn('es80_signed_field_artifact_evidence.py', self.source)
        self.assertIn('--ipa "$IPA_PATH"', self.source)
        self.assertIn('--expected-source-sha "$SOURCE_SHA"', self.source)
        self.assertIn('NembraCaptureExternalBuildRecord.json', self.source)
        self.assertIn('NembraCaptureFieldBuildEvidenceRecord.json', self.source)
        self.assertIn('NembraCaptureSignedFieldArtifactInspection.json', self.source)
        self.assertIn('build-evidence/NembraField.ipa', self.source)
        self.assertIn('signed-field-artifact-inspection-not-field-authorization', self.source)
        self.assertIn('fieldBuildEvidenceRecordSHA256', self.source)
        self.assertIn('externalBuildRecordSHA256', self.source)
        self.assertIn('signedInstallableSHA256', self.source)
        self.assertNotIn('NembraCaptureSignedFieldArtifactEvidence.json', self.source)
        self.assertNotIn('NembraCaptureSignedFieldCandidateEvidence.json', self.source)
        self.assertNotIn('es80_field_candidate_verify.py', self.source)

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

    def test_canonicalizes_unique_non_destructive_evidence_directory(self):
        self.assertIn('pwd -P', self.source)
        self.assertIn(
            'RAW_ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT/artifacts/Xcode27FieldCandidate-${SOURCE_SHA:0:12}-$BUILD_INSTANCE_ID}"',
            self.source,
        )
        self.assertIn('Path(sys.argv[1]).resolve(strict=False)', self.source)
        self.assertIn('"$ARTIFACTS_DIR" == "/" || "$ARTIFACTS_DIR" == "$ROOT"', self.source)
        self.assertIn('if [[ -e "$ARTIFACTS_DIR" ]]', self.source)
        self.assertIn('refusing to mix or overwrite field-production evidence', self.source)
        self.assertIn('git check-ignore -q', self.source)
        self.assertIn('--output-dir "$ARTIFACTS_DIR"', self.source)

    def test_snapshots_and_binds_exact_export_options_used(self):
        self.assertIn('EXPORT_OPTIONS_SNAPSHOT="$ARTIFACTS_DIR/ExportOptions.plist"', self.source)
        self.assertIn('cp -p "$EXPORT_OPTIONS_PLIST" "$EXPORT_OPTIONS_SNAPSHOT"', self.source)
        self.assertIn('-exportOptionsPlist "$EXPORT_OPTIONS_SNAPSHOT"', self.source)
        self.assertIn('options.get("teamID")', self.source)
        self.assertIn('Export options teamID does not match NEMBRA_DEVELOPMENT_TEAM', self.source)
        self.assertIn('EXPORT_OPTIONS_SHA256=', self.source)
        self.assertIn('POST_EXPORT_OPTIONS_SHA256=', self.source)
        self.assertIn('Retained ExportOptions.plist changed during archive/export', self.source)
        self.assertIn('export_options_file=ExportOptions.plist', self.source)
        self.assertIn('export_options_sha256=$EXPORT_OPTIONS_SHA256', self.source)

    def test_optional_provisioning_path_is_safe_on_macos_bash_32(self):
        self.assertIn('ALLOW_PROVISIONING_UPDATES="${NEMBRA_ALLOW_PROVISIONING_UPDATES:-0}"', self.source)
        self.assertIn('NEMBRA_ALLOW_PROVISIONING_UPDATES must be exactly 0 or 1.', self.source)
        self.assertIn('run_xcodebuild()', self.source)
        self.assertIn('xcodebuild -allowProvisioningUpdates "$@"', self.source)
        self.assertGreaterEqual(self.source.count('run_xcodebuild'), 3)
        self.assertNotIn('PROVISIONING_ARGS=()', self.source)
        self.assertNotIn('${PROVISIONING_ARGS[@]}', self.source)
        self.assertIn('allow_provisioning_updates=$ALLOW_PROVISIONING_UPDATES', self.source)

    def test_retains_archive_and_export_logs(self):
        self.assertIn('logs/xcodebuild-archive.log', self.source)
        self.assertIn('logs/xcodebuild-export.log', self.source)
        self.assertIn('ARCHIVE_PIPESTATUS=("${PIPESTATUS[@]}")', self.source)
        self.assertIn('EXPORT_PIPESTATUS=("${PIPESTATUS[@]}")', self.source)
        self.assertIn('archive_log=logs/xcodebuild-archive.log', self.source)
        self.assertIn('export_log=logs/xcodebuild-export.log', self.source)

    def test_never_mutates_physical_authorization(self):
        self.assertIn('Independent acceptance has NOT occurred.', self.source)
        self.assertIn('PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN.', self.source)
        self.assertIn('physical_authorization=not-granted', self.source)
        self.assertNotIn('PassiveBluetoothExperimentOneFieldExecutionGate', self.source)
        self.assertNotIn('ES80_PHYSICAL_CAPTURE_RUNBOOK.md', self.source)


if __name__ == "__main__":
    unittest.main()

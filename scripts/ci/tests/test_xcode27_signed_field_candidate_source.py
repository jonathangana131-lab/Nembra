#!/usr/bin/env python3
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidateProducerSourceTests(unittest.TestCase):
    def setUp(self):
        self.source = SCRIPT.read_text(encoding="utf-8")

    def test_targets_real_ios_and_injects_exact_build_rendezvous(self):
        self.assertIn('generic/platform=iOS', self.source)
        self.assertIn('-exportArchive', self.source)
        self.assertNotIn('CODE_SIGNING_ALLOWED=NO', self.source)
        self.assertIn('Capture Build V14-${SOURCE_SHA:0:12}', self.source)
        self.assertIn('INFOPLIST_KEY_NembraCaptureBuildIdentifier', self.source)
        self.assertIn('INFOPLIST_KEY_NembraCaptureBuildInstanceID', self.source)
        self.assertIn('INFOPLIST_KEY_NembraCaptureBuildCommitSHA', self.source)

    def test_reuses_single_canonical_signed_field_artifact_evidence_owner(self):
        self.assertIn('es80_signed_field_artifact_evidence.py', self.source)
        self.assertIn('--ipa "$IPA_PATH"', self.source)
        self.assertIn('--expected-source-sha "$SOURCE_SHA"', self.source)
        self.assertIn('signed-field-artifact-evidence-not-field-authorization', self.source)
        self.assertNotIn('NembraCaptureSignedFieldCandidateEvidence.json', self.source)
        self.assertNotIn('es80_field_candidate_verify.py', self.source)
        self.assertNotIn('verify_es80_field_artifact.py', self.source)

    def test_rechecks_same_exact_head_and_clean_tree_across_long_build(self):
        self.assertIn('require_exact_clean_source "initial source admission"', self.source)
        self.assertIn('require_exact_clean_source "post archive/export admission"', self.source)
        self.assertIn('require_exact_clean_source "post evidence admission"', self.source)
        self.assertIn('head_before="$(git rev-parse --verify HEAD^{commit})"', self.source)
        self.assertIn('head_after="$(git rev-parse --verify HEAD^{commit})"', self.source)
        self.assertIn('head_before" != "$SOURCE_SHA', self.source)
        self.assertIn('head_after" != "$SOURCE_SHA', self.source)
        self.assertIn('git status --porcelain=v1 --untracked-files=all', self.source)

    def test_generated_paths_cannot_dirty_exact_source_checkout(self):
        self.assertIn('require_safe_generated_path "$WORK_ROOT"', self.source)
        self.assertIn('require_safe_generated_path "$ARTIFACTS_DIR"', self.source)
        self.assertIn('must not be the repository root', self.source)
        self.assertIn('git check-ignore -q', self.source)
        self.assertIn('$ROOT/artifacts/Xcode27FieldCandidate', self.source)

    def test_requires_exact_one_final_exported_ipa(self):
        self.assertIn('IPA_FILES=("$EXPORT_DIR"/*.ipa)', self.source)
        self.assertIn('"${#IPA_FILES[@]}" -ne 1', self.source)
        self.assertIn('IPA_PATH="${IPA_FILES[0]}"', self.source)

    def test_never_mutates_physical_authorization(self):
        self.assertIn('Independent acceptance has NOT occurred.', self.source)
        self.assertIn('PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN.', self.source)
        self.assertNotIn('PassiveBluetoothExperimentOneFieldExecutionGate', self.source)
        self.assertNotIn('ES80_PHYSICAL_CAPTURE_RUNBOOK.md', self.source)


if __name__ == "__main__":
    unittest.main()

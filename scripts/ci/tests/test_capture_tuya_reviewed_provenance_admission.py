#!/usr/bin/env python3
from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = (ROOT / "scripts" / "field" / "install_one_time_capture.command").read_text(encoding="utf-8")
BOOTSTRAP = (ROOT / "Scripts" / "bootstrap_capture_tuya_sdk.sh").read_text(encoding="utf-8")


class CaptureTuyaReviewedProvenanceAdmissionTests(unittest.TestCase):
    def test_field_installer_can_only_verify_preexisting_private_provenance(self) -> None:
        invocation = '"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh" --verify-existing-provenance'
        self.assertIn(invocation, INSTALLER)
        self.assertNotIn('"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"\n', INSTALLER)

    def test_bootstrap_separates_preparation_snapshot_from_field_verification(self) -> None:
        self.assertIn('PROVENANCE_MODE="snapshot"', BOOTSTRAP)
        self.assertIn('--verify-existing-provenance)', BOOTSTRAP)
        self.assertIn('PROVENANCE_MODE="verify"', BOOTSTRAP)
        self.assertIn('if [[ "$PROVENANCE_MODE" == "verify" ]]; then', BOOTSTRAP)
        self.assertIn('"$PROVENANCE_HELPER" verify "${PROVENANCE_ARGUMENTS[@]}"', BOOTSTRAP)
        self.assertIn('"$PROVENANCE_HELPER" snapshot "${PROVENANCE_ARGUMENTS[@]}"', BOOTSTRAP)

    def test_field_verification_fails_when_preserved_record_is_missing_or_drifted(self) -> None:
        start = BOOTSTRAP.index('if [[ "$PROVENANCE_MODE" == "verify" ]]; then')
        end = BOOTSTRAP.index('\nelse\n', start)
        verify_branch = BOOTSTRAP[start:end]
        self.assertIn('[[ -f "$DEPENDENCY_PROVENANCE" ]]', verify_branch)
        self.assertIn('will not create its own admission record', verify_branch)
        self.assertIn('"$PROVENANCE_HELPER" verify', verify_branch)
        self.assertNotIn('"$PROVENANCE_HELPER" snapshot', verify_branch)
        self.assertIn('do not match the preserved reviewed provenance record', verify_branch)

    def test_snapshot_remains_available_only_as_explicit_preparation_behavior(self) -> None:
        start = BOOTSTRAP.index('if [[ "$PROVENANCE_MODE" == "verify" ]]; then')
        else_index = BOOTSTRAP.index('\nelse\n', start)
        end = BOOTSTRAP.index('\nfi\n', else_index) + len('\nfi\n')
        admission = BOOTSTRAP[start:end]
        snapshot_branch = admission[admission.index('\nelse\n') + len('\nelse\n'):]
        self.assertIn('"$PROVENANCE_HELPER" snapshot', snapshot_branch)
        self.assertNotIn('"$PROVENANCE_HELPER" verify', snapshot_branch)


if __name__ == "__main__":
    unittest.main()

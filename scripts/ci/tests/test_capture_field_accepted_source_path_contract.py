#!/usr/bin/env python3
from pathlib import Path
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"
BOOTSTRAP = REPOSITORY / "Scripts/bootstrap_capture_tuya_sdk.sh"


class CaptureFieldAcceptedSourcePathContractTests(unittest.TestCase):
    def test_field_guard_uses_declared_relative_exact_source_path(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        self.assertIn(
            'TUYA_BUILD_WINDOW_GUARD_RELATIVE="Scripts/capture_tuya_private_input_build_guard.py"',
            source,
        )
        self.assertIn(
            '[[ -f "$ROOT/$TUYA_BUILD_WINDOW_GUARD_RELATIVE" ]]',
            source,
        )
        self.assertNotIn(
            '[[ -f "$TUYA_BUILD_WINDOW_GUARD" ]]',
            source,
            "field installer must not dereference the removed pre-relative-path variable under set -u",
        )
        self.assertIn(
            'run_accepted_source_python "$TUYA_BUILD_WINDOW_GUARD_RELATIVE"',
            source,
            "build-window guard must execute from the exact accepted Git source subject",
        )
        self.assertNotIn(
            '/usr/bin/python3 -I "$TUYA_BUILD_WINDOW_GUARD"',
            source,
            "field guard must not be executable again through a mutable worktree pathname",
        )

    def test_private_provenance_uses_declared_relative_exact_source_path(self) -> None:
        installer_source = INSTALLER.read_text(encoding="utf-8")
        bootstrap_source = BOOTSTRAP.read_text(encoding="utf-8")
        self.assertIn(
            'TUYA_PROVENANCE_HELPER_RELATIVE="Scripts/capture_tuya_private_input_provenance.py"',
            installer_source,
        )
        self.assertIn(
            'run_accepted_source_python "$TUYA_PROVENANCE_HELPER_RELATIVE" verify',
            installer_source,
        )
        self.assertIn(
            'run_accepted_python_helper "$PROVENANCE_HELPER" "$PROVENANCE_HELPER_SHA256" snapshot',
            bootstrap_source,
            "review-only provenance snapshot must execute captured digest-matching helper bytes",
        )
        self.assertIn(
            'run_accepted_python_helper "$PROVENANCE_HELPER" "$PROVENANCE_HELPER_SHA256" verify',
            bootstrap_source,
            "field provenance verification must execute captured digest-matching helper bytes",
        )
        self.assertNotIn(
            '"$PROVENANCE_HELPER" snapshot',
            bootstrap_source,
            "provenance snapshot must not regain direct mutable-path execution",
        )
        self.assertNotIn(
            '"$PROVENANCE_HELPER" verify',
            bootstrap_source,
            "provenance verification must not regain direct mutable-path execution",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Expected-red oracle for exact private guard/provenance execution authority.

The selected-Xcode/dedicated-build composition must not regress from executing the
private build-window guard and provenance helper out of exact accepted Git bytes to
reopening those authority-bearing helpers through mutable checkout pathnames.
"""

from __future__ import annotations

from pathlib import Path
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def _sources() -> tuple[str, str, str]:
    installer = INSTALLER.read_text(encoding="utf-8")
    orchestrator = ORCHESTRATOR.read_text(encoding="utf-8")
    return installer, orchestrator, installer + "\n" + orchestrator


class CaptureSelectedXcodeGuardExecutionAuthorityTests(unittest.TestCase):
    def test_guard_is_not_reopened_by_mutable_checkout_path(self) -> None:
        installer, _orchestrator, _combined = _sources()
        self.assertNotIn(
            '/usr/bin/python3 -I "$TUYA_BUILD_WINDOW_GUARD"',
            installer,
            "selected-Xcode composition reopens the private build-window guard by mutable checkout pathname",
        )

    def test_provenance_is_not_reopened_by_mutable_checkout_path(self) -> None:
        installer, _orchestrator, _combined = _sources()
        self.assertNotIn(
            '/usr/bin/python3 -I "$TUYA_PROVENANCE_HELPER" verify',
            installer,
            "selected-Xcode composition reopens the private provenance helper by mutable checkout pathname",
        )

    def test_guard_has_mechanically_visible_exact_execution_subject(self) -> None:
        _installer, _orchestrator, combined = _sources()
        exact_guard_markers = (
            'run_accepted_source_python "$TUYA_BUILD_WINDOW_GUARD_RELATIVE"',
            "guard_base64",
            "guard_blob",
            "accepted_guard",
        )
        self.assertTrue(
            any(marker in combined for marker in exact_guard_markers),
            "no exact accepted execution subject is visible for the private build-window guard",
        )

    def test_provenance_has_mechanically_visible_exact_execution_subject(self) -> None:
        _installer, _orchestrator, combined = _sources()
        exact_provenance_markers = (
            'run_accepted_source_python "$TUYA_PROVENANCE_HELPER_RELATIVE"',
            "provenance_base64",
            "provenance_blob",
            "accepted_provenance",
        )
        self.assertTrue(
            any(marker in combined for marker in exact_provenance_markers),
            "no exact accepted execution subject is visible for the private provenance helper",
        )

    def test_current_accepted_blob_transports_do_not_substitute_for_helper_identity(self) -> None:
        _installer, orchestrator, _combined = _sources()
        # These current accepted transports are legitimate for their own subjects.
        # Their presence alone cannot prove that guard/provenance bytes were admitted.
        for marker in (
            "freeze_launcher_base64",
            "freeze_helper_base64",
            "build_origin_base64",
            "install_custody_base64",
        ):
            self.assertIn(marker, orchestrator)


if __name__ == "__main__":
    unittest.main(verbosity=2)

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


class CaptureSelectedXcodeGuardExecutionAuthorityTests(unittest.TestCase):
    def test_guard_and_provenance_do_not_reopen_mutable_checkout_helpers(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        orchestrator = ORCHESTRATOR.read_text(encoding="utf-8")

        mutable_guard = '/usr/bin/python3 -I "$TUYA_BUILD_WINDOW_GUARD"'
        mutable_provenance = '/usr/bin/python3 -I "$TUYA_PROVENANCE_HELPER" verify'
        self.assertNotIn(
            mutable_guard,
            installer,
            "selected-Xcode composition reopens the private build-window guard by mutable checkout pathname",
        )
        self.assertNotIn(
            mutable_provenance,
            installer,
            "selected-Xcode composition reopens the private provenance helper by mutable checkout pathname",
        )

        # The previously selected field-authority contract executed these helpers
        # directly from exact accepted Git source. A future production repair may
        # use an equally strong base64/blob handoff in the orchestrator instead;
        # either shape must make exact accepted bytes mechanically visible here.
        exact_guard_markers = (
            'run_accepted_source_python "$TUYA_BUILD_WINDOW_GUARD_RELATIVE"',
            "guard_base64",
            "guard_blob",
            "accepted_guard",
        )
        exact_provenance_markers = (
            'run_accepted_source_python "$TUYA_PROVENANCE_HELPER_RELATIVE"',
            "provenance_base64",
            "provenance_blob",
            "accepted_provenance",
        )
        combined = installer + "\n" + orchestrator
        self.assertTrue(
            any(marker in combined for marker in exact_guard_markers),
            "no exact accepted execution subject is visible for the private build-window guard",
        )
        self.assertTrue(
            any(marker in combined for marker in exact_provenance_markers),
            "no exact accepted execution subject is visible for the private provenance helper",
        )

    def test_current_orchestrator_blob_transport_does_not_silently_count_as_guard_transport(self) -> None:
        orchestrator = ORCHESTRATOR.read_text(encoding="utf-8")
        # These are accepted helper transports, but none names the private guard or
        # provenance helper. Their presence cannot be used to make the guard gate green.
        for marker in (
            "freeze_launcher_base64",
            "freeze_helper_base64",
            "build_origin_base64",
            "install_custody_base64",
        ):
            self.assertIn(marker, orchestrator)
        self.assertFalse(
            "guard_base64" in orchestrator or "accepted_guard" in orchestrator,
            "update this oracle if production intentionally adds an exact private-guard handoff",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

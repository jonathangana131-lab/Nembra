#!/usr/bin/env python3
from pathlib import Path
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"


class CaptureFieldAcceptedSourcePathContractTests(unittest.TestCase):
    def test_field_guard_uses_exact_accepted_git_source(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        self.assertIn(
            'TUYA_BUILD_WINDOW_GUARD_RELATIVE="Scripts/capture_tuya_private_input_build_guard.py"',
            source,
        )
        self.assertIn(
            'GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git cat-file -e "$SOURCE_SHA:$TUYA_BUILD_WINDOW_GUARD_RELATIVE"',
            source,
            "guard presence must be proven in the exact accepted Git source",
        )
        self.assertNotIn(
            '[[ -f "$ROOT/$TUYA_BUILD_WINDOW_GUARD_RELATIVE" ]]',
            source,
            "mutable worktree guard presence must not gate exact-source execution",
        )
        self.assertNotIn(
            '[[ -f "$TUYA_BUILD_WINDOW_GUARD" ]]',
            source,
            "removed pre-relative-path variable must never be dereferenced under set -u",
        )
        self.assertIn(
            'run_accepted_source_python "$TUYA_BUILD_WINDOW_GUARD_RELATIVE"',
            source,
            "build-window guard must execute from exact accepted Git bytes",
        )

    def test_private_provenance_uses_exact_accepted_git_source(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        self.assertIn(
            'TUYA_PROVENANCE_HELPER_RELATIVE="Scripts/capture_tuya_private_input_provenance.py"',
            source,
        )
        self.assertIn(
            'run_accepted_source_python "$TUYA_PROVENANCE_HELPER_RELATIVE" verify',
            source,
        )

    def test_accepted_source_git_reads_ignore_replacement_refs_and_ambient_config(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        self.assertIn('"GIT_NO_REPLACE_OBJECTS": "1"', source)
        self.assertIn('"GIT_CONFIG_NOSYSTEM": "1"', source)
        self.assertIn('"GIT_CONFIG_GLOBAL": "/dev/null"', source)
        self.assertIn('env=git_environment', source)


if __name__ == "__main__":
    unittest.main(verbosity=2)

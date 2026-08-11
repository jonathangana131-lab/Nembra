#!/usr/bin/env python3
"""Expected-red contract for selected Xcode executable-file custody.

Directory ancestry custody is necessary but not sufficient for the physical
field compiler subject. A same-UID writable xcodebuild file can live inside a
root-owned/non-group-or-world-writable developer tree. The exact executable
resolved for the guarded build therefore needs its own root-owned,
non-group/world-writable regular-file admission before it can become authority.

This diagnostic is intentionally source-only and hardware-free. It does not
run Xcode, scan Bluetooth, or authorize a physical field experiment.
"""
from __future__ import annotations

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts" / "field" / "install_one_time_capture.command"


class CaptureFieldSelectedXcodebuildFileCustodyRedTeamTests(unittest.TestCase):
    def setUp(self) -> None:
        self.source = INSTALLER.read_text(encoding="utf-8")

    def _selected_xcodebuild_window(self) -> str:
        assignment = self.source.find('SELECTED_XCODEBUILD="$(DEVELOPER_DIR="$SELECTED_DEVELOPER_DIR" /usr/bin/xcrun --find xcodebuild)"')
        self.assertNotEqual(
            assignment,
            -1,
            "fixture requires the selected Xcode spine to resolve one concrete xcodebuild executable",
        )
        first_guarded_use = self.source.find('-- "$SELECTED_XCODEBUILD"', assignment)
        self.assertNotEqual(
            first_guarded_use,
            -1,
            "fixture requires the selected executable to become the vnode-guarded build subject",
        )
        return self.source[assignment:first_guarded_use]

    def test_parent_directory_custody_is_not_misrepresented_as_file_custody(self) -> None:
        window = self._selected_xcodebuild_window()
        self.assertIn(
            'validate_root_custodied_path "$(dirname "$SELECTED_XCODEBUILD")" directory',
            window,
            "fixture requires the current parent-directory custody contract",
        )

        exact_file_calls = (
            'validate_root_custodied_path "$SELECTED_XCODEBUILD" file',
            'require_root_custodied_file "$SELECTED_XCODEBUILD"',
            'assert_root_custodied_file "$SELECTED_XCODEBUILD"',
            'validate_root_custodied_file "$SELECTED_XCODEBUILD"',
        )
        self.assertTrue(
            any(call in window for call in exact_file_calls),
            "EXPECTED RED: selected Xcode directory ancestry is admitted, but the exact xcodebuild file is never admitted as a root-owned non-group/world-writable authority subject",
        )

    def test_exact_file_custody_contract_must_prove_regular_root_owned_nonwritable_bytes(self) -> None:
        window = self._selected_xcodebuild_window()
        helper_names = re.findall(
            r'(?m)^([A-Za-z_][A-Za-z0-9_]*)\s+"?\$SELECTED_XCODEBUILD"?\s+(?:file|regular_file)\b',
            window,
        )
        if not helper_names:
            self.fail(
                "EXPECTED RED: no exact selected-xcodebuild file-custody helper is called before guarded execution"
            )

        helper = helper_names[-1]
        definition = re.search(
            rf'(?ms)^{re.escape(helper)}\(\)\s*\{{(?P<body>.*?)^\}}',
            self.source,
        )
        self.assertIsNotNone(
            definition,
            "selected xcodebuild file-custody call must resolve to an auditable installer helper",
        )
        assert definition is not None
        body = definition.group("body")
        semantic_requirements = (
            (r'(?i)(regular|S_ISREG|-f)', "regular-file identity"),
            (r'(?i)(st_uid|uid)[^\n]*(?:0|root)|(?:0|root)[^\n]*(st_uid|uid)', "root ownership"),
            (r'(?i)(0o022|022|group/world|group-or-world|writable)', "non-group/world-writable mode"),
            (r'(?i)(lstat|fstat|stat\()', "filesystem metadata proof"),
        )
        for pattern, label in semantic_requirements:
            self.assertRegex(
                body,
                re.compile(pattern),
                f"selected xcodebuild file custody is missing {label}",
            )

    def test_exact_file_custody_precedes_guarded_build_subject_use(self) -> None:
        window = self._selected_xcodebuild_window()
        custody_positions = [
            position
            for call in (
                'validate_root_custodied_path "$SELECTED_XCODEBUILD" file',
                'require_root_custodied_file "$SELECTED_XCODEBUILD"',
                'assert_root_custodied_file "$SELECTED_XCODEBUILD"',
                'validate_root_custodied_file "$SELECTED_XCODEBUILD"',
            )
            if (position := window.find(call)) >= 0
        ]
        self.assertTrue(
            custody_positions,
            "EXPECTED RED: exact selected-xcodebuild file custody is absent before the guarded build consumes that executable",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Expected-red contract for exact selected Xcode executable-file custody.

Root-custodied directory ancestry is necessary but does not authorize mutable
regular-file bytes already present inside that ancestry. The field installer
must therefore prove the exact executable files it selects for physical Xcode
work are root-owned and not group/world writable before use.

Source-only, hardware-free diagnostic. It authorizes no physical experiment.
"""
from __future__ import annotations

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts" / "field" / "install_one_time_capture.command"


class CaptureFieldSelectedXcodeToolFileCustodyRedTeamTests(unittest.TestCase):
    def setUp(self) -> None:
        self.source = INSTALLER.read_text(encoding="utf-8")

    def _xcodebuild_assignment(self) -> int:
        marker = 'SELECTED_XCODEBUILD="$(DEVELOPER_DIR="$SELECTED_DEVELOPER_DIR" /usr/bin/xcrun --find xcodebuild)"'
        index = self.source.find(marker)
        self.assertNotEqual(index, -1, "fixture requires one explicitly selected xcodebuild subject")
        return index

    def _first_guarded_xcodebuild_use(self, start: int) -> int:
        index = self.source.find('-- "$SELECTED_XCODEBUILD"', start)
        self.assertNotEqual(index, -1, "fixture requires the selected xcodebuild to cross guarded execution")
        return index

    def test_parent_directory_custody_cannot_substitute_for_exact_file_custody(self) -> None:
        start = self._xcodebuild_assignment()
        end = self._first_guarded_xcodebuild_use(start)
        window = self.source[start:end]
        self.assertIn(
            'validate_root_custodied_path "$(dirname "$SELECTED_XCODEBUILD")" directory',
            window,
            "fixture requires the current parent-directory custody contract",
        )
        exact_file_markers = (
            'validate_root_custodied_path "$SELECTED_XCODEBUILD" file',
            'validate_root_custodied_file "$SELECTED_XCODEBUILD"',
            'require_root_custodied_file "$SELECTED_XCODEBUILD"',
            'assert_root_custodied_file "$SELECTED_XCODEBUILD"',
        )
        self.assertTrue(
            any(marker in window for marker in exact_file_markers),
            "EXPECTED RED: selected xcodebuild parent custody exists, but the exact executable file never becomes a root-owned non-group/world-writable authority subject",
        )

    def test_exact_file_custody_primitive_proves_file_identity_owner_and_mode(self) -> None:
        helper = re.search(
            r'(?m)^([A-Za-z_][A-Za-z0-9_]*)\s+"?\$SELECTED_XCODEBUILD"?\s+(?:file|regular_file)\b',
            self.source,
        )
        if helper is None:
            self.fail("EXPECTED RED: no exact selected-xcodebuild file-custody helper is called")
        helper_name = helper.group(1)
        definition = re.search(
            rf'(?ms)^{re.escape(helper_name)}\(\)\s*\{{(?P<body>.*?)^\}}',
            self.source,
        )
        self.assertIsNotNone(definition, "selected tool-file custody helper must be auditable in the installer")
        assert definition is not None
        body = definition.group("body")
        for pattern, label in (
            (r'(?i)(regular|S_ISREG|-f)', "regular-file identity"),
            (r'(?i)(st_uid|uid)[^\n]*(?:0|root)|(?:0|root)[^\n]*(st_uid|uid)', "root ownership"),
            (r'(?i)(0o022|022|group/world|group-or-world|writable)', "non-group/world-writable mode"),
            (r'(?i)(lstat|fstat|stat\()', "filesystem metadata proof"),
        ):
            self.assertRegex(body, re.compile(pattern), f"selected tool-file custody is missing {label}")

    def test_physical_xcrun_tools_have_file_level_authority_not_only_developer_dir_selection(self) -> None:
        # The installer currently drives xctrace/devicectl through the selected
        # DEVELOPER_DIR. Production may satisfy this by resolving each exact tool
        # with xcrun --find and applying the same file-custody primitive, or by an
        # equal-or-stronger exact descriptor/object authority before execution.
        for tool in ("xctrace", "devicectl"):
            selected_assignment = re.search(
                rf'(?m)^(?:readonly\s+)?(?P<name>SELECTED_[A-Z0-9_]*{tool.upper()}[A-Z0-9_]*)='
                rf'"?\$\(DEVELOPER_DIR="?\$SELECTED_DEVELOPER_DIR"?\s+/usr/bin/xcrun\s+--find\s+{tool}\)"?\s*$',
                self.source,
            )
            self.assertIsNotNone(
                selected_assignment,
                f"EXPECTED RED: physical {tool} is selected only indirectly through xcrun; no exact executable subject is resolved for file-level custody",
            )
            assert selected_assignment is not None
            variable = selected_assignment.group("name")
            exact_file_call = re.search(
                rf'(?m)^[A-Za-z_][A-Za-z0-9_]*\s+"?\${variable}"?\s+(?:file|regular_file)\b',
                self.source[selected_assignment.start():],
            )
            self.assertIsNotNone(
                exact_file_call,
                f"EXPECTED RED: selected {tool} executable has no exact file-level root/nonwritable custody before physical use",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)

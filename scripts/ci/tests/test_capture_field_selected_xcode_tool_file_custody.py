#!/usr/bin/env python3
"""Regression contract for exact selected Xcode executable-file custody.

Directory ancestry alone is not executable-byte authority. The physical field
installer must resolve the exact Xcode tools it will execute and prove each is a
regular root-owned file that is not group/world writable before physical use.
This source-only regression authorizes no physical experiment.
"""
from __future__ import annotations

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts" / "field" / "install_one_time_capture.command"


class CaptureFieldSelectedXcodeToolFileCustodyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.source = INSTALLER.read_text(encoding="utf-8")

    def _selected_assignment(self, tool: str) -> tuple[str, int]:
        assignment = re.search(
            rf'(?m)^(?:readonly\s+)?(?P<name>SELECTED_[A-Z0-9_]*{tool.upper()}[A-Z0-9_]*)='
            rf'"?\$\(DEVELOPER_DIR="?\$SELECTED_DEVELOPER_DIR"?\s+/usr/bin/xcrun\s+--find\s+{tool}\)"?\s*$',
            self.source,
        )
        self.assertIsNotNone(assignment, f"{tool} must be resolved to one exact selected executable")
        assert assignment is not None
        return assignment.group("name"), assignment.start()

    def _assert_exact_file_custody_after(self, variable: str, start: int) -> None:
        custody = re.search(
            rf'(?m)^(?P<helper>[A-Za-z_][A-Za-z0-9_]*)\s+"?\${variable}"?\s+(?:file|regular_file)\b',
            self.source[start:],
        )
        self.assertIsNotNone(custody, f"{variable} must receive exact file-level custody before use")
        assert custody is not None
        helper_name = custody.group("helper")
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

    def test_all_selected_xcode_tools_receive_exact_file_custody(self) -> None:
        for tool in ("xcodebuild", "xctrace", "devicectl"):
            variable, start = self._selected_assignment(tool)
            self._assert_exact_file_custody_after(variable, start)

    def test_physical_xctrace_and_devicectl_use_custodied_exact_subjects(self) -> None:
        xctrace, _ = self._selected_assignment("xctrace")
        devicectl, _ = self._selected_assignment("devicectl")
        self.assertIn(f'"${xctrace}" list devices', self.source)
        self.assertIn(f'"${devicectl}" list devices', self.source)
        self.assertIn(f'"${devicectl}" device install app', self.source)
        self.assertIn(f'"${devicectl}" device process launch', self.source)
        self.assertNotIn('/usr/bin/xcrun xctrace list devices', self.source)
        self.assertNotIn('/usr/bin/xcrun devicectl list devices', self.source)
        self.assertNotIn('/usr/bin/xcrun devicectl device install app', self.source)
        self.assertNotIn('/usr/bin/xcrun devicectl device process launch', self.source)

    def test_selected_xcodebuild_itself_interrogates_version(self) -> None:
        variable, start = self._selected_assignment("xcodebuild")
        custody = self.source.find(f'validate_root_custodied_path "${variable}" file', start)
        self.assertNotEqual(custody, -1)
        version = self.source.find(f'SELECTED_XCODE_VERSION="$("${variable}" -version', custody)
        self.assertNotEqual(version, -1, "version admission must interrogate the exact custodied xcodebuild subject")


if __name__ == "__main__":
    unittest.main(verbosity=2)

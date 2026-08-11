#!/usr/bin/env python3
"""Source contract for selected Xcode developer-tree and exact-tool custody.

Clearing caller overrides only delegates selection back to xcode-select. The
physical field path must prove the selected Xcode 27 developer tree first, then
resolve and custody the exact executable files used for build/device authority.
"""
from __future__ import annotations

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts" / "field" / "install_one_time_capture.command"


class CaptureFieldSelectedXcodeCustodyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.source = INSTALLER.read_text(encoding="utf-8")

    def _selected_developer_dir(self) -> tuple[str, int]:
        selection = re.search(
            r'(?m)^(?:readonly\s+)?(?P<name>[A-Z0-9_]*DEVELOPER_DIR)='
            r'"?\$\((?:/usr/bin/)?xcode-select\s+-p\)"?\s*$',
            self.source,
        )
        self.assertIsNotNone(
            selection,
            "field authority must capture the system-selected developer directory with /usr/bin/xcode-select -p rather than merely trust the dispatcher default",
        )
        assert selection is not None
        return selection.group("name"), selection.start()

    def _selected_tool(self, tool: str) -> tuple[str, int]:
        assignment = re.search(
            rf'(?m)^(?P<name>SELECTED_[A-Z0-9_]*{tool.upper()}[A-Z0-9_]*)='
            rf'"?\$\(DEVELOPER_DIR="?\$SELECTED_DEVELOPER_DIR"?\s+/usr/bin/xcrun\s+--find\s+{tool}\)"?\s*$',
            self.source,
        )
        self.assertIsNotNone(
            assignment,
            f"{tool} must be resolved once from the admitted selected developer tree",
        )
        assert assignment is not None
        return assignment.group("name"), assignment.start()

    def _first_physical_device_tool_use(self) -> int:
        xctrace, _ = self._selected_tool("xctrace")
        devicectl, _ = self._selected_tool("devicectl")
        tokens = (f'"${xctrace}" list devices', f'"${devicectl}" list devices')
        positions: list[int] = []
        for token in tokens:
            position = self.source.find(token)
            self.assertNotEqual(position, -1, f"expected exact physical device-tool boundary is missing: {token}")
            positions.append(position)
        return min(positions)

    def test_system_selected_developer_tree_is_explicit_authority_subject(self) -> None:
        name, selection_index = self._selected_developer_dir()
        first_tool_resolution = min(self._selected_tool(tool)[1] for tool in ("xcodebuild", "xctrace", "devicectl"))
        self.assertLess(selection_index, first_tool_resolution)

        preflight = self.source[selection_index:first_tool_resolution]
        custody_patterns = (
            rf'validate_root_custodied_path\s+"?\${name}"?\s+directory',
            rf'verify_[A-Za-z0-9_]*developer[A-Za-z0-9_]*\s+"?\${name}"?',
            rf'assert_[A-Za-z0-9_]*root[A-Za-z0-9_]*nonwritable[A-Za-z0-9_]*\s+"?\${name}"?',
        )
        self.assertTrue(
            any(re.search(pattern, preflight) for pattern in custody_patterns),
            "the exact xcode-select developer tree must pass an explicit root-owned/non-group-or-world-writable ancestry custody check before selected-tool resolution",
        )

    def test_selected_toolchain_is_admitted_as_xcode_27_before_device_or_build_use(self) -> None:
        _, selection_index = self._selected_developer_dir()
        device_use = self._first_physical_device_tool_use()
        preflight = self.source[selection_index:device_use]
        self.assertIn(
            'SELECTED_XCODE_VERSION="$("$SELECTED_XCODEBUILD" -version',
            preflight,
            "Xcode version admission must interrogate the exact custodied selected xcodebuild subject",
        )
        self.assertRegex(
            preflight,
            re.compile(r'Xcode[^\n]*27|27[^\n]*Xcode', re.IGNORECASE),
            "field admission must fail closed unless the selected toolchain identifies as Xcode 27",
        )

    def test_caller_fence_alone_is_not_misrepresented_as_selected_toolchain_custody(self) -> None:
        self._selected_developer_dir()
        self.assertIn(
            "xcode-select",
            self.source,
            "selected developer-directory authority must remain explicit after caller overrides are cleared",
        )

    def test_same_selected_tree_drives_exact_custodied_build_and_device_tools(self) -> None:
        for tool, variable in (
            ("xcodebuild", "SELECTED_XCODEBUILD"),
            ("xctrace", "SELECTED_XCTRACE"),
            ("devicectl", "SELECTED_DEVICECTL"),
        ):
            discovered, _ = self._selected_tool(tool)
            self.assertEqual(discovered, variable)
            self.assertIn(
                f'validate_root_custodied_path "${variable}" file',
                self.source,
                f"{tool} must receive exact regular-file/root-custody admission before use",
            )

        self.assertIn('-- "$SELECTED_XCODEBUILD" \\', self.source)
        self.assertIn('"$SELECTED_XCTRACE" list devices', self.source)
        self.assertIn('"$SELECTED_DEVICECTL" list devices', self.source)
        self.assertIn('"$SELECTED_DEVICECTL" device install app', self.source)
        self.assertIn('"$SELECTED_DEVICECTL" device process launch', self.source)
        self.assertNotIn('-- /usr/bin/xcodebuild', self.source)
        self.assertNotIn('/usr/bin/xcrun xctrace list devices', self.source)
        self.assertNotIn('/usr/bin/xcrun devicectl list devices', self.source)
        self.assertNotIn('/usr/bin/xcrun devicectl device install app', self.source)
        self.assertNotIn('/usr/bin/xcrun devicectl device process launch', self.source)


if __name__ == "__main__":
    unittest.main(verbosity=2)

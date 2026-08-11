#!/usr/bin/env python3
"""Source contract for selected Xcode developer-tree custody.

This is deliberately distinct from the caller-DEVELOPER_DIR fence. Clearing a
caller override only delegates toolchain selection back to xcode-select; the
physical field path must also prove that selected developer tree is a trusted
Xcode 27 subject before any candidate build can earn authority.
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

    def test_system_selected_developer_tree_is_explicit_authority_subject(self) -> None:
        name, selection_index = self._selected_developer_dir()
        device_discovery = self.source.find("xctrace list devices")
        self.assertNotEqual(device_discovery, -1, "expected physical Xcode device-discovery boundary")
        self.assertLess(
            selection_index,
            device_discovery,
            "selected Xcode custody must be established before the first physical device-discovery use",
        )

        preflight = self.source[selection_index:device_discovery]
        custody_patterns = (
            rf'validate_root_custodied_path\s+"?\${name}"?\s+directory',
            rf'verify_[A-Za-z0-9_]*developer[A-Za-z0-9_]*\s+"?\${name}"?',
            rf'assert_[A-Za-z0-9_]*root[A-Za-z0-9_]*nonwritable[A-Za-z0-9_]*\s+"?\${name}"?',
        )
        self.assertTrue(
            any(re.search(pattern, preflight) for pattern in custody_patterns),
            "the exact xcode-select developer tree must pass an explicit root-owned/non-group-or-world-writable ancestry custody check before field Xcode use",
        )

    def test_selected_toolchain_is_admitted_as_xcode_27_before_device_or_build_use(self) -> None:
        _, selection_index = self._selected_developer_dir()
        device_discovery = self.source.find("xctrace list devices")
        preflight = self.source[selection_index:device_discovery]
        self.assertRegex(
            preflight,
            re.compile(r'/usr/bin/xcodebuild[^\n]*-version|run_[A-Za-z0-9_]*xcodebuild[^\n]*-version'),
            "the selected system toolchain must be interrogated before field device/build work",
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


if __name__ == "__main__":
    unittest.main(verbosity=2)

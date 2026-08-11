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

    def _selected_xcodebuild(self) -> tuple[str, int]:
        selection = re.search(
            r'(?m)^(?:readonly\s+)?(?P<name>SELECTED_[A-Z0-9_]*XCODEBUILD[A-Z0-9_]*)='
            r'"?\$\(DEVELOPER_DIR="?\$SELECTED_DEVELOPER_DIR"?\s+/usr/bin/xcrun\s+--find\s+xcodebuild\)"?\s*$',
            self.source,
        )
        self.assertIsNotNone(selection, "field authority must resolve one exact selected xcodebuild executable")
        assert selection is not None
        return selection.group("name"), selection.start()

    def test_system_selected_developer_tree_is_explicit_authority_subject(self) -> None:
        name, selection_index = self._selected_developer_dir()
        device_discovery = self.source.find("list devices")
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

    def test_selected_toolchain_is_admitted_as_xcode_27_through_exact_custodied_xcodebuild(self) -> None:
        _, selection_index = self._selected_developer_dir()
        xcodebuild, xcodebuild_index = self._selected_xcodebuild()
        device_discovery = self.source.find("list devices")
        self.assertGreater(xcodebuild_index, selection_index)
        self.assertGreater(device_discovery, xcodebuild_index)
        preflight = self.source[xcodebuild_index:device_discovery]
        custody_marker = f'validate_root_custodied_path "${xcodebuild}" file'
        version_marker = f'SELECTED_XCODE_VERSION="$("${xcodebuild}" -version'
        self.assertIn(custody_marker, preflight, "exact selected xcodebuild must be file-custodied before version admission")
        self.assertIn(version_marker, preflight, "Xcode 27 version admission must interrogate the exact custodied xcodebuild executable")
        self.assertLess(preflight.index(custody_marker), preflight.index(version_marker))
        self.assertNotIn(
            'DEVELOPER_DIR="$SELECTED_DEVELOPER_DIR" /usr/bin/xcodebuild -version',
            preflight,
            "version admission must not use the mutable system xcodebuild dispatcher before exact executable custody",
        )
        self.assertRegex(
            preflight,
            re.compile(r'Xcode[^\n]*27|27[^\n]*Xcode', re.IGNORECASE),
            "field admission must fail closed unless the exact selected toolchain identifies as Xcode 27",
        )

    def test_caller_fence_alone_is_not_misrepresented_as_selected_toolchain_custody(self) -> None:
        self._selected_developer_dir()
        self.assertIn(
            "xcode-select",
            self.source,
            "selected developer-directory authority must remain explicit after caller overrides are cleared",
        )

    def test_same_selected_tree_drives_exact_device_tools_and_guarded_xcodebuild(self) -> None:
        name, _ = self._selected_developer_dir()
        for tool, variable in (("xctrace", "SELECTED_XCTRACE"), ("devicectl", "SELECTED_DEVICECTL")):
            self.assertIn(
                f'{variable}="$(DEVELOPER_DIR="${name}" /usr/bin/xcrun --find {tool})"',
                self.source,
                f"{tool} must be resolved from the admitted selected developer tree",
            )
            self.assertIn(
                f'validate_root_custodied_path "${variable}" file',
                self.source,
                f"{tool} must receive exact executable-file custody",
            )
            self.assertRegex(
                self.source,
                re.compile(rf'(?m)^.*"\${variable}"\s+(?:list|device|process)\b'),
                f"physical {tool} must execute the exact admitted executable",
            )
        self.assertIn(
            'SELECTED_XCODEBUILD="$(DEVELOPER_DIR="$SELECTED_DEVELOPER_DIR" /usr/bin/xcrun --find xcodebuild)"',
            self.source,
        )
        self.assertIn(
            'validate_root_custodied_path "$SELECTED_XCODEBUILD" file',
            self.source,
            "selected xcodebuild must receive exact executable-file custody",
        )
        self.assertIn(
            '-- "$SELECTED_XCODEBUILD"',
            self.source,
            "the vnode-guarded compiler must execute the exact xcodebuild resolved from the admitted selected tree",
        )
        self.assertNotIn(
            '-- /usr/bin/xcodebuild',
            self.source,
            "the guarded physical build must not fall back to the mutable system Xcode dispatcher after custody",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

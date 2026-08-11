#!/usr/bin/env python3
"""Contract for caller-selected xcrun SDK/toolchain authority.

The field installer uses xcrun only to resolve exact selected Xcode executables.
Those resolutions still treat SDKROOT and TOOLCHAINS as caller-selectable inputs,
so both selectors must be fenced before the first `xcrun --find`. Physical
xctrace/devicectl execution must then use the exact custodied resolved files
rather than invoking xcrun again.
"""
from __future__ import annotations

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts" / "field" / "install_one_time_capture.command"


class CaptureFieldXcrunEnvironmentAuthorityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.source = INSTALLER.read_text(encoding="utf-8")

    def _first_selected_xcrun_resolution(self) -> int:
        boundaries = (
            "/usr/bin/xcrun --find xcodebuild",
            "/usr/bin/xcrun --find xctrace",
            "/usr/bin/xcrun --find devicectl",
        )
        positions: list[int] = []
        for token in boundaries:
            position = self.source.find(token)
            self.assertNotEqual(
                position,
                -1,
                f"expected selected Xcode tool-resolution boundary is missing: {token}",
            )
            positions.append(position)
        return min(positions)

    @staticmethod
    def _unset_names(source: str) -> set[str]:
        names: set[str] = set()
        for match in re.finditer(r"(?m)^\s*unset\s+([^\n#]+)", source):
            body = match.group(1).split("||", 1)[0]
            for token in body.split():
                if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", token):
                    names.add(token)
        return names

    def test_caller_xcrun_sdk_and_toolchain_selectors_are_fenced_before_tool_resolution(self) -> None:
        first_xcrun = self._first_selected_xcrun_resolution()
        preflight = self.source[:first_xcrun]
        unset_names = self._unset_names(preflight)

        missing = {"SDKROOT", "TOOLCHAINS"} - unset_names
        self.assertFalse(
            missing,
            "selected Xcode xcrun resolution still inherits caller SDK/toolchain selection: "
            + ", ".join(sorted(missing)),
        )

    def test_fenced_xcrun_selectors_are_not_reexported_before_selected_tool_resolution(self) -> None:
        first_xcrun = self._first_selected_xcrun_resolution()
        preflight = self.source[:first_xcrun]
        for name in ("SDKROOT", "TOOLCHAINS"):
            self.assertIsNone(
                re.search(rf"(?m)^\s*(?:export\s+)?{name}=", preflight),
                f"field preflight reintroduces caller-selectable {name} before selected Xcode tool resolution",
            )

    def test_physical_device_operations_do_not_reresolve_through_xcrun(self) -> None:
        self.assertIn('"$SELECTED_XCTRACE" list devices', self.source)
        self.assertIn('"$SELECTED_DEVICECTL" list devices', self.source)
        self.assertIn('"$SELECTED_DEVICECTL" device install app', self.source)
        self.assertIn('"$SELECTED_DEVICECTL" device process launch', self.source)
        for forbidden in (
            "/usr/bin/xcrun xctrace list devices",
            "/usr/bin/xcrun devicectl list devices",
            "/usr/bin/xcrun devicectl device install app",
            "/usr/bin/xcrun devicectl device process launch",
        ):
            self.assertNotIn(forbidden, self.source)


if __name__ == "__main__":
    unittest.main(verbosity=2)

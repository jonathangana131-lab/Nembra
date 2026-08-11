#!/usr/bin/env python3
"""Contract for caller-selected xcrun SDK/toolchain authority.

The field installer uses xcrun only to resolve exact Xcode tool subjects before
physical device work. xcrun treats SDKROOT and TOOLCHAINS as selection inputs,
so caller values must not remain ambient at those authority boundaries.
DEVELOPER_DIR is intentionally owned by the separate selected-Xcode lane.
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

    def _first_field_xcrun_use(self) -> int:
        boundaries = (
            "/usr/bin/xcrun --find xcodebuild",
            "/usr/bin/xcrun --find xctrace",
            "/usr/bin/xcrun --find devicectl",
        )
        positions = []
        for token in boundaries:
            position = self.source.find(token)
            self.assertNotEqual(
                position,
                -1,
                f"expected selected-Xcode xcrun resolution boundary is missing: {token}",
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
        first_xcrun = self._first_field_xcrun_use()
        preflight = self.source[:first_xcrun]
        unset_names = self._unset_names(preflight)

        missing = {"SDKROOT", "TOOLCHAINS"} - unset_names
        self.assertFalse(
            missing,
            "selected-Xcode xcrun still inherits caller SDK/toolchain selection before exact tool resolution: "
            + ", ".join(sorted(missing)),
        )

    def test_fenced_xcrun_selectors_are_not_reexported_before_tool_resolution(self) -> None:
        first_xcrun = self._first_field_xcrun_use()
        preflight = self.source[:first_xcrun]
        for name in ("SDKROOT", "TOOLCHAINS"):
            self.assertIsNone(
                re.search(rf"(?m)^\s*(?:export\s+)?{name}=", preflight),
                f"field preflight reintroduces caller-selectable {name} before xcrun resolution authority use",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)

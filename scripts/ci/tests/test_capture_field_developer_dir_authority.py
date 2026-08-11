#!/usr/bin/env python3
"""Expected-red source contract for field Xcode developer-directory authority."""
from __future__ import annotations

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts" / "field" / "install_one_time_capture.command"


class CaptureFieldDeveloperDirectoryAuthorityTests(unittest.TestCase):
    def test_caller_developer_dir_is_removed_before_any_xcode_tool_use(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        fence = "unset DEVELOPER_DIR"
        self.assertIn(
            fence,
            source,
            "physical field admission must not inherit caller-selected DEVELOPER_DIR",
        )

        fence_index = source.index(fence)
        xcrun_index = source.index("/usr/bin/xcrun")
        xcodebuild_index = source.index("/usr/bin/xcodebuild")
        self.assertLess(fence_index, xcrun_index)
        self.assertLess(fence_index, xcodebuild_index)

    def test_developer_dir_is_not_reintroduced_into_field_child_environment(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        fence_index = source.index("unset DEVELOPER_DIR")
        remainder = source[fence_index:]
        self.assertNotIn("export DEVELOPER_DIR", remainder)
        self.assertNotIn("DEVELOPER_DIR=\"${DEVELOPER_DIR", remainder)
        self.assertNotIn("DEVELOPER_DIR=$DEVELOPER_DIR", remainder)


if __name__ == "__main__":
    unittest.main(verbosity=2)

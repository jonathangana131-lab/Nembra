#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / "es80_today_field_candidate_preflight.py"
spec = importlib.util.spec_from_file_location("preflight", MODULE)
preflight = importlib.util.module_from_spec(spec)
assert spec and spec.loader
sys.modules[spec.name] = preflight
spec.loader.exec_module(preflight)


class ExportOptionsCustodyTests(unittest.TestCase):
    TEAM = "ABCDE12345"

    def write_plist(self, path: Path, value: object | None = None) -> None:
        with path.open("wb") as handle:
            plistlib.dump(
                value if value is not None else {"teamID": self.TEAM, "method": "development"},
                handle,
            )

    def test_absolute_regular_subject_is_admitted(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "ExportOptions.plist"
            self.write_plist(path)
            self.assertTrue(preflight._export_options_are_ready(path, self.TEAM))

    def test_relative_path_fails_closed(self):
        self.assertFalse(
            preflight._export_options_are_ready(Path("ExportOptions.plist"), self.TEAM)
        )

    def test_symlinked_parent_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            real_parent = root / "real"
            real_parent.mkdir()
            self.write_plist(real_parent / "ExportOptions.plist")
            alias_parent = root / "alias"
            try:
                alias_parent.symlink_to(real_parent, target_is_directory=True)
            except (OSError, NotImplementedError) as error:
                self.skipTest(f"symlink creation unavailable: {error}")

            self.assertFalse(
                preflight._export_options_are_ready(
                    alias_parent / "ExportOptions.plist",
                    self.TEAM,
                )
            )

    def test_symlinked_final_subject_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            real = root / "real.plist"
            self.write_plist(real)
            alias = root / "ExportOptions.plist"
            try:
                alias.symlink_to(real)
            except (OSError, NotImplementedError) as error:
                self.skipTest(f"symlink creation unavailable: {error}")

            self.assertFalse(preflight._export_options_are_ready(alias, self.TEAM))

    def test_descriptor_custody_does_not_weaken_semantic_coherence(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "ExportOptions.plist"
            self.write_plist(path, {"teamID": "ZZZZZ99999", "method": "development"})
            self.assertFalse(preflight._export_options_are_ready(path, self.TEAM))


if __name__ == "__main__":
    unittest.main()

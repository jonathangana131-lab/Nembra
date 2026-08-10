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


class ExportOptionsCoherenceTests(unittest.TestCase):
    TEAM = "ABCDE12345"

    def plist(self, root: Path, value: object) -> Path:
        path = root / "ExportOptions.plist"
        with path.open("wb") as handle:
            plistlib.dump(value, handle)
        return path

    def test_matching_team_is_admitted(self):
        with tempfile.TemporaryDirectory() as temp:
            path = self.plist(Path(temp), {"teamID": self.TEAM, "method": "development"})
            self.assertTrue(preflight._export_options_are_ready(path, self.TEAM))

    def test_mismatched_team_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            path = self.plist(Path(temp), {"teamID": "ZZZZZ99999", "method": "development"})
            self.assertFalse(preflight._export_options_are_ready(path, self.TEAM))

    def test_present_method_must_be_nonempty_string(self):
        for method in ("", "   ", 42, False, []):
            with self.subTest(method=method), tempfile.TemporaryDirectory() as temp:
                path = self.plist(Path(temp), {"method": method})
                self.assertFalse(preflight._export_options_are_ready(path, self.TEAM))

    def test_optional_fields_may_be_absent(self):
        with tempfile.TemporaryDirectory() as temp:
            path = self.plist(Path(temp), {})
            self.assertTrue(preflight._export_options_are_ready(path, self.TEAM))

    def test_non_dictionary_plist_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            path = self.plist(Path(temp), ["development"])
            self.assertFalse(preflight._export_options_are_ready(path, self.TEAM))


if __name__ == "__main__":
    unittest.main()

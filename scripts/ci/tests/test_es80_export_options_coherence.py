#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / "es80_today_field_candidate_preflight.py"
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
HANDOFF = REPOSITORY_ROOT / "docs" / "ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md"
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

    def test_export_options_path_must_be_absolute(self):
        self.assertFalse(
            preflight._export_options_are_ready(Path("ExportOptions.plist"), self.TEAM)
        )

    def test_symlinked_parent_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            real_parent = root / "real"
            real_parent.mkdir()
            path = self.plist(real_parent, {"teamID": self.TEAM, "method": "development"})
            alias = root / "alias"
            try:
                alias.symlink_to(real_parent, target_is_directory=True)
            except (OSError, NotImplementedError) as error:
                self.skipTest(f"symlink creation unavailable: {error}")
            self.assertFalse(preflight._export_options_are_ready(alias / path.name, self.TEAM))

    def test_symlinked_final_subject_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            real = root / "real.plist"
            with real.open("wb") as handle:
                plistlib.dump({"teamID": self.TEAM, "method": "development"}, handle)
            alias = root / "ExportOptions.plist"
            try:
                alias.symlink_to(real)
            except (OSError, NotImplementedError) as error:
                self.skipTest(f"symlink creation unavailable: {error}")
            self.assertFalse(preflight._export_options_are_ready(alias, self.TEAM))

    def test_fifo_subject_fails_closed_without_waiting_for_writer(self):
        if not hasattr(os, "mkfifo"):
            self.skipTest("FIFO creation unavailable")
        with tempfile.TemporaryDirectory() as temp:
            fifo = Path(temp) / "ExportOptions.plist"
            os.mkfifo(fifo, 0o600)
            self.assertFalse(preflight._export_options_are_ready(fifo, self.TEAM))

    def test_empty_file_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "ExportOptions.plist"
            path.touch()
            self.assertFalse(preflight._export_options_are_ready(path, self.TEAM))

    def test_retired_handoff_cannot_publish_old_export_options_helper_authority(self):
        handoff = HANDOFF.read_text(encoding="utf-8")
        stale_markers = (
            "74f4e88e4efb78bf69fe504f407ef42398e4b6ab",
            "1b0155ab8d990420c33ad4c65461e7663612f9fb",
            "31349183788",
            "93336690257",
            "PREFLIGHT_COMMIT=",
            "PREFLIGHT_BLOB=",
            "ExportOptions path/coherence/custody checks fail",
            "descriptor-opened regular-file subject",
        )

        self.assertIn("RETIRED / NON-AUTHORIZING", handoff)
        self.assertIn("ES80-AUTHENTICATED-STATIONARY-v1", handoff)
        self.assertIn("PHYSICAL STATUS: NO-GO", handoff)
        self.assertIn("old provisioning receipt", handoff)
        for marker in stale_markers:
            with self.subTest(marker=marker):
                self.assertNotIn(marker, handoff)


if __name__ == "__main__":
    unittest.main()

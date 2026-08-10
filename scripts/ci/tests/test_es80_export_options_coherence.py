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

    def test_canonical_handoff_pins_current_descriptor_bound_helper(self):
        handoff = HANDOFF.read_text(encoding="utf-8")
        current_section = handoff.split(
            "The current accepted external pre-signing helper is also non-authorizing software tooling:",
            1,
        )[1].split("## Why an exact detached source checkout is mandatory", 1)[0]

        self.assertIn("74f4e88e4efb78bf69fe504f407ef42398e4b6ab", current_section)
        self.assertIn("1b0155ab8d990420c33ad4c65461e7663612f9fb", current_section)
        self.assertIn("31349183788", current_section)
        self.assertIn("93336690257", current_section)
        self.assertIn("descriptor-opened regular-file subject", current_section)
        self.assertIn("Do not materialize or invoke that superseded helper", current_section)

        self.assertIn(
            "PREFLIGHT_COMMIT='74f4e88e4efb78bf69fe504f407ef42398e4b6ab'",
            handoff,
        )
        self.assertIn(
            "PREFLIGHT_BLOB='1b0155ab8d990420c33ad4c65461e7663612f9fb'",
            handoff,
        )
        self.assertIn("ExportOptions path/coherence/custody checks fail", handoff)
        self.assertIn("PHYSICAL EXPERIMENT ONE REMAINS NO-GO", handoff)

    def test_canonical_handoff_pins_current_private_input_helper(self):
        handoff = HANDOFF.read_text(encoding="utf-8")
        self.assertIn(
            "PRIVATE_INPUT_HELPER_COMMIT='c8c706e3d67d2aeab37341035468437dc2af0491'",
            handoff,
        )
        self.assertIn(
            "PRIVATE_INPUT_HELPER_BLOB='38eb695792fb759428a98686081b883e39c3b118'",
            handoff,
        )
        self.assertIn("31349522672", handoff)
        self.assertIn("93337607527", handoff)
        self.assertIn("require secure no-echo terminal input", handoff)
        self.assertIn("clean only the exact created inode", handoff)
        self.assertIn("terminal-abort failure", handoff)
        self.assertIn("PHYSICAL EXPERIMENT ONE REMAINS NO-GO", handoff)


if __name__ == "__main__":
    unittest.main()

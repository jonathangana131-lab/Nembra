#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_field_candidate_preflight.py"
spec = importlib.util.spec_from_file_location("field_candidate_preflight_export_options", MODULE_PATH)
preflight = importlib.util.module_from_spec(spec)
assert spec and spec.loader
sys.modules[spec.name] = preflight
spec.loader.exec_module(preflight)


class ExportOptionsCustodyTests(unittest.TestCase):
    def _valid_plist(self, path: Path) -> None:
        with path.open("wb") as handle:
            plistlib.dump({"method": "development"}, handle)

    def test_absolute_regular_plist_is_ready(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "ExportOptions.plist"
            self._valid_plist(path)
            self.assertTrue(preflight._export_options_are_ready(path))

    def test_relative_path_fails_closed(self):
        self.assertFalse(preflight._export_options_are_ready(Path("ExportOptions.plist")))

    def test_symlinked_parent_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            real_parent = root / "real"
            real_parent.mkdir()
            path = real_parent / "ExportOptions.plist"
            self._valid_plist(path)
            alias = root / "alias"
            try:
                alias.symlink_to(real_parent, target_is_directory=True)
            except (OSError, NotImplementedError) as error:
                self.skipTest(f"symlink creation unavailable: {error}")
            self.assertFalse(preflight._export_options_are_ready(alias / path.name))

    def test_symlink_final_subject_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            real = root / "real.plist"
            self._valid_plist(real)
            alias = root / "ExportOptions.plist"
            try:
                alias.symlink_to(real)
            except (OSError, NotImplementedError) as error:
                self.skipTest(f"symlink creation unavailable: {error}")
            self.assertFalse(preflight._export_options_are_ready(alias))

    def test_fifo_subject_fails_closed_without_waiting_for_writer(self):
        if not hasattr(os, "mkfifo"):
            self.skipTest("FIFO creation unavailable")
        with tempfile.TemporaryDirectory() as temporary:
            fifo = Path(temporary) / "ExportOptions.plist"
            os.mkfifo(fifo, 0o600)
            self.assertFalse(preflight._export_options_are_ready(fifo))

    def test_empty_or_non_dictionary_plist_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            empty = root / "empty.plist"
            empty.touch()
            self.assertFalse(preflight._export_options_are_ready(empty))

            array = root / "array.plist"
            with array.open("wb") as handle:
                plistlib.dump(["development"], handle)
            self.assertFalse(preflight._export_options_are_ready(array))


if __name__ == "__main__":
    unittest.main()

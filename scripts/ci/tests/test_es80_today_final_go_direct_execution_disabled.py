#!/usr/bin/env python3
"""Reject direct execution and ordinary imported-builder authority on public Final GO surfaces."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest

CI_DIR = Path(__file__).resolve().parents[1]


class FinalGoDirectExecutionDisabledTests(unittest.TestCase):
    def assert_non_authorizing(self, filename: str) -> None:
        completed = subprocess.run(
            [sys.executable, str(CI_DIR / filename), "--help"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.assertEqual(completed.returncode, 2)
        self.assertEqual(completed.stdout, "")
        self.assertIn("non-authorizing", completed.stderr)
        self.assertIn("es80_today_final_go_hardened.py", completed.stderr)
        self.assertNotIn("TODAY Final GO record:", completed.stderr)

    def load_module(self, filename: str):
        path = CI_DIR / filename
        spec = importlib.util.spec_from_file_location(f"non_authorizing_{path.stem}", path)
        self.assertIsNotNone(spec)
        assert spec is not None
        self.assertIsNotNone(spec.loader)
        assert spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_historical_record_path_is_non_authorizing(self):
        self.assert_non_authorizing("es80_today_final_go_record.py")

    def test_public_foundation_path_is_non_authorizing(self):
        self.assert_non_authorizing("es80_today_final_go_foundation.py")

    def test_public_foundation_imported_builder_is_non_authorizing(self):
        foundation = self.load_module("es80_today_final_go_foundation.py")
        with self.assertRaisesRegex(
            foundation.FinalGoError,
            "public Final GO foundation builder is non-authorizing",
        ):
            foundation.build_final_go_record()


if __name__ == "__main__":
    unittest.main()

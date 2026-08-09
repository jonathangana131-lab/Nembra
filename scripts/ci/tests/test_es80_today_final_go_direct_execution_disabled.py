#!/usr/bin/env python3
"""Reject non-canonical Final GO execution/import authority surfaces."""
from __future__ import annotations

import importlib.util
import inspect
from pathlib import Path
import subprocess
import sys
import unittest

CI_DIR = Path(__file__).resolve().parents[1]


def load_public_foundation():
    path = CI_DIR / "es80_today_final_go_foundation.py"
    spec = importlib.util.spec_from_file_location("nembra_public_final_go_foundation", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load public Final GO foundation")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


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

    def test_historical_record_path_is_non_authorizing(self):
        self.assert_non_authorizing("es80_today_final_go_record.py")

    def test_public_foundation_path_is_non_authorizing(self):
        self.assert_non_authorizing("es80_today_final_go_foundation.py")

    def test_private_implementation_path_is_non_authorizing(self):
        self.assert_non_authorizing("_es80_today_final_go_foundation_impl.py")

    def test_imported_public_foundation_builder_is_non_authorizing(self):
        foundation = load_public_foundation()
        with self.assertRaisesRegex(
            foundation.FinalGoError,
            "public Final GO foundation builder is non-authorizing",
        ):
            foundation.build_final_go_record()

    def test_imported_public_foundation_publisher_is_non_authorizing(self):
        foundation = load_public_foundation()
        with self.assertRaisesRegex(
            foundation.FinalGoError,
            "public Final GO foundation publisher is non-authorizing",
        ):
            foundation.publish_record_no_replace()

    def test_public_foundation_retains_no_private_builder_capability(self):
        foundation = load_public_foundation()
        self.assertFalse(hasattr(foundation, "_impl"))
        self.assertFalse(hasattr(foundation, "_IMPL_PATH"))
        self.assertFalse(hasattr(foundation, "_git"))
        self.assertFalse(hasattr(foundation, "_trusted_xcode_subject"))
        self.assertFalse(hasattr(foundation, "_api_get_json"))
        leaked_private_functions = [
            name
            for name, value in vars(foundation).items()
            if inspect.isfunction(value)
            and value.__module__ == "nembra_today_final_go_foundation_impl"
        ]
        self.assertEqual(leaked_private_functions, [])
        self.assertEqual(foundation.RECIPE, "ES80-FINGERPRINT-v1")
        self.assertEqual(foundation.PROCEDURE, "V14")


if __name__ == "__main__":
    unittest.main()

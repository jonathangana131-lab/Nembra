#!/usr/bin/env python3
"""Reject direct execution of both public/legacy Final GO Python surfaces."""
from __future__ import annotations

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

    def test_historical_record_path_is_non_authorizing(self):
        self.assert_non_authorizing("es80_today_final_go_record.py")

    def test_public_foundation_path_is_non_authorizing(self):
        self.assert_non_authorizing("es80_today_final_go_foundation.py")


if __name__ == "__main__":
    unittest.main()

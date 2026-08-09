#!/usr/bin/env python3
import subprocess
import sys
from pathlib import Path
import unittest

LEGACY_ENTRYPOINT = Path(__file__).resolve().parents[1] / "es80_today_final_go_record.py"


class LegacyFinalGoEntrypointTests(unittest.TestCase):
    def test_direct_legacy_execution_is_fail_closed_before_argument_parsing(self):
        completed = subprocess.run(
            [sys.executable, str(LEGACY_ENTRYPOINT), "--help"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.assertEqual(completed.returncode, 2)
        self.assertEqual(completed.stdout, "")
        self.assertIn("legacy foundation entrypoint is non-authorizing", completed.stderr)
        self.assertIn("es80_today_final_go_hardened.py", completed.stderr)
        self.assertNotIn("TODAY Final GO record:", completed.stdout + completed.stderr)


if __name__ == "__main__":
    unittest.main()

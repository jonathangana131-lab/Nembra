#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest

CI_DIR = Path(__file__).resolve().parents[1]
LEGACY = CI_DIR / "es80_today_final_go_record.py"
FOUNDATION = CI_DIR / "es80_today_final_go_foundation.py"
HARDENED = CI_DIR / "es80_today_final_go_hardened.py"


class LegacyFinalGoEntrypointTests(unittest.TestCase):
    def test_legacy_direct_execution_fails_closed(self):
        completed = subprocess.run(
            [sys.executable, str(LEGACY), "--help"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.assertEqual(completed.returncode, 2)
        self.assertIn("legacy entrypoint disabled", completed.stderr)
        self.assertIn("es80_today_final_go_hardened.py", completed.stderr)
        self.assertNotIn("--trusted-xcode-run-id", completed.stdout + completed.stderr)

    def test_legacy_import_keeps_foundation_contract_for_hardened_composition(self):
        self.assertTrue(FOUNDATION.is_file())
        spec = importlib.util.spec_from_file_location("legacy_final_go", LEGACY)
        module = importlib.util.module_from_spec(spec)
        self.assertIsNotNone(spec)
        self.assertIsNotNone(spec.loader)
        spec.loader.exec_module(module)
        self.assertTrue(callable(module.build_final_go_record))
        self.assertTrue(callable(module._trusted_xcode_subject))
        self.assertEqual(module.RECIPE, "ES80-FINGERPRINT-v1")

    def test_hardened_entrypoint_remains_the_executable_authority(self):
        completed = subprocess.run(
            [sys.executable, str(HARDENED), "--help"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn("--trusted-xcode-run-id", completed.stdout)
        self.assertIn("--operator-attestation", completed.stdout)


if __name__ == "__main__":
    unittest.main()

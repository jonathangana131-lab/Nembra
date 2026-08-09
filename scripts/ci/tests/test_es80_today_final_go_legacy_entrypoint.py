#!/usr/bin/env python3
import importlib.util
import subprocess
import sys
from pathlib import Path
import unittest

LEGACY_ENTRYPOINT = Path(__file__).resolve().parents[1] / "es80_today_final_go_record.py"


def _load_legacy():
    spec = importlib.util.spec_from_file_location("legacy_final_go", LEGACY_ENTRYPOINT)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load legacy Final GO compatibility module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


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

    def test_imported_legacy_builder_is_fail_closed_before_authority_work(self):
        legacy = _load_legacy()
        self.assertFalse(hasattr(legacy, "_foundation"))
        with self.assertRaisesRegex(
            legacy.FinalGoError,
            "legacy Final GO compatibility builder is non-authorizing",
        ):
            legacy.build_final_go_record()


if __name__ == "__main__":
    unittest.main()

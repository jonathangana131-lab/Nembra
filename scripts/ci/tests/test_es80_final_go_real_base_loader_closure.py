#!/usr/bin/env python3
"""Runtime closure tests for the sealed Final-GO base-loader root.

Validation only. This test never installs, opens Bluetooth, talks to Tuya, maps a
DP, writes a command, or creates physical-result authority.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[3]
MODULE_PATH = ROOT / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_real_loader_closure", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class FinalGoRealBaseLoaderClosureTests(unittest.TestCase):
    def test_outer_real_checkout_loads_exact_generated_subject_base_blob(self):
        self.assertEqual(Path(module.__file__).resolve().parents[2], ROOT)

        # The inherited generated subject may legitimately carry a synthetic Git
        # filename because it was executed from a pinned blob. Production must not
        # use that filename as its filesystem authority root.
        synthetic_file = getattr(module.generated, "__file__", "")
        if isinstance(synthetic_file, str) and synthetic_file.startswith("git:"):
            self.assertNotEqual(Path(synthetic_file).resolve().parents[2], ROOT)

        base = module._load_generated_base_module_from_checkout()
        self.assertEqual(
            getattr(base, "__nembra_accepted_control_blob__", None),
            module.generated.PARENT_BASE_MODULE_GIT_BLOB,
        )
        source = subprocess.run(
            ["/usr/bin/git", "-C", str(ROOT), "rev-parse", "HEAD"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env={"PATH": "/usr/bin:/bin", "GIT_NO_REPLACE_OBJECTS": "1"},
        ).stdout.strip().lower()
        self.assertRegex(source, r"^[0-9a-f]{40}(?:[0-9a-f]{24})?$")
        self.assertEqual(getattr(base, "__nembra_accepted_control_source__", None), source)
        self.assertEqual(base.REPO, "jonathangana131-lab/Nembra")
        self.assertTrue(callable(base.api))

    def test_production_source_does_not_call_synthetic_generated_loader(self):
        source = MODULE_PATH.read_text(encoding="utf-8")
        self.assertIn("base = _load_generated_base_module_from_checkout()", source)
        self.assertNotIn("base = generated._load_base_module()", source)
        self.assertNotRegex(
            source,
            r"def build\([^)]*(?:base_module|get|authority_root|repo_root|checkout_root)",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

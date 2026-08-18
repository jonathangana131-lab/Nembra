#!/usr/bin/env python3
"""Exploit-positive runtime probe for the real Final-GO generated base loader.

SUCCESS means the unpatched production loader inherited by #3619 cannot resolve
its repository root from the synthetic git:<sha>:... module __file__ and therefore
cannot load the accepted base module when caller base injection is removed.

Validation only. No install, device, Bluetooth, telemetry, command, or physical
authority is created.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
MODULE_PATH = ROOT / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_real_loader_redteam", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class FinalGoRealBaseLoaderRootRedTeamTests(unittest.TestCase):
    def test_real_generated_loader_is_rooted_from_synthetic_module_file_and_fails(self):
        generated = module.generated
        synthetic_file = getattr(generated, "__file__", "")
        self.assertRegex(
            synthetic_file,
            r"^git:[0-9a-f]{40}(?:[0-9a-f]{24})?:scripts/ci/es80_authenticated_stationary_generated_subject_final_go\.py$",
        )

        # This is the exact root expression in the accepted generated-subject
        # module. Because __file__ is synthetic and relative, resolve() anchors it
        # beneath the real checkout, then parents[2] lands in a non-repository
        # git:<sha>:... subtree rather than ROOT.
        derived_root = Path(synthetic_file).resolve().parents[2]
        self.assertNotEqual(derived_root, ROOT)
        self.assertFalse((derived_root / ".git").exists())

        with self.assertRaises(module.generated.GeneratedSubjectGoError) as caught:
            generated._load_base_module()
        self.assertIn("parent Git custody failed", str(caught.exception))


if __name__ == "__main__":
    unittest.main(verbosity=2)

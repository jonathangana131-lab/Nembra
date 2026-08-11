#!/usr/bin/env python3
"""Expected-red contract for current vnode acceptance in ES80 Final-GO."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_private_review_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_current_vnode_gate", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("current private-review Final-GO module is unavailable")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

CURRENT_WORKFLOW = "Capture CocoaPods Vnode Attribute Current"
CURRENT_PATH = ".github/workflows/capture-cocoapods-vnode-attribute-current.yml"
RETIRED_WORKFLOW = "Capture CocoaPods Vnode Attribute Convergence"
RETIRED_PATH = ".github/workflows/capture-cocoapods-vnode-attribute-convergence.yml"


class FinalGoCurrentVnodeGateTests(unittest.TestCase):
    def test_final_go_generated_parent_requires_selected_current_vnode_gate(self) -> None:
        generated = MODULE.generated

        self.assertEqual(
            generated.VNODE_WORKFLOW,
            CURRENT_WORKFLOW,
            "Final-GO still names the retired vnode convergence workflow instead of the selected current gate",
        )
        self.assertEqual(
            generated.VNODE_WORKFLOW_PATH,
            CURRENT_PATH,
            "Final-GO still requires the retired vnode convergence workflow path",
        )
        self.assertIn(
            (CURRENT_WORKFLOW, CURRENT_PATH),
            generated.GENERATED_ACCEPTANCE_WORKFLOWS,
            "Final-GO software acceptance does not require the selected current vnode gate",
        )
        self.assertIn(
            CURRENT_PATH,
            generated.GENERATED_AUTHORITY_PATHS,
            "Final-GO candidate authority does not bind the selected current vnode workflow bytes",
        )
        self.assertNotIn(
            (RETIRED_WORKFLOW, RETIRED_PATH),
            generated.GENERATED_ACCEPTANCE_WORKFLOWS,
            "retired vnode convergence acceptance must not remain promotable",
        )
        self.assertNotIn(
            RETIRED_PATH,
            generated.GENERATED_AUTHORITY_PATHS,
            "retired vnode convergence path must not remain a candidate authority prerequisite",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

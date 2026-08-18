#!/usr/bin/env python3
from __future__ import annotations

import ast
import importlib.util
import inspect
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_generated_subject_final_go.py"
SPEC = importlib.util.spec_from_file_location("generated_subject_final_go_workflow_gates", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load generated-subject Final-GO module")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class GeneratedSubjectWorkflowGateTests(unittest.TestCase):
    def test_exact_generated_workflow_names_and_paths_are_release_authority(self) -> None:
        self.assertEqual(
            MODULE.GENERATED_ACCEPTANCE_WORKFLOWS,
            (
                (
                    "Capture CocoaPods Build Subject Authority",
                    ".github/workflows/capture-cocoapods-build-subject-redteam.yml",
                ),
                (
                    "Capture CocoaPods Vnode Attribute Convergence",
                    ".github/workflows/capture-cocoapods-vnode-attribute-convergence.yml",
                ),
            ),
        )
        for _, path in MODULE.GENERATED_ACCEPTANCE_WORKFLOWS:
            self.assertIn(path, MODULE.GENERATED_AUTHORITY_PATHS)

    def test_final_build_enters_workflow_requirements_before_parent_build(self) -> None:
        tree = ast.parse(inspect.getsource(MODULE.build))
        with_nodes = [node for node in ast.walk(tree) if isinstance(node, ast.With)]
        self.assertEqual(len(with_nodes), 1)
        context_calls = [
            item.context_expr.func.id
            for item in with_nodes[0].items
            if isinstance(item.context_expr, ast.Call)
            and isinstance(item.context_expr.func, ast.Name)
        ]
        self.assertIn("_candidate_workflow_requirements", context_calls)
        self.assertIn("_parent_extensions", context_calls)

    def test_candidate_contract_requires_vnode_attribute_and_real_macos_evidence(self) -> None:
        source = inspect.getsource(MODULE.candidate_generated_authority)
        for required in (
            "KQ_NOTE_ATTRIB",
            "_ensure_fd_budget",
            "_require_real_checkout_ancestry",
            "Real macOS chmod vnode evidence",
            "macos-15",
        ):
            self.assertIn(required, source)

    def test_final_record_requires_generated_workflow_acceptance(self) -> None:
        source = inspect.getsource(MODULE.build)
        self.assertIn("requiredGeneratedBuildWorkflowAcceptance", source)
        self.assertIn("Final-GO record did not retain exact generated-build workflow acceptance", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)

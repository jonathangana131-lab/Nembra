#!/usr/bin/env python3
"""Expected-red coherent-generation test for #2709 exact production helper."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
HELPER_PATH = REPOSITORY / "Scripts" / "capture_cocoapods_generated_build_subject.py"


def load_helper():
    spec = importlib.util.spec_from_file_location("nembra_2709_cross_tree_helper", HELPER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load generated-build helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class GeneratedCrossTreeCoherenceTests(unittest.TestCase):
    def test_same_size_pods_mutation_between_tree_witnesses_is_rejected(self) -> None:
        helper = load_helper()
        with tempfile.TemporaryDirectory(prefix="nembra-2709-cross-tree-") as temporary:
            root = Path(temporary)
            lockfile = root / "Podfile.lock"
            pods = root / "Pods"
            workspace = root / "NembraCapture.xcworkspace"
            support = pods / "Target Support Files/Pods-NembraCapture"
            support.mkdir(parents=True)
            workspace.mkdir()
            lockfile.write_text("PODS:\n  - Example (1.0)\n", encoding="utf-8")
            generated = support / "Pods-NembraCapture.debug.xcconfig"
            generated.write_text("A\n", encoding="utf-8")
            (workspace / "contents.xcworkspacedata").write_text("workspace\n", encoding="utf-8")

            original = helper._tree_fingerprint
            calls = 0

            def mutate_after_pods(path: Path, *, repository_root: Path) -> str:
                nonlocal calls
                value = original(path, repository_root=repository_root)
                calls += 1
                if calls == 1:
                    # The first tree witness has already passed all of its local
                    # rechecks. Change its bytes without changing file size before
                    # the workspace witness is taken.
                    generated.write_text("B\n", encoding="utf-8")
                return value

            with mock.patch.object(helper, "_tree_fingerprint", side_effect=mutate_after_pods):
                with self.assertRaises(
                    helper.GeneratedBuildSubjectError,
                    msg="combined subject returned authority for a hybrid Pods/workspace generation",
                ):
                    helper.build_subject(lockfile=lockfile, pods=pods, workspace=workspace)


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Production regression for one coherent lock + Pods + workspace generation."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
HELPER_PATH = REPOSITORY / "Scripts" / "capture_cocoapods_generated_build_subject.py"


def load_helper():
    spec = importlib.util.spec_from_file_location("nembra_coherent_generation_helper", HELPER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load generated-build helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fixture(root: Path) -> tuple[Path, Path, Path, Path]:
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
    return lockfile, pods, workspace, generated


class GeneratedCrossTreeCoherenceTests(unittest.TestCase):
    def test_stable_generation_is_deterministic(self) -> None:
        helper = load_helper()
        with tempfile.TemporaryDirectory(prefix="nembra-coherent-generation-") as temporary:
            lockfile, pods, workspace, _ = fixture(Path(temporary))
            first = helper.build_subject(lockfile=lockfile, pods=pods, workspace=workspace)
            second = helper.build_subject(lockfile=lockfile, pods=pods, workspace=workspace)
            self.assertRegex(first, r"^[0-9a-f]{64}$")
            self.assertEqual(first, second)

    def test_same_size_pods_mutation_between_tree_witnesses_is_rejected(self) -> None:
        helper = load_helper()
        with tempfile.TemporaryDirectory(prefix="nembra-coherent-generation-") as temporary:
            lockfile, pods, workspace, generated = fixture(Path(temporary))
            original = helper._tree_fingerprint
            calls = 0

            def mutate_after_pods(path: Path, *, repository_root: Path) -> str:
                nonlocal calls
                value = original(path, repository_root=repository_root)
                calls += 1
                if calls == 1:
                    # Preserve size while changing bytes after the Pods local pass
                    # has already accepted its own snapshot but before workspace.
                    generated.write_text("B\n", encoding="utf-8")
                return value

            with mock.patch.object(helper, "_tree_fingerprint", side_effect=mutate_after_pods):
                with self.assertRaises(
                    helper.GeneratedBuildSubjectError,
                    msg="combined subject returned authority for a hybrid Pods/workspace generation",
                ) as error:
                    helper.build_subject(lockfile=lockfile, pods=pods, workspace=workspace)
            self.assertIn("combined lock/Pods/workspace fingerprint", str(error.exception))

    def test_same_size_lock_mutation_during_tree_fingerprints_is_rejected(self) -> None:
        helper = load_helper()
        with tempfile.TemporaryDirectory(prefix="nembra-coherent-generation-") as temporary:
            lockfile, pods, workspace, _ = fixture(Path(temporary))
            original = helper._tree_fingerprint
            calls = 0

            def mutate_lock_after_first_tree(path: Path, *, repository_root: Path) -> str:
                nonlocal calls
                value = original(path, repository_root=repository_root)
                calls += 1
                if calls == 1:
                    original_bytes = lockfile.read_bytes()
                    replacement = original_bytes.replace(b"Example", b"Changed")
                    self.assertEqual(len(original_bytes), len(replacement))
                    lockfile.write_bytes(replacement)
                return value

            with mock.patch.object(helper, "_tree_fingerprint", side_effect=mutate_lock_after_first_tree):
                with self.assertRaises(helper.GeneratedBuildSubjectError):
                    helper.build_subject(lockfile=lockfile, pods=pods, workspace=workspace)


if __name__ == "__main__":
    unittest.main(verbosity=2)

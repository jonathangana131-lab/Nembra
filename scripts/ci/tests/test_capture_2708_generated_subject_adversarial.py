#!/usr/bin/env python3
"""Expected-red adversarial tests for the current #2708 generated-build subject.

These tests intentionally add no production behavior. They require the attested
subject to describe one coherent Pods/workspace generation and to reject any
symlink target whose bytes are not part of a separately admitted custody root.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
HELPER_PATH = REPOSITORY / "Scripts" / "capture_cocoapods_build_subject.py"


def load_helper():
    spec = importlib.util.spec_from_file_location("capture_2708_build_subject", HELPER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("generated build-subject helper could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AttestedGeneratedSubjectAdversarialTests(unittest.TestCase):
    def roots(self, root: Path) -> tuple[Path, Path, Path]:
        pods = root / "Pods"
        workspace = root / "NembraCapture.xcworkspace"
        generated = pods / "Target Support Files/Pods-NembraCapture"
        generated.mkdir(parents=True)
        workspace.mkdir()
        xcconfig = generated / "Pods-NembraCapture.debug.xcconfig"
        xcconfig.write_text("A\n", encoding="utf-8")
        (pods / "Manifest.lock").write_text("LOCK\n", encoding="utf-8")
        (workspace / "contents.xcworkspacedata").write_text("workspace\n", encoding="utf-8")
        return pods, workspace, xcconfig

    def test_subject_rejects_cross_tree_hybrid_generation(self) -> None:
        helper = load_helper()
        with tempfile.TemporaryDirectory(prefix="nembra-2708-cross-tree-") as temporary:
            root = Path(temporary)
            pods, workspace, xcconfig = self.roots(root)
            original_tree_fingerprint = helper.tree_fingerprint
            calls = 0

            def mutate_after_first_tree(path: Path, **kwargs) -> str:
                nonlocal calls
                value = original_tree_fingerprint(path, **kwargs)
                calls += 1
                if calls == 1:
                    # Same-size mutation after the Pods tree has locally passed its
                    # checks, before the workspace witness is complete.
                    xcconfig.write_text("B\n", encoding="utf-8")
                return value

            with mock.patch.object(helper, "tree_fingerprint", side_effect=mutate_after_first_tree):
                with self.assertRaises(
                    helper.BuildSubjectError,
                    msg="helper returned authority for a hybrid Pods/workspace generation",
                ):
                    helper.build_subject_fingerprint(pods=pods, workspace=workspace)

    def test_arbitrary_external_symlink_target_bytes_are_not_unbound(self) -> None:
        helper = load_helper()
        with tempfile.TemporaryDirectory(prefix="nembra-2708-external-link-") as temporary:
            root = Path(temporary)
            pods, workspace, _ = self.roots(root)
            outside = root / "outside"
            outside.mkdir()
            target = outside / "GeneratedConfig.xcconfig"
            target.write_text("SETTING=A\n", encoding="utf-8")
            (pods / "ExternalConfig.xcconfig").symlink_to(target)

            try:
                reviewed = helper.build_subject_fingerprint(pods=pods, workspace=workspace)
            except helper.BuildSubjectError:
                return

            target.write_text("SETTING=B\n", encoding="utf-8")
            try:
                substituted = helper.build_subject_fingerprint(pods=pods, workspace=workspace)
            except helper.BuildSubjectError:
                return

            self.assertNotEqual(
                reviewed,
                substituted,
                "stable symlink text kept identical authority while unadmitted external target bytes changed",
            )

    def test_broken_generated_symlink_is_not_authoritative(self) -> None:
        helper = load_helper()
        with tempfile.TemporaryDirectory(prefix="nembra-2708-broken-link-") as temporary:
            root = Path(temporary)
            pods, workspace, _ = self.roots(root)
            (pods / "LateBoundConfig.xcconfig").symlink_to(root / "not-created-yet.xcconfig")
            with self.assertRaises(
                helper.BuildSubjectError,
                msg="broken generated symlink can acquire build-affecting bytes after review",
            ):
                helper.build_subject_fingerprint(pods=pods, workspace=workspace)


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Independent semantic review for the #2696 generated CocoaPods authority repair."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
SUBJECT_HELPER = REPOSITORY / "Scripts" / "capture_cocoapods_build_subject.py"
BUILD_GUARD = REPOSITORY / "Scripts" / "capture_tuya_private_input_build_guard.py"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class GeneratedSubjectAdversarialReviewTests(unittest.TestCase):
    def test_subject_rejects_cross_tree_generation_change(self) -> None:
        helper = load_module(SUBJECT_HELPER, "nembra_cocoapods_subject_review")
        with tempfile.TemporaryDirectory(prefix="nembra-cocoapods-cross-tree-review-") as temporary:
            root = Path(temporary)
            lockfile = root / "Podfile.lock"
            pods = root / "Pods"
            workspace = root / "NembraCapture.xcworkspace"
            generated = pods / "Target Support Files/Pods-NembraCapture"
            generated.mkdir(parents=True)
            workspace.mkdir()
            lockfile.write_text("PODS:\n  - Example (1.0)\n", encoding="utf-8")
            xcconfig = generated / "Pods-NembraCapture.debug.xcconfig"
            xcconfig.write_text("A\n", encoding="utf-8")
            (workspace / "contents.xcworkspacedata").write_text("workspace\n", encoding="utf-8")

            original_tree_fingerprint = helper.provenance._tree_fingerprint
            call_count = 0

            def mutate_after_pods(root_path: Path) -> str:
                nonlocal call_count
                result = original_tree_fingerprint(root_path)
                call_count += 1
                if call_count == 1:
                    # Mutate the already-hashed Pods generation before the workspace
                    # witness finishes. A coherent subject must reject the hybrid pair.
                    xcconfig.write_text("B\n", encoding="utf-8")
                return result

            with mock.patch.object(helper.provenance, "_tree_fingerprint", side_effect=mutate_after_pods):
                with self.assertRaises(
                    helper.GeneratedSubjectError,
                    msg="subject returned authority for a hybrid Pods/workspace generation",
                ):
                    helper.subject_digest(lockfile=lockfile, pods=pods, workspace=workspace)

    def test_build_window_watch_set_contains_generated_tree_members(self) -> None:
        guard = load_module(BUILD_GUARD, "nembra_build_guard_review")
        with tempfile.TemporaryDirectory(prefix="nembra-cocoapods-watch-review-") as temporary:
            root = Path(temporary)
            lockfile = root / "Podfile.lock"
            lockfile.write_text("LOCK\n", encoding="utf-8")

            security_podspec = root / "LocalSecrets/TuyaSDK/ThingSmartCryption.podspec"
            security_build = root / "LocalSecrets/TuyaSDK/Build"
            identity_podspec = root / "LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec"
            identity_sources = root / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig"
            security_build.mkdir(parents=True)
            identity_sources.mkdir(parents=True)
            security_podspec.write_text("podspec\n", encoding="utf-8")
            identity_podspec.write_text("podspec\n", encoding="utf-8")
            (security_build / "libThingSmartCryption.a").write_bytes(b"sdk")
            (identity_sources / "Identity.swift").write_text("identity\n", encoding="utf-8")

            pods = root / "Pods"
            workspace = root / "NembraCapture.xcworkspace"
            generated = pods / "Target Support Files/Pods-NembraCapture"
            generated.mkdir(parents=True)
            workspace.mkdir()
            xcconfig = generated / "Pods-NembraCapture.debug.xcconfig"
            workspace_data = workspace / "contents.xcworkspacedata"
            xcconfig.write_text("SETTING=A\n", encoding="utf-8")
            workspace_data.write_text("workspace\n", encoding="utf-8")

            inputs = guard.PrivateInputs(
                lockfile=lockfile,
                security_podspec=security_podspec,
                security_build=security_build,
                identity_podspec=identity_podspec,
                identity_sources=identity_sources,
            )
            watched = set(guard._watch_paths(inputs))
            for required in (pods, generated, xcconfig, workspace, workspace_data):
                self.assertIn(required, watched, f"generated build input is not under vnode custody: {required}")

            before = inputs.generation_snapshot()
            xcconfig.write_text("SETTING=B\n", encoding="utf-8")
            after = inputs.generation_snapshot()
            self.assertNotEqual(before, after, "generated mutation did not change the guarded generation witness")


if __name__ == "__main__":
    unittest.main(verbosity=2)

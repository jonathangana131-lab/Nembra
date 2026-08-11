#!/usr/bin/env python3
"""Adversarial regression for the converged generated CocoaPods subject.

The production helper must preserve one coherent lock+Pods+workspace witness while
still admitting CocoaPods' canonical local-path links only into the two private
Tuya roots that are independently under private-input provenance/build custody.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
HELPER_PATH = REPOSITORY / "Scripts/capture_cocoapods_build_subject.py"

spec = importlib.util.spec_from_file_location("capture_cocoapods_converged_subject", HELPER_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError("could not load converged CocoaPods build-subject helper")
helper = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = helper
spec.loader.exec_module(helper)


class ConvergedCocoaPodsSubjectTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-cocoapods-converged-")
        self.root = Path(self.temporary.name)
        self.lock = self.root / "Podfile.lock"
        self.lock.write_text("PODS:\n  - ThingSmartHomeKit (7.8.0)\n", encoding="utf-8")
        self.pods = self.root / "Pods"
        support = self.pods / "Target Support Files/Pods-NembraCapture"
        support.mkdir(parents=True)
        self.generated = support / "Pods-NembraCapture.debug.xcconfig"
        self.generated.write_text("SETTING = REVIEWED\n", encoding="utf-8")
        self.workspace = self.root / "NembraCapture.xcworkspace"
        self.workspace.mkdir()
        (self.workspace / "contents.xcworkspacedata").write_text("<Workspace/>\n", encoding="utf-8")

        self.private_sdk = self.root / "LocalSecrets/TuyaSDK"
        (self.private_sdk / "Build").mkdir(parents=True)
        (self.private_sdk / "ThingSmartCryption.podspec").write_text("private sdk\n", encoding="utf-8")
        (self.private_sdk / "Build/libThingSmartCryption.a").write_bytes(b"private")
        self.private_identity = self.root / "LocalSecrets/TuyaRuntime"
        identity_sources = self.private_identity / "Sources/NembraTuyaPrivateConfig"
        identity_sources.mkdir(parents=True)
        (self.private_identity / "NembraTuyaPrivateConfig.podspec").write_text("private identity\n", encoding="utf-8")
        (identity_sources / "Identity.swift").write_text("let configured = true\n", encoding="utf-8")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def digest(self) -> str:
        return helper.subject_digest(
            lockfile=self.lock,
            pods=self.pods,
            workspace=self.workspace,
        )

    def test_stable_subject_is_deterministic(self) -> None:
        self.assertEqual(self.digest(), self.digest())

    def test_canonical_local_path_pod_symlinks_are_admitted(self) -> None:
        (self.pods / "ThingSmartCryption").symlink_to(self.private_sdk)
        (self.pods / "NembraTuyaPrivateConfig").symlink_to(self.private_identity)
        first = self.digest()
        second = self.digest()
        self.assertRegex(first, r"^[0-9a-f]{64}$")
        self.assertEqual(first, second)

    def test_unprovenanced_external_symlink_is_rejected(self) -> None:
        outside = self.root / "UnreviewedGeneratorOutput"
        outside.mkdir()
        (outside / "Config.xcconfig").write_text("HOSTILE = 1\n", encoding="utf-8")
        (self.pods / "Unreviewed").symlink_to(outside)
        with self.assertRaisesRegex(helper.GeneratedSubjectError, "escapes"):
            self.digest()

    def test_broken_generated_symlink_is_rejected(self) -> None:
        (self.pods / "LateBound").symlink_to(self.root / "does-not-exist")
        with self.assertRaisesRegex(helper.GeneratedSubjectError, "broken|unavailable"):
            self.digest()

    def test_cross_tree_generation_change_is_rejected(self) -> None:
        original = helper._tree_fingerprint
        mutated = False

        def fingerprint(root: Path, *, allowed_roots):
            nonlocal mutated
            result = original(root, allowed_roots=allowed_roots)
            if root == self.pods and not mutated:
                mutated = True
                self.generated.write_text("SETTING = MUTATED_BETWEEN_TREES\n", encoding="utf-8")
            return result

        with mock.patch.object(helper, "_tree_fingerprint", side_effect=fingerprint):
            with self.assertRaisesRegex(helper.GeneratedSubjectError, "changed"):
                self.digest()
        self.assertTrue(mutated, "fixture must mutate after the Pods fingerprint and before final pair revalidation")


if __name__ == "__main__":
    unittest.main(verbosity=2)

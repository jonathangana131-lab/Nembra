#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
HELPER = REPOSITORY / "Scripts/capture_cocoapods_generated_build_subject.py"


def load_helper():
    spec = importlib.util.spec_from_file_location("nembra_generated_subject_symlink_test", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load generated-build subject helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class GeneratedSymlinkAuthorityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-generated-symlink-")
        self.root = Path(self.temporary.name)
        self.lockfile = self.root / "Podfile.lock"
        self.lockfile.write_text("PODS:\n  - Example (1.0)\n", encoding="utf-8")
        self.pods = self.root / "Pods"
        self.workspace = self.root / "NembraCapture.xcworkspace"
        self.pods.mkdir()
        self.workspace.mkdir()
        (self.pods / "Target").mkdir()
        (self.pods / "Target/input.xcconfig").write_text("VALUE = ACCEPTED\n", encoding="utf-8")
        (self.workspace / "contents.xcworkspacedata").write_text("accepted\n", encoding="utf-8")

        self.private_sdk = self.root / "LocalSecrets/TuyaSDK"
        self.private_runtime = self.root / "LocalSecrets/TuyaRuntime"
        self.private_sdk.mkdir(parents=True)
        self.private_runtime.mkdir(parents=True)
        (self.private_sdk / "private.a").write_bytes(b"sdk")
        (self.private_runtime / "identity.swift").write_text("private identity\n", encoding="utf-8")
        self.helper = load_helper()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def subject(self) -> str:
        return self.helper.build_subject(
            lockfile=self.lockfile,
            pods=self.pods,
            workspace=self.workspace,
        )

    def test_internal_generated_symlink_is_allowed_and_bound(self) -> None:
        os.symlink("Target", self.pods / "InternalLink")
        first = self.subject()
        self.assertRegex(first, r"^[0-9a-f]{64}$")
        os.unlink(self.pods / "InternalLink")
        os.symlink("Target/input.xcconfig", self.pods / "InternalLink")
        second = self.subject()
        self.assertNotEqual(first, second)

    def test_capture_private_pod_symlinks_are_allowed(self) -> None:
        os.symlink("../LocalSecrets/TuyaSDK", self.pods / "ThingSmartCryption")
        os.symlink("../LocalSecrets/TuyaRuntime", self.pods / "NembraTuyaPrivateConfig")
        self.assertRegex(self.subject(), r"^[0-9a-f]{64}$")

    def test_symlink_to_unprovenanced_external_repo_path_is_rejected(self) -> None:
        untrusted = self.root / "MutableUnreviewedInput"
        untrusted.mkdir()
        (untrusted / "payload.xcconfig").write_text("ATTACK = 1\n", encoding="utf-8")
        os.symlink("../MutableUnreviewedInput", self.pods / "Escape")
        with self.assertRaises(self.helper.GeneratedBuildSubjectError):
            self.subject()

    def test_broken_generated_symlink_is_rejected(self) -> None:
        os.symlink("../missing-build-input", self.pods / "Broken")
        with self.assertRaises(self.helper.GeneratedBuildSubjectError):
            self.subject()


if __name__ == "__main__":
    unittest.main(verbosity=2)

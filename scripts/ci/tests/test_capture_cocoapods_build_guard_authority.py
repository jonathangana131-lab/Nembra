#!/usr/bin/env python3
"""Adversarial custody tests for generated CocoaPods authority at build admission."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
GUARD_PATH = REPOSITORY / "Scripts/capture_tuya_private_input_build_guard.py"

spec = importlib.util.spec_from_file_location("capture_build_guard_authority", GUARD_PATH)
assert spec is not None and spec.loader is not None
guard = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = guard
spec.loader.exec_module(guard)

AUTHORITY_ENV = "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256"


class QuietBackend:
    def register(self, descriptor: int) -> None:
        del descriptor

    def events(self, timeout: float):
        del timeout
        return ()

    def close(self) -> None:
        pass


class FinishedProcess:
    returncode = 0

    def poll(self):
        return 0

    def terminate(self) -> None:
        pass

    def wait(self, timeout=None):
        del timeout
        return 0

    def kill(self) -> None:
        pass


class CocoaPodsBuildGuardAuthorityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-cocoapods-build-authority-")
        self.root = Path(self.temporary.name)
        self.lock = self.root / "Podfile.lock"
        self.lock.write_text("PODS:\n  - ThingSmartHomeKit (7.8.0)\n", encoding="utf-8")

        self.security_podspec = self.root / "ThingSmartCryption.podspec"
        self.security_podspec.write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
        self.security_build = self.root / "SecurityBuild"
        self.security_build.mkdir()
        (self.security_build / "libThingSmartCryption.a").write_bytes(b"security")

        self.identity_podspec = self.root / "NembraTuyaPrivateConfig.podspec"
        self.identity_podspec.write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
        self.identity_sources = self.root / "IdentitySources"
        self.identity_sources.mkdir()
        (self.identity_sources / "Identity.swift").write_text("let configured = true\n", encoding="utf-8")

        self.pods = self.root / "Pods"
        generated_dir = self.pods / "Target Support Files/Pods-NembraCapture"
        generated_dir.mkdir(parents=True)
        self.generated = generated_dir / "Pods-NembraCapture.debug.xcconfig"
        self.generated.write_text("SETTING = REVIEWED\n", encoding="utf-8")

        self.workspace = self.root / "NembraCapture.xcworkspace"
        self.workspace.mkdir()
        (self.workspace / "contents.xcworkspacedata").write_text("REVIEWED\n", encoding="utf-8")

        self.inputs = guard.PrivateInputs(
            lockfile=self.lock,
            security_podspec=self.security_podspec,
            security_build=self.security_build,
            identity_podspec=self.identity_podspec,
            identity_sources=self.identity_sources,
        )
        self.accepted = guard.generated_subject.subject_digest(
            lockfile=self.lock,
            pods=self.pods,
            workspace=self.workspace,
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_guarded(self, popen):
        return guard.run_guarded_build(
            self.inputs,
            ["fake-xcodebuild"],
            backend_factory=QuietBackend,
            popen_factory=popen,
        )

    def test_exact_externally_accepted_subject_is_admitted(self) -> None:
        with mock.patch.dict(os.environ, {AUTHORITY_ENV: self.accepted}, clear=False):
            self.assertEqual(self.run_guarded(lambda _command: FinishedProcess()), 0)

    def test_missing_external_generated_subject_authority_fails_before_child(self) -> None:
        spawned = False

        def popen(_command):
            nonlocal spawned
            spawned = True
            return FinishedProcess()

        with mock.patch.dict(os.environ, {AUTHORITY_ENV: ""}, clear=False):
            with self.assertRaisesRegex(guard.BuildGuardError, "must carry the exact reviewed"):
                self.run_guarded(popen)
        self.assertFalse(spawned)

    def test_subject_changed_after_bootstrap_fails_before_child(self) -> None:
        self.generated.write_text("SETTING = SUBSTITUTED\n", encoding="utf-8")
        spawned = False

        def popen(_command):
            nonlocal spawned
            spawned = True
            return FinishedProcess()

        with mock.patch.dict(os.environ, {AUTHORITY_ENV: self.accepted}, clear=False):
            with self.assertRaisesRegex(guard.BuildGuardError, "no longer matches externally accepted authority"):
                self.run_guarded(popen)
        self.assertFalse(spawned)

    def test_swap_after_digest_before_baseline_completion_is_rejected(self) -> None:
        """The digest check itself cannot be followed by an attacker-selected baseline."""
        spawned = False
        original_digest = guard.PrivateInputs.generated_subject_digest

        def digest_then_swap(instance):
            digest = original_digest(instance)
            self.generated.write_text("SETTING = SWAPPED-AFTER-AUTHORITY\n", encoding="utf-8")
            return digest

        def popen(_command):
            nonlocal spawned
            spawned = True
            return FinishedProcess()

        with mock.patch.dict(os.environ, {AUTHORITY_ENV: self.accepted}, clear=False):
            with mock.patch.object(
                guard.PrivateInputs,
                "generated_subject_digest",
                autospec=True,
                side_effect=digest_then_swap,
            ):
                with self.assertRaisesRegex(guard.BuildGuardError, "changed while externally accepted"):
                    self.run_guarded(popen)
        self.assertFalse(spawned, "inter-sample substitution must fail before xcodebuild admission")


if __name__ == "__main__":
    unittest.main(verbosity=2)

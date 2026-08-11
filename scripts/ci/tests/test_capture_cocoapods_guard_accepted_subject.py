#!/usr/bin/env python3
"""Require xcodebuild admission to remain bound to the externally accepted generated subject."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
GUARD_PATH = REPOSITORY / "Scripts" / "capture_tuya_private_input_build_guard.py"

spec = importlib.util.spec_from_file_location("capture_generated_subject_admission_guard", GUARD_PATH)
assert spec is not None and spec.loader is not None
guard = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = guard
spec.loader.exec_module(guard)


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


class AcceptedGeneratedSubjectAdmissionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-cocoapods-admission-")
        self.root = Path(self.temporary.name)
        self.lock = self.root / "Podfile.lock"
        self.lock.write_text("PODS:\n  - ThingSmartHomeKit (7.8.0)\n", encoding="utf-8")
        self.security_podspec = self.root / "ThingSmartCryption.podspec"
        self.security_podspec.write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
        self.security_build = self.root / "SecurityBuild"
        self.security_build.mkdir()
        (self.security_build / "lib.a").write_bytes(b"security")
        self.identity_podspec = self.root / "Identity.podspec"
        self.identity_podspec.write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
        self.identity_sources = self.root / "IdentitySources"
        self.identity_sources.mkdir()
        (self.identity_sources / "Identity.swift").write_text("let configured = true\n", encoding="utf-8")
        self.pods = self.root / "Pods"
        generated_parent = self.pods / "Target Support Files" / "Pods-NembraCapture"
        generated_parent.mkdir(parents=True)
        self.generated = generated_parent / "Pods-NembraCapture.debug.xcconfig"
        self.generated.write_text("FLAG=REVIEWED\n", encoding="utf-8")
        self.workspace = self.root / "NembraCapture.xcworkspace"
        self.workspace.mkdir()
        (self.workspace / "contents.xcworkspacedata").write_text("REVIEWED\n", encoding="utf-8")
        self.accepted = guard.generated_subject.subject_digest(
            lockfile=self.lock,
            pods=self.pods,
            workspace=self.workspace,
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def inputs(self):
        return guard.PrivateInputs(
            lockfile=self.lock,
            security_podspec=self.security_podspec,
            security_build=self.security_build,
            identity_podspec=self.identity_podspec,
            identity_sources=self.identity_sources,
        )

    def run_with_accepted_environment(self, popen):
        with mock.patch.dict(
            os.environ,
            {"NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256": self.accepted},
            clear=False,
        ):
            return guard.run_guarded_build(
                self.inputs(),
                ["fake-xcodebuild"],
                backend_factory=QuietBackend,
                popen_factory=popen,
            )

    def test_post_bootstrap_substitution_is_rejected_before_child_start(self) -> None:
        self.generated.write_text("FLAG=SUBSTITUTED\n", encoding="utf-8")
        spawned = False

        def popen(_command):
            nonlocal spawned
            spawned = True
            return FinishedProcess()

        with self.assertRaisesRegex(guard.BuildGuardError, "accepted.*generated|generated.*accepted"):
            self.run_with_accepted_environment(popen)
        self.assertFalse(spawned, "xcodebuild must not start from a generated subject that differs from accepted authority")

    def test_unchanged_accepted_subject_is_admitted(self) -> None:
        self.assertEqual(
            self.run_with_accepted_environment(lambda _command: FinishedProcess()),
            0,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

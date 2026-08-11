#!/usr/bin/env python3
"""Adversarial unit coverage for CocoaPods generated-input build-window custody."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
from types import SimpleNamespace
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
GUARD_PATH = REPOSITORY / "Scripts/capture_tuya_private_input_build_guard.py"


def load_guard():
    spec = importlib.util.spec_from_file_location("capture_build_guard_under_test", GUARD_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load Capture build guard")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


guard = load_guard()


class QuietBackend:
    def __init__(self) -> None:
        self.descriptors: list[int] = []
        self.closed = False

    def register(self, descriptor: int) -> None:
        self.descriptors.append(descriptor)

    def events(self, timeout: float):
        return []

    def close(self) -> None:
        self.closed = True


class MutatingBackend(QuietBackend):
    def __init__(self, target: Path) -> None:
        super().__init__()
        self.target = target
        self.calls = 0

    def events(self, timeout: float):
        self.calls += 1
        if self.calls == 1:
            # The first zero-time poll is the pre-spawn race gate.
            return []
        if self.calls == 2:
            self.target.write_text("SUBSTITUTED_DURING_BUILD\n", encoding="utf-8")
            return [SimpleNamespace(ident=self.descriptors[-1], fflags=0x2)]
        return []


class CocoaPodsBuildWindowCustodyTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="nembra-build-custody-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

        (self.root / "Podfile.lock").write_text("LOCK\n", encoding="utf-8")
        generated = self.root / "Pods/Target Support Files/Pods-NembraCapture"
        generated.mkdir(parents=True)
        self.generated_file = generated / "Pods-NembraCapture.debug.xcconfig"
        self.generated_file.write_text("REVIEWED_GRAPH\n", encoding="utf-8")
        workspace = self.root / "NembraCapture.xcworkspace"
        workspace.mkdir()
        (workspace / "contents.xcworkspacedata").write_text("REVIEWED_GRAPH\n", encoding="utf-8")

        security_build = self.root / "LocalSecrets/TuyaSDK/Build"
        security_build.mkdir(parents=True)
        security_podspec = self.root / "LocalSecrets/TuyaSDK/ThingSmartCryption.podspec"
        security_podspec.write_text("security\n", encoding="utf-8")
        (security_build / "libThingSmartCryption.a").write_bytes(b"private-security-sdk")

        identity_sources = self.root / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig"
        identity_sources.mkdir(parents=True)
        identity_podspec = self.root / "LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec"
        identity_podspec.write_text("identity\n", encoding="utf-8")
        (identity_sources / "Identity.swift").write_text("private identity\n", encoding="utf-8")

        self.inputs = guard.PrivateInputs(
            lockfile=self.root / "Podfile.lock",
            security_podspec=security_podspec,
            security_build=security_build,
            identity_podspec=identity_podspec,
            identity_sources=identity_sources,
        )
        self.accepted_digest = guard.cocoapods_build_subject.fingerprint(self.root)
        self.subject = guard.CocoaPodsBuildSubject(
            root=self.root,
            expected_digest=self.accepted_digest,
        )

    def test_final_go_environment_reconstructs_exact_generated_subject(self) -> None:
        with mock.patch.dict(
            os.environ,
            {"NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256": self.accepted_digest.upper()},
            clear=False,
        ):
            subject = guard._build_subject_from_final_go_environment(self.inputs)
        self.assertEqual(subject.root, self.root)
        self.assertEqual(subject.expected_digest, self.accepted_digest)
        self.assertEqual(subject.snapshot(), self.accepted_digest)

    def test_changed_generated_subject_is_rejected_before_child_build(self) -> None:
        self.generated_file.write_text("SUBSTITUTED_BEFORE_BUILD\n", encoding="utf-8")
        with self.assertRaisesRegex(
            guard.BuildGuardError,
            "no longer matches Final GO authority",
        ):
            guard.run_guarded_build(
                self.inputs,
                [sys.executable, "-c", "raise SystemExit(0)"],
                build_subject=self.subject,
                backend_factory=QuietBackend,
            )

    def test_generated_mutation_event_terminates_guarded_build(self) -> None:
        backend = MutatingBackend(self.generated_file)
        with self.assertRaisesRegex(
            guard.BuildGuardError,
            "mutation was observed while xcodebuild was running",
        ):
            guard.run_guarded_build(
                self.inputs,
                [sys.executable, "-c", "import time; time.sleep(30)"],
                build_subject=self.subject,
                backend_factory=lambda: backend,
                poll_interval=0.001,
            )
        self.assertTrue(backend.closed)
        self.assertNotEqual(
            guard.cocoapods_build_subject.fingerprint(self.root),
            self.accepted_digest,
        )

    def test_generated_regular_files_and_directories_are_watched(self) -> None:
        paths = guard._generated_watch_paths(self.root)
        self.assertIn(self.root / "Pods", paths)
        self.assertIn(self.root / "NembraCapture.xcworkspace", paths)
        self.assertIn(self.generated_file, paths)

    def test_invalid_final_go_generated_subject_digest_fails_closed(self) -> None:
        with mock.patch.dict(
            os.environ,
            {"NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256": "not-a-digest"},
            clear=False,
        ):
            with self.assertRaisesRegex(guard.BuildGuardError, "Final GO did not provide"):
                guard._build_subject_from_final_go_environment(self.inputs)


if __name__ == "__main__":
    unittest.main(verbosity=2)

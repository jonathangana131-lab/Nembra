#!/usr/bin/env python3
"""Regression for external private-review HMAC at xcodebuild admission."""
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


def load_guard():
    spec = importlib.util.spec_from_file_location("capture_private_hmac_guard_under_test", GUARD_PATH)
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


class PrivateReviewHMACBuildGuardTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-private-hmac-guard-")
        self.root = Path(self.temporary.name).resolve()
        self.lockfile = self.root / "Podfile.lock"
        self.lockfile.write_text("LOCK\n", encoding="utf-8")

        self.security_build = self.root / "LocalSecrets/TuyaSDK/Build"
        self.security_build.mkdir(parents=True)
        self.security_podspec = self.security_build.parent / "ThingSmartCryption.podspec"
        self.security_podspec.write_text("security\n", encoding="utf-8")
        self.security_binary = self.security_build / "libThingSmartCryption.a"
        self.security_binary.write_bytes(b"REVIEWED-A")

        self.identity_root = self.root / "LocalSecrets/TuyaRuntime"
        self.identity_sources = self.identity_root / "Sources/NembraTuyaPrivateConfig"
        self.identity_sources.mkdir(parents=True)
        self.identity_podspec = self.identity_root / "NembraTuyaPrivateConfig.podspec"
        self.identity_podspec.write_text("identity\n", encoding="utf-8")
        self.identity_source = self.identity_sources / "Identity.swift"
        self.identity_source.write_text("private identity A\n", encoding="utf-8")
        self.private_review_key = self.identity_root / "PrivateReviewAuthority.key"
        self.private_review_key.write_bytes(bytes(range(32)))
        self.private_review_key.chmod(0o600)

        self.pods = self.root / "Pods"
        self.pods.mkdir()
        (self.pods / "generated.xcconfig").write_text("SETTING = A\n", encoding="utf-8")
        self.workspace = self.root / "NembraCapture.xcworkspace"
        self.workspace.mkdir()
        (self.workspace / "contents.xcworkspacedata").write_text("workspace\n", encoding="utf-8")

        self.inputs = guard.PrivateInputs(
            lockfile=self.lockfile,
            security_podspec=self.security_podspec,
            security_build=self.security_build,
            identity_podspec=self.identity_podspec,
            identity_sources=self.identity_sources,
            generated_pods=self.pods,
            generated_workspace=self.workspace,
            private_review_key=self.private_review_key,
        )
        self.accepted_generated = self.inputs.generated_build_subject()
        self.accepted_private_hmac = self.inputs.private_review_hmac()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def authority_environment(self):
        return mock.patch.dict(
            os.environ,
            {
                "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256": self.accepted_generated,
                "NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_REVIEW_HMAC_SHA256": self.accepted_private_hmac,
            },
            clear=False,
        )

    def test_exact_private_generation_passes_external_hmac_at_build_boundary(self) -> None:
        backend = QuietBackend()
        with self.authority_environment():
            result = guard.run_guarded_build(
                self.inputs,
                [sys.executable, "-c", "raise SystemExit(0)"],
                backend_factory=lambda: backend,
                poll_interval=0.001,
                require_accepted_generated_subject=True,
                require_accepted_private_review_hmac=True,
            )
        self.assertEqual(result, 0)
        self.assertTrue(backend.closed)

    def test_coherent_private_generation_replacement_fails_before_child_spawn(self) -> None:
        self.security_binary.write_bytes(b"SUBSTITUTED-B")
        self.identity_source.write_text("private identity B\n", encoding="utf-8")
        with self.authority_environment():
            with self.assertRaisesRegex(
                guard.BuildGuardError,
                "externally accepted review HMAC",
            ):
                guard.run_guarded_build(
                    self.inputs,
                    [sys.executable, "-c", "raise SystemExit(99)"],
                    backend_factory=QuietBackend,
                    popen_factory=mock.Mock(side_effect=AssertionError("child must not spawn")),
                    require_accepted_generated_subject=True,
                    require_accepted_private_review_hmac=True,
                )

    def test_private_review_key_replacement_fails_before_child_spawn(self) -> None:
        self.private_review_key.write_bytes(bytes(reversed(range(32))))
        self.private_review_key.chmod(0o600)
        with self.authority_environment():
            with self.assertRaisesRegex(
                guard.BuildGuardError,
                "externally accepted review HMAC",
            ):
                guard.run_guarded_build(
                    self.inputs,
                    [sys.executable, "-c", "raise SystemExit(99)"],
                    backend_factory=QuietBackend,
                    popen_factory=mock.Mock(side_effect=AssertionError("child must not spawn")),
                    require_accepted_generated_subject=True,
                    require_accepted_private_review_hmac=True,
                )

    def test_private_review_key_is_held_in_vnode_watch_set(self) -> None:
        paths = guard._watch_paths(self.inputs)
        self.assertIn(self.private_review_key, paths)
        self.assertIn(self.identity_root, paths)
        self.assertIn(self.root / "LocalSecrets", paths)
        self.assertIn(self.root, paths)

    def test_missing_external_hmac_fails_closed(self) -> None:
        with mock.patch.dict(
            os.environ,
            {"NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256": self.accepted_generated},
            clear=True,
        ):
            with self.assertRaisesRegex(
                guard.BuildGuardError,
                "NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_REVIEW_HMAC_SHA256",
            ):
                guard.run_guarded_build(
                    self.inputs,
                    [sys.executable, "-c", "raise SystemExit(99)"],
                    backend_factory=QuietBackend,
                    popen_factory=mock.Mock(side_effect=AssertionError("child must not spawn")),
                    require_accepted_generated_subject=True,
                    require_accepted_private_review_hmac=True,
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)

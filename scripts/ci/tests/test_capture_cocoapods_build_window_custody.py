#!/usr/bin/env python3
"""Regression coverage for accepted generated CocoaPods build-window custody."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
GUARD_PATH = REPOSITORY / "Scripts" / "capture_tuya_private_input_build_guard.py"

spec = importlib.util.spec_from_file_location("capture_tuya_private_input_build_guard_tested", GUARD_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError("build-window guard could not be loaded")
guard = importlib.util.module_from_spec(spec)
os.sys.modules[spec.name] = guard
spec.loader.exec_module(guard)


class CocoaPodsBuildWindowCustodyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-generated-window-")
        self.root = Path(self.temporary.name).resolve()
        self.lockfile = self.root / "Podfile.lock"
        self.lockfile.write_text("PODS:\n", encoding="utf-8")

        self.pods = self.root / "Pods"
        self.workspace = self.root / "NembraCapture.xcworkspace"
        self.sources = self.root / "Sources"
        self.pods.mkdir()
        self.workspace.mkdir()
        self.sources.mkdir()
        (self.pods / "Pods-NembraCapture.debug.xcconfig").write_text("A\n", encoding="utf-8")
        (self.workspace / "contents.xcworkspacedata").write_text("workspace\n", encoding="utf-8")
        self.link_target = self.sources / "Shared.swift"
        self.link_target.write_text("let value = 1\n", encoding="utf-8")
        (self.pods / "Shared.swift").symlink_to(self.link_target)

        private_sdk = self.root / "LocalSecrets/TuyaSDK"
        self.security_build = private_sdk / "Build"
        self.security_build.mkdir(parents=True)
        self.security_podspec = private_sdk / "ThingSmartCryption.podspec"
        self.security_podspec.write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
        (self.security_build / "libThingSmartCryption.a").write_bytes(b"security")

        private_identity = self.root / "LocalSecrets/TuyaRuntime"
        self.identity_sources = private_identity / "Sources/NembraTuyaPrivateConfig"
        self.identity_sources.mkdir(parents=True)
        self.identity_podspec = private_identity / "NembraTuyaPrivateConfig.podspec"
        self.identity_podspec.write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
        (self.identity_sources / "NembraTuyaPrivateIdentity.swift").write_text(
            "enum Identity { static let configured = true }\n",
            encoding="utf-8",
        )

        self.accepted = guard.generated_subject.fingerprint_subject(
            self.root,
            (self.pods, self.workspace),
        )
        self.inputs = guard.PrivateInputs(
            lockfile=self.lockfile,
            security_podspec=self.security_podspec,
            security_build=self.security_build,
            identity_podspec=self.identity_podspec,
            identity_sources=self.identity_sources,
            generated_repository_root=self.root,
            generated_pods=self.pods,
            generated_workspace=self.workspace,
            accepted_generated_subject_sha256=self.accepted,
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_generated_graph_and_resolved_symlink_target_are_vnode_watched(self) -> None:
        watched = set(guard._watch_paths(self.inputs))
        self.assertIn(self.pods.resolve(), watched)
        self.assertIn(self.workspace.resolve(), watched)
        self.assertIn(self.link_target.resolve(), watched)
        self.assertIn(self.link_target.parent.resolve(), watched)
        self.assertIn(self.root, watched)
        self.assertEqual(self.inputs.prove_accepted_generated_subject(), self.accepted)

    def test_resolved_symlink_target_substitution_invalidates_external_acceptance(self) -> None:
        self.link_target.write_text("let value = 2\n", encoding="utf-8")
        changed = self.inputs.generated_snapshot()
        self.assertNotEqual(changed, self.accepted)
        with self.assertRaisesRegex(
            guard.BuildGuardError,
            "no longer matches the externally accepted SHA-256",
        ):
            self.inputs.prove_accepted_generated_subject(changed)

    def test_generated_file_substitution_invalidates_external_acceptance(self) -> None:
        generated_file = self.pods / "Pods-NembraCapture.debug.xcconfig"
        generated_file.write_text("SUBSTITUTED\n", encoding="utf-8")
        with self.assertRaisesRegex(
            guard.BuildGuardError,
            "no longer matches the externally accepted SHA-256",
        ):
            self.inputs.prove_accepted_generated_subject()

    def test_physical_cli_requires_accepted_digest_to_survive_bootstrap_handoff(self) -> None:
        argv = [
            "--lockfile", str(self.lockfile),
            "--security-podspec", str(self.security_podspec),
            "--security-build", str(self.security_build),
            "--identity-podspec", str(self.identity_podspec),
            "--identity-sources", str(self.identity_sources),
            "--", "true",
        ]
        with mock.patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(
                guard.BuildGuardError,
                "must remain inherited from Final GO",
            ):
                guard._parse_args(argv)

        with mock.patch.dict(
            os.environ,
            {"NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_SUBJECT_SHA256": self.accepted.upper()},
            clear=True,
        ):
            parsed, command = guard._parse_args(argv)
        self.assertEqual(parsed.accepted_generated_subject_sha256, self.accepted)
        self.assertEqual(command, ["true"])
        self.assertEqual(parsed.generated_pods, self.pods)
        self.assertEqual(parsed.generated_workspace, self.workspace)


if __name__ == "__main__":
    unittest.main(verbosity=2)

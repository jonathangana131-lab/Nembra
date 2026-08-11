#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

REPOSITORY = Path(__file__).resolve().parents[3]
GUARD = REPOSITORY / "Scripts/capture_tuya_private_input_build_guard.py"
SPEC = importlib.util.spec_from_file_location("nembra_private_input_guard_redteam", GUARD)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load Capture field-build guard")
guard = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = guard
SPEC.loader.exec_module(guard)


class QuietBackend:
    def register(self, descriptor: int) -> None:
        del descriptor
    def events(self, timeout: float):
        del timeout
        return []
    def close(self) -> None:
        pass


class CompletedProcess:
    returncode = 0
    def poll(self): return 0
    def terminate(self) -> None: raise AssertionError("completed fake child must not be terminated")
    def wait(self, timeout=None): del timeout; return 0
    def kill(self) -> None: raise AssertionError("completed fake child must not be killed")


class PrivateInputAncestorRetargetTests(unittest.TestCase):
    def test_guard_rejects_localsecrets_ancestor_retarget_before_child_consumption(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-private-input-retarget-") as temporary:
            root = Path(temporary)
            accepted_secrets = root / "accepted-secrets"
            substituted_secrets = root / "substituted-secrets"

            for secrets, payload in ((accepted_secrets, "ACCEPTED"), (substituted_secrets, "SUBSTITUTED")):
                sdk = secrets / "TuyaSDK"
                build = sdk / "Build"
                build.mkdir(parents=True)
                (sdk / "ThingSmartCryption.podspec").write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
                (build / "payload.bin").write_text(payload, encoding="utf-8")

                identity = secrets / "TuyaRuntime"
                identity_sources = identity / "Sources/NembraTuyaPrivateConfig"
                identity_sources.mkdir(parents=True)
                (identity / "NembraTuyaPrivateConfig.podspec").write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
                (identity_sources / "NembraTuyaPrivateIdentity.swift").write_text(
                    f'enum PrivateIdentity {{ static let generation = "{payload}" }}\n',
                    encoding="utf-8",
                )

            local = root / "LocalSecrets"
            local.symlink_to(accepted_secrets, target_is_directory=True)
            sdk = local / "TuyaSDK"
            identity = local / "TuyaRuntime"
            identity_sources = identity / "Sources/NembraTuyaPrivateConfig"

            lockfile = root / "Podfile.lock"
            lockfile.write_text("PODS:\n  - Example (1.0)\n", encoding="utf-8")
            pods = root / "Pods"
            workspace = root / "NembraCapture.xcworkspace"
            pods.mkdir()
            workspace.mkdir()
            (pods / "generated.xcconfig").write_text("SETTING = ACCEPTED\n", encoding="utf-8")
            (workspace / "contents.xcworkspacedata").write_text("ACCEPTED\n", encoding="utf-8")

            # The converged generated-subject helper rejects a symlink at the
            # TuyaSDK/TuyaRuntime leaf itself, but it currently resolves through
            # a mutable LocalSecrets ancestor. This establishes the exact-current
            # accepted generated subject before the ancestor retarget attack.
            accepted_generated = guard.generated_subject.subject_digest(
                lockfile=lockfile,
                pods=pods,
                workspace=workspace,
            )

            consumed: list[str] = []
            def launch(_command):
                local.unlink()
                local.symlink_to(substituted_secrets, target_is_directory=True)
                consumed.append((local / "TuyaSDK/Build/payload.bin").read_text(encoding="utf-8"))
                return CompletedProcess()

            argv = [
                "--lockfile", str(lockfile),
                "--security-podspec", str(sdk / "ThingSmartCryption.podspec"),
                "--security-build", str(sdk / "Build"),
                "--identity-podspec", str(identity / "NembraTuyaPrivateConfig.podspec"),
                "--identity-sources", str(identity_sources),
                "--", "fake-xcodebuild",
            ]

            def attempt() -> None:
                with patch.dict(
                    os.environ,
                    {"NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256": accepted_generated},
                    clear=False,
                ):
                    inputs, command = guard._parse_args(argv)
                    guard.run_guarded_build(
                        inputs,
                        command,
                        backend_factory=QuietBackend,
                        popen_factory=launch,
                        poll_interval=0.0,
                    )

            with self.assertRaises(guard.BuildGuardError):
                attempt()
            self.assertEqual(consumed, [], "substituted private SDK bytes reached the fake build")


if __name__ == "__main__":
    unittest.main(verbosity=2)

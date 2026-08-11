#!/usr/bin/env python3
"""Expected-red final-reproof test for #2709 private local-pod selector custody.

The vnode layer should normally observe a LocalSecrets directory mutation. The
final generation reproof is the independent fallback if event delivery is lost.
It must therefore detect that a generated local-pod symlink now resolves through
a different private-root selector even when the generated link text is stable.
"""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

REPOSITORY = Path(__file__).resolve().parents[3]
GUARD_PATH = REPOSITORY / "Scripts" / "capture_tuya_private_input_build_guard.py"


def load_guard():
    spec = importlib.util.spec_from_file_location("nembra_2709_selector_guard", GUARD_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load Capture build guard")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class QuietBackend:
    """Model the guard's documented final-reproof fallback when vnode events are missed."""

    def register(self, descriptor: int) -> None:
        del descriptor

    def events(self, timeout: float):
        del timeout
        return []

    def close(self) -> None:
        pass


class CompletedProcess:
    returncode = 0

    def poll(self):
        return 0

    def terminate(self) -> None:
        raise AssertionError("completed fake build must not be terminated")

    def wait(self, timeout=None):
        del timeout
        return 0

    def kill(self) -> None:
        raise AssertionError("completed fake build must not be killed")


class PrivateSelectorFinalReproofTests(unittest.TestCase):
    def test_final_reproof_rejects_private_sdk_selector_retarget_if_events_are_missed(self) -> None:
        guard = load_guard()
        with tempfile.TemporaryDirectory(prefix="nembra-private-selector-reproof-") as temporary:
            root = Path(temporary)
            local = root / "LocalSecrets"
            local.mkdir()

            accepted_sdk = root / "accepted-sdk"
            substituted_sdk = root / "substituted-sdk"
            for sdk, payload in ((accepted_sdk, "ACCEPTED"), (substituted_sdk, "SUBSTITUTED")):
                build = sdk / "Build"
                build.mkdir(parents=True)
                (sdk / "ThingSmartCryption.podspec").write_text(
                    "Pod::Spec.new do |s|\nend\n", encoding="utf-8"
                )
                (build / "payload.bin").write_text(payload, encoding="utf-8")

            sdk_selector = local / "TuyaSDK"
            sdk_selector.symlink_to(accepted_sdk, target_is_directory=True)

            identity = local / "TuyaRuntime"
            identity_sources = identity / "Sources/NembraTuyaPrivateConfig"
            identity_sources.mkdir(parents=True)
            (identity / "NembraTuyaPrivateConfig.podspec").write_text(
                "Pod::Spec.new do |s|\nend\n", encoding="utf-8"
            )
            (identity_sources / "NembraTuyaPrivateIdentity.swift").write_text(
                "enum PrivateIdentity {}\n", encoding="utf-8"
            )

            lockfile = root / "Podfile.lock"
            lockfile.write_text("PODS:\n  - ThingSmartCryption (1.0)\n", encoding="utf-8")
            pods = root / "Pods"
            workspace = root / "NembraCapture.xcworkspace"
            pods.mkdir()
            workspace.mkdir()
            (pods / "generated.xcconfig").write_text("SETTING = ACCEPTED\n", encoding="utf-8")
            (workspace / "contents.xcworkspacedata").write_text("workspace\n", encoding="utf-8")
            (pods / "ThingSmartCryption").symlink_to(
                "../LocalSecrets/TuyaSDK", target_is_directory=True
            )

            accepted_generated = guard.generated_build.build_subject(
                lockfile=lockfile,
                pods=pods,
                workspace=workspace,
            )

            argv = [
                "--lockfile",
                str(lockfile),
                "--security-podspec",
                str(sdk_selector / "ThingSmartCryption.podspec"),
                "--security-build",
                str(sdk_selector / "Build"),
                "--identity-podspec",
                str(identity / "NembraTuyaPrivateConfig.podspec"),
                "--identity-sources",
                str(identity_sources),
                "--",
                "fake-xcodebuild",
            ]
            inputs, command = guard._parse_args(argv)
            self.assertEqual(inputs.security_build, (accepted_sdk / "Build").resolve())

            consumed: list[str] = []

            def launch(_command):
                sdk_selector.unlink()
                sdk_selector.symlink_to(substituted_sdk, target_is_directory=True)
                consumed.append(
                    (pods / "ThingSmartCryption/Build/payload.bin").read_text(encoding="utf-8")
                )
                self.assertEqual(consumed[-1], "SUBSTITUTED")
                return CompletedProcess()

            with patch.dict(
                os.environ,
                {"NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256": accepted_generated},
                clear=False,
            ):
                with self.assertRaises(
                    guard.BuildGuardError,
                    msg=(
                        "final generation reproof accepted a retargeted private local-pod selector "
                        "when vnode event delivery was absent"
                    ),
                ):
                    guard.run_guarded_build(
                        inputs,
                        command,
                        backend_factory=QuietBackend,
                        popen_factory=launch,
                        poll_interval=0.0,
                        require_accepted_generated_subject=True,
                    )

            self.assertEqual(consumed, ["SUBSTITUTED"])


if __name__ == "__main__":
    unittest.main(verbosity=2)

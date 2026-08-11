#!/usr/bin/env python3
"""Portable authority regression for the reviewed CocoaPods-generated Capture build subject."""

from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
BOOTSTRAP = REPOSITORY / "Scripts/bootstrap_capture_tuya_sdk.sh"
PROVENANCE = REPOSITORY / "Scripts/capture_tuya_private_input_provenance.py"
GENERATED_HELPER = REPOSITORY / "Scripts/capture_cocoapods_generated_subject.py"
BUILD_GUARD = REPOSITORY / "Scripts/capture_tuya_private_input_build_guard.py"
GENERATED_RELATIVE = Path(
    "Pods/Target Support Files/Pods-NembraCapture/Pods-NembraCapture.debug.xcconfig"
)
DIGEST_LINE = re.compile(r"CocoaPods generated-subject SHA-256: ([0-9a-f]{64})")


class CocoaPodsGeneratedSubjectAuthorityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-cocoapods-authority-")
        self.root = Path(self.temporary.name)
        scripts = self.root / "Scripts"
        scripts.mkdir()
        for source in (BOOTSTRAP, PROVENANCE, GENERATED_HELPER, BUILD_GUARD):
            shutil.copy2(source, scripts / source.name)

        (self.root / "Podfile").write_text("platform :ios, '17.0'\n", encoding="utf-8")
        (self.root / "NembraCapture.xcodeproj").mkdir()

        private_sdk = self.root / "LocalSecrets/TuyaSDK"
        (private_sdk / "Build").mkdir(parents=True)
        (private_sdk / "ThingSmartCryption.podspec").write_text(
            "Pod::Spec.new do |s|\nend\n", encoding="utf-8"
        )
        (private_sdk / "Build/libThingSmartCryption.a").write_bytes(
            b"private-security-sdk"
        )

        private_identity = self.root / "LocalSecrets/TuyaRuntime"
        identity_sources = private_identity / "Sources/NembraTuyaPrivateConfig"
        identity_sources.mkdir(parents=True)
        (private_identity / "NembraTuyaPrivateConfig.podspec").write_text(
            "Pod::Spec.new do |s|\nend\n", encoding="utf-8"
        )
        (identity_sources / "NembraTuyaPrivateIdentity.swift").write_text(
            "enum NembraTuyaPrivateIdentity { static let configured = true }\n",
            encoding="utf-8",
        )

        self.fake_bin = self.root / "fake-bin"
        self.fake_bin.mkdir()
        self.pod_invocations = self.root / "pod-invocations"
        pod = self.fake_bin / "pod"
        pod.write_text(
            "#!/bin/bash\n"
            "set -euo pipefail\n"
            "printf 'pod\\n' >> \"${NEMBRA_TEST_POD_INVOCATIONS:?}\"\n"
            "mkdir -p 'NembraCapture.xcworkspace' 'Pods/Target Support Files/Pods-NembraCapture'\n"
            "cat > Podfile.lock <<'EOF'\n"
            "PODS:\n"
            "  - ThingSmartHomeKit (7.8.0)\n"
            "  - ThingSmartBusinessExtensionKit (7.8.0)\n"
            "DEPENDENCIES:\n"
            "  - ThingSmartHomeKit (= 7.8.0)\n"
            "  - ThingSmartBusinessExtensionKit (= 7.8.0)\n"
            "EOF\n"
            "printf '%s\\n' 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) REVIEWED_GRAPH' > 'Pods/Target Support Files/Pods-NembraCapture/Pods-NembraCapture.debug.xcconfig'\n"
            "printf '%s\\n' 'REVIEWED_GRAPH' > NembraCapture.xcworkspace/contents.xcworkspacedata\n",
            encoding="utf-8",
        )
        pod.chmod(0o755)

        # bootstrap uses macOS `stat -f %Lp` for the freshly-created mode-0600
        # local provenance record. Preserve the product script and emulate only
        # that spelling in this Ubuntu-portable regression.
        fake_stat = self.fake_bin / "stat"
        fake_stat.write_text(
            "#!/bin/bash\n"
            "set -euo pipefail\n"
            "if [[ ${1:-} == '-f' && ${2:-} == '%Lp' ]]; then\n"
            "  printf '600\\n'\n"
            "  exit 0\n"
            "fi\n"
            "exec /usr/bin/stat \"$@\"\n",
            encoding="utf-8",
        )
        fake_stat.chmod(0o755)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def environment(self) -> dict[str, str]:
        return {
            "PATH": f"{self.fake_bin}:/usr/bin:/bin",
            "HOME": str(self.root),
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            "NEMBRA_TEST_POD_INVOCATIONS": str(self.pod_invocations),
        }

    def run_bootstrap(
        self,
        *,
        review_only: bool,
        accepted_lock: str | None = None,
        accepted_generated: str | None = None,
    ) -> subprocess.CompletedProcess[str]:
        environment = self.environment()
        if accepted_lock is not None:
            environment["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"] = accepted_lock
        if accepted_generated is not None:
            environment[
                "NEMBRA_CAPTURE_ACCEPTED_TUYA_GENERATED_SUBJECT_SHA256"
            ] = accepted_generated
        command = ["/bin/bash", str(self.root / "Scripts/bootstrap_capture_tuya_sdk.sh")]
        if review_only:
            command.append("--resolve-lock-for-review")
        return subprocess.run(
            command,
            cwd=self.root,
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )

    def reviewed_subjects(self) -> tuple[str, str]:
        review = self.run_bootstrap(review_only=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        lock = hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest()
        match = DIGEST_LINE.search(review.stdout)
        self.assertIsNotNone(match, review.stdout)
        assert match is not None
        generated = match.group(1)
        return lock, generated

    def test_normal_field_bootstrap_consumes_reviewed_bytes_without_invoking_pod(self) -> None:
        accepted_lock, accepted_generated = self.reviewed_subjects()
        self.assertEqual(self.pod_invocations.read_text(encoding="utf-8").splitlines(), ["pod"])

        field = self.run_bootstrap(
            review_only=False,
            accepted_lock=accepted_lock,
            accepted_generated=accepted_generated,
        )
        self.assertEqual(field.returncode, 0, field.stdout)
        self.assertIn("Preaccepted CocoaPods generated subject matched", field.stdout)
        self.assertEqual(
            self.pod_invocations.read_text(encoding="utf-8").splitlines(),
            ["pod"],
            "normal field bootstrap must not reopen mutable CocoaPods generation",
        )

    def test_same_accepted_lock_rejects_changed_generated_build_graph(self) -> None:
        accepted_lock, accepted_generated = self.reviewed_subjects()
        reviewed_bytes = (self.root / GENERATED_RELATIVE).read_bytes()

        (self.root / GENERATED_RELATIVE).write_text(
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) SUBSTITUTED_GRAPH\n",
            encoding="utf-8",
        )
        (self.root / "NembraCapture.xcworkspace/contents.xcworkspacedata").write_text(
            "SUBSTITUTED_GRAPH\n", encoding="utf-8"
        )
        self.assertNotEqual(reviewed_bytes, (self.root / GENERATED_RELATIVE).read_bytes())
        self.assertEqual(
            hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest(),
            accepted_lock,
        )

        field = self.run_bootstrap(
            review_only=False,
            accepted_lock=accepted_lock,
            accepted_generated=accepted_generated,
        )
        self.assertNotEqual(field.returncode, 0, field.stdout)
        self.assertIn("generated build bytes do not match", field.stdout)
        self.assertEqual(self.pod_invocations.read_text(encoding="utf-8").splitlines(), ["pod"])

    def test_build_guard_reproves_generated_subject_before_compiler_admission(self) -> None:
        accepted_lock, accepted_generated = self.reviewed_subjects()
        module_path = self.root / "Scripts/capture_tuya_private_input_build_guard.py"
        spec = importlib.util.spec_from_file_location("nembra_build_guard", module_path)
        self.assertIsNotNone(spec)
        assert spec is not None and spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        inputs = module.PrivateInputs(
            lockfile=self.root / "Podfile.lock",
            security_podspec=self.root / "LocalSecrets/TuyaSDK/ThingSmartCryption.podspec",
            security_build=self.root / "LocalSecrets/TuyaSDK/Build",
            identity_podspec=self.root / "LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec",
            identity_sources=self.root / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig",
            generated_pods=self.root / "Pods",
            generated_workspace=self.root / "NembraCapture.xcworkspace",
            accepted_generated_subject_sha256=accepted_generated,
        )
        snapshot = inputs.generation_snapshot()
        self.assertEqual(snapshot[1], accepted_generated)
        self.assertEqual(
            hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest(),
            accepted_lock,
        )

        (self.root / GENERATED_RELATIVE).write_text(
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) MUTATED_DURING_BUILD\n",
            encoding="utf-8",
        )
        with self.assertRaises(module.BuildGuardError):
            inputs.generation_snapshot()


if __name__ == "__main__":
    unittest.main(verbosity=2)

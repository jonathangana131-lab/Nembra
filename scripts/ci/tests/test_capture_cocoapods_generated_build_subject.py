#!/usr/bin/env python3
"""Lock the reviewed CocoaPods-generated build subject to exact field bytes."""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
BOOTSTRAP = REPOSITORY / "Scripts" / "bootstrap_capture_tuya_sdk.sh"
PROVENANCE = REPOSITORY / "Scripts" / "capture_tuya_private_input_provenance.py"
GENERATED_SUBJECT = REPOSITORY / "Scripts" / "capture_cocoapods_generated_build_subject.py"
GENERATED_RELATIVE = Path("Pods/Target Support Files/Pods-NembraCapture/Pods-NembraCapture.debug.xcconfig")
LOCK_PATTERN = re.compile(r"Podfile\.lock SHA-256:\s*([0-9a-f]{64})")
GENERATED_PATTERN = re.compile(r"CocoaPods generated-build SHA-256:\s*([0-9a-f]{64})")


class CocoaPodsGeneratedBuildSubjectTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-cocoapods-subject-")
        self.root = Path(self.temporary.name)
        scripts = self.root / "Scripts"
        scripts.mkdir()
        shutil.copy2(BOOTSTRAP, scripts / BOOTSTRAP.name)
        shutil.copy2(PROVENANCE, scripts / PROVENANCE.name)
        shutil.copy2(GENERATED_SUBJECT, scripts / GENERATED_SUBJECT.name)

        (self.root / "Podfile").write_text("platform :ios, '17.0'\n", encoding="utf-8")
        (self.root / "NembraCapture.xcodeproj").mkdir()

        private_sdk = self.root / "LocalSecrets/TuyaSDK"
        (private_sdk / "Build").mkdir(parents=True)
        (private_sdk / "ThingSmartCryption.podspec").write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
        (private_sdk / "Build/libThingSmartCryption.a").write_bytes(b"private-security-sdk")

        private_identity = self.root / "LocalSecrets/TuyaRuntime"
        identity_sources = private_identity / "Sources/NembraTuyaPrivateConfig"
        identity_sources.mkdir(parents=True)
        (private_identity / "NembraTuyaPrivateConfig.podspec").write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
        (identity_sources / "NembraTuyaPrivateIdentity.swift").write_text(
            "enum NembraTuyaPrivateIdentity { static let configured = true }\n",
            encoding="utf-8",
        )

        self.fake_bin = self.root / "fake-bin"
        self.fake_bin.mkdir()
        pod = self.fake_bin / "pod"
        pod.write_text(
            "#!/bin/bash\n"
            "set -euo pipefail\n"
            "mkdir -p 'NembraCapture.xcworkspace' 'Pods/Target Support Files/Pods-NembraCapture'\n"
            "cat > Podfile.lock <<'EOF'\n"
            "PODS:\n"
            "  - ThingSmartHomeKit (7.8.0)\n"
            "  - ThingSmartBusinessExtensionKit (7.8.0)\n"
            "DEPENDENCIES:\n"
            "  - ThingSmartHomeKit (= 7.8.0)\n"
            "  - ThingSmartBusinessExtensionKit (= 7.8.0)\n"
            "EOF\n"
            "printf '%s\\n' \"SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) ${NEMBRA_TEST_GENERATED_PAYLOAD:?}\" > 'Pods/Target Support Files/Pods-NembraCapture/Pods-NembraCapture.debug.xcconfig'\n"
            "printf '%s\\n' \"${NEMBRA_TEST_GENERATED_PAYLOAD:?}\" > NembraCapture.xcworkspace/contents.xcworkspacedata\n",
            encoding="utf-8",
        )
        pod.chmod(0o755)

        # Product bootstrap uses the macOS stat spelling only for the private
        # provenance record mode. Keep this authority regression portable.
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

    def run_bootstrap(
        self,
        payload: str,
        *,
        review_only: bool,
        accepted_lock: str | None = None,
        accepted_generated: str | None = None,
    ) -> subprocess.CompletedProcess[str]:
        environment = {
            "PATH": f"{self.fake_bin}:/usr/bin:/bin",
            "HOME": str(self.root),
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            "NEMBRA_TEST_GENERATED_PAYLOAD": payload,
        }
        if accepted_lock is not None:
            environment["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"] = accepted_lock
        if accepted_generated is not None:
            environment["NEMBRA_CAPTURE_ACCEPTED_TUYA_GENERATED_BUILD_SHA256"] = accepted_generated
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

    def reviewed_subject(self) -> tuple[str, str, bytes]:
        review = self.run_bootstrap("REVIEWED_GRAPH", review_only=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        lock_match = LOCK_PATTERN.search(review.stdout)
        generated_match = GENERATED_PATTERN.search(review.stdout)
        self.assertIsNotNone(lock_match, review.stdout)
        self.assertIsNotNone(generated_match, review.stdout)
        assert lock_match is not None and generated_match is not None
        lock = lock_match.group(1)
        generated = generated_match.group(1)
        self.assertEqual(hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest(), lock)
        return lock, generated, (self.root / GENERATED_RELATIVE).read_bytes()

    def test_exact_reviewed_generated_subject_is_admitted(self) -> None:
        lock, generated, reviewed_bytes = self.reviewed_subject()
        field = self.run_bootstrap(
            "REVIEWED_GRAPH",
            review_only=False,
            accepted_lock=lock,
            accepted_generated=generated,
        )
        self.assertEqual(field.returncode, 0, field.stdout)
        self.assertEqual((self.root / GENERATED_RELATIVE).read_bytes(), reviewed_bytes)
        self.assertIn("Preaccepted CocoaPods generated-build subject matched", field.stdout)

    def test_same_accepted_lock_rejects_changed_generated_build_graph(self) -> None:
        lock, generated, reviewed_bytes = self.reviewed_subject()
        field = self.run_bootstrap(
            "SUBSTITUTED_GRAPH",
            review_only=False,
            accepted_lock=lock,
            accepted_generated=generated,
        )
        field_lock = hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest()
        substituted_bytes = (self.root / GENERATED_RELATIVE).read_bytes()

        self.assertEqual(field_lock, lock, "fake pod must preserve the exact preaccepted Podfile.lock")
        self.assertNotEqual(reviewed_bytes, substituted_bytes, "test must materially replace generated build bytes")
        self.assertNotEqual(field.returncode, 0, field.stdout)
        self.assertIn("generated-build SHA-256", field.stdout)

    def test_missing_generated_authority_fails_before_pod_install(self) -> None:
        lock, _, _ = self.reviewed_subject()
        marker = self.root / "pod-invoked"
        pod = self.fake_bin / "pod"
        original = pod.read_text(encoding="utf-8")
        pod.write_text("#!/bin/bash\ntouch 'pod-invoked'\n" + original.split("\n", 1)[1], encoding="utf-8")
        pod.chmod(0o755)
        field = self.run_bootstrap("REVIEWED_GRAPH", review_only=False, accepted_lock=lock)
        self.assertNotEqual(field.returncode, 0, field.stdout)
        self.assertFalse(marker.exists(), "missing generated-build authority must fail before resolver/generator side effects")


if __name__ == "__main__":
    unittest.main(verbosity=2)

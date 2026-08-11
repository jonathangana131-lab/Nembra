#!/usr/bin/env python3
"""End-to-end normal-bootstrap admission test for reviewed private Tuya inputs."""
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
BOOTSTRAP = REPOSITORY / "Scripts/bootstrap_capture_tuya_sdk.sh"
PROVENANCE = REPOSITORY / "Scripts/capture_tuya_private_input_provenance.py"
PRIVATE_REVIEW = REPOSITORY / "Scripts/capture_tuya_private_input_review.py"
GENERATED_SUBJECT = REPOSITORY / "Scripts/capture_cocoapods_generated_build_subject.py"
GENERATED_PATTERN = re.compile(r"CocoaPods generated build subject SHA-256:\s*([0-9a-f]{64})")
PRIVATE_PATTERN = re.compile(r"Private Tuya input review commitment:\s*([0-9a-f]{64})")


class PrivateInputBootstrapAdmissionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-private-bootstrap-admission-")
        self.root = Path(self.temporary.name)
        scripts = self.root / "Scripts"
        scripts.mkdir()
        for source in (BOOTSTRAP, PROVENANCE, PRIVATE_REVIEW, GENERATED_SUBJECT):
            shutil.copy2(source, scripts / source.name)

        (self.root / "Podfile").write_text("platform :ios, '17.0'\n", encoding="utf-8")
        (self.root / "NembraCapture.xcodeproj").mkdir()

        self.sdk = self.root / "LocalSecrets/TuyaSDK"
        self.security_build = self.sdk / "Build"
        self.security_build.mkdir(parents=True)
        (self.sdk / "ThingSmartCryption.podspec").write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
        self.security_binary = self.security_build / "libThingSmartCryption.a"
        self.security_binary.write_bytes(b"REVIEWED-SECURITY-A")

        self.runtime = self.root / "LocalSecrets/TuyaRuntime"
        self.identity_sources = self.runtime / "Sources/NembraTuyaPrivateConfig"
        self.identity_sources.mkdir(parents=True)
        (self.runtime / "NembraTuyaPrivateConfig.podspec").write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
        self.identity_source = self.identity_sources / "NembraTuyaPrivateIdentity.swift"
        self.identity_source.write_text("enum Identity { static let generation = \"A\" }\n", encoding="utf-8")
        self.record = self.runtime / "ResolvedTuyaDependencyProvenance.txt"
        self.key = self.runtime / "PrivateInputReviewKey.bin"

        self.fake_bin = self.root / "fake-bin"
        self.fake_bin.mkdir()
        self.pod_marker = self.root / "pod-invoked"
        pod = self.fake_bin / "pod"
        pod.write_text(
            "#!/bin/bash\n"
            "set -euo pipefail\n"
            "touch pod-invoked\n"
            "mkdir -p 'NembraCapture.xcworkspace' 'Pods/Target Support Files/Pods-NembraCapture'\n"
            "cat > Podfile.lock <<'EOF'\n"
            "PODS:\n"
            "  - ThingSmartHomeKit (7.8.0)\n"
            "  - ThingSmartBusinessExtensionKit (7.8.0)\n"
            "DEPENDENCIES:\n"
            "  - ThingSmartHomeKit (= 7.8.0)\n"
            "  - ThingSmartBusinessExtensionKit (= 7.8.0)\n"
            "EOF\n"
            "printf 'REVIEWED-GRAPH\\n' > 'Pods/Target Support Files/Pods-NembraCapture/Pods-NembraCapture.debug.xcconfig'\n"
            "printf 'REVIEWED-GRAPH\\n' > NembraCapture.xcworkspace/contents.xcworkspacedata\n",
            encoding="utf-8",
        )
        pod.chmod(0o755)

        fake_stat = self.fake_bin / "stat"
        fake_stat.write_text(
            "#!/bin/bash\n"
            "set -euo pipefail\n"
            "if [[ ${1:-} == '-f' && ${2:-} == '%Lp' ]]; then printf '600\\n'; exit 0; fi\n"
            "exec /usr/bin/stat \"$@\"\n",
            encoding="utf-8",
        )
        fake_stat.chmod(0o755)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def bootstrap(
        self,
        *,
        review: bool,
        lock: str = "",
        generated: str = "",
        private: str = "",
    ) -> subprocess.CompletedProcess[str]:
        environment = {
            "PATH": f"{self.fake_bin}:/usr/bin:/bin",
            "HOME": str(self.root),
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
        }
        if lock:
            environment["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"] = lock
        if generated:
            environment["NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256"] = generated
        if private:
            environment["NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_INPUT_COMMITMENT"] = private
        command = ["/bin/bash", str(self.root / "Scripts/bootstrap_capture_tuya_sdk.sh")]
        if review:
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

    def reviewed_authority(self) -> tuple[str, str, str]:
        result = self.bootstrap(review=True)
        self.assertEqual(result.returncode, 0, result.stdout)
        generated = GENERATED_PATTERN.search(result.stdout)
        private = PRIVATE_PATTERN.search(result.stdout)
        self.assertIsNotNone(generated, result.stdout)
        self.assertIsNotNone(private, result.stdout)
        assert generated is not None and private is not None
        return (
            hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest(),
            generated.group(1),
            private.group(1),
        )

    def test_private_generation_b_is_rejected_before_pod_and_without_witness_rewrite(self) -> None:
        lock, generated, private = self.reviewed_authority()
        self.assertTrue(self.pod_marker.exists(), "review candidate creation must exercise the resolver")
        self.pod_marker.unlink()

        record_bytes = self.record.read_bytes()
        key_bytes = self.key.read_bytes()
        record_inode = self.record.stat().st_ino
        key_inode = self.key.stat().st_ino

        self.security_binary.write_bytes(b"SUBSTITUTED-SECURITY-B")
        self.identity_source.write_text("enum Identity { static let generation = \"B\" }\n", encoding="utf-8")

        field = self.bootstrap(
            review=False,
            lock=lock,
            generated=generated,
            private=private,
        )
        self.assertNotEqual(field.returncode, 0, field.stdout)
        self.assertIn("not the externally reviewed field-build subject", field.stdout)
        self.assertFalse(self.pod_marker.exists(), "unreviewed private bytes must fail before pod install")
        self.assertEqual(self.record.read_bytes(), record_bytes)
        self.assertEqual(self.key.read_bytes(), key_bytes)
        self.assertEqual(self.record.stat().st_ino, record_inode, "normal bootstrap must not replace the reviewed record")
        self.assertEqual(self.key.stat().st_ino, key_inode, "normal bootstrap must not rotate the reviewed HMAC key")

    def test_accepted_generation_a_does_not_rewrite_private_witness_or_key(self) -> None:
        lock, generated, private = self.reviewed_authority()
        self.pod_marker.unlink()
        record_bytes = self.record.read_bytes()
        key_bytes = self.key.read_bytes()
        record_inode = self.record.stat().st_ino
        key_inode = self.key.stat().st_ino

        field = self.bootstrap(
            review=False,
            lock=lock,
            generated=generated,
            private=private,
        )
        self.assertEqual(field.returncode, 0, field.stdout)
        self.assertTrue(self.pod_marker.exists())
        self.assertEqual(self.record.read_bytes(), record_bytes)
        self.assertEqual(self.key.read_bytes(), key_bytes)
        self.assertEqual(self.record.stat().st_ino, record_inode)
        self.assertEqual(self.key.stat().st_ino, key_inode)


if __name__ == "__main__":
    unittest.main(verbosity=2)

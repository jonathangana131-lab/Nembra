#!/usr/bin/env python3
"""Regression for the reviewed CocoaPods generated build-subject boundary."""

from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
BOOTSTRAP = REPOSITORY / "Scripts" / "bootstrap_capture_tuya_sdk.sh"
PROVENANCE = REPOSITORY / "Scripts" / "capture_tuya_private_input_provenance.py"
BUILD_SUBJECT = REPOSITORY / "Scripts" / "capture_cocoapods_build_subject.py"

spec = importlib.util.spec_from_file_location("nembra_build_subject", BUILD_SUBJECT)
assert spec and spec.loader
build_subject = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_subject)


class CocoaPodsGeneratedBuildSubjectTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-cocoapods-subject-")
        self.root = Path(self.temporary.name)
        scripts = self.root / "Scripts"
        scripts.mkdir()
        for source in (BOOTSTRAP, PROVENANCE, BUILD_SUBJECT):
            shutil.copy2(source, scripts / source.name)

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

    def run_bootstrap(
        self,
        payload: str,
        *,
        review_only: bool,
        accepted_lock: str | None = None,
        accepted_build_subject: str | None = None,
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
        if accepted_build_subject is not None:
            environment["NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256"] = accepted_build_subject
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

    def test_same_lock_cannot_authorize_changed_generated_build_graph(self) -> None:
        review = self.run_bootstrap("REVIEWED_GRAPH", review_only=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        accepted_lock = hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest()
        accepted_subject = build_subject.build_subject_digest(
            self.root / "Pods",
            self.root / "NembraCapture.xcworkspace",
        )

        field = self.run_bootstrap(
            "SUBSTITUTED_GRAPH",
            review_only=False,
            accepted_lock=accepted_lock,
            accepted_build_subject=accepted_subject,
        )
        self.assertNotEqual(field.returncode, 0, field.stdout)
        self.assertIn("generated CocoaPods build subject does not match", field.stdout)

    def test_normal_bootstrap_rejects_lock_mismatch_before_pod_runs(self) -> None:
        (self.root / "Podfile.lock").write_text("unreviewed\n", encoding="utf-8")
        marker = self.root / "pod-ran"
        pod = self.fake_bin / "pod"
        original = pod.read_text(encoding="utf-8")
        pod.write_text(f"#!/bin/bash\ntouch '{marker}'\n" + original, encoding="utf-8")
        pod.chmod(0o755)

        field = self.run_bootstrap(
            "IGNORED",
            review_only=False,
            accepted_lock="0" * 64,
            accepted_build_subject="1" * 64,
        )
        self.assertNotEqual(field.returncode, 0, field.stdout)
        self.assertFalse(marker.exists(), "CocoaPods must not start before the on-disk lock matches reviewed authority")


if __name__ == "__main__":
    unittest.main(verbosity=2)

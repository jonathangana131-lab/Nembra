#!/usr/bin/env python3
"""Regression: one reviewed lock cannot authorize a different CocoaPods build graph."""

from __future__ import annotations

import hashlib
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
BOOTSTRAP = REPOSITORY / "Scripts/bootstrap_capture_tuya_sdk.sh"
PROVENANCE = REPOSITORY / "Scripts/capture_tuya_private_input_provenance.py"
SUBJECT_HELPER = REPOSITORY / "Scripts/capture_cocoapods_build_subject.py"
GENERATED_RELATIVE = Path("Pods/Target Support Files/Pods-NembraCapture/Pods-NembraCapture.debug.xcconfig")


class CocoaPodsGeneratedBuildSubjectTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-cocoapods-subject-")
        self.root = Path(self.temporary.name)
        scripts = self.root / "Scripts"
        scripts.mkdir()
        for source in (BOOTSTRAP, PROVENANCE, SUBJECT_HELPER):
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
            "printf '%s\\n' \"SWIFT_ACTIVE_COMPILATION_CONDITIONS = \\$(inherited) ${NEMBRA_REDTEAM_GENERATED_PAYLOAD:?}\" > 'Pods/Target Support Files/Pods-NembraCapture/Pods-NembraCapture.debug.xcconfig'\n"
            "printf '%s\\n' \"${NEMBRA_REDTEAM_GENERATED_PAYLOAD:?}\" > NembraCapture.xcworkspace/contents.xcworkspacedata\n",
            encoding="utf-8",
        )
        pod.chmod(0o755)

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
        accepted_subject: str | None = None,
    ) -> subprocess.CompletedProcess[str]:
        environment = {
            "PATH": f"{self.fake_bin}:/usr/bin:/bin",
            "HOME": str(self.root),
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            "NEMBRA_REDTEAM_GENERATED_PAYLOAD": payload,
        }
        if accepted_lock is not None:
            environment["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"] = accepted_lock
        if accepted_subject is not None:
            environment["NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256"] = accepted_subject
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

    def current_subject(self) -> str:
        result = subprocess.run(
            [
                "/usr/bin/python3",
                "-I",
                str(self.root / "Scripts/capture_cocoapods_build_subject.py"),
                "digest",
                "--lockfile",
                str(self.root / "Podfile.lock"),
                "--pods",
                str(self.root / "Pods"),
                "--workspace",
                str(self.root / "NembraCapture.xcworkspace"),
            ],
            cwd=self.root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout)
        return result.stdout.strip()

    def test_same_accepted_lock_cannot_authorize_changed_generated_build_graph(self) -> None:
        review = self.run_bootstrap("REVIEWED_GRAPH", review_only=True)
        self.assertEqual(review.returncode, 0, review.stdout)

        accepted_lock = hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest()
        accepted_subject = self.current_subject()
        reviewed_generated = (self.root / GENERATED_RELATIVE).read_bytes()

        field = self.run_bootstrap(
            "SUBSTITUTED_GRAPH",
            review_only=False,
            accepted_lock=accepted_lock,
            accepted_subject=accepted_subject,
        )
        field_lock = hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest()
        substituted_generated = (self.root / GENERATED_RELATIVE).read_bytes()

        self.assertEqual(field_lock, accepted_lock, "fake pod must preserve the exact preaccepted Podfile.lock")
        self.assertNotEqual(reviewed_generated, substituted_generated, "test must materially replace generated build bytes")
        self.assertNotEqual(field.returncode, 0, "different generated build bytes crossed the accepted subject boundary")
        self.assertIn("generated CocoaPods build subject does not match", field.stdout)

    def test_exact_generated_subject_is_admitted(self) -> None:
        review = self.run_bootstrap("REVIEWED_GRAPH", review_only=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        accepted_lock = hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest()
        accepted_subject = self.current_subject()

        field = self.run_bootstrap(
            "REVIEWED_GRAPH",
            review_only=False,
            accepted_lock=accepted_lock,
            accepted_subject=accepted_subject,
        )
        self.assertEqual(field.returncode, 0, field.stdout)
        self.assertIn("Preaccepted CocoaPods generated build subject matched", field.stdout)

    def test_normal_bootstrap_requires_external_generated_subject_authority(self) -> None:
        review = self.run_bootstrap("REVIEWED_GRAPH", review_only=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        accepted_lock = hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest()

        field = self.run_bootstrap(
            "REVIEWED_GRAPH",
            review_only=False,
            accepted_lock=accepted_lock,
        )
        self.assertNotEqual(field.returncode, 0)
        self.assertIn("NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256", field.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)

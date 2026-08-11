#!/usr/bin/env python3
"""Regression coverage for reviewed CocoaPods build-subject authority.

A reviewed dependency lock is necessary but not sufficient: the generated Pods/
and workspace bytes must also remain the exact reviewed build subject. Normal
field bootstrap must additionally reject a mismatched on-disk reviewed lock
before CocoaPods itself is allowed to run.
"""
from __future__ import annotations

import hashlib
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
GENERATED_RELATIVE = Path("Pods/Target Support Files/Pods-NembraCapture/Pods-NembraCapture.debug.xcconfig")


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
            "printf '%s\\n' \"${NEMBRA_REDTEAM_GENERATED_PAYLOAD:?}\" >> .pod-invocations\n"
            "mkdir -p 'NembraCapture.xcworkspace' 'Pods/Target Support Files/Pods-NembraCapture'\n"
            "cat > Podfile.lock <<'EOF'\n"
            "PODS:\n"
            "  - ThingSmartHomeKit (7.8.0)\n"
            "  - ThingSmartBusinessExtensionKit (7.8.0)\n"
            "DEPENDENCIES:\n"
            "  - ThingSmartHomeKit (= 7.8.0)\n"
            "  - ThingSmartBusinessExtensionKit (= 7.8.0)\n"
            "EOF\n"
            "printf '%s\\n' \"SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) ${NEMBRA_REDTEAM_GENERATED_PAYLOAD:?}\" > 'Pods/Target Support Files/Pods-NembraCapture/Pods-NembraCapture.debug.xcconfig'\n"
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

    def build_subject(self) -> str:
        result = subprocess.run(
            [
                "/usr/bin/python3",
                "-I",
                str(self.root / "Scripts/capture_cocoapods_build_subject.py"),
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
        value = result.stdout.strip()
        self.assertRegex(value, r"^[0-9a-f]{64}$")
        return value

    def invocation_count(self) -> int:
        path = self.root / ".pod-invocations"
        if not path.exists():
            return 0
        return len(path.read_text(encoding="utf-8").splitlines())

    def reviewed_subject(self) -> tuple[str, str]:
        review = self.run_bootstrap("REVIEWED_GRAPH", review_only=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        lock = hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest()
        subject = self.build_subject()
        self.assertIn(lock, review.stdout)
        self.assertIn(subject, review.stdout)
        return lock, subject

    def test_exact_reviewed_generated_graph_is_required(self) -> None:
        accepted_lock, accepted_subject = self.reviewed_subject()
        reviewed_generated = (self.root / GENERATED_RELATIVE).read_bytes()

        same = self.run_bootstrap(
            "REVIEWED_GRAPH",
            review_only=False,
            accepted_lock=accepted_lock,
            accepted_subject=accepted_subject,
        )
        self.assertEqual(same.returncode, 0, same.stdout)

        changed = self.run_bootstrap(
            "SUBSTITUTED_GRAPH",
            review_only=False,
            accepted_lock=accepted_lock,
            accepted_subject=accepted_subject,
        )
        substituted_generated = (self.root / GENERATED_RELATIVE).read_bytes()
        self.assertNotEqual(reviewed_generated, substituted_generated)
        self.assertNotEqual(changed.returncode, 0, changed.stdout)
        self.assertIn("generated CocoaPods build subject", changed.stdout)

    def test_reviewed_lock_mismatch_fails_before_cocoapods_executes(self) -> None:
        accepted_lock, accepted_subject = self.reviewed_subject()
        calls_before = self.invocation_count()
        generated_before = (self.root / GENERATED_RELATIVE).read_bytes()
        (self.root / "Podfile.lock").write_text("tampered-before-cocoapods\n", encoding="utf-8")

        result = self.run_bootstrap(
            "SHOULD_NOT_RUN",
            review_only=False,
            accepted_lock=accepted_lock,
            accepted_subject=accepted_subject,
        )
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.invocation_count(), calls_before)
        self.assertEqual((self.root / GENERATED_RELATIVE).read_bytes(), generated_before)
        self.assertIn("before CocoaPods", result.stdout)

    def test_generated_subject_authority_is_mandatory_before_cocoapods(self) -> None:
        accepted_lock, _ = self.reviewed_subject()
        calls_before = self.invocation_count()
        result = self.run_bootstrap(
            "SHOULD_NOT_RUN",
            review_only=False,
            accepted_lock=accepted_lock,
        )
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.invocation_count(), calls_before)
        self.assertIn("NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)

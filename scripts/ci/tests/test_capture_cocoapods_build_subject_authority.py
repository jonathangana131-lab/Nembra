#!/usr/bin/env python3
"""Production regression for reviewed CocoaPods generated-build authority."""

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
GENERATED_RELATIVE = Path(
    "Pods/Target Support Files/Pods-NembraCapture/Pods-NembraCapture.debug.xcconfig"
)


class CocoaPodsBuildSubjectAuthorityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-cocoapods-authority-")
        self.root = Path(self.temporary.name)
        scripts = self.root / "Scripts"
        scripts.mkdir()
        for source in (BOOTSTRAP, PROVENANCE, BUILD_SUBJECT):
            shutil.copy2(source, scripts / source.name)

        (self.root / "Podfile").write_text("platform :ios, '17.0'\n", encoding="utf-8")
        (self.root / "NembraCapture.xcodeproj").mkdir()

        private_sdk = self.root / "LocalSecrets/TuyaSDK"
        (private_sdk / "Build").mkdir(parents=True)
        (private_sdk / "ThingSmartCryption.podspec").write_text(
            "Pod::Spec.new do |s|\nend\n", encoding="utf-8"
        )
        (private_sdk / "Build/libThingSmartCryption.a").write_bytes(b"private-security-sdk")

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

        # The product bootstrap uses macOS `stat -f %Lp` for its private record.
        # Keep this resolver-only regression portable without changing product bytes.
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
            "NEMBRA_TEST_GENERATED_PAYLOAD": payload,
        }
        if accepted_lock is not None:
            environment["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"] = accepted_lock
        if accepted_subject is not None:
            environment[
                "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256"
            ] = accepted_subject
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

    def subject_digest(self) -> str:
        completed = subprocess.run(
            [
                "/usr/bin/python3",
                "-I",
                str(self.root / "Scripts/capture_cocoapods_build_subject.py"),
                "fingerprint",
                "--root",
                str(self.root),
            ],
            cwd=self.root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout)
        digest = completed.stdout.strip()
        self.assertRegex(digest, r"^[0-9a-f]{64}$")
        return digest

    def test_reviewed_generated_graph_is_required_and_substitution_is_rejected(self) -> None:
        review = self.run_bootstrap("REVIEWED_GRAPH", review_only=True)
        self.assertEqual(review.returncode, 0, review.stdout)

        accepted_lock = hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest()
        accepted_subject = self.subject_digest()
        reviewed_generated = (self.root / GENERATED_RELATIVE).read_bytes()
        self.assertIn(accepted_lock, review.stdout)
        self.assertIn(accepted_subject, review.stdout)

        unchanged = self.run_bootstrap(
            "REVIEWED_GRAPH",
            review_only=False,
            accepted_lock=accepted_lock,
            accepted_subject=accepted_subject,
        )
        self.assertEqual(
            unchanged.returncode,
            0,
            "the exact reviewed resolver + generated graph must remain an admissible bootstrap subject\n"
            + unchanged.stdout,
        )

        substituted = self.run_bootstrap(
            "SUBSTITUTED_GRAPH",
            review_only=False,
            accepted_lock=accepted_lock,
            accepted_subject=accepted_subject,
        )
        substituted_lock = hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest()
        substituted_generated = (self.root / GENERATED_RELATIVE).read_bytes()

        self.assertEqual(
            substituted_lock,
            accepted_lock,
            "the adversarial resolver must preserve the exact preaccepted Podfile.lock",
        )
        self.assertNotEqual(
            reviewed_generated,
            substituted_generated,
            "the adversarial resolver must materially replace generated build-affecting bytes",
        )
        self.assertNotEqual(
            substituted.returncode,
            0,
            "different CocoaPods-generated build bytes were admitted under an old reviewed subject",
        )
        self.assertIn(
            "do not match the preaccepted build-subject SHA-256",
            substituted.stdout,
            "the rejection must be generated-build authority, not a missing unrelated prerequisite",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

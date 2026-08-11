#!/usr/bin/env python3
"""Expected-red diagnostic for review-time private Tuya build-input authority.

A review-only bootstrap snapshots private generation A. The private SDK/identity
inputs are then replaced by a stable generation B while the accepted public
Podfile.lock remains byte-identical. Normal field bootstrap must reject B before
it can become a newly self-authorized provenance witness.
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
BOOTSTRAP = REPOSITORY / "Scripts/bootstrap_capture_tuya_sdk.sh"
PROVENANCE = REPOSITORY / "Scripts/capture_tuya_private_input_provenance.py"


class PrivateInputReviewAuthorityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-private-review-authority-")
        self.root = Path(self.temporary.name)
        scripts = self.root / "Scripts"
        scripts.mkdir()
        shutil.copy2(BOOTSTRAP, scripts / BOOTSTRAP.name)
        shutil.copy2(PROVENANCE, scripts / PROVENANCE.name)

        (self.root / "Podfile").write_text("platform :ios, '17.0'\n", encoding="utf-8")
        (self.root / "NembraCapture.xcodeproj").mkdir()

        self.security_sdk = self.root / "LocalSecrets/TuyaSDK"
        self.security_build = self.security_sdk / "Build"
        self.security_build.mkdir(parents=True)
        (self.security_sdk / "ThingSmartCryption.podspec").write_text(
            "Pod::Spec.new do |s|\n  s.name = 'ThingSmartCryption'\nend\n",
            encoding="utf-8",
        )
        self.security_binary = self.security_build / "libThingSmartCryption.a"
        self.security_binary.write_bytes(b"REVIEWED-PRIVATE-SECURITY-A")

        self.identity_root = self.root / "LocalSecrets/TuyaRuntime"
        self.identity_sources = self.identity_root / "Sources/NembraTuyaPrivateConfig"
        self.identity_sources.mkdir(parents=True)
        (self.identity_root / "NembraTuyaPrivateConfig.podspec").write_text(
            "Pod::Spec.new do |s|\n  s.name = 'NembraTuyaPrivateConfig'\nend\n",
            encoding="utf-8",
        )
        self.identity_source = self.identity_sources / "NembraTuyaPrivateIdentity.swift"
        self.identity_source.write_text(
            "enum NembraTuyaPrivateIdentity { static let generation = \"REVIEWED-A\" }\n",
            encoding="utf-8",
        )

        self.fake_bin = self.root / "fake-bin"
        self.fake_bin.mkdir()
        pod = self.fake_bin / "pod"
        pod.write_text(
            "#!/bin/bash\n"
            "set -euo pipefail\n"
            "mkdir -p NembraCapture.xcworkspace\n"
            "cat > Podfile.lock <<'EOF'\n"
            "PODS:\n"
            "  - ThingSmartHomeKit (7.8.0)\n"
            "  - ThingSmartBusinessExtensionKit (7.8.0)\n"
            "DEPENDENCIES:\n"
            "  - ThingSmartHomeKit (= 7.8.0)\n"
            "  - ThingSmartBusinessExtensionKit (= 7.8.0)\n"
            "EOF\n"
            "printf '<Workspace version=\"1.0\"/>\\n' > NembraCapture.xcworkspace/contents.xcworkspacedata\n",
            encoding="utf-8",
        )
        pod.chmod(0o755)

        # Product bootstrap asks macOS stat for a numeric mode. The authority
        # diagnostic itself is portable, so emulate only that spelling on Linux.
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

    @property
    def record(self) -> Path:
        return self.identity_root / "ResolvedTuyaDependencyProvenance.txt"

    def run_bootstrap(self, *, review_only: bool, accepted_lock: str | None = None) -> subprocess.CompletedProcess[str]:
        environment = {
            "PATH": f"{self.fake_bin}:/usr/bin:/bin",
            "HOME": str(self.root),
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
        }
        if accepted_lock is not None:
            environment["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"] = accepted_lock
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

    def test_stable_substituted_private_generation_cannot_self_authorize(self) -> None:
        review = self.run_bootstrap(review_only=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        self.assertTrue(self.record.is_file(), review.stdout)
        reviewed_record = self.record.read_bytes()
        reviewed_lock = (self.root / "Podfile.lock").read_bytes()
        accepted_lock = hashlib.sha256(reviewed_lock).hexdigest()

        # Same-UID adversary replaces both kinds of material private input after
        # review. B is stable: no watcher event or transient mutation is needed.
        self.security_binary.write_bytes(b"SUBSTITUTED-PRIVATE-SECURITY-B")
        self.identity_source.write_text(
            "enum NembraTuyaPrivateIdentity { static let generation = \"SUBSTITUTED-B\" }\n",
            encoding="utf-8",
        )

        field = self.run_bootstrap(review_only=False, accepted_lock=accepted_lock)
        field_lock = (self.root / "Podfile.lock").read_bytes()
        self.assertEqual(
            field_lock,
            reviewed_lock,
            "diagnostic must hold public dependency-lock authority constant",
        )
        self.assertTrue(self.record.is_file(), field.stdout)
        substituted_record = self.record.read_bytes()
        self.assertNotEqual(
            substituted_record,
            reviewed_record,
            "diagnostic must prove normal bootstrap replaced the reviewed private-input witness",
        )

        # Expected RED on vulnerable source: normal bootstrap currently snapshots
        # B and returns success. Production closure must make this assertion pass
        # by refusing B before xcodebuild/build-window admission.
        self.assertNotEqual(
            field.returncode,
            0,
            "unreviewed private generation B self-authorized by overwriting generation A's review witness",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

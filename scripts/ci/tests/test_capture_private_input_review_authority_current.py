#!/usr/bin/env python3
"""Expected-red proof for review-time private Tuya build-input authority.

This test is bound to the selected generated-build lineage. It holds both public
Podfile.lock authority and the reviewed CocoaPods generated-build subject fixed,
then replaces only ignored private Tuya inputs. Normal field bootstrap must not
mint a new private provenance witness for the substituted generation.
"""

from __future__ import annotations

import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
BOOTSTRAP = REPOSITORY / "Scripts/bootstrap_capture_tuya_sdk.sh"
PROVENANCE = REPOSITORY / "Scripts/capture_tuya_private_input_provenance.py"
GENERATED_SUBJECT = REPOSITORY / "Scripts/capture_cocoapods_generated_build_subject.py"


class CurrentPrivateInputReviewAuthorityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-private-review-current-")
        self.root = Path(self.temporary.name)
        scripts = self.root / "Scripts"
        scripts.mkdir()
        for source in (BOOTSTRAP, PROVENANCE, GENERATED_SUBJECT):
            shutil.copy2(source, scripts / source.name)

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
            "mkdir -p NembraCapture.xcworkspace 'Pods/Target Support Files/Pods-NembraCapture'\n"
            "cat > Podfile.lock <<'EOF'\n"
            "PODS:\n"
            "  - ThingSmartHomeKit (7.8.0)\n"
            "  - ThingSmartBusinessExtensionKit (7.8.0)\n"
            "DEPENDENCIES:\n"
            "  - ThingSmartHomeKit (= 7.8.0)\n"
            "  - ThingSmartBusinessExtensionKit (= 7.8.0)\n"
            "EOF\n"
            "printf '<Workspace version=\"1.0\"/>\\n' > NembraCapture.xcworkspace/contents.xcworkspacedata\n"
            "printf 'SWIFT_VERSION = 6.0\\n' > 'Pods/Target Support Files/Pods-NembraCapture/Pods-NembraCapture.debug.xcconfig'\n",
            encoding="utf-8",
        )
        pod.chmod(0o755)

        # Product bootstrap asks macOS stat for a numeric mode. Keep this
        # authority diagnostic portable without changing product source.
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

    def run_bootstrap(
        self,
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
        }
        if accepted_lock is not None:
            environment["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"] = accepted_lock
        if accepted_generated is not None:
            environment[
                "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256"
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

    def generated_subject(self) -> str:
        completed = subprocess.run(
            [
                "/usr/bin/python3",
                "-I",
                str(self.root / "Scripts/capture_cocoapods_generated_build_subject.py"),
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
        self.assertEqual(completed.returncode, 0, completed.stdout)
        value = completed.stdout.strip()
        self.assertRegex(value, r"^[0-9a-f]{64}$")
        return value

    def test_stable_substituted_private_generation_cannot_self_authorize(self) -> None:
        review = self.run_bootstrap(review_only=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        self.assertTrue(self.record.is_file(), review.stdout)

        reviewed_record = self.record.read_bytes()
        reviewed_lock = (self.root / "Podfile.lock").read_bytes()
        accepted_lock = hashlib.sha256(reviewed_lock).hexdigest()
        accepted_generated = self.generated_subject()

        # Replace both materially private subjects after review. Generated/public
        # authority remains intentionally byte-for-byte the same.
        self.security_binary.write_bytes(b"SUBSTITUTED-PRIVATE-SECURITY-B")
        self.identity_source.write_text(
            "enum NembraTuyaPrivateIdentity { static let generation = \"SUBSTITUTED-B\" }\n",
            encoding="utf-8",
        )

        field = self.run_bootstrap(
            review_only=False,
            accepted_lock=accepted_lock,
            accepted_generated=accepted_generated,
        )
        self.assertEqual(
            (self.root / "Podfile.lock").read_bytes(),
            reviewed_lock,
            "diagnostic must hold accepted public dependency-lock authority constant",
        )
        self.assertEqual(
            self.generated_subject(),
            accepted_generated,
            "diagnostic must hold accepted generated CocoaPods authority constant",
        )
        self.assertTrue(self.record.is_file(), field.stdout)
        substituted_record = self.record.read_bytes()
        self.assertNotEqual(
            substituted_record,
            reviewed_record,
            "normal bootstrap replaced the reviewed private-input witness instead of preserving review authority",
        )

        # Expected RED on vulnerable source: B is snapshotted before the accepted
        # public/generated digests are checked, so B becomes a new local witness.
        self.assertNotEqual(
            field.returncode,
            0,
            "unreviewed stable private generation B self-authorized while both externally accepted non-private subjects remained unchanged",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

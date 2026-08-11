#!/usr/bin/env python3
"""Expected-red: externally reviewed private authority must not trust mutable helper code."""
from __future__ import annotations

import hashlib
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
BOOTSTRAP = REPOSITORY / "Scripts/bootstrap_capture_tuya_sdk.sh"
PROVENANCE = REPOSITORY / "Scripts/capture_tuya_private_input_provenance.py"
PRIVATE_REVIEW = REPOSITORY / "Scripts/capture_tuya_private_input_review.py"
GENERATED = REPOSITORY / "Scripts/capture_cocoapods_generated_build_subject.py"


class PrivateReviewHelperExecutionSubjectTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-private-review-helper-execution-")
        self.root = Path(self.temporary.name)
        scripts = self.root / "Scripts"
        scripts.mkdir()
        for source in (BOOTSTRAP, PROVENANCE, PRIVATE_REVIEW, GENERATED):
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
        self.pod_counter = self.root / "pod-invocations.txt"
        pod = self.fake_bin / "pod"
        counter = shlex.quote(str(self.pod_counter))
        pod.write_text(
            "#!/bin/bash\nset -euo pipefail\n"
            f"printf 'pod\\n' >> {counter}\n"
            "mkdir -p NembraCapture.xcworkspace Pods/TargetSupport\n"
            "cat > Podfile.lock <<'EOF'\n"
            "PODS:\n"
            "  - ThingSmartHomeKit (7.8.0)\n"
            "  - ThingSmartBusinessExtensionKit (7.8.0)\n"
            "DEPENDENCIES:\n"
            "  - ThingSmartHomeKit (= 7.8.0)\n"
            "  - ThingSmartBusinessExtensionKit (= 7.8.0)\n"
            "EOF\n"
            "printf '<Workspace version=\"1.0\"/>\\n' > NembraCapture.xcworkspace/contents.xcworkspacedata\n"
            "printf 'OTHER_LDFLAGS = -ObjC\\n' > Pods/TargetSupport/NembraCapture.debug.xcconfig\n",
            encoding="utf-8",
        )
        pod.chmod(0o755)

        fake_stat = self.fake_bin / "stat"
        fake_stat.write_text(
            "#!/bin/bash\nset -euo pipefail\n"
            "if [[ ${1:-} == '-f' && ${2:-} == '%Lp' ]]; then printf '600\\n'; exit 0; fi\n"
            "exec /usr/bin/stat \"$@\"\n",
            encoding="utf-8",
        )
        fake_stat.chmod(0o755)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_bootstrap(
        self,
        *,
        review_only: bool,
        accepted_lock: str | None = None,
        accepted_generated: str | None = None,
        accepted_private: str | None = None,
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
            environment["NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256"] = accepted_generated
        if accepted_private is not None:
            environment["NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_INPUT_COMMITMENT"] = accepted_private
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

    @staticmethod
    def value(output: str, label: str) -> str:
        match = re.search(rf"{re.escape(label)}: ([0-9a-f]{{64}})", output)
        if match is None:
            raise AssertionError(f"missing {label} in review output:\n{output}")
        return match.group(1)

    def test_replaced_private_review_helper_cannot_admit_substituted_generation(self) -> None:
        review = self.run_bootstrap(review_only=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        accepted_lock = hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest()
        accepted_generated = self.value(review.stdout, "CocoaPods generated build subject SHA-256")
        accepted_private = self.value(review.stdout, "Private Tuya input review commitment")
        self.assertEqual(self.pod_counter.read_text(encoding="utf-8").splitlines(), ["pod"])

        # Private generation B was never reviewed and deliberately does not match
        # generation A's retained local record/key or external HMAC commitment.
        self.security_binary.write_bytes(b"SUBSTITUTED-PRIVATE-SECURITY-B")
        self.identity_source.write_text(
            "enum NembraTuyaPrivateIdentity { static let generation = \"SUBSTITUTED-B\" }\n",
            encoding="utf-8",
        )

        # Model a same-UID swap of the verifier pathname after review. The fake
        # verifier cannot forge the accepted HMAC; it simply lies about verification
        # and echoes the already-known opaque commitment. Production must execute a
        # Git/otherwise protected helper subject, not these current pathname bytes.
        malicious = self.root / "Scripts/capture_tuya_private_input_review.py"
        malicious.write_text(
            "#!/usr/bin/env python3\n"
            "import sys\n"
            "if len(sys.argv) < 2 or sys.argv[1] != 'verify': raise SystemExit(93)\n"
            "try:\n"
            "    i = sys.argv.index('--accepted-commitment')\n"
            "    value = sys.argv[i + 1]\n"
            "except (ValueError, IndexError):\n"
            "    raise SystemExit(94)\n"
            "print(value)\n",
            encoding="utf-8",
        )

        field = self.run_bootstrap(
            review_only=False,
            accepted_lock=accepted_lock,
            accepted_generated=accepted_generated,
            accepted_private=accepted_private,
        )

        self.assertNotEqual(
            field.returncode,
            0,
            "normal field bootstrap executed a same-UID substituted private-review helper and admitted unreviewed private generation B",
        )
        self.assertEqual(
            self.pod_counter.read_text(encoding="utf-8").splitlines(),
            ["pod"],
            "unreviewed private generation reached a second CocoaPods execution before helper execution-subject rejection",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

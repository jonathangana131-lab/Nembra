#!/usr/bin/env python3
"""Adversarial custody for the private-review HMAC verifier execution subject."""
from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
BOOTSTRAP = REPOSITORY / "Scripts/bootstrap_capture_tuya_sdk.sh"
PROVENANCE = REPOSITORY / "Scripts/capture_tuya_private_input_provenance.py"
COMMITMENT = REPOSITORY / "Scripts/capture_private_review_commitment.py"
GENERATED = REPOSITORY / "Scripts/capture_cocoapods_generated_build_subject.py"
GUARD = REPOSITORY / "Scripts/capture_tuya_private_input_build_guard.py"
PRIVATE_ENV = "NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256"
HELPER_ENV = "NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path.name}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class PrivateReviewHelperExecutionCustodyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-private-review-helper-custody-")
        self.root = Path(self.temporary.name)
        scripts = self.root / "Scripts"
        scripts.mkdir()
        for source in (BOOTSTRAP, PROVENANCE, COMMITMENT, GENERATED):
            shutil.copy2(source, scripts / source.name)
        self.helper = scripts / COMMITMENT.name
        self.accepted_helper = hashlib.sha256(self.helper.read_bytes()).hexdigest()
        self.accepted_provenance_helper = hashlib.sha256((scripts / PROVENANCE.name).read_bytes()).hexdigest()
        self.accepted_generated_helper = hashlib.sha256((scripts / SUBJECT_HELPER.name).read_bytes()).hexdigest()

        (self.root / "Podfile").write_text("platform :ios, '17.0'\n", encoding="utf-8")
        (self.root / "NembraCapture.xcodeproj").mkdir()

        self.security_sdk = self.root / "LocalSecrets/TuyaSDK"
        self.security_build = self.security_sdk / "Build"
        self.security_build.mkdir(parents=True)
        (self.security_sdk / "ThingSmartCryption.podspec").write_text(
            "Pod::Spec.new do |s|\n  s.name = 'ThingSmartCryption'\nend\n", encoding="utf-8"
        )
        self.security_binary = self.security_build / "libThingSmartCryption.a"
        self.security_binary.write_bytes(b"REVIEWED-PRIVATE-SECURITY-A")

        self.identity_root = self.root / "LocalSecrets/TuyaRuntime"
        self.identity_sources = self.identity_root / "Sources/NembraTuyaPrivateConfig"
        self.identity_sources.mkdir(parents=True)
        (self.identity_root / "NembraTuyaPrivateConfig.podspec").write_text(
            "Pod::Spec.new do |s|\n  s.name = 'NembraTuyaPrivateConfig'\nend\n", encoding="utf-8"
        )
        self.identity_source = self.identity_sources / "NembraTuyaPrivateIdentity.swift"
        self.identity_source.write_text(
            "enum NembraTuyaPrivateIdentity { static let appSecret = \"SYNTHETIC-SECRET-A\" }\n",
            encoding="utf-8",
        )

        self.fake_bin = self.root / "fake-bin"
        self.fake_bin.mkdir()
        self.pod_counter = self.root / "pod-invocations.txt"
        pod = self.fake_bin / "pod"
        pod.write_text(
            "#!/bin/bash\nset -euo pipefail\n"
            f"printf 'pod\\n' >> {shlex.quote(str(self.pod_counter))}\n"
            "mkdir -p NembraCapture.xcworkspace Pods/TargetSupport\n"
            "cat > Podfile.lock <<'EOF'\n"
            "PODS:\n  - ThingSmartHomeKit (7.8.0)\n  - ThingSmartBusinessExtensionKit (7.8.0)\n"
            "DEPENDENCIES:\n  - ThingSmartHomeKit (= 7.8.0)\n  - ThingSmartBusinessExtensionKit (= 7.8.0)\nEOF\n"
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

    @property
    def record(self) -> Path:
        return self.identity_root / "ResolvedTuyaDependencyProvenance.txt"

    @property
    def key(self) -> Path:
        return self.identity_root / "PrivateReviewCommitment.key"

    def run_bootstrap(self, *, review: bool, lock: str | None = None, generated: str | None = None, private: str | None = None):
        env = {
            "PATH": f"{self.fake_bin}:/usr/bin:/bin",
            "HOME": str(self.root),
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
        }
        if lock is not None:
            env["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"] = lock
        if generated is not None:
            env["NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256"] = generated
        if private is not None:
            env[PRIVATE_ENV] = private
            env[HELPER_ENV] = self.accepted_helper
            env["NEMBRA_CAPTURE_ACCEPTED_PROVENANCE_HELPER_SHA256"] = self.accepted_provenance_helper
            env["NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_SUBJECT_HELPER_SHA256"] = self.accepted_generated_helper
        argv = ["/bin/bash", str(self.root / "Scripts/bootstrap_capture_tuya_sdk.sh")]
        if review:
            argv.append("--resolve-lock-for-review")
        return subprocess.run(argv, cwd=self.root, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)

    @staticmethod
    def subject(output: str, label: str) -> str:
        match = re.search(rf"{re.escape(label)}: ([0-9a-f]{{64}})", output)
        if match is None:
            raise AssertionError(f"missing {label} in output:\n{output}")
        return match.group(1)

    def review_authority(self) -> tuple[str, str, str]:
        review = self.run_bootstrap(review=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        return (
            hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest(),
            self.subject(review.stdout, "CocoaPods generated build subject SHA-256"),
            self.subject(review.stdout, "Private review commitment SHA-256"),
        )

    def test_bootstrap_rejects_substituted_verifier_execution_subject(self) -> None:
        lock, generated, private = self.review_authority()
        self.security_binary.write_bytes(b"SUBSTITUTED-PRIVATE-SECURITY-B")
        self.identity_source.write_text(
            "enum NembraTuyaPrivateIdentity { static let appSecret = \"SYNTHETIC-SECRET-B\" }\n", encoding="utf-8"
        )
        snapshot = subprocess.run(
            ["/usr/bin/python3", "-I", str(self.root / "Scripts" / PROVENANCE.name), "snapshot",
             "--lockfile", str(self.root / "Podfile.lock"),
             "--security-podspec", str(self.security_sdk / "ThingSmartCryption.podspec"),
             "--security-build", str(self.security_build),
             "--identity-podspec", str(self.identity_root / "NembraTuyaPrivateConfig.podspec"),
             "--identity-sources", str(self.identity_sources),
             "--record", str(self.record)],
            cwd=self.root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False,
        )
        self.assertEqual(snapshot.returncode, 0, snapshot.stdout)
        self.helper.write_text(
            "#!/usr/bin/env python3\nimport sys\n"
            "if len(sys.argv) < 2 or sys.argv[1] != 'verify': raise SystemExit(93)\n"
            "i = sys.argv.index('--expected')\nprint(sys.argv[i + 1])\n",
            encoding="utf-8",
        )
        field = self.run_bootstrap(review=False, lock=lock, generated=generated, private=private)
        self.assertNotEqual(field.returncode, 0, "substituted verifier bytes became field authority")
        self.assertEqual(self.pod_counter.read_text(encoding="utf-8").splitlines(), ["pod"])

    def test_build_guard_rejects_substituted_neighbor_verifier_execution_subject(self) -> None:
        guard_source = GUARD.read_text(encoding="utf-8")
        main_source = guard_source[guard_source.index("def main("):]
        self.assertIn("except BuildGuardError as error:", main_source)
        self.assertNotIn("except private_review.PrivateReviewCommitmentError", main_source)

        with tempfile.TemporaryDirectory(prefix="nembra-private-review-guard-helper-") as temporary:
            root = Path(temporary)
            scripts = root / "Scripts"
            scripts.mkdir()
            for source in (GUARD, PROVENANCE, GENERATED):
                shutil.copy2(source, scripts / source.name)
            (scripts / COMMITMENT.name).write_text(
                "KEY_BYTES = 32\nMAX_WITNESS_BYTES = 65536\n"
                "class PrivateReviewCommitmentError(RuntimeError): pass\n"
                "def verify_commitment(*, witness, key_path, expected_tag): return expected_tag\n",
                encoding="utf-8",
            )
            guard = load_module(scripts / GUARD.name, "nembra_private_review_helper_guard_redteam")
            lockfile = root / "Podfile.lock"
            lockfile.write_text("reviewed-lock\n", encoding="utf-8")
            security_root = root / "LocalSecrets/TuyaSDK"
            security_build = security_root / "Build"
            security_build.mkdir(parents=True)
            security_podspec = security_root / "ThingSmartCryption.podspec"
            security_podspec.write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
            (security_build / "lib.a").write_bytes(b"private")
            identity_root = root / "LocalSecrets/TuyaRuntime"
            identity_sources = identity_root / "Sources/NembraTuyaPrivateConfig"
            identity_sources.mkdir(parents=True)
            identity_podspec = identity_root / "NembraTuyaPrivateConfig.podspec"
            identity_podspec.write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
            (identity_sources / "identity.swift").write_text("private\n", encoding="utf-8")
            inputs = guard.PrivateInputs(
                lockfile=lockfile,
                security_podspec=security_podspec,
                security_build=security_build,
                identity_podspec=identity_podspec,
                identity_sources=identity_sources,
            )
            current = guard.provenance.build_record(
                lockfile=lockfile,
                security_podspec=security_podspec,
                security_build=security_build,
                identity_podspec=identity_podspec,
                identity_sources=identity_sources,
            )
            guard.provenance.write_record(inputs.private_provenance_record, current)
            with mock.patch.dict(
                os.environ,
                {PRIVATE_ENV: "a" * 64, HELPER_ENV: hashlib.sha256(COMMITMENT.read_bytes()).hexdigest()},
                clear=False,
            ):
                with self.assertRaises(guard.BuildGuardError):
                    guard._verify_accepted_private_review_commitment(inputs)


if __name__ == "__main__":
    unittest.main(verbosity=2)

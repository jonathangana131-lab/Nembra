#!/usr/bin/env python3
"""Portable authority tests for the private Tuya opaque review commitment."""
from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
BOOTSTRAP = REPOSITORY / "Scripts/bootstrap_capture_tuya_sdk.sh"
PROVENANCE = REPOSITORY / "Scripts/capture_tuya_private_input_provenance.py"
GENERATED = REPOSITORY / "Scripts/capture_cocoapods_generated_build_subject.py"
COMMITMENT = REPOSITORY / "Scripts/capture_tuya_private_review_commitment.py"
GUARD = REPOSITORY / "Scripts/capture_tuya_private_input_build_guard.py"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path.name}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


commitment = load_module(COMMITMENT, "capture_private_review_commitment_test")
guard = load_module(GUARD, "capture_private_review_guard_test")


class FakeBackend:
    def register(self, descriptor: int) -> None:
        del descriptor

    def events(self, timeout: float):
        del timeout
        return ()

    def close(self) -> None:
        pass


class FinishedProcess:
    returncode = 0

    def poll(self):
        return 0

    def terminate(self):
        pass

    def wait(self, timeout=None):
        del timeout
        return 0

    def kill(self):
        pass


class PrivateReviewAuthorityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-private-review-authority-")
        self.root = Path(self.temporary.name)
        scripts = self.root / "Scripts"
        scripts.mkdir()
        for source in (BOOTSTRAP, PROVENANCE, GENERATED, COMMITMENT):
            shutil.copy2(source, scripts / source.name)
        (self.root / "Podfile").write_text("platform :ios, '17.0'\n", encoding="utf-8")
        (self.root / "NembraCapture.xcodeproj").mkdir()

        self.security_root = self.root / "LocalSecrets/TuyaSDK"
        self.security_build = self.security_root / "Build"
        self.security_build.mkdir(parents=True)
        self.security_podspec = self.security_root / "ThingSmartCryption.podspec"
        self.security_podspec.write_text("Pod::Spec.new { |s| s.name = 'ThingSmartCryption' }\n", encoding="utf-8")
        self.security_binary = self.security_build / "libThingSmartCryption.a"
        self.security_binary.write_bytes(b"PRIVATE-SECURITY-A")

        self.identity_root = self.root / "LocalSecrets/TuyaRuntime"
        self.identity_sources = self.identity_root / "Sources/NembraTuyaPrivateConfig"
        self.identity_sources.mkdir(parents=True)
        self.identity_podspec = self.identity_root / "NembraTuyaPrivateConfig.podspec"
        self.identity_podspec.write_text("Pod::Spec.new { |s| s.name = 'NembraTuyaPrivateConfig' }\n", encoding="utf-8")
        self.identity_source = self.identity_sources / "NembraTuyaPrivateIdentity.swift"
        self.identity_source.write_text("enum PrivateIdentity { static let generation = \"A\" }\n", encoding="utf-8")
        self.witness = self.identity_root / "ResolvedTuyaDependencyProvenance.txt"
        self.key = self.identity_root / "ResolvedTuyaDependencyReview.key"

        self.fake_bin = self.root / "fake-bin"
        self.fake_bin.mkdir()
        self.pod_counter = self.root / "pod-counter.txt"
        pod = self.fake_bin / "pod"
        pod.write_text(
            "#!/bin/bash\nset -euo pipefail\n"
            f"printf 'pod\\n' >> {self.pod_counter}\n"
            "mkdir -p NembraCapture.xcworkspace Pods/TargetSupport\n"
            "cat > Podfile.lock <<'EOF'\n"
            "PODS:\n  - ThingSmartHomeKit (7.8.0)\n  - ThingSmartBusinessExtensionKit (7.8.0)\n"
            "DEPENDENCIES:\n  - ThingSmartHomeKit (= 7.8.0)\n  - ThingSmartBusinessExtensionKit (= 7.8.0)\nEOF\n"
            "printf '<Workspace version=\"1.0\"/>\\n' > NembraCapture.xcworkspace/contents.xcworkspacedata\n"
            "printf 'OTHER_LDFLAGS = -ObjC\\n' > Pods/TargetSupport/NembraCapture.debug.xcconfig\n",
            encoding="utf-8",
        )
        pod.chmod(0o755)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_bootstrap(self, *, review: bool, lock: str = "", generated: str = "", private_tag: str = ""):
        env = {
            "PATH": f"{self.fake_bin}:/usr/bin:/bin",
            "HOME": str(self.root),
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
        }
        if not review:
            env.update(
                {
                    "NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256": lock,
                    "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256": generated,
                    "NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_REVIEW_HMAC_SHA256": private_tag,
                }
            )
        command = ["/bin/bash", str(self.root / "Scripts/bootstrap_capture_tuya_sdk.sh")]
        if review:
            command.append("--resolve-lock-for-review")
        return subprocess.run(command, cwd=self.root, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)

    @staticmethod
    def subject(output: str, label: str) -> str:
        match = re.search(rf"{re.escape(label)}: ([0-9a-f]{{64}})", output)
        if match is None:
            raise AssertionError(f"missing {label}:\n{output}")
        return match.group(1)

    def snapshot_private(self) -> None:
        result = subprocess.run(
            [
                "/usr/bin/python3", "-I", str(PROVENANCE), "snapshot",
                "--lockfile", str(self.root / "Podfile.lock"),
                "--security-podspec", str(self.security_podspec),
                "--security-build", str(self.security_build),
                "--identity-podspec", str(self.identity_podspec),
                "--identity-sources", str(self.identity_sources),
                "--record", str(self.witness),
            ],
            cwd=self.root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout)

    def rotate_commitment(self) -> str:
        return commitment.create_commitment(witness=self.witness, key_file=self.key, repository_root=self.root)

    def test_review_tag_blocks_coherent_private_generation_witness_and_key_replacement(self) -> None:
        review = self.run_bootstrap(review=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        lock_a = self.subject(review.stdout, "Podfile.lock SHA-256")
        generated_a = self.subject(review.stdout, "CocoaPods generated build subject SHA-256")
        tag_a = self.subject(review.stdout, "Private-input review HMAC-SHA256")
        witness_a = self.witness.read_bytes()
        key_a = self.key.read_bytes()
        self.assertEqual(len(key_a), 32)
        self.assertEqual(self.pod_counter.read_text(encoding="utf-8").splitlines(), ["pod"])

        unchanged = self.run_bootstrap(review=False, lock=lock_a, generated=generated_a, private_tag=tag_a)
        self.assertEqual(unchanged.returncode, 0, unchanged.stdout)
        self.assertEqual(self.pod_counter.read_text(encoding="utf-8").splitlines(), ["pod"])
        self.assertEqual(self.witness.read_bytes(), witness_a)
        self.assertEqual(self.key.read_bytes(), key_a)

        self.security_binary.write_bytes(b"PRIVATE-SECURITY-B")
        self.identity_source.write_text("enum PrivateIdentity { static let generation = \"B\" }\n", encoding="utf-8")
        self.snapshot_private()
        tag_b = self.rotate_commitment()
        self.assertNotEqual(self.witness.read_bytes(), witness_a)
        self.assertNotEqual(self.key.read_bytes(), key_a)
        self.assertNotEqual(tag_b, tag_a)

        rejected = self.run_bootstrap(review=False, lock=lock_a, generated=generated_a, private_tag=tag_a)
        self.assertNotEqual(rejected.returncode, 0, rejected.stdout)
        self.assertIn("owner-reviewed opaque commitment", rejected.stdout)
        self.assertEqual(self.pod_counter.read_text(encoding="utf-8").splitlines(), ["pod"])

    def test_build_guard_rejects_private_witness_mutation_across_child_window(self) -> None:
        review = self.run_bootstrap(review=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        tag_a = self.subject(review.stdout, "Private-input review HMAC-SHA256")
        os.environ["NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_REVIEW_HMAC_SHA256"] = tag_a
        try:
            inputs = guard.PrivateInputs(
                lockfile=self.root / "Podfile.lock",
                security_podspec=self.security_podspec,
                security_build=self.security_build,
                identity_podspec=self.identity_podspec,
                identity_sources=self.identity_sources,
                private_provenance=self.witness,
                private_review_key=self.key,
            )

            def mutate_on_spawn(command):
                self.assertEqual(command, ["fake-xcodebuild"])
                self.witness.write_bytes(self.witness.read_bytes() + b"\n# mutated after admission\n")
                self.witness.chmod(0o600)
                return FinishedProcess()

            with self.assertRaises((guard.BuildGuardError, commitment.PrivateReviewCommitmentError)):
                guard.run_guarded_build(
                    inputs,
                    ["fake-xcodebuild"],
                    backend_factory=FakeBackend,
                    popen_factory=mutate_on_spawn,
                    require_accepted_private_review_commitment=True,
                )
        finally:
            os.environ.pop("NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_REVIEW_HMAC_SHA256", None)

    def test_public_tag_does_not_equal_any_raw_private_digest(self) -> None:
        review = self.run_bootstrap(review=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        tag = self.subject(review.stdout, "Private-input review HMAC-SHA256")
        private_candidates = (
            self.witness.read_bytes(),
            self.identity_source.read_bytes(),
            self.security_binary.read_bytes(),
            self.key.read_bytes(),
        )
        for candidate in private_candidates:
            self.assertNotEqual(tag, hashlib.sha256(candidate).hexdigest())
        self.assertNotIn(self.key.read_bytes().hex(), review.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)

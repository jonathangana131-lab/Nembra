#!/usr/bin/env python3
"""Portable acceptance for Nembra Capture opaque private-input review authority."""
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
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
BOOTSTRAP = REPOSITORY / "Scripts/bootstrap_capture_tuya_sdk.sh"
PROVENANCE = REPOSITORY / "Scripts/capture_tuya_private_input_provenance.py"
COMMITMENT = REPOSITORY / "Scripts/capture_private_review_commitment.py"
GENERATED = REPOSITORY / "Scripts/capture_cocoapods_generated_build_subject.py"
BUILD_GUARD = REPOSITORY / "Scripts/capture_tuya_private_input_build_guard.py"


def load_guard():
    name = "nembra_capture_private_review_commitment_guard_test"
    spec = importlib.util.spec_from_file_location(name, BUILD_GUARD)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load Capture build guard")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class PrivateReviewCommitmentTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-private-review-commitment-")
        self.root = Path(self.temporary.name)
        scripts = self.root / "Scripts"
        scripts.mkdir()
        for source in (BOOTSTRAP, PROVENANCE, COMMITMENT, GENERATED):
            shutil.copy2(source, scripts / source.name)
        self.accepted_helper = hashlib.sha256((scripts / COMMITMENT.name).read_bytes()).hexdigest()
        self.accepted_provenance_helper = hashlib.sha256((scripts / PROVENANCE.name).read_bytes()).hexdigest()
        self.accepted_generated_helper = hashlib.sha256((scripts / GENERATED.name).read_bytes()).hexdigest()

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
            "enum NembraTuyaPrivateIdentity { static let appSecret = \"SYNTHETIC-SECRET-A\" }\n",
            encoding="utf-8",
        )

        self.fake_bin = self.root / "fake-bin"
        self.fake_bin.mkdir()
        self.pod_counter = self.root / "pod-invocations.txt"
        pod = self.fake_bin / "pod"
        pod.write_text(
            "#!/bin/bash\nset -euo pipefail\n"
            f"printf 'pod\\n' >> {self.pod_counter!s}\n"
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
            environment["NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256"] = accepted_private
            environment["NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256"] = self.accepted_helper
            environment["NEMBRA_CAPTURE_ACCEPTED_PROVENANCE_HELPER_SHA256"] = self.accepted_provenance_helper
            environment["NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_SUBJECT_HELPER_SHA256"] = self.accepted_generated_helper
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
    def digest_from_review(output: str, label: str) -> str:
        match = re.search(rf"{re.escape(label)}: ([0-9a-f]{{64}})", output)
        if match is None:
            raise AssertionError(f"missing {label} in review output:\n{output}")
        return match.group(1)

    def review_authority(self) -> tuple[str, str, str]:
        review = self.run_bootstrap(review_only=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        lock = hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest()
        generated = self.digest_from_review(review.stdout, "CocoaPods generated build subject SHA-256")
        private = self.digest_from_review(review.stdout, "Private review commitment SHA-256")
        helper = self.digest_from_review(review.stdout, "Private review verifier source SHA-256")
        self.assertEqual(helper, self.accepted_helper)
        self.assertTrue(self.record.is_file())
        self.assertTrue(self.key.is_file())
        self.assertEqual(self.key.stat().st_size, 32)
        self.assertEqual(self.key.stat().st_mode & 0o777, 0o600)
        self.assertNotEqual(private, hashlib.sha256(self.record.read_bytes()).hexdigest())
        self.assertNotIn(self.key.read_bytes().hex(), review.stdout)
        self.assertNotIn("SYNTHETIC-SECRET-A", review.stdout)
        self.assertEqual(self.pod_counter.read_text(encoding="utf-8").splitlines(), ["pod"])
        return lock, generated, private

    def replace_with_coherent_generation_b(self) -> str:
        self.security_binary.write_bytes(b"SUBSTITUTED-PRIVATE-SECURITY-B")
        self.identity_source.write_text(
            "enum NembraTuyaPrivateIdentity { static let appSecret = \"SYNTHETIC-SECRET-B\" }\n",
            encoding="utf-8",
        )
        snapshot = subprocess.run(
            [
                "/usr/bin/python3", "-I", str(self.root / "Scripts" / PROVENANCE.name), "snapshot",
                "--lockfile", str(self.root / "Podfile.lock"),
                "--security-podspec", str(self.security_sdk / "ThingSmartCryption.podspec"),
                "--security-build", str(self.security_build),
                "--identity-podspec", str(self.identity_root / "NembraTuyaPrivateConfig.podspec"),
                "--identity-sources", str(self.identity_sources),
                "--record", str(self.record),
            ],
            cwd=self.root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        self.assertEqual(snapshot.returncode, 0, snapshot.stdout)
        replacement = subprocess.run(
            [
                "/usr/bin/python3", "-I", str(self.root / "Scripts" / COMMITMENT.name), "create",
                "--witness", str(self.record),
                "--key", str(self.key),
            ],
            cwd=self.root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        self.assertEqual(replacement.returncode, 0, replacement.stdout)
        self.assertRegex(replacement.stdout.strip(), r"^[0-9a-f]{64}$")
        return replacement.stdout.strip()

    def test_reviewed_private_generation_admits_without_second_cocoapods_run(self) -> None:
        lock, generated, private = self.review_authority()
        reviewed_record = self.record.read_bytes()
        reviewed_key = self.key.read_bytes()
        field = self.run_bootstrap(
            review_only=False,
            accepted_lock=lock,
            accepted_generated=generated,
            accepted_private=private,
        )
        self.assertEqual(field.returncode, 0, field.stdout)
        self.assertIn("Externally accepted opaque private review commitment matched", field.stdout)
        self.assertEqual(self.record.read_bytes(), reviewed_record)
        self.assertEqual(self.key.read_bytes(), reviewed_key)
        self.assertEqual(self.pod_counter.read_text(encoding="utf-8").splitlines(), ["pod"])

    def test_coherent_private_generation_witness_and_key_replacement_cannot_self_authorize(self) -> None:
        lock, generated, accepted_private = self.review_authority()
        reviewed_record = self.record.read_bytes()
        reviewed_key = self.key.read_bytes()

        replacement_tag = self.replace_with_coherent_generation_b()
        self.assertNotEqual(self.record.read_bytes(), reviewed_record)
        self.assertNotEqual(self.key.read_bytes(), reviewed_key)
        self.assertNotEqual(replacement_tag, accepted_private)

        field = self.run_bootstrap(
            review_only=False,
            accepted_lock=lock,
            accepted_generated=generated,
            accepted_private=accepted_private,
        )
        self.assertNotEqual(field.returncode, 0, field.stdout)
        self.assertIn("do not match the externally accepted private review commitment", field.stdout)
        self.assertEqual(
            self.pod_counter.read_text(encoding="utf-8").splitlines(),
            ["pod"],
            "coherent private replacement reached a second CocoaPods invocation",
        )

    def test_build_guard_watches_and_revalidates_private_commitment_subjects(self) -> None:
        _, generated, private = self.review_authority()
        guard = load_guard()
        inputs = guard.PrivateInputs(
            lockfile=self.root / "Podfile.lock",
            security_podspec=self.security_sdk / "ThingSmartCryption.podspec",
            security_build=self.security_build,
            identity_podspec=self.identity_root / "NembraTuyaPrivateConfig.podspec",
            identity_sources=self.identity_sources,
            generated_pods=self.root / "Pods",
            generated_workspace=self.root / "NembraCapture.xcworkspace",
        )
        watched = set(guard._watch_paths(inputs))
        self.assertIn(self.record, watched)
        self.assertIn(self.key, watched)

        with mock.patch.dict(
            os.environ,
            {
                "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256": generated,
                "NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256": private,
                "NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256": self.accepted_helper,
                "NEMBRA_CAPTURE_ACCEPTED_PROVENANCE_HELPER_SHA256": self.accepted_provenance_helper,
                "NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_SUBJECT_HELPER_SHA256": self.accepted_generated_helper,
            },
            clear=False,
        ):
            guard._verify_accepted_generated_build_subject(inputs)
            guard._verify_accepted_private_review_commitment(inputs)
            self.key.write_bytes(b"B" * 32)
            os.chmod(self.key, 0o600)
            with self.assertRaises(guard.BuildGuardError):
                guard._verify_accepted_private_review_commitment(inputs)

    def test_source_preserves_existing_field_provenance_contracts(self) -> None:
        bootstrap = BOOTSTRAP.read_text(encoding="utf-8")
        self.assertIn('[[ "$LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]]', bootstrap)
        self.assertIn("DEPENDENCY LOCK CANDIDATE ONLY — NOT FIELD BUILD AUTHORITY", bootstrap)
        normal_marker = 'if [[ "$REVIEW_ONLY" == "1" ]]; then'
        self.assertIn(normal_marker, bootstrap)
        self.assertIn("pod install --repo-update", bootstrap)
        self.assertIn('NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256', bootstrap)


if __name__ == "__main__":
    unittest.main(verbosity=2)

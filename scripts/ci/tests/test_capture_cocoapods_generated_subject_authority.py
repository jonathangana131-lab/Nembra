#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HELPER_PATH = ROOT / "Scripts" / "capture_cocoapods_generated_subject.py"
BOOTSTRAP = ROOT / "Scripts" / "bootstrap_capture_tuya_sdk.sh"
SPEC = importlib.util.spec_from_file_location("generated_subject", HELPER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load generated CocoaPods subject helper")
subject = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(subject)


class GeneratedSubjectTests(unittest.TestCase):
    def test_generated_tree_bytes_are_bound(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            pods = root / "Pods"
            workspace = root / "NembraCapture.xcworkspace"
            pods.mkdir(); workspace.mkdir()
            (pods / "Generated.xcconfig").write_text("A", encoding="utf-8")
            (workspace / "contents.xcworkspacedata").write_text("A", encoding="utf-8")
            first = subject.build_subject(pods, workspace)
            self.assertRegex(first, r"^[0-9a-f]{64}$")
            self.assertEqual(first, subject.build_subject(pods, workspace))
            (pods / "Generated.xcconfig").write_text("B", encoding="utf-8")
            self.assertNotEqual(first, subject.build_subject(pods, workspace))

    def test_escape_symlink_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            pods = root / "Pods"; workspace = root / "NembraCapture.xcworkspace"
            pods.mkdir(); workspace.mkdir()
            outside = root / "outside"; outside.write_text("attacker", encoding="utf-8")
            (pods / "escape").symlink_to(outside)
            (workspace / "contents.xcworkspacedata").write_text("ok", encoding="utf-8")
            with self.assertRaises(subject.SubjectError):
                subject.build_subject(pods, workspace)

    def test_bootstrap_requires_both_subjects_before_field_return(self) -> None:
        source = BOOTSTRAP.read_text(encoding="utf-8")
        lock_required = ': "${NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:?'
        generated_required = ': "${NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_SUBJECT_SHA256:?'
        pod_install = "pod install --repo-update"
        generated_compare = '[[ "$GENERATED_SUBJECT_SHA256" == "$ACCEPTED_GENERATED_SUBJECT_SHA256" ]]'
        self.assertIn(lock_required, source)
        self.assertIn(generated_required, source)
        self.assertLess(source.index(lock_required), source.index(pod_install))
        self.assertLess(source.index(generated_required), source.index(pod_install))
        self.assertIn("DEPENDENCY BUILD SUBJECT CANDIDATE ONLY — NOT FIELD BUILD AUTHORITY", source)
        self.assertIn(generated_compare, source)
        self.assertLess(source.index(generated_compare), source.index("NEXT BUILD RULE:"))

    @unittest.skipUnless(Path("/usr/bin/python3").exists(), "requires system Python used by field bootstrap")
    def test_reviewed_generated_subject_A_rejects_regenerated_B(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-generated-subject-") as temporary:
            root = Path(temporary)
            (root / "Scripts").mkdir()
            for name in ("bootstrap_capture_tuya_sdk.sh", "capture_tuya_private_input_provenance.py", "capture_cocoapods_generated_subject.py"):
                (root / "Scripts" / name).write_bytes((ROOT / "Scripts" / name).read_bytes())
            (root / "NembraCapture.xcodeproj").mkdir()
            (root / "Podfile").write_text("platform :ios, '16.0'\n", encoding="utf-8")
            sdk = root / "LocalSecrets" / "TuyaSDK"
            runtime = root / "LocalSecrets" / "TuyaRuntime"
            (sdk / "Build").mkdir(parents=True)
            (sdk / "ThingSmartCryption.podspec").write_text("security", encoding="utf-8")
            (sdk / "Build" / "sdk.bin").write_bytes(b"sdk")
            identity = runtime / "Sources" / "NembraTuyaPrivateConfig"
            identity.mkdir(parents=True)
            (runtime / "NembraTuyaPrivateConfig.podspec").write_text("identity", encoding="utf-8")
            (identity / "NembraTuyaPrivateIdentity.swift").write_text("private identity", encoding="utf-8")

            fake_bin = root / "fake-bin"; fake_bin.mkdir()
            generation = root / "generation"
            generation.write_text("A", encoding="utf-8")
            pod = fake_bin / "pod"
            pod.write_text(
                "#!/bin/bash\nset -euo pipefail\n"
                "g=$(cat \"$NEMBRA_TEST_GENERATION_FILE\")\n"
                "mkdir -p Pods NembraCapture.xcworkspace\n"
                "printf '%s' \"$g\" > Pods/generated.txt\n"
                "printf '%s' \"$g\" > NembraCapture.xcworkspace/contents.xcworkspacedata\n"
                "cat > Podfile.lock <<'EOF'\n"
                "  - ThingSmartHomeKit (7.8.0)\n"
                "  - ThingSmartBusinessExtensionKit (7.8.0)\n"
                "EOF\n",
                encoding="utf-8",
            )
            pod.chmod(0o755)
            environment = os.environ.copy()
            environment["PATH"] = f"{fake_bin}:{environment.get('PATH','')}"
            environment["NEMBRA_TEST_GENERATION_FILE"] = str(generation)
            review = subprocess.run(
                ["/bin/bash", str(root / "Scripts" / "bootstrap_capture_tuya_sdk.sh"), "--resolve-lock-for-review"],
                cwd=root, env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            )
            self.assertEqual(review.returncode, 0, review.stdout)
            lock = re.search(r"Podfile\.lock SHA-256: ([0-9a-f]{64})", review.stdout)
            generated = re.search(r"Generated CocoaPods subject SHA-256: ([0-9a-f]{64})", review.stdout)
            self.assertIsNotNone(lock, review.stdout); self.assertIsNotNone(generated, review.stdout)

            generation.write_text("B", encoding="utf-8")
            environment["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"] = lock.group(1)
            environment["NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_SUBJECT_SHA256"] = generated.group(1)
            field = subprocess.run(
                ["/bin/bash", str(root / "Scripts" / "bootstrap_capture_tuya_sdk.sh")],
                cwd=root, env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            )
            self.assertNotEqual(field.returncode, 0, field.stdout)
            self.assertIn("generated CocoaPods build bytes do not match", field.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)

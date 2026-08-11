#!/usr/bin/env python3
"""Portable generated-build authority checks for Capture."""
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

ROOT = Path(__file__).resolve().parents[3]
BOOTSTRAP = ROOT / "Scripts/bootstrap_capture_tuya_sdk.sh"
PROVENANCE = ROOT / "Scripts/capture_tuya_private_input_provenance.py"
PRIVATE_REVIEW = ROOT / "Scripts/capture_tuya_private_review_commitment.py"
SUBJECT = ROOT / "Scripts/capture_cocoapods_generated_build_subject.py"
GUARD = ROOT / "Scripts/capture_tuya_private_input_build_guard.py"
GENERATED = Path("Pods/Target Support Files/Pods-NembraCapture/Pods-NembraCapture.debug.xcconfig")


def load_guard():
    name = "nembra_generated_subject_guard_test"
    spec = importlib.util.spec_from_file_location(name, GUARD)
    if spec is None or spec.loader is None:
        raise RuntimeError("guard unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class GeneratedBuildSubjectTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="nembra-generated-subject-")
        self.root = Path(self.tmp.name)
        scripts = self.root / "Scripts"
        scripts.mkdir()
        for source in (BOOTSTRAP, PROVENANCE, PRIVATE_REVIEW, SUBJECT):
            shutil.copy2(source, scripts / source.name)
        (self.root / "Podfile").write_text("platform :ios, '17.0'\n", encoding="utf-8")
        (self.root / "NembraCapture.xcodeproj").mkdir()

        self.sdk = self.root / "LocalSecrets/TuyaSDK"
        (self.sdk / "Build").mkdir(parents=True)
        (self.sdk / "ThingSmartCryption.podspec").write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
        (self.sdk / "Build/library.a").write_bytes(b"review-fixture")
        self.identity = self.root / "LocalSecrets/TuyaRuntime"
        self.sources = self.identity / "Sources/NembraTuyaPrivateConfig"
        self.sources.mkdir(parents=True)
        (self.identity / "NembraTuyaPrivateConfig.podspec").write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
        (self.sources / "NembraTuyaPrivateIdentity.swift").write_text("enum Fixture { static let ready = true }\n", encoding="utf-8")

        self.bin = self.root / "bin"
        self.bin.mkdir()
        pod = self.bin / "pod"
        pod.write_text(
            "#!/bin/bash\nset -euo pipefail\n"
            "mkdir -p 'NembraCapture.xcworkspace' 'Pods/Target Support Files/Pods-NembraCapture'\n"
            "cat > Podfile.lock <<'EOF'\nPODS:\n  - ThingSmartHomeKit (7.8.0)\n  - ThingSmartBusinessExtensionKit (7.8.0)\nEOF\n"
            "printf '%s\\n' \"${NEMBRA_TEST_GRAPH:?}\" > 'Pods/Target Support Files/Pods-NembraCapture/Pods-NembraCapture.debug.xcconfig'\n"
            "printf '%s\\n' \"${NEMBRA_TEST_GRAPH:?}\" > NembraCapture.xcworkspace/contents.xcworkspacedata\n",
            encoding="utf-8",
        )
        pod.chmod(0o755)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def bootstrap(self, *, review: bool, lock: str = "", subject: str = "", private: str = ""):
        env = {"PATH": f"{self.bin}:/usr/bin:/bin", "HOME": str(self.root), "NEMBRA_TEST_GRAPH": "A"}
        if not review:
            env.update({
                "NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256": lock,
                "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256": subject,
                "NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_REVIEW_HMAC_SHA256": private,
            })
        command = ["/bin/bash", str(self.root / "Scripts/bootstrap_capture_tuya_sdk.sh")]
        if review:
            command.append("--resolve-lock-for-review")
        return subprocess.run(command, cwd=self.root, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)

    @staticmethod
    def tagged(output: str, label: str) -> str:
        match = re.search(rf"{re.escape(label)}: ([0-9a-f]{{64}})", output)
        if not match:
            raise AssertionError(output)
        return match.group(1)

    def graph_subject(self) -> str:
        result = subprocess.run([
            "/usr/bin/python3", "-I", str(self.root / "Scripts" / SUBJECT.name),
            "--lockfile", str(self.root / "Podfile.lock"),
            "--pods", str(self.root / "Pods"),
            "--workspace", str(self.root / "NembraCapture.xcworkspace"),
        ], cwd=self.root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
        self.assertEqual(result.returncode, 0, result.stdout)
        return result.stdout.strip()

    def reviewed(self):
        review = self.bootstrap(review=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        lock = hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest()
        graph = self.graph_subject()
        private = self.tagged(review.stdout, "Private-input review HMAC-SHA256")
        return review, lock, graph, private

    def test_exact_reviewed_lock_and_generated_subject_are_required(self) -> None:
        review, lock, graph, private = self.reviewed()
        self.assertIn(graph, review.stdout)
        missing = self.bootstrap(review=False, lock=lock, private=private)
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256", missing.stdout)
        accepted = self.bootstrap(review=False, lock=lock, subject=graph, private=private)
        self.assertEqual(accepted.returncode, 0, accepted.stdout)

    def test_same_accepted_lock_rejects_changed_generated_build_graph(self) -> None:
        _, lock, graph, private = self.reviewed()
        before = (self.root / GENERATED).read_bytes()
        (self.root / GENERATED).write_bytes(b"B\n")
        field = self.bootstrap(review=False, lock=lock, subject=graph, private=private)
        self.assertEqual(hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest(), lock)
        self.assertNotEqual((self.root / GENERATED).read_bytes(), before)
        self.assertNotEqual(field.returncode, 0, field.stdout)
        self.assertIn("generated build inputs do not match", field.stdout)

    def test_build_window_snapshot_and_watch_set_cover_generated_graph(self) -> None:
        _, _, graph, _ = self.reviewed()
        guard = load_guard()
        inputs = guard.PrivateInputs(
            lockfile=self.root / "Podfile.lock",
            security_podspec=self.sdk / "ThingSmartCryption.podspec",
            security_build=self.sdk / "Build",
            identity_podspec=self.identity / "NembraTuyaPrivateConfig.podspec",
            identity_sources=self.sources,
            generated_pods=self.root / "Pods",
            generated_workspace=self.root / "NembraCapture.xcworkspace",
        )
        watched = set(guard._watch_paths(inputs))
        self.assertIn(self.root / GENERATED, watched)
        self.assertIn(self.root / "NembraCapture.xcworkspace/contents.xcworkspacedata", watched)
        before = inputs.generation_snapshot()
        with mock.patch.dict(os.environ, {"NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256": graph}, clear=False):
            guard._verify_accepted_generated_build_subject(inputs)
            (self.root / GENERATED).write_bytes(b"C\n")
            self.assertNotEqual(before, inputs.generation_snapshot())
            with self.assertRaises(guard.BuildGuardError):
                guard._verify_accepted_generated_build_subject(inputs)

    def test_private_only_guard_keeps_original_cross_root_staging_contract(self) -> None:
        guard = load_guard()
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            a, b = Path(a), Path(b)
            lock = a / "Podfile.lock"; lock.write_text("lock\n")
            build = b / "build"; build.mkdir(); (build / "a").write_text("a")
            sources = b / "sources"; sources.mkdir(); (sources / "b").write_text("b")
            sp = b / "s.podspec"; sp.write_text("s")
            ip = b / "i.podspec"; ip.write_text("i")
            watched = set(guard._watch_paths(guard.PrivateInputs(lock, sp, build, ip, sources)))
            self.assertIn(lock, watched)
            self.assertNotIn(a, watched)
            self.assertNotIn(b, watched)

    def test_partial_generated_roots_fail_closed(self) -> None:
        guard = load_guard()
        inputs = guard.PrivateInputs(
            self.root / "Podfile.lock", self.sdk / "ThingSmartCryption.podspec", self.sdk / "Build",
            self.identity / "NembraTuyaPrivateConfig.podspec", self.sources, generated_pods=self.root / "Pods"
        )
        with self.assertRaises(guard.BuildGuardError):
            guard._watch_paths(inputs)

    def test_generated_watch_fd_budget_raises_soft_limit_or_fails_closed(self) -> None:
        guard = load_guard()
        with mock.patch.object(guard, "_current_descriptor_count", return_value=10), mock.patch.object(guard.resource, "getrlimit", side_effect=[(64, 1024), (174, 1024)]), mock.patch.object(guard.resource, "setrlimit") as setter:
            guard._ensure_fd_budget(100)
            setter.assert_called_once_with(guard.resource.RLIMIT_NOFILE, (174, 1024))
        with mock.patch.object(guard, "_current_descriptor_count", return_value=10), mock.patch.object(guard.resource, "getrlimit", return_value=(64, 173)):
            with self.assertRaises(guard.BuildGuardError):
                guard._ensure_fd_budget(100)


if __name__ == "__main__":
    unittest.main(verbosity=2)

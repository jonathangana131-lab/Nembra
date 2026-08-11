#!/usr/bin/env python3
"""Adversarial custody tests for the generated CocoaPods Capture build subject.

A reviewed Podfile.lock is necessary but not sufficient authority: a different
CocoaPods implementation can preserve that lock while emitting different ignored
workspace/Pods bytes that xcodebuild will consume. Review-only bootstrap must
therefore expose an exact generated-build digest, normal field bootstrap must
reject lock-preserving generated substitution, and the build guard must keep the
accepted generated graph under custody through xcodebuild.
"""

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
BOOTSTRAP = REPOSITORY / "Scripts" / "bootstrap_capture_tuya_sdk.sh"
PROVENANCE = REPOSITORY / "Scripts" / "capture_tuya_private_input_provenance.py"
PRIVATE_REVIEW = REPOSITORY / "Scripts" / "capture_private_review_commitment.py"
SUBJECT_HELPER = REPOSITORY / "Scripts" / "capture_cocoapods_generated_build_subject.py"
BUILD_GUARD = REPOSITORY / "Scripts" / "capture_tuya_private_input_build_guard.py"
GENERATED_RELATIVE = Path("Pods/Target Support Files/Pods-NembraCapture/Pods-NembraCapture.debug.xcconfig")


def load_build_guard():
    module_name = "nembra_capture_build_guard_test_subject"
    spec = importlib.util.spec_from_file_location(module_name, BUILD_GUARD)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load Capture build guard")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


class CocoaPodsGeneratedBuildSubjectTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-cocoapods-subject-")
        self.root = Path(self.temporary.name)
        scripts = self.root / "Scripts"
        scripts.mkdir()
        for source in (BOOTSTRAP, PROVENANCE, PRIVATE_REVIEW, SUBJECT_HELPER):
            shutil.copy2(source, scripts / source.name)
        self.accepted_private_review_helper = hashlib.sha256((scripts / PRIVATE_REVIEW.name).read_bytes()).hexdigest()
        self.accepted_provenance_helper = hashlib.sha256((scripts / PROVENANCE.name).read_bytes()).hexdigest()
        self.accepted_generated_helper = hashlib.sha256((scripts / SUBJECT_HELPER.name).read_bytes()).hexdigest()

        (self.root / "Podfile").write_text("platform :ios, '17.0'\n", encoding="utf-8")
        (self.root / "NembraCapture.xcodeproj").mkdir()

        self.private_sdk = self.root / "LocalSecrets/TuyaSDK"
        (self.private_sdk / "Build").mkdir(parents=True)
        (self.private_sdk / "ThingSmartCryption.podspec").write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
        (self.private_sdk / "Build/libThingSmartCryption.a").write_bytes(b"private-security-sdk")

        self.private_identity = self.root / "LocalSecrets/TuyaRuntime"
        self.identity_sources = self.private_identity / "Sources/NembraTuyaPrivateConfig"
        self.identity_sources.mkdir(parents=True)
        (self.private_identity / "NembraTuyaPrivateConfig.podspec").write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
        (self.identity_sources / "NembraTuyaPrivateIdentity.swift").write_text(
            "enum NembraTuyaPrivateIdentity { static let configured = true }\n",
            encoding="utf-8",
        )

        self.fake_bin = self.root / "fake-bin"
        self.fake_bin.mkdir()
        self.pod_counter = self.root / "pod-invocations.txt"
        pod = self.fake_bin / "pod"
        pod.write_text(
            "#!/bin/bash\n"
            "set -euo pipefail\n"
            f"printf 'pod\\n' >> {self.pod_counter!s}\n"
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
        accepted_private: str | None = None,
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
        if accepted_private is not None:
            environment["NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256"] = accepted_private
            environment["NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256"] = self.accepted_private_review_helper
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
    def review_digest(output: str, label: str) -> str:
        match = re.search(rf"{re.escape(label)}: ([0-9a-f]{{64}})", output)
        if match is None:
            raise AssertionError(f"missing {label} in review output:\n{output}")
        return match.group(1)

    def generated_subject(self) -> str:
        result = subprocess.run(
            [
                "/usr/bin/python3",
                "-I",
                str(self.root / "Scripts" / SUBJECT_HELPER.name),
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
        subject = result.stdout.strip()
        self.assertRegex(subject, r"^[0-9a-f]{64}$")
        return subject

    def test_exact_reviewed_lock_and_generated_subject_are_required(self) -> None:
        review = self.run_bootstrap("REVIEWED_GRAPH", review_only=True)
        self.assertEqual(review.returncode, 0, review.stdout)

        accepted_lock = hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest()
        accepted_subject = self.generated_subject()
        accepted_private = self.review_digest(review.stdout, "Private review commitment SHA-256")
        self.assertIn(f"Podfile.lock SHA-256: {accepted_lock}", review.stdout)
        self.assertIn(
            f"CocoaPods generated build subject SHA-256: {accepted_subject}",
            review.stdout,
        )
        self.assertEqual(self.pod_counter.read_text(encoding="utf-8").splitlines(), ["pod"])

        missing_subject = self.run_bootstrap(
            "REVIEWED_GRAPH",
            review_only=False,
            accepted_lock=accepted_lock,
        )
        self.assertNotEqual(missing_subject.returncode, 0, missing_subject.stdout)
        self.assertIn("NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256", missing_subject.stdout)

        accepted = self.run_bootstrap(
            "REVIEWED_GRAPH",
            review_only=False,
            accepted_lock=accepted_lock,
            accepted_subject=accepted_subject,
            accepted_private=accepted_private,
        )
        self.assertEqual(accepted.returncode, 0, accepted.stdout)
        self.assertIn("Preaccepted CocoaPods generated build subject matched", accepted.stdout)
        self.assertEqual(
            self.pod_counter.read_text(encoding="utf-8").splitlines(),
            ["pod"],
            "normal field bootstrap must not rerun CocoaPods after review",
        )

    def test_same_accepted_lock_rejects_changed_generated_build_graph(self) -> None:
        review = self.run_bootstrap("REVIEWED_GRAPH", review_only=True)
        self.assertEqual(review.returncode, 0, review.stdout)

        accepted_lock = hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest()
        accepted_subject = self.generated_subject()
        accepted_private = self.review_digest(review.stdout, "Private review commitment SHA-256")
        reviewed_generated = (self.root / GENERATED_RELATIVE).read_bytes()

        # Verification-only field bootstrap intentionally never gives CocoaPods a
        # chance to regenerate ignored inputs. Model the attacker substitution
        # directly while preserving the exact reviewed lock and private witness.
        (self.root / GENERATED_RELATIVE).write_text(
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) SUBSTITUTED_GRAPH\n",
            encoding="utf-8",
        )
        (self.root / "NembraCapture.xcworkspace/contents.xcworkspacedata").write_text(
            "SUBSTITUTED_GRAPH\n",
            encoding="utf-8",
        )

        field = self.run_bootstrap(
            "IGNORED_IN_NORMAL_MODE",
            review_only=False,
            accepted_lock=accepted_lock,
            accepted_subject=accepted_subject,
            accepted_private=accepted_private,
        )
        field_lock = hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest()
        substituted_generated = (self.root / GENERATED_RELATIVE).read_bytes()

        self.assertEqual(field_lock, accepted_lock)
        self.assertNotEqual(reviewed_generated, substituted_generated)
        self.assertNotEqual(field.returncode, 0, field.stdout)
        self.assertIn("generated build inputs do not match", field.stdout)
        self.assertEqual(
            self.pod_counter.read_text(encoding="utf-8").splitlines(),
            ["pod"],
            "generated substitution must be rejected without a second CocoaPods execution",
        )

    def test_build_window_snapshot_and_watch_set_cover_generated_graph(self) -> None:
        review = self.run_bootstrap("REVIEWED_GRAPH", review_only=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        accepted_subject = self.generated_subject()

        guard = load_build_guard()
        inputs = guard.PrivateInputs(
            lockfile=self.root / "Podfile.lock",
            security_podspec=self.private_sdk / "ThingSmartCryption.podspec",
            security_build=self.private_sdk / "Build",
            identity_podspec=self.private_identity / "NembraTuyaPrivateConfig.podspec",
            identity_sources=self.identity_sources,
            generated_pods=self.root / "Pods",
            generated_workspace=self.root / "NembraCapture.xcworkspace",
        )

        watched = set(guard._watch_paths(inputs))
        generated_file = self.root / GENERATED_RELATIVE
        workspace_file = self.root / "NembraCapture.xcworkspace/contents.xcworkspacedata"
        self.assertIn(self.root, watched)
        self.assertIn(self.root / "LocalSecrets", watched)
        self.assertIn(self.private_sdk, watched)
        self.assertIn(self.private_identity, watched)
        self.assertIn(inputs.private_provenance_record, watched)
        self.assertIn(inputs.private_review_key, watched)
        self.assertIn(generated_file, watched)
        self.assertIn(workspace_file, watched)

        before = inputs.generation_snapshot()
        with mock.patch.dict(
            os.environ,
            {"NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256": accepted_subject},
            clear=False,
        ):
            guard._verify_accepted_generated_build_subject(inputs)
            generated_file.write_text("SUBSTITUTED_DURING_BUILD\n", encoding="utf-8")
            after = inputs.generation_snapshot()
            self.assertNotEqual(before, after)
            with self.assertRaises(guard.BuildGuardError):
                guard._verify_accepted_generated_build_subject(inputs)

    def test_private_only_guard_keeps_original_cross_root_staging_contract(self) -> None:
        guard = load_build_guard()
        with tempfile.TemporaryDirectory(prefix="nembra-private-only-lock-") as lock_text, tempfile.TemporaryDirectory(
            prefix="nembra-private-only-inputs-"
        ) as private_text:
            lock_root = Path(lock_text)
            private_root = Path(private_text)
            lockfile = lock_root / "Podfile.lock"
            lockfile.write_text("private-only\n", encoding="utf-8")
            security_build = private_root / "security-build"
            identity_sources = private_root / "identity-sources"
            security_build.mkdir()
            identity_sources.mkdir()
            security_podspec = private_root / "security.podspec"
            identity_podspec = private_root / "identity.podspec"
            security_podspec.write_text("security\n", encoding="utf-8")
            identity_podspec.write_text("identity\n", encoding="utf-8")
            (security_build / "lib.a").write_bytes(b"private")
            (identity_sources / "identity.swift").write_text("private\n", encoding="utf-8")

            inputs = guard.PrivateInputs(
                lockfile=lockfile,
                security_podspec=security_podspec,
                security_build=security_build,
                identity_podspec=identity_podspec,
                identity_sources=identity_sources,
            )
            watched = set(guard._watch_paths(inputs))
            self.assertIn(lockfile, watched)
            self.assertIn(security_build / "lib.a", watched)
            self.assertIn(identity_sources / "identity.swift", watched)
            self.assertNotIn(lock_root, watched)
            self.assertNotIn(private_root, watched)

    def test_partial_generated_roots_fail_closed(self) -> None:
        guard = load_build_guard()
        inputs = guard.PrivateInputs(
            lockfile=self.root / "Podfile.lock",
            security_podspec=self.private_sdk / "ThingSmartCryption.podspec",
            security_build=self.private_sdk / "Build",
            identity_podspec=self.private_identity / "NembraTuyaPrivateConfig.podspec",
            identity_sources=self.identity_sources,
            generated_pods=self.root / "Pods",
        )
        with self.assertRaises(guard.BuildGuardError):
            guard._watch_paths(inputs)

    def test_generated_watch_fd_budget_raises_soft_limit_or_fails_closed(self) -> None:
        guard = load_build_guard()
        with (
            mock.patch.object(guard, "_current_descriptor_count", return_value=10),
            mock.patch.object(
                guard.resource,
                "getrlimit",
                side_effect=[(64, 1024), (174, 1024)],
            ),
            mock.patch.object(guard.resource, "setrlimit") as setrlimit,
        ):
            guard._ensure_fd_budget(100)
            setrlimit.assert_called_once_with(guard.resource.RLIMIT_NOFILE, (174, 1024))

        with (
            mock.patch.object(guard, "_current_descriptor_count", return_value=10),
            mock.patch.object(guard.resource, "getrlimit", return_value=(64, 173)),
        ):
            with self.assertRaises(guard.BuildGuardError):
                guard._ensure_fd_budget(100)


if __name__ == "__main__":
    unittest.main(verbosity=2)

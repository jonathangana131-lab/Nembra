#!/usr/bin/env python3
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

ROOT = Path(__file__).resolve().parents[3]
HELPER = ROOT / "Scripts/capture_cocoapods_generated_build_subject.py"
BOOTSTRAP = ROOT / "Scripts/bootstrap_capture_tuya_sdk.sh"
PROVENANCE = ROOT / "Scripts/capture_tuya_private_input_provenance.py"
BUILD_GUARD = ROOT / "Scripts/capture_tuya_private_input_build_guard.py"
SUBJECT_RE = re.compile(r"CocoaPods build subject SHA-256: ([0-9a-f]{64})")


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {name}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def load_helper():
    return load_module("cocoapods_subject", HELPER)


def load_build_guard():
    return load_module("capture_tuya_private_input_build_guard_test", BUILD_GUARD)


def make_subject(root: Path) -> tuple[Path, Path, Path, Path]:
    pods = root / "Pods"
    support = pods / "Target Support Files/Pods-NembraCapture"
    workspace = root / "NembraCapture.xcworkspace"
    support.mkdir(parents=True)
    workspace.mkdir()
    config = support / "Pods-NembraCapture.debug.xcconfig"
    data = workspace / "contents.xcworkspacedata"
    config.write_text("GRAPH=A\n", encoding="utf-8")
    data.write_text("A\n", encoding="utf-8")
    return pods, workspace, config, data


class CocoaPodsGeneratedBuildSubjectTests(unittest.TestCase):
    def test_generated_build_bytes_change_subject_digest(self) -> None:
        module = load_helper()
        with tempfile.TemporaryDirectory(prefix="nembra-cocoapods-subject-") as temporary:
            root = Path(temporary)
            pods, workspace, config, data = make_subject(root)
            reviewed = module.fingerprint_subject(pods, workspace)
            config.write_text("GRAPH=B\n", encoding="utf-8")
            data.write_text("B\n", encoding="utf-8")
            substituted = module.fingerprint_subject(pods, workspace)
            self.assertRegex(reviewed, r"^[0-9a-f]{64}$")
            self.assertRegex(substituted, r"^[0-9a-f]{64}$")
            self.assertNotEqual(reviewed, substituted)

    def test_external_symlink_requires_explicit_separately_guarded_root(self) -> None:
        module = load_helper()
        with tempfile.TemporaryDirectory(prefix="nembra-cocoapods-symlink-") as temporary:
            root = Path(temporary)
            pods, workspace, _, _ = make_subject(root)
            private_root = root / "LocalSecrets/TuyaSDK"
            private_root.mkdir(parents=True)
            (private_root / "private.a").write_bytes(b"private")
            (pods / "DevelopmentPod").symlink_to(private_root, target_is_directory=True)

            with self.assertRaises(module.SubjectError):
                module.fingerprint_subject(pods, workspace)

            admitted = module.fingerprint_subject(
                pods,
                workspace,
                separately_guarded_external_roots=(private_root,),
            )
            self.assertRegex(admitted, r"^[0-9a-f]{64}$")

    def test_preaccepted_digest_mismatch_blocks_before_backend_or_child_spawn(self) -> None:
        module = load_build_guard()

        class FakeInputs:
            def generation_snapshot(self):
                return ("private-snapshot", "a" * 64)

        def forbidden_backend():
            self.fail("backend must not be constructed after digest mismatch")

        def forbidden_spawn(*_args, **_kwargs):
            self.fail("child process must not spawn after digest mismatch")

        with self.assertRaises(module.BuildGuardError) as error:
            module.run_guarded_build(
                FakeInputs(),
                ["xcodebuild"],
                expected_generated_subject_sha256="b" * 64,
                backend_factory=forbidden_backend,
                popen_factory=forbidden_spawn,
            )
        self.assertIn("no longer matches the preaccepted SHA-256", str(error.exception))

    def test_real_bootstrap_rejects_same_lock_different_generated_graph(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-cocoapods-bootstrap-") as temporary:
            root = Path(temporary)
            scripts = root / "Scripts"
            scripts.mkdir()
            for source in (BOOTSTRAP, PROVENANCE, HELPER):
                shutil.copy2(source, scripts / source.name)

            (root / "Podfile").write_text("platform :ios, '17.0'\n", encoding="utf-8")
            (root / "NembraCapture.xcodeproj").mkdir()

            sdk = root / "LocalSecrets/TuyaSDK"
            (sdk / "Build").mkdir(parents=True)
            (sdk / "ThingSmartCryption.podspec").write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
            (sdk / "Build/security.bin").write_bytes(b"security")

            identity = root / "LocalSecrets/TuyaRuntime"
            identity_sources = identity / "Sources/NembraTuyaPrivateConfig"
            identity_sources.mkdir(parents=True)
            (identity / "NembraTuyaPrivateConfig.podspec").write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
            (identity_sources / "NembraTuyaPrivateIdentity.swift").write_text(
                "enum NembraTuyaPrivateIdentity { static let configured = true }\n",
                encoding="utf-8",
            )

            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            fake_pod = fake_bin / "pod"
            fake_pod.write_text(
                "#!/usr/bin/python3\n"
                "import os\n"
                "from pathlib import Path\n"
                "payload = os.environ['NEMBRA_TEST_GENERATED_PAYLOAD']\n"
                "support = Path('Pods/Target Support Files/Pods-NembraCapture')\n"
                "workspace = Path('NembraCapture.xcworkspace')\n"
                "support.mkdir(parents=True, exist_ok=True)\n"
                "workspace.mkdir(parents=True, exist_ok=True)\n"
                "Path('Podfile.lock').write_text('PODS:\\n  - ThingSmartHomeKit (7.8.0)\\n  - ThingSmartBusinessExtensionKit (7.8.0)\\n', encoding='utf-8')\n"
                "(support / 'Pods-NembraCapture.debug.xcconfig').write_text('GRAPH=' + payload + '\\n', encoding='utf-8')\n"
                "(workspace / 'contents.xcworkspacedata').write_text(payload + '\\n', encoding='utf-8')\n",
                encoding="utf-8",
            )
            fake_pod.chmod(0o755)

            fake_stat = fake_bin / "stat"
            fake_stat.write_text(
                "#!/usr/bin/python3\n"
                "import os, sys\n"
                "if sys.argv[1:3] == ['-f', '%Lp']:\n"
                "    print('600')\n"
                "    raise SystemExit(0)\n"
                "os.execv('/usr/bin/stat', ['/usr/bin/stat', *sys.argv[1:]])\n",
                encoding="utf-8",
            )
            fake_stat.chmod(0o755)

            base_environment = {
                "PATH": f"{fake_bin}:/usr/bin:/bin",
                "HOME": str(root),
                "LANG": "C.UTF-8",
                "LC_ALL": "C.UTF-8",
            }

            review_environment = dict(base_environment)
            review_environment["NEMBRA_TEST_GENERATED_PAYLOAD"] = "REVIEWED_GRAPH"
            review = subprocess.run(
                ["/bin/bash", str(scripts / BOOTSTRAP.name), "--resolve-lock-for-review"],
                cwd=root,
                env=review_environment,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
            self.assertEqual(review.returncode, 0, review.stdout)
            accepted_lock = hashlib.sha256((root / "Podfile.lock").read_bytes()).hexdigest()
            match = SUBJECT_RE.search(review.stdout)
            self.assertIsNotNone(match, review.stdout)
            assert match is not None
            accepted_subject = match.group(1)

            changed_environment = dict(base_environment)
            changed_environment.update(
                {
                    "NEMBRA_TEST_GENERATED_PAYLOAD": "SUBSTITUTED_GRAPH",
                    "NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256": accepted_lock,
                    "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256": accepted_subject,
                }
            )
            changed = subprocess.run(
                ["/bin/bash", str(scripts / BOOTSTRAP.name)],
                cwd=root,
                env=changed_environment,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
            self.assertEqual(
                hashlib.sha256((root / "Podfile.lock").read_bytes()).hexdigest(),
                accepted_lock,
                "attack fixture must preserve the exact reviewed lock",
            )
            self.assertEqual(changed.returncode, 18, changed.stdout)
            self.assertIn("same Podfile.lock produced different build-affecting generated bytes", changed.stdout)

            accepted_environment = dict(base_environment)
            accepted_environment.update(
                {
                    "NEMBRA_TEST_GENERATED_PAYLOAD": "REVIEWED_GRAPH",
                    "NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256": accepted_lock,
                    "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256": accepted_subject,
                }
            )
            accepted = subprocess.run(
                ["/bin/bash", str(scripts / BOOTSTRAP.name)],
                cwd=root,
                env=accepted_environment,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
            self.assertEqual(accepted.returncode, 0, accepted.stdout)
            self.assertIn(f"Preaccepted CocoaPods build subject matched: {accepted_subject}", accepted.stdout)

    def test_bootstrap_binds_reviewed_generated_subject_before_field_build(self) -> None:
        source = BOOTSTRAP.read_text(encoding="utf-8")
        fingerprint = source.index("COCOAPODS_BUILD_SUBJECT_SHA256=\"")
        missing_authority = source.index("generated CocoaPods build subject has no preaccepted SHA-256 authority")
        mismatch = source.index("same Podfile.lock produced different build-affecting generated bytes")
        self.assertLess(fingerprint, missing_authority)
        self.assertLess(missing_authority, mismatch)
        self.assertIn("NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256", source)
        self.assertIn("--resolve-lock-for-review", source)
        self.assertIn("CocoaPods build subject SHA-256", source)
        self.assertEqual(source.count("--separately-guarded-external-root"), 2)
        self.assertIn('"$TUYA_PRIVATE_SDK"', source)
        self.assertIn('"$TUYA_PRIVATE_IDENTITY"', source)

    def test_existing_xcodebuild_guard_owns_exact_preaccepted_generated_subject(self) -> None:
        source = BUILD_GUARD.read_text(encoding="utf-8")
        loader = source.index("capture_cocoapods_generated_build_subject.py")
        generated_snapshot = source.index("generated_build_subject.fingerprint_subject")
        expected_environment = source.index(
            'os.environ.get("NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256")'
        )
        prebuild_match = source.index(
            "generated CocoaPods build subject no longer matches the preaccepted SHA-256 before xcodebuild"
        )
        watcher = source.index("inputs.generated_pods")
        xcodebuild = source.index("process = popen_factory(list(command))")
        final_snapshot = source.rindex("final_snapshot = inputs.generation_snapshot()")
        self.assertLess(loader, generated_snapshot)
        self.assertLess(generated_snapshot, watcher)
        self.assertLess(prebuild_match, xcodebuild)
        self.assertLess(xcodebuild, final_snapshot)
        self.assertLess(final_snapshot, expected_environment)
        self.assertIn("inputs.generated_workspace", source)
        self.assertIn("separately_guarded_external_roots", source)
        self.assertIn("self.security_podspec.parent", source)
        self.assertIn("self.identity_podspec.parent", source)
        self.assertIn("field build inputs changed across the guarded xcodebuild window", source)
        self.assertIn("generated CocoaPods build subject lost preaccepted authority across xcodebuild", source)

    def test_helper_has_no_second_build_window_authority(self) -> None:
        source = HELPER.read_text(encoding="utf-8")
        self.assertNotIn("subprocess.Popen", source)
        self.assertNotIn("select.kqueue", source)
        self.assertIn("separately_guarded_external_roots", source)
        self.assertIn("generated build symlink escapes", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)

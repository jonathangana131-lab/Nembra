#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]
FILES = (
    REPO / "Scripts/bootstrap_capture_tuya_sdk.sh",
    REPO / "Scripts/capture_tuya_private_input_provenance.py",
    REPO / "Scripts/capture_cocoapods_build_subject.py",
)
GUARD = REPO / "Scripts/capture_tuya_private_input_build_guard.py"
GENERATED = Path("Pods/Target Support Files/Pods-NembraCapture/Pods-NembraCapture.debug.xcconfig")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class GeneratedBuildSubjectClosureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="nembra-generated-subject-")
        self.root = Path(self.tmp.name)
        scripts = self.root / "Scripts"
        scripts.mkdir()
        for source in FILES:
            shutil.copy2(source, scripts / source.name)
        (self.root / "Podfile").write_text("platform :ios, '17.0'\n", encoding="utf-8")
        (self.root / "NembraCapture.xcodeproj").mkdir()

        sdk = self.root / "LocalSecrets/TuyaSDK"
        (sdk / "Build").mkdir(parents=True)
        (sdk / "ThingSmartCryption.podspec").write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
        (sdk / "Build/lib.a").write_bytes(b"sdk")
        runtime = self.root / "LocalSecrets/TuyaRuntime"
        sources = runtime / "Sources/NembraTuyaPrivateConfig"
        sources.mkdir(parents=True)
        (runtime / "NembraTuyaPrivateConfig.podspec").write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
        (sources / "NembraTuyaPrivateIdentity.swift").write_text("enum Identity {}\n", encoding="utf-8")

        self.bin = self.root / "fake-bin"
        self.bin.mkdir()
        pod = self.bin / "pod"
        pod.write_text(
            "#!/bin/bash\nset -euo pipefail\n"
            "mkdir -p 'NembraCapture.xcworkspace' 'Pods/Target Support Files/Pods-NembraCapture'\n"
            "cat > Podfile.lock <<'EOF'\n"
            "PODS:\n  - ThingSmartHomeKit (7.8.0)\n  - ThingSmartBusinessExtensionKit (7.8.0)\n"
            "DEPENDENCIES:\n  - ThingSmartHomeKit (= 7.8.0)\n  - ThingSmartBusinessExtensionKit (= 7.8.0)\nEOF\n"
            "cp Podfile.lock Pods/Manifest.lock\n"
            "printf '%s\\n' \"${NEMBRA_TEST_GRAPH:?}\" > 'Pods/Target Support Files/Pods-NembraCapture/Pods-NembraCapture.debug.xcconfig'\n"
            "printf '%s\\n' \"${NEMBRA_TEST_GRAPH:?}\" > NembraCapture.xcworkspace/contents.xcworkspacedata\n",
            encoding="utf-8",
        )
        pod.chmod(0o755)
        stat = self.bin / "stat"
        stat.write_text(
            "#!/bin/bash\nset -euo pipefail\n"
            "if [[ ${1:-} == '-f' && ${2:-} == '%Lp' ]]; then printf '600\\n'; exit 0; fi\n"
            "exec /usr/bin/stat \"$@\"\n",
            encoding="utf-8",
        )
        stat.chmod(0o755)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def bootstrap(self, graph: str, *, review: bool, accepted: str = "") -> subprocess.CompletedProcess[str]:
        env = {
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "HOME": str(self.root),
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            "NEMBRA_TEST_GRAPH": graph,
        }
        if accepted:
            env["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"] = accepted
        command = ["/bin/bash", str(self.root / "Scripts/bootstrap_capture_tuya_sdk.sh")]
        if review:
            command.append("--resolve-lock-for-review")
        return subprocess.run(command, cwd=self.root, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)

    def helper(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["/usr/bin/python3", "-I", str(self.root / "Scripts/capture_cocoapods_build_subject.py"), *args],
            cwd=self.root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )

    def fingerprint(self) -> subprocess.CompletedProcess[str]:
        return self.helper(
            "fingerprint",
            "--pods", str(self.root / "Pods"),
            "--workspace", str(self.root / "NembraCapture.xcworkspace"),
        )

    def test_same_graph_reproduces_reviewed_attested_lock_and_manifest(self) -> None:
        review = self.bootstrap("GRAPH_A", review=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        lock = self.root / "Podfile.lock"
        manifest = self.root / "Pods/Manifest.lock"
        accepted = digest(lock)
        self.assertEqual(lock.read_bytes(), manifest.read_bytes())
        expected = self.helper("read-attestation", "--lockfile", str(lock))
        self.assertEqual(expected.returncode, 0, expected.stdout)
        self.assertRegex(expected.stdout.strip(), r"^[0-9a-f]{64}$")

        field = self.bootstrap("GRAPH_A", review=False, accepted=accepted)
        self.assertEqual(field.returncode, 0, field.stdout)
        self.assertEqual(digest(lock), accepted)
        self.assertEqual(lock.read_bytes(), manifest.read_bytes())

    def test_changed_graph_fails_with_same_reviewed_lock(self) -> None:
        review = self.bootstrap("GRAPH_A", review=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        lock = self.root / "Podfile.lock"
        manifest = self.root / "Pods/Manifest.lock"
        accepted = digest(lock)
        before = (self.root / GENERATED).read_bytes()
        field = self.bootstrap("GRAPH_B", review=False, accepted=accepted)
        self.assertNotEqual(field.returncode, 0, field.stdout)
        self.assertEqual(digest(lock), accepted)
        self.assertEqual(lock.read_bytes(), manifest.read_bytes())
        self.assertNotEqual(before, (self.root / GENERATED).read_bytes())
        self.assertIn("generated different build-affecting bytes", field.stdout)

    def test_attestation_rewrite_is_deterministic_and_single(self) -> None:
        review = self.bootstrap("GRAPH_A", review=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        lock = self.root / "Podfile.lock"
        before = lock.read_bytes()
        value = self.helper("read-attestation", "--lockfile", str(lock)).stdout.strip()
        rewrite = self.helper("attest-lock", "--lockfile", str(lock), "--digest", value)
        self.assertEqual(rewrite.returncode, 0, rewrite.stdout)
        self.assertEqual(lock.read_bytes(), before)
        self.assertEqual(lock.read_bytes().count(b"# NEMBRA_CAPTURE_GENERATED_BUILD_SUBJECT_SHA256="), 1)

    def test_manifest_bytes_are_not_recursive_graph_input(self) -> None:
        review = self.bootstrap("GRAPH_A", review=True)
        self.assertEqual(review.returncode, 0, review.stdout)
        before = self.fingerprint()
        self.assertEqual(before.returncode, 0, before.stdout)
        manifest = self.root / "Pods/Manifest.lock"
        manifest.write_bytes(manifest.read_bytes() + b"# mirror-only-change\n")
        after = self.fingerprint()
        self.assertEqual(after.returncode, 0, after.stdout)
        self.assertEqual(before.stdout.strip(), after.stdout.strip())

    def test_existing_build_guard_includes_generated_subject_and_manifest_mirror(self) -> None:
        source = GUARD.read_text(encoding="utf-8")
        for marker in (
            '"capture_cocoapods_build_subject.py"',
            "def generated_pods",
            "def generated_workspace",
            "def generated_manifest",
            "build_subject.stable_file_sha256(self.generated_manifest)",
            "build_subject.read_attestation(self.lockfile)",
            "build_subject.build_subject_fingerprint",
            "inputs.generated_pods",
            "inputs.generated_workspace",
        ):
            self.assertIn(marker, source)


if __name__ == "__main__":
    unittest.main(verbosity=2)

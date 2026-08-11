#!/usr/bin/env python3
"""Expected-red attacks for downstream helpers that still participate in field authority."""
from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
BOOTSTRAP = REPOSITORY / "Scripts/bootstrap_capture_tuya_sdk.sh"
PROVENANCE = REPOSITORY / "Scripts/capture_tuya_private_input_provenance.py"
COMMITMENT = REPOSITORY / "Scripts/capture_private_review_commitment.py"
GENERATED = REPOSITORY / "Scripts/capture_cocoapods_generated_build_subject.py"
GUARD = REPOSITORY / "Scripts/capture_tuya_private_input_build_guard.py"

LOCK_ENV = "NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"
GENERATED_ENV = "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256"
PRIVATE_ENV = "NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256"
PRIVATE_HELPER_ENV = "NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256"
PROVENANCE_HELPER_ENV = "NEMBRA_CAPTURE_ACCEPTED_PROVENANCE_HELPER_SHA256"
GENERATED_HELPER_ENV = "NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_SUBJECT_HELPER_SHA256"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path.name}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class DownstreamBootstrapHelperExecutionCustodyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="nembra-downstream-bootstrap-helper-")
        self.root = Path(self.temporary.name)
        scripts = self.root / "Scripts"
        scripts.mkdir()
        for source in (BOOTSTRAP, PROVENANCE, COMMITMENT, GENERATED):
            shutil.copy2(source, scripts / source.name)
        self.bootstrap = scripts / BOOTSTRAP.name
        self.provenance = scripts / PROVENANCE.name
        self.commitment = scripts / COMMITMENT.name
        self.generated = scripts / GENERATED.name

        (self.root / "Podfile").write_text("platform :ios, '17.0'\n", encoding="utf-8")
        (self.root / "NembraCapture.xcodeproj").mkdir()
        (self.root / "NembraCapture.xcworkspace").mkdir()
        (self.root / "NembraCapture.xcworkspace/contents.xcworkspacedata").write_text(
            '<Workspace version="1.0"/>\n', encoding="utf-8"
        )
        (self.root / "Pods/TargetSupport").mkdir(parents=True)
        self.generated_file = self.root / "Pods/TargetSupport/NembraCapture.debug.xcconfig"
        self.generated_file.write_text("OTHER_LDFLAGS = -ObjC\n", encoding="utf-8")
        (self.root / "Podfile.lock").write_text(
            "PODS:\n"
            "  - ThingSmartHomeKit (7.8.0)\n"
            "  - ThingSmartBusinessExtensionKit (7.8.0)\n"
            "DEPENDENCIES:\n"
            "  - ThingSmartHomeKit (= 7.8.0)\n"
            "  - ThingSmartBusinessExtensionKit (= 7.8.0)\n",
            encoding="utf-8",
        )

        self.security_root = self.root / "LocalSecrets/TuyaSDK"
        self.security_build = self.security_root / "Build"
        self.security_build.mkdir(parents=True)
        self.security_podspec = self.security_root / "ThingSmartCryption.podspec"
        self.security_podspec.write_text("Pod::Spec.new do |s|\n  s.name = 'ThingSmartCryption'\nend\n", encoding="utf-8")
        self.security_binary = self.security_build / "libThingSmartCryption.a"
        self.security_binary.write_bytes(b"REVIEWED-PRIVATE-SECURITY-A")

        self.identity_root = self.root / "LocalSecrets/TuyaRuntime"
        self.identity_sources = self.identity_root / "Sources/NembraTuyaPrivateConfig"
        self.identity_sources.mkdir(parents=True)
        self.identity_podspec = self.identity_root / "NembraTuyaPrivateConfig.podspec"
        self.identity_podspec.write_text("Pod::Spec.new do |s|\n  s.name = 'NembraTuyaPrivateConfig'\nend\n", encoding="utf-8")
        self.identity_source = self.identity_sources / "NembraTuyaPrivateIdentity.swift"
        self.identity_source.write_text(
            'enum NembraTuyaPrivateIdentity { static let appSecret = "SYNTHETIC-SECRET-A" }\n',
            encoding="utf-8",
        )

        self.record = self.identity_root / "ResolvedTuyaDependencyProvenance.txt"
        self.key = self.identity_root / "PrivateReviewCommitment.key"

        self.fake_bin = self.root / "fake-bin"
        self.fake_bin.mkdir()
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

    def _python(self, *arguments: object) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["/usr/bin/python3", "-I", *(str(argument) for argument in arguments)],
            cwd=self.root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )

    def reviewed_subjects(self) -> tuple[str, str, str, str, str, str]:
        snapshot = self._python(
            self.provenance,
            "snapshot",
            "--lockfile", self.root / "Podfile.lock",
            "--security-podspec", self.security_podspec,
            "--security-build", self.security_build,
            "--identity-podspec", self.identity_podspec,
            "--identity-sources", self.identity_sources,
            "--record", self.record,
        )
        self.assertEqual(snapshot.returncode, 0, snapshot.stdout)
        os.chmod(self.record, 0o600)

        commitment = self._python(self.commitment, "create", "--witness", self.record, "--key", self.key)
        self.assertEqual(commitment.returncode, 0, commitment.stdout)
        private = commitment.stdout.strip()
        self.assertRegex(private, r"^[0-9a-f]{64}$")

        generated = self._python(
            self.generated,
            "--lockfile", self.root / "Podfile.lock",
            "--pods", self.root / "Pods",
            "--workspace", self.root / "NembraCapture.xcworkspace",
        )
        self.assertEqual(generated.returncode, 0, generated.stdout)
        generated_digest = generated.stdout.strip()
        self.assertRegex(generated_digest, r"^[0-9a-f]{64}$")

        lock = hashlib.sha256((self.root / "Podfile.lock").read_bytes()).hexdigest()
        private_helper = hashlib.sha256(self.commitment.read_bytes()).hexdigest()
        provenance_helper = hashlib.sha256(self.provenance.read_bytes()).hexdigest()
        generated_helper = hashlib.sha256(self.generated.read_bytes()).hexdigest()
        return lock, generated_digest, private, private_helper, provenance_helper, generated_helper

    def run_field(self, subjects: tuple[str, str, str, str]) -> subprocess.CompletedProcess[str]:
        lock, generated, private, private_helper, provenance_helper, generated_helper = subjects
        env = {
            "PATH": f"{self.fake_bin}:/usr/bin:/bin",
            "HOME": str(self.root),
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            LOCK_ENV: lock,
            GENERATED_ENV: generated,
            PRIVATE_ENV: private,
            PRIVATE_HELPER_ENV: private_helper,
            PROVENANCE_HELPER_ENV: provenance_helper,
            GENERATED_HELPER_ENV: generated_helper,
        }
        return subprocess.run(
            ["/bin/bash", str(self.bootstrap)],
            cwd=self.root,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )

    def test_bootstrap_rejects_substituted_provenance_verifier(self) -> None:
        subjects = self.reviewed_subjects()
        self.security_binary.write_bytes(b"SUBSTITUTED-PRIVATE-SECURITY-B")
        self.identity_source.write_text(
            'enum NembraTuyaPrivateIdentity { static let appSecret = "SYNTHETIC-SECRET-B" }\n',
            encoding="utf-8",
        )
        self.provenance.write_text(
            "#!/usr/bin/env python3\n"
            "import sys\n"
            "if len(sys.argv) < 2 or sys.argv[1] != 'verify': raise SystemExit(91)\n"
            "raise SystemExit(0)\n",
            encoding="utf-8",
        )
        field = self.run_field(subjects)
        self.assertNotEqual(
            field.returncode,
            0,
            "mutable provenance verifier let changed private SDK/identity bytes pass an accepted A witness/HMAC",
        )

    def test_bootstrap_rejects_substituted_generated_subject_helper(self) -> None:
        subjects = self.reviewed_subjects()
        accepted_generated = subjects[1]
        self.generated_file.write_text("OTHER_LDFLAGS = -force_load attacker\n", encoding="utf-8")
        self.generated.write_text(
            "#!/usr/bin/env python3\n"
            f"print({accepted_generated!r})\n",
            encoding="utf-8",
        )
        field = self.run_field(subjects)
        self.assertNotEqual(
            field.returncode,
            0,
            "mutable generated-subject helper let changed Pods/workspace bytes claim the accepted digest",
        )


class DownstreamBuildGuardHelperExecutionCustodyTests(unittest.TestCase):
    def _load_guard_with_replacement(self, *, replace: Path) -> Path:
        temporary = tempfile.TemporaryDirectory(prefix="nembra-downstream-guard-helper-")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        scripts = root / "Scripts"
        scripts.mkdir()
        sentinel = root / "executed.txt"
        for source in (GUARD, PROVENANCE, GENERATED, COMMITMENT):
            shutil.copy2(source, scripts / source.name)
        (scripts / replace.name).write_text(
            "from pathlib import Path\n"
            f"Path({str(sentinel)!r}).write_text('executed', encoding='utf-8')\n",
            encoding="utf-8",
        )
        load_module(scripts / GUARD.name, f"nembra_guard_downstream_{replace.stem}")
        return sentinel

    def test_build_guard_does_not_execute_mutable_provenance_neighbor(self) -> None:
        sentinel = self._load_guard_with_replacement(replace=PROVENANCE)
        self.assertFalse(
            sentinel.exists(),
            "build guard executed mutable provenance neighbor before accepted execution authority existed",
        )

    def test_build_guard_does_not_execute_mutable_generated_subject_neighbor(self) -> None:
        sentinel = self._load_guard_with_replacement(replace=GENERATED)
        self.assertFalse(
            sentinel.exists(),
            "build guard executed mutable generated-subject neighbor before accepted execution authority existed",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

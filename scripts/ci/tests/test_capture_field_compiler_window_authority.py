#!/usr/bin/env python3
"""V14 permanent regressions for physical field compiler-window authority."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
GUARD = ROOT / "Scripts/capture_tuya_private_input_build_guard.py"
FIELD_GATE = ROOT / ".github/workflows/capture-field-build-provenance.yml"

SPEC = importlib.util.spec_from_file_location("capture_field_build_guard_under_test", GUARD)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load Capture field build guard")
build_guard = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = build_guard
SPEC.loader.exec_module(build_guard)


class CaptureFieldCompilerWindowAuthorityTests(unittest.TestCase):
    def _repository_fixture(self, root: Path) -> tuple[object, Path, str]:
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.email", "nembra@example.invalid"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.name", "Nembra Red Team"], cwd=root, check=True)
        tracked = root / "Tracked.swift"
        tracked.write_text("let accepted = 1\n", encoding="utf-8")
        lockfile = root / "Podfile.lock"
        lockfile.write_text("accepted lock\n", encoding="utf-8")
        subprocess.run(["git", "add", "Tracked.swift", "Podfile.lock"], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", "accepted source"], cwd=root, check=True)
        source_sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
        inputs = build_guard.PrivateInputs(
            lockfile=lockfile,
            security_podspec=root / "unused-security.podspec",
            security_build=root / "unused-security-build",
            identity_podspec=root / "unused-identity.podspec",
            identity_sources=root / "unused-identity-sources",
            accepted_source_root=root,
            accepted_source_sha=source_sha,
        )
        return inputs, tracked, source_sha

    def test_exact_git_manifest_and_descriptor_hash_reject_mutated_tracked_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            inputs, tracked, _ = self._repository_fixture(root)
            manifest = build_guard._accepted_source_manifest(inputs)
            descriptors: list[tuple[int, Path]] = []
            try:
                for path in manifest:
                    descriptors.append((os.open(path, os.O_RDONLY), path))
                build_guard._verify_accepted_tracked_source_descriptors(manifest, descriptors)
                tracked.write_text("let attacker = 1\n", encoding="utf-8")
                with self.assertRaises(build_guard.BuildGuardError):
                    build_guard._verify_accepted_tracked_source_descriptors(manifest, descriptors)
            finally:
                for descriptor, _ in descriptors:
                    os.close(descriptor)

    def test_manifest_refuses_a_sha_that_is_not_current_checkout_head(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            inputs, tracked, accepted_sha = self._repository_fixture(root)
            tracked.write_text("let later = 2\n", encoding="utf-8")
            subprocess.run(["git", "add", "Tracked.swift"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "later source"], cwd=root, check=True)
            self.assertNotEqual(
                subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
                accepted_sha,
            )
            with self.assertRaises(build_guard.BuildGuardError):
                build_guard._accepted_source_manifest(inputs)

    def test_private_runner_executes_exact_git_object_bytes_not_worktree_path(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        self.assertNotIn(
            'PRIVATE_DEVICE_RUNNER="$ROOT/scripts/ci/es80_signed_field_artifact_private_runner.py"',
            source,
        )
        self.assertNotIn('spec_from_file_location("nembra_private_device_reader", runner_path)', source)
        for marker in (
            'PRIVATE_DEVICE_RUNNER_RELATIVE="scripts/ci/es80_signed_field_artifact_private_runner.py"',
            'PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB="$(run_authority_git rev-parse "$SOURCE_SHA:$PRIVATE_DEVICE_RUNNER_RELATIVE"',
            'run_authority_git cat-file blob "$PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB"',
            'run_authority_git hash-object --stdin',
            'runner_source = base64.b64decode(sys.argv[1], validate=True)',
            'compile(runner_source, "<accepted-private-device-runner>", "exec", dont_inherit=True)',
        ):
            self.assertIn(marker, source)

    def test_xcodebuild_is_inside_exact_tracked_source_custody(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        guard = GUARD.read_text(encoding="utf-8")
        start = installer.index('say "Building SDK-integrated Nembra Capture for the intended iPhone"')
        end = installer.index("verify_private_tuya_inputs\nverify_accepted_checkout_source", start)
        build_window = installer[start:end]
        for marker in (
            '--accepted-source-root "$ROOT"',
            '--accepted-source-sha "$SOURCE_SHA"',
            '-- /usr/bin/xcodebuild',
        ):
            self.assertIn(marker, build_window)
        for marker in (
            "accepted_source_root: Path | None = None",
            "accepted_source_sha: str | None = None",
            "def _accepted_source_manifest(inputs: PrivateInputs)",
            '"GIT_NO_REPLACE_OBJECTS": "1"',
            "_verify_accepted_tracked_source_descriptors(accepted_source_manifest, watched)",
            'parser.add_argument("--accepted-source-root", required=True, type=Path)',
            'parser.add_argument("--accepted-source-sha", required=True)',
        ):
            self.assertIn(marker, guard)
        self.assertGreaterEqual(
            guard.count("_verify_accepted_tracked_source_descriptors(accepted_source_manifest, watched)"),
            2,
        )

    def test_canonical_field_gate_rejects_ambient_source_sha_authority(self) -> None:
        gate = FIELD_GATE.read_text(encoding="utf-8")
        self.assertIn('AUTHORITY_GIT_DIR="$ROOT/.git"', gate)
        self.assertIn('SOURCE_SHA="$(run_authority_git rev-parse --verify ', gate)
        self.assertIn("field source authority regressed to ambient Git execution", gate)


if __name__ == "__main__":
    unittest.main(verbosity=2)

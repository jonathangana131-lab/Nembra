#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
HELPER_PATH = REPOSITORY_ROOT / "Scripts" / "capture_tuya_private_input_provenance.py"
BOOTSTRAP_PATH = REPOSITORY_ROOT / "Scripts" / "bootstrap_capture_tuya_sdk.sh"
FIELD_INSTALLER_PATH = REPOSITORY_ROOT / "scripts" / "field" / "install_one_time_capture.command"
SPEC = importlib.util.spec_from_file_location("capture_tuya_private_input_provenance", HELPER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load Capture private-input provenance helper")
provenance = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(provenance)

PRIVATE_DEVICE_RUNNER_PATH = REPOSITORY_ROOT / "scripts" / "ci" / "es80_signed_field_artifact_private_runner.py"
PRIVATE_DEVICE_RUNNER_SPEC = importlib.util.spec_from_file_location(
    "es80_signed_field_artifact_private_runner",
    PRIVATE_DEVICE_RUNNER_PATH,
)
if PRIVATE_DEVICE_RUNNER_SPEC is None or PRIVATE_DEVICE_RUNNER_SPEC.loader is None:
    raise RuntimeError("could not load hardened intended-device runner")
private_device_runner = importlib.util.module_from_spec(PRIVATE_DEVICE_RUNNER_SPEC)
PRIVATE_DEVICE_RUNNER_SPEC.loader.exec_module(private_device_runner)


class CaptureTuyaPrivateInputProvenanceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.sdk = self.root / "TuyaSDK"
        self.identity = self.root / "TuyaRuntime"
        self.security_build = self.sdk / "Build"
        self.identity_sources = self.identity / "Sources" / "NembraTuyaPrivateConfig"
        self.security_build.mkdir(parents=True)
        self.identity_sources.mkdir(parents=True)
        self.security_podspec = self.sdk / "ThingSmartCryption.podspec"
        self.identity_podspec = self.identity / "NembraTuyaPrivateConfig.podspec"
        self.lockfile = self.root / "Podfile.lock"
        self.record = self.identity / "ResolvedTuyaDependencyProvenance.txt"
        self.security_podspec.write_text("security-podspec-v1", encoding="utf-8")
        (self.security_build / "ThingSmartCryption.bin").write_bytes(b"security-bytes-v1")
        self.identity_podspec.write_text("private-config-podspec-v1", encoding="utf-8")
        (self.identity_sources / "NembraTuyaPrivateIdentity.swift").write_text(
            'private let encodedAppKey = "TOPSECRET-APPKEY"\n'
            'private let encodedAppSecret = "TOPSECRET-APPSECRET"\n',
            encoding="utf-8",
        )
        self.lockfile.write_text(
            "  - ThingSmartHomeKit (7.8.0)\n"
            "  - ThingSmartBusinessExtensionKit (7.8.0)\n",
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def current(self) -> dict[str, str]:
        return provenance.build_record(
            lockfile=self.lockfile,
            security_podspec=self.security_podspec,
            security_build=self.security_build,
            identity_podspec=self.identity_podspec,
            identity_sources=self.identity_sources,
        )

    def snapshot(self) -> dict[str, str]:
        current = self.current()
        provenance.write_record(self.record, current)
        return current

    def test_hardened_intended_device_runner_executes_its_adversarial_self_test(self) -> None:
        private_device_runner.self_test()

    def test_field_build_requires_preaccepted_lock_before_xcodebuild(self) -> None:
        bootstrap = BOOTSTRAP_PATH.read_text(encoding="utf-8")
        installer = FIELD_INSTALLER_PATH.read_text(encoding="utf-8")

        review_mode = 'if [[ "${1:-}" == "--resolve-lock-for-review" ]]; then'
        required_digest = ': "${NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:?'
        digest_shape = '[[ "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]]'
        lock_compare = '[[ "$LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]]'
        review_only_stop = 'DEPENDENCY LOCK CANDIDATE ONLY — NOT FIELD BUILD AUTHORITY'
        bootstrap_call = 'run_accepted_source_bash "Scripts/bootstrap_capture_tuya_sdk.sh"'
        retired_bootstrap_call = '"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"'
        build_call = "-- xcodebuild"

        for required in (
            review_mode,
            required_digest,
            digest_shape,
            lock_compare,
            review_only_stop,
        ):
            self.assertIn(required, bootstrap)
        self.assertLess(bootstrap.index(required_digest), bootstrap.index("pod install --repo-update"))
        self.assertLess(bootstrap.index(lock_compare), bootstrap.index("NEXT BUILD RULE:"))
        self.assertIn(bootstrap_call, installer)
        self.assertNotIn(
            retired_bootstrap_call,
            installer,
            "field bootstrap must not be reopened from the mutable checkout pathname",
        )
        self.assertIn(build_call, installer)
        self.assertLess(installer.index(bootstrap_call), installer.index(build_call))

    def test_snapshot_contains_only_fingerprints_and_is_private(self) -> None:
        current = self.snapshot()
        provenance.verify_record(self.record, current)

        text = self.record.read_text(encoding="utf-8")
        self.assertIn("schema=nembra-capture-tuya-dependencies-v2", text)
        self.assertIn("thing_smart_home_kit=7.8.0", text)
        self.assertIn("thing_smart_cryption_build_tree_sha256=", text)
        self.assertIn("private_identity_sources_tree_sha256=", text)
        self.assertNotIn("TOPSECRET-APPKEY", text)
        self.assertNotIn("TOPSECRET-APPSECRET", text)
        self.assertEqual(stat.S_IMODE(self.record.stat().st_mode), 0o600)

    def test_security_sdk_mutation_invalidates_snapshot(self) -> None:
        self.snapshot()
        (self.security_build / "ThingSmartCryption.bin").write_bytes(b"security-bytes-v2")
        with self.assertRaises(provenance.ProvenanceError):
            provenance.verify_record(self.record, self.current())

    def test_private_identity_mutation_invalidates_snapshot(self) -> None:
        self.snapshot()
        (self.identity_sources / "NembraTuyaPrivateIdentity.swift").write_text(
            'private let encodedAppKey = "DIFFERENT"\n', encoding="utf-8"
        )
        with self.assertRaises(provenance.ProvenanceError):
            provenance.verify_record(self.record, self.current())

    def test_lockfile_mutation_invalidates_snapshot(self) -> None:
        self.snapshot()
        self.lockfile.write_text("different resolution", encoding="utf-8")
        with self.assertRaises(provenance.ProvenanceError):
            provenance.verify_record(self.record, self.current())

    def test_file_fingerprint_rejects_same_size_mutation_during_read(self) -> None:
        target = self.security_podspec
        original_read = provenance.os.read
        mutated = False

        def read_then_mutate(descriptor: int, count: int) -> bytes:
            nonlocal mutated
            chunk = original_read(descriptor, count)
            if chunk and not mutated:
                mutated = True
                target.write_bytes(b"Z" * target.stat().st_size)
            return chunk

        with mock.patch.object(provenance.os, "read", side_effect=read_then_mutate):
            with self.assertRaises(provenance.ProvenanceError):
                provenance._file_fingerprint(target)
        self.assertTrue(mutated)

    def test_lockfile_digest_rejects_same_size_mutation_during_read(self) -> None:
        target = self.lockfile
        original_read = provenance.os.read
        mutated = False

        def read_then_mutate(descriptor: int, count: int) -> bytes:
            nonlocal mutated
            chunk = original_read(descriptor, count)
            if chunk and not mutated:
                mutated = True
                target.write_bytes(b"L" * target.stat().st_size)
            return chunk

        with mock.patch.object(provenance.os, "read", side_effect=read_then_mutate):
            with self.assertRaises(provenance.ProvenanceError):
                self.current()
        self.assertTrue(mutated)

    def test_file_fingerprint_rejects_same_inode_mutation_after_final_descriptor_stat(self) -> None:
        target = self.security_podspec
        size = target.stat().st_size
        inode = target.stat().st_ino
        original_lstat = Path.lstat
        mutated = False

        def mutate_then_lstat(path: Path) -> os.stat_result:
            nonlocal mutated
            if path == target and not mutated:
                mutated = True
                target.write_bytes(b"Q" * size)
            return original_lstat(path)

        with mock.patch.object(Path, "lstat", autospec=True, side_effect=mutate_then_lstat):
            with self.assertRaises(provenance.ProvenanceError):
                provenance._file_fingerprint(target)

        self.assertTrue(mutated)
        self.assertEqual(target.stat().st_ino, inode)

    def test_tree_rejects_file_replacement_after_individual_fingerprint(self) -> None:
        target = self.security_build / "ThingSmartCryption.bin"
        replacement = self.root / "replacement.bin"
        replacement.write_bytes(b"replacement-bytes")
        original_fingerprint = provenance._file_fingerprint
        replaced = False

        def fingerprint_then_replace(path: Path, **kwargs: object) -> str:
            nonlocal replaced
            result = original_fingerprint(path, **kwargs)
            if path == target and not replaced:
                replaced = True
                os.replace(replacement, target)
            return result

        with mock.patch.object(
            provenance,
            "_file_fingerprint",
            side_effect=fingerprint_then_replace,
        ):
            with self.assertRaises(provenance.ProvenanceError):
                provenance._tree_fingerprint(self.security_build)
        self.assertTrue(replaced)

    def test_tree_binds_open_descriptor_to_enumerated_file_identity(self) -> None:
        target = self.security_build / "ThingSmartCryption.bin"
        replacement = self.root / "replacement-before-open.bin"
        replacement.write_bytes(b"attacker-replacement-bytes")
        original_open = provenance.os.open
        original_lstat = Path.lstat
        substituted_open = False
        post_open_target_lstat_calls = 0

        def open_replacement(path: object, flags: int, *args: object, **kwargs: object) -> int:
            nonlocal substituted_open
            if Path(path) == target:
                substituted_open = True
                return original_open(replacement, flags, *args, **kwargs)
            return original_open(path, flags, *args, **kwargs)

        def lstat_aba(path: Path) -> os.stat_result:
            nonlocal post_open_target_lstat_calls
            if path == target and substituted_open and post_open_target_lstat_calls == 0:
                post_open_target_lstat_calls += 1
                return original_lstat(replacement)
            return original_lstat(path)

        with mock.patch.object(provenance.os, "open", side_effect=open_replacement), mock.patch.object(
            Path, "lstat", autospec=True, side_effect=lstat_aba
        ):
            with self.assertRaises(provenance.ProvenanceError):
                provenance._tree_fingerprint(self.security_build)

        self.assertTrue(substituted_open)
        self.assertEqual(target.read_bytes(), b"security-bytes-v1")

    def test_tree_rejects_entry_added_after_directory_enumeration(self) -> None:
        target = self.security_build / "ThingSmartCryption.bin"
        late_entry = self.security_build / "late.bin"
        original_fingerprint = provenance._file_fingerprint
        added = False

        def fingerprint_then_add(path: Path, **kwargs: object) -> str:
            nonlocal added
            result = original_fingerprint(path, **kwargs)
            if path == target and not added:
                added = True
                late_entry.write_bytes(b"late")
            return result

        with mock.patch.object(
            provenance,
            "_file_fingerprint",
            side_effect=fingerprint_then_add,
        ):
            with self.assertRaises(provenance.ProvenanceError):
                provenance._tree_fingerprint(self.security_build)
        self.assertTrue(added)

    def test_record_symlink_is_rejected(self) -> None:
        self.snapshot()
        alternate = self.root / "alternate-record"
        alternate.write_text(self.record.read_text(encoding="utf-8"), encoding="utf-8")
        os.chmod(alternate, 0o600)
        self.record.unlink()
        self.record.symlink_to(alternate)
        with self.assertRaises(provenance.ProvenanceError):
            provenance.read_record(self.record)

    def test_escaping_security_tree_symlink_is_rejected(self) -> None:
        outside = self.root / "outside.bin"
        outside.write_bytes(b"outside")
        (self.security_build / "escape").symlink_to(outside)
        with self.assertRaises(provenance.ProvenanceError):
            self.current()


if __name__ == "__main__":
    unittest.main()

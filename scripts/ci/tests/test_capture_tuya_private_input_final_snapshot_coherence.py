#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
HELPER_PATH = REPOSITORY_ROOT / "Scripts" / "capture_tuya_private_input_provenance.py"
SPEC = importlib.util.spec_from_file_location("capture_tuya_private_input_provenance", HELPER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load Capture private-input provenance helper")
provenance = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(provenance)


class CaptureTuyaPrivateInputFinalSnapshotCoherenceTests(unittest.TestCase):
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
        self.security_podspec.write_text("security-podspec-v1", encoding="utf-8")
        (self.security_build / "ThingSmartCryption.bin").write_bytes(b"security-bytes-v1")
        self.identity_podspec.write_text("private-config-podspec-v1", encoding="utf-8")
        (self.identity_sources / "NembraTuyaPrivateIdentity.swift").write_text(
            'private let encodedAppKey = "TOPSECRET-APPKEY"\n'
            'private let encodedAppSecret = "TOPSECRET-APPSECRET"\n',
            encoding="utf-8",
        )
        self.original_lockfile = (
            "  - ThingSmartHomeKit (7.8.0)\n"
            "  - ThingSmartBusinessExtensionKit (7.8.0)\n"
        )
        self.lockfile.write_text(self.original_lockfile, encoding="utf-8")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def build_record(self) -> dict[str, str]:
        return provenance.build_record(
            lockfile=self.lockfile,
            security_podspec=self.security_podspec,
            security_build=self.security_build,
            identity_podspec=self.identity_podspec,
            identity_sources=self.identity_sources,
        )

    def test_final_after_snapshot_rejects_earlier_lockfile_mutate_restore(self) -> None:
        original_tree_snapshot = provenance._tree_generation_snapshot
        tree_generation_calls = 0
        mutated_and_restored = False

        def snapshot_then_mutate_restore(path: Path):
            nonlocal tree_generation_calls, mutated_and_restored
            result = original_tree_snapshot(path)
            tree_generation_calls += 1
            if tree_generation_calls == 4 and not mutated_and_restored:
                self.lockfile.write_text("different resolution", encoding="utf-8")
                self.lockfile.write_text(self.original_lockfile, encoding="utf-8")
                mutated_and_restored = True
            return result

        with mock.patch.object(
            provenance,
            "_tree_generation_snapshot",
            side_effect=snapshot_then_mutate_restore,
        ):
            with self.assertRaises(provenance.ProvenanceError):
                self.build_record()

        self.assertTrue(mutated_and_restored)
        self.assertEqual(tree_generation_calls, 4)

    def test_final_after_snapshot_rejects_earlier_tree_file_mutate_restore(self) -> None:
        original_tree_snapshot = provenance._tree_generation_snapshot
        tree_generation_calls = 0
        mutated_and_restored = False
        target = self.security_build / "ThingSmartCryption.bin"
        original = target.read_bytes()

        def snapshot_then_mutate_restore(path: Path):
            nonlocal tree_generation_calls, mutated_and_restored
            result = original_tree_snapshot(path)
            tree_generation_calls += 1
            if tree_generation_calls == 4 and not mutated_and_restored:
                target.write_bytes(b"Z" * len(original))
                target.write_bytes(original)
                mutated_and_restored = True
            return result

        with mock.patch.object(
            provenance,
            "_tree_generation_snapshot",
            side_effect=snapshot_then_mutate_restore,
        ):
            with self.assertRaises(provenance.ProvenanceError):
                self.build_record()

        self.assertTrue(mutated_and_restored)
        self.assertEqual(tree_generation_calls, 4)

    def test_final_after_snapshot_rejects_earlier_tree_membership_mutate_restore(self) -> None:
        original_tree_snapshot = provenance._tree_generation_snapshot
        tree_generation_calls = 0
        mutated_and_restored = False
        transient = self.security_build / "transient.bin"

        def snapshot_then_mutate_restore(path: Path):
            nonlocal tree_generation_calls, mutated_and_restored
            result = original_tree_snapshot(path)
            tree_generation_calls += 1
            if tree_generation_calls == 4 and not mutated_and_restored:
                transient.write_bytes(b"transient")
                transient.unlink()
                mutated_and_restored = True
            return result

        with mock.patch.object(
            provenance,
            "_tree_generation_snapshot",
            side_effect=snapshot_then_mutate_restore,
        ):
            with self.assertRaises(provenance.ProvenanceError):
                self.build_record()

        self.assertTrue(mutated_and_restored)
        self.assertEqual(tree_generation_calls, 4)

    def test_generation_snapshot_uses_kernel_mutation_guard_not_only_sequential_rechecks(self) -> None:
        source = HELPER_PATH.read_text(encoding="utf-8")
        snapshot_start = source.index("def _private_input_record_generation_snapshot(")
        snapshot_end = source.index("\ndef build_record", snapshot_start)
        snapshot_source = source[snapshot_start:snapshot_end]
        build_start = source.index("def build_record(")
        build_end = source.index("\ndef _record_text", build_start)
        build_source = source[build_start:build_end]

        self.assertNotIn("    return (\n", snapshot_source)
        self.assertIn("mutation_guard.assert_unchanged", snapshot_source)
        self.assertIn("_PrivateInputMutationSentinel", build_source)
        self.assertIn("with _PrivateInputMutationSentinel", build_source)
        self.assertIn("inotify_init1", source)
        self.assertIn("select.kqueue", source)
        self.assertIn("kernel mutation sentinel", source.lower())


if __name__ == "__main__":
    unittest.main()

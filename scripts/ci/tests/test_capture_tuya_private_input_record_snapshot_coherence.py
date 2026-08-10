#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
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


class CaptureTuyaPrivateInputRecordSnapshotCoherenceTests(unittest.TestCase):
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

    def test_record_rejects_earlier_input_mutation_during_later_tree_fingerprint(self) -> None:
        original_tree_fingerprint = provenance._tree_fingerprint
        mutated_and_restored = False

        def fingerprint_then_cross_input_mutation(path: Path) -> str:
            nonlocal mutated_and_restored
            result = original_tree_fingerprint(path)
            if path == self.identity_sources and not mutated_and_restored:
                self.lockfile.write_text("different resolution", encoding="utf-8")
                self.lockfile.write_text(self.original_lockfile, encoding="utf-8")
                mutated_and_restored = True
            return result

        with mock.patch.object(provenance, "_tree_fingerprint", side_effect=fingerprint_then_cross_input_mutation):
            with self.assertRaises(provenance.ProvenanceError):
                self.build_record()

        self.assertTrue(mutated_and_restored)

    def test_record_rejects_tree_member_mutation_restored_after_earlier_tree_fingerprint(self) -> None:
        original_file_fingerprint = provenance._file_fingerprint
        member = self.security_build / "ThingSmartCryption.bin"
        original = member.read_bytes()
        mutated_and_restored = False

        def fingerprint_then_cross_tree_mutation(path: Path) -> str:
            nonlocal mutated_and_restored
            result = original_file_fingerprint(path)
            if path == self.identity_podspec and not mutated_and_restored:
                member.write_bytes(b"temporary-different-bytes")
                member.write_bytes(original)
                mutated_and_restored = True
            return result

        with mock.patch.object(provenance, "_file_fingerprint", side_effect=fingerprint_then_cross_tree_mutation):
            with self.assertRaises(provenance.ProvenanceError):
                self.build_record()

        self.assertTrue(mutated_and_restored)

    def test_build_record_has_one_whole_snapshot_boundary_not_only_per_component_reads(self) -> None:
        source = HELPER_PATH.read_text(encoding="utf-8")
        start = source.index("def build_record(")
        end = source.index("\ndef _record_text", start)
        build_record_source = source[start:end]

        self.assertNotIn("    return {", build_record_source)
        self.assertIn("_record_input_snapshot", build_record_source)
        self.assertIn("before_snapshot", build_record_source)
        self.assertIn("after_snapshot", build_record_source)
        self.assertIn("before_snapshot != after_snapshot", build_record_source)


if __name__ == "__main__":
    unittest.main()

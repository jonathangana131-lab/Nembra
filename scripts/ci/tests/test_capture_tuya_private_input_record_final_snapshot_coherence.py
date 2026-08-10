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

    def test_one_record_snapshot_revalidates_earlier_authority_after_last_tree_collection(self) -> None:
        original_tree_snapshot = provenance._tree_identity_snapshot
        tree_calls = 0
        mutated_and_restored = False

        def tree_snapshot_with_cross_input_mutation(path: Path):
            nonlocal tree_calls, mutated_and_restored
            tree_calls += 1
            result = original_tree_snapshot(path)
            # The first two tree calls are the collection phase. Mutate and restore
            # the already-collected standalone lockfile after the last tree collection;
            # a self-coherent record witness must then globally revalidate it.
            if tree_calls == 2 and not mutated_and_restored:
                self.assertEqual(path, self.identity_sources)
                self.lockfile.write_text("transient different resolution", encoding="utf-8")
                self.lockfile.write_text(self.original_lockfile, encoding="utf-8")
                mutated_and_restored = True
            return result

        with mock.patch.object(
            provenance,
            "_tree_identity_snapshot",
            side_effect=tree_snapshot_with_cross_input_mutation,
        ):
            with self.assertRaises(provenance.ProvenanceError):
                provenance._record_identity_snapshot(
                    lockfile=self.lockfile,
                    security_podspec=self.security_podspec,
                    security_build=self.security_build,
                    identity_podspec=self.identity_podspec,
                    identity_sources=self.identity_sources,
                )

        self.assertTrue(mutated_and_restored)
        self.assertGreaterEqual(tree_calls, 2)

    def test_tree_snapshot_revalidates_entries_and_membership_before_return(self) -> None:
        source = HELPER_PATH.read_text(encoding="utf-8")
        start = source.index("def _tree_identity_snapshot(")
        end = source.index("\ndef _record_identity_snapshot(", start)
        tree_source = source[start:end]

        self.assertIn("observed_states", tree_source)
        self.assertIn("observed_directory_members", tree_source)
        self.assertIn("_assert_unchanged_tree_entry", tree_source)
        self.assertIn("_directory_member_names", tree_source)

    def test_record_snapshot_has_global_revalidation_after_all_collection(self) -> None:
        source = HELPER_PATH.read_text(encoding="utf-8")
        start = source.index("def _record_identity_snapshot(")
        end = source.index("\ndef build_record(", start)
        snapshot_source = source[start:end]

        self.assertIn("lockfile_identity", snapshot_source)
        self.assertIn("identity_sources_snapshot", snapshot_source)
        self.assertIn("_tree_identity_snapshot(security_build) != security_build_snapshot", snapshot_source)
        self.assertIn("_tree_identity_snapshot(identity_sources) != identity_sources_snapshot", snapshot_source)
        self.assertIn("_regular_file_identity_snapshot(lockfile) != lockfile_identity", snapshot_source)
        self.assertIn("private build input set changed while record identity was captured", snapshot_source)
        self.assertNotIn("    return (\n        (\"lockfile\", _regular_file_identity_snapshot", snapshot_source)


if __name__ == "__main__":
    unittest.main()

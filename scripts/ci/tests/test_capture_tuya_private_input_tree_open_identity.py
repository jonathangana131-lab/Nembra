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


class CaptureTuyaPrivateInputTreeOpenIdentityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name) / "Build"
        self.root.mkdir(parents=True)
        self.binary = self.root / "ThingSmartCryption.bin"
        self.original_bytes = b"reviewed-security-bytes"
        self.replacement_bytes = b"swapped-unreviewed-security-bytes"
        self.binary.write_bytes(self.original_bytes)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_tree_fingerprint_binds_opened_file_to_identity_admitted_by_tree_walk(self) -> None:
        original_file_fingerprint = provenance._file_fingerprint
        swapped = False

        def fingerprint_with_lstat_to_open_swap(path: Path, *args, **kwargs) -> str:
            nonlocal swapped
            if path != self.binary or swapped:
                return original_file_fingerprint(path, *args, **kwargs)

            swapped = True
            backup = path.with_name(path.name + ".admitted-backup")
            path.rename(backup)
            path.write_bytes(self.replacement_bytes)
            try:
                # Current d7fb code hashes this replacement inode because the tree's
                # earlier lstat identity is no longer passed into _file_fingerprint.
                fingerprint = original_file_fingerprint(path, *args, **kwargs)
            finally:
                path.unlink()
                backup.rename(path)
            return fingerprint

        with mock.patch.object(
            provenance,
            "_file_fingerprint",
            side_effect=fingerprint_with_lstat_to_open_swap,
        ):
            with self.assertRaises(provenance.ProvenanceError):
                provenance._tree_fingerprint(self.root)

        self.assertTrue(swapped)
        self.assertEqual(self.binary.read_bytes(), self.original_bytes)

    def test_tree_source_passes_admitted_identity_into_file_fingerprint(self) -> None:
        source = HELPER_PATH.read_text(encoding="utf-8")
        start = source.index("def _tree_fingerprint(")
        end = source.index("\ndef _regular_file_identity_snapshot", start)
        tree_source = source[start:end]

        self.assertIn("expected_identity=identity", tree_source)
        self.assertIn("expected_identity", source[source.index("def _read_stable_regular_file_sha256("):start])


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
HELPER = ROOT / "Scripts" / "capture_tuya_private_input_provenance.py"
SPEC = importlib.util.spec_from_file_location("capture_tuya_private_input_provenance", HELPER)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load provenance helper")
provenance = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(provenance)


class PostPathDescriptorCustodyRedTests(unittest.TestCase):
    def test_same_inode_mutation_after_pathname_sample_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "ThingSmartCryption.podspec"
            target.write_bytes(b"AAAA")
            original_inode = target.stat().st_ino
            original_lstat = Path.lstat
            mutated = False

            def lstat_then_mutate(path: Path) -> os.stat_result:
                nonlocal mutated
                metadata = original_lstat(path)
                if path == target and not mutated:
                    mutated = True
                    target.write_bytes(b"BBBB")
                    os.utime(
                        target,
                        ns=(metadata.st_atime_ns, metadata.st_mtime_ns + 1_000_000_000),
                    )
                return metadata

            with mock.patch.object(Path, "lstat", autospec=True, side_effect=lstat_then_mutate):
                with self.assertRaises(provenance.ProvenanceError):
                    provenance._file_fingerprint(target)

            self.assertTrue(mutated)
            self.assertEqual(target.stat().st_ino, original_inode)
            self.assertEqual(target.stat().st_size, 4)

    def test_source_has_post_path_descriptor_reconciliation(self) -> None:
        source = HELPER.read_text(encoding="utf-8")
        start = source.index("def _read_stable_regular_file_sha256(")
        end = source.index("\ndef _file_fingerprint(", start)
        helper = source[start:end]
        pathname = helper.index("current_path = path.lstat()")
        final_fstat = helper.find("os.fstat(descriptor)", pathname)
        self.assertNotEqual(final_fstat, -1)
        self.assertIn("_stat_identity(final_descriptor)", helper[pathname:])


if __name__ == "__main__":
    unittest.main()

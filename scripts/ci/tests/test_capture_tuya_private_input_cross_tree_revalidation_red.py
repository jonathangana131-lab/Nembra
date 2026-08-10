#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
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


class CrossTreeRevalidationTests(unittest.TestCase):
    def test_earlier_tree_is_checked_after_later_tree_revalidation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first_tree = root / "FirstTree"
            second_tree = root / "SecondTree"
            first_tree.mkdir()
            second_tree.mkdir()
            first_file = first_tree / "library.bin"
            first_file.write_bytes(b"AAAA")
            (second_tree / "identity.swift").write_text("identity", encoding="utf-8")
            lockfile = root / "Podfile.lock"
            first_podspec = root / "first.podspec"
            second_podspec = root / "second.podspec"
            lockfile.write_text("lock", encoding="utf-8")
            first_podspec.write_text("first", encoding="utf-8")
            second_podspec.write_text("second", encoding="utf-8")

            original_tree_snapshot = provenance._tree_generation_snapshot
            tree_calls = 0
            changed_and_restored = False

            def tree_snapshot_with_late_change(path: Path):
                nonlocal tree_calls, changed_and_restored
                tree_calls += 1
                result = original_tree_snapshot(path)
                if tree_calls == 4:
                    self.assertEqual(path, second_tree)
                    first_file.write_bytes(b"BBBB")
                    first_file.write_bytes(b"AAAA")
                    changed_and_restored = True
                return result

            with mock.patch.object(
                provenance,
                "_tree_generation_snapshot",
                side_effect=tree_snapshot_with_late_change,
            ):
                with self.assertRaises(provenance.ProvenanceError):
                    provenance._private_input_record_generation_snapshot(
                        lockfile=lockfile,
                        security_podspec=first_podspec,
                        security_build=first_tree,
                        identity_podspec=second_podspec,
                        identity_sources=second_tree,
                    )

            self.assertTrue(changed_and_restored)
            self.assertEqual(tree_calls, 4)


if __name__ == "__main__":
    unittest.main()

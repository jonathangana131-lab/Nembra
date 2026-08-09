#!/usr/bin/env python3
"""Prove Final GO local evidence bytes stay bound to the validated opened inode."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
SUBJECT = ROOT / "scripts/ci/_es80_today_final_go_foundation_impl.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_foundation_impl_fd", SUBJECT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load Final GO foundation implementation")
foundation = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(foundation)


class LocalEvidenceDescriptorCustodyTests(unittest.TestCase):
    def test_same_size_bytes_cannot_change_after_path_check_before_read(self) -> None:
        trusted = b"A" * 4096
        substituted = b"B" * 4096

        with tempfile.TemporaryDirectory() as temporary:
            subject = Path(temporary) / "authority.json"
            subject.write_bytes(trusted)
            original_read_bytes = Path.read_bytes
            raced = False

            def mutate_then_reopen(path: Path) -> bytes:
                nonlocal raced
                if path == subject and not raced:
                    raced = True
                    subject.write_bytes(substituted)
                return original_read_bytes(path)

            with mock.patch.object(Path, "read_bytes", mutate_then_reopen):
                try:
                    observed = foundation._regular(subject, "authority subject")
                except foundation.FinalGoError:
                    return

            self.assertNotEqual(
                observed,
                substituted,
                "Final GO admitted same-size bytes that appeared only after the pathname check",
            )
            self.assertEqual(observed, trusted)

    def test_symlink_subject_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / "target.json"
            link = root / "authority.json"
            target.write_bytes(b"trusted")
            link.symlink_to(target)
            with self.assertRaises(foundation.FinalGoError):
                foundation._regular(link, "authority subject")


if __name__ == "__main__":
    unittest.main()

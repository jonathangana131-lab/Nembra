#!/usr/bin/env python3
"""Regression coverage for descriptor-bound local Final GO evidence custody."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "_es80_today_final_go_foundation_impl.py"
spec = importlib.util.spec_from_file_location("final_go_impl", MODULE_PATH)
final_go = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(final_go)


class FinalGoLocalEvidenceDescriptorCustodyTests(unittest.TestCase):
    def test_regular_does_not_check_one_path_then_reopen_it_for_authority_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / "evidence.bin"
            evidence.write_bytes(b"trusted-authority")
            with mock.patch.object(
                Path,
                "read_bytes",
                side_effect=AssertionError("authority path was reopened after metadata check"),
            ):
                self.assertEqual(final_go._regular(evidence, "evidence"), b"trusted-authority")

    def test_regular_rejects_final_component_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "target.bin"
            target.write_bytes(b"trusted-authority")
            link = root / "link.bin"
            link.symlink_to(target)
            with self.assertRaises(final_go.FinalGoError):
                final_go._regular(link, "evidence")

    def test_regular_rejects_path_rebind_after_descriptor_open(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = root / "evidence.bin"
            attacker = root / "attacker.bin"
            evidence.write_bytes(b"trusted-authority")
            attacker.write_bytes(b"forged--authority")
            self.assertEqual(evidence.stat().st_size, attacker.stat().st_size)

            real_read = os.read
            swapped = False

            def swap_then_read(fd: int, count: int) -> bytes:
                nonlocal swapped
                if not swapped:
                    swapped = True
                    attacker.replace(evidence)
                return real_read(fd, count)

            with mock.patch.object(final_go.os, "read", side_effect=swap_then_read):
                with self.assertRaisesRegex(final_go.FinalGoError, "path identity changed"):
                    final_go._regular(evidence, "evidence")
            self.assertTrue(swapped, "race fixture did not replace the pathname")

    def test_regular_rejects_in_place_metadata_change_during_descriptor_read(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / "evidence.bin"
            evidence.write_bytes(b"a" * (1024 * 1024 + 32))

            real_read = os.read
            changed = False

            def change_then_read(fd: int, count: int) -> bytes:
                nonlocal changed
                chunk = real_read(fd, count)
                if chunk and not changed:
                    changed = True
                    with evidence.open("r+b") as handle:
                        handle.seek(0)
                        handle.write(b"b")
                        handle.flush()
                        os.fsync(handle.fileno())
                return chunk

            with mock.patch.object(final_go.os, "read", side_effect=change_then_read):
                with self.assertRaisesRegex(final_go.FinalGoError, "changed while reading"):
                    final_go._regular(evidence, "evidence")
            self.assertTrue(changed, "race fixture did not mutate the opened file")


if __name__ == "__main__":
    unittest.main()

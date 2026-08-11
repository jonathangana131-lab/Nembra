#!/usr/bin/env python3
"""Crash-residue reuse must never act on a swapped replacement pathname."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
WRITER_PATH = ROOT / "Scripts/provision_capture_tuya_identity_writer.py"
PREFIX = ".nembra-private-stage-"


def load_writer():
    spec = importlib.util.spec_from_file_location("nembra_private_identity_recovery_inode_custody", WRITER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("private identity writer import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PrivateIdentityRecoveryInodeCustodyTests(unittest.TestCase):
    def test_post_admission_name_swap_preserves_replacement_and_admitted_inode(self) -> None:
        writer = load_writer()
        admitted_payload = b"dummy-admitted-crash-residue"
        replacement_payload = b"attacker-replacement-must-survive"
        new_payload = b"new-private-output"

        with tempfile.TemporaryDirectory(prefix="nembra-private-recovery-inode-custody-") as temporary:
            checkout = Path(temporary) / "repo"
            destination_parent = checkout / "private"
            destination_parent.mkdir(parents=True, mode=0o700)
            stage_name = f"{PREFIX}{os.getpid()}-{'f' * 24}"
            escaped_name = "attacker-renamed-admitted-residue"
            stage = checkout / stage_name
            escaped = checkout / escaped_name
            destination = destination_parent / "identity.swift"
            stage.write_bytes(admitted_payload)
            stage.chmod(0o600)

            checkout_fd = os.open(checkout, writer._directory_flags())
            destination_fd = os.open(destination_parent, writer._directory_flags())
            recovered = None
            try:
                recovered = writer._recover_private_stage_residue(checkout_fd)
                self.assertIsNotNone(recovered, "fixture did not admit the writer-shaped crash residue")

                os.rename(stage_name, escaped_name, src_dir_fd=checkout_fd, dst_dir_fd=checkout_fd)
                replacement_fd = os.open(
                    stage_name,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW,
                    0o600,
                    dir_fd=checkout_fd,
                )
                try:
                    os.write(replacement_fd, replacement_payload)
                    os.fsync(replacement_fd)
                finally:
                    os.close(replacement_fd)

                with self.assertRaises(writer.ProvisionError):
                    writer._write_staged(
                        checkout_fd,
                        destination_fd,
                        "identity.swift",
                        "private/identity.swift",
                        new_payload,
                        recovered_stage=recovered,
                    )
            finally:
                if recovered is not None:
                    recovered.close()
                os.close(destination_fd)
                os.close(checkout_fd)

            self.assertTrue(escaped.is_file(), "admitted inode disappeared after fail-closed name swap")
            self.assertEqual(escaped.read_bytes(), admitted_payload)
            self.assertTrue(stage.is_file(), "recovery deleted the replacement pathname subject")
            self.assertEqual(stage.read_bytes(), replacement_payload)
            self.assertFalse(destination.exists(), "failed recovery published a private output")

    def test_recovery_source_never_pathname_unlinks_admitted_residue(self) -> None:
        source = WRITER_PATH.read_text(encoding="utf-8")
        start = source.index("def _recover_private_stage_residue")
        end = source.index("def _ensure_private_directory", start)
        recovery = source[start:end]
        self.assertNotIn("os.unlink(", recovery)
        self.assertIn("return recovered", recovery)
        self.assertIn("_RecoveredPrivateStage", recovery)


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Crash-residue recovery must neutralize only the held inode under a name swap.

Production successor to expected-red #2918. The attacker swaps the admitted
residue at the exact descriptor-neutralization boundary inside the authenticated
LocalSecrets staging root. Recovery must truncate the already-held inode, never
the replacement pathname subject, then fail closed because the canonical name
no longer binds the neutralized inode. Dummy bytes only; this is logical byte
handling, not secure-media erasure.
"""
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
    spec = importlib.util.spec_from_file_location("nembra_private_identity_recovery_neutralization", WRITER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("private identity writer import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def make_staging_root(checkout: Path) -> Path:
    root = checkout / "LocalSecrets"
    root.mkdir(mode=0o700)
    return root


class PrivateIdentityRecoveryNeutralizationTests(unittest.TestCase):
    def test_name_swap_at_neutralization_preserves_replacement_and_zeros_held_inode(self) -> None:
        writer = load_writer()
        admitted_payload = b"dummy-admitted-crash-residue"
        replacement_payload = b"attacker-replacement-must-survive"

        with tempfile.TemporaryDirectory(prefix="nembra-private-recovery-neutralization-") as temporary:
            checkout = Path(temporary) / "repo"
            checkout.mkdir(mode=0o700)
            staging_root = make_staging_root(checkout)
            stage_name = f"{PREFIX}{os.getpid()}-{'f' * 24}"
            escaped_name = "attacker-renamed-admitted-residue"
            stage = staging_root / stage_name
            escaped = staging_root / escaped_name
            stage.write_bytes(admitted_payload)
            stage.chmod(0o600)

            staging_fd = os.open(staging_root, writer._directory_flags())
            real_ftruncate = writer.os.ftruncate
            attack_fired = False

            def interpose_at_neutralization(descriptor: int, length: int) -> None:
                nonlocal attack_fired
                if length == 0 and not attack_fired:
                    attack_fired = True
                    writer.os.rename(
                        stage_name,
                        escaped_name,
                        src_dir_fd=staging_fd,
                        dst_dir_fd=staging_fd,
                    )
                    replacement_fd = writer.os.open(
                        stage_name,
                        writer.os.O_WRONLY
                        | writer.os.O_CREAT
                        | writer.os.O_EXCL
                        | writer.os.O_CLOEXEC
                        | writer.os.O_NOFOLLOW,
                        0o600,
                        dir_fd=staging_fd,
                    )
                    try:
                        writer.os.fchmod(replacement_fd, 0o600)
                        writer.os.write(replacement_fd, replacement_payload)
                        writer.os.fsync(replacement_fd)
                    finally:
                        writer.os.close(replacement_fd)
                real_ftruncate(descriptor, length)

            writer.os.ftruncate = interpose_at_neutralization
            try:
                with self.assertRaises(
                    writer.ProvisionError,
                    msg="recovery accepted a name swap at the credential-neutralization boundary",
                ):
                    writer._recover_private_stage_residue(staging_fd)
            finally:
                writer.os.ftruncate = real_ftruncate
                os.close(staging_fd)

            self.assertEqual(
                sorted(checkout.glob(f"{PREFIX}*")),
                [],
                "replacement-race fixture escaped LocalSecrets into the raw checkout root",
            )
            self.assertTrue(attack_fired, "fixture did not interpose at descriptor neutralization")
            self.assertTrue(escaped.is_file(), "fixture lost the originally admitted held residue")
            self.assertEqual(
                escaped.read_bytes(),
                b"",
                "recovery failed to neutralize credential bytes through the admitted descriptor",
            )
            self.assertTrue(
                stage.is_file(),
                "recovery deleted the replacement pathname subject outside held-inode authority",
            )
            self.assertEqual(
                stage.read_bytes(),
                replacement_payload,
                "recovery modified the replacement pathname subject outside held-inode authority",
            )

    def test_zero_length_canonical_tombstone_is_inert_inside_local_secrets(self) -> None:
        writer = load_writer()
        with tempfile.TemporaryDirectory(prefix="nembra-private-recovery-tombstone-") as temporary:
            checkout = Path(temporary) / "repo"
            checkout.mkdir(mode=0o700)
            staging_root = make_staging_root(checkout)
            stage = staging_root / f"{PREFIX}{os.getpid()}-{'e' * 24}"
            stage.write_bytes(b"")
            stage.chmod(0o600)
            staging_fd = os.open(staging_root, writer._directory_flags())
            try:
                writer._recover_private_stage_residue(staging_fd)
            finally:
                os.close(staging_fd)
            self.assertEqual(sorted(checkout.glob(f"{PREFIX}*")), [])
            self.assertTrue(stage.is_file())
            self.assertEqual(stage.read_bytes(), b"")


if __name__ == "__main__":
    unittest.main(verbosity=2)
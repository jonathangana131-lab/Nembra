#!/usr/bin/env python3
"""Adversarial: same-UID name swap cannot redirect crash-residue destruction.

Recovery may logically sanitize only the exact already-admitted inode. This test
replaces its pathname immediately before descriptor truncation. The replacement
must survive byte-for-byte, while the escaped admitted inode is sanitized and
recovery fails closed because the canonical name no longer binds that inode.
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
    spec = importlib.util.spec_from_file_location("nembra_private_identity_recovery_descriptor_race", WRITER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("private identity writer import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PrivateIdentityRecoveryDescriptorRaceTests(unittest.TestCase):
    def test_name_swap_before_descriptor_sanitize_preserves_replacement(self) -> None:
        writer = load_writer()
        admitted_payload = b"dummy-admitted-crash-residue"
        replacement_payload = b"attacker-replacement-must-survive"

        with tempfile.TemporaryDirectory(prefix="nembra-private-recovery-descriptor-race-") as temporary:
            checkout = Path(temporary) / "repo"
            checkout.mkdir(mode=0o700)
            stage_name = f"{PREFIX}{os.getpid()}-{'f' * 24}"
            escaped_name = "attacker-renamed-admitted-residue"
            stage = checkout / stage_name
            escaped = checkout / escaped_name
            stage.write_bytes(admitted_payload)
            stage.chmod(0o600)

            checkout_fd = os.open(checkout, writer._directory_flags())
            real_ftruncate = writer.os.ftruncate
            attack_fired = False

            def interpose_at_ftruncate(descriptor: int, length: int):
                nonlocal attack_fired
                if not attack_fired:
                    attack_fired = True
                    writer.os.rename(
                        stage_name,
                        escaped_name,
                        src_dir_fd=checkout_fd,
                        dst_dir_fd=checkout_fd,
                    )
                    replacement_fd = writer.os.open(
                        stage_name,
                        writer.os.O_WRONLY
                        | writer.os.O_CREAT
                        | writer.os.O_EXCL
                        | writer.os.O_CLOEXEC
                        | writer.os.O_NOFOLLOW,
                        0o600,
                        dir_fd=checkout_fd,
                    )
                    try:
                        writer.os.fchmod(replacement_fd, 0o600)
                        writer.os.write(replacement_fd, replacement_payload)
                        writer.os.fsync(replacement_fd)
                    finally:
                        writer.os.close(replacement_fd)
                return real_ftruncate(descriptor, length)

            writer.os.ftruncate = interpose_at_ftruncate
            try:
                with self.assertRaises(
                    writer.ProvisionError,
                    msg="recovery accepted a name swap at the destructive descriptor boundary",
                ):
                    writer._recover_private_stage_residue(checkout_fd)
            finally:
                writer.os.ftruncate = real_ftruncate
                os.close(checkout_fd)

            self.assertTrue(attack_fired, "fixture did not interpose at descriptor sanitization")
            self.assertTrue(escaped.is_file(), "escaped admitted residue disappeared")
            self.assertEqual(
                escaped.read_bytes(),
                b"",
                "recovery failed to sanitize the exact admitted inode after its name was moved",
            )
            self.assertTrue(stage.is_file(), "recovery deleted the replacement pathname subject")
            self.assertEqual(
                stage.read_bytes(),
                replacement_payload,
                "recovery mutated replacement bytes outside the admitted inode authority",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)

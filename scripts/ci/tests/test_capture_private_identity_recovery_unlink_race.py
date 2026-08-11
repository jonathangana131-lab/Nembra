#!/usr/bin/env python3
"""Expected-red: crash-residue cleanup must never unlink a swapped replacement inode.

The production recovery path admits one writer-shaped stage under descriptor
custody, then removes it by pathname. A same-UID actor can replace that name
between the final identity check and unlink. Detection after unlink is too late
if the replacement inode has already been deleted.

This regression uses dummy bytes only. It requires failure to preserve the
replacement pathname subject while also refusing to claim that the originally
admitted held inode lost its final link.
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
    spec = importlib.util.spec_from_file_location("nembra_private_identity_recovery_unlink_race", WRITER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("private identity writer import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PrivateIdentityRecoveryUnlinkRaceTests(unittest.TestCase):
    def test_name_swap_immediately_before_unlink_never_deletes_replacement(self) -> None:
        writer = load_writer()
        admitted_payload = b"dummy-admitted-crash-residue"
        replacement_payload = b"attacker-replacement-must-survive"

        with tempfile.TemporaryDirectory(prefix="nembra-private-recovery-unlink-race-") as temporary:
            checkout = Path(temporary) / "repo"
            checkout.mkdir(mode=0o700)
            stage_name = f"{PREFIX}{os.getpid()}-{'f' * 24}"
            escaped_name = "attacker-renamed-admitted-residue"
            stage = checkout / stage_name
            escaped = checkout / escaped_name
            stage.write_bytes(admitted_payload)
            stage.chmod(0o600)

            checkout_fd = os.open(checkout, writer._directory_flags())
            real_unlink = writer.os.unlink
            attack_fired = False

            def interpose_at_unlink(path, *args, dir_fd=None, **kwargs):
                nonlocal attack_fired
                if path == stage_name and dir_fd == checkout_fd and not attack_fired:
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
                return real_unlink(path, *args, dir_fd=dir_fd, **kwargs)

            writer.os.unlink = interpose_at_unlink
            try:
                with self.assertRaises(
                    writer.ProvisionError,
                    msg="recovery accepted a name swap at the final deletion boundary",
                ):
                    writer._recover_private_stage_residue(checkout_fd)
            finally:
                writer.os.unlink = real_unlink
                os.close(checkout_fd)

            self.assertTrue(attack_fired, "fixture did not interpose at the production unlink boundary")
            self.assertTrue(
                escaped.is_file(),
                "fixture lost the originally admitted held residue instead of demonstrating the rename race",
            )
            self.assertEqual(escaped.read_bytes(), admitted_payload)
            self.assertTrue(
                stage.is_file(),
                "recovery deleted the same-UID replacement inode before detecting that the held inode was still linked",
            )
            self.assertEqual(
                stage.read_bytes(),
                replacement_payload,
                "recovery changed or deleted the replacement pathname subject outside its admitted inode authority",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)

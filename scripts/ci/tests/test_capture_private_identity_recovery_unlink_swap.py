#!/usr/bin/env python3
"""Expected-red witness for private-identity crash-residue deletion authority.

The recovery path admits one exact writer-shaped staging inode, then unlinks its
reserved pathname. A same-UID actor can swap that pathname after the final
identity check but before unlink. Detection after unlink is too late if recovery
has already deleted the replacement inode and left the admitted residue linked
under another name.

The safe contract is narrower: a failed recovery may not delete a pathname
replacement that was never the admitted held inode, and it may not claim the
admitted residue was removed unless that exact held inode lost its final link.
Dummy payloads only; this makes no secure-erasure claim.
"""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import stat
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
WRITER_PATH = REPOSITORY / "Scripts" / "provision_capture_tuya_identity_writer.py"
RESERVED_PREFIX = ".nembra-private-stage-"


def load_writer():
    spec = importlib.util.spec_from_file_location(
        "nembra_private_identity_recovery_unlink_swap_redteam",
        WRITER_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("private identity writer import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_regular(parent_fd: int, name: str, payload: bytes) -> None:
    descriptor = os.open(
        name,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW,
        0o600,
        dir_fd=parent_fd,
    )
    try:
        view = memoryview(payload)
        offset = 0
        while offset < len(view):
            written = os.write(descriptor, view[offset:])
            if written <= 0:
                raise RuntimeError("could not write adversarial fixture")
            offset += written
        os.fchmod(descriptor, 0o600)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


class PrivateIdentityRecoveryUnlinkSwapTests(unittest.TestCase):
    def test_recovery_cannot_delete_replacement_after_admission_before_unlink(self) -> None:
        writer = load_writer()
        admitted_payload = b"writer-shaped-crash-residue"
        replacement_payload = b"same-uid-replacement-must-survive"

        with tempfile.TemporaryDirectory(prefix="nembra-private-recovery-unlink-swap-") as temporary:
            checkout = Path(temporary) / "repo"
            checkout.mkdir(mode=0o700)
            checkout_fd = os.open(checkout, writer._directory_flags())
            stage_name = f"{RESERVED_PREFIX}{os.getpid()}-{'a' * 24}"
            stolen_name = f"{stage_name}.renamed-after-admission"
            write_regular(checkout_fd, stage_name, admitted_payload)

            original_unlink = writer.os.unlink
            attacked = False

            def adversarial_unlink(path, *args, **kwargs):
                nonlocal attacked
                dir_fd = kwargs.get("dir_fd")
                if not attacked and path == stage_name and dir_fd == checkout_fd:
                    attacked = True
                    os.rename(
                        stage_name,
                        stolen_name,
                        src_dir_fd=checkout_fd,
                        dst_dir_fd=checkout_fd,
                    )
                    write_regular(checkout_fd, stage_name, replacement_payload)
                return original_unlink(path, *args, **kwargs)

            writer.os.unlink = adversarial_unlink
            failed_closed = False
            try:
                try:
                    writer._recover_private_stage_residue(checkout_fd)
                except (writer.ProvisionError, OSError):
                    failed_closed = True
            finally:
                writer.os.unlink = original_unlink
                os.close(checkout_fd)

            stage = checkout / stage_name
            stolen = checkout / stolen_name
            self.assertTrue(attacked, "attack never reached the final check-to-unlink window")
            self.assertTrue(failed_closed, "recovery reported success after its admitted inode was renamed away")
            self.assertTrue(stolen.is_file(), "fixture did not preserve the admitted held residue under its swapped name")
            self.assertEqual(stolen.read_bytes(), admitted_payload)

            self.assertTrue(
                stage.is_file(),
                "recovery deleted a replacement inode before detecting that the admitted held residue still had a link",
            )
            metadata = stage.stat()
            self.assertTrue(stat.S_ISREG(metadata.st_mode))
            self.assertEqual(stat.S_IMODE(metadata.st_mode), 0o600)
            self.assertEqual(stage.read_bytes(), replacement_payload)


if __name__ == "__main__":
    unittest.main(verbosity=2)

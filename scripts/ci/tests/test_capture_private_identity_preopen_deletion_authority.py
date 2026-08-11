#!/usr/bin/env python3
"""Expected-red V14 witness for private identity rejection cleanup authority.

The writer must not acquire deletion authority over a same-UID replacement merely
because that replacement occupies the canonical credential name after publication.
This attack swaps the accepted published inode away *before* the writer performs
its first final-path reopen. Rejection is required, but the attacker replacement
must survive; only the exact writer-owned sealed inode may authorize cleanup.
"""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
WRITER_PATH = ROOT / "Scripts" / "provision_capture_tuya_identity_writer.py"


def load_writer():
    spec = importlib.util.spec_from_file_location(
        "nembra_private_identity_preopen_deletion_authority_redteam",
        WRITER_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("private identity writer import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_regular_at(root_fd: int, relative_path: str, payload: bytes) -> None:
    descriptor = os.open(
        relative_path,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW,
        0o600,
        dir_fd=root_fd,
    )
    try:
        view = memoryview(payload)
        offset = 0
        while offset < len(view):
            written = os.write(descriptor, view[offset:])
            if written <= 0:
                raise RuntimeError("could not write attacker replacement")
            offset += written
        os.fchmod(descriptor, 0o600)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


class PrivateIdentityPreopenDeletionAuthorityTests(unittest.TestCase):
    def test_post_publication_preopen_replacement_must_survive_rejection(self) -> None:
        writer = load_writer()
        payload = b"sealed-private-identity-payload"
        attacker_payload = b"A" * len(payload)
        destination = "private/identity.swift"
        stolen_destination = "private/identity.swift.sealed-stolen"

        with tempfile.TemporaryDirectory(prefix="nembra-private-preopen-delete-") as temporary:
            checkout = Path(temporary) / "repo"
            parent = checkout / "private"
            parent.mkdir(parents=True, mode=0o700)
            checkout_fd = os.open(checkout, writer._directory_flags())
            parent_fd = os.open(parent, writer._directory_flags())
            original_replace = writer._secure_replace_beneath
            attacked = False

            def publish_then_replace(
                root_fd: int,
                source_name: str,
                destination_relative: str,
                sealed,
            ) -> None:
                nonlocal attacked
                original_replace(root_fd, source_name, destination_relative, sealed)
                self.assertEqual(destination_relative, destination)
                os.rename(
                    destination_relative,
                    stolen_destination,
                    src_dir_fd=root_fd,
                    dst_dir_fd=root_fd,
                )
                write_regular_at(root_fd, destination_relative, attacker_payload)
                attacked = True

            writer._secure_replace_beneath = publish_then_replace
            succeeded = False
            try:
                try:
                    writer._write_staged(
                        checkout_fd,
                        parent_fd,
                        "identity.swift",
                        destination,
                        payload,
                    )
                    succeeded = True
                except (writer.ProvisionError, OSError):
                    pass
            finally:
                writer._secure_replace_beneath = original_replace
                os.close(parent_fd)
                os.close(checkout_fd)

            canonical = parent / "identity.swift"
            stolen = parent / "identity.swift.sealed-stolen"

            self.assertTrue(attacked, "attack never reached the post-publication/pre-final-open window")
            self.assertFalse(succeeded, "writer accepted a canonical destination that no longer names the sealed inode")
            self.assertTrue(stolen.is_file(), "attack did not preserve the writer-owned sealed inode")
            self.assertEqual(stolen.read_bytes(), payload)
            self.assertTrue(
                canonical.is_file(),
                "rejection deleted a same-UID attacker replacement using newly observed final-inode authority",
            )
            self.assertEqual(
                canonical.read_bytes(),
                attacker_payload,
                "rejection modified or replaced attacker-controlled canonical bytes",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)

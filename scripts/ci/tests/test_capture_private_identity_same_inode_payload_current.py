#!/usr/bin/env python3
"""Expected-red diagnostic for same-inode private identity staging mutation."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
WRITER_PATH = REPOSITORY / "Scripts" / "provision_capture_tuya_identity_writer.py"


def load_writer():
    spec = importlib.util.spec_from_file_location(
        "nembra_private_identity_same_inode_current", WRITER_PATH
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("private identity writer import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PrivateIdentitySameInodePayloadCurrentTests(unittest.TestCase):
    def test_same_inode_same_size_staging_mutation_cannot_be_accepted(self) -> None:
        writer = load_writer()
        payload = b"accepted-private-identity-payload"
        attacker_payload = b"X" * len(payload)

        with tempfile.TemporaryDirectory(prefix="nembra-private-same-inode-") as temporary:
            checkout = Path(temporary) / "repo"
            parent = checkout / "private"
            parent.mkdir(parents=True, mode=0o700)
            checkout_fd = os.open(checkout, writer._directory_flags())
            parent_fd = os.open(parent, writer._directory_flags())
            original_publish = writer._secure_replace_beneath
            attacked = False

            def adversarial_publish(root_fd: int, src: str, dst: str, sealed) -> None:
                nonlocal attacked
                if not attacked:
                    mutation_fd = os.open(
                        src,
                        os.O_WRONLY | getattr(os, "O_CLOEXEC", 0) | os.O_NOFOLLOW,
                        dir_fd=root_fd,
                    )
                    try:
                        current = os.fstat(mutation_fd)
                        self.assertEqual((current.st_dev, current.st_ino), (sealed.st_dev, sealed.st_ino))
                        os.lseek(mutation_fd, 0, os.SEEK_SET)
                        view = memoryview(attacker_payload)
                        offset = 0
                        while offset < len(view):
                            written = os.write(mutation_fd, view[offset:])
                            self.assertGreater(written, 0)
                            offset += written
                        os.ftruncate(mutation_fd, len(attacker_payload))
                        os.fsync(mutation_fd)
                    finally:
                        os.close(mutation_fd)
                    attacked = True
                original_publish(root_fd, src, dst, sealed)

            writer._secure_replace_beneath = adversarial_publish
            rejected = False
            try:
                try:
                    writer._write_staged(
                        checkout_fd,
                        parent_fd,
                        "identity.swift",
                        "private/identity.swift",
                        payload,
                    )
                except (writer.ProvisionError, OSError):
                    rejected = True
            finally:
                writer._secure_replace_beneath = original_publish
                os.close(parent_fd)
                os.close(checkout_fd)

            final = parent / "identity.swift"
            final_bytes = final.read_bytes() if final.is_file() else None
            self.assertTrue(attacked, "diagnostic never reached the sealed staging publication boundary")
            self.assertTrue(
                rejected or final_bytes == payload,
                "writer accepted same-inode attacker bytes because metadata identity remained unchanged",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)

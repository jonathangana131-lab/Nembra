#!/usr/bin/env python3
"""Expected-red diagnostic for private identity destination-ancestor substitution."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
WRITER_PATH = REPOSITORY / "Scripts" / "provision_capture_tuya_identity_writer.py"


def load_writer():
    spec = importlib.util.spec_from_file_location("nembra_private_identity_writer_ancestor_redteam", WRITER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("private identity writer import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PrivateIdentityDestinationAncestorSwapTests(unittest.TestCase):
    def test_rejected_current_destination_ancestor_swap_does_not_leave_attacker_payload(self) -> None:
        writer = load_writer()
        payload = b"accepted-private-identity-payload"
        attacker_payload = b"Z" * len(payload)

        with tempfile.TemporaryDirectory(prefix="nembra-private-destination-ancestor-") as temporary:
            checkout = Path(temporary) / "repo"
            parent = checkout / "private"
            parent.mkdir(parents=True, mode=0o700)
            checkout_fd = os.open(checkout, writer._directory_flags())
            parent_fd = os.open(parent, writer._directory_flags())
            original_open = writer._open_relative_regular_file
            attacked = False

            def adversarial_open(root_fd: int, relative_path: str) -> int:
                nonlocal attacked
                if not attacked and relative_path == "private/identity.swift":
                    attacked = True
                    os.rename("private", "private.detached", src_dir_fd=root_fd, dst_dir_fd=root_fd)
                    os.mkdir("private", 0o700, dir_fd=root_fd)
                    replacement_parent_fd = os.open("private", writer._directory_flags(), dir_fd=root_fd)
                    try:
                        attacker_fd = os.open(
                            "identity.swift",
                            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW,
                            0o600,
                            dir_fd=replacement_parent_fd,
                        )
                        try:
                            os.write(attacker_fd, attacker_payload)
                            os.fchmod(attacker_fd, 0o600)
                            os.fsync(attacker_fd)
                        finally:
                            os.close(attacker_fd)
                    finally:
                        os.close(replacement_parent_fd)
                return original_open(root_fd, relative_path)

            writer._open_relative_regular_file = adversarial_open
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
                writer._open_relative_regular_file = original_open
                os.close(parent_fd)
                os.close(checkout_fd)

            canonical = checkout / "private" / "identity.swift"
            canonical_bytes = canonical.read_bytes() if canonical.is_file() else None
            detached = checkout / "private.detached" / "identity.swift"

            self.assertTrue(attacked, "diagnostic never reached the post-publication final-open seam")
            self.assertTrue(rejected, "writer reported success after destination ancestry was replaced")
            self.assertNotEqual(
                canonical_bytes,
                attacker_payload,
                "rejected publication left attacker bytes at the canonical credential destination",
            )
            self.assertTrue(
                detached.is_file(),
                "diagnostic did not preserve the originally published accepted inode in detached ancestry",
            )
            self.assertEqual(detached.read_bytes(), payload)


if __name__ == "__main__":
    unittest.main(verbosity=2)

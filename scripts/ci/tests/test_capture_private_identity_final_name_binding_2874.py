#!/usr/bin/env python3
"""Adversarial test for private identity canonical destination-name binding.

A same-UID actor may replace the destination pathname after the writer has opened
and verified the sealed published inode. Success must never coexist with attacker
bytes at the canonical credential name.
"""

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
        "nembra_private_identity_final_name_binding_redteam",
        WRITER_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("private identity writer import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_regular_at(parent_fd: int, name: str, payload: bytes) -> None:
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
                raise RuntimeError("could not write attacker fixture")
            offset += written
        os.fchmod(descriptor, 0o600)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


class PrivateIdentityFinalNameBindingTests(unittest.TestCase):
    def test_destination_name_swap_after_verified_open_cannot_return_success(self) -> None:
        writer = load_writer()
        payload = b"sealed-private-identity-payload"
        attacker_payload = b"Y" * len(payload)

        with tempfile.TemporaryDirectory(prefix="nembra-private-final-name-") as temporary:
            checkout = Path(temporary) / "repo"
            parent = checkout / "private"
            parent.mkdir(parents=True, mode=0o700)
            checkout_fd = os.open(checkout, writer._directory_flags())
            parent_fd = os.open(parent, writer._directory_flags())
            original_open = writer._open_relative_regular_file
            attacked = False

            def adversarial_open(root_fd: int, relative_path: str) -> int:
                nonlocal attacked
                descriptor = original_open(root_fd, relative_path)
                if not attacked and relative_path == "private/identity.swift":
                    attacked = True
                    os.rename(
                        relative_path,
                        f"{relative_path}.sealed-stolen",
                        src_dir_fd=root_fd,
                        dst_dir_fd=root_fd,
                    )
                    write_regular_at(root_fd, relative_path, attacker_payload)
                return descriptor

            writer._open_relative_regular_file = adversarial_open
            succeeded = False
            try:
                try:
                    writer._write_staged(
                        checkout_fd,
                        parent_fd,
                        "identity.swift",
                        "private/identity.swift",
                        payload,
                    )
                    succeeded = True
                except (writer.ProvisionError, OSError):
                    pass
            finally:
                writer._open_relative_regular_file = original_open
                os.close(parent_fd)
                os.close(checkout_fd)

            final = parent / "identity.swift"
            final_bytes = final.read_bytes() if final.is_file() else None
            stolen = parent / "identity.swift.sealed-stolen"

            self.assertTrue(attacked, "attack never reached the post-open/pre-success window")
            self.assertFalse(
                succeeded and final_bytes == attacker_payload,
                "writer reported success while the credential destination named attacker bytes",
            )
            if succeeded:
                self.assertTrue(stolen.is_file(), "attack did not preserve the held sealed inode")
                self.assertEqual(stolen.read_bytes(), payload)


if __name__ == "__main__":
    unittest.main(verbosity=2)

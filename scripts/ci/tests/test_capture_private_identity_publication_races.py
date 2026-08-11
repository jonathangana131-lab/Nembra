#!/usr/bin/env python3
"""Adversarial custody tests for private Tuya identity publication.

These tests exercise the real descriptor-bound writer and deliberately simulate
same-UID filesystem races at the two remaining publication boundaries:
1. staging-name substitution after the staged inode has been sealed;
2. detaching an already-open private directory from the admitted checkout before
   credential-bearing publication.

A safe writer must fail closed rather than report success with substituted bytes
or write the credential-bearing Swift identity into detached ancestry.
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


def load_writer():
    spec = importlib.util.spec_from_file_location("nembra_private_identity_writer_redteam", WRITER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("private identity writer import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PrivateIdentityPublicationRaceTests(unittest.TestCase):
    def test_staging_name_substitution_cannot_be_accepted_as_published_payload(self) -> None:
        writer = load_writer()
        payload = b"accepted-private-identity-payload"
        attacker_payload = b"X" * len(payload)

        with tempfile.TemporaryDirectory(prefix="nembra-private-staging-race-") as temporary:
            parent = Path(temporary) / "private"
            parent.mkdir(mode=0o700)
            parent_fd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY)
            original_replace = writer.os.replace
            attacked = False

            def adversarial_replace(src, dst, *, src_dir_fd=None, dst_dir_fd=None):
                nonlocal attacked
                if not attacked:
                    attacked = True
                    self.assertIsNotNone(src_dir_fd)
                    stolen = f"{src}.attacker-stolen"
                    os.rename(src, stolen, src_dir_fd=src_dir_fd, dst_dir_fd=src_dir_fd)
                    replacement_fd = os.open(
                        src,
                        os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                        0o600,
                        dir_fd=src_dir_fd,
                    )
                    try:
                        view = memoryview(attacker_payload)
                        offset = 0
                        while offset < len(view):
                            written = os.write(replacement_fd, view[offset:])
                            self.assertGreater(written, 0)
                            offset += written
                        os.fchmod(replacement_fd, 0o600)
                        os.fsync(replacement_fd)
                    finally:
                        os.close(replacement_fd)
                return original_replace(
                    src,
                    dst,
                    src_dir_fd=src_dir_fd,
                    dst_dir_fd=dst_dir_fd,
                )

            writer.os.replace = adversarial_replace
            rejected = False
            try:
                try:
                    writer._write_staged(parent_fd, "identity.swift", payload)
                except (writer.ProvisionError, OSError):
                    rejected = True
            finally:
                writer.os.replace = original_replace
                os.close(parent_fd)

            final = parent / "identity.swift"
            final_bytes = final.read_bytes() if final.exists() else None
            self.assertTrue(attacked, "diagnostic never reached the staging publication boundary")
            self.assertTrue(
                rejected or final_bytes == payload,
                "writer accepted a different inode/payload substituted under the sealed staging name",
            )
            self.assertNotEqual(
                final_bytes,
                attacker_payload,
                "attacker-controlled replacement bytes were accepted as the published private identity",
            )

    def test_detached_private_directory_cannot_receive_credential_bearing_identity(self) -> None:
        writer = load_writer()
        key_b64 = "bmVtYnJhLWR1bW15LWFwcC1rZXk="
        secret_b64 = "bmVtYnJhLWR1bW15LWFwcC1zZWNyZXQ="

        with tempfile.TemporaryDirectory(prefix="nembra-private-ancestry-race-") as temporary:
            sandbox = Path(temporary)
            checkout = sandbox / "repo"
            checkout.mkdir(mode=0o700)
            checkout_fd = os.open(checkout, writer._directory_flags())
            outside_runtime = sandbox / "detached-TuyaRuntime"
            original_replace = writer.os.replace
            attacked = False

            def adversarial_replace(src, dst, *, src_dir_fd=None, dst_dir_fd=None):
                nonlocal attacked
                if not attacked:
                    runtime = checkout / "LocalSecrets" / "TuyaRuntime"
                    self.assertTrue(runtime.is_dir(), "runtime directory was not created before publication")
                    os.rename(runtime, outside_runtime)
                    attacked = True
                return original_replace(
                    src,
                    dst,
                    src_dir_fd=src_dir_fd,
                    dst_dir_fd=dst_dir_fd,
                )

            writer.os.replace = adversarial_replace
            try:
                try:
                    writer.provision(checkout_fd, checkout, key_b64, secret_b64)
                except (writer.ProvisionError, OSError):
                    pass
            finally:
                writer.os.replace = original_replace
                os.close(checkout_fd)

            detached_identity = (
                outside_runtime
                / "Sources"
                / "NembraTuyaPrivateConfig"
                / "NembraTuyaPrivateIdentity.swift"
            )
            self.assertTrue(attacked, "diagnostic never reached the descendant publication boundary")
            self.assertFalse(
                detached_identity.exists(),
                "credential-bearing identity was written through a directory FD after that directory was detached from the admitted checkout",
            )

            canonical_identity = (
                checkout
                / "LocalSecrets"
                / "TuyaRuntime"
                / "Sources"
                / "NembraTuyaPrivateConfig"
                / "NembraTuyaPrivateIdentity.swift"
            )
            if canonical_identity.exists():
                mode = stat.S_IMODE(canonical_identity.stat().st_mode)
                self.assertEqual(mode, 0o600)


if __name__ == "__main__":
    unittest.main(verbosity=2)

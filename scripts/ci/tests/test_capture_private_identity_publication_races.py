#!/usr/bin/env python3
"""Adversarial custody tests for private Tuya identity publication.

The attacks are injected at the writer's secure-publication seam so the same
contract exercises Linux CI fallback and Darwin renameatx_np publication.
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
            checkout = Path(temporary) / "repo"
            parent = checkout / "private"
            parent.mkdir(parents=True, mode=0o700)
            checkout_fd = os.open(checkout, writer._directory_flags())
            parent_fd = os.open(parent, writer._directory_flags())
            original_publish = writer._secure_replace_beneath
            attacked = False

            def adversarial_publish(root_fd: int, src: str, dst: str) -> None:
                nonlocal attacked
                if not attacked:
                    attacked = True
                    stolen = f"{src}.attacker-stolen"
                    os.rename(src, stolen, src_dir_fd=root_fd, dst_dir_fd=root_fd)
                    replacement_fd = os.open(
                        src,
                        os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                        0o600,
                        dir_fd=root_fd,
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
                original_publish(root_fd, src, dst)

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
            final_bytes = final.read_bytes() if final.exists() else None
            self.assertTrue(attacked, "diagnostic never reached the staging publication boundary")
            self.assertTrue(rejected, "writer accepted a substituted staging inode as successful publication")
            self.assertNotEqual(
                final_bytes,
                attacker_payload,
                "attacker-controlled replacement bytes remained accepted at the final private identity path",
            )


    def test_same_staging_inode_payload_mutation_cannot_be_accepted(self) -> None:
        writer = load_writer()
        payload = b"accepted-private-identity-payload"
        attacker_payload = b"Y" * len(payload)

        with tempfile.TemporaryDirectory(prefix="nembra-private-same-inode-race-") as temporary:
            checkout = Path(temporary) / "repo"
            parent = checkout / "private"
            parent.mkdir(parents=True, mode=0o700)
            checkout_fd = os.open(checkout, writer._directory_flags())
            parent_fd = os.open(parent, writer._directory_flags())
            original_publish = writer._secure_replace_beneath
            attacked = False

            def adversarial_publish(root_fd: int, src: str, dst: str) -> None:
                nonlocal attacked
                if not attacked:
                    attacked = True
                    mutation_fd = os.open(
                        src,
                        os.O_WRONLY | os.O_CLOEXEC | os.O_NOFOLLOW,
                        dir_fd=root_fd,
                    )
                    try:
                        os.lseek(mutation_fd, 0, os.SEEK_SET)
                        view = memoryview(attacker_payload)
                        offset = 0
                        while offset < len(view):
                            written = os.write(mutation_fd, view[offset:])
                            self.assertGreater(written, 0)
                            offset += written
                        os.fsync(mutation_fd)
                    finally:
                        os.close(mutation_fd)
                original_publish(root_fd, src, dst)

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
            final_bytes = final.read_bytes() if final.exists() else None
            self.assertTrue(attacked, "diagnostic never reached the sealed-inode publication boundary")
            self.assertTrue(
                rejected or final_bytes == payload,
                "writer reported success after the sealed staging inode payload changed in place",
            )
            self.assertNotEqual(
                final_bytes,
                attacker_payload,
                "same-inode attacker bytes were accepted as the published private identity",
            )

    def test_detached_private_directory_cannot_receive_or_stage_credential_identity(self) -> None:
        writer = load_writer()
        key_b64 = "bmVtYnJhLWR1bW15LWFwcC1rZXk="
        secret_b64 = "bmVtYnJhLWR1bW15LWFwcC1zZWNyZXQ="

        with tempfile.TemporaryDirectory(prefix="nembra-private-ancestry-race-") as temporary:
            sandbox = Path(temporary)
            checkout = sandbox / "repo"
            checkout.mkdir(mode=0o700)
            checkout_fd = os.open(checkout, writer._directory_flags())
            outside_runtime = sandbox / "detached-TuyaRuntime"
            original_publish = writer._secure_replace_beneath
            attacked = False
            leaked_before_publish: list[bytes] = []

            def adversarial_publish(root_fd: int, src: str, dst: str) -> None:
                nonlocal attacked
                if not attacked and dst.endswith("NembraTuyaPrivateIdentity.swift"):
                    runtime = checkout / "LocalSecrets" / "TuyaRuntime"
                    self.assertTrue(runtime.is_dir(), "runtime directory was not present before identity publication")
                    os.rename(runtime, outside_runtime)
                    attacked = True

                    detached_module = outside_runtime / "Sources" / "NembraTuyaPrivateConfig"
                    if detached_module.is_dir():
                        for candidate in detached_module.iterdir():
                            if candidate.name.startswith(".NembraTuyaPrivateIdentity.swift.nembra-"):
                                leaked_before_publish.append(candidate.read_bytes())
                original_publish(root_fd, src, dst)

            writer._secure_replace_beneath = adversarial_publish
            rejected = False
            try:
                try:
                    writer.provision(checkout_fd, checkout, key_b64, secret_b64)
                except (writer.ProvisionError, OSError):
                    rejected = True
            finally:
                writer._secure_replace_beneath = original_publish
                os.close(checkout_fd)

            detached_identity = (
                outside_runtime
                / "Sources"
                / "NembraTuyaPrivateConfig"
                / "NembraTuyaPrivateIdentity.swift"
            )
            self.assertTrue(attacked, "diagnostic never reached credential-bearing publication")
            self.assertTrue(rejected, "writer reported success after private ancestry was detached")
            self.assertEqual(
                leaked_before_publish,
                [],
                "credential-bearing staging bytes already existed inside descendant ancestry before secure publication",
            )
            self.assertFalse(
                detached_identity.exists(),
                "credential-bearing identity was published through ancestry detached from the admitted checkout",
            )

            canonical_identity = (
                checkout
                / "LocalSecrets"
                / "TuyaRuntime"
                / "Sources"
                / "NembraTuyaPrivateConfig"
                / "NembraTuyaPrivateIdentity.swift"
            )
            self.assertFalse(
                canonical_identity.exists(),
                "publication unexpectedly succeeded after the admitted descendant was detached",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)

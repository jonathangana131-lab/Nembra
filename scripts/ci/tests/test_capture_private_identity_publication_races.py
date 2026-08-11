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
    def _assert_staging_substitution_rejected(self, replacement_kind: str) -> None:
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
            replacement_name: str | None = None

            def adversarial_publish(root_fd: int, src: str, dst: str, sealed) -> None:
                nonlocal attacked, replacement_name
                if not attacked:
                    attacked = True
                    stolen = f"{src}.attacker-stolen"
                    os.rename(src, stolen, src_dir_fd=root_fd, dst_dir_fd=root_fd)
                    replacement_name = src
                    if replacement_kind == "regular":
                        replacement_fd = os.open(
                            src,
                            os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                            0o600,
                            dir_fd=root_fd,
                        )
                        try:
                            os.write(replacement_fd, attacker_payload)
                            os.fchmod(replacement_fd, 0o600)
                            os.fsync(replacement_fd)
                        finally:
                            os.close(replacement_fd)
                    elif replacement_kind == "directory":
                        os.mkdir(src, 0o700, dir_fd=root_fd)
                    elif replacement_kind == "symlink":
                        os.symlink("attacker-target", src, dir_fd=root_fd)
                    else:
                        raise AssertionError(f"unknown replacement kind {replacement_kind}")
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
            self.assertTrue(attacked, "diagnostic never reached the staging publication boundary")
            self.assertTrue(rejected, "writer accepted a substituted staging inode as successful publication")
            self.assertNotEqual(final_bytes, attacker_payload)

            replacement = checkout / replacement_name if replacement_name is not None else None
            self.assertIsNotNone(replacement)
            if replacement_kind == "regular":
                self.assertTrue(replacement.is_file(), "cleanup deleted attacker replacement regular file")
                self.assertEqual(replacement.read_bytes(), attacker_payload)
            elif replacement_kind == "directory":
                self.assertTrue(replacement.is_dir(), "cleanup removed attacker replacement directory")
            else:
                self.assertTrue(replacement.is_symlink(), "cleanup removed attacker replacement symlink")

    def test_staging_regular_file_substitution_cannot_be_published_or_cleaned_as_owned(self) -> None:
        self._assert_staging_substitution_rejected("regular")

    def test_staging_directory_substitution_cannot_be_published_or_cleaned_as_owned(self) -> None:
        self._assert_staging_substitution_rejected("directory")

    def test_staging_symlink_substitution_cannot_be_published_or_cleaned_as_owned(self) -> None:
        self._assert_staging_substitution_rejected("symlink")

    def test_post_check_substitution_fails_without_claiming_replacement_cleanup_authority(self) -> None:
        writer = load_writer()
        payload = b"accepted-private-identity-payload"
        attacker_payload = b"Y" * len(payload)

        with tempfile.TemporaryDirectory(prefix="nembra-private-post-check-race-") as temporary:
            checkout = Path(temporary) / "repo"
            parent = checkout / "private"
            parent.mkdir(parents=True, mode=0o700)
            checkout_fd = os.open(checkout, writer._directory_flags())
            parent_fd = os.open(parent, writer._directory_flags())
            original_require = writer._require_sealed_staging_name
            attacked = False
            stolen_name: str | None = None

            def adversarial_require(root_fd: int, src: str, sealed) -> None:
                nonlocal attacked, stolen_name
                original_require(root_fd, src, sealed)
                if attacked:
                    return
                attacked = True
                stolen_name = f"{src}.sealed-owner"
                os.rename(src, stolen_name, src_dir_fd=root_fd, dst_dir_fd=root_fd)
                replacement_fd = os.open(
                    src,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                    0o600,
                    dir_fd=root_fd,
                )
                try:
                    os.write(replacement_fd, attacker_payload)
                    os.fchmod(replacement_fd, 0o600)
                    os.fsync(replacement_fd)
                finally:
                    os.close(replacement_fd)

            writer._require_sealed_staging_name = adversarial_require
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
                writer._require_sealed_staging_name = original_require
                os.close(parent_fd)
                os.close(checkout_fd)

            final = parent / "identity.swift"
            stolen = checkout / stolen_name if stolen_name is not None else None
            self.assertTrue(attacked, "diagnostic never reached the post-name-check publication gap")
            self.assertTrue(rejected, "writer accepted the post-check staging substitution")
            self.assertTrue(final.is_file(), "writer deleted the attacker replacement after fail-closed publication")
            self.assertEqual(
                final.read_bytes(),
                attacker_payload,
                "writer mutated or deleted bytes outside the exact held staging inode authority",
            )
            self.assertIsNotNone(stolen, "fixture did not retain the accepted staging inode name")
            self.assertTrue(stolen.is_file(), "accepted held staging inode disappeared during failure sanitation")
            self.assertEqual(
                stolen.read_bytes(),
                b"",
                "credential-bearing accepted staging bytes survived fail-closed publication",
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

            def adversarial_publish(root_fd: int, src: str, dst: str, sealed) -> None:
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
                original_publish(root_fd, src, dst, sealed)

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

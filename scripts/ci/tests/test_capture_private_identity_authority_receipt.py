#!/usr/bin/env python3
"""Behavioral tests for the root-sealed private identity transaction receipt.

The production CLI requires root for seal/revocation. These tests exercise the
same internal custody functions with the current test UID standing in for the
protected authority owner inside an isolated temporary directory.
"""

from __future__ import annotations

import hashlib
import importlib.util
import os
import stat
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
HELPER_PATH = ROOT / "Scripts/capture_tuya_private_identity_authority.py"


def load_helper():
    spec = importlib.util.spec_from_file_location("nembra_private_identity_authority_tests", HELPER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("private identity authority helper import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_private(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    current = path.parent
    while current.name and current != current.parent:
        if current.name in {"LocalSecrets", "TuyaRuntime", "Sources", "NembraTuyaPrivateConfig"}:
            current.chmod(0o700)
        current = current.parent
    path.write_bytes(payload)
    path.chmod(0o600)


class PrivateIdentityAuthorityReceiptTests(unittest.TestCase):
    def make_subject(self, temporary: str):
        helper = load_helper()
        checkout = Path(temporary) / "repo"
        checkout.mkdir(mode=0o700)
        scripts = checkout / "Scripts"
        scripts.mkdir(mode=0o700)
        writer = scripts / "provision_capture_tuya_identity_writer.py"
        writer.write_bytes(b"accepted-writer-bytes\n")
        writer.chmod(0o600)
        podspec = checkout / helper.PODSPEC_RELATIVE
        identity = checkout / helper.IDENTITY_RELATIVE
        write_private(podspec, b"accepted-podspec\n")
        write_private(identity, b"accepted-identity\n")
        authority_root = Path(temporary) / "protected-authority"
        uid = os.geteuid()
        writer_sha = hashlib.sha256(writer.read_bytes()).hexdigest()
        podspec_sha = hashlib.sha256(podspec.read_bytes()).hexdigest()
        identity_sha = hashlib.sha256(identity.read_bytes()).hexdigest()
        return helper, checkout, authority_root, uid, writer_sha, podspec_sha, identity_sha, podspec, identity

    def test_successful_seal_verifies_exact_current_outputs(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-private-authority-success-") as temporary:
            helper, checkout, authority_root, uid, writer_sha, podspec_sha, identity_sha, _, _ = self.make_subject(temporary)
            receipt = helper._seal_current_subject(
                checkout,
                operator_uid=uid,
                expected_writer_sha256=writer_sha,
                expected_podspec_sha256=podspec_sha,
                expected_identity_sha256=identity_sha,
                authority_root=authority_root,
                authority_uid=uid,
            )
            self.assertTrue(receipt.is_file())
            verified = helper._verify_current_subject(
                checkout,
                operator_uid=uid,
                expected_writer_sha256=writer_sha,
                authority_root=authority_root,
                authority_uid=uid,
            )
            self.assertEqual(verified, receipt)

    def test_current_identity_change_is_rejected_even_with_old_receipt(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-private-authority-mutation-") as temporary:
            helper, checkout, authority_root, uid, writer_sha, podspec_sha, identity_sha, _, identity = self.make_subject(temporary)
            helper._seal_current_subject(
                checkout,
                operator_uid=uid,
                expected_writer_sha256=writer_sha,
                expected_podspec_sha256=podspec_sha,
                expected_identity_sha256=identity_sha,
                authority_root=authority_root,
                authority_uid=uid,
            )
            identity.write_bytes(b"attacker-replacement\n")
            identity.chmod(0o600)
            with self.assertRaises(helper.AuthorityError):
                helper._verify_current_subject(
                    checkout,
                    operator_uid=uid,
                    expected_writer_sha256=writer_sha,
                    authority_root=authority_root,
                    authority_uid=uid,
                )

    def test_new_attempt_revocation_prevents_stale_success_fallback(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-private-authority-revoke-") as temporary:
            helper, checkout, authority_root, uid, writer_sha, podspec_sha, identity_sha, _, identity = self.make_subject(temporary)
            helper._seal_current_subject(
                checkout,
                operator_uid=uid,
                expected_writer_sha256=writer_sha,
                expected_podspec_sha256=podspec_sha,
                expected_identity_sha256=identity_sha,
                authority_root=authority_root,
                authority_uid=uid,
            )
            helper._invalidate_current_subject(
                checkout,
                authority_root=authority_root,
                authority_uid=uid,
                operator_uid=uid,
            )
            # Model a failed later transaction leaving attacker bytes at the
            # canonical identity path. No new root receipt was sealed.
            identity.write_bytes(b"failed-attempt-attacker-source\n")
            identity.chmod(0o600)
            with self.assertRaises(helper.AuthorityError):
                helper._verify_current_subject(
                    checkout,
                    operator_uid=uid,
                    expected_writer_sha256=writer_sha,
                    authority_root=authority_root,
                    authority_uid=uid,
                )

    def test_strict_umask_creation_is_normalized_for_unprivileged_verify(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-private-authority-umask-") as temporary:
            helper, checkout, authority_root, uid, writer_sha, podspec_sha, identity_sha, _, _ = self.make_subject(temporary)
            previous_umask = os.umask(0o077)
            try:
                receipt = helper._seal_current_subject(
                    checkout,
                    operator_uid=uid,
                    expected_writer_sha256=writer_sha,
                    expected_podspec_sha256=podspec_sha,
                    expected_identity_sha256=identity_sha,
                    authority_root=authority_root,
                    authority_uid=uid,
                )
            finally:
                os.umask(previous_umask)
            self.assertTrue(receipt.is_file())
            self.assertEqual(stat.S_IMODE(authority_root.stat().st_mode), 0o755)
            self.assertEqual(
                helper._verify_current_subject(
                    checkout,
                    operator_uid=uid,
                    expected_writer_sha256=writer_sha,
                    authority_root=authority_root,
                    authority_uid=uid,
                ),
                receipt,
            )

    def test_root_owned_private_mode_residue_is_normalized_on_next_seal(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-private-authority-mode-recovery-") as temporary:
            helper, checkout, authority_root, uid, writer_sha, podspec_sha, identity_sha, _, _ = self.make_subject(temporary)
            authority_root.mkdir(mode=0o700)
            authority_root.chmod(0o700)
            helper._seal_current_subject(
                checkout,
                operator_uid=uid,
                expected_writer_sha256=writer_sha,
                expected_podspec_sha256=podspec_sha,
                expected_identity_sha256=identity_sha,
                authority_root=authority_root,
                authority_uid=uid,
            )
            self.assertEqual(stat.S_IMODE(authority_root.stat().st_mode), 0o755)

    def test_pathname_inode_swap_cannot_preserve_prior_transaction_receipt(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-private-authority-path-swap-") as temporary:
            helper, checkout, authority_root, uid, writer_sha, podspec_sha, identity_sha, _, _ = self.make_subject(temporary)
            receipt = helper._seal_current_subject(
                checkout,
                operator_uid=uid,
                expected_writer_sha256=writer_sha,
                expected_podspec_sha256=podspec_sha,
                expected_identity_sha256=identity_sha,
                authority_root=authority_root,
                authority_uid=uid,
            )
            self.assertTrue(receipt.is_file())

            parked = checkout.with_name("repo.admitted-before-swap")
            checkout.rename(parked)
            checkout.mkdir(mode=0o700)
            try:
                helper._invalidate_current_subject(
                    checkout,
                    authority_root=authority_root,
                    authority_uid=uid,
                    operator_uid=uid,
                )
            finally:
                checkout.rmdir()
                parked.rename(checkout)

            self.assertFalse(receipt.exists(), "swapped checkout inode preserved stale path-bound authority")
            with self.assertRaises(helper.AuthorityError):
                helper._verify_current_subject(
                    checkout,
                    operator_uid=uid,
                    expected_writer_sha256=writer_sha,
                    authority_root=authority_root,
                    authority_uid=uid,
                )

    def test_world_writable_authority_directory_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-private-authority-mode-") as temporary:
            helper, checkout, authority_root, uid, writer_sha, podspec_sha, identity_sha, _, _ = self.make_subject(temporary)
            authority_root.mkdir(mode=0o700)
            authority_root.chmod(0o777)
            with self.assertRaises(helper.AuthorityError):
                helper._seal_current_subject(
                    checkout,
                    operator_uid=uid,
                    expected_writer_sha256=writer_sha,
                    expected_podspec_sha256=podspec_sha,
                    expected_identity_sha256=identity_sha,
                    authority_root=authority_root,
                    authority_uid=uid,
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)

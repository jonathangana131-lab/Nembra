#!/usr/bin/env python3
"""Private staging failure paths must stay bound to exact held inode authority."""
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
    spec = importlib.util.spec_from_file_location("nembra_private_identity_recovery_inode_custody", WRITER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("private identity writer import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def install_replacement(writer, checkout_fd: int, stage_name: str, escaped_name: str, payload: bytes) -> None:
    writer.os.rename(stage_name, escaped_name, src_dir_fd=checkout_fd, dst_dir_fd=checkout_fd)
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
        writer.os.write(replacement_fd, payload)
        writer.os.fsync(replacement_fd)
    finally:
        writer.os.close(replacement_fd)


class PrivateIdentityRecoveryInodeCustodyTests(unittest.TestCase):
    def test_post_admission_name_swap_preserves_replacement_and_sanitizes_admitted_inode(self) -> None:
        writer = load_writer()
        admitted_payload = b"dummy-admitted-crash-residue"
        replacement_payload = b"attacker-replacement-must-survive"
        new_payload = b"new-private-output"

        with tempfile.TemporaryDirectory(prefix="nembra-private-recovery-inode-custody-") as temporary:
            checkout = Path(temporary) / "repo"
            destination_parent = checkout / "private"
            destination_parent.mkdir(parents=True, mode=0o700)
            stage_name = f"{PREFIX}{os.getpid()}-{'f' * 24}"
            escaped_name = "attacker-renamed-admitted-residue"
            stage = checkout / stage_name
            escaped = checkout / escaped_name
            destination = destination_parent / "identity.swift"
            stage.write_bytes(admitted_payload)
            stage.chmod(0o600)

            checkout_fd = os.open(checkout, writer._directory_flags())
            destination_fd = os.open(destination_parent, writer._directory_flags())
            recovered = None
            try:
                recovered = writer._recover_private_stage_residue(checkout_fd)
                self.assertIsNotNone(recovered, "fixture did not admit the writer-shaped crash residue")

                install_replacement(writer, checkout_fd, stage_name, escaped_name, replacement_payload)

                with self.assertRaises(writer.ProvisionError):
                    writer._write_staged(
                        checkout_fd,
                        destination_fd,
                        "identity.swift",
                        "private/identity.swift",
                        new_payload,
                        recovered_stage=recovered,
                    )
            finally:
                if recovered is not None:
                    recovered.close()
                os.close(destination_fd)
                os.close(checkout_fd)

            self.assertTrue(escaped.is_file(), "admitted inode disappeared after fail-closed name swap")
            self.assertEqual(
                escaped.read_bytes(),
                b"",
                "pre-rebind failure left credential-bearing bytes in the exact held admitted inode",
            )
            self.assertTrue(stage.is_file(), "recovery deleted the replacement pathname subject")
            self.assertEqual(stage.read_bytes(), replacement_payload)
            self.assertFalse(destination.exists(), "failed recovery published a private output")

    def test_early_existing_output_rejection_sanitizes_admitted_inode(self) -> None:
        writer = load_writer()
        admitted_payload = b"credential-bearing-crash-residue-must-not-survive-rejection"
        new_payload = b"new-private-output"

        with tempfile.TemporaryDirectory(prefix="nembra-private-preconsume-reject-") as temporary:
            checkout = Path(temporary) / "repo"
            destination_parent = checkout / "private"
            destination_parent.mkdir(parents=True, mode=0o700)
            stage_name = f"{PREFIX}{os.getpid()}-{'c' * 24}"
            stage = checkout / stage_name
            stage.write_bytes(admitted_payload)
            stage.chmod(0o600)

            destination = destination_parent / "identity.swift"
            destination.mkdir(mode=0o700)

            checkout_fd = os.open(checkout, writer._directory_flags())
            destination_fd = os.open(destination_parent, writer._directory_flags())
            recovered = None
            try:
                recovered = writer._recover_private_stage_residue(checkout_fd)
                self.assertIsNotNone(recovered, "fixture did not admit the writer-shaped crash residue")
                with self.assertRaises(writer.ProvisionError):
                    writer._write_staged(
                        checkout_fd,
                        destination_fd,
                        "identity.swift",
                        "private/identity.swift",
                        new_payload,
                        recovered_stage=recovered,
                    )
            finally:
                if recovered is not None:
                    recovered.close()
                os.close(destination_fd)
                os.close(checkout_fd)

            self.assertTrue(destination.is_dir(), "failure cleanup mutated the invalid attacker destination")
            self.assertTrue(stage.is_file(), "admitted residue disappeared instead of remaining under exact inode custody")
            self.assertEqual(
                stage.read_bytes(),
                b"",
                "early existing-output rejection left credential-bearing bytes in the exact admitted residue inode",
            )

    def test_name_swap_after_rebind_mutates_only_held_inode(self) -> None:
        writer = load_writer()
        admitted_payload = b"dummy-admitted-crash-residue-after-rebind"
        replacement_payload = b"late-replacement-must-survive"
        new_payload = b"new-private-output-after-rebind"

        with tempfile.TemporaryDirectory(prefix="nembra-private-recovery-late-swap-") as temporary:
            checkout = Path(temporary) / "repo"
            destination_parent = checkout / "private"
            destination_parent.mkdir(parents=True, mode=0o700)
            stage_name = f"{PREFIX}{os.getpid()}-{'e' * 24}"
            escaped_name = "attacker-late-renamed-admitted-residue"
            stage = checkout / stage_name
            escaped = checkout / escaped_name
            destination = destination_parent / "identity.swift"
            stage.write_bytes(admitted_payload)
            stage.chmod(0o600)

            checkout_fd = os.open(checkout, writer._directory_flags())
            destination_fd = os.open(destination_parent, writer._directory_flags())
            recovered = None
            real_ftruncate = writer.os.ftruncate
            attack_fired = False

            try:
                recovered = writer._recover_private_stage_residue(checkout_fd)
                self.assertIsNotNone(recovered, "fixture did not admit the writer-shaped crash residue")
                admitted_dev = recovered.metadata.st_dev
                admitted_ino = recovered.metadata.st_ino

                def interpose_after_rebind(descriptor: int, length: int) -> None:
                    nonlocal attack_fired
                    held = writer.os.fstat(descriptor)
                    if not attack_fired and held.st_dev == admitted_dev and held.st_ino == admitted_ino:
                        attack_fired = True
                        install_replacement(writer, checkout_fd, stage_name, escaped_name, replacement_payload)
                    real_ftruncate(descriptor, length)

                writer.os.ftruncate = interpose_after_rebind
                with self.assertRaises(writer.ProvisionError):
                    writer._write_staged(
                        checkout_fd,
                        destination_fd,
                        "identity.swift",
                        "private/identity.swift",
                        new_payload,
                        recovered_stage=recovered,
                    )
            finally:
                writer.os.ftruncate = real_ftruncate
                if recovered is not None:
                    recovered.close()
                os.close(destination_fd)
                os.close(checkout_fd)

            self.assertTrue(attack_fired, "fixture did not swap the recovered name after final re-bind")
            self.assertTrue(stage.is_file(), "late replacement pathname subject was deleted")
            self.assertEqual(stage.read_bytes(), replacement_payload)
            self.assertTrue(escaped.is_file(), "held admitted inode disappeared during late swap failure")
            self.assertEqual(
                escaped.read_bytes(),
                b"",
                "failure sanitation did not stay on the exact held inode after the late name swap",
            )
            self.assertFalse(destination.exists(), "late-swap failure published a private output")

    def test_post_publication_destination_swap_never_deletes_replacement(self) -> None:
        writer = load_writer()
        private_payload = b"dummy-private-output-for-publication-race"
        replacement_payload = b"canonical-destination-replacement-must-survive"

        with tempfile.TemporaryDirectory(prefix="nembra-private-publication-cleanup-authority-") as temporary:
            checkout = Path(temporary) / "repo"
            destination_parent = checkout / "private"
            destination_parent.mkdir(parents=True, mode=0o700)
            destination_relative = "private/identity.swift"
            destination = checkout / destination_relative
            escaped = checkout / "attacker-renamed-published-private-output"

            checkout_fd = os.open(checkout, writer._directory_flags())
            destination_fd = os.open(destination_parent, writer._directory_flags())
            real_secure_replace = writer._secure_replace_beneath
            attack_fired = False

            def publish_then_swap(
                root_fd: int,
                source_name: str,
                target_relative: str,
                sealed,
            ) -> None:
                nonlocal attack_fired
                real_secure_replace(root_fd, source_name, target_relative, sealed)
                attack_fired = True
                install_replacement(
                    writer,
                    root_fd,
                    target_relative,
                    escaped.name,
                    replacement_payload,
                )

            writer._secure_replace_beneath = publish_then_swap
            try:
                with self.assertRaises(writer.ProvisionError):
                    writer._write_staged(
                        checkout_fd,
                        destination_fd,
                        "identity.swift",
                        destination_relative,
                        private_payload,
                    )
            finally:
                writer._secure_replace_beneath = real_secure_replace
                os.close(destination_fd)
                os.close(checkout_fd)

            self.assertTrue(attack_fired, "fixture did not replace the canonical destination after publication")
            self.assertTrue(destination.is_file(), "failure cleanup deleted the replacement canonical destination")
            self.assertEqual(destination.read_bytes(), replacement_payload)
            self.assertTrue(escaped.is_file(), "accepted staging inode disappeared after destination replacement")
            self.assertEqual(
                escaped.read_bytes(),
                b"",
                "failed publication did not sanitize only the exact held private staging inode",
            )

    def test_recovery_source_never_pathname_unlinks_admitted_residue(self) -> None:
        source = WRITER_PATH.read_text(encoding="utf-8")
        start = source.index("def _recover_private_stage_residue")
        end = source.index("def _ensure_private_directory", start)
        recovery = source[start:end]
        self.assertNotIn("os.unlink(", recovery)
        self.assertIn("return recovered", recovery)
        self.assertIn("_RecoveredPrivateStage", recovery)

        write_start = source.index("def _write_staged(")
        write_end = source.index("def _decode_input", write_start)
        write_staged = source[write_start:write_end]
        self.assertNotIn("_unlink_owned_inode_if_named", write_staged)
        self.assertNotIn("_unlink_owned_relative_inode_if_named", write_staged)
        self.assertIn("_sanitize_held_private_descriptor", write_staged)
        self.assertNotIn("def _unlink_owned_inode_if_named", source)
        self.assertNotIn("def _unlink_owned_relative_inode_if_named", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)

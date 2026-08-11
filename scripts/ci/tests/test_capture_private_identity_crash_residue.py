#!/usr/bin/env python3
"""Adversarial crash-recovery tests for private Tuya identity staging residue.

A hard process exit does not execute Python ``except``/``finally`` cleanup. The
first regression kills the writer exactly when its credential-bearing
LocalSecrets stage has already been written, chmod'd and fsync'd but before
publication. The next writer invocation must not silently proceed while those
hidden ``.nembra-private-stage-*`` bytes remain behind.

Recovery itself is also an authority boundary. A same-UID adversary can create
entries under the reserved ignored prefix. A safe recovery may neutralize only a
narrow exact writer-shaped crash artifact; it must fail closed on ambiguous or
unsafe reserved entries without following aliases, widening mutation authority,
or recursively deleting attacker-controlled content.

These tests use only dummy payloads and define logical retained-byte handling;
they make no claim of secure physical-media erasure.
"""

from __future__ import annotations

import base64
import importlib.util
import os
from pathlib import Path
import stat
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
WRITER_PATH = REPOSITORY / "Scripts" / "provision_capture_tuya_identity_writer.py"
CRASH_EXIT = 73
RESERVED_PREFIX = ".nembra-private-stage-"


def load_writer():
    spec = importlib.util.spec_from_file_location("nembra_private_identity_writer_crash_redteam", WRITER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("private identity writer import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def staging_root(checkout: Path) -> Path:
    root = checkout / "LocalSecrets"
    root.mkdir(mode=0o700, exist_ok=True)
    root.chmod(0o700)
    return root


def run_recovery_invocation(writer, checkout: Path) -> bool:
    """Run the next writer invocation; return True only for a fail-closed result."""
    checkout_fd = os.open(checkout, writer._directory_flags())
    try:
        key_b64 = base64.b64encode(b"dummy-recovery-key").decode("ascii")
        secret_b64 = base64.b64encode(b"dummy-recovery-secret").decode("ascii")
        try:
            writer.provision(checkout_fd, checkout, key_b64, secret_b64)
        except (writer.ProvisionError, OSError):
            return True
        return False
    finally:
        os.close(checkout_fd)


def path_entry_exists(path: Path) -> bool:
    """Like lexists(2): true even for a dangling symlink."""
    return os.path.lexists(os.fspath(path))


def canonical_spoof_name(nibble: str) -> str:
    """Produce an attacker-controlled name that passes the writer's reserved-name grammar."""
    if len(nibble) != 1 or nibble not in "0123456789abcdef":
        raise ValueError("spoof nibble must be one lowercase hex character")
    return f"{RESERVED_PREFIX}{os.getpid()}-{nibble * 24}"


class PrivateIdentityCrashResidueTests(unittest.TestCase):
    def test_next_invocation_cannot_leave_hard_exit_stage_credentials_hidden(self) -> None:
        writer = load_writer()
        crashed_payload = b"dummy-crash-residue-private-identity"

        with tempfile.TemporaryDirectory(prefix="nembra-private-crash-residue-") as temporary:
            checkout = Path(temporary) / "repo"
            checkout.mkdir(mode=0o700)
            local_secrets = staging_root(checkout)
            destination_parent = checkout / "private"
            destination_parent.mkdir(parents=True, mode=0o700)

            pid = os.fork()
            if pid == 0:
                checkout_fd = local_secrets_fd = destination_parent_fd = -1
                try:
                    child_writer = load_writer()
                    checkout_fd = os.open(checkout, child_writer._directory_flags())
                    local_secrets_fd = os.open(local_secrets, child_writer._directory_flags())
                    destination_parent_fd = os.open(destination_parent, child_writer._directory_flags())

                    def hard_exit_after_seal(_root_fd: int, _src: str, _dst: str, _sealed) -> None:
                        # _write_staged reaches this seam only after the stage has
                        # been fully written, chmod'd to 0600 and fsync'd.
                        os._exit(CRASH_EXIT)

                    child_writer._secure_replace_beneath = hard_exit_after_seal
                    child_writer._write_staged(
                        checkout_fd,
                        destination_parent_fd,
                        "identity.swift",
                        "private/identity.swift",
                        crashed_payload,
                        staging_parent_fd=local_secrets_fd,
                    )
                    os._exit(74)
                except BaseException:
                    os._exit(75)
                finally:
                    # os._exit() intentionally bypasses this path in the attack.
                    if destination_parent_fd >= 0:
                        os.close(destination_parent_fd)
                    if local_secrets_fd >= 0:
                        os.close(local_secrets_fd)
                    if checkout_fd >= 0:
                        os.close(checkout_fd)

            waited, status = os.waitpid(pid, 0)
            self.assertEqual(waited, pid)
            self.assertTrue(os.WIFEXITED(status), "crash fixture did not exit deterministically")
            self.assertEqual(
                os.WEXITSTATUS(status),
                CRASH_EXIT,
                "crash fixture did not reach the post-fsync/pre-publication seam",
            )

            self.assertEqual(
                sorted(checkout.glob(f"{RESERVED_PREFIX}*")),
                [],
                "production staging escaped LocalSecrets into the raw checkout root",
            )
            orphaned = sorted(local_secrets.glob(f"{RESERVED_PREFIX}*"))
            self.assertEqual(len(orphaned), 1, "fixture did not reproduce one writer-owned crash residue stage")
            orphan = orphaned[0]
            orphan_metadata = orphan.lstat()
            self.assertTrue(stat.S_ISREG(orphan_metadata.st_mode))
            self.assertEqual(orphan_metadata.st_uid, os.geteuid())
            self.assertEqual(stat.S_IMODE(orphan_metadata.st_mode), 0o600)
            self.assertEqual(orphan.read_bytes(), crashed_payload)

            # A later writer invocation is the first deterministic recovery
            # opportunity after SIGKILL/power-loss. It may recover or fail
            # closed, but it must not leave the prior known writer-shaped
            # credential bytes hidden in LocalSecrets.
            run_recovery_invocation(writer, checkout)

            self.assertEqual(
                sorted(checkout.glob(f"{RESERVED_PREFIX}*")),
                [],
                "recovery introduced a raw-root staging subject outside LocalSecrets",
            )
            residual_entries = sorted(local_secrets.glob(f"{RESERVED_PREFIX}*"))
            residual_payloads = []
            for candidate in residual_entries:
                try:
                    if candidate.is_file() and not candidate.is_symlink():
                        residual_payloads.append(candidate.read_bytes())
                except OSError:
                    pass

            self.assertNotIn(
                crashed_payload,
                residual_payloads,
                "recovery left credential-bearing hard-exit staging bytes inside LocalSecrets",
            )
            # A same-UID actor can swap a pathname after identity admission and
            # before unlink, so recovery does not claim race-free exact-inode
            # deletion. It may retain only inert zero-length canonical tombstones
            # inside the authenticated LocalSecrets field-input root.
            for candidate in residual_entries:
                metadata = candidate.lstat()
                self.assertTrue(stat.S_ISREG(metadata.st_mode))
                self.assertEqual(metadata.st_uid, os.geteuid())
                self.assertEqual(metadata.st_nlink, 1)
                self.assertEqual(stat.S_IMODE(metadata.st_mode), 0o600)
                self.assertEqual(metadata.st_size, 0)
                self.assertEqual(candidate.read_bytes(), b"")

    def test_recovery_cannot_follow_or_silently_ignore_reserved_symlink(self) -> None:
        writer = load_writer()
        victim_payload = b"unrelated-symlink-target-must-survive"

        with tempfile.TemporaryDirectory(prefix="nembra-private-symlink-orphan-") as temporary:
            checkout = Path(temporary) / "repo"
            checkout.mkdir(mode=0o700)
            stage_root = staging_root(checkout)
            victim = checkout / "unrelated.txt"
            victim.write_bytes(victim_payload)
            stage = stage_root / canonical_spoof_name("a")
            stage.symlink_to(victim)

            failed_closed = run_recovery_invocation(writer, checkout)

            self.assertEqual(
                victim.read_bytes(),
                victim_payload,
                "reserved-stage recovery followed a symlink and modified unrelated bytes",
            )
            if not failed_closed:
                self.assertFalse(
                    path_entry_exists(stage),
                    "successful recovery silently ignored a reserved symlink staging entry",
                )

    def test_recovery_cannot_truncate_or_silently_ignore_reserved_hardlink(self) -> None:
        writer = load_writer()
        victim_payload = b"unrelated-hardlink-target-must-survive"

        with tempfile.TemporaryDirectory(prefix="nembra-private-hardlink-orphan-") as temporary:
            checkout = Path(temporary) / "repo"
            checkout.mkdir(mode=0o700)
            stage_root = staging_root(checkout)
            victim = checkout / "unrelated.txt"
            victim.write_bytes(victim_payload)
            stage = stage_root / canonical_spoof_name("b")
            os.link(victim, stage)
            self.assertGreaterEqual(victim.stat().st_nlink, 2)

            failed_closed = run_recovery_invocation(writer, checkout)

            self.assertEqual(
                victim.read_bytes(),
                victim_payload,
                "reserved-stage recovery truncated an unrelated hard-linked file",
            )
            if not failed_closed:
                self.assertFalse(
                    path_entry_exists(stage),
                    "successful recovery silently ignored a reserved hard-link staging entry",
                )

    def test_recovery_must_fail_closed_on_reserved_nonempty_directory(self) -> None:
        writer = load_writer()

        with tempfile.TemporaryDirectory(prefix="nembra-private-directory-orphan-") as temporary:
            checkout = Path(temporary) / "repo"
            checkout.mkdir(mode=0o700)
            stage_root = staging_root(checkout)
            stage = stage_root / canonical_spoof_name("c")
            stage.mkdir(mode=0o700)
            marker = stage / "do-not-delete.txt"
            marker_payload = b"attacker-controlled-directory-content"
            marker.write_bytes(marker_payload)

            failed_closed = run_recovery_invocation(writer, checkout)

            self.assertTrue(
                failed_closed,
                "writer silently proceeded while a nonempty reserved staging directory remained unresolved",
            )
            self.assertTrue(marker.is_file(), "recovery recursively deleted attacker-controlled reserved directory content")
            self.assertEqual(marker.read_bytes(), marker_payload)

    def test_recovery_must_not_delete_malformed_reserved_regular_file(self) -> None:
        writer = load_writer()
        payload = b"same-uid-malformed-reserved-entry-must-survive"

        with tempfile.TemporaryDirectory(prefix="nembra-private-malformed-orphan-") as temporary:
            checkout = Path(temporary) / "repo"
            checkout.mkdir(mode=0o700)
            stage_root = staging_root(checkout)
            stage = stage_root / f"{RESERVED_PREFIX}not-a-writer-name"
            stage.write_bytes(payload)
            stage.chmod(0o600)

            failed_closed = run_recovery_invocation(writer, checkout)

            self.assertTrue(failed_closed, "writer accepted a malformed reserved staging name")
            self.assertTrue(stage.is_file(), "recovery deleted a malformed same-UID reserved regular file")
            self.assertEqual(stage.read_bytes(), payload)

    def test_recovery_must_not_delete_wrong_mode_reserved_regular_file(self) -> None:
        writer = load_writer()
        payload = b"same-uid-wrong-mode-reserved-entry-must-survive"

        with tempfile.TemporaryDirectory(prefix="nembra-private-wrong-mode-orphan-") as temporary:
            checkout = Path(temporary) / "repo"
            checkout.mkdir(mode=0o700)
            stage_root = staging_root(checkout)
            stage = stage_root / canonical_spoof_name("d")
            stage.write_bytes(payload)
            stage.chmod(0o640)

            failed_closed = run_recovery_invocation(writer, checkout)

            self.assertTrue(failed_closed, "writer accepted reserved crash residue that was not mode 0600")
            self.assertTrue(stage.is_file(), "recovery deleted a wrong-mode same-UID reserved regular file")
            self.assertEqual(stage.read_bytes(), payload)
            self.assertEqual(stat.S_IMODE(stage.stat().st_mode), 0o640)

    def test_recovery_must_not_delete_oversized_reserved_regular_file(self) -> None:
        writer = load_writer()

        with tempfile.TemporaryDirectory(prefix="nembra-private-oversized-orphan-") as temporary:
            checkout = Path(temporary) / "repo"
            checkout.mkdir(mode=0o700)
            stage_root = staging_root(checkout)
            stage = stage_root / canonical_spoof_name("e")
            oversized_length = writer._PRIVATE_STAGE_MAX_BYTES + 1
            with stage.open("wb") as handle:
                handle.truncate(oversized_length)
            stage.chmod(0o600)

            failed_closed = run_recovery_invocation(writer, checkout)

            self.assertTrue(failed_closed, "writer accepted oversized reserved crash residue")
            self.assertTrue(stage.is_file(), "recovery deleted an oversized same-UID reserved regular file")
            self.assertEqual(stage.stat().st_size, oversized_length)


_CASES = {
    "hard-exit": "test_next_invocation_cannot_leave_hard_exit_stage_credentials_hidden",
    "symlink": "test_recovery_cannot_follow_or_silently_ignore_reserved_symlink",
    "hardlink": "test_recovery_cannot_truncate_or_silently_ignore_reserved_hardlink",
    "directory": "test_recovery_must_fail_closed_on_reserved_nonempty_directory",
    "malformed-name": "test_recovery_must_not_delete_malformed_reserved_regular_file",
    "wrong-mode": "test_recovery_must_not_delete_wrong_mode_reserved_regular_file",
    "oversized": "test_recovery_must_not_delete_oversized_reserved_regular_file",
}


if __name__ == "__main__":
    selected = os.environ.get("NEMBRA_CRASH_RESIDUE_CASE")
    if selected:
        method = _CASES.get(selected)
        if method is None:
            raise SystemExit(f"unknown crash-residue case: {selected}")
        suite = unittest.TestSuite([PrivateIdentityCrashResidueTests(method)])
        result = unittest.TextTestRunner(verbosity=2).run(suite)
        raise SystemExit(0 if result.wasSuccessful() else 1)
    unittest.main(verbosity=2)
#!/usr/bin/env python3
"""Adversarial crash-recovery tests for private Tuya identity staging residue.

A hard process exit does not execute Python ``except``/``finally`` cleanup. The
first regression kills the writer exactly when its credential-bearing
checkout-root stage has already been written, chmod'd and fsync'd but before
publication. The next writer invocation must not silently proceed while those
hidden ``.nembra-private-stage-*`` bytes remain behind.

Recovery itself is also an authority boundary. A same-UID adversary can create
entries under the reserved ignored prefix. A safe recovery may remove a
reserved non-directory path or fail closed, but it must not silently accept an
unresolved reserved entry, follow a symlink, truncate a hard-linked unrelated
file, or recursively delete an attacker-controlled directory tree.

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


class PrivateIdentityCrashResidueTests(unittest.TestCase):
    def test_next_invocation_cannot_leave_hard_exit_stage_credentials_hidden(self) -> None:
        writer = load_writer()
        crashed_payload = b"dummy-crash-residue-private-identity"

        with tempfile.TemporaryDirectory(prefix="nembra-private-crash-residue-") as temporary:
            checkout = Path(temporary) / "repo"
            destination_parent = checkout / "private"
            destination_parent.mkdir(parents=True, mode=0o700)

            pid = os.fork()
            if pid == 0:
                checkout_fd = destination_parent_fd = -1
                try:
                    child_writer = load_writer()
                    checkout_fd = os.open(checkout, child_writer._directory_flags())
                    destination_parent_fd = os.open(destination_parent, child_writer._directory_flags())

                    def hard_exit_after_seal(_root_fd: int, _src: str, _dst: str) -> None:
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
                    )
                    os._exit(74)
                except BaseException:
                    os._exit(75)
                finally:
                    # os._exit() intentionally bypasses this path in the attack.
                    if destination_parent_fd >= 0:
                        os.close(destination_parent_fd)
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

            orphaned = sorted(checkout.glob(f"{RESERVED_PREFIX}*"))
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
            # credential bytes hidden under the ignored reserved prefix.
            run_recovery_invocation(writer, checkout)

            residual_entries = sorted(checkout.glob(f"{RESERVED_PREFIX}*"))
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
                "recovery left credential-bearing hard-exit staging bytes hidden under the ignored root pattern",
            )
            self.assertEqual(
                residual_entries,
                [],
                "recovery left writer-owned .nembra-private-stage-* crash residue in the checkout root",
            )

    def test_recovery_cannot_follow_or_silently_ignore_reserved_symlink(self) -> None:
        writer = load_writer()
        victim_payload = b"unrelated-symlink-target-must-survive"

        with tempfile.TemporaryDirectory(prefix="nembra-private-symlink-orphan-") as temporary:
            checkout = Path(temporary) / "repo"
            checkout.mkdir(mode=0o700)
            victim = checkout / "unrelated.txt"
            victim.write_bytes(victim_payload)
            stage = checkout / f"{RESERVED_PREFIX}attacker-symlink"
            stage.symlink_to(victim.name)

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
            victim = checkout / "unrelated.txt"
            victim.write_bytes(victim_payload)
            stage = checkout / f"{RESERVED_PREFIX}attacker-hardlink"
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
            stage = checkout / f"{RESERVED_PREFIX}attacker-directory"
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


_CASES = {
    "hard-exit": "test_next_invocation_cannot_leave_hard_exit_stage_credentials_hidden",
    "symlink": "test_recovery_cannot_follow_or_silently_ignore_reserved_symlink",
    "hardlink": "test_recovery_cannot_truncate_or_silently_ignore_reserved_hardlink",
    "directory": "test_recovery_must_fail_closed_on_reserved_nonempty_directory",
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

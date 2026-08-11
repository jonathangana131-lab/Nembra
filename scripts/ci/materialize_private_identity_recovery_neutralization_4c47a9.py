#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import hashlib
import re

WRITER = Path("Scripts/provision_capture_tuya_identity_writer.py")
SHELL = Path("Scripts/provision_capture_tuya_identity.sh")
CRASH_TEST = Path("scripts/ci/tests/test_capture_private_identity_crash_residue.py")
RACE_TEST = Path("scripts/ci/tests/test_capture_private_identity_recovery_neutralization.py")
WORKFLOW = Path(".github/workflows/capture-private-identity-publication-races-redteam.yml")
ONE_SHOT = Path(".github/workflows/one-shot-private-identity-recovery-neutralization-4c47a9.yml")
SELF = Path("scripts/ci/materialize_private_identity_recovery_neutralization_4c47a9.py")

RECOVERY = '''def _recover_private_stage_residue(checkout_fd: int) -> None:
    """Neutralize exact writer-shaped crash residue without pathname deletion authority.

    The checkout is writable by the same UID as this process, so a pathname can be
    renamed/replaced between an identity check and unlink(2). Recovery therefore never
    deletes a reserved staging pathname. Credential-bearing bytes are truncated through
    the already-admitted file descriptor, fsync'd, and then the name is re-bound to that
    exact neutralized inode. Zero-length canonical 0600 entries are inert tombstones and
    may remain; they contain no logical credential bytes.
    """
    try:
        entries = os.listdir(checkout_fd)
    except OSError as exc:
        raise ProvisionError("could not inspect private identity staging namespace") from exc

    reserved = sorted(name for name in entries if name.startswith(_PRIVATE_STAGE_PREFIX))
    for name in reserved:
        if not _is_canonical_private_stage_name(name):
            raise ProvisionError("reserved private identity staging namespace contains a non-writer entry")

        try:
            named = os.stat(name, dir_fd=checkout_fd, follow_symlinks=False)
        except FileNotFoundError:
            continue
        except OSError as exc:
            raise ProvisionError("could not inspect reserved private identity staging entry") from exc

        if (
            not stat.S_ISREG(named.st_mode)
            or named.st_uid != os.geteuid()
            or named.st_nlink != 1
            or stat.S_IMODE(named.st_mode) != 0o600
            or named.st_size > _PRIVATE_STAGE_MAX_BYTES
        ):
            raise ProvisionError("reserved private identity staging entry is not safe writer-owned crash residue")

        # A previously neutralized zero-length tombstone contains no logical
        # credential bytes. Leave it named rather than reacquiring raceable
        # pathname-deletion authority.
        if named.st_size == 0:
            continue

        descriptor = -1
        try:
            descriptor = os.open(
                name,
                os.O_RDWR | os.O_CLOEXEC | os.O_NOFOLLOW,
                dir_fd=checkout_fd,
            )
            held = os.fstat(descriptor)
            current = os.stat(name, dir_fd=checkout_fd, follow_symlinks=False)
            if (
                not stat.S_ISREG(held.st_mode)
                or held.st_uid != os.geteuid()
                or held.st_nlink != 1
                or stat.S_IMODE(held.st_mode) != 0o600
                or held.st_size <= 0
                or held.st_size > _PRIVATE_STAGE_MAX_BYTES
                or current.st_dev != held.st_dev
                or current.st_ino != held.st_ino
                or current.st_uid != held.st_uid
                or current.st_nlink != held.st_nlink
                or current.st_mode != held.st_mode
                or current.st_size != held.st_size
            ):
                raise ProvisionError("reserved private identity staging entry changed during recovery admission")

            # Descriptor-bound truncation targets the admitted inode even if a
            # concurrent same-UID actor renames it and installs a replacement at
            # the old reserved pathname. This is logical byte neutralization only;
            # it intentionally makes no physical-media secure-erasure claim.
            os.ftruncate(descriptor, 0)
            os.fsync(descriptor)
            neutralized = os.fstat(descriptor)
            if (
                neutralized.st_dev != held.st_dev
                or neutralized.st_ino != held.st_ino
                or neutralized.st_uid != held.st_uid
                or neutralized.st_nlink != held.st_nlink
                or neutralized.st_mode != held.st_mode
                or neutralized.st_size != 0
            ):
                raise ProvisionError("private identity crash residue failed exact-inode neutralization")

            try:
                rebound = os.stat(name, dir_fd=checkout_fd, follow_symlinks=False)
            except OSError as exc:
                raise ProvisionError("reserved private identity staging name changed during recovery neutralization") from exc
            if (
                rebound.st_dev != neutralized.st_dev
                or rebound.st_ino != neutralized.st_ino
                or rebound.st_uid != neutralized.st_uid
                or rebound.st_nlink != neutralized.st_nlink
                or rebound.st_mode != neutralized.st_mode
                or rebound.st_size != 0
            ):
                raise ProvisionError("reserved private identity staging name changed during recovery neutralization")
        except ProvisionError:
            raise
        except OSError as exc:
            raise ProvisionError("could not safely neutralize writer-owned private identity crash residue") from exc
        finally:
            if descriptor >= 0:
                os.close(descriptor)

    # A successful recovery may retain only inert canonical tombstones. Re-scan
    # from the admitted root so malformed, swapped, or newly credential-bearing
    # reserved entries still fail closed before provisioning continues.
    try:
        leftovers = sorted(
            name for name in os.listdir(checkout_fd) if name.startswith(_PRIVATE_STAGE_PREFIX)
        )
    except OSError as exc:
        raise ProvisionError("could not re-inspect private identity staging namespace") from exc
    for name in leftovers:
        if not _is_canonical_private_stage_name(name):
            raise ProvisionError("private identity staging namespace contains a non-writer entry after recovery")
        try:
            metadata = os.stat(name, dir_fd=checkout_fd, follow_symlinks=False)
        except OSError as exc:
            raise ProvisionError("could not verify private identity recovery tombstone") from exc
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_uid != os.geteuid()
            or metadata.st_nlink != 1
            or stat.S_IMODE(metadata.st_mode) != 0o600
            or metadata.st_size != 0
        ):
            raise ProvisionError("private identity staging namespace is not credential-neutral after recovery")

'''

RACE_TEST_TEXT = r'''#!/usr/bin/env python3
"""Crash-residue recovery must neutralize only the held inode under a name swap.

Production successor to expected-red #2918. The attacker swaps the admitted
residue at the exact descriptor-neutralization boundary. Recovery must truncate
the already-held inode, never the replacement pathname subject, then fail closed
because the canonical name no longer binds the neutralized inode.
Dummy bytes only; this is logical byte handling, not secure-media erasure.
"""
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
    spec = importlib.util.spec_from_file_location("nembra_private_identity_recovery_neutralization", WRITER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("private identity writer import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PrivateIdentityRecoveryNeutralizationTests(unittest.TestCase):
    def test_name_swap_at_neutralization_preserves_replacement_and_zeros_held_inode(self) -> None:
        writer = load_writer()
        admitted_payload = b"dummy-admitted-crash-residue"
        replacement_payload = b"attacker-replacement-must-survive"

        with tempfile.TemporaryDirectory(prefix="nembra-private-recovery-neutralization-") as temporary:
            checkout = Path(temporary) / "repo"
            checkout.mkdir(mode=0o700)
            stage_name = f"{PREFIX}{os.getpid()}-{'f' * 24}"
            escaped_name = "attacker-renamed-admitted-residue"
            stage = checkout / stage_name
            escaped = checkout / escaped_name
            stage.write_bytes(admitted_payload)
            stage.chmod(0o600)

            checkout_fd = os.open(checkout, writer._directory_flags())
            real_ftruncate = writer.os.ftruncate
            attack_fired = False

            def interpose_at_neutralization(descriptor: int, length: int) -> None:
                nonlocal attack_fired
                if length == 0 and not attack_fired:
                    attack_fired = True
                    writer.os.rename(
                        stage_name,
                        escaped_name,
                        src_dir_fd=checkout_fd,
                        dst_dir_fd=checkout_fd,
                    )
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
                        writer.os.fchmod(replacement_fd, 0o600)
                        writer.os.write(replacement_fd, replacement_payload)
                        writer.os.fsync(replacement_fd)
                    finally:
                        writer.os.close(replacement_fd)
                real_ftruncate(descriptor, length)

            writer.os.ftruncate = interpose_at_neutralization
            try:
                with self.assertRaises(
                    writer.ProvisionError,
                    msg="recovery accepted a name swap at the credential-neutralization boundary",
                ):
                    writer._recover_private_stage_residue(checkout_fd)
            finally:
                writer.os.ftruncate = real_ftruncate
                os.close(checkout_fd)

            self.assertTrue(attack_fired, "fixture did not interpose at descriptor neutralization")
            self.assertTrue(escaped.is_file(), "fixture lost the originally admitted held residue")
            self.assertEqual(
                escaped.read_bytes(),
                b"",
                "recovery failed to neutralize credential bytes through the admitted descriptor",
            )
            self.assertTrue(
                stage.is_file(),
                "recovery deleted the replacement pathname subject outside held-inode authority",
            )
            self.assertEqual(
                stage.read_bytes(),
                replacement_payload,
                "recovery modified the replacement pathname subject outside held-inode authority",
            )

    def test_zero_length_canonical_tombstone_is_inert_and_needs_no_unlink(self) -> None:
        writer = load_writer()
        with tempfile.TemporaryDirectory(prefix="nembra-private-recovery-tombstone-") as temporary:
            checkout = Path(temporary) / "repo"
            checkout.mkdir(mode=0o700)
            stage = checkout / f"{PREFIX}{os.getpid()}-{'e' * 24}"
            stage.write_bytes(b"")
            stage.chmod(0o600)
            checkout_fd = os.open(checkout, writer._directory_flags())
            try:
                writer._recover_private_stage_residue(checkout_fd)
            finally:
                os.close(checkout_fd)
            self.assertTrue(stage.is_file())
            self.assertEqual(stage.read_bytes(), b"")


if __name__ == "__main__":
    unittest.main(verbosity=2)
'''

FINAL_WORKFLOW = '''name: Capture Private Identity Publication Races Red Team

on:
  push:
    branches:
      - adversarial/v14-private-identity-publication-races-sol
    paths:
      - Scripts/provision_capture_tuya_identity_writer.py
      - scripts/ci/tests/test_capture_private_identity_publication_races.py
      - scripts/ci/tests/test_capture_private_identity_same_inode_payload_current.py
      - scripts/ci/tests/test_capture_private_identity_destination_ancestor_swap_current.py
      - scripts/ci/tests/test_capture_private_identity_crash_residue.py
      - scripts/ci/tests/test_capture_private_identity_recovery_neutralization.py
      - scripts/ci/tests/test_capture_private_identity_final_name_binding_2874.py
      - .github/workflows/capture-private-identity-publication-races-redteam.yml
  pull_request:
    paths:
      - Scripts/provision_capture_tuya_identity_writer.py
      - scripts/ci/tests/test_capture_private_identity_publication_races.py
      - scripts/ci/tests/test_capture_private_identity_same_inode_payload_current.py
      - scripts/ci/tests/test_capture_private_identity_destination_ancestor_swap_current.py
      - scripts/ci/tests/test_capture_private_identity_crash_residue.py
      - scripts/ci/tests/test_capture_private_identity_recovery_neutralization.py
      - scripts/ci/tests/test_capture_private_identity_final_name_binding_2874.py
      - .github/workflows/capture-private-identity-publication-races-redteam.yml
  workflow_dispatch:

permissions:
  contents: read

jobs:
  publication-custody:
    name: Reject staging substitution, detached ancestry, crash residue, and final-name swaps
    if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha || github.sha }}

      - name: Bind diagnostic to exact checked-out head
        shell: bash
        env:
          EXPECTED_HEAD_SHA: ${{ github.event.pull_request.head.sha || github.sha }}
        run: |
          set -euo pipefail
          test "$(git rev-parse HEAD)" = "$EXPECTED_HEAD_SHA"
          test -z "$(git status --porcelain=v1 --untracked-files=all)"

      - name: Compile adversarial diagnostic
        shell: bash
        run: |
          set -euo pipefail
          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_private_identity_publication_races.py
          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_private_identity_same_inode_payload_current.py
          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_private_identity_destination_ancestor_swap_current.py
          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_private_identity_crash_residue.py
          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_private_identity_recovery_neutralization.py
          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_private_identity_final_name_binding_2874.py
          /usr/bin/python3 -m py_compile Scripts/provision_capture_tuya_identity_writer.py

      - name: Reject publication races and hard-exit residue
        shell: bash
        run: |
          set -euo pipefail
          /usr/bin/python3 -I scripts/ci/tests/test_capture_private_identity_publication_races.py
          /usr/bin/python3 -I scripts/ci/tests/test_capture_private_identity_same_inode_payload_current.py
          /usr/bin/python3 -I scripts/ci/tests/test_capture_private_identity_destination_ancestor_swap_current.py
          /usr/bin/python3 -I scripts/ci/tests/test_capture_private_identity_crash_residue.py
          /usr/bin/python3 -I scripts/ci/tests/test_capture_private_identity_recovery_neutralization.py
          /usr/bin/python3 -I scripts/ci/tests/test_capture_private_identity_final_name_binding_2874.py
'''


def main() -> None:
    writer = WRITER.read_text()
    writer, count = re.subn(
        r"def _recover_private_stage_residue\(checkout_fd: int\) -> None:\n.*?\n(?=def _ensure_private_directory)",
        RECOVERY,
        writer,
        count=1,
        flags=re.S,
    )
    if count != 1:
        raise SystemExit(f"expected one recovery block, replaced {count}")
    WRITER.write_text(writer)

    crash = CRASH_TEST.read_text()
    old = '''            self.assertEqual(
                residual_entries,
                [],
                "recovery left writer-owned .nembra-private-stage-* crash residue in the checkout root",
            )
'''
    new = '''            # Same-UID pathname interposition means exact-inode deletion cannot be
            # granted safely after a crash. Recovery may retain a zero-length inert
            # tombstone, but no prior credential bytes may remain logically readable.
            for candidate in residual_entries:
                metadata = candidate.lstat()
                self.assertTrue(stat.S_ISREG(metadata.st_mode))
                self.assertEqual(metadata.st_uid, os.geteuid())
                self.assertEqual(metadata.st_nlink, 1)
                self.assertEqual(stat.S_IMODE(metadata.st_mode), 0o600)
                self.assertEqual(metadata.st_size, 0)
                self.assertEqual(candidate.read_bytes(), b"")
'''
    if old not in crash:
        raise SystemExit("hard-exit residual assertion contract not found")
    CRASH_TEST.write_text(crash.replace(old, new, 1))
    RACE_TEST.write_text(RACE_TEST_TEXT)
    WORKFLOW.write_text(FINAL_WORKFLOW)

    shell = SHELL.read_text()
    digest = hashlib.sha256(WRITER.read_bytes()).hexdigest()
    shell, count = re.subn(
        r'WRITER_SHA256="[0-9a-f]{64}"',
        f'WRITER_SHA256="{digest}"',
        shell,
        count=1,
    )
    if count != 1:
        raise SystemExit(f"expected one writer digest pin, replaced {count}")
    SHELL.write_text(shell)

    if ONE_SHOT.exists():
        ONE_SHOT.unlink()
    SELF.unlink()


if __name__ == "__main__":
    main()

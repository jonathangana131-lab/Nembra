#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
WRITER = ROOT / "Scripts/provision_capture_tuya_identity_writer.py"
SHELL = ROOT / "Scripts/provision_capture_tuya_identity.sh"
PACKAGE_TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateIdentityProvisionerCustodyTests.swift"
CRASH_TEST = ROOT / "scripts/ci/tests/test_capture_private_identity_crash_residue.py"
RACE_TEST = ROOT / "scripts/ci/tests/test_capture_private_identity_recovery_unlink_race.py"
WORKFLOW = ROOT / ".github/workflows/capture-private-identity-publication-races-redteam.yml"

NEW_RECOVERY = r'''def _recover_private_stage_residue(checkout_fd: int) -> None:
    """Logically sanitize exact admitted crash residue; never unlink by mutable name.

    POSIX does not provide an atomic compare-and-unlink primitive that can say
    "remove this pathname only if it still names this already-open inode". A
    same-UID actor can therefore replace a name between any user-space identity
    check and pathname unlink. Recovery deliberately performs the destructive
    operation only through the already-admitted descriptor: credential bytes
    are truncated from that exact inode and fsynced. The zero-length tombstone
    is left in place and provisioning fails closed so an operator can remove it
    in a quiescent trusted context. This is logical retained-byte cleanup only;
    it is not a claim of secure physical-media erasure.
    """
    try:
        entries = os.listdir(checkout_fd)
    except OSError as exc:
        raise ProvisionError("could not inspect private identity staging namespace") from exc

    reserved = sorted(name for name in entries if name.startswith(_PRIVATE_STAGE_PREFIX))
    sanitized: list[str] = []
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
                or held.st_size > _PRIVATE_STAGE_MAX_BYTES
                or current.st_dev != held.st_dev
                or current.st_ino != held.st_ino
                or current.st_uid != held.st_uid
                or current.st_nlink != held.st_nlink
                or current.st_mode != held.st_mode
                or current.st_size != held.st_size
            ):
                raise ProvisionError("reserved private identity staging entry changed during recovery admission")

            os.ftruncate(descriptor, 0)
            os.fsync(descriptor)
            after_sanitize = os.fstat(descriptor)
            if (
                not stat.S_ISREG(after_sanitize.st_mode)
                or after_sanitize.st_uid != held.st_uid
                or stat.S_IMODE(after_sanitize.st_mode) != 0o600
                or after_sanitize.st_dev != held.st_dev
                or after_sanitize.st_ino != held.st_ino
                or after_sanitize.st_nlink < 1
                or after_sanitize.st_size != 0
            ):
                raise ProvisionError("private identity staging descriptor changed during recovery sanitization")

            try:
                rebound = os.stat(name, dir_fd=checkout_fd, follow_symlinks=False)
            except OSError as exc:
                raise ProvisionError("private identity staging name changed during recovery sanitization") from exc
            if (
                not stat.S_ISREG(rebound.st_mode)
                or rebound.st_uid != after_sanitize.st_uid
                or rebound.st_nlink != after_sanitize.st_nlink
                or stat.S_IMODE(rebound.st_mode) != 0o600
                or rebound.st_dev != after_sanitize.st_dev
                or rebound.st_ino != after_sanitize.st_ino
                or rebound.st_size != 0
            ):
                raise ProvisionError("private identity staging name changed during recovery sanitization")
            os.fsync(checkout_fd)
            sanitized.append(name)
        except ProvisionError:
            raise
        except OSError as exc:
            raise ProvisionError("could not safely sanitize writer-owned private identity crash residue") from exc
        finally:
            if descriptor >= 0:
                os.close(descriptor)

    if sanitized:
        raise ProvisionError(
            "private identity crash residue was descriptor-sanitized; remove the zero-length reserved tombstone in a trusted quiescent checkout and retry"
        )

    try:
        leftovers = sorted(
            name for name in os.listdir(checkout_fd) if name.startswith(_PRIVATE_STAGE_PREFIX)
        )
    except OSError as exc:
        raise ProvisionError("could not re-inspect private identity staging namespace") from exc
    if leftovers:
        raise ProvisionError("private identity staging namespace is not clean after recovery")

'''

RACE_TEST_TEXT = r'''#!/usr/bin/env python3
"""Adversarial: same-UID name swap cannot redirect crash-residue destruction.

Recovery may logically sanitize only the exact already-admitted inode. This test
replaces its pathname immediately before descriptor truncation. The replacement
must survive byte-for-byte, while the escaped admitted inode is sanitized and
recovery fails closed because the canonical name no longer binds that inode.
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
    spec = importlib.util.spec_from_file_location("nembra_private_identity_recovery_descriptor_race", WRITER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("private identity writer import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PrivateIdentityRecoveryDescriptorRaceTests(unittest.TestCase):
    def test_name_swap_before_descriptor_sanitize_preserves_replacement(self) -> None:
        writer = load_writer()
        admitted_payload = b"dummy-admitted-crash-residue"
        replacement_payload = b"attacker-replacement-must-survive"

        with tempfile.TemporaryDirectory(prefix="nembra-private-recovery-descriptor-race-") as temporary:
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

            def interpose_at_ftruncate(descriptor: int, length: int):
                nonlocal attack_fired
                if not attack_fired:
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
                return real_ftruncate(descriptor, length)

            writer.os.ftruncate = interpose_at_ftruncate
            try:
                with self.assertRaises(
                    writer.ProvisionError,
                    msg="recovery accepted a name swap at the destructive descriptor boundary",
                ):
                    writer._recover_private_stage_residue(checkout_fd)
            finally:
                writer.os.ftruncate = real_ftruncate
                os.close(checkout_fd)

            self.assertTrue(attack_fired, "fixture did not interpose at descriptor sanitization")
            self.assertTrue(escaped.is_file(), "escaped admitted residue disappeared")
            self.assertEqual(
                escaped.read_bytes(),
                b"",
                "recovery failed to sanitize the exact admitted inode after its name was moved",
            )
            self.assertTrue(stage.is_file(), "recovery deleted the replacement pathname subject")
            self.assertEqual(
                stage.read_bytes(),
                replacement_payload,
                "recovery mutated replacement bytes outside the admitted inode authority",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
'''


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


writer = WRITER.read_text(encoding="utf-8")
start = writer.index("def _recover_private_stage_residue(checkout_fd: int) -> None:\n")
end = writer.index("def _ensure_private_directory(parent_fd: int, name: str) -> int:\n", start)
writer = writer[:start] + NEW_RECOVERY + writer[end:]
WRITER.write_text(writer, encoding="utf-8")

writer_digest = hashlib.sha256(writer.encode("utf-8")).hexdigest()

shell = SHELL.read_text(encoding="utf-8")
shell, count = re.subn(r'WRITER_SHA256="[0-9a-f]{64}"', f'WRITER_SHA256="{writer_digest}"', shell, count=1)
if count != 1:
    raise SystemExit("shell: writer digest pin not found exactly once")
SHELL.write_text(shell, encoding="utf-8")

package = PACKAGE_TEST.read_text(encoding="utf-8")
package, count = re.subn(
    r'#expect\(shell\.contains\("WRITER_SHA256=\\"[0-9a-f]{64}\\""\)\)',
    f'#expect(shell.contains("WRITER_SHA256=\\"{writer_digest}\\""))',
    package,
    count=1,
)
if count != 1:
    raise SystemExit("package test: writer digest assertion not found exactly once")
needle = '        #expect(writer.contains("_recover_private_stage_residue"))\n'
addition = (
    needle
    + '        #expect(writer.contains("os.ftruncate(descriptor, 0)"))\n'
    + '        #expect(writer.contains("private identity staging descriptor changed during recovery sanitization"))\n'
    + '        #expect(writer.contains("remove the zero-length reserved tombstone in a trusted quiescent checkout and retry"))\n'
)
package = replace_once(package, needle, addition, "package recovery contract")
PACKAGE_TEST.write_text(package, encoding="utf-8")

crash = CRASH_TEST.read_text(encoding="utf-8")
old = '''            self.assertEqual(\n                residual_entries,\n                [],\n                "recovery left writer-owned .nembra-private-stage-* crash residue in the checkout root",\n            )\n'''
new = '''            self.assertEqual(\n                len(residual_entries),\n                1,\n                "descriptor-bound recovery should retain exactly one explicit zero-length tombstone",\n            )\n            tombstone = residual_entries[0]\n            tombstone_metadata = tombstone.lstat()\n            self.assertTrue(stat.S_ISREG(tombstone_metadata.st_mode))\n            self.assertEqual(tombstone_metadata.st_uid, os.geteuid())\n            self.assertEqual(tombstone_metadata.st_nlink, 1)\n            self.assertEqual(stat.S_IMODE(tombstone_metadata.st_mode), 0o600)\n            self.assertEqual(tombstone_metadata.st_size, 0)\n            self.assertEqual(tombstone.read_bytes(), b"")\n'''
crash = replace_once(crash, old, new, "crash residue tombstone contract")
comment_old = '''            # A later writer invocation is the first deterministic recovery\n            # opportunity after SIGKILL/power-loss. It may recover or fail\n            # closed, but it must not leave the prior known writer-shaped\n            # credential bytes hidden under the ignored reserved prefix.\n            run_recovery_invocation(writer, checkout)\n'''
comment_new = '''            # A later writer invocation is the first deterministic recovery\n            # opportunity after SIGKILL/power-loss. It must sanitize the exact\n            # admitted inode through its held descriptor, then fail closed with\n            # an explicit zero-length tombstone rather than pathname-unlinking.\n            self.assertTrue(run_recovery_invocation(writer, checkout))\n'''
crash = replace_once(crash, comment_old, comment_new, "crash residue explanation")
CRASH_TEST.write_text(crash, encoding="utf-8")

RACE_TEST.write_text(RACE_TEST_TEXT, encoding="utf-8")

workflow = WORKFLOW.read_text(encoding="utf-8")
path_line = "      - scripts/ci/tests/test_capture_private_identity_crash_residue.py\n"
if workflow.count(path_line) != 2:
    raise SystemExit(f"workflow: expected two crash-residue trigger lines, found {workflow.count(path_line)}")
workflow = workflow.replace(
    path_line,
    path_line + "      - scripts/ci/tests/test_capture_private_identity_recovery_unlink_race.py\n",
)
compile_line = "          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_private_identity_crash_residue.py\n"
workflow = replace_once(
    workflow,
    compile_line,
    compile_line + "          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_private_identity_recovery_unlink_race.py\n",
    "workflow compile",
)
run_line = "          /usr/bin/python3 -I scripts/ci/tests/test_capture_private_identity_crash_residue.py\n"
workflow = replace_once(
    workflow,
    run_line,
    run_line + "          /usr/bin/python3 -I scripts/ci/tests/test_capture_private_identity_recovery_unlink_race.py\n",
    "workflow run",
)
WORKFLOW.write_text(workflow, encoding="utf-8")

print(f"materialized descriptor-bound recovery; writer sha256={writer_digest}")

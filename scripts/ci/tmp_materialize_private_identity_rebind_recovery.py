#!/usr/bin/env python3
"""One-shot materializer for #3206 private-identity rebind closure.

This script is temporary construction machinery. It transforms the exact #2755
writer contract, repins the privileged shell/package digest, and leaves the
permanent descendant/name rebind regression in the candidate tree.
"""

from __future__ import annotations

import hashlib
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
WRITER = ROOT / "Scripts" / "provision_capture_tuya_identity_writer.py"
SHELL = ROOT / "Scripts" / "provision_capture_tuya_identity.sh"
SWIFT_TEST = (
    ROOT
    / "Packages"
    / "NembraBluetoothCapture"
    / "Tests"
    / "NembraBluetoothCaptureTests"
    / "TuyaPrivateIdentityProvisionerCustodyTests.swift"
)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


source = WRITER.read_text(encoding="utf-8")

helper_anchor = "def _secure_replace_beneath(checkout_fd: int, source_name: str, destination_relative: str) -> None:\n"
if source.count(helper_anchor) != 1:
    raise SystemExit("unexpected #2755 secure publication function shape")

helpers = r'''def _open_relative_parent(checkout_fd: int, relative_path: str) -> int:
    components = _relative_components(relative_path)
    parent_fd = os.dup(checkout_fd)
    try:
        for component in components[:-1]:
            next_fd = os.open(component, _directory_flags(), dir_fd=parent_fd)
            os.close(parent_fd)
            parent_fd = next_fd
        return parent_fd
    except Exception:
        os.close(parent_fd)
        raise


def _require_relative_parent_matches_fd(
    checkout_fd: int,
    relative_path: str,
    expected_parent_fd: int,
) -> None:
    current_parent_fd = _open_relative_parent(checkout_fd, relative_path)
    try:
        current = os.fstat(current_parent_fd)
        expected = os.fstat(expected_parent_fd)
        if (
            not stat.S_ISDIR(current.st_mode)
            or not stat.S_ISDIR(expected.st_mode)
            or current.st_uid != os.geteuid()
            or expected.st_uid != os.geteuid()
            or current.st_dev != expected.st_dev
            or current.st_ino != expected.st_ino
        ):
            raise ProvisionError("private identity destination parent left admitted checkout ancestry")
    finally:
        os.close(current_parent_fd)


def _require_relative_name_matches_fd(
    checkout_fd: int,
    relative_path: str,
    expected_fd: int,
) -> None:
    components = _relative_components(relative_path)
    parent_fd = _open_relative_parent(checkout_fd, relative_path)
    try:
        try:
            named = os.stat(components[-1], dir_fd=parent_fd, follow_symlinks=False)
        except OSError as exc:
            raise ProvisionError("private identity canonical destination name changed") from exc
        held = os.fstat(expected_fd)
        if (
            not stat.S_ISREG(named.st_mode)
            or not stat.S_ISREG(held.st_mode)
            or named.st_uid != os.geteuid()
            or held.st_uid != os.geteuid()
            or named.st_nlink != 1
            or held.st_nlink != 1
            or named.st_dev != held.st_dev
            or named.st_ino != held.st_ino
        ):
            raise ProvisionError("private identity canonical destination no longer names the sealed inode")
    finally:
        os.close(parent_fd)


def _remove_named_if_same_inode(
    parent_fd: int,
    name: str,
    expected_dev: int,
    expected_ino: int,
) -> None:
    try:
        named = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    except OSError:
        return
    if (
        stat.S_ISREG(named.st_mode)
        and named.st_uid == os.geteuid()
        and named.st_nlink == 1
        and named.st_dev == expected_dev
        and named.st_ino == expected_ino
    ):
        try:
            os.unlink(name, dir_fd=parent_fd)
            os.fsync(parent_fd)
        except OSError:
            pass


def _remove_reserved_canonical_output_if_safe(checkout_fd: int, relative_path: str) -> None:
    components = _relative_components(relative_path)
    parent_fd = _open_relative_parent(checkout_fd, relative_path)
    try:
        try:
            named = os.stat(components[-1], dir_fd=parent_fd, follow_symlinks=False)
        except OSError:
            return
        if (
            stat.S_ISREG(named.st_mode)
            and named.st_uid == os.geteuid()
            and named.st_nlink == 1
            and stat.S_IMODE(named.st_mode) == 0o600
        ):
            try:
                os.unlink(components[-1], dir_fd=parent_fd)
                os.fsync(parent_fd)
            except OSError:
                pass
    finally:
        os.close(parent_fd)


def _secure_replace_beneath(
    checkout_fd: int,
    source_name: str,
    destination_parent_fd: int,
    final_name: str,
    destination_relative: str,
) -> None:
    source_components = _relative_components(source_name)
    destination_components = _relative_components(destination_relative)
    if len(source_components) != 1:
        raise ProvisionError("private identity staging source must be one admitted-root leaf")
    if destination_components[-1] != final_name:
        raise ProvisionError("private identity destination leaf does not match admitted relative path")

    # This check is deliberately inside the publication primitive. A caller-side
    # precheck cannot authorize a later root-relative re-resolution after a
    # same-UID descendant replacement.
    _require_relative_parent_matches_fd(checkout_fd, destination_relative, destination_parent_fd)

    if sys.platform == "darwin":
        libc = ctypes.CDLL(None, use_errno=True)
        try:
            renameatx_np = libc.renameatx_np
        except AttributeError as exc:
            raise ProvisionError("Darwin cannot provide renameatx_np publication custody") from exc
        renameatx_np.argtypes = (
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        )
        renameatx_np.restype = ctypes.c_int
        flags = _DARWIN_RENAME_NOFOLLOW_ANY | _DARWIN_RENAME_RESOLVE_BENEATH
        result = renameatx_np(
            checkout_fd,
            os.fsencode(source_name),
            destination_parent_fd,
            os.fsencode(final_name),
            flags,
        )
        if result != 0:
            error = ctypes.get_errno()
            raise ProvisionError("Darwin rejected private identity publication outside admitted ancestry") from OSError(
                error,
                os.strerror(error),
            )
        return

    # Linux CI fallback keeps the same held-parent publication shape. Physical
    # field publication is macOS-only and is required to take the Darwin path.
    os.replace(
        source_name,
        final_name,
        src_dir_fd=checkout_fd,
        dst_dir_fd=destination_parent_fd,
    )
'''

start = source.index(helper_anchor)
end = source.index("\n\ndef _write_staged(", start)
source = source[:start] + helpers.rstrip() + source[end:]

old_publish = """        _require_staging_name_matches_fd(checkout_fd, temporary_name, sealed)\n        _secure_replace_beneath(checkout_fd, temporary_name, destination_relative)\n\n        final_fd = _open_relative_regular_file(checkout_fd, destination_relative)\n"""
new_publish = """        _require_staging_name_matches_fd(checkout_fd, temporary_name, sealed)\n        _secure_replace_beneath(\n            checkout_fd,\n            temporary_name,\n            destination_parent_fd,\n            final_name,\n            destination_relative,\n        )\n        try:\n            _require_relative_parent_matches_fd(\n                checkout_fd,\n                destination_relative,\n                destination_parent_fd,\n            )\n        except Exception:\n            _remove_named_if_same_inode(\n                destination_parent_fd,\n                final_name,\n                sealed.st_dev,\n                sealed.st_ino,\n            )\n            raise\n\n        final_fd = _open_relative_regular_file(checkout_fd, destination_relative)\n"""
source = replace_once(source, old_publish, new_publish, "held-parent publication")

old_finish = """        os.fchmod(final_fd, 0o600)\n        os.fsync(final_fd)\n        os.fsync(checkout_fd)\n"""
new_finish = """        os.fchmod(final_fd, 0o600)\n        os.fsync(final_fd)\n        try:\n            _require_relative_parent_matches_fd(\n                checkout_fd,\n                destination_relative,\n                destination_parent_fd,\n            )\n            _require_relative_name_matches_fd(\n                checkout_fd,\n                destination_relative,\n                final_fd,\n            )\n        except Exception as exc:\n            _remove_reserved_canonical_output_if_safe(checkout_fd, destination_relative)\n            raise ProvisionError(\n                \"private identity canonical destination changed before success\"\n            ) from exc\n        os.fsync(destination_parent_fd)\n        os.fsync(checkout_fd)\n"""
source = replace_once(source, old_finish, new_finish, "final canonical rebind")

source = source.replace(
    "uses renameatx_np with no-follow-any + resolve-beneath semantics so every path\n"
    "component is resolved beneath that admitted root in the publication syscall.\n"
    "The sealed staging descriptor remains open through publication and the final\n"
    "named inode must match it exactly before success.\n",
    "uses renameatx_np from the admitted root into the exact held destination-parent\n"
    "descriptor after that parent is rebound to the live canonical ancestry inside\n"
    "the publication seam. The sealed staging descriptor remains open through\n"
    "publication, and the canonical final name is rebound to that sealed inode again\n"
    "at the success boundary.\n",
    1,
)

WRITER.write_text(source, encoding="utf-8")
writer_digest = hashlib.sha256(WRITER.read_bytes()).hexdigest()

shell = SHELL.read_text(encoding="utf-8")
shell, shell_count = re.subn(
    r'WRITER_SHA256="[0-9a-f]{64}"',
    f'WRITER_SHA256="{writer_digest}"',
    shell,
    count=1,
)
if shell_count != 1:
    raise SystemExit(f"shell writer digest: expected one replacement, found {shell_count}")
SHELL.write_text(shell, encoding="utf-8")

swift = SWIFT_TEST.read_text(encoding="utf-8")
swift, swift_count = re.subn(
    r'WRITER_SHA256=\\"[0-9a-f]{64}\\"',
    f'WRITER_SHA256=\\"{writer_digest}\\"',
    swift,
    count=1,
)
if swift_count != 1:
    raise SystemExit(f"Swift writer digest: expected one replacement, found {swift_count}")
SWIFT_TEST.write_text(swift, encoding="utf-8")

print(f"materialized private identity rebind repair; writer sha256={writer_digest}")

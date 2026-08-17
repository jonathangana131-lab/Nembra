#!/usr/bin/env python3
"""Narrow Darwin ACL lease primitive for an ACL-absent, descriptor-pinned object.

This module deliberately implements only the baseline shape proven by the Nembra
Capture xcode-27 oracle: the exact object has no extended ACL before admission,
temporary authority is granted through its canonical pathname while pathname and
held descriptor identity still agree, and rollback clears the original vnode through
the held descriptor with public acl_set_fd(3).

A pre-existing/non-empty ACL is rejected before mutation. The caller must keep the
canonical parent ancestry root-custodied during the pathname grant; this primitive
does not make an untrusted rename race during chmod safe. If the pathname no longer
identifies the held object during revoke, cleanup is still applied to the held
original descriptor and the operation then fails closed.

This helper creates no install, device, Bluetooth, Tuya, telemetry, command, or
physical authority by itself.
"""

from __future__ import annotations

import ctypes
import errno
import os
from pathlib import Path
import stat
import subprocess
import sys
from typing import Sequence


# Darwin <sys/acl.h>. Kept local and guarded by sys.platform so importing this
# validation/production ingredient on non-Darwin hosts remains harmless.
_ACL_TYPE_EXTENDED = 0x00000100


class DarwinAbsentACLLeaseError(RuntimeError):
    pass


class DarwinAbsentACLPathIdentityLost(DarwinAbsentACLLeaseError):
    """Raised after descriptor-bound cleanup when the canonical name was replaced."""


def _require_darwin() -> None:
    if sys.platform != "darwin":
        raise DarwinAbsentACLLeaseError("Darwin ACL lease is available only on macOS")


def _libc():
    _require_darwin()
    library = ctypes.CDLL(None, use_errno=True)
    try:
        acl_get_file = library.acl_get_file
        acl_init = library.acl_init
        acl_set_fd = library.acl_set_fd
        acl_free = library.acl_free
    except AttributeError as error:
        raise DarwinAbsentACLLeaseError("required public Darwin ACL symbols are unavailable") from error

    acl_get_file.argtypes = (ctypes.c_char_p, ctypes.c_int)
    acl_get_file.restype = ctypes.c_void_p
    acl_init.argtypes = (ctypes.c_int,)
    acl_init.restype = ctypes.c_void_p
    acl_set_fd.argtypes = (ctypes.c_int, ctypes.c_void_p)
    acl_set_fd.restype = ctypes.c_int
    acl_free.argtypes = (ctypes.c_void_p,)
    acl_free.restype = ctypes.c_int
    return acl_get_file, acl_init, acl_set_fd, acl_free


def _signature_from_stat(metadata: os.stat_result) -> tuple[int, int, int]:
    return metadata.st_dev, metadata.st_ino, stat.S_IFMT(metadata.st_mode)


def descriptor_signature(descriptor: int) -> tuple[int, int, int]:
    if descriptor < 0:
        raise DarwinAbsentACLLeaseError("ACL lease descriptor is invalid")
    try:
        metadata = os.fstat(descriptor)
    except OSError as error:
        raise DarwinAbsentACLLeaseError("ACL lease descriptor is unavailable") from error
    return _signature_from_stat(metadata)


def path_signature(path: Path) -> tuple[int, int, int]:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise DarwinAbsentACLLeaseError(f"ACL lease pathname is unavailable: {path}") from error
    if stat.S_ISLNK(metadata.st_mode):
        raise DarwinAbsentACLLeaseError(f"ACL lease pathname became a symlink: {path}")
    return _signature_from_stat(metadata)


def require_bound_path(descriptor: int, path: Path, expected: tuple[int, int, int]) -> None:
    if descriptor_signature(descriptor) != expected:
        raise DarwinAbsentACLLeaseError("held ACL lease descriptor changed identity")
    if path_signature(path) != expected:
        raise DarwinAbsentACLPathIdentityLost(
            f"canonical ACL lease pathname no longer identifies held object: {path}"
        )


def path_extended_acl_absent(path: Path) -> bool:
    """Return True only for the Darwin ACL-absent result; fail closed otherwise."""
    acl_get_file, _acl_init, _acl_set_fd, acl_free = _libc()
    ctypes.set_errno(0)
    acl = acl_get_file(os.fsencode(path), _ACL_TYPE_EXTENDED)
    saved_errno = ctypes.get_errno()
    if acl:
        try:
            return False
        finally:
            acl_free(acl)
    if saved_errno == errno.ENOENT:
        return True
    raise DarwinAbsentACLLeaseError(
        f"could not classify extended ACL baseline for {path}: errno={saved_errno}"
    )


def _restore_empty_acl(descriptor: int) -> None:
    """Restore an ACL-absent baseline on the exact held vnode using public APIs."""
    _acl_get_file, acl_init, acl_set_fd, acl_free = _libc()
    ctypes.set_errno(0)
    empty_acl = acl_init(0)
    if not empty_acl:
        saved_errno = ctypes.get_errno()
        raise DarwinAbsentACLLeaseError(
            f"acl_init(0) failed while restoring absent ACL baseline: errno={saved_errno}"
        )
    try:
        ctypes.set_errno(0)
        result = acl_set_fd(descriptor, empty_acl)
        saved_errno = ctypes.get_errno()
        if result != 0:
            raise DarwinAbsentACLLeaseError(
                f"acl_set_fd failed while restoring absent ACL baseline: errno={saved_errno}"
            )
    finally:
        acl_free(empty_acl)


def _chmod_add(path: Path, acl_text: str) -> None:
    if not acl_text or "\x00" in acl_text or "\n" in acl_text or "\r" in acl_text:
        raise DarwinAbsentACLLeaseError("temporary ACL text is malformed")
    completed = subprocess.run(
        ["/bin/chmod", "+a", acl_text, str(path)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = ((completed.stdout or "") + "\n" + (completed.stderr or "")).strip()
        raise DarwinAbsentACLLeaseError(
            "canonical-path Darwin ACL grant failed"
            + (f": {detail[-800:]}" if detail else "")
        )


class DarwinAbsentACLLease:
    """One temporary ACL grant whose original baseline is proven ACL-absent."""

    def __init__(self, descriptor: int, path: Path, acl_text: str) -> None:
        _require_darwin()
        self._descriptor = descriptor
        self._path = Path(path)
        self._acl_text = acl_text
        self._expected = descriptor_signature(descriptor)
        self._mutated = False
        self._active = False

    @property
    def active(self) -> bool:
        return self._active

    def grant(self) -> None:
        if self._active or self._mutated:
            raise DarwinAbsentACLLeaseError("Darwin ACL lease is already active or dirty")

        # Canonical-path mutation is admissible only while it still names the exact
        # held object. Baseline classification is bracketed by identity checks.
        require_bound_path(self._descriptor, self._path, self._expected)
        absent = path_extended_acl_absent(self._path)
        require_bound_path(self._descriptor, self._path, self._expected)
        if not absent:
            raise DarwinAbsentACLLeaseError(
                "pre-existing/non-empty extended ACL is unsupported; refusing mutation"
            )

        try:
            _chmod_add(self._path, self._acl_text)
            self._mutated = True
            require_bound_path(self._descriptor, self._path, self._expected)
            if path_extended_acl_absent(self._path):
                raise DarwinAbsentACLLeaseError("temporary ACL did not materialize")
            require_bound_path(self._descriptor, self._path, self._expected)
            self._active = True
        except Exception:
            # Once chmod was attempted, absence cannot be assumed. Restore the proven
            # empty baseline on the held original descriptor before surfacing failure.
            if self._mutated:
                _restore_empty_acl(self._descriptor)
                self._mutated = False
            self._active = False
            raise

    def revoke(self) -> None:
        if not self._mutated:
            self._active = False
            return

        failures: list[str] = []
        try:
            _restore_empty_acl(self._descriptor)
        except Exception as error:
            failures.append(str(error))
        finally:
            self._active = False
            self._mutated = False

        # Cleanup above is descriptor-bound and therefore targets the original vnode
        # even after rename/replacement. Verification through the canonical path is
        # authoritative only if it still names that original object.
        path_bound = True
        try:
            require_bound_path(self._descriptor, self._path, self._expected)
        except DarwinAbsentACLPathIdentityLost as error:
            path_bound = False
            failures.append(str(error))
        except Exception as error:
            failures.append(str(error))

        if path_bound:
            try:
                if not path_extended_acl_absent(self._path):
                    failures.append("descriptor-bound revoke did not restore ACL-absent baseline")
            except Exception as error:
                failures.append(str(error))

        if failures:
            if not path_bound and len(failures) == 1:
                raise DarwinAbsentACLPathIdentityLost(failures[0])
            raise DarwinAbsentACLLeaseError("Darwin ACL lease revoke failed: " + "; ".join(failures))


def revoke_all(leases: Sequence[DarwinAbsentACLLease]) -> None:
    """Reverse-order cleanup for a partially granted component chain."""
    failures: list[str] = []
    for lease in reversed(tuple(leases)):
        try:
            lease.revoke()
        except Exception as error:
            failures.append(str(error))
    if failures:
        raise DarwinAbsentACLLeaseError(
            "one or more descriptor-bound Darwin ACL revocations failed: " + "; ".join(failures)
        )

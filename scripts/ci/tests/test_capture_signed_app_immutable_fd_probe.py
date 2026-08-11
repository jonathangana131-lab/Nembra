#!/usr/bin/env python3
"""Validation-only macOS probe for revoking an already-open compiler-output FD.

This does not change Nembra production authority. It asks whether a root supervisor can
transfer an output inode to root, apply UF_IMMUTABLE, and thereby prevent the original
field UID from mutating bytes or clearing the flag through a writable FD opened before
revocation.
"""

from __future__ import annotations

import errno
import hashlib
import os
import stat
import struct
import tempfile
from pathlib import Path


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _read_exact(fd: int, size: int) -> bytes:
    chunks: list[bytes] = []
    remaining = size
    while remaining:
        chunk = os.read(fd, remaining)
        if not chunk:
            raise RuntimeError("unexpected EOF from probe child")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def main() -> int:
    if os.geteuid() != 0:
        raise RuntimeError("probe must run under sudo on macOS")
    if not hasattr(stat, "UF_IMMUTABLE") or not hasattr(os, "chflags"):
        raise RuntimeError("macOS immutable-file primitives are unavailable")

    raw_uid = os.environ.get("SUDO_UID", "")
    raw_gid = os.environ.get("SUDO_GID", "")
    if not raw_uid.isdigit() or not raw_gid.isdigit():
        raise RuntimeError("sudo did not expose the invoking field identity")
    uid = int(raw_uid)
    gid = int(raw_gid)
    if uid <= 0:
        raise RuntimeError("field identity must be non-root")

    root = Path(tempfile.mkdtemp(prefix="nembra-immutable-fd-probe.", dir="/private/tmp"))
    product = root / "CaptureProduct"
    initial = b"accepted-build-output\n"
    product.write_bytes(initial)
    os.chown(product, uid, gid)
    os.chmod(product, 0o600)
    os.chown(root, uid, gid)
    os.chmod(root, 0o700)
    before = _sha256(product)

    child_ready_r, child_ready_w = os.pipe()
    parent_go_r, parent_go_w = os.pipe()
    result_r, result_w = os.pipe()
    pid = os.fork()
    if pid == 0:
        try:
            os.close(child_ready_r)
            os.close(parent_go_w)
            os.close(result_r)
            os.setgroups([])
            os.setgid(gid)
            os.setuid(uid)
            fd = os.open(product, os.O_RDWR | os.O_CLOEXEC)
            os.write(child_ready_w, b"R")
            if _read_exact(parent_go_r, 1) != b"G":
                raise RuntimeError("bad parent synchronization")

            clear_errno = 0
            if hasattr(os, "fchflags"):
                try:
                    os.fchflags(fd, 0)
                except OSError as error:
                    clear_errno = error.errno or -1
            else:
                clear_errno = errno.ENOTSUP

            write_errno = 0
            try:
                os.lseek(fd, 0, os.SEEK_END)
                os.write(fd, b"ATTACK\n")
                os.fsync(fd)
            except OSError as error:
                write_errno = error.errno or -1

            payload = struct.pack("!ii", clear_errno, write_errno)
            os.write(result_w, payload)
            os.close(fd)
            os._exit(0)
        except BaseException:
            os._exit(111)

    os.close(child_ready_w)
    os.close(parent_go_r)
    os.close(result_w)
    immutable_set = False
    try:
        if _read_exact(child_ready_r, 1) != b"R":
            raise RuntimeError("child did not open product FD")

        # Model the proposed post-build authority revocation: take inode ownership away
        # from the field UID, close ordinary pathname authority, then make the inode
        # immutable before any authoritative fingerprint is minted.
        os.chown(root, 0, 0)
        os.chmod(root, 0o700)
        os.chown(product, 0, 0)
        os.chmod(product, 0o600)
        os.chflags(product, stat.UF_IMMUTABLE)
        immutable_set = True

        os.write(parent_go_w, b"G")
        clear_errno, write_errno = struct.unpack("!ii", _read_exact(result_r, 8))
        _, status = os.waitpid(pid, 0)
        if not os.WIFEXITED(status) or os.WEXITSTATUS(status) != 0:
            raise RuntimeError(f"probe child failed with status {status}")

        after = _sha256(product)
        if clear_errno == 0:
            raise AssertionError("field UID cleared UF_IMMUTABLE through pre-opened FD")
        if write_errno == 0:
            raise AssertionError("field UID mutated product through pre-opened FD after immutable revocation")
        if after != before or product.read_bytes() != initial:
            raise AssertionError("product bytes changed after immutable revocation")

        flags = product.stat().st_flags
        if not flags & stat.UF_IMMUTABLE:
            raise AssertionError("product immutable flag did not remain set")
        if product.stat().st_uid != 0:
            raise AssertionError("product ownership was not transferred to root")

        print(
            "PASS: root ownership + UF_IMMUTABLE revoked mutation authority from an already-open field-user FD "
            f"(clear errno={clear_errno}, write errno={write_errno})"
        )
        return 0
    finally:
        try:
            os.close(child_ready_r)
        except OSError:
            pass
        try:
            os.close(parent_go_w)
        except OSError:
            pass
        try:
            os.close(result_r)
        except OSError:
            pass
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass
        try:
            os.waitpid(pid, 0)
        except ChildProcessError:
            pass
        if immutable_set:
            try:
                os.chflags(product, 0)
            except OSError:
                pass
        try:
            product.unlink(missing_ok=True)
            root.rmdir()
        except OSError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())

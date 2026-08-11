#!/usr/bin/env python3
"""Bind the signed Nembra Capture.app subject across the devicectl install window.

The field installer first earns authority for one signed app bundle through provenance,
code-signature, entitlement, and provisioning-profile checks. This helper fingerprints
that exact directory tree through descriptor-bound, no-follow reads, then keeps vnode
custody armed while the install subprocess runs. Any persistent or observed mutation
fails closed; render/build/runtime evidence is not promoted by this helper.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
import select
import stat
import subprocess
import sys
from typing import Callable, Protocol, Sequence

SCHEMA = b"nembra-capture-signed-app-install-subject-v1\0"
DIGEST_RE = re.compile(r"^[0-9a-f]{64}$")


class InstallSubjectError(RuntimeError):
    pass


class EventBackend(Protocol):
    def register(self, descriptor: int) -> None: ...
    def events(self, timeout: float) -> Sequence[object]: ...
    def close(self) -> None: ...


class KqueueVnodeBackend:
    def __init__(self) -> None:
        required = (
            "kqueue", "kevent", "KQ_FILTER_VNODE", "KQ_EV_ADD", "KQ_EV_ENABLE", "KQ_EV_CLEAR",
            "KQ_NOTE_DELETE", "KQ_NOTE_WRITE", "KQ_NOTE_EXTEND", "KQ_NOTE_LINK", "KQ_NOTE_RENAME", "KQ_NOTE_REVOKE",
        )
        missing = [name for name in required if not hasattr(select, name)]
        if missing:
            raise InstallSubjectError("macOS kqueue vnode monitoring is unavailable: " + ", ".join(missing))
        self._queue = select.kqueue()
        self._fflags = (
            select.KQ_NOTE_DELETE
            | select.KQ_NOTE_WRITE
            | select.KQ_NOTE_EXTEND
            | select.KQ_NOTE_LINK
            | select.KQ_NOTE_RENAME
            | select.KQ_NOTE_REVOKE
        )

    def register(self, descriptor: int) -> None:
        self._queue.control([
            select.kevent(
                descriptor,
                filter=select.KQ_FILTER_VNODE,
                flags=select.KQ_EV_ADD | select.KQ_EV_ENABLE | select.KQ_EV_CLEAR,
                fflags=self._fflags,
            )
        ], 0, 0)

    def events(self, timeout: float) -> Sequence[object]:
        return self._queue.control(None, 512, timeout)

    def close(self) -> None:
        self._queue.close()


def _identity(metadata: os.stat_result) -> tuple[int, int, int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_nlink,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _record(hasher: "hashlib._Hash", kind: bytes, relative: str, metadata: os.stat_result, payload: bytes = b"") -> None:
    encoded = relative.encode("utf-8")
    hasher.update(kind)
    hasher.update(len(encoded).to_bytes(8, "big"))
    hasher.update(encoded)
    hasher.update((metadata.st_mode & 0o7777).to_bytes(4, "big"))
    hasher.update(len(payload).to_bytes(8, "big"))
    hasher.update(payload)


def _open_absolute_directory_no_follow(path: Path) -> int:
    if not path.is_absolute():
        raise InstallSubjectError("signed app path must be absolute")
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0)
    descriptor = os.open("/", flags)
    try:
        for component in path.parts[1:]:
            if component in ("", ".", ".."):
                raise InstallSubjectError("signed app path contains a non-canonical component")
            next_descriptor = os.open(component, flags, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = next_descriptor
        metadata = os.fstat(descriptor)
        if not stat.S_ISDIR(metadata.st_mode):
            raise InstallSubjectError("signed app subject is not a directory")
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


def _hash_regular_file(parent_fd: int, name: str, expected: os.stat_result) -> bytes:
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0)
    descriptor = os.open(name, flags, dir_fd=parent_fd)
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or _identity(before) != _identity(expected):
            raise InstallSubjectError(f"signed app file changed during descriptor admission: {name}")
        digest = hashlib.sha256()
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
        after = os.fstat(descriptor)
        if _identity(after) != _identity(before):
            raise InstallSubjectError(f"signed app file changed while hashing: {name}")
        return digest.digest()
    finally:
        os.close(descriptor)


def _digest_directory(directory_fd: int, relative: str, hasher: "hashlib._Hash") -> None:
    root_metadata = os.fstat(directory_fd)
    _record(hasher, b"D", relative, root_metadata)
    try:
        names = sorted(os.listdir(directory_fd))
    except TypeError as error:
        raise InstallSubjectError("descriptor directory enumeration is unavailable") from error

    for name in names:
        if name in (".", ".."):
            continue
        metadata = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        child_relative = f"{relative}/{name}" if relative else name
        if stat.S_ISDIR(metadata.st_mode):
            flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0)
            child_fd = os.open(name, flags, dir_fd=directory_fd)
            try:
                if _identity(os.fstat(child_fd)) != _identity(metadata):
                    raise InstallSubjectError(f"signed app directory changed during descriptor admission: {child_relative}")
                _digest_directory(child_fd, child_relative, hasher)
            finally:
                os.close(child_fd)
        elif stat.S_ISREG(metadata.st_mode):
            payload = _hash_regular_file(directory_fd, name, metadata)
            _record(hasher, b"F", child_relative, metadata, payload)
        elif stat.S_ISLNK(metadata.st_mode):
            # The physical field app does not require path indirection. Rejecting
            # symlinks keeps every byte consumed by install inside one descriptor-
            # admitted tree instead of granting authority to an external target.
            raise InstallSubjectError(f"signed app contains unsupported symlink: {child_relative}")
        else:
            raise InstallSubjectError(f"signed app contains unsupported filesystem entry: {child_relative}")


def digest_app(app: Path) -> str:
    descriptor = _open_absolute_directory_no_follow(app)
    try:
        hasher = hashlib.sha256()
        hasher.update(SCHEMA)
        _digest_directory(descriptor, "Nembra Capture.app", hasher)
        return hasher.hexdigest()
    finally:
        os.close(descriptor)


def _collect_watch_descriptors(app: Path, backend: EventBackend) -> tuple[tuple[int, str], ...]:
    root_fd = _open_absolute_directory_no_follow(app)
    retained: list[tuple[int, str]] = []

    def retain_tree(directory_fd: int, relative: str) -> None:
        backend.register(directory_fd)
        retained.append((directory_fd, relative))
        for name in sorted(os.listdir(directory_fd)):
            if name in (".", ".."):
                continue
            metadata = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
            child_relative = f"{relative}/{name}" if relative else name
            if stat.S_ISDIR(metadata.st_mode):
                flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0)
                child_fd = os.open(name, flags, dir_fd=directory_fd)
                if _identity(os.fstat(child_fd)) != _identity(metadata):
                    os.close(child_fd)
                    raise InstallSubjectError(f"signed app directory changed while arming custody: {child_relative}")
                retain_tree(child_fd, child_relative)
            elif stat.S_ISREG(metadata.st_mode):
                flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0)
                file_fd = os.open(name, flags, dir_fd=directory_fd)
                if _identity(os.fstat(file_fd)) != _identity(metadata):
                    os.close(file_fd)
                    raise InstallSubjectError(f"signed app file changed while arming custody: {child_relative}")
                backend.register(file_fd)
                retained.append((file_fd, child_relative))
            elif stat.S_ISLNK(metadata.st_mode):
                raise InstallSubjectError(f"signed app contains unsupported symlink: {child_relative}")
            else:
                raise InstallSubjectError(f"signed app contains unsupported filesystem entry: {child_relative}")

    try:
        retain_tree(root_fd, "Nembra Capture.app")
        return tuple(retained)
    except Exception:
        for descriptor, _ in retained:
            try:
                os.close(descriptor)
            except OSError:
                pass
        if not retained:
            os.close(root_fd)
        raise


def _stop_process(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def guarded_install(
    app: Path,
    expected_digest: str,
    command: Sequence[str],
    *,
    backend_factory: Callable[[], EventBackend] = KqueueVnodeBackend,
    popen_factory: Callable[..., subprocess.Popen] = subprocess.Popen,
    poll_interval: float = 0.05,
) -> int:
    if DIGEST_RE.fullmatch(expected_digest) is None:
        raise InstallSubjectError("expected signed app subject digest must be lowercase 64-hex")
    if not command:
        raise InstallSubjectError("no install command supplied")
    if digest_app(app) != expected_digest:
        raise InstallSubjectError("signed app subject changed after field-authority verification")

    backend = backend_factory()
    watched: tuple[tuple[int, str], ...] = ()
    process: subprocess.Popen | None = None
    try:
        watched = _collect_watch_descriptors(app, backend)
        if digest_app(app) != expected_digest:
            raise InstallSubjectError("signed app subject changed while install custody was armed")
        if backend.events(0):
            raise InstallSubjectError("signed app mutation was queued before devicectl admission")

        process = popen_factory(list(command))
        while process.poll() is None:
            if backend.events(poll_interval):
                _stop_process(process)
                raise InstallSubjectError("signed app mutation was observed while devicectl was consuming the install subject")

        if backend.events(0):
            raise InstallSubjectError("signed app mutation was observed at devicectl completion")
        if digest_app(app) != expected_digest:
            raise InstallSubjectError("signed app subject changed across the devicectl install window")
        return int(process.returncode or 0)
    finally:
        if process is not None and process.poll() is None:
            _stop_process(process)
        for descriptor, _ in watched:
            try:
                os.close(descriptor)
            except OSError:
                pass
        backend.close()


def _parse(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="action", required=True)
    digest_parser = subparsers.add_parser("digest")
    digest_parser.add_argument("--app", type=Path, required=True)
    guard_parser = subparsers.add_parser("guard")
    guard_parser.add_argument("--app", type=Path, required=True)
    guard_parser.add_argument("--expected", required=True)
    guard_parser.add_argument("command", nargs=argparse.REMAINDER)
    return parser.parse_args(list(argv))


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parse(sys.argv[1:] if argv is None else argv)
    try:
        if arguments.action == "digest":
            print(digest_app(arguments.app))
            return 0
        command = list(arguments.command)
        if command and command[0] == "--":
            command = command[1:]
        return guarded_install(arguments.app, arguments.expected, command)
    except InstallSubjectError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 74
    except OSError as error:
        print(f"ERROR: signed app filesystem custody failed: {error}", file=sys.stderr)
        return 75


if __name__ == "__main__":
    raise SystemExit(main())

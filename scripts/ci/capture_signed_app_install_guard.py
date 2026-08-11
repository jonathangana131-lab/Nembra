#!/usr/bin/env python3
"""Hold one signed Nembra Capture.app subject stable across verification + install.

The physical field installer must not verify one app bundle and later let CoreDevice
consume different bytes from the same mutable pathname. This helper keeps vnode
custody armed on the app bundle, every real descendant, and the app's parent for
the complete guarded child process. It also re-samples a deterministic bundle
subject before arming and after completion so missed/non-restored mutations fail
closed. The guarded child is expected to perform every signed-app provenance,
signature/entitlement/profile check and the devicectl install side effect.

This helper creates no physical authority. It only rejects a candidate when the
host-side signed install subject is not stable for the whole verification/install
window.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import select
import stat
import subprocess
import sys
from dataclasses import dataclass
from typing import Callable, Iterable, Protocol, Sequence


class InstallGuardError(RuntimeError):
    pass


@dataclass(frozen=True)
class EntryIdentity:
    device: int
    inode: int
    mode: int
    uid: int
    gid: int
    size: int
    mtime_ns: int
    ctime_ns: int
    links: int


def _identity(metadata: os.stat_result) -> EntryIdentity:
    return EntryIdentity(
        device=metadata.st_dev,
        inode=metadata.st_ino,
        mode=metadata.st_mode,
        uid=metadata.st_uid,
        gid=metadata.st_gid,
        size=metadata.st_size,
        mtime_ns=metadata.st_mtime_ns,
        ctime_ns=metadata.st_ctime_ns,
        links=metadata.st_nlink,
    )


def _record(hasher: "hashlib._Hash", kind: bytes, relative: bytes, metadata: os.stat_result, payload: bytes) -> None:
    hasher.update(kind)
    hasher.update(len(relative).to_bytes(8, "big"))
    hasher.update(relative)
    hasher.update((metadata.st_mode & 0o7777).to_bytes(4, "big"))
    hasher.update(metadata.st_size.to_bytes(8, "big", signed=False))
    hasher.update(len(payload).to_bytes(8, "big"))
    hasher.update(payload)


def _read_regular_file_stably(path: Path, expected: os.stat_result) -> bytes:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise InstallGuardError(f"signed app file could not be opened without following links: {path}") from error
    try:
        opened = os.fstat(descriptor)
        if _identity(opened) != _identity(expected) or not stat.S_ISREG(opened.st_mode):
            raise InstallGuardError(f"signed app file changed while its subject was sampled: {path}")
        result = bytearray()
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            result.extend(chunk)
        final = os.fstat(descriptor)
        if _identity(final) != _identity(opened) or len(result) != opened.st_size:
            raise InstallGuardError(f"signed app file changed during subject sampling: {path}")
        return bytes(result)
    finally:
        os.close(descriptor)


def bundle_subject(app: Path) -> str:
    """Return one deterministic SHA-256 over the current non-followed app tree."""

    app = Path(os.path.abspath(os.fspath(app)))
    try:
        root_metadata = app.lstat()
    except OSError as error:
        raise InstallGuardError(f"signed app bundle is unavailable: {app}") from error
    if not stat.S_ISDIR(root_metadata.st_mode) or stat.S_ISLNK(root_metadata.st_mode):
        raise InstallGuardError("signed app install subject must be one real directory, not a symlink")

    hasher = hashlib.sha256()
    hasher.update(b"nembra-capture-signed-app-install-subject-v1\0")
    _record(hasher, b"R", b".", root_metadata, b"")

    for current_raw, directory_names, file_names in os.walk(app, topdown=True, followlinks=False):
        directory_names.sort()
        file_names.sort()
        current = Path(current_raw)
        retained_directories: list[str] = []

        for name in directory_names:
            path = current / name
            try:
                metadata = path.lstat()
            except OSError as error:
                raise InstallGuardError(f"signed app directory entry disappeared during sampling: {path}") from error
            relative = path.relative_to(app).as_posix().encode("utf-8")
            if stat.S_ISLNK(metadata.st_mode):
                try:
                    target = os.readlink(path).encode("utf-8")
                except OSError as error:
                    raise InstallGuardError(f"signed app symlink changed during sampling: {path}") from error
                _record(hasher, b"L", relative, metadata, target)
            elif stat.S_ISDIR(metadata.st_mode):
                _record(hasher, b"D", relative, metadata, b"")
                retained_directories.append(name)
            else:
                raise InstallGuardError(f"signed app contains unsupported directory entry: {path}")
        directory_names[:] = retained_directories

        for name in file_names:
            path = current / name
            try:
                metadata = path.lstat()
            except OSError as error:
                raise InstallGuardError(f"signed app file entry disappeared during sampling: {path}") from error
            relative = path.relative_to(app).as_posix().encode("utf-8")
            if stat.S_ISLNK(metadata.st_mode):
                try:
                    target = os.readlink(path).encode("utf-8")
                except OSError as error:
                    raise InstallGuardError(f"signed app symlink changed during sampling: {path}") from error
                _record(hasher, b"L", relative, metadata, target)
            elif stat.S_ISREG(metadata.st_mode):
                payload_digest = hashlib.sha256(_read_regular_file_stably(path, metadata)).digest()
                _record(hasher, b"F", relative, metadata, payload_digest)
            else:
                raise InstallGuardError(f"signed app contains unsupported file entry: {path}")

    try:
        final_root = app.lstat()
    except OSError as error:
        raise InstallGuardError("signed app root disappeared during subject sampling") from error
    if _identity(final_root) != _identity(root_metadata):
        raise InstallGuardError("signed app root changed during subject sampling")
    return hasher.hexdigest()


class EventBackend(Protocol):
    def register(self, descriptor: int) -> None: ...
    def events(self, timeout: float) -> Sequence[object]: ...
    def close(self) -> None: ...


class KqueueVnodeBackend:
    """macOS vnode watcher used only for the physical signed-app install window."""

    def __init__(self) -> None:
        required = (
            "kqueue",
            "kevent",
            "KQ_FILTER_VNODE",
            "KQ_EV_ADD",
            "KQ_EV_ENABLE",
            "KQ_EV_CLEAR",
            "KQ_NOTE_DELETE",
            "KQ_NOTE_WRITE",
            "KQ_NOTE_EXTEND",
            "KQ_NOTE_LINK",
            "KQ_NOTE_RENAME",
            "KQ_NOTE_REVOKE",
        )
        missing = [name for name in required if not hasattr(select, name)]
        if missing:
            raise InstallGuardError("macOS kqueue vnode monitoring is unavailable: " + ", ".join(missing))
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
        self._queue.control(
            [
                select.kevent(
                    descriptor,
                    filter=select.KQ_FILTER_VNODE,
                    flags=select.KQ_EV_ADD | select.KQ_EV_ENABLE | select.KQ_EV_CLEAR,
                    fflags=self._fflags,
                )
            ],
            0,
            0,
        )

    def events(self, timeout: float) -> Sequence[object]:
        return self._queue.control(None, 256, timeout)

    def close(self) -> None:
        self._queue.close()


def watch_paths(app: Path) -> tuple[Path, ...]:
    """Return parent + every real bundle entry whose mutation can change install bytes."""

    app = Path(os.path.abspath(os.fspath(app)))
    if not app.is_dir() or app.is_symlink():
        raise InstallGuardError("signed app install subject must be one real directory")
    parent = app.parent
    if not parent.is_dir() or parent.is_symlink():
        raise InstallGuardError("signed app parent must be one real directory")

    paths: set[Path] = {parent, app}
    for current_raw, directory_names, file_names in os.walk(app, topdown=True, followlinks=False):
        directory_names.sort()
        file_names.sort()
        current = Path(current_raw)
        for name in directory_names:
            candidate = current / name
            if candidate.is_symlink():
                continue
            paths.add(candidate)
        for name in file_names:
            candidate = current / name
            if candidate.is_symlink():
                continue
            paths.add(candidate)
    return tuple(sorted(paths, key=lambda path: (len(path.parts), str(path))))


def _open_watched(paths: Iterable[Path], backend: EventBackend) -> tuple[tuple[int, Path], ...]:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    opened: list[tuple[int, Path]] = []
    try:
        for path in paths:
            try:
                before = path.lstat()
                descriptor = os.open(path, flags)
            except OSError as error:
                raise InstallGuardError(f"signed app custody path could not be opened: {path}") from error
            try:
                after = os.fstat(descriptor)
                if _identity(before) != _identity(after):
                    raise InstallGuardError(f"signed app custody path changed while monitoring armed: {path}")
                if not (stat.S_ISDIR(after.st_mode) or stat.S_ISREG(after.st_mode)):
                    raise InstallGuardError(f"signed app custody path is not one real file/directory: {path}")
                backend.register(descriptor)
            except Exception:
                os.close(descriptor)
                raise
            opened.append((descriptor, path))
        return tuple(opened)
    except Exception:
        for descriptor, _ in opened:
            try:
                os.close(descriptor)
            except OSError:
                pass
        raise


def _describe_events(events: Sequence[object], watched: Sequence[tuple[int, Path]]) -> str:
    by_descriptor = {descriptor: path for descriptor, path in watched}
    rendered: list[str] = []
    for event in events:
        descriptor = int(getattr(event, "ident", -1))
        flags = int(getattr(event, "fflags", 0))
        rendered.append(f"{by_descriptor.get(descriptor, '<unknown>')} (flags=0x{flags:x})")
    return "; ".join(rendered)


def _stop_process(process: subprocess.Popen[bytes] | subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def run_guarded_command(
    app: Path,
    command: Sequence[str],
    *,
    backend_factory: Callable[[], EventBackend] = KqueueVnodeBackend,
    popen_factory: Callable[..., subprocess.Popen] = subprocess.Popen,
    poll_interval: float = 0.05,
) -> int:
    if not command:
        raise InstallGuardError("no signed-app verification/install command was supplied")

    app = Path(os.path.abspath(os.fspath(app)))
    initial_subject = bundle_subject(app)
    initial_root = _identity(app.lstat())
    backend = backend_factory()
    watched: tuple[tuple[int, Path], ...] = ()
    process: subprocess.Popen | None = None
    try:
        watched = _open_watched(watch_paths(app), backend)
        armed_subject = bundle_subject(app)
        if armed_subject != initial_subject or _identity(app.lstat()) != initial_root:
            raise InstallGuardError("signed app changed while install-window custody was armed")
        queued = backend.events(0)
        if queued:
            raise InstallGuardError(
                "signed app mutation was observed before verification/install admission: "
                + _describe_events(queued, watched)
            )

        process = popen_factory(list(command))
        while process.poll() is None:
            events = backend.events(poll_interval)
            if events:
                _stop_process(process)
                raise InstallGuardError(
                    "signed app mutation was observed during verification/install: "
                    + _describe_events(events, watched)
                )

        trailing = backend.events(0)
        if trailing:
            raise InstallGuardError(
                "signed app mutation was observed at verification/install completion: "
                + _describe_events(trailing, watched)
            )
        if _identity(app.lstat()) != initial_root or bundle_subject(app) != initial_subject:
            raise InstallGuardError("signed app subject changed across the guarded verification/install window")
        trailing = backend.events(0)
        if trailing:
            raise InstallGuardError(
                "signed app mutation was observed during final install-subject verification: "
                + _describe_events(trailing, watched)
            )
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


def _parse_args(argv: Sequence[str]) -> tuple[Path, list[str]]:
    parser = argparse.ArgumentParser(
        description="Keep one signed Capture.app stable while a child verifies and installs it."
    )
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(list(argv))
    command = list(args.command)
    if command and command[0] == "--":
        command = command[1:]
    return args.app, command


def main(argv: Sequence[str] | None = None) -> int:
    try:
        app, command = _parse_args(sys.argv[1:] if argv is None else argv)
        return run_guarded_command(app, command)
    except InstallGuardError as error:
        print(f"ERROR: signed-app install custody rejected candidate: {error}", file=sys.stderr)
        return 76
    except OSError as error:
        print(f"ERROR: signed-app install custody failed closed: {error}", file=sys.stderr)
        return 77


if __name__ == "__main__":
    raise SystemExit(main())

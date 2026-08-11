#!/usr/bin/env python3
"""Final-GO whole-tree atomicity successor for Nembra Capture.

This child executes the exact reviewed #2921 Final-GO implementation from its
accepted Git blob and strengthens only candidate-tree admission. Every tracked
directory and regular-file subject is placed under continuous OS mutation
observation before the first accepted physical-byte admission. Linux CI uses
inotify; the physical macOS field path uses kqueue vnode events.

The guard deliberately fails closed on any mutation event or identity drift
while the inherited raw-tree/descriptor audit is running. Display, BLE/Tuya,
credentials, telemetry, signing, install, and physical procedure semantics are
unchanged.
"""
from __future__ import annotations

import contextlib
import ctypes
import errno
import hashlib
import os
import select
import stat
import struct
import subprocess
import sys
import types
from pathlib import Path, PurePosixPath
from typing import Any, Iterator, Sequence

PARENT_COMMIT = "471cc025b332f4df8b43a98d709710aeb4e0698f"
PARENT_PATH = "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
PARENT_BLOB = "48ce4bd8f933ae062eaaadd0d017d13c781a8c02"
MAX_PARENT_BYTES = 8 * 1024 * 1024


def _closed_git_environment() -> dict[str, str]:
    return {
        "PATH": "/usr/bin:/bin",
        "HOME": "/tmp",
        "LANG": "C",
        "LC_ALL": "C",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_OPTIONAL_LOCKS": "0",
    }


def _git_blob_oid(payload: bytes) -> str:
    header = b"blob " + str(len(payload)).encode("ascii") + b"\0"
    return hashlib.sha1(header + payload).hexdigest()


def _load_exact_parent() -> types.ModuleType:
    root = Path(__file__).resolve().parents[2]
    git_dir = root / ".git"
    try:
        metadata = git_dir.lstat()
    except OSError as error:
        raise RuntimeError("Final-GO atomic successor requires one real Git directory") from error
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        raise RuntimeError("Final-GO atomic successor Git directory is not a real directory")

    process = subprocess.Popen(
        ["/usr/bin/git", f"--git-dir={git_dir}", "cat-file", "blob", PARENT_BLOB],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        env=_closed_git_environment(),
    )
    if process.stdout is None:
        raise RuntimeError("Final-GO parent Git capture pipe unavailable")
    try:
        payload = process.stdout.read(MAX_PARENT_BYTES + 1)
    finally:
        process.stdout.close()
    if len(payload) > MAX_PARENT_BYTES:
        process.kill()
        process.wait()
        raise RuntimeError("Final-GO parent source exceeds bounded capture limit")
    if process.wait() != 0:
        raise RuntimeError("Final-GO parent Git blob capture failed")
    if _git_blob_oid(payload) != PARENT_BLOB:
        raise RuntimeError("Final-GO parent Git lookup returned bytes outside accepted identity")

    module = types.ModuleType("nembra_final_go_parent_2921")
    module.__file__ = str(Path(__file__).resolve())
    module.__nembra_atomic_parent_commit__ = PARENT_COMMIT
    module.__nembra_atomic_parent_blob__ = PARENT_BLOB
    filename = f"git:{PARENT_COMMIT}:{PARENT_PATH}"
    try:
        exec(compile(payload, filename, "exec", dont_inherit=True), module.__dict__)
    except Exception as error:
        raise RuntimeError("accepted #2921 Final-GO parent could not execute") from error
    return module


_parent = _load_exact_parent()

# Preserve the reviewed parent API. The successor overrides only the candidate
# audit below, then installs that override into the exact parent module so all
# inherited authority callers use the strengthened boundary.
for _name, _value in tuple(_parent.__dict__.items()):
    if not _name.startswith("__") and _name not in globals():
        globals()[_name] = _value


class _MutationBackend:
    def register(self, path: Path, descriptor: int) -> None:
        raise NotImplementedError

    def events(self) -> Sequence[object]:
        raise NotImplementedError

    def close(self) -> None:
        raise NotImplementedError


class _KqueueMutationBackend(_MutationBackend):
    """macOS vnode mutation observer for physical Final-GO."""

    def __init__(self) -> None:
        required = (
            "kqueue", "kevent", "KQ_FILTER_VNODE", "KQ_EV_ADD", "KQ_EV_ENABLE",
            "KQ_EV_CLEAR", "KQ_NOTE_DELETE", "KQ_NOTE_WRITE", "KQ_NOTE_EXTEND",
            "KQ_NOTE_ATTRIB", "KQ_NOTE_LINK", "KQ_NOTE_RENAME", "KQ_NOTE_REVOKE",
        )
        missing = [name for name in required if not hasattr(select, name)]
        if missing:
            raise RuntimeError("Final-GO kqueue vnode monitoring unavailable: " + ", ".join(missing))
        self._queue = select.kqueue()
        self._flags = (
            select.KQ_NOTE_DELETE
            | select.KQ_NOTE_WRITE
            | select.KQ_NOTE_EXTEND
            | select.KQ_NOTE_ATTRIB
            | select.KQ_NOTE_LINK
            | select.KQ_NOTE_RENAME
            | select.KQ_NOTE_REVOKE
        )

    def register(self, path: Path, descriptor: int) -> None:
        del path
        event = select.kevent(
            descriptor,
            filter=select.KQ_FILTER_VNODE,
            flags=select.KQ_EV_ADD | select.KQ_EV_ENABLE | select.KQ_EV_CLEAR,
            fflags=self._flags,
        )
        self._queue.control([event], 0, 0)

    def events(self) -> Sequence[object]:
        return self._queue.control(None, 1024, 0)

    def close(self) -> None:
        self._queue.close()


class _InotifyMutationBackend(_MutationBackend):
    """Linux mutation observer used by exact-head Final-GO CI."""

    _IN_MODIFY = 0x00000002
    _IN_ATTRIB = 0x00000004
    _IN_CLOSE_WRITE = 0x00000008
    _IN_MOVED_FROM = 0x00000040
    _IN_MOVED_TO = 0x00000080
    _IN_CREATE = 0x00000100
    _IN_DELETE = 0x00000200
    _IN_DELETE_SELF = 0x00000400
    _IN_MOVE_SELF = 0x00000800
    _IN_UNMOUNT = 0x00002000
    _IN_Q_OVERFLOW = 0x00004000
    _IN_IGNORED = 0x00008000
    _IN_DONT_FOLLOW = 0x02000000
    _MASK = (
        _IN_MODIFY | _IN_ATTRIB | _IN_CLOSE_WRITE | _IN_MOVED_FROM | _IN_MOVED_TO
        | _IN_CREATE | _IN_DELETE | _IN_DELETE_SELF | _IN_MOVE_SELF | _IN_UNMOUNT
        | _IN_Q_OVERFLOW | _IN_IGNORED | _IN_DONT_FOLLOW
    )

    def __init__(self) -> None:
        libc = ctypes.CDLL(None, use_errno=True)
        if not hasattr(libc, "inotify_init1") or not hasattr(libc, "inotify_add_watch"):
            raise RuntimeError("Final-GO inotify monitoring is unavailable")
        libc.inotify_init1.argtypes = [ctypes.c_int]
        libc.inotify_init1.restype = ctypes.c_int
        libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
        libc.inotify_add_watch.restype = ctypes.c_int
        self._libc = libc
        flags = os.O_NONBLOCK | getattr(os, "O_CLOEXEC", 0)
        descriptor = libc.inotify_init1(flags)
        if descriptor < 0:
            code = ctypes.get_errno()
            raise RuntimeError(f"Final-GO inotify initialization failed: errno {code}")
        self._descriptor = descriptor
        self._paths: dict[int, str] = {}

    def register(self, path: Path, descriptor: int) -> None:
        del descriptor
        wd = self._libc.inotify_add_watch(
            self._descriptor, os.fsencode(path), ctypes.c_uint32(self._MASK)
        )
        if wd < 0:
            code = ctypes.get_errno()
            raise RuntimeError(f"Final-GO inotify watch failed for {path}: errno {code}")
        self._paths[int(wd)] = str(path)

    def events(self) -> Sequence[object]:
        events: list[tuple[str, int, str]] = []
        header = struct.Struct("iIII")
        while True:
            try:
                payload = os.read(self._descriptor, 65536)
            except BlockingIOError:
                break
            except OSError as error:
                if error.errno in {errno.EAGAIN, errno.EWOULDBLOCK}:
                    break
                raise RuntimeError("Final-GO inotify event read failed") from error
            if not payload:
                break
            offset = 0
            while offset + header.size <= len(payload):
                wd, mask, _cookie, length = header.unpack_from(payload, offset)
                offset += header.size
                name_raw = payload[offset:offset + length]
                offset += length
                name = name_raw.split(b"\0", 1)[0].decode("utf-8", "replace")
                events.append((self._paths.get(wd, "<unknown>"), int(mask), name))
            if offset != len(payload):
                raise RuntimeError("Final-GO inotify event stream was malformed")
        return events

    def close(self) -> None:
        if self._descriptor >= 0:
            os.close(self._descriptor)
            self._descriptor = -1


def _backend() -> _MutationBackend:
    if sys.platform == "darwin":
        return _KqueueMutationBackend()
    if sys.platform.startswith("linux"):
        return _InotifyMutationBackend()
    raise RuntimeError("Final-GO whole-tree mutation custody is unavailable on this platform")


def _identity(metadata: os.stat_result) -> tuple[int, ...]:
    return (
        metadata.st_dev, metadata.st_ino, metadata.st_mode, metadata.st_uid,
        metadata.st_gid, metadata.st_nlink, metadata.st_size,
        metadata.st_mtime_ns, metadata.st_ctime_ns,
    )


class _WholeTreeMutationGuard:
    def __init__(self, root: Path, entries: dict[str, tuple[bytes, str]]) -> None:
        self.root = root
        self.entries = entries
        self.backend = _backend()
        self.opened: list[tuple[int, Path, tuple[int, ...]]] = []
        self.symlinks: dict[Path, tuple[int, ...]] = {}
        self.closed = False

    def _subjects(self) -> tuple[tuple[Path, bool], ...]:
        directories: set[Path] = {self.root}
        files: set[Path] = set()
        symlinks: set[Path] = set()
        for relative, (mode, _oid) in self.entries.items():
            parts = PurePosixPath(relative).parts
            for index in range(1, len(parts)):
                directories.add(self.root.joinpath(*parts[:index]))
            path = self.root.joinpath(*parts)
            if mode == b"120000":
                symlinks.add(path)
            else:
                files.add(path)

        # Direct field-input roots are authority-bearing namespace subjects even
        # though their internal bytes are validated by separate accepted guards.
        for relative in FIELD_INPUT_DIRECTORIES:
            directories.add(self.root / relative)
        for relative in FIELD_INPUT_FILES:
            files.add(self.root / relative)

        ordered: list[tuple[Path, bool]] = []
        for path in sorted(directories, key=lambda item: (len(item.parts), str(item))):
            ordered.append((path, True))
        for path in sorted(files, key=str):
            ordered.append((path, False))
        for path in sorted(symlinks, key=str):
            ordered.append((path, False))
        return tuple(ordered)

    def arm(self) -> None:
        cloexec = getattr(os, "O_CLOEXEC", 0)
        nofollow = getattr(os, "O_NOFOLLOW", 0)
        try:
            for path, is_directory in self._subjects():
                before = _identity(os.lstat(path))
                if stat.S_ISLNK(before[2]):
                    self.symlinks[path] = before
                    # Containing-directory custody observes symlink replacement.
                    continue
                flags = os.O_RDONLY | cloexec | nofollow
                if is_directory:
                    flags |= getattr(os, "O_DIRECTORY", 0)
                descriptor = os.open(path, flags)
                after = _identity(os.fstat(descriptor))
                if before != after:
                    os.close(descriptor)
                    raise RuntimeError("Final-GO subject changed while whole-tree custody armed: " + str(path))
                if is_directory and not stat.S_ISDIR(after[2]):
                    os.close(descriptor)
                    raise RuntimeError("Final-GO watched directory is not a directory: " + str(path))
                if not is_directory and not stat.S_ISREG(after[2]):
                    os.close(descriptor)
                    raise RuntimeError("Final-GO watched file is not a regular file: " + str(path))
                self.backend.register(path, descriptor)
                self.opened.append((descriptor, path, after))
            self.assert_stable("watch registration")
        except Exception:
            self.close()
            raise

    def _event_error(self, stage: str, events: Sequence[object]) -> RuntimeError:
        preview = "; ".join(str(item) for item in list(events)[:8])
        if len(events) > 8:
            preview += f"; +{len(events) - 8} more"
        return RuntimeError(
            "candidate whole-tree mutation observed during Final-GO "
            + stage + (": " + preview if preview else "")
        )

    def assert_stable(self, stage: str) -> None:
        events = self.backend.events()
        if events:
            raise self._event_error(stage, events)
        for descriptor, path, accepted in self.opened:
            try:
                held = _identity(os.fstat(descriptor))
                current = _identity(os.lstat(path))
            except OSError as error:
                raise RuntimeError(
                    "candidate whole-tree subject disappeared during Final-GO " + stage + ": " + str(path)
                ) from error
            if held != accepted or current != accepted:
                raise RuntimeError(
                    "candidate whole-tree subject identity drifted during Final-GO " + stage + ": " + str(path)
                )
        for path, accepted in self.symlinks.items():
            try:
                current = _identity(os.lstat(path))
            except OSError as error:
                raise RuntimeError(
                    "candidate whole-tree symlink disappeared during Final-GO " + stage + ": " + str(path)
                ) from error
            if current != accepted:
                raise RuntimeError(
                    "candidate whole-tree symlink identity drifted during Final-GO " + stage + ": " + str(path)
                )
        trailing = self.backend.events()
        if trailing:
            raise self._event_error(stage + " reproof", trailing)

    def close(self) -> None:
        if self.closed:
            return
        self.closed = True
        for descriptor, _path, _accepted in reversed(self.opened):
            try:
                os.close(descriptor)
            except OSError:
                pass
        self.opened.clear()
        try:
            self.backend.close()
        except OSError:
            pass


_physical_blob_oid = _parent._physical_blob_oid
_original_audit_candidate_tree = _parent._audit_candidate_tree
_original_candidate_git_custody = _parent._candidate_git_custody


def _run_inherited_audit_under_guard(
    root: Path,
    source: str,
    guard: _WholeTreeMutationGuard,
) -> dict[str, tuple[bytes, str]]:
    guard.assert_stable("pre-admission")
    original_parent_blob_oid = _parent._physical_blob_oid
    try:
        # Preserve #3024's deterministic post-subject scheduling seam. A test
        # replacing this successor module's callable is consumed by the exact
        # inherited audit while whole-tree watchers are already armed.
        _parent._physical_blob_oid = globals()["_physical_blob_oid"]
        result = _original_audit_candidate_tree(root, source)
    finally:
        _parent._physical_blob_oid = original_parent_blob_oid
    guard.assert_stable("post-admission")
    return result


def _audit_candidate_tree(root: Path, source: str) -> dict[str, tuple[bytes, str]]:
    """Run the exact #2921 raw audit inside whole-tree mutation custody."""
    root = root.expanduser().resolve(strict=True)
    entries = _parent._tree_entries(root, source)
    guard = _WholeTreeMutationGuard(root, entries)
    guard.arm()
    try:
        return _run_inherited_audit_under_guard(root, source, guard)
    finally:
        guard.close()


@contextlib.contextmanager
def _candidate_git_custody(base: Any, candidate_repo: Path, source: str) -> Iterator[None]:
    """Keep whole-tree custody live for the complete inherited authority window.

    #2921's original context performs the exact raw audit and installs its
    replacement-blind Git adapters. This outer guard starts before that audit
    and remains armed until the inherited build has completely consumed the
    candidate authority, eliminating the post-audit/pre-return gap identified
    by #3024.
    """
    root = candidate_repo.expanduser().resolve(strict=True)
    entries = _parent._tree_entries(root, source)
    guard = _WholeTreeMutationGuard(root, entries)
    guard.arm()
    try:
        guard.assert_stable("before inherited candidate custody")
        with _original_candidate_git_custody(base, candidate_repo, source):
            guard.assert_stable("after inherited audit")
            yield
            guard.assert_stable("inherited authority completion")
        guard.assert_stable("candidate custody release")
    finally:
        guard.close()


_parent._audit_candidate_tree = _audit_candidate_tree
_parent._candidate_git_custody = _candidate_git_custody


def build(*args: Any, **kwargs: Any) -> dict[str, Any]:
    return _parent.build(*args, **kwargs)


def __getattr__(name: str) -> Any:
    return getattr(_parent, name)


if __name__ == "__main__":
    raise SystemExit(
        "This whole-tree Final-GO control extension is exercised by its exact-head workflow; "
        "physical publication remains delegated to the sealed parent issuer."
    )

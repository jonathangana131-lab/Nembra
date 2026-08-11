#!/usr/bin/env python3
"""Final-GO whole-tree mutation custody successor.

This child keeps the accepted #2921 per-object and descriptor-bound candidate
proofs, but adds a kernel-backed mutation exclusion oracle around the complete
candidate authority window. A tracked subject that changes after one accepted
read can no longer be restored and silently promoted: any vnode/inotify event,
watch invalidation, overflow, or end-of-window identity drift fails closed.

The accepted parent is executed only from its pinned Git blob. No mutable sibling
module becomes authority.
"""
from __future__ import annotations

import contextlib
import ctypes
import hashlib
import os
import select
import stat
import struct
import subprocess
import types
from pathlib import Path, PurePosixPath
from typing import Any, Iterator

PARENT_SOURCE = "471cc025b332f4df8b43a98d709710aeb4e0698f"
PARENT_MODULE_PATH = "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
PARENT_MODULE_GIT_BLOB = "48ce4bd8f933ae062eaaadd0d017d13c781a8c02"
MAX_PARENT_BYTES = 4 * 1024 * 1024

# Linux inotify constants from <sys/inotify.h>.
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
_IN_ONLYDIR = 0x01000000
_IN_DONT_FOLLOW = 0x02000000
_IN_MASK = (
    _IN_MODIFY
    | _IN_ATTRIB
    | _IN_CLOSE_WRITE
    | _IN_MOVED_FROM
    | _IN_MOVED_TO
    | _IN_CREATE
    | _IN_DELETE
    | _IN_DELETE_SELF
    | _IN_MOVE_SELF
    | _IN_UNMOUNT
    | _IN_Q_OVERFLOW
    | _IN_IGNORED
)
_IN_EVENT = struct.Struct("iIII")


def _repo_root() -> Path:
    root = Path(__file__).resolve(strict=True).parents[2]
    marker = root / ".git"
    metadata = os.lstat(marker)
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        raise RuntimeError("whole-tree Final-GO parent requires one real repository .git directory")
    return root


def _accepted_parent_payload() -> bytes:
    root = _repo_root()
    git_dir = root / ".git"
    env = {
        "PATH": "/usr/bin:/bin",
        "HOME": "/tmp",
        "LANG": "C",
        "LC_ALL": "C",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_OPTIONAL_LOCKS": "0",
    }
    try:
        process = subprocess.Popen(
            ["/usr/bin/git", f"--git-dir={git_dir}", "cat-file", "blob", PARENT_MODULE_GIT_BLOB],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=env,
        )
        if process.stdout is None:
            raise RuntimeError("accepted Final-GO parent capture pipe unavailable")
        payload = process.stdout.read(MAX_PARENT_BYTES + 1)
        if len(payload) > MAX_PARENT_BYTES:
            process.kill()
            process.wait()
            raise RuntimeError("accepted Final-GO parent exceeds bounded capture limit")
        if process.wait() != 0:
            raise RuntimeError("accepted Final-GO parent Git blob unavailable")
    except OSError as error:
        raise RuntimeError("accepted Final-GO parent Git blob capture failed") from error
    finally:
        if "process" in locals() and process.stdout is not None:
            process.stdout.close()

    header = b"blob " + str(len(payload)).encode("ascii") + b"\0"
    if hashlib.sha1(header + payload).hexdigest() != PARENT_MODULE_GIT_BLOB:
        raise RuntimeError("accepted Final-GO parent returned bytes outside pinned blob identity")
    return payload


def _load_parent() -> types.ModuleType:
    payload = _accepted_parent_payload()
    module = types.ModuleType("nembra_final_go_parent_2921")
    module.__file__ = str(Path(__file__).resolve(strict=True))
    module.__nembra_accepted_control_source__ = PARENT_SOURCE
    module.__nembra_accepted_control_blob__ = PARENT_MODULE_GIT_BLOB
    filename = f"git:{PARENT_SOURCE}:{PARENT_MODULE_PATH}"
    try:
        exec(compile(payload, filename, "exec", dont_inherit=True), module.__dict__)
    except Exception as error:
        raise RuntimeError("accepted #2921 Final-GO parent could not execute") from error
    return module


_parent = _load_parent()
_raw_parent_audit = _parent._audit_candidate_tree
_raw_parent_candidate_custody = _parent._candidate_git_custody
_raw_parent_physical_blob_oid = _parent._physical_blob_oid


def _stable_stat(metadata: os.stat_result) -> tuple[int, ...]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_uid,
        metadata.st_gid,
        metadata.st_nlink,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _watch_subjects(
    root: Path, entries: dict[str, tuple[bytes, str]]
) -> list[tuple[Path, tuple[int, ...], bool]]:
    """Capture every tracked leaf plus every namespace directory needed to reach it."""
    root = root.expanduser().resolve(strict=True)
    relative_subjects: dict[str, bool] = {"": True}
    for relative, (mode, _) in entries.items():
        parts = PurePosixPath(relative).parts
        if not parts or any(part in {"", ".", ".."} for part in parts):
            raise RuntimeError("whole-tree Final-GO tracked path is unsafe: " + relative)
        for index in range(1, len(parts)):
            relative_subjects[PurePosixPath(*parts[:index]).as_posix()] = True
        # Symlinks are immutable in place; their parent directory catches replacement.
        if mode != b"120000":
            relative_subjects[relative] = False

    subjects: list[tuple[Path, tuple[int, ...], bool]] = []
    for relative in sorted(relative_subjects, key=lambda item: (item.count("/"), item)):
        path = root if not relative else root / relative
        try:
            metadata = os.lstat(path)
        except OSError as error:
            raise RuntimeError(
                "whole-tree Final-GO watch subject unavailable: " + (relative or ".")
            ) from error
        is_directory = relative_subjects[relative]
        if is_directory:
            if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
                raise RuntimeError(
                    "whole-tree Final-GO namespace subject is not one real directory: "
                    + (relative or ".")
                )
        else:
            if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
                raise RuntimeError(
                    "whole-tree Final-GO payload watch subject is not one real regular file: "
                    + relative
                )
        subjects.append((path, _stable_stat(metadata), is_directory))
    return subjects


class _LinuxInotify:
    def __init__(self) -> None:
        self.fd: int | None = None
        self._libc: Any | None = None
        self._watches: dict[int, str] = {}

    def arm(self, subjects: list[tuple[Path, tuple[int, ...], bool]]) -> None:
        libc = ctypes.CDLL(None, use_errno=True)
        init = libc.inotify_init1
        init.argtypes = [ctypes.c_int]
        init.restype = ctypes.c_int
        add = libc.inotify_add_watch
        add.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
        add.restype = ctypes.c_int
        fd = init(os.O_NONBLOCK | getattr(os, "O_CLOEXEC", 0))
        if fd < 0:
            error = ctypes.get_errno()
            raise RuntimeError(f"whole-tree Final-GO inotify init failed: errno {error}")
        self.fd = fd
        self._libc = libc
        try:
            for path, _, is_directory in subjects:
                mask = _IN_MASK | _IN_DONT_FOLLOW | (_IN_ONLYDIR if is_directory else 0)
                wd = add(fd, os.fsencode(path), mask)
                if wd < 0:
                    error = ctypes.get_errno()
                    raise RuntimeError(
                        f"whole-tree Final-GO inotify watch failed for {path}: errno {error}"
                    )
                self._watches[wd] = str(path)
        except Exception:
            self.close()
            raise

    def events(self) -> list[str]:
        if self.fd is None:
            raise RuntimeError("whole-tree Final-GO inotify backend is not armed")
        found: list[str] = []
        while True:
            try:
                payload = os.read(self.fd, 1 << 20)
            except BlockingIOError:
                break
            except OSError as error:
                raise RuntimeError("whole-tree Final-GO inotify read failed") from error
            if not payload:
                break
            offset = 0
            while offset < len(payload):
                if len(payload) - offset < _IN_EVENT.size:
                    raise RuntimeError("whole-tree Final-GO inotify event stream is truncated")
                wd, mask, _, name_len = _IN_EVENT.unpack_from(payload, offset)
                offset += _IN_EVENT.size
                if offset + name_len > len(payload):
                    raise RuntimeError("whole-tree Final-GO inotify event name is truncated")
                raw_name = payload[offset : offset + name_len].split(b"\0", 1)[0]
                offset += name_len
                subject = self._watches.get(wd, f"watch:{wd}")
                suffix = os.fsdecode(raw_name) if raw_name else ""
                if suffix:
                    subject = subject + "/" + suffix
                found.append(f"{subject}:0x{mask:08x}")
        return found

    def close(self) -> None:
        if self.fd is not None:
            try:
                os.close(self.fd)
            except OSError:
                pass
            self.fd = None


class _DarwinKqueue:
    def __init__(self) -> None:
        self.queue: Any | None = None
        self._fds: dict[int, str] = {}

    def arm(self, subjects: list[tuple[Path, tuple[int, ...], bool]]) -> None:
        required = (
            "KQ_FILTER_VNODE",
            "KQ_EV_ADD",
            "KQ_EV_ENABLE",
            "KQ_EV_CLEAR",
            "KQ_NOTE_WRITE",
            "KQ_NOTE_DELETE",
            "KQ_NOTE_RENAME",
            "KQ_NOTE_ATTRIB",
            "KQ_NOTE_EXTEND",
            "KQ_NOTE_REVOKE",
        )
        missing = [name for name in required if not hasattr(select, name)]
        if missing or not hasattr(select, "kqueue") or not hasattr(select, "kevent"):
            raise RuntimeError(
                "whole-tree Final-GO Darwin vnode custody unavailable: " + ",".join(missing)
            )
        queue = select.kqueue()
        self.queue = queue
        fflags = 0
        for name in required[4:]:
            fflags |= int(getattr(select, name))
        try:
            for path, _, is_directory in subjects:
                flags = getattr(os, "O_EVTONLY", os.O_RDONLY) | getattr(os, "O_CLOEXEC", 0)
                flags |= getattr(os, "O_NOFOLLOW", 0)
                if is_directory:
                    flags |= getattr(os, "O_DIRECTORY", 0)
                fd = os.open(path, flags)
                self._fds[fd] = str(path)
                event = select.kevent(
                    fd,
                    filter=select.KQ_FILTER_VNODE,
                    flags=select.KQ_EV_ADD | select.KQ_EV_ENABLE | select.KQ_EV_CLEAR,
                    fflags=fflags,
                )
                queue.control([event], 0, 0)
        except Exception:
            self.close()
            raise

    def events(self) -> list[str]:
        if self.queue is None:
            raise RuntimeError("whole-tree Final-GO kqueue backend is not armed")
        maximum = max(1, len(self._fds))
        try:
            events = self.queue.control(None, maximum, 0)
        except OSError as error:
            raise RuntimeError("whole-tree Final-GO kqueue read failed") from error
        return [
            f"{self._fds.get(int(event.ident), f'fd:{event.ident}')}:0x{int(event.fflags):08x}"
            for event in events
        ]

    def close(self) -> None:
        for fd in list(self._fds):
            try:
                os.close(fd)
            except OSError:
                pass
        self._fds.clear()
        if self.queue is not None:
            try:
                self.queue.close()
            except OSError:
                pass
            self.queue = None


class _WholeTreeMutationGuard:
    """Fail-closed kernel event custody for the accepted tracked physical tree."""

    def __init__(self, root: Path, entries: dict[str, tuple[bytes, str]]) -> None:
        self.root = root.expanduser().resolve(strict=True)
        self.subjects = _watch_subjects(self.root, entries)
        if os.uname().sysname == "Darwin":
            self.backend: Any = _DarwinKqueue()
        elif os.uname().sysname == "Linux":
            self.backend = _LinuxInotify()
        else:
            raise RuntimeError("whole-tree Final-GO mutation custody is unsupported on this platform")
        self._armed = False

    def __enter__(self) -> "_WholeTreeMutationGuard":
        self.backend.arm(self.subjects)
        self._armed = True
        self.assert_clean("arming")
        return self

    def assert_clean(self, phase: str) -> None:
        if not self._armed:
            raise RuntimeError("whole-tree Final-GO mutation custody is not armed")
        events = self.backend.events()
        drift: list[str] = []
        for path, baseline, _ in self.subjects:
            try:
                current = _stable_stat(os.lstat(path))
            except OSError:
                drift.append(str(path) + ":missing")
                continue
            if current != baseline:
                drift.append(str(path) + ":identity")
        if events or drift:
            details = ", ".join((events + drift)[:8])
            raise RuntimeError(
                f"candidate physical tree changed during Final-GO {phase} custody"
                + (": " + details if details else "")
            )

    def __exit__(self, exc_type: Any, exc: Any, traceback: Any) -> bool:
        try:
            if exc_type is None:
                self.assert_clean("acceptance")
        finally:
            self.backend.close()
            self._armed = False
        return False


# Keep the adversarial scheduling seam used by #3024/#3030 pointed at this
# child global, while the actual default implementation remains the exact
# accepted parent primitive.
_physical_blob_oid = _raw_parent_physical_blob_oid


def _parent_physical_blob_oid_forward(
    root: Path, relative: str, mode: bytes, accepted_oid: str
) -> str:
    return _physical_blob_oid(root, relative, mode, accepted_oid)


_parent._physical_blob_oid = _parent_physical_blob_oid_forward


def _entries_for_guard(root: Path, source: str) -> dict[str, tuple[bytes, str]]:
    return _parent._tree_entries(root.expanduser().resolve(strict=True), source.lower())


def _audit_candidate_tree(root: Path, source: str) -> dict[str, tuple[bytes, str]]:
    """Run the exact #2921 audit under continuous tracked-tree mutation custody."""
    entries = _entries_for_guard(root, source)
    with _WholeTreeMutationGuard(root, entries) as guard:
        result = _raw_parent_audit(root, source)
        guard.assert_clean("audit")
        return result


_parent._audit_candidate_tree = _audit_candidate_tree


@contextlib.contextmanager
def _candidate_git_custody(
    base: Any, candidate_repo: Path, source: str
) -> Iterator[None]:
    """Keep whole-tree custody armed through the inherited candidate authority window."""
    entries = _entries_for_guard(candidate_repo, source)
    with _WholeTreeMutationGuard(candidate_repo, entries) as guard:
        with _raw_parent_candidate_custody(base, candidate_repo, source):
            yield
        guard.assert_clean("candidate authority")


_parent._candidate_git_custody = _candidate_git_custody


def build(*args: Any, **kwargs: Any) -> dict[str, Any]:
    return _parent.build(*args, **kwargs)


def __getattr__(name: str) -> Any:
    return getattr(_parent, name)


if __name__ == "__main__":
    raise SystemExit(
        "Whole-tree Final-GO custody is exercised by exact-head acceptance workflows; "
        "this module creates no physical authorization by itself."
    )

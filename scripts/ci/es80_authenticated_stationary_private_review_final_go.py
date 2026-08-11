#!/usr/bin/env python3
"""Final-GO successor with continuous tracked-tree mutation custody.

The exact #2921 implementation remains the semantic parent and is executed from
its immutable Git blob. This successor adds one authority property only: from
before the first physical tracked-tree audit until candidate authority returns,
every admitted tracked regular file and directory remains under a kernel vnode
mutation watch. Any write, attribute change, link change, create/delete,
rename/replacement, unmount/revoke, or watcher overflow fails closed.

This closes the whole-tree gap demonstrated by #3024 and the finite-rehash gap
demonstrated by #3030 without turning another endpoint hash pass into authority.
Field-input subtrees retain their existing specialized authority contracts; this
layer protects the accepted Git-tracked candidate tree and its namespace.
"""
from __future__ import annotations

import contextlib
import contextvars
import ctypes
import errno
import hashlib
import os
from pathlib import Path, PurePosixPath
import select
import stat
import struct
import subprocess
import sys
import threading
import types
from typing import Any, Callable, Iterator, Protocol, Sequence

DIRECT_PARENT_SOURCE = "471cc025b332f4df8b43a98d709710aeb4e0698f"
DIRECT_PARENT_MODULE_PATH = "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
DIRECT_PARENT_MODULE_GIT_BLOB = "48ce4bd8f933ae062eaaadd0d017d13c781a8c02"
MAX_PARENT_BLOB_BYTES = 4 * 1024 * 1024


class _TrackedTreeCustodyError(RuntimeError):
    pass


def _closed_parent_object_environment() -> dict[str, str]:
    return {
        "PATH": "/usr/bin:/bin",
        "HOME": "/tmp",
        "LANG": "C",
        "LC_ALL": "C",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_OPTIONAL_LOCKS": "0",
        "GIT_CONFIG_COUNT": "2",
        "GIT_CONFIG_KEY_0": "core.fsmonitor",
        "GIT_CONFIG_VALUE_0": "false",
        "GIT_CONFIG_KEY_1": "core.hooksPath",
        "GIT_CONFIG_VALUE_1": "/dev/null",
    }


def _canonical_git_blob_oid(payload: bytes, accepted_oid: str) -> str:
    header = b"blob " + str(len(payload)).encode("ascii") + b"\0"
    if len(accepted_oid) == 40:
        return hashlib.sha1(header + payload).hexdigest()
    if len(accepted_oid) == 64:
        return hashlib.sha256(header + payload).hexdigest()
    raise RuntimeError("direct Final-GO parent blob has unsupported Git object width")


def _capture_direct_parent_blob(root: Path) -> bytes:
    git_dir = root / ".git"
    try:
        metadata = git_dir.lstat()
    except OSError as error:
        raise RuntimeError("direct Final-GO parent Git directory unavailable") from error
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        raise RuntimeError("direct Final-GO parent requires one real .git directory")

    process: subprocess.Popen[bytes] | None = None
    try:
        process = subprocess.Popen(
            [
                "/usr/bin/git",
                f"--git-dir={git_dir}",
                "cat-file",
                "blob",
                DIRECT_PARENT_MODULE_GIT_BLOB,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=_closed_parent_object_environment(),
        )
        if process.stdout is None:
            raise RuntimeError("direct Final-GO parent capture pipe unavailable")
        payload = process.stdout.read(MAX_PARENT_BLOB_BYTES + 1)
        if len(payload) > MAX_PARENT_BLOB_BYTES:
            process.kill()
            process.wait()
            raise RuntimeError("direct Final-GO parent exceeds bounded blob limit")
        if process.wait() != 0:
            raise RuntimeError("direct Final-GO parent Git blob capture failed")
    except OSError as error:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        raise RuntimeError("direct Final-GO parent Git blob capture failed") from error
    finally:
        if process is not None and process.stdout is not None:
            process.stdout.close()

    if _canonical_git_blob_oid(payload, DIRECT_PARENT_MODULE_GIT_BLOB) != DIRECT_PARENT_MODULE_GIT_BLOB:
        raise RuntimeError("direct Final-GO parent Git lookup returned bytes outside accepted identity")
    return payload


def _load_direct_parent() -> types.ModuleType:
    root = Path(__file__).resolve().parents[2]
    payload = _capture_direct_parent_blob(root)
    module = types.ModuleType("nembra_final_go_parent_2921")
    module.__file__ = str(Path(__file__).resolve())
    module.__nembra_direct_parent_source__ = DIRECT_PARENT_SOURCE
    module.__nembra_direct_parent_blob__ = DIRECT_PARENT_MODULE_GIT_BLOB
    filename = f"git:{DIRECT_PARENT_SOURCE}:{DIRECT_PARENT_MODULE_PATH}"
    try:
        exec(compile(payload, filename, "exec", dont_inherit=True), module.__dict__)
    except Exception as error:
        raise RuntimeError("accepted #2921 Final-GO parent could not execute") from error
    return module


_direct_parent = _load_direct_parent()

# Preserve #2921's public compatibility surface. In particular, its inherited
# tests intentionally expect PARENT_SOURCE/_parent to keep referring to #2873.
_parent = _direct_parent._parent
generated = _direct_parent.generated
PrivateReviewGoError = _direct_parent.PrivateReviewGoError
PARENT_SOURCE = _direct_parent.PARENT_SOURCE
PARENT_MODULE_GIT_BLOB = _direct_parent.PARENT_MODULE_GIT_BLOB
FIELD_INPUT_DIRECTORIES = _direct_parent.FIELD_INPUT_DIRECTORIES
FIELD_INPUT_FILES = _direct_parent.FIELD_INPUT_FILES
review_v5 = _direct_parent.review_v5
candidate_private_authority = _direct_parent.candidate_private_authority

_PARENT_PHYSICAL_BLOB_OID = _direct_parent._physical_blob_oid
_PARENT_AUDIT_CANDIDATE_TREE = _direct_parent._audit_candidate_tree
_PARENT_CANDIDATE_GIT_CUSTODY = _direct_parent._candidate_git_custody
_PARENT_DISPATCH_LOCK = threading.RLock()


def _stable_identity(metadata: os.stat_result) -> tuple[int, ...]:
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


class _MutationBackend(Protocol):
    def register(self, descriptor: int, path: Path) -> None: ...
    def events(self, timeout: float) -> Sequence[str]: ...
    def close(self) -> None: ...


class _KqueueMutationBackend:
    """Descriptor-bound Darwin vnode watcher for the physical Final-GO host."""

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
            "KQ_NOTE_ATTRIB",
            "KQ_NOTE_LINK",
            "KQ_NOTE_RENAME",
            "KQ_NOTE_REVOKE",
        )
        missing = [name for name in required if not hasattr(select, name)]
        if missing:
            raise _TrackedTreeCustodyError(
                "Darwin tracked-tree vnode monitoring unavailable: " + ", ".join(missing)
            )
        self._queue = select.kqueue()
        self._paths: dict[int, Path] = {}
        self._fflags = (
            select.KQ_NOTE_DELETE
            | select.KQ_NOTE_WRITE
            | select.KQ_NOTE_EXTEND
            | select.KQ_NOTE_ATTRIB
            | select.KQ_NOTE_LINK
            | select.KQ_NOTE_RENAME
            | select.KQ_NOTE_REVOKE
        )

    def register(self, descriptor: int, path: Path) -> None:
        event = select.kevent(
            descriptor,
            filter=select.KQ_FILTER_VNODE,
            flags=select.KQ_EV_ADD | select.KQ_EV_ENABLE | select.KQ_EV_CLEAR,
            fflags=self._fflags,
        )
        self._queue.control([event], 0, 0)
        self._paths[descriptor] = path

    def events(self, timeout: float) -> Sequence[str]:
        pending = self._queue.control(None, max(1, len(self._paths)), timeout)
        return tuple(
            f"{self._paths.get(int(event.ident), Path('<unknown>'))} (flags=0x{int(event.fflags):x})"
            for event in pending
        )

    def close(self) -> None:
        self._queue.close()


class _InotifyMutationBackend:
    """Linux exact-inode watcher used by portable exact-head adversarial CI."""

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
    _MASK = (
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
    )
    _EVENT = struct.Struct("iIII")

    def __init__(self) -> None:
        if not sys.platform.startswith("linux"):
            raise _TrackedTreeCustodyError("Linux inotify backend requested on a non-Linux host")
        if not Path("/proc/self/fd").is_dir():
            raise _TrackedTreeCustodyError("Linux /proc/self/fd is required for descriptor-bound inotify")
        self._libc = ctypes.CDLL(None, use_errno=True)
        init = self._libc.inotify_init1
        init.argtypes = [ctypes.c_int]
        init.restype = ctypes.c_int
        self._add_watch = self._libc.inotify_add_watch
        self._add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
        self._add_watch.restype = ctypes.c_int
        flags = getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0)
        self._descriptor = int(init(flags))
        if self._descriptor < 0:
            value = ctypes.get_errno()
            raise _TrackedTreeCustodyError(
                f"Linux inotify initialization failed: errno {value}"
            )
        self._paths: dict[int, Path] = {}

    def register(self, descriptor: int, path: Path) -> None:
        # Watching /proc/self/fd/N deliberately binds inotify to the already-open
        # inode instead of resolving the attacker-mutable candidate pathname again.
        proc_subject = os.fsencode(f"/proc/self/fd/{descriptor}")
        watch = int(self._add_watch(self._descriptor, proc_subject, self._MASK))
        if watch < 0:
            value = ctypes.get_errno()
            raise _TrackedTreeCustodyError(
                f"Linux inotify could not bind admitted tracked subject {path}: errno {value}"
            )
        self._paths[watch] = path

    def events(self, timeout: float) -> Sequence[str]:
        readable, _, _ = select.select([self._descriptor], [], [], max(0.0, timeout))
        if not readable:
            return ()
        descriptions: list[str] = []
        while True:
            try:
                payload = os.read(self._descriptor, 1 << 16)
            except BlockingIOError:
                break
            except OSError as error:
                if error.errno in {errno.EAGAIN, errno.EWOULDBLOCK}:
                    break
                raise _TrackedTreeCustodyError("Linux inotify event read failed") from error
            if not payload:
                break
            offset = 0
            while offset + self._EVENT.size <= len(payload):
                watch, mask, _cookie, name_length = self._EVENT.unpack_from(payload, offset)
                offset += self._EVENT.size
                name_raw = payload[offset : offset + name_length]
                offset += name_length
                name = name_raw.split(b"\0", 1)[0]
                path = self._paths.get(watch)
                label = str(path) if path is not None else "<watch-queue>"
                if name:
                    label += "/" + os.fsdecode(name)
                descriptions.append(f"{label} (flags=0x{mask:x})")
                if mask & self._IN_Q_OVERFLOW:
                    descriptions.append("<inotify-queue-overflow>")
            if len(payload) < (1 << 16):
                # Nonblocking descriptor has been drained for the current burst.
                continue
        return tuple(descriptions)

    def close(self) -> None:
        if self._descriptor >= 0:
            os.close(self._descriptor)
            self._descriptor = -1


def _default_backend() -> _MutationBackend:
    if hasattr(select, "kqueue") and sys.platform == "darwin":
        return _KqueueMutationBackend()
    if sys.platform.startswith("linux"):
        return _InotifyMutationBackend()
    raise _TrackedTreeCustodyError(
        "continuous tracked-tree mutation custody is unavailable on this host"
    )


def _tracked_watch_subjects(
    root: Path, source: str
) -> tuple[dict[str, tuple[bytes, str]], tuple[tuple[Path, bool], ...]]:
    entries = _direct_parent._tree_entries(root, source)
    subjects: dict[Path, bool] = {root: True}
    for relative, (mode, _oid) in entries.items():
        parts = PurePosixPath(relative).parts
        if not parts or any(part in {"", ".", ".."} for part in parts):
            raise _TrackedTreeCustodyError("accepted tracked-tree path is unsafe: " + relative)
        for index in range(1, len(parts)):
            subjects[root.joinpath(*parts[:index])] = True
        if mode in {b"100644", b"100755"}:
            subjects[root.joinpath(*parts)] = False
        elif mode != b"120000":
            raise _TrackedTreeCustodyError(
                "accepted tracked-tree contains unsupported watch subject: " + relative
            )
    ordered = tuple(
        sorted(
            subjects.items(),
            key=lambda item: (len(item[0].relative_to(root).parts), str(item[0])),
        )
    )
    return entries, ordered


class _TrackedTreeCustody:
    def __init__(
        self,
        root: Path,
        source: str,
        *,
        backend_factory: Callable[[], _MutationBackend] = _default_backend,
    ) -> None:
        self.root = root.expanduser().resolve(strict=True)
        self.source = source.lower()
        self.backend = backend_factory()
        self.entries, self.subjects = _tracked_watch_subjects(self.root, self.source)
        self.opened: list[tuple[int, Path, tuple[int, ...]]] = []

    def arm(self) -> None:
        flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
        try:
            for path, is_directory in self.subjects:
                try:
                    before_metadata = os.lstat(path)
                except OSError as error:
                    raise _TrackedTreeCustodyError(
                        "tracked-tree subject disappeared before mutation custody: " + str(path)
                    ) from error
                if is_directory:
                    if not stat.S_ISDIR(before_metadata.st_mode) or stat.S_ISLNK(before_metadata.st_mode):
                        raise _TrackedTreeCustodyError(
                            "tracked-tree directory subject is not one real directory: " + str(path)
                        )
                    open_flags = flags | getattr(os, "O_DIRECTORY", 0)
                else:
                    if not stat.S_ISREG(before_metadata.st_mode) or stat.S_ISLNK(before_metadata.st_mode):
                        raise _TrackedTreeCustodyError(
                            "tracked-tree file subject is not one real regular file: " + str(path)
                        )
                    open_flags = flags
                try:
                    descriptor = os.open(path, open_flags)
                except OSError as error:
                    raise _TrackedTreeCustodyError(
                        "tracked-tree subject could not be opened for mutation custody: " + str(path)
                    ) from error
                try:
                    after_identity = _stable_identity(os.fstat(descriptor))
                    before_identity = _stable_identity(before_metadata)
                    if after_identity != before_identity:
                        raise _TrackedTreeCustodyError(
                            "tracked-tree subject changed while mutation custody was armed: " + str(path)
                        )
                    self.backend.register(descriptor, path)
                except Exception:
                    os.close(descriptor)
                    raise
                self.opened.append((descriptor, path, before_identity))

            # Registration itself is a race boundary. Rebind every pathname to
            # its held inode after every watcher is live, then reject any event
            # queued during watcher construction before physical audit begins.
            self._reprove_identities("watch registration")
            self.raise_if_mutated("watch registration")
        except Exception:
            self.close()
            raise

    def _reprove_identities(self, stage: str) -> None:
        for descriptor, path, admitted in self.opened:
            try:
                held = _stable_identity(os.fstat(descriptor))
                current = _stable_identity(os.lstat(path))
            except OSError as error:
                raise _TrackedTreeCustodyError(
                    f"tracked-tree subject disappeared during {stage}: {path}"
                ) from error
            if held != admitted or current != admitted:
                raise _TrackedTreeCustodyError(
                    f"tracked-tree namespace changed during {stage}: {path}"
                )

    def raise_if_mutated(self, stage: str) -> None:
        events = self.backend.events(0)
        if events:
            preview = "; ".join(events[:8])
            if len(events) > 8:
                preview += f"; +{len(events) - 8} more"
            raise _TrackedTreeCustodyError(
                f"tracked-tree mutation observed during {stage}: {preview}"
            )

    def prove_quiet(self, stage: str) -> None:
        self.raise_if_mutated(stage)
        self._reprove_identities(stage)
        # Keep watchers armed while identities are sampled; reject a mutation
        # that arrives during the reproof itself before authority can return.
        self.raise_if_mutated(stage + " reproof")

    def close(self) -> None:
        for descriptor, _path, _identity in reversed(self.opened):
            try:
                os.close(descriptor)
            except OSError:
                pass
        self.opened.clear()
        try:
            self.backend.close()
        except OSError:
            pass


_ACTIVE_CUSTODY: contextvars.ContextVar[_TrackedTreeCustody | None] = contextvars.ContextVar(
    "nembra_final_go_active_tracked_tree_custody", default=None
)


@contextlib.contextmanager
def _continuous_tracked_tree_custody(
    root: Path,
    source: str,
    *,
    backend_factory: Callable[[], _MutationBackend] = _default_backend,
) -> Iterator[_TrackedTreeCustody]:
    custody = _TrackedTreeCustody(root, source, backend_factory=backend_factory)
    custody.arm()
    token = _ACTIVE_CUSTODY.set(custody)
    try:
        yield custody
        custody.prove_quiet("Final-GO authority completion")
    finally:
        _ACTIVE_CUSTODY.reset(token)
        custody.close()


@contextlib.contextmanager
def _dispatch_parent_physical_reads() -> Iterator[None]:
    # #2921 itself uses scoped global adaptation for inherited authority. Keep
    # this successor equally explicit and serialize the one dynamic dispatch
    # seam so concurrent callers cannot observe a half-installed hook.
    with _PARENT_DISPATCH_LOCK:
        original = _direct_parent._physical_blob_oid

        def dispatch(
            root: Path, relative: str, mode: bytes, accepted_oid: str
        ) -> str:
            return globals()["_physical_blob_oid"](root, relative, mode, accepted_oid)

        _direct_parent._physical_blob_oid = dispatch
        try:
            yield
        finally:
            _direct_parent._physical_blob_oid = original


def _physical_blob_oid(root: Path, relative: str, mode: bytes, accepted_oid: str) -> str:
    result = _PARENT_PHYSICAL_BLOB_OID(root, relative, mode, accepted_oid)
    custody = _ACTIVE_CUSTODY.get()
    if custody is not None:
        custody.raise_if_mutated("tracked payload admission")
    return result


def _audit_candidate_tree(root: Path, source: str) -> dict[str, tuple[bytes, str]]:
    root = root.expanduser().resolve(strict=True)
    try:
        with _continuous_tracked_tree_custody(root, source) as custody:
            with _dispatch_parent_physical_reads():
                result = _PARENT_AUDIT_CANDIDATE_TREE(root, source)
                custody.prove_quiet("whole-tree physical audit")
                return result
    except _TrackedTreeCustodyError:
        raise


@contextlib.contextmanager
def _candidate_git_custody(base: Any, candidate_repo: Path, source: str) -> Iterator[None]:
    root = candidate_repo.expanduser().resolve(strict=True)
    try:
        with _continuous_tracked_tree_custody(root, source) as custody:
            with _dispatch_parent_physical_reads():
                with _PARENT_CANDIDATE_GIT_CUSTODY(base, root, source):
                    custody.prove_quiet("initial candidate authority")
                    yield
                    custody.prove_quiet("candidate authority handoff")
    except _TrackedTreeCustodyError as error:
        raise PrivateReviewGoError(str(error)) from error


def build(
    *,
    candidate_repo: Path,
    source: str,
    base_module: Any | None = None,
    **kwargs: Any,
) -> dict[str, Any]:
    base = base_module or generated._load_base_module()
    source = base.canon(source, "source")
    with _candidate_git_custody(base, candidate_repo, source), _direct_parent._current_vnode_authority():
        return _direct_parent._parent.build(
            candidate_repo=candidate_repo,
            source=source,
            base_module=base,
            **kwargs,
        )


def __getattr__(name: str) -> Any:
    return getattr(_direct_parent, name)


if __name__ == "__main__":
    raise SystemExit(
        "This exact-parent Final-GO successor is exercised by its exact-head workflows; "
        "physical publication remains NO-GO until final composed authority is accepted."
    )

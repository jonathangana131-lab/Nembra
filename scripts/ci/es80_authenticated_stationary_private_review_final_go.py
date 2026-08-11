#!/usr/bin/env python3
"""Final-GO whole-tree mutation custody successor.

The exact accepted predecessor remains the semantic implementation. This child
loads that predecessor only from an independently verified accepted Git
commit/tree/blob chain, then strengthens the physical candidate boundary with
continuous kernel mutation custody. Tracked-tree mutation events fail closed
even when a pathname is restored to accepted bytes before an endpoint reproof.
"""
from __future__ import annotations

import contextlib
import ctypes
import hashlib
import os
import resource
import select
import stat
import subprocess
import sys
import types
from pathlib import Path, PurePosixPath
from typing import Any, Iterator

PREVIOUS_SOURCE = "471cc025b332f4df8b43a98d709710aeb4e0698f"
PREVIOUS_MODULE_PATH = "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
PREVIOUS_MODULE_GIT_BLOB = "48ce4bd8f933ae062eaaadd0d017d13c781a8c02"
OID_WIDTH = 40
MAX_COMMIT_OBJECT_BYTES = 4 * 1024 * 1024
MAX_TREE_OBJECT_BYTES = 16 * 1024 * 1024
MAX_BLOB_OBJECT_BYTES = 64 * 1024 * 1024
MAX_TREE_DEPTH = 64
MAX_TREE_OBJECTS = 100_000
MAX_TRACKED_ENTRIES = 250_000
MAX_TRACKED_PATH_BYTES = 4096
MAX_MUTATION_EVENT_BYTES = 1024 * 1024


def _closed_object_environment() -> dict[str, str]:
    return {
        "PATH": "/usr/bin:/bin",
        "HOME": "/tmp",
        "LANG": "C",
        "LC_ALL": "C",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_OPTIONAL_LOCKS": "0",
        "GIT_CONFIG_COUNT": "4",
        "GIT_CONFIG_KEY_0": "core.fsmonitor",
        "GIT_CONFIG_VALUE_0": "false",
        "GIT_CONFIG_KEY_1": "core.hooksPath",
        "GIT_CONFIG_VALUE_1": "/dev/null",
        "GIT_CONFIG_KEY_2": "core.attributesFile",
        "GIT_CONFIG_VALUE_2": "/dev/null",
        "GIT_CONFIG_KEY_3": "core.excludesFile",
        "GIT_CONFIG_VALUE_3": "/dev/null",
    }


def _real_git_dir(root: Path) -> Path:
    root = root.expanduser().resolve(strict=True)
    marker = root / ".git"
    try:
        metadata = marker.lstat()
    except OSError as error:
        raise RuntimeError("candidate physical Git directory unavailable") from error
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        raise RuntimeError("candidate authority requires one real .git directory")
    try:
        resolved = marker.resolve(strict=True)
    except OSError as error:
        raise RuntimeError("candidate physical Git directory could not be resolved") from error
    if resolved.parent != root:
        raise RuntimeError("candidate physical Git directory escaped the accepted checkout")
    return resolved


def _object_oid(object_type: str, payload: bytes, accepted_oid: str) -> str:
    if object_type not in {"commit", "tree", "blob"}:
        raise RuntimeError("candidate Git object type is unsupported")
    header = object_type.encode("ascii") + b" " + str(len(payload)).encode("ascii") + b"\0"
    if len(accepted_oid) == 40:
        return hashlib.sha1(header + payload).hexdigest()
    if len(accepted_oid) == 64:
        return hashlib.sha256(header + payload).hexdigest()
    raise RuntimeError("candidate accepted Git object has unsupported width")


def _blob_oid(payload: bytes, accepted_oid: str) -> str:
    return _object_oid("blob", payload, accepted_oid)


def _capture_object_bytes(root: Path, object_type: str, oid: str, limit: int) -> bytes:
    oid = oid.lower()
    if len(oid) not in {40, 64} or any(character not in "0123456789abcdef" for character in oid):
        raise RuntimeError("candidate Git object identity is not canonical")
    if object_type not in {"commit", "tree", "blob"} or limit <= 0:
        raise RuntimeError("candidate Git object capture contract is invalid")
    git_dir = _real_git_dir(root)
    process: subprocess.Popen[bytes] | None = None
    try:
        process = subprocess.Popen(
            ["/usr/bin/git", f"--git-dir={git_dir}", "cat-file", object_type, oid],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=_closed_object_environment(),
        )
        if process.stdout is None:
            raise RuntimeError("candidate Git object capture pipe unavailable")
        payload = process.stdout.read(limit + 1)
        if len(payload) > limit:
            process.kill()
            process.wait()
            raise RuntimeError("candidate Git object exceeds bounded capture limit")
        if process.wait() != 0:
            raise RuntimeError("candidate Git object capture failed")
        return payload
    except OSError as error:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        raise RuntimeError("candidate Git object capture failed") from error
    finally:
        if process is not None and process.stdout is not None:
            process.stdout.close()


def _verified_object_bytes(root: Path, object_type: str, oid: str, limit: int) -> bytes:
    payload = _capture_object_bytes(root, object_type, oid, limit)
    if _object_oid(object_type, payload, oid) != oid.lower():
        raise RuntimeError("candidate Git object lookup returned bytes outside accepted identity")
    return payload


def _commit_tree_oid(commit_payload: bytes, source: str) -> str:
    try:
        headers = commit_payload.split(b"\n\n", 1)[0]
        tree_lines = [line for line in headers.splitlines() if line.startswith(b"tree ")]
        if len(tree_lines) != 1:
            raise ValueError("commit must carry exactly one tree header")
        tree_oid = tree_lines[0][5:].decode("ascii").lower()
    except (UnicodeDecodeError, ValueError) as error:
        raise RuntimeError("candidate accepted commit tree header is malformed") from error
    if len(tree_oid) != len(source) or any(character not in "0123456789abcdef" for character in tree_oid):
        raise RuntimeError("candidate accepted commit tree identity is invalid")
    return tree_oid


def _parse_tree_object(payload: bytes, oid_width: int) -> list[tuple[bytes, bytes, str]]:
    raw_oid_bytes = oid_width // 2
    if raw_oid_bytes not in {20, 32}:
        raise RuntimeError("candidate tree hash width is unsupported")
    entries: list[tuple[bytes, bytes, str]] = []
    offset = 0
    while offset < len(payload):
        space = payload.find(b" ", offset)
        if space <= offset:
            raise RuntimeError("candidate accepted tree mode record is malformed")
        nul = payload.find(b"\0", space + 1)
        if nul <= space + 1:
            raise RuntimeError("candidate accepted tree name record is malformed")
        oid_start = nul + 1
        oid_end = oid_start + raw_oid_bytes
        if oid_end > len(payload):
            raise RuntimeError("candidate accepted tree object identity is truncated")
        mode = payload[offset:space]
        name = payload[space + 1:nul]
        if name in {b".", b".."} or b"/" in name or not name:
            raise RuntimeError("candidate accepted tree contains unsafe path component")
        entries.append((mode, name, payload[oid_start:oid_end].hex()))
        offset = oid_end
    return entries


def _tree_entries(root: Path, source: str) -> dict[str, tuple[bytes, str]]:
    """Derive tracked leaves from one independently verified commit/tree chain."""
    source = source.lower()
    if len(source) not in {40, 64} or any(character not in "0123456789abcdef" for character in source):
        raise RuntimeError("candidate source is not a canonical Git object ID")
    commit_payload = _verified_object_bytes(root, "commit", source, MAX_COMMIT_OBJECT_BYTES)
    root_tree_oid = _commit_tree_oid(commit_payload, source)
    entries: dict[str, tuple[bytes, str]] = {}
    tree_cache: dict[str, bytes] = {}
    active_trees: set[str] = set()
    tree_objects = 0

    def walk(tree_oid: str, prefix: tuple[str, ...], depth: int) -> None:
        nonlocal tree_objects
        if depth > MAX_TREE_DEPTH:
            raise RuntimeError("candidate accepted tree exceeds recursion limit")
        if tree_oid in active_trees:
            raise RuntimeError("candidate accepted tree contains recursive object cycle")
        if tree_oid not in tree_cache:
            tree_objects += 1
            if tree_objects > MAX_TREE_OBJECTS:
                raise RuntimeError("candidate accepted tree exceeds object-count limit")
            tree_cache[tree_oid] = _verified_object_bytes(
                root, "tree", tree_oid, MAX_TREE_OBJECT_BYTES
            )
        payload = tree_cache[tree_oid]
        active_trees.add(tree_oid)
        try:
            for mode, name_raw, oid in _parse_tree_object(payload, len(source)):
                name = os.fsdecode(name_raw)
                relative_parts = prefix + (name,)
                relative = PurePosixPath(*relative_parts).as_posix()
                if len(os.fsencode(relative)) > MAX_TRACKED_PATH_BYTES:
                    raise RuntimeError("candidate accepted tree path exceeds bounded length")
                if mode == b"40000":
                    walk(oid, relative_parts, depth + 1)
                    continue
                if mode not in {b"100644", b"100755", b"120000"}:
                    raise RuntimeError("candidate accepted tree contains unsupported tracked object")
                if len(oid) != len(source) or any(character not in "0123456789abcdef" for character in oid):
                    raise RuntimeError("candidate accepted tree contains invalid blob identity")
                if relative in entries:
                    raise RuntimeError("candidate accepted tree contains duplicate tracked path")
                entries[relative] = (mode, oid)
                if len(entries) > MAX_TRACKED_ENTRIES:
                    raise RuntimeError("candidate accepted tree exceeds tracked-entry limit")
        finally:
            active_trees.remove(tree_oid)

    walk(root_tree_oid, (), 0)
    if not entries:
        raise RuntimeError("candidate accepted tree contains no tracked blobs")
    return entries


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


def _load_previous_module() -> types.ModuleType:
    root = Path(__file__).resolve().parents[2]
    entries = _tree_entries(root, PREVIOUS_SOURCE)
    entry = entries.get(PREVIOUS_MODULE_PATH)
    if entry is None or entry != (b"100644", PREVIOUS_MODULE_GIT_BLOB):
        raise RuntimeError("Final-GO predecessor path is not the exact accepted Git blob")
    payload = _verified_object_bytes(root, "blob", PREVIOUS_MODULE_GIT_BLOB, MAX_BLOB_OBJECT_BYTES)
    module = types.ModuleType("nembra_final_go_predecessor_471cc025")
    module.__file__ = str(Path(__file__).resolve())
    module.__nembra_accepted_control_source__ = PREVIOUS_SOURCE
    module.__nembra_accepted_control_blob__ = PREVIOUS_MODULE_GIT_BLOB
    filename = f"git:{PREVIOUS_SOURCE}:{PREVIOUS_MODULE_PATH}"
    try:
        exec(compile(payload, filename, "exec", dont_inherit=True), module.__dict__)
    except Exception as error:
        raise RuntimeError("accepted Final-GO predecessor could not execute") from error
    return module


_previous = _load_previous_module()
_ORIGINAL_AUDIT = _previous._audit_candidate_tree
_ORIGINAL_CANDIDATE_GIT_CUSTODY = _previous._candidate_git_custody

# Preserve the predecessor's public/current compatibility contract. Existing
# exact-head tests bind these names to historical #2873 authority.
_parent = _previous._parent
PARENT_SOURCE = _previous.PARENT_SOURCE
PARENT_MODULE_PATH = _previous.PARENT_MODULE_PATH
PARENT_MODULE_GIT_BLOB = _previous.PARENT_MODULE_GIT_BLOB
generated = _previous.generated
PrivateReviewGoError = _previous.PrivateReviewGoError
review_v5 = _previous.review_v5
candidate_private_authority = _previous.candidate_private_authority


def _tracked_directories(entries: dict[str, tuple[bytes, str]]) -> list[str]:
    directories: set[str] = {""}
    for relative in entries:
        parts = PurePosixPath(relative).parts
        if not parts or any(part in {"", ".", ".."} for part in parts):
            raise RuntimeError("candidate accepted tree contains unsafe tracked path")
        for index in range(1, len(parts)):
            directories.add(PurePosixPath(*parts[:index]).as_posix())
    return sorted(directories, key=lambda item: (len(PurePosixPath(item).parts), item))


class _LinuxInotifyMutationWatch:
    _IN_MODIFY = 0x00000002
    _IN_ATTRIB = 0x00000004
    _IN_CLOSE_WRITE = 0x00000008
    _IN_MOVED_FROM = 0x00000040
    _IN_MOVED_TO = 0x00000080
    _IN_CREATE = 0x00000100
    _IN_DELETE = 0x00000200
    _IN_DELETE_SELF = 0x00000400
    _IN_MOVE_SELF = 0x00000800
    _IN_Q_OVERFLOW = 0x00004000
    _IN_ONLYDIR = 0x01000000
    _IN_DONT_FOLLOW = 0x02000000

    def __init__(self, root: Path, directories: list[str]) -> None:
        self.root = root
        self.directories = directories
        self.fd: int | None = None

    @property
    def _mask(self) -> int:
        return (
            self._IN_MODIFY
            | self._IN_ATTRIB
            | self._IN_CLOSE_WRITE
            | self._IN_MOVED_FROM
            | self._IN_MOVED_TO
            | self._IN_CREATE
            | self._IN_DELETE
            | self._IN_DELETE_SELF
            | self._IN_MOVE_SELF
            | self._IN_Q_OVERFLOW
            | self._IN_ONLYDIR
            | self._IN_DONT_FOLLOW
        )

    def arm(self) -> None:
        libc = ctypes.CDLL(None, use_errno=True)
        if not hasattr(libc, "inotify_init1") or not hasattr(libc, "inotify_add_watch"):
            raise RuntimeError("candidate continuous whole-tree mutation custody is unavailable")
        libc.inotify_init1.argtypes = [ctypes.c_int]
        libc.inotify_init1.restype = ctypes.c_int
        libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
        libc.inotify_add_watch.restype = ctypes.c_int
        fd = libc.inotify_init1(os.O_NONBLOCK | getattr(os, "O_CLOEXEC", 0))
        if fd < 0:
            errno = ctypes.get_errno()
            raise RuntimeError(f"candidate inotify custody initialization failed: errno {errno}")
        self.fd = fd
        try:
            for relative in self.directories:
                path = self.root if not relative else self.root / relative
                before = os.lstat(path)
                if not stat.S_ISDIR(before.st_mode) or stat.S_ISLNK(before.st_mode):
                    raise RuntimeError("candidate tracked directory is not one real directory: " + relative)
                watch = libc.inotify_add_watch(fd, os.fsencode(path), self._mask)
                if watch < 0:
                    errno = ctypes.get_errno()
                    raise RuntimeError(
                        f"candidate inotify custody could not watch tracked directory {relative!r}: errno {errno}"
                    )
                after = os.lstat(path)
                if _stable_stat(before) != _stable_stat(after):
                    raise RuntimeError("candidate tracked directory changed during custody arm: " + relative)
            self.assert_quiet()
        except OSError as error:
            raise RuntimeError("candidate tracked directory unavailable during inotify custody arm") from error

    def assert_quiet(self) -> None:
        if self.fd is None:
            raise RuntimeError("candidate continuous whole-tree mutation custody is not armed")
        total = 0
        while True:
            try:
                payload = os.read(self.fd, 64 * 1024)
            except BlockingIOError:
                break
            except OSError as error:
                raise RuntimeError("candidate whole-tree mutation event read failed") from error
            if not payload:
                break
            total += len(payload)
            if total > MAX_MUTATION_EVENT_BYTES:
                raise RuntimeError("candidate whole-tree mutation event stream exceeded bound")
        if total:
            raise RuntimeError("candidate tracked tree changed under continuous whole-tree mutation custody")

    def close(self) -> None:
        if self.fd is not None:
            try:
                os.close(self.fd)
            finally:
                self.fd = None


class _DarwinKqueueMutationWatch:
    def __init__(self, root: Path, directories: list[str], entries: dict[str, tuple[bytes, str]]) -> None:
        self.root = root
        self.directories = directories
        self.entries = entries
        self.queue: Any | None = None
        self.descriptors: list[int] = []

    def _subjects(self) -> list[tuple[Path, bool]]:
        subjects = [(self.root if not relative else self.root / relative, True) for relative in self.directories]
        subjects.extend(
            (self.root / relative, False)
            for relative, (mode, _) in sorted(self.entries.items())
            if mode != b"120000"
        )
        return subjects

    def arm(self) -> None:
        if not hasattr(select, "kqueue") or not hasattr(select, "kevent"):
            raise RuntimeError("candidate continuous whole-tree mutation custody is unavailable")
        subjects = self._subjects()
        soft_limit, _ = resource.getrlimit(resource.RLIMIT_NOFILE)
        if soft_limit != resource.RLIM_INFINITY and len(subjects) + 64 >= soft_limit:
            raise RuntimeError("candidate tracked tree exceeds macOS vnode custody descriptor budget")
        self.queue = select.kqueue()
        fflags = (
            select.KQ_NOTE_WRITE
            | select.KQ_NOTE_EXTEND
            | select.KQ_NOTE_ATTRIB
            | select.KQ_NOTE_DELETE
            | select.KQ_NOTE_RENAME
            | select.KQ_NOTE_REVOKE
            | getattr(select, "KQ_NOTE_LINK", 0)
        )
        try:
            for path, is_directory in subjects:
                before = os.lstat(path)
                if is_directory:
                    if not stat.S_ISDIR(before.st_mode) or stat.S_ISLNK(before.st_mode):
                        raise RuntimeError("candidate tracked directory is not one real directory: " + str(path))
                    flags = os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
                else:
                    if not stat.S_ISREG(before.st_mode) or stat.S_ISLNK(before.st_mode):
                        raise RuntimeError("candidate tracked file is not one real regular file: " + str(path))
                    flags = getattr(os, "O_EVTONLY", os.O_RDONLY) | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
                descriptor = os.open(path, flags)
                self.descriptors.append(descriptor)
                opened = os.fstat(descriptor)
                rebound = os.lstat(path)
                if _stable_stat(before) != _stable_stat(opened) or _stable_stat(opened) != _stable_stat(rebound):
                    raise RuntimeError("candidate tracked vnode changed during kqueue custody arm: " + str(path))
                event = select.kevent(
                    descriptor,
                    filter=select.KQ_FILTER_VNODE,
                    flags=select.KQ_EV_ADD | select.KQ_EV_CLEAR,
                    fflags=fflags,
                )
                self.queue.control([event], 0, 0)
                registered = os.fstat(descriptor)
                rebound_after = os.lstat(path)
                if _stable_stat(opened) != _stable_stat(registered) or _stable_stat(registered) != _stable_stat(rebound_after):
                    raise RuntimeError("candidate tracked vnode changed while kqueue watch registered: " + str(path))
            self.assert_quiet()
        except OSError as error:
            raise RuntimeError("candidate tracked vnode could not enter kqueue custody") from error

    def assert_quiet(self) -> None:
        if self.queue is None:
            raise RuntimeError("candidate continuous whole-tree mutation custody is not armed")
        try:
            events = self.queue.control(None, max(1, min(len(self.descriptors), 8192)), 0)
        except OSError as error:
            raise RuntimeError("candidate kqueue mutation event read failed") from error
        if events:
            raise RuntimeError("candidate tracked tree changed under continuous whole-tree mutation custody")

    def close(self) -> None:
        if self.queue is not None:
            try:
                self.queue.close()
            finally:
                self.queue = None
        for descriptor in reversed(self.descriptors):
            try:
                os.close(descriptor)
            except OSError:
                pass
        self.descriptors.clear()


class _WholeTreeMutationCustody:
    def __init__(self, root: Path, entries: dict[str, tuple[bytes, str]]) -> None:
        self.root = root.expanduser().resolve(strict=True)
        self.entries = entries
        directories = _tracked_directories(entries)
        if sys.platform.startswith("linux"):
            self.backend: Any = _LinuxInotifyMutationWatch(self.root, directories)
        elif sys.platform == "darwin":
            self.backend = _DarwinKqueueMutationWatch(self.root, directories, entries)
        else:
            raise RuntimeError("candidate continuous whole-tree mutation custody requires Linux or macOS")

    def __enter__(self) -> "_WholeTreeMutationCustody":
        try:
            self.backend.arm()
        except Exception:
            self.backend.close()
            raise
        return self

    def assert_quiet(self) -> None:
        self.backend.assert_quiet()

    def __exit__(self, exc_type: Any, exc: Any, tb: Any) -> bool:
        try:
            if exc_type is None:
                self.backend.assert_quiet()
        finally:
            self.backend.close()
        return False


@contextlib.contextmanager
def _override(module: types.ModuleType, name: str, value: Any) -> Iterator[None]:
    original = getattr(module, name)
    setattr(module, name, value)
    try:
        yield
    finally:
        setattr(module, name, original)


def _active_physical_blob_oid() -> Any:
    return globals().get("_physical_blob_oid", _previous._physical_blob_oid)


def _audit_candidate_tree(root: Path, source: str) -> dict[str, tuple[bytes, str]]:
    root = root.expanduser().resolve(strict=True)
    entries = _tree_entries(root, source)
    with _WholeTreeMutationCustody(root, entries) as custody:
        with _override(_previous, "_physical_blob_oid", _active_physical_blob_oid()):
            result = _ORIGINAL_AUDIT(root, source)
        custody.assert_quiet()
        return result


@contextlib.contextmanager
def _candidate_git_custody(base: Any, candidate_repo: Path, source: str) -> Iterator[None]:
    root = candidate_repo.expanduser().resolve(strict=True)
    entries = _tree_entries(root, source)
    try:
        with _WholeTreeMutationCustody(root, entries) as custody:
            physical_blob_oid = _active_physical_blob_oid()

            def guarded_audit(current_root: Path, current_source: str) -> dict[str, tuple[bytes, str]]:
                with _override(_previous, "_physical_blob_oid", physical_blob_oid):
                    result = _ORIGINAL_AUDIT(current_root, current_source)
                custody.assert_quiet()
                return result

            with (
                _override(_previous, "_audit_candidate_tree", guarded_audit),
                _override(_previous, "_physical_blob_oid", physical_blob_oid),
            ):
                with _ORIGINAL_CANDIDATE_GIT_CUSTODY(base, root, source):
                    custody.assert_quiet()
                    yield
                    custody.assert_quiet()
    except RuntimeError as error:
        raise PrivateReviewGoError(str(error)) from error


def build(*, candidate_repo: Path, source: str, base_module: Any | None = None, **kwargs: Any) -> dict[str, Any]:
    with _override(_previous, "_candidate_git_custody", _candidate_git_custody):
        return _previous.build(
            candidate_repo=candidate_repo,
            source=source,
            base_module=base_module,
            **kwargs,
        )


def __getattr__(name: str) -> Any:
    return getattr(_previous, name)


if __name__ == "__main__":
    raise SystemExit(
        "This exact-predecessor Final-GO successor is exercised by its exact-head workflows; "
        "physical publication remains NO-GO until final composition acceptance."
    )

#!/usr/bin/env python3
"""Final-GO successor that keeps the accepted physical source tree under custody.

The exact #2921 Final-GO implementation correctly descriptor-binds each tracked
payload while that one payload is read, but expected-red #3024 proves a tracked
pathname can be replaced after its individual read/rebind has completed and
before the whole candidate audit returns.

This successor does not attempt to paper over that race with an unsynchronised
second hash pass. On the physical macOS path it arms kqueue vnode custody over
every accepted tracked regular file plus every tracked directory/ancestor before
#2921 is allowed to audit or build. The held descriptors remain live through the
entire inherited Final-GO build. Namespace identities are re-proved while all
watches are armed, queued vnode events are fail-closed, and the complete raw
candidate audit is replayed before custody is released.

Therefore a replace/restore race cannot become invisible merely because endpoint
bytes happen to match again: the namespace/file vnode event remains authority-
invalidating. A persistent replacement is additionally rejected by held-inode
namespace reproof and the final raw audit.

No Bluetooth, Tuya, credential, install, launch, telemetry, scooter-command, or
physical evidence semantics are introduced here.
"""
from __future__ import annotations

import contextlib
import hashlib
import os
import re
import resource
import select
import stat
import subprocess
import types
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Callable, Iterator, Sequence

PARENT_SOURCE = "471cc025b332f4df8b43a98d709710aeb4e0698f"
PARENT_MODULE_PATH = "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
PARENT_MODULE_GIT_BLOB = "48ce4bd8f933ae062eaaadd0d017d13c781a8c02"
MAX_PARENT_BYTES = 2 * 1024 * 1024
MAX_WATCH_SUBJECTS = 250_000
OID = re.compile(r"^[0-9a-f]{40}(?:[0-9a-f]{24})?$")


class WholeTreeCustodyError(RuntimeError):
    pass


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


def _blob_oid(payload: bytes, accepted_oid: str) -> str:
    framed = b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload
    if len(accepted_oid) == 40:
        return hashlib.sha1(framed).hexdigest()
    if len(accepted_oid) == 64:
        return hashlib.sha256(framed).hexdigest()
    raise WholeTreeCustodyError("Final-GO parent blob identity has unsupported width")


def _capture_exact_parent_module() -> types.ModuleType:
    """Execute only the independently hash-bound #2921 parent bytes."""
    root = Path(__file__).resolve().parents[2]
    marker = root / ".git"
    try:
        marker_metadata = marker.lstat()
    except OSError as error:
        raise WholeTreeCustodyError("Final-GO parent Git directory is unavailable") from error
    if not stat.S_ISDIR(marker_metadata.st_mode) or stat.S_ISLNK(marker_metadata.st_mode):
        raise WholeTreeCustodyError("Final-GO parent requires one real checkout Git directory")
    try:
        process = subprocess.run(
            ["/usr/bin/git", f"--git-dir={marker}", "cat-file", "blob", PARENT_MODULE_GIT_BLOB],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=_closed_git_environment(),
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise WholeTreeCustodyError("Final-GO exact parent bytes could not be captured") from error
    payload = process.stdout
    if not payload or len(payload) > MAX_PARENT_BYTES:
        raise WholeTreeCustodyError("Final-GO exact parent bytes exceed the accepted bound")
    if _blob_oid(payload, PARENT_MODULE_GIT_BLOB) != PARENT_MODULE_GIT_BLOB:
        raise WholeTreeCustodyError("Final-GO exact parent Git lookup returned different bytes")

    module = types.ModuleType("nembra_final_go_parent_2921_whole_tree")
    module.__file__ = str(Path(__file__).resolve())
    filename = f"git:{PARENT_SOURCE}:{PARENT_MODULE_PATH}"
    try:
        exec(compile(payload, filename, "exec", dont_inherit=True), module.__dict__)
    except Exception as error:
        raise WholeTreeCustodyError("Final-GO exact #2921 parent could not execute") from error

    try:
        entry = module._tree_entries(root, PARENT_SOURCE).get(PARENT_MODULE_PATH)
    except Exception as error:
        raise WholeTreeCustodyError("Final-GO exact parent tree provenance could not be proved") from error
    if entry is None or entry[1] != PARENT_MODULE_GIT_BLOB:
        raise WholeTreeCustodyError("Final-GO exact parent path is not the reviewed #2921 Git blob")
    return module


_parent = _capture_exact_parent_module()


class EventBackend:
    def register(self, descriptor: int) -> None:
        raise NotImplementedError

    def events(self, timeout: float) -> Sequence[object]:
        raise NotImplementedError

    def close(self) -> None:
        raise NotImplementedError


class KqueueVnodeBackend(EventBackend):
    """macOS vnode monitor for the complete Final-GO source-authority window."""

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
            "KQ_NOTE_ATTRIB",
            "KQ_NOTE_RENAME",
            "KQ_NOTE_REVOKE",
        )
        missing = [name for name in required if not hasattr(select, name)]
        if missing:
            raise WholeTreeCustodyError(
                "Final-GO whole-tree vnode custody requires macOS kqueue: " + ", ".join(missing)
            )
        self._queue = select.kqueue()
        self._fflags = (
            select.KQ_NOTE_DELETE
            | select.KQ_NOTE_WRITE
            | select.KQ_NOTE_EXTEND
            | select.KQ_NOTE_LINK
            | select.KQ_NOTE_ATTRIB
            | select.KQ_NOTE_RENAME
            | select.KQ_NOTE_REVOKE
        )

    def register(self, descriptor: int) -> None:
        event = select.kevent(
            descriptor,
            filter=select.KQ_FILTER_VNODE,
            flags=select.KQ_EV_ADD | select.KQ_EV_ENABLE | select.KQ_EV_CLEAR,
            fflags=self._fflags,
        )
        self._queue.control([event], 0, 0)

    def events(self, timeout: float) -> Sequence[object]:
        return self._queue.control(None, 512, timeout)

    def close(self) -> None:
        self._queue.close()


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
        int(getattr(metadata, "st_flags", 0)),
    )


@dataclass(frozen=True)
class WatchedSubject:
    descriptor: int
    path: Path
    identity: tuple[int, ...]


def _current_descriptor_count() -> int:
    try:
        return len(os.listdir("/dev/fd"))
    except OSError:
        return 64


def _ensure_fd_budget(watcher_count: int) -> None:
    if watcher_count <= 0 or watcher_count > MAX_WATCH_SUBJECTS:
        raise WholeTreeCustodyError("Final-GO whole-tree watch-set size is outside the accepted bound")
    required = _current_descriptor_count() + watcher_count + 64
    try:
        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
    except (OSError, ValueError) as error:
        raise WholeTreeCustodyError("Final-GO could not read its file-descriptor limit") from error
    if soft >= required:
        return
    if hard != resource.RLIM_INFINITY and hard < required:
        raise WholeTreeCustodyError(
            f"Final-GO whole-tree custody needs {required} descriptors but hard limit is {hard}"
        )
    try:
        resource.setrlimit(resource.RLIMIT_NOFILE, (required, hard))
        updated, _ = resource.getrlimit(resource.RLIMIT_NOFILE)
    except (OSError, ValueError) as error:
        raise WholeTreeCustodyError("Final-GO could not raise its descriptor limit") from error
    if updated < required:
        raise WholeTreeCustodyError("Final-GO descriptor limit remained below whole-tree custody need")


def _watch_paths(root: Path, entries: dict[str, tuple[bytes, str]]) -> tuple[Path, ...]:
    """Watch every tracked regular file and every directory that can replace a leaf."""
    paths: set[Path] = {root}
    for relative, (mode, _) in entries.items():
        parts = PurePosixPath(relative).parts
        if not parts or any(part in {"", ".", ".."} for part in parts):
            raise WholeTreeCustodyError("Final-GO accepted tree contains unsafe watch path")
        for depth in range(1, len(parts)):
            paths.add(root.joinpath(*parts[:depth]))
        if mode in {b"100644", b"100755"}:
            paths.add(root.joinpath(*parts))
        elif mode != b"120000":
            raise WholeTreeCustodyError("Final-GO accepted tree contains unsupported watch subject")
    if len(paths) > MAX_WATCH_SUBJECTS:
        raise WholeTreeCustodyError("Final-GO accepted tree exceeds whole-tree watcher bound")
    return tuple(sorted(paths, key=lambda item: (len(item.parts), os.fspath(item))))


def _open_watched_subjects(paths: Sequence[Path], backend: EventBackend) -> tuple[WatchedSubject, ...]:
    _ensure_fd_budget(len(paths))
    opened: list[WatchedSubject] = []
    cloexec = getattr(os, "O_CLOEXEC", 0)
    nofollow = getattr(os, "O_NOFOLLOW", 0)
    try:
        for path in paths:
            try:
                before = os.lstat(path)
            except OSError as error:
                raise WholeTreeCustodyError("Final-GO watched source disappeared before custody: " + str(path)) from error
            if stat.S_ISLNK(before.st_mode) or not (stat.S_ISDIR(before.st_mode) or stat.S_ISREG(before.st_mode)):
                raise WholeTreeCustodyError("Final-GO watched source is not a real file/directory: " + str(path))
            flags = os.O_RDONLY | cloexec | nofollow
            if stat.S_ISDIR(before.st_mode):
                flags |= getattr(os, "O_DIRECTORY", 0)
            try:
                descriptor = os.open(path, flags)
            except OSError as error:
                raise WholeTreeCustodyError("Final-GO watched source could not be opened: " + str(path)) from error
            try:
                after = os.fstat(descriptor)
                if _stable_stat(before) != _stable_stat(after):
                    raise WholeTreeCustodyError("Final-GO watched source changed during custody admission: " + str(path))
                backend.register(descriptor)
            except Exception:
                os.close(descriptor)
                raise
            opened.append(WatchedSubject(descriptor, path, _stable_stat(after)))
        return tuple(opened)
    except Exception:
        for item in reversed(opened):
            try:
                os.close(item.descriptor)
            except OSError:
                pass
        raise


def _describe_events(events: Sequence[object], watched: Sequence[WatchedSubject]) -> str:
    by_descriptor = {item.descriptor: item.path for item in watched}
    descriptions: list[str] = []
    for event in events[:16]:
        descriptor = int(getattr(event, "ident", -1))
        path = by_descriptor.get(descriptor)
        flags = int(getattr(event, "fflags", 0))
        descriptions.append(f"{path if path is not None else '<unknown>'} (flags=0x{flags:x})")
    return "; ".join(descriptions)


def _drain_events(backend: EventBackend, watched: Sequence[WatchedSubject], *, phase: str) -> None:
    observed: list[object] = []
    while True:
        events = list(backend.events(0.0))
        if not events:
            break
        observed.extend(events)
        if len(observed) > MAX_WATCH_SUBJECTS:
            raise WholeTreeCustodyError("Final-GO vnode event volume exceeded the accepted bound")
    if observed:
        raise WholeTreeCustodyError(
            f"Final-GO whole-tree vnode mutation observed during {phase}: " + _describe_events(observed, watched)
        )


def _reprove_namespace(watched: Sequence[WatchedSubject], *, phase: str) -> None:
    for item in watched:
        try:
            descriptor_identity = _stable_stat(os.fstat(item.descriptor))
            namespace_identity = _stable_stat(os.lstat(item.path))
        except OSError as error:
            raise WholeTreeCustodyError(
                f"Final-GO watched namespace disappeared during {phase}: {item.path}"
            ) from error
        if descriptor_identity != item.identity or namespace_identity != item.identity:
            raise WholeTreeCustodyError(
                f"Final-GO watched namespace changed during {phase}: {item.path}"
            )


def _require_quiet(
    backend: EventBackend,
    watched: Sequence[WatchedSubject],
    *,
    phase: str,
) -> None:
    # Rebind first and then drain while every watcher remains armed. If a race
    # occurs during this pass, its vnode event remains queued for the drain.
    _reprove_namespace(watched, phase=phase)
    _drain_events(backend, watched, phase=phase)


@contextlib.contextmanager
def _whole_tree_custody(
    candidate_repo: Path,
    source: str,
    *,
    backend_factory: Callable[[], EventBackend] = KqueueVnodeBackend,
) -> Iterator[None]:
    root = candidate_repo.expanduser().resolve(strict=True)
    normalized_source = source.lower()
    if not OID.fullmatch(normalized_source):
        raise WholeTreeCustodyError("Final-GO candidate source is not a canonical Git object ID")
    try:
        if _parent._head_oid(root) != normalized_source:
            raise WholeTreeCustodyError("Final-GO candidate HEAD differs from accepted source")
        entries = _parent._tree_entries(root, normalized_source)
    except WholeTreeCustodyError:
        raise
    except Exception as error:
        raise WholeTreeCustodyError("Final-GO accepted source tree could not be derived") from error

    backend = backend_factory()
    watched: tuple[WatchedSubject, ...] = ()
    try:
        watched = _open_watched_subjects(_watch_paths(root, entries), backend)
        _require_quiet(backend, watched, phase="watch admission")
        yield
        # Re-audit while every source watcher is still armed. This second pass is
        # not relied upon alone: replace/restore activity is independently fatal
        # because queued vnode events survive until the quiet barrier below.
        _parent._audit_candidate_tree(root, normalized_source)
        _require_quiet(backend, watched, phase="final candidate authority")
    finally:
        for item in reversed(watched):
            try:
                os.close(item.descriptor)
            except OSError:
                pass
        try:
            backend.close()
        except Exception:
            pass


def _audit_candidate_tree(
    candidate_repo: Path,
    source: str,
    *,
    backend_factory: Callable[[], EventBackend] = KqueueVnodeBackend,
) -> dict[str, tuple[bytes, str]]:
    """Audit the exact #2921 candidate while whole-tree custody remains armed."""
    with _whole_tree_custody(candidate_repo, source, backend_factory=backend_factory):
        return _parent._audit_candidate_tree(candidate_repo, source)


def build(*, candidate_repo: Path, source: str, base_module: Any | None = None, **kwargs: Any) -> dict[str, Any]:
    """Run the exact #2921 Final-GO build inside continuous whole-tree custody."""
    with _whole_tree_custody(candidate_repo, source):
        return _parent.build(
            candidate_repo=candidate_repo,
            source=source,
            base_module=base_module,
            **kwargs,
        )


def __getattr__(name: str) -> Any:
    return getattr(_parent, name)


if __name__ == "__main__":
    raise SystemExit(
        "This Final-GO whole-tree authority successor is exercised by exact-head validation; "
        "physical publication remains NO-GO until final composition accepts it."
    )

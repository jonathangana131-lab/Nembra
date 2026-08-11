#!/usr/bin/env python3
"""Final-GO successor that keeps whole-tree mutation custody across raw audit.

Exact parent #2921@471cc025... descriptor-binds each tracked payload while it
is read, but #3024 and #3030 demonstrate that sequential endpoint reproof is
not whole-tree atomicity: a same-UID writer can replace an already-admitted
pathname before the overall audit returns, or restore accepted bytes before
every finite endpoint read and diverge again immediately afterward.

This successor does not add another rehash pass. On the Linux authority runner
used by the canonical Final-GO gate, it arms descriptor-bound inotify watches
for the candidate root and every accepted tracked directory before the parent
raw audit begins. Directory watches receive content and namespace events for
direct children, so recursive directory coverage detects tracked-file writes,
replacements, creates, deletes, renames, metadata changes, and subtree
mutation. Any event from arming through the completed parent audit fails
closed. Unsupported platforms fail closed rather than silently falling back to
finite polling.

The exact #2921 parent implementation is loaded from its immutable accepted Git
blob and then patched only at its `_audit_candidate_tree` seam. All inherited
Final-GO semantics remain owned by that exact parent.
"""
from __future__ import annotations

import ctypes
import errno
import hashlib
import os
from pathlib import Path, PurePosixPath
import select
import stat
import subprocess
import types
from typing import Any, Sequence

PARENT_SOURCE = "471cc025b332f4df8b43a98d709710aeb4e0698f"
PARENT_MODULE_PATH = "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
PARENT_MODULE_GIT_BLOB = "48ce4bd8f933ae062eaaadd0d017d13c781a8c02"
MAX_PARENT_BYTES = 4 * 1024 * 1024


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


def _git_blob_oid(payload: bytes) -> str:
    header = b"blob " + str(len(payload)).encode("ascii") + b"\0"
    return hashlib.sha1(header + payload).hexdigest()


def _capture_parent_blob(root: Path) -> bytes:
    process: subprocess.Popen[bytes] | None = None
    try:
        process = subprocess.Popen(
            ["/usr/bin/git", "-C", str(root), "cat-file", "blob", PARENT_MODULE_GIT_BLOB],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=_closed_git_environment(),
        )
        if process.stdout is None:
            raise WholeTreeCustodyError("Final-GO parent blob pipe unavailable")
        payload = process.stdout.read(MAX_PARENT_BYTES + 1)
        if len(payload) > MAX_PARENT_BYTES:
            process.kill()
            process.wait()
            raise WholeTreeCustodyError("Final-GO parent blob exceeds bounded capture")
        if process.wait() != 0:
            raise WholeTreeCustodyError("Final-GO parent blob capture failed")
    except OSError as error:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        raise WholeTreeCustodyError("Final-GO parent blob capture failed") from error
    finally:
        if process is not None and process.stdout is not None:
            process.stdout.close()
    if _git_blob_oid(payload) != PARENT_MODULE_GIT_BLOB:
        raise WholeTreeCustodyError("Final-GO parent blob bytes differ from accepted identity")
    return payload


def _load_parent_module() -> types.ModuleType:
    root = Path(__file__).resolve().parents[2]
    payload = _capture_parent_blob(root)
    module = types.ModuleType("nembra_final_go_parent_2921")
    module.__file__ = str(root / PARENT_MODULE_PATH)
    module.__nembra_accepted_control_source__ = PARENT_SOURCE
    module.__nembra_accepted_control_blob__ = PARENT_MODULE_GIT_BLOB
    filename = f"git:{PARENT_SOURCE}:{PARENT_MODULE_PATH}"
    try:
        exec(compile(payload, filename, "exec", dont_inherit=True), module.__dict__)
    except Exception as error:
        raise WholeTreeCustodyError("accepted #2921 Final-GO parent could not execute") from error
    return module


_parent = _load_parent_module()
_original_audit_candidate_tree = _parent._audit_candidate_tree

# Public aliases intentionally preserve the existing Final-GO test/consumer API.
FIELD_INPUT_DIRECTORIES = _parent.FIELD_INPUT_DIRECTORIES
FIELD_INPUT_FILES = _parent.FIELD_INPUT_FILES
_tree_entries = _parent._tree_entries
_physical_blob_oid = _parent._physical_blob_oid
_stable_stat = _parent._stable_stat


class _LinuxInotifyBackend:
    """Descriptor-bound recursive-directory mutation witness for Final-GO CI."""

    # inotify masks from linux/inotify.h. Access/open events are intentionally
    # excluded because the authority audit itself reads the candidate.
    _MASK = (
        0x00000002  # IN_MODIFY
        | 0x00000004  # IN_ATTRIB
        | 0x00000008  # IN_CLOSE_WRITE
        | 0x00000040  # IN_MOVED_FROM
        | 0x00000080  # IN_MOVED_TO
        | 0x00000100  # IN_CREATE
        | 0x00000200  # IN_DELETE
        | 0x00000400  # IN_DELETE_SELF
        | 0x00000800  # IN_MOVE_SELF
        | 0x00002000  # IN_UNMOUNT
        | 0x00004000  # IN_Q_OVERFLOW
        | 0x00008000  # IN_IGNORED
    )

    def __init__(self) -> None:
        if not os.path.isdir("/proc/self/fd"):
            raise WholeTreeCustodyError("descriptor-bound inotify requires procfs fd subjects")
        self._libc = ctypes.CDLL(None, use_errno=True)
        try:
            init1 = self._libc.inotify_init1
            add_watch = self._libc.inotify_add_watch
        except AttributeError as error:
            raise WholeTreeCustodyError("Linux inotify custody is unavailable") from error
        init1.argtypes = [ctypes.c_int]
        init1.restype = ctypes.c_int
        add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
        add_watch.restype = ctypes.c_int
        flags = getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NONBLOCK", 0)
        self._descriptor = init1(flags)
        if self._descriptor < 0:
            code = ctypes.get_errno()
            raise WholeTreeCustodyError(
                "Linux inotify custody could not initialize: " + os.strerror(code)
            )
        self._add_watch = add_watch
        self._watch_count = 0

    def register(self, descriptor: int) -> None:
        # `/proc/self/fd/N` binds the watch to the already-open directory inode;
        # a mutable pathname lookup never decides which vnode receives custody.
        subject = f"/proc/self/fd/{descriptor}".encode("ascii")
        result = self._add_watch(self._descriptor, subject, self._MASK)
        if result < 0:
            code = ctypes.get_errno()
            raise WholeTreeCustodyError(
                "Linux inotify custody could not arm directory subject: " + os.strerror(code)
            )
        self._watch_count += 1

    def events(self, timeout: float) -> Sequence[bytes]:
        if self._descriptor < 0:
            return ()
        ready, _, _ = select.select([self._descriptor], [], [], timeout)
        if not ready:
            return ()
        chunks: list[bytes] = []
        while True:
            try:
                payload = os.read(self._descriptor, 65536)
            except BlockingIOError:
                break
            except OSError as error:
                if error.errno in {errno.EAGAIN, errno.EWOULDBLOCK}:
                    break
                raise WholeTreeCustodyError("Linux inotify event read failed") from error
            if not payload:
                break
            chunks.append(payload)
        return tuple(chunks)

    def close(self) -> None:
        if self._descriptor >= 0:
            os.close(self._descriptor)
            self._descriptor = -1


class _CandidateWholeTreeCustody:
    def __init__(self, root: Path, entries: dict[str, tuple[bytes, str]]) -> None:
        if not os.sys.platform.startswith("linux"):
            raise WholeTreeCustodyError(
                "whole-tree Final-GO mutation custody is accepted only on Linux inotify authority"
            )
        self._root = root.expanduser().resolve(strict=True)
        self._entries = entries
        self._backend = _LinuxInotifyBackend()
        self._opened: list[tuple[int, Path]] = []

    def _directory_subjects(self) -> tuple[Path, ...]:
        relatives: set[str] = {""}
        for relative in self._entries:
            parts = PurePosixPath(relative).parts
            for index in range(1, len(parts)):
                relatives.add(PurePosixPath(*parts[:index]).as_posix())
        # Explicit field roots are outside the tracked tree but their own
        # namespace shape is part of the parent raw-audit admission contract.
        relatives.update(FIELD_INPUT_DIRECTORIES)
        return tuple(
            self._root if not relative else self._root / relative
            for relative in sorted(relatives, key=lambda value: (value.count("/"), value))
        )

    def arm(self) -> None:
        flags = os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_CLOEXEC", 0)
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        try:
            for path in self._directory_subjects():
                try:
                    before = os.lstat(path)
                except OSError as error:
                    raise WholeTreeCustodyError(
                        "whole-tree candidate directory disappeared before custody: " + str(path)
                    ) from error
                if not stat.S_ISDIR(before.st_mode) or stat.S_ISLNK(before.st_mode):
                    raise WholeTreeCustodyError(
                        "whole-tree candidate custody requires one real directory: " + str(path)
                    )
                try:
                    descriptor = os.open(path, flags)
                except OSError as error:
                    raise WholeTreeCustodyError(
                        "whole-tree candidate directory could not be opened for custody: " + str(path)
                    ) from error
                try:
                    opened = os.fstat(descriptor)
                    rebound = os.lstat(path)
                    if (
                        _stable_stat(before) != _stable_stat(opened)
                        or _stable_stat(opened) != _stable_stat(rebound)
                    ):
                        raise WholeTreeCustodyError(
                            "whole-tree candidate directory changed while custody armed: " + str(path)
                        )
                    self._backend.register(descriptor)
                except Exception:
                    os.close(descriptor)
                    raise
                self._opened.append((descriptor, path))
        except Exception:
            self.close()
            raise

    def reject_events(self, phase: str) -> None:
        if self._backend.events(0):
            raise WholeTreeCustodyError(
                "whole-tree candidate mutation observed " + phase
            )

    def close(self) -> None:
        for descriptor, _ in reversed(self._opened):
            try:
                os.close(descriptor)
            except OSError:
                pass
        self._opened.clear()
        self._backend.close()


def _audit_candidate_tree(root: Path, source: str) -> dict[str, tuple[bytes, str]]:
    """Run exact #2921 raw audit while recursive mutation custody stays armed."""
    root = root.expanduser().resolve(strict=True)
    entries = _tree_entries(root, source)
    custody = _CandidateWholeTreeCustody(root, entries)
    custody.arm()
    try:
        # Registration has its own chronology boundary. Any mutation observed
        # while earlier directories were already armed invalidates the window;
        # mutations to not-yet-armed directories are re-proved by the full raw
        # parent audit that follows once every directory has custody.
        custody.reject_events("while mutation custody was armed")

        # Preserve adversarial monkeypatch seams: validation may replace this
        # successor module's `_physical_blob_oid`, and the exact parent audit
        # must consume that same callable instead of silently bypassing it.
        prior_physical_blob_oid = _parent._physical_blob_oid
        _parent._physical_blob_oid = globals()["_physical_blob_oid"]
        try:
            result = _original_audit_candidate_tree(root, source)
        finally:
            _parent._physical_blob_oid = prior_physical_blob_oid

        custody.reject_events("during the complete raw candidate audit")
        if result != entries:
            raise WholeTreeCustodyError("whole-tree parent audit returned unexpected accepted tree")
        return result
    finally:
        custody.close()


# Existing parent call sites resolve module globals at execution time. Replacing
# this one seam makes inherited candidate_private_authority/main consume the
# stronger whole-tree custody without duplicating their accepted semantics.
_parent._audit_candidate_tree = _audit_candidate_tree


def __getattr__(name: str) -> Any:
    return getattr(_parent, name)


def main() -> int:
    return int(_parent.main())


if __name__ == "__main__":
    raise SystemExit(main())

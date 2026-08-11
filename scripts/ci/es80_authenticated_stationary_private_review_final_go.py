#!/usr/bin/env python3
"""Final-GO child that keeps the accepted tracked tree under descriptor custody.

Exact parent #2921 already binds every individual tracked read to a no-follow
pathname/descriptor proof. Expected-red #3024 and #3030 demonstrate the next
boundary: after one subject is admitted, its pathname can be replaced while
later subjects are checked, so a finite sequence of endpoint re-hashes can still
return an accepted tree while the physical candidate has diverged.

This successor does not add another re-hash pass. It loads exact #2921 bytes
from their immutable Git blob, holds every accepted regular-file inode open for
the complete candidate-custody window, records symlink inode identity together
with its accepted target, and finally re-binds every current tracked pathname to
the held snapshot without calling the per-file hash primitive again. In-place
mutation changes the held inode metadata; replacement changes the final namespace
identity. Either condition fails closed before authority can return.
"""
from __future__ import annotations

import contextlib
import hashlib
import os
import resource
import stat
import subprocess
import types
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Iterator

PARENT_SOURCE = "471cc025b332f4df8b43a98d709710aeb4e0698f"
PARENT_MODULE_PATH = "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
PARENT_MODULE_GIT_BLOB = "48ce4bd8f933ae062eaaadd0d017d13c781a8c02"
MAX_PARENT_MODULE_BYTES = 2 * 1024 * 1024
FD_HEADROOM = 96


def _closed_loader_environment() -> dict[str, str]:
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


def _git_blob_oid(payload: bytes, accepted_oid: str) -> str:
    header = b"blob " + str(len(payload)).encode("ascii") + b"\0"
    if len(accepted_oid) == 40:
        return hashlib.sha1(header + payload).hexdigest()
    if len(accepted_oid) == 64:
        return hashlib.sha256(header + payload).hexdigest()
    raise RuntimeError("Final-GO parent blob has unsupported Git object width")


def _capture_exact_parent_blob(root: Path) -> bytes:
    git_dir = root / ".git"
    try:
        metadata = git_dir.lstat()
    except OSError as error:
        raise RuntimeError("Final-GO parent loader requires one real .git directory") from error
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        raise RuntimeError("Final-GO parent loader requires one real .git directory")

    process: subprocess.Popen[bytes] | None = None
    try:
        process = subprocess.Popen(
            ["/usr/bin/git", f"--git-dir={git_dir}", "cat-file", "blob", PARENT_MODULE_GIT_BLOB],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=_closed_loader_environment(),
        )
        if process.stdout is None:
            raise RuntimeError("Final-GO parent blob pipe unavailable")
        payload = process.stdout.read(MAX_PARENT_MODULE_BYTES + 1)
        if len(payload) > MAX_PARENT_MODULE_BYTES:
            process.kill()
            process.wait()
            raise RuntimeError("Final-GO parent module exceeds bounded capture limit")
        if process.wait() != 0:
            raise RuntimeError("Final-GO exact parent blob capture failed")
    except OSError as error:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        raise RuntimeError("Final-GO exact parent blob capture failed") from error
    finally:
        if process is not None and process.stdout is not None:
            process.stdout.close()

    if _git_blob_oid(payload, PARENT_MODULE_GIT_BLOB) != PARENT_MODULE_GIT_BLOB:
        raise RuntimeError("Final-GO parent object lookup returned bytes outside accepted identity")
    return payload


def _load_parent_module() -> types.ModuleType:
    root = Path(__file__).resolve().parents[2]
    payload = _capture_exact_parent_blob(root)
    module = types.ModuleType("nembra_private_review_final_go_parent_2921")
    module.__file__ = str(Path(__file__).resolve())
    module.__nembra_accepted_control_source__ = PARENT_SOURCE
    module.__nembra_accepted_control_blob__ = PARENT_MODULE_GIT_BLOB
    filename = f"git:{PARENT_SOURCE}:{PARENT_MODULE_PATH}"
    try:
        exec(compile(payload, filename, "exec", dont_inherit=True), module.__dict__)
    except Exception as error:
        raise RuntimeError("accepted #2921 Final-GO parent could not execute") from error
    return module


_parent = _load_parent_module()
PrivateReviewGoError = _parent.PrivateReviewGoError
_ORIGINAL_AUDIT = _parent._audit_candidate_tree
_ORIGINAL_PHYSICAL_BLOB_OID = _parent._physical_blob_oid
_ORIGINAL_CUSTODY = _parent._candidate_git_custody

# Preserve the historical monkeypatch seam used by adversarial tests. The exact
# parent calls this bridge from its own module globals; replacing this child
# module's `_physical_blob_oid` therefore still attacks the real parent read.
_physical_blob_oid = _ORIGINAL_PHYSICAL_BLOB_OID


def _physical_blob_oid_bridge(root: Path, relative: str, mode: bytes, accepted_oid: str) -> str:
    return _physical_blob_oid(root, relative, mode, accepted_oid)


_parent._physical_blob_oid = _physical_blob_oid_bridge


@dataclass
class _HeldTrackedSubject:
    relative: str
    mode: bytes
    accepted_oid: str
    identity: tuple[int, ...]
    descriptor: int | None


@dataclass
class _HeldTrackedSnapshot:
    root: Path
    source: str
    entries: dict[str, tuple[bytes, str]]
    subjects: list[_HeldTrackedSubject]
    old_fd_limit: tuple[int, int] | None


def _raise_fd_budget(entry_count: int) -> tuple[int, int] | None:
    try:
        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
    except (OSError, ValueError) as error:
        raise RuntimeError("candidate whole-tree descriptor FD budget is unavailable") from error
    needed = entry_count + int(getattr(_parent, "MAX_TREE_DEPTH", 64)) + FD_HEADROOM
    if soft >= needed:
        return None
    unlimited = hard == resource.RLIM_INFINITY
    target = needed if unlimited else min(hard, needed)
    if target < needed:
        raise RuntimeError(
            f"candidate whole-tree descriptor custody requires {needed} file descriptors; hard limit is {hard}"
        )
    try:
        resource.setrlimit(resource.RLIMIT_NOFILE, (target, hard))
    except (OSError, ValueError) as error:
        raise RuntimeError("candidate whole-tree descriptor FD budget could not be raised") from error
    return (soft, hard)


def _restore_fd_budget(previous: tuple[int, int] | None) -> None:
    if previous is None:
        return
    try:
        resource.setrlimit(resource.RLIMIT_NOFILE, previous)
    except (OSError, ValueError) as error:
        raise RuntimeError("candidate whole-tree descriptor FD budget could not be restored") from error


def _open_parent_chain(root: Path, relative: str) -> tuple[int, list[int], str]:
    if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_DIRECTORY"):
        raise RuntimeError("candidate whole-tree descriptor custody is unavailable")
    parts = PurePosixPath(relative).parts
    if not parts or any(part in {"", ".", ".."} for part in parts):
        raise RuntimeError("candidate tracked path is unsafe: " + relative)
    cloexec = getattr(os, "O_CLOEXEC", 0)
    descriptors: list[int] = []
    try:
        parent = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | cloexec)
        descriptors.append(parent)
        for component in parts[:-1]:
            child = os.open(
                component,
                os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | cloexec,
                dir_fd=parent,
            )
            metadata = os.fstat(child)
            if not stat.S_ISDIR(metadata.st_mode):
                os.close(child)
                raise RuntimeError("candidate tracked path has non-directory ancestry: " + relative)
            descriptors.append(child)
            parent = child
        return parent, descriptors, parts[-1]
    except Exception:
        for descriptor in reversed(descriptors):
            try:
                os.close(descriptor)
            except OSError:
                pass
        raise


def _close_descriptors(descriptors: list[int]) -> None:
    for descriptor in reversed(descriptors):
        try:
            os.close(descriptor)
        except OSError:
            pass


def _read_held_regular(descriptor: int, expected_size: int, relative: str) -> bytes:
    chunks: list[bytes] = []
    total = 0
    try:
        os.lseek(descriptor, 0, os.SEEK_SET)
        while True:
            chunk = os.read(descriptor, 1 << 20)
            if not chunk:
                break
            total += len(chunk)
            if total > expected_size:
                raise RuntimeError("candidate tracked regular file grew during whole-tree snapshot: " + relative)
            chunks.append(chunk)
    except OSError as error:
        raise RuntimeError("candidate tracked regular file could not be read under whole-tree custody: " + relative) from error
    if total != expected_size:
        raise RuntimeError("candidate tracked regular file size changed during whole-tree snapshot: " + relative)
    return b"".join(chunks)


def _capture_subject(root: Path, relative: str, mode: bytes, accepted_oid: str) -> _HeldTrackedSubject:
    parent, ancestry, name = _open_parent_chain(root, relative)
    cloexec = getattr(os, "O_CLOEXEC", 0)
    leaf_descriptor: int | None = None
    try:
        admitted = os.stat(name, dir_fd=parent, follow_symlinks=False)
        if mode == b"120000":
            if not stat.S_ISLNK(admitted.st_mode):
                raise RuntimeError("candidate expected tracked symlink: " + relative)
            target = os.readlink(name, dir_fd=parent)
            after = os.stat(name, dir_fd=parent, follow_symlinks=False)
            if _parent._stable_stat(admitted) != _parent._stable_stat(after):
                raise RuntimeError("candidate tracked symlink changed during whole-tree snapshot: " + relative)
            payload = os.fsencode(target) if isinstance(target, str) else target
            if _parent._blob_oid(payload, accepted_oid) != accepted_oid:
                raise RuntimeError("candidate physical tracked bytes differ from accepted tree: " + relative)
            return _HeldTrackedSubject(
                relative=relative,
                mode=mode,
                accepted_oid=accepted_oid,
                identity=_parent._stable_stat(admitted),
                descriptor=None,
            )

        if not stat.S_ISREG(admitted.st_mode) or stat.S_ISLNK(admitted.st_mode):
            raise RuntimeError("candidate expected tracked regular file: " + relative)
        expected_executable = mode == b"100755"
        if bool(admitted.st_mode & 0o111) != expected_executable:
            raise RuntimeError("candidate tracked executable mode differs from accepted tree: " + relative)
        leaf_descriptor = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | cloexec, dir_fd=parent)
        opened = os.fstat(leaf_descriptor)
        if not stat.S_ISREG(opened.st_mode) or _parent._stable_stat(opened) != _parent._stable_stat(admitted):
            raise RuntimeError(
                "candidate tracked regular-file identity changed before whole-tree descriptor admission: "
                + relative
            )
        payload = _read_held_regular(leaf_descriptor, opened.st_size, relative)
        after = os.fstat(leaf_descriptor)
        if _parent._stable_stat(opened) != _parent._stable_stat(after):
            raise RuntimeError("candidate tracked regular file changed during whole-tree snapshot: " + relative)
        if _parent._blob_oid(payload, accepted_oid) != accepted_oid:
            raise RuntimeError("candidate physical tracked bytes differ from accepted tree: " + relative)
        subject = _HeldTrackedSubject(
            relative=relative,
            mode=mode,
            accepted_oid=accepted_oid,
            identity=_parent._stable_stat(opened),
            descriptor=leaf_descriptor,
        )
        leaf_descriptor = None
        return subject
    except OSError as error:
        raise RuntimeError("candidate tracked path descriptor snapshot failed: " + relative) from error
    finally:
        if leaf_descriptor is not None:
            try:
                os.close(leaf_descriptor)
            except OSError:
                pass
        _close_descriptors(ancestry)


def _current_namespace_identity(root: Path, relative: str) -> tuple[int, ...]:
    parent, ancestry, name = _open_parent_chain(root, relative)
    try:
        metadata = os.stat(name, dir_fd=parent, follow_symlinks=False)
        return _parent._stable_stat(metadata)
    except OSError as error:
        raise RuntimeError("candidate tracked namespace could not be rebound: " + relative) from error
    finally:
        _close_descriptors(ancestry)


def _rebind_snapshot(snapshot: _HeldTrackedSnapshot) -> None:
    if _parent._head_oid(snapshot.root) != snapshot.source:
        raise RuntimeError("candidate physical checkout HEAD changed across whole-tree custody")
    for subject in snapshot.subjects:
        if subject.descriptor is not None:
            try:
                held_now = _parent._stable_stat(os.fstat(subject.descriptor))
            except OSError as error:
                raise RuntimeError("candidate held tracked descriptor became unavailable: " + subject.relative) from error
            if held_now != subject.identity:
                raise RuntimeError("candidate held tracked inode changed across whole-tree custody: " + subject.relative)
        current = _current_namespace_identity(snapshot.root, subject.relative)
        if current != subject.identity:
            raise RuntimeError(
                "candidate tracked namespace diverged from held whole-tree snapshot: " + subject.relative
            )


@contextlib.contextmanager
def _held_tracked_snapshot(root: Path, source: str) -> Iterator[_HeldTrackedSnapshot]:
    root = root.expanduser().resolve(strict=True)
    source = source.lower()
    _parent._real_git_dir(root)
    if _parent._head_oid(root) != source:
        raise RuntimeError("candidate physical checkout HEAD differs from accepted source")
    entries = _parent._tree_entries(root, source)
    old_limit = _raise_fd_budget(len(entries))
    subjects: list[_HeldTrackedSubject] = []
    try:
        for relative, (mode, accepted_oid) in sorted(entries.items()):
            subjects.append(_capture_subject(root, relative, mode, accepted_oid))
        snapshot = _HeldTrackedSnapshot(
            root=root,
            source=source,
            entries=entries,
            subjects=subjects,
            old_fd_limit=old_limit,
        )
        _rebind_snapshot(snapshot)
        yield snapshot
    finally:
        close_error: RuntimeError | None = None
        for subject in subjects:
            if subject.descriptor is not None:
                try:
                    os.close(subject.descriptor)
                except OSError:
                    pass
        try:
            _restore_fd_budget(old_limit)
        except RuntimeError as error:
            close_error = error
        if close_error is not None:
            raise close_error


def _audit_candidate_tree(root: Path, source: str) -> dict[str, tuple[bytes, str]]:
    """Run #2921's full raw audit while one held tracked snapshot spans it."""
    with _held_tracked_snapshot(root, source) as snapshot:
        entries = _ORIGINAL_AUDIT(snapshot.root, snapshot.source)
        if entries != snapshot.entries:
            raise RuntimeError("candidate accepted tree changed across whole-tree descriptor snapshot")
        # This is an identity re-bind, not another content re-hash. The accepted
        # bytes came only from the held descriptors/symlink snapshot above.
        _rebind_snapshot(snapshot)
        return entries


def _guarded_git_for_snapshot(
    snapshot: _HeldTrackedSnapshot,
    original_git: Any,
    repo: Path,
    *args: str,
) -> str:
    try:
        item_root = repo.expanduser().resolve(strict=True)
    except OSError as error:
        raise PrivateReviewGoError("Git repository path is unavailable") from error
    if item_root != snapshot.root:
        return original_git(repo, *args)
    try:
        if args == ("status", "--porcelain=v1", "--untracked-files=all"):
            _ORIGINAL_AUDIT(snapshot.root, snapshot.source)
            _rebind_snapshot(snapshot)
            return ""
        return _parent._candidate_git_text(snapshot.root, snapshot.source, *args)
    except RuntimeError as error:
        raise PrivateReviewGoError(str(error)) from error


def _guarded_git_bytes_for_snapshot(
    snapshot: _HeldTrackedSnapshot,
    original_git_bytes: Any,
    repo: Path,
    *args: str,
) -> bytes:
    try:
        item_root = repo.expanduser().resolve(strict=True)
    except OSError as error:
        raise PrivateReviewGoError("Git repository path is unavailable") from error
    if item_root != snapshot.root:
        return original_git_bytes(repo, *args)
    try:
        return _parent._candidate_git_bytes(snapshot.root, snapshot.source, *args)
    except RuntimeError as error:
        raise PrivateReviewGoError(str(error)) from error


@contextlib.contextmanager
def _candidate_git_custody(base: Any, candidate_repo: Path, source: str) -> Iterator[None]:
    """Keep the same held tracked snapshot alive for the full parent build."""
    root = candidate_repo.expanduser().resolve(strict=True)
    source = source.lower()
    original_git = getattr(base, "git", None)
    original_git_bytes = getattr(base, "git_bytes", None)
    if not callable(original_git) or not callable(original_git_bytes):
        raise PrivateReviewGoError("parent Final-GO Git authority is not patchable")

    try:
        with _held_tracked_snapshot(root, source) as snapshot:
            # Preserve #2921's raw-tree/field-input checks once, but do not nest a
            # second descriptor snapshot inside this long-lived custody window.
            _ORIGINAL_AUDIT(root, source)
            _rebind_snapshot(snapshot)

            def guarded_git(repo: Path, *args: str) -> str:
                return _guarded_git_for_snapshot(snapshot, original_git, repo, *args)

            def guarded_git_bytes(repo: Path, *args: str) -> bytes:
                return _guarded_git_bytes_for_snapshot(snapshot, original_git_bytes, repo, *args)

            base.git = guarded_git
            base.git_bytes = guarded_git_bytes
            try:
                yield
                _rebind_snapshot(snapshot)
            finally:
                base.git = original_git
                base.git_bytes = original_git_bytes
    except RuntimeError as error:
        raise PrivateReviewGoError(str(error)) from error


# Patch the exact parent module globals used by its already-reviewed build()
# implementation. Direct callers of this child also receive the stronger audit.
_parent._audit_candidate_tree = _audit_candidate_tree
_parent._candidate_git_custody = _candidate_git_custody


def build(*, candidate_repo: Path, source: str, base_module: Any | None = None, **kwargs: Any) -> dict[str, Any]:
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
        "This exact-parent Final-GO control extension is exercised by its exact-head workflow; "
        "physical publication remains NO-GO until final composition accepts this successor."
    )

#!/usr/bin/env python3
"""Run pre-generated Tuya dependency work under private-input vnode custody.

This is intentionally *not* the physical field-build CLI. Dependency resolution
runs before generated CocoaPods subjects exist, but the code that creates custody
must itself be accepted authority. This adapter therefore executes only captured
Git-identity-pinned canonical guard/provenance bytes, then extends the canonical
private-input event loop with checkout-ancestry rename custody.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import select
import stat
import sys
import tempfile
from types import ModuleType
from typing import Sequence


class ResolutionGuardError(RuntimeError):
    pass


_CANONICAL_GUARD_GIT_BLOB_OID = "e1481b1e2ac0321ab4198ae960b5439a00acf3c1"
_PROVENANCE_HELPER_GIT_BLOB_OID = "66c21083dca625da11ad72bb6c652a09c2434ef6"
_CANONICAL_GUARD_MODULE_NAME = "nembra_private_dependency_resolution_build_guard"
_PINNED_PROVENANCE_FD_ENV = "NEMBRA_CAPTURE_PINNED_PROVENANCE_SOURCE_FD"
_MAX_HELPER_BYTES = 2 * 1024 * 1024


def _git_blob_oid(payload: bytes) -> str:
    return hashlib.sha1(
        b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload
    ).hexdigest()


def _source_identity(metadata: os.stat_result) -> tuple[int, ...]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_uid,
        metadata.st_gid,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _capture_accepted_python_source(path: Path, expected_oid: str, *, label: str) -> bytes:
    nofollow = getattr(os, "O_NOFOLLOW", None)
    if nofollow is None:
        raise ResolutionGuardError(f"{label} capture requires O_NOFOLLOW")
    flags = os.O_RDONLY | nofollow | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise ResolutionGuardError(f"{label} could not be opened without following links") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_size <= 0 or before.st_size > _MAX_HELPER_BYTES:
            raise ResolutionGuardError(f"{label} must be one bounded regular file")
        before_identity = _source_identity(before)
        chunks: list[bytes] = []
        total = 0
        while True:
            chunk = os.read(descriptor, min(65536, _MAX_HELPER_BYTES + 1 - total))
            if not chunk:
                break
            chunks.append(chunk)
            total += len(chunk)
            if total > _MAX_HELPER_BYTES:
                raise ResolutionGuardError(f"{label} exceeds the bounded source limit")
        after = os.fstat(descriptor)
        if _source_identity(after) != before_identity or total != after.st_size:
            raise ResolutionGuardError(f"{label} changed while accepted bytes were captured")
        try:
            current = path.lstat()
        except OSError as error:
            raise ResolutionGuardError(f"{label} pathname disappeared during capture") from error
        if stat.S_ISLNK(current.st_mode) or _source_identity(current) != before_identity:
            raise ResolutionGuardError(f"{label} pathname changed while accepted bytes were captured")
    finally:
        os.close(descriptor)

    source = b"".join(chunks)
    if _git_blob_oid(source) != expected_oid:
        raise ResolutionGuardError(f"{label} bytes do not match accepted Git identity")
    return source


def _load_guard(guard_path: Path, provenance_path: Path, checkout: Path):
    guard_path = _require_real_checkout_ancestry(
        guard_path, checkout, label="canonical private-input build guard source"
    )
    provenance_path = _require_real_checkout_ancestry(
        provenance_path, checkout, label="private-input provenance helper source"
    )
    guard_source = _capture_accepted_python_source(
        guard_path,
        _CANONICAL_GUARD_GIT_BLOB_OID,
        label="canonical private-input build guard source",
    )
    provenance_source = _capture_accepted_python_source(
        provenance_path,
        _PROVENANCE_HELPER_GIT_BLOB_OID,
        label="private-input provenance helper source",
    )

    with tempfile.TemporaryFile(prefix="nembra-private-provenance-source-") as pinned_provenance:
        pinned_provenance.write(provenance_source)
        pinned_provenance.flush()
        pinned_provenance.seek(0)
        previous_fd = os.environ.get(_PINNED_PROVENANCE_FD_ENV)
        os.environ[_PINNED_PROVENANCE_FD_ENV] = str(pinned_provenance.fileno())

        module = ModuleType(_CANONICAL_GUARD_MODULE_NAME)
        module.__file__ = "<accepted-capture_tuya_private_input_build_guard.py>"
        sys.modules[_CANONICAL_GUARD_MODULE_NAME] = module
        try:
            exec(compile(guard_source, module.__file__, "exec"), module.__dict__)
        except Exception:
            if sys.modules.get(_CANONICAL_GUARD_MODULE_NAME) is module:
                sys.modules.pop(_CANONICAL_GUARD_MODULE_NAME, None)
            raise
        finally:
            if previous_fd is None:
                os.environ.pop(_PINNED_PROVENANCE_FD_ENV, None)
            else:
                os.environ[_PINNED_PROVENANCE_FD_ENV] = previous_fd
    return module


def _lexical_absolute(path: Path) -> Path:
    """Normalize dot components without following attacker-controlled symlinks."""
    return Path(os.path.abspath(os.fspath(path)))


def _directory_identity(metadata: os.stat_result) -> tuple[int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        stat.S_IFMT(metadata.st_mode),
        metadata.st_uid,
    )


def _directory_flags() -> int:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_DIRECTORY", 0)
    nofollow = getattr(os, "O_NOFOLLOW", None)
    if nofollow is None:
        raise ResolutionGuardError("dependency-resolution ancestry custody requires O_NOFOLLOW")
    return flags | nofollow


def _require_real_checkout_ancestry(path: Path, root: Path, *, label: str) -> Path:
    """Admit one existing subject only through real descendants of one checkout root."""
    checkout = _lexical_absolute(root)
    candidate = _lexical_absolute(path)
    try:
        relative = candidate.relative_to(checkout)
    except ValueError as exc:
        raise ResolutionGuardError(f"{label} escapes the admitted checkout root") from exc

    try:
        root_metadata = checkout.lstat()
    except OSError as exc:
        raise ResolutionGuardError("dependency-resolution checkout root is unavailable") from exc
    if stat.S_ISLNK(root_metadata.st_mode) or not stat.S_ISDIR(root_metadata.st_mode):
        raise ResolutionGuardError("dependency-resolution checkout root is not one real directory")

    current = checkout
    for component in relative.parts:
        if component in ("", ".", ".."):
            raise ResolutionGuardError(f"{label} has invalid checkout-relative ancestry")
        current = current / component
        try:
            metadata = current.lstat()
        except OSError as exc:
            raise ResolutionGuardError(f"{label} is unavailable inside the admitted checkout") from exc
        if stat.S_ISLNK(metadata.st_mode):
            raise ResolutionGuardError(f"{label} traverses a symlink inside the admitted checkout")
        if current != candidate and not stat.S_ISDIR(metadata.st_mode):
            raise ResolutionGuardError(f"{label} traverses a non-directory checkout ancestor")

    return candidate


def _subject_parent_prefixes(checkout: Path, subjects: Sequence[Path]) -> tuple[tuple[str, ...], ...]:
    prefixes: set[tuple[str, ...]] = set()
    for subject in subjects:
        try:
            relative = subject.relative_to(checkout)
        except ValueError as exc:
            raise ResolutionGuardError("private dependency subject escaped checkout before custody") from exc
        parent_parts = relative.parts[:-1]
        for depth in range(1, len(parent_parts) + 1):
            prefixes.add(tuple(parent_parts[:depth]))
    return tuple(sorted(prefixes, key=lambda parts: (len(parts), parts)))


class _AncestryCustodyBackend:
    """Canonical event backend plus rename custody for absolute + checkout ancestry."""

    def __init__(self, checkout: Path, inputs) -> None:
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
            raise ResolutionGuardError(
                "macOS kqueue vnode monitoring is unavailable: " + ", ".join(missing)
            )
        self._queue = select.kqueue()
        self._descriptors: list[int] = []
        self._held_directories: list[tuple[int, Path, tuple[int, int, int, int]]] = []
        self._closed = False
        self._ancestry_fflags = (
            select.KQ_NOTE_DELETE | select.KQ_NOTE_RENAME | select.KQ_NOTE_REVOKE
        )
        self._input_fflags = (
            select.KQ_NOTE_DELETE
            | select.KQ_NOTE_WRITE
            | select.KQ_NOTE_EXTEND
            | select.KQ_NOTE_LINK
            | select.KQ_NOTE_RENAME
            | select.KQ_NOTE_REVOKE
        )
        try:
            self._arm_checkout_ancestry(checkout, inputs)
        except Exception:
            self.close()
            raise

    def _register_descriptor(self, descriptor: int, fflags: int) -> None:
        event = select.kevent(
            descriptor,
            filter=select.KQ_FILTER_VNODE,
            flags=select.KQ_EV_ADD | select.KQ_EV_ENABLE | select.KQ_EV_CLEAR,
            fflags=fflags,
        )
        self._queue.control([event], 0, 0)

    def _hold_directory(self, descriptor: int, path: Path) -> None:
        metadata = os.fstat(descriptor)
        if not stat.S_ISDIR(metadata.st_mode):
            raise ResolutionGuardError(f"dependency ancestry is not a directory: {path}")
        identity = _directory_identity(metadata)
        self._register_descriptor(descriptor, self._ancestry_fflags)
        self._descriptors.append(descriptor)
        self._held_directories.append((descriptor, path, identity))

    def _arm_checkout_ancestry(self, checkout: Path, inputs) -> None:
        checkout = _lexical_absolute(checkout)
        if not checkout.is_absolute():
            raise ResolutionGuardError("dependency-resolution checkout root is not absolute")

        flags = _directory_flags()
        filesystem_root = Path(checkout.anchor)
        try:
            parent_fd = os.open(filesystem_root, flags)
        except OSError as exc:
            raise ResolutionGuardError("filesystem root could not be opened for ancestry custody") from exc
        self._hold_directory(parent_fd, filesystem_root)

        current = filesystem_root
        checkout_fd = parent_fd
        for component in checkout.parts[1:]:
            current = current / component
            try:
                child_fd = os.open(component, flags, dir_fd=checkout_fd)
            except OSError as exc:
                raise ResolutionGuardError(
                    f"checkout ancestry could not be opened without symlinks: {current}"
                ) from exc
            self._hold_directory(child_fd, current)
            checkout_fd = child_fd

        try:
            cwd_fd = os.open(".", flags)
        except OSError as exc:
            raise ResolutionGuardError("inherited bootstrap working directory is unavailable") from exc
        try:
            if _directory_identity(os.fstat(cwd_fd)) != _directory_identity(os.fstat(checkout_fd)):
                raise ResolutionGuardError(
                    "dependency-resolution checkout path no longer names the inherited bootstrap working directory"
                )
        finally:
            os.close(cwd_fd)

        subjects = (
            inputs.lockfile,
            inputs.security_podspec,
            inputs.security_build,
            inputs.identity_podspec,
            inputs.identity_sources,
        )
        prefix_fds: dict[tuple[str, ...], int] = {(): checkout_fd}
        for prefix in _subject_parent_prefixes(checkout, subjects):
            parent_prefix = prefix[:-1]
            parent_descriptor = prefix_fds[parent_prefix]
            component = prefix[-1]
            path = checkout.joinpath(*prefix)
            try:
                descriptor = os.open(component, flags, dir_fd=parent_descriptor)
            except OSError as exc:
                raise ResolutionGuardError(
                    f"private dependency ancestry could not be opened without symlinks: {path}"
                ) from exc
            self._hold_directory(descriptor, path)
            prefix_fds[prefix] = descriptor

        for descriptor, path, identity in self._held_directories:
            try:
                current_metadata = path.lstat()
            except OSError as exc:
                raise ResolutionGuardError(
                    f"dependency ancestry disappeared while custody was armed: {path}"
                ) from exc
            if stat.S_ISLNK(current_metadata.st_mode) or not stat.S_ISDIR(current_metadata.st_mode):
                raise ResolutionGuardError(
                    f"dependency ancestry changed type while custody was armed: {path}"
                )
            if _directory_identity(current_metadata) != identity:
                raise ResolutionGuardError(
                    f"dependency ancestry changed inode while custody was armed: {path}"
                )
            if _directory_identity(os.fstat(descriptor)) != identity:
                raise ResolutionGuardError(
                    f"held dependency ancestry changed while custody was armed: {path}"
                )

    def register(self, descriptor: int) -> None:
        self._register_descriptor(descriptor, self._input_fflags)

    def events(self, timeout: float):
        return self._queue.control(None, 256, timeout)

    def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        for descriptor in reversed(self._descriptors):
            try:
                os.close(descriptor)
            except OSError:
                pass
        self._descriptors.clear()
        try:
            self._queue.close()
        except Exception:
            pass


def _parse_args(argv: Sequence[str]):
    parser = argparse.ArgumentParser(
        description="Run pre-generated private Tuya dependency work under vnode custody."
    )
    parser.add_argument("--canonical-guard-source", required=True, type=Path)
    parser.add_argument("--provenance-helper-source", required=True, type=Path)
    parser.add_argument("--lockfile", required=True, type=Path)
    parser.add_argument("--security-podspec", required=True, type=Path)
    parser.add_argument("--security-build", required=True, type=Path)
    parser.add_argument("--identity-podspec", required=True, type=Path)
    parser.add_argument("--identity-sources", required=True, type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(list(argv))
    command = list(args.command)
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        raise ResolutionGuardError("no guarded dependency command was supplied")

    lockfile = _lexical_absolute(args.lockfile)
    checkout = lockfile.parent
    admitted = {
        "lockfile": _require_real_checkout_ancestry(
            lockfile, checkout, label="dependency manifest anchor"
        ),
        "security_podspec": _require_real_checkout_ancestry(
            args.security_podspec, checkout, label="private security podspec"
        ),
        "security_build": _require_real_checkout_ancestry(
            args.security_build, checkout, label="private security build tree"
        ),
        "identity_podspec": _require_real_checkout_ancestry(
            args.identity_podspec, checkout, label="private identity podspec"
        ),
        "identity_sources": _require_real_checkout_ancestry(
            args.identity_sources, checkout, label="private identity source tree"
        ),
        "canonical_guard_source": _require_real_checkout_ancestry(
            args.canonical_guard_source, checkout, label="canonical private-input build guard source"
        ),
        "provenance_helper_source": _require_real_checkout_ancestry(
            args.provenance_helper_source, checkout, label="private-input provenance helper source"
        ),
    }
    return args, admitted, command, checkout


def main(argv: Sequence[str] | None = None) -> int:
    guard = None
    try:
        _, admitted, command, checkout = _parse_args(sys.argv[1:] if argv is None else argv)
        guard = _load_guard(
            admitted["canonical_guard_source"],
            admitted["provenance_helper_source"],
            checkout,
        )
        inputs = guard.PrivateInputs(
            lockfile=admitted["lockfile"],
            security_podspec=admitted["security_podspec"],
            security_build=admitted["security_build"],
            identity_podspec=admitted["identity_podspec"],
            identity_sources=admitted["identity_sources"],
        )
        return guard.run_guarded_build(
            inputs,
            command,
            backend_factory=lambda: _AncestryCustodyBackend(checkout, inputs),
        )
    except ResolutionGuardError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 74
    except Exception as error:
        guard_error = getattr(guard, "BuildGuardError", ()) if guard is not None else ()
        if guard_error and isinstance(error, guard_error):
            print(f"ERROR: {error}", file=sys.stderr)
            return 74
        print("ERROR: unexpected dependency-resolution custody failure", file=sys.stderr)
        return 77


if __name__ == "__main__":
    raise SystemExit(main())

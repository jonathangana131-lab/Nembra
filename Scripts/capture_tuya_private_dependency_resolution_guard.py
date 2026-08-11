#!/usr/bin/env python3
"""Run pre-generated Tuya dependency work under private-input vnode custody.

This is intentionally *not* the physical field-build CLI. The canonical build
guard's CLI protects the later xcodebuild window. Dependency resolution runs one
rung earlier, before generated CocoaPods subjects can exist.

The canonical guard deliberately preserves a private-only `run_guarded_build`
API whose authority is exactly the five admitted inputs plus the child command.
This adapter exposes only that narrow mode. It grants no xcodebuild,
generated-build, private-review, source-acceptance, or physical GO authority.
The child command must independently establish semantic authority (bootstrap
uses the root-sealed private-identity receipt) after vnode watchers are armed.
"""

from __future__ import annotations

import argparse
import importlib.util
import os
from pathlib import Path
import select
import stat
import sys
from typing import Sequence


class ResolutionGuardError(RuntimeError):
    pass


def _load_guard():
    guard_path = Path(__file__).with_name("capture_tuya_private_input_build_guard.py")
    if not guard_path.is_file() or guard_path.is_symlink():
        raise ResolutionGuardError("canonical private-input build guard is missing or symlinked")
    spec = importlib.util.spec_from_file_location(
        "nembra_private_dependency_resolution_build_guard",
        guard_path,
    )
    if spec is None or spec.loader is None:
        raise ResolutionGuardError("canonical private-input build guard could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
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
    """Admit one existing subject only through real descendants of one checkout root.

    Every pathname component from the checkout root through the supplied subject
    must exist without a symlink hop. The canonical guard remains the authority
    for final file/tree type, generation snapshots, exact descriptors, and vnode
    monitoring. A separate backend below keeps the ancestry directories themselves
    under rename/delete custody while that canonical window is live.
    """
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
    """Canonical event backend plus rename custody for absolute + checkout ancestry.

    CocoaPods legitimately writes generated siblings beneath the checkout, so
    ancestry directories deliberately watch only deletion/rename/revocation.
    Canonical private input descriptors still use the full mutation flags when
    `register` is called by `run_guarded_build`.
    """

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

        # Registration has its own race boundary. Reprove every canonical
        # directory pathname against the exact held inode after every ancestry
        # watcher is armed. Any later swap is queued for the canonical guard's
        # pre-child `events(0)` check or its live event loop.
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


def _parse_args(guard, argv: Sequence[str]):
    parser = argparse.ArgumentParser(
        description="Run pre-generated private Tuya dependency work under vnode custody."
    )
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

    # The tracked Podfile is the root anchor because CocoaPods itself executes it.
    # The adapter admits only real descendants, and the backend additionally binds
    # that root to the inherited bootstrap cwd plus watched directory ancestry.
    lockfile = _lexical_absolute(args.lockfile)
    root = lockfile.parent
    lockfile = _require_real_checkout_ancestry(lockfile, root, label="dependency manifest anchor")
    security_podspec = _require_real_checkout_ancestry(
        args.security_podspec, root, label="private security podspec"
    )
    security_build = _require_real_checkout_ancestry(
        args.security_build, root, label="private security build tree"
    )
    identity_podspec = _require_real_checkout_ancestry(
        args.identity_podspec, root, label="private identity podspec"
    )
    identity_sources = _require_real_checkout_ancestry(
        args.identity_sources, root, label="private identity source tree"
    )
    return (
        guard.PrivateInputs(
            lockfile=lockfile,
            security_podspec=security_podspec,
            security_build=security_build,
            identity_podspec=identity_podspec,
            identity_sources=identity_sources,
        ),
        command,
        root,
    )


def main(argv: Sequence[str] | None = None) -> int:
    try:
        guard = _load_guard()
        inputs, command, checkout = _parse_args(guard, sys.argv[1:] if argv is None else argv)
        # The canonical guard still owns exact input generation + live mutation
        # authority. The accepted backend keyword is used only to add checkout and
        # intermediate-directory rename custody to that same event loop.
        return guard.run_guarded_build(
            inputs,
            command,
            backend_factory=lambda: _AncestryCustodyBackend(checkout, inputs),
        )
    except ResolutionGuardError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 74
    except Exception as error:
        guard_error = getattr(locals().get("guard", None), "BuildGuardError", ())
        if guard_error and isinstance(error, guard_error):
            print(f"ERROR: {error}", file=sys.stderr)
            return 74
        print("ERROR: unexpected dependency-resolution custody failure", file=sys.stderr)
        return 77


if __name__ == "__main__":
    raise SystemExit(main())

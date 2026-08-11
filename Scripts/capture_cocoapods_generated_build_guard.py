#!/usr/bin/env python3
"""Guard accepted CocoaPods-generated build bytes across xcodebuild on macOS."""
from __future__ import annotations

import argparse
import importlib.util
import os
import select
import stat
import subprocess
import sys
from pathlib import Path
from typing import Callable, Iterable, Protocol, Sequence


class GeneratedBuildGuardError(RuntimeError):
    pass


def _load_subject_module():
    helper = Path(__file__).with_name("capture_cocoapods_generated_build_subject.py")
    spec = importlib.util.spec_from_file_location("capture_cocoapods_generated_build_subject", helper)
    if spec is None or spec.loader is None:
        raise GeneratedBuildGuardError("generated-build subject helper could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


subject = _load_subject_module()


class EventBackend(Protocol):
    def register(self, descriptor: int) -> None: ...
    def events(self, timeout: float) -> Sequence[object]: ...
    def close(self) -> None: ...


class KqueueVnodeBackend:
    def __init__(self) -> None:
        required = (
            "kqueue", "kevent", "KQ_FILTER_VNODE", "KQ_EV_ADD", "KQ_EV_ENABLE", "KQ_EV_CLEAR",
            "KQ_NOTE_DELETE", "KQ_NOTE_WRITE", "KQ_NOTE_EXTEND", "KQ_NOTE_LINK", "KQ_NOTE_RENAME", "KQ_NOTE_REVOKE",
        )
        missing = [name for name in required if not hasattr(select, name)]
        if missing:
            raise GeneratedBuildGuardError("macOS kqueue vnode monitoring is unavailable: " + ", ".join(missing))
        self._queue = select.kqueue()
        self._fflags = (
            select.KQ_NOTE_DELETE | select.KQ_NOTE_WRITE | select.KQ_NOTE_EXTEND |
            select.KQ_NOTE_LINK | select.KQ_NOTE_RENAME | select.KQ_NOTE_REVOKE
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
        return self._queue.control(None, 256, timeout)

    def close(self) -> None:
        self._queue.close()


def _watch_paths(roots: Iterable[Path]) -> tuple[Path, ...]:
    paths: set[Path] = set()
    for root in roots:
        meta = root.lstat()
        if stat.S_ISLNK(meta.st_mode) or not stat.S_ISDIR(meta.st_mode):
            raise GeneratedBuildGuardError(f"generated build root is not a real directory: {root}")
        for current_text, directories, files in os.walk(root, topdown=True, followlinks=False):
            current = Path(current_text)
            paths.add(current)
            kept: list[str] = []
            for name in directories:
                candidate = current / name
                if candidate.is_symlink():
                    continue
                paths.add(candidate)
                kept.append(name)
            directories[:] = kept
            for name in files:
                candidate = current / name
                if candidate.is_symlink():
                    continue
                paths.add(candidate)
    return tuple(sorted(paths, key=lambda item: str(item)))


def _open_watches(paths: Iterable[Path], backend: EventBackend) -> tuple[tuple[int, Path], ...]:
    opened: list[tuple[int, Path]] = []
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        for path in paths:
            before = subject._identity(path.lstat())
            descriptor = os.open(path, flags)
            try:
                after = subject._identity(os.fstat(descriptor))
                if before != after:
                    raise GeneratedBuildGuardError(f"generated build entry changed while custody was armed: {path}")
                mode = os.fstat(descriptor).st_mode
                if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
                    raise GeneratedBuildGuardError(f"generated build entry is not watchable: {path}")
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


def _stop(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def run_guarded(
    pods: Path,
    workspace: Path,
    expected_sha256: str,
    command: Sequence[str],
    *,
    backend_factory: Callable[[], EventBackend] = KqueueVnodeBackend,
    popen_factory: Callable[..., subprocess.Popen] = subprocess.Popen,
    poll_interval: float = 0.10,
) -> int:
    if not command:
        raise GeneratedBuildGuardError("no guarded build command was supplied")
    expected = expected_sha256.lower()
    if len(expected) != 64 or any(character not in "0123456789abcdef" for character in expected):
        raise GeneratedBuildGuardError("expected generated-build subject must be exactly 64 hex characters")
    initial = subject.fingerprint(pods, workspace)
    if initial != expected:
        raise GeneratedBuildGuardError("CocoaPods-generated build subject does not match reviewed authority before xcodebuild")

    backend = backend_factory()
    watched: tuple[tuple[int, Path], ...] = ()
    process: subprocess.Popen | None = None
    try:
        watched = _open_watches(_watch_paths((pods, workspace)), backend)
        armed = subject.fingerprint(pods, workspace)
        if armed != expected:
            raise GeneratedBuildGuardError("CocoaPods-generated build subject changed while build-window custody was armed")
        if backend.events(0):
            raise GeneratedBuildGuardError("CocoaPods-generated build subject changed before xcodebuild admission")
        process = popen_factory(list(command))
        while process.poll() is None:
            if backend.events(poll_interval):
                _stop(process)
                raise GeneratedBuildGuardError("CocoaPods-generated build subject mutated while xcodebuild was running")
        if backend.events(0):
            raise GeneratedBuildGuardError("CocoaPods-generated build subject mutated at xcodebuild completion")
        final = subject.fingerprint(pods, workspace)
        if final != expected:
            raise GeneratedBuildGuardError("CocoaPods-generated build subject changed across the guarded xcodebuild window")
        if backend.events(0):
            raise GeneratedBuildGuardError("CocoaPods-generated build subject mutated during final verification")
        return int(process.returncode or 0)
    finally:
        if process is not None and process.poll() is None:
            _stop(process)
        for descriptor, _ in watched:
            try:
                os.close(descriptor)
            except OSError:
                pass
        backend.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pods", type=Path, required=True)
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--expected-sha256", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = list(args.command)
    if command and command[0] == "--":
        command = command[1:]
    try:
        return run_guarded(args.pods, args.workspace, args.expected_sha256, command)
    except (GeneratedBuildGuardError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 86


if __name__ == "__main__":
    raise SystemExit(main())

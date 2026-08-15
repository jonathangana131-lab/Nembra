#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import os
import re
import select
import stat
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable, Protocol, Sequence


class BuildGuardError(RuntimeError):
    pass


def _load_provenance_module():
    helper = Path(__file__).with_name("capture_tuya_private_input_provenance.py")
    spec = importlib.util.spec_from_file_location("capture_tuya_private_input_provenance", helper)
    if spec is None or spec.loader is None:
        raise BuildGuardError("private-input provenance helper could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


provenance = _load_provenance_module()


@dataclass(frozen=True)
class PrivateInputs:
    lockfile: Path
    security_podspec: Path
    security_build: Path
    identity_podspec: Path
    identity_sources: Path

    def generation_snapshot(self):
        return provenance._private_input_record_generation_snapshot(
            lockfile=self.lockfile,
            security_podspec=self.security_podspec,
            security_build=self.security_build,
            identity_podspec=self.identity_podspec,
            identity_sources=self.identity_sources,
        )

    def canonical_provenance_sha256(self) -> str:
        """Hash the exact canonical v2 provenance record implied by live inputs.

        The field-owned record file is deliberately not trusted here. Review mode
        creates that record only as a candidate for independent acceptance. The
        guarded build recomputes the same canonical record directly from the live
        lock/private inputs and compares it to the externally accepted digest.
        """
        record = provenance.build_record(
            lockfile=self.lockfile,
            security_podspec=self.security_podspec,
            security_build=self.security_build,
            identity_podspec=self.identity_podspec,
            identity_sources=self.identity_sources,
        )
        encoded = provenance._record_text(record).encode("utf-8")
        return hashlib.sha256(encoded).hexdigest()


class EventBackend(Protocol):
    def register(self, descriptor: int) -> None: ...
    def events(self, timeout: float) -> Sequence[object]: ...
    def close(self) -> None: ...


class KqueueVnodeBackend:
    """macOS vnode watcher used only for the physical field-build window."""

    def __init__(self) -> None:
        required = (
            "kqueue", "kevent", "KQ_FILTER_VNODE", "KQ_EV_ADD", "KQ_EV_ENABLE", "KQ_EV_CLEAR",
            "KQ_NOTE_DELETE", "KQ_NOTE_WRITE", "KQ_NOTE_EXTEND", "KQ_NOTE_ATTRIB",
            "KQ_NOTE_LINK", "KQ_NOTE_RENAME", "KQ_NOTE_REVOKE",
        )
        missing = [name for name in required if not hasattr(select, name)]
        if missing:
            raise BuildGuardError(
                "macOS kqueue vnode monitoring is unavailable: " + ", ".join(missing)
            )
        self._queue = select.kqueue()
        self._fflags = (
            select.KQ_NOTE_DELETE | select.KQ_NOTE_WRITE | select.KQ_NOTE_EXTEND
            | select.KQ_NOTE_ATTRIB | select.KQ_NOTE_LINK | select.KQ_NOTE_RENAME
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
        return self._queue.control(None, 256, timeout)

    def close(self) -> None:
        self._queue.close()


def _lstat_identity(path: Path) -> tuple[int, int, int, int, int, int, int]:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise BuildGuardError(f"private build input disappeared before vnode admission: {path}") from error
    return provenance._stat_identity(metadata)


def _watch_paths(inputs: PrivateInputs) -> tuple[Path, ...]:
    paths: set[Path] = {
        inputs.lockfile,
        inputs.security_podspec,
        inputs.identity_podspec,
    }
    for root in (inputs.security_build, inputs.identity_sources):
        if not root.is_dir() or root.is_symlink():
            raise BuildGuardError(f"private build input tree is not one real directory: {root}")
        paths.add(root)
        for current_root, directories, files in os.walk(root, topdown=True, followlinks=False):
            current = Path(current_root)
            paths.add(current)
            for name in directories:
                candidate = current / name
                if candidate.is_symlink():
                    continue
                paths.add(candidate)
            for name in files:
                candidate = current / name
                if candidate.is_symlink():
                    continue
                paths.add(candidate)
    return tuple(sorted(paths, key=lambda item: str(item)))


def _open_watched_inputs(paths: Iterable[Path], backend: EventBackend) -> tuple[tuple[int, Path], ...]:
    opened: list[tuple[int, Path]] = []
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        for path in paths:
            before = _lstat_identity(path)
            try:
                descriptor = os.open(path, flags)
            except OSError as error:
                raise BuildGuardError(f"private build input could not be opened for build-window custody: {path}") from error
            try:
                after = provenance._stat_identity(os.fstat(descriptor))
                if before != after:
                    raise BuildGuardError(f"private build input changed while vnode custody was armed: {path}")
                mode = os.fstat(descriptor).st_mode
                if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
                    raise BuildGuardError(f"private build input is not a watchable regular file/directory: {path}")
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


def _describe_events(events: Sequence[object], watched: Sequence[tuple[int, Path]]) -> str:
    by_descriptor = {descriptor: path for descriptor, path in watched}
    descriptions: list[str] = []
    for event in events:
        descriptor = int(getattr(event, "ident", -1))
        path = by_descriptor.get(descriptor)
        fflags = int(getattr(event, "fflags", 0))
        descriptions.append(f"{path if path is not None else '<unknown>'} (flags=0x{fflags:x})")
    return "; ".join(descriptions)


def _stop_process(process: subprocess.Popen[bytes] | subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def _accepted_digest(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = value.strip().lower()
    if re.fullmatch(r"[0-9a-f]{64}", normalized) is None:
        raise BuildGuardError("accepted private-input provenance SHA-256 is malformed")
    return normalized


def _require_accepted_live_inputs(inputs: PrivateInputs, accepted: str | None, phase: str) -> None:
    accepted = _accepted_digest(accepted)
    if accepted is None:
        return
    actual = inputs.canonical_provenance_sha256()
    if actual != accepted:
        raise BuildGuardError(
            f"live private build inputs do not match the independently accepted provenance at {phase}"
        )


def run_guarded_build(
    inputs: PrivateInputs,
    command: Sequence[str],
    *,
    expected_provenance_sha256: str | None = None,
    backend_factory: Callable[[], EventBackend] = KqueueVnodeBackend,
    popen_factory: Callable[..., subprocess.Popen] = subprocess.Popen,
    poll_interval: float = 0.10,
) -> int:
    if not command:
        raise BuildGuardError("no build command was supplied")

    accepted = _accepted_digest(expected_provenance_sha256)
    initial_snapshot = inputs.generation_snapshot()
    _require_accepted_live_inputs(inputs, accepted, "initial admission")
    backend = backend_factory()
    watched: tuple[tuple[int, Path], ...] = ()
    process: subprocess.Popen | None = None
    try:
        watched = _open_watched_inputs(_watch_paths(inputs), backend)

        armed_snapshot = inputs.generation_snapshot()
        if armed_snapshot != initial_snapshot:
            raise BuildGuardError("private build inputs changed while build-window monitoring was armed")
        _require_accepted_live_inputs(inputs, accepted, "armed admission")
        queued = backend.events(0)
        if queued:
            raise BuildGuardError(
                "private build inputs changed before xcodebuild admission: "
                + _describe_events(queued, watched)
            )

        process = popen_factory(list(command))
        while process.poll() is None:
            events = backend.events(poll_interval)
            if events:
                _stop_process(process)
                raise BuildGuardError(
                    "private build input mutation was observed while xcodebuild was running: "
                    + _describe_events(events, watched)
                )

        trailing = backend.events(0)
        if trailing:
            raise BuildGuardError(
                "private build input mutation was observed at xcodebuild completion: "
                + _describe_events(trailing, watched)
            )

        final_snapshot = inputs.generation_snapshot()
        if final_snapshot != initial_snapshot:
            raise BuildGuardError("private build inputs changed across the guarded xcodebuild window")
        _require_accepted_live_inputs(inputs, accepted, "final admission")
        trailing = backend.events(0)
        if trailing:
            raise BuildGuardError(
                "private build input mutation was observed during final build-window verification: "
                + _describe_events(trailing, watched)
            )
        return int(process.returncode or 0)
    finally:
        if process is not None and process.poll() is None:
            _stop_process(process)
        for descriptor, _ in watched:
            try:
                os.close(descriptor)
            except OSError:
                pass
        backend.close()


def _parse_args(argv: Sequence[str]) -> tuple[PrivateInputs, str, list[str]]:
    parser = argparse.ArgumentParser(
        description="Run the Capture field build while macOS vnode custody watches every independently accepted private input."
    )
    parser.add_argument("--lockfile", required=True, type=Path)
    parser.add_argument("--security-podspec", required=True, type=Path)
    parser.add_argument("--security-build", required=True, type=Path)
    parser.add_argument("--identity-podspec", required=True, type=Path)
    parser.add_argument("--identity-sources", required=True, type=Path)
    parser.add_argument("--expected-provenance-sha256", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(list(argv))
    command = list(args.command)
    if command and command[0] == "--":
        command = command[1:]
    return (
        PrivateInputs(
            lockfile=args.lockfile.resolve(),
            security_podspec=args.security_podspec.resolve(),
            security_build=args.security_build.resolve(),
            identity_podspec=args.identity_podspec.resolve(),
            identity_sources=args.identity_sources.resolve(),
        ),
        _accepted_digest(args.expected_provenance_sha256) or "",
        command,
    )


def main(argv: Sequence[str] | None = None) -> int:
    try:
        inputs, accepted, command = _parse_args(sys.argv[1:] if argv is None else argv)
        return run_guarded_build(inputs, command, expected_provenance_sha256=accepted)
    except BuildGuardError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 74
    except provenance.ProvenanceError as error:
        print(f"ERROR: private-input provenance rejected build-window custody: {error}", file=sys.stderr)
        return 75


if __name__ == "__main__":
    raise SystemExit(main())

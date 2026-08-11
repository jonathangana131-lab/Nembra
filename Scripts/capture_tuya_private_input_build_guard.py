#!/usr/bin/env python3
from __future__ import annotations

import argparse
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


def _load_sibling_module(filename: str, module_name: str):
    helper = Path(__file__).with_name(filename)
    spec = importlib.util.spec_from_file_location(module_name, helper)
    if spec is None or spec.loader is None:
        raise BuildGuardError(f"required build-custody helper could not be loaded: {filename}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


provenance = _load_sibling_module(
    "capture_tuya_private_input_provenance.py",
    "capture_tuya_private_input_provenance",
)
generated_subject = _load_sibling_module(
    "capture_cocoapods_generated_subject.py",
    "capture_cocoapods_generated_subject",
)


@dataclass(frozen=True)
class PrivateInputs:
    lockfile: Path
    security_podspec: Path
    security_build: Path
    identity_podspec: Path
    identity_sources: Path
    generated_pods: Path
    generated_workspace: Path
    accepted_generated_subject_sha256: str

    def generation_snapshot(self):
        private_snapshot = provenance._private_input_record_generation_snapshot(
            lockfile=self.lockfile,
            security_podspec=self.security_podspec,
            security_build=self.security_build,
            identity_podspec=self.identity_podspec,
            identity_sources=self.identity_sources,
        )
        actual_generated = generated_subject.generated_subject_sha256(
            pods=self.generated_pods,
            workspace=self.generated_workspace,
        )
        if actual_generated != self.accepted_generated_subject_sha256:
            raise BuildGuardError(
                "CocoaPods generated build bytes do not match the preaccepted generated-subject SHA-256"
            )
        return private_snapshot, actual_generated


class EventBackend(Protocol):
    def register(self, descriptor: int) -> None: ...
    def events(self, timeout: float) -> Sequence[object]: ...
    def close(self) -> None: ...


class KqueueVnodeBackend:
    """macOS vnode watcher used only for the physical field-build window."""

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
            "KQ_NOTE_RENAME",
            "KQ_NOTE_REVOKE",
        )
        missing = [name for name in required if not hasattr(select, name)]
        if missing:
            raise BuildGuardError(
                "macOS kqueue vnode monitoring is unavailable: " + ", ".join(missing)
            )
        self._queue = select.kqueue()
        self._fflags = (
            select.KQ_NOTE_DELETE
            | select.KQ_NOTE_WRITE
            | select.KQ_NOTE_EXTEND
            | select.KQ_NOTE_LINK
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
        return self._queue.control(None, 256, timeout)

    def close(self) -> None:
        self._queue.close()


def _lstat_identity(path: Path) -> tuple[int, ...]:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise BuildGuardError(f"build input disappeared before vnode admission: {path}") from error
    return provenance._stat_identity(metadata)


def _tree_watch_paths(root: Path, *, label: str) -> set[Path]:
    if not root.is_dir() or root.is_symlink():
        raise BuildGuardError(f"{label} is not one real generated directory: {root}")
    paths: set[Path] = {root}
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
    return paths


def _watch_paths(inputs: PrivateInputs) -> tuple[Path, ...]:
    """Return every regular file + directory whose mutation could change admitted inputs.

    Symlink objects are covered by their containing directory watcher. The provenance
    and generated-subject helpers independently prove that admitted symlinks are
    internal and stable before and after the compiler/linker window.
    """

    paths: set[Path] = {
        inputs.lockfile,
        inputs.security_podspec,
        inputs.identity_podspec,
    }
    paths.update(_tree_watch_paths(inputs.security_build, label="private security build tree"))
    paths.update(_tree_watch_paths(inputs.identity_sources, label="private identity source tree"))
    paths.update(_tree_watch_paths(inputs.generated_pods, label="CocoaPods generated Pods tree"))
    paths.update(
        _tree_watch_paths(
            inputs.generated_workspace,
            label="CocoaPods generated workspace tree",
        )
    )
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
                raise BuildGuardError(f"build input could not be opened for build-window custody: {path}") from error
            try:
                after = provenance._stat_identity(os.fstat(descriptor))
                if before != after:
                    raise BuildGuardError(f"build input changed while vnode custody was armed: {path}")
                mode = os.fstat(descriptor).st_mode
                if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
                    raise BuildGuardError(f"build input is not a watchable regular file/directory: {path}")
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


def run_guarded_build(
    inputs: PrivateInputs,
    command: Sequence[str],
    *,
    backend_factory: Callable[[], EventBackend] = KqueueVnodeBackend,
    popen_factory: Callable[..., subprocess.Popen] = subprocess.Popen,
    poll_interval: float = 0.10,
) -> int:
    if not command:
        raise BuildGuardError("no build command was supplied")

    initial_snapshot = inputs.generation_snapshot()
    backend = backend_factory()
    watched: tuple[tuple[int, Path], ...] = ()
    process: subprocess.Popen | None = None
    try:
        watched = _open_watched_inputs(_watch_paths(inputs), backend)

        # Registration itself has a race boundary. Reprove the entire admitted
        # private + generated generation after every vnode watch is armed, then
        # reject any queued mutation before the child build is allowed to start.
        armed_snapshot = inputs.generation_snapshot()
        if armed_snapshot != initial_snapshot:
            raise BuildGuardError("field build inputs changed while build-window monitoring was armed")
        queued = backend.events(0)
        if queued:
            raise BuildGuardError(
                "field build inputs changed before xcodebuild admission: "
                + _describe_events(queued, watched)
            )

        process = popen_factory(list(command))
        while process.poll() is None:
            events = backend.events(poll_interval)
            if events:
                _stop_process(process)
                raise BuildGuardError(
                    "field build input mutation was observed while xcodebuild was running: "
                    + _describe_events(events, watched)
                )

        trailing = backend.events(0)
        if trailing:
            raise BuildGuardError(
                "field build input mutation was observed at xcodebuild completion: "
                + _describe_events(trailing, watched)
            )

        # Keep every vnode watcher live while the final generation is sampled.
        # A mutation after this point cannot have affected the already-finished
        # child build; the install script still performs independent private
        # cryptographic verification immediately after this guard returns.
        final_snapshot = inputs.generation_snapshot()
        if final_snapshot != initial_snapshot:
            raise BuildGuardError("field build inputs changed across the guarded xcodebuild window")
        trailing = backend.events(0)
        if trailing:
            raise BuildGuardError(
                "field build input mutation was observed during final build-window verification: "
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


def _accepted_generated_subject_from_environment() -> str:
    value = os.environ.get(
        "NEMBRA_CAPTURE_ACCEPTED_TUYA_GENERATED_SUBJECT_SHA256", ""
    ).strip().lower()
    if re.fullmatch(r"[0-9a-f]{64}", value) is None:
        raise BuildGuardError(
            "NEMBRA_CAPTURE_ACCEPTED_TUYA_GENERATED_SUBJECT_SHA256 must contain the preaccepted 64-hex generated-subject digest"
        )
    return value


def _parse_args(argv: Sequence[str]) -> tuple[PrivateInputs, list[str]]:
    parser = argparse.ArgumentParser(
        description="Run the Capture field build while macOS vnode custody watches every admitted private and CocoaPods-generated input."
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

    lockfile = args.lockfile.resolve()
    generated_root = lockfile.parent
    return (
        PrivateInputs(
            lockfile=lockfile,
            security_podspec=args.security_podspec.resolve(),
            security_build=args.security_build.resolve(),
            identity_podspec=args.identity_podspec.resolve(),
            identity_sources=args.identity_sources.resolve(),
            generated_pods=generated_root / "Pods",
            generated_workspace=generated_root / "NembraCapture.xcworkspace",
            accepted_generated_subject_sha256=_accepted_generated_subject_from_environment(),
        ),
        command,
    )


def main(argv: Sequence[str] | None = None) -> int:
    try:
        inputs, command = _parse_args(sys.argv[1:] if argv is None else argv)
        return run_guarded_build(inputs, command)
    except BuildGuardError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 74
    except provenance.ProvenanceError as error:
        print(f"ERROR: private-input provenance rejected build-window custody: {error}", file=sys.stderr)
        return 75
    except generated_subject.GeneratedSubjectError as error:
        print(f"ERROR: generated-subject authority rejected build-window custody: {error}", file=sys.stderr)
        return 76


if __name__ == "__main__":
    raise SystemExit(main())

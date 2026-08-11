#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import os
import select
import stat
import subprocess
import sys
import time
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


def _load_generated_build_subject_module():
    helper = Path(__file__).with_name("capture_cocoapods_generated_build_subject.py")
    spec = importlib.util.spec_from_file_location("capture_cocoapods_generated_build_subject", helper)
    if spec is None or spec.loader is None:
        raise BuildGuardError("generated CocoaPods build-subject helper could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


provenance = _load_provenance_module()
generated_build_subject = _load_generated_build_subject_module()


@dataclass(frozen=True)
class PrivateInputs:
    lockfile: Path
    security_podspec: Path
    security_build: Path
    identity_podspec: Path
    identity_sources: Path

    @property
    def generated_pods(self) -> Path:
        return self.lockfile.parent / "Pods"

    @property
    def generated_workspace(self) -> Path:
        return self.lockfile.parent / "NembraCapture.xcworkspace"

    def generation_snapshot(self):
        private_snapshot = provenance._private_input_record_generation_snapshot(
            lockfile=self.lockfile,
            security_podspec=self.security_podspec,
            security_build=self.security_build,
            identity_podspec=self.identity_podspec,
            identity_sources=self.identity_sources,
        )
        try:
            generated_sha256 = generated_build_subject.fingerprint_subject(
                self.generated_pods,
                self.generated_workspace,
                separately_guarded_external_roots=(
                    self.security_podspec.parent,
                    self.identity_podspec.parent,
                ),
            )
        except generated_build_subject.SubjectError as error:
            raise BuildGuardError(
                f"generated CocoaPods build subject could not be admitted: {error}"
            ) from error
        return private_snapshot, generated_sha256


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


def _lstat_identity(path: Path) -> tuple[int, int, int, int, int, int, int]:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise BuildGuardError(f"private build input disappeared before vnode admission: {path}") from error
    return provenance._stat_identity(metadata)


def _watch_paths(inputs: PrivateInputs) -> tuple[Path, ...]:
    """Return every regular file + directory whose mutation could change the field build.

    The private provenance snapshot owns exact Tuya inputs. The generated-subject
    fingerprint independently owns Pods + workspace bytes. Symlink objects are
    covered by their containing directory watcher while each snapshot revalidates
    the corresponding path graph before and after xcodebuild.
    """

    paths: set[Path] = {
        inputs.lockfile,
        inputs.security_podspec,
        inputs.identity_podspec,
    }
    for root in (
        inputs.security_build,
        inputs.identity_sources,
        inputs.generated_pods,
        inputs.generated_workspace,
    ):
        if not root.is_dir() or root.is_symlink():
            raise BuildGuardError(f"field build input tree is not one real directory: {root}")
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


def _canonical_expected_generated_subject(value: str | None) -> str:
    if value is None:
        raise BuildGuardError(
            "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 is required before xcodebuild admission"
        )
    normalized = value.lower()
    if len(normalized) != 64 or any(character not in "0123456789abcdef" for character in normalized):
        raise BuildGuardError(
            "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 must be exactly 64 hex characters"
        )
    return normalized


def run_guarded_build(
    inputs: PrivateInputs,
    command: Sequence[str],
    *,
    expected_generated_subject_sha256: str | None = None,
    backend_factory: Callable[[], EventBackend] = KqueueVnodeBackend,
    popen_factory: Callable[..., subprocess.Popen] = subprocess.Popen,
    poll_interval: float = 0.10,
) -> int:
    if not command:
        raise BuildGuardError("no build command was supplied")

    initial_snapshot = inputs.generation_snapshot()
    if expected_generated_subject_sha256 is not None:
        expected = _canonical_expected_generated_subject(expected_generated_subject_sha256)
        if initial_snapshot[1] != expected:
            raise BuildGuardError(
                "generated CocoaPods build subject no longer matches the preaccepted SHA-256 before xcodebuild"
            )

    backend = backend_factory()
    watched: tuple[tuple[int, Path], ...] = ()
    process: subprocess.Popen | None = None
    try:
        watched = _open_watched_inputs(_watch_paths(inputs), backend)

        # Registration itself has a race boundary. Reprove every admitted private
        # and generated build subject after all vnode watches are armed, then reject
        # any queued mutation before the child build is allowed to start.
        armed_snapshot = inputs.generation_snapshot()
        if armed_snapshot != initial_snapshot:
            raise BuildGuardError("field build inputs changed while build-window monitoring was armed")
        if expected_generated_subject_sha256 is not None and armed_snapshot[1] != expected:
            raise BuildGuardError(
                "generated CocoaPods build subject lost preaccepted authority while monitoring was armed"
            )
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

        # Keep every vnode watcher live while the final generations are sampled.
        # A mutation after this point cannot have affected the already-finished
        # child build; the install script still performs its independent private
        # cryptographic provenance verification immediately after this guard returns.
        final_snapshot = inputs.generation_snapshot()
        if final_snapshot != initial_snapshot:
            raise BuildGuardError("field build inputs changed across the guarded xcodebuild window")
        if expected_generated_subject_sha256 is not None and final_snapshot[1] != expected:
            raise BuildGuardError(
                "generated CocoaPods build subject lost preaccepted authority across xcodebuild"
            )
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


def _parse_args(argv: Sequence[str]) -> tuple[PrivateInputs, list[str]]:
    parser = argparse.ArgumentParser(
        description="Run the Capture field build while macOS vnode custody watches every admitted private and generated input."
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
    return (
        PrivateInputs(
            lockfile=args.lockfile.resolve(),
            security_podspec=args.security_podspec.resolve(),
            security_build=args.security_build.resolve(),
            identity_podspec=args.identity_podspec.resolve(),
            identity_sources=args.identity_sources.resolve(),
        ),
        command,
    )


def main(argv: Sequence[str] | None = None) -> int:
    inputs, command = _parse_args(sys.argv[1:] if argv is None else argv)
    try:
        expected_generated_subject_sha256 = _canonical_expected_generated_subject(
            os.environ.get("NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256")
        )
        return run_guarded_build(
            inputs,
            command,
            expected_generated_subject_sha256=expected_generated_subject_sha256,
        )
    except BuildGuardError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 74
    except provenance.ProvenanceError as error:
        print(f"ERROR: private-input provenance rejected build-window custody: {error}", file=sys.stderr)
        return 75


if __name__ == "__main__":
    raise SystemExit(main())

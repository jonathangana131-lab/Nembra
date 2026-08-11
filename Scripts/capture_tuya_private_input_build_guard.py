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


def _load_helper(name: str, filename: str):
    helper = Path(__file__).with_name(filename)
    spec = importlib.util.spec_from_file_location(name, helper)
    if spec is None or spec.loader is None:
        raise BuildGuardError(f"build-custody helper could not be loaded: {filename}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


provenance = _load_helper(
    "capture_tuya_private_input_provenance",
    "capture_tuya_private_input_provenance.py",
)
cocoapods_build_subject = _load_helper(
    "capture_cocoapods_build_subject",
    "capture_cocoapods_build_subject.py",
)


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


@dataclass(frozen=True)
class CocoaPodsBuildSubject:
    root: Path
    expected_digest: str

    def snapshot(self) -> str:
        actual = cocoapods_build_subject.fingerprint(self.root)
        if actual != self.expected_digest:
            raise BuildGuardError(
                "generated CocoaPods build subject no longer matches Final GO authority"
            )
        return actual


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
            "KQ_NOTE_ATTRIB",
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
            | select.KQ_NOTE_ATTRIB
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
        raise BuildGuardError(f"admitted build input disappeared before vnode admission: {path}") from error
    return provenance._stat_identity(metadata)


def _generated_watch_paths(root: Path) -> set[Path]:
    """Return real generated files/directories that can be vnode-watched.

    Symlink objects are intentionally not opened: their containing directory is
    watched for replacement/rename while the build-subject fingerprint binds the
    exact link text and requires an internal, resolvable target. Any target that
    is also a generated or private admitted node is independently watched there.
    """

    paths: set[Path] = set()
    for relative in (Path("Pods"), Path("NembraCapture.xcworkspace")):
        tree = root / relative
        try:
            metadata = tree.lstat()
        except OSError as error:
            raise BuildGuardError(f"generated build tree disappeared before vnode admission: {tree}") from error
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            raise BuildGuardError(f"generated build tree is not one real directory: {tree}")
        paths.add(tree)
        for current_root, directories, files in os.walk(tree, topdown=True, followlinks=False):
            current = Path(current_root)
            paths.add(current)
            kept: list[str] = []
            for name in directories:
                candidate = current / name
                candidate_metadata = candidate.lstat()
                if stat.S_ISLNK(candidate_metadata.st_mode):
                    continue
                if not stat.S_ISDIR(candidate_metadata.st_mode):
                    raise BuildGuardError(f"unsupported generated directory entry: {candidate}")
                paths.add(candidate)
                kept.append(name)
            directories[:] = kept
            for name in files:
                candidate = current / name
                candidate_metadata = candidate.lstat()
                if stat.S_ISLNK(candidate_metadata.st_mode):
                    continue
                if not stat.S_ISREG(candidate_metadata.st_mode):
                    raise BuildGuardError(f"unsupported generated file entry: {candidate}")
                paths.add(candidate)
    return paths


def _watch_paths(
    inputs: PrivateInputs,
    build_subject: CocoaPodsBuildSubject | None = None,
) -> tuple[Path, ...]:
    """Return every regular file + directory whose mutation could change admitted inputs.

    Symlink objects are covered by their containing directory watcher. The provenance
    helpers independently prove that every admitted link remains internal and stable.
    """

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
    if build_subject is not None:
        if inputs.lockfile != build_subject.root / "Podfile.lock":
            raise BuildGuardError(
                "generated CocoaPods authority and private-input authority do not name the same Podfile.lock"
            )
        paths.update(_generated_watch_paths(build_subject.root))
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
                raise BuildGuardError(f"admitted build input could not be opened for build-window custody: {path}") from error
            try:
                after = provenance._stat_identity(os.fstat(descriptor))
                if before != after:
                    raise BuildGuardError(f"admitted build input changed while vnode custody was armed: {path}")
                mode = os.fstat(descriptor).st_mode
                if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
                    raise BuildGuardError(f"admitted build input is not a watchable regular file/directory: {path}")
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
    build_subject: CocoaPodsBuildSubject | None = None,
    backend_factory: Callable[[], EventBackend] = KqueueVnodeBackend,
    popen_factory: Callable[..., subprocess.Popen] = subprocess.Popen,
    poll_interval: float = 0.10,
) -> int:
    if not command:
        raise BuildGuardError("no build command was supplied")

    initial_snapshot = inputs.generation_snapshot()
    initial_build_subject = build_subject.snapshot() if build_subject is not None else None
    backend = backend_factory()
    watched: tuple[tuple[int, Path], ...] = ()
    process: subprocess.Popen | None = None
    try:
        watched = _open_watched_inputs(_watch_paths(inputs, build_subject), backend)

        # Registration itself has a race boundary. Reprove every admitted
        # generation after every vnode watch is armed, then reject any queued
        # mutation before the child build is allowed to start.
        armed_snapshot = inputs.generation_snapshot()
        armed_build_subject = build_subject.snapshot() if build_subject is not None else None
        if armed_snapshot != initial_snapshot or armed_build_subject != initial_build_subject:
            raise BuildGuardError("admitted build inputs changed while build-window monitoring was armed")
        queued = backend.events(0)
        if queued:
            raise BuildGuardError(
                "admitted build inputs changed before xcodebuild admission: "
                + _describe_events(queued, watched)
            )

        process = popen_factory(list(command))
        while process.poll() is None:
            events = backend.events(poll_interval)
            if events:
                _stop_process(process)
                raise BuildGuardError(
                    "admitted build-input mutation was observed while xcodebuild was running: "
                    + _describe_events(events, watched)
                )

        trailing = backend.events(0)
        if trailing:
            raise BuildGuardError(
                "admitted build-input mutation was observed at xcodebuild completion: "
                + _describe_events(trailing, watched)
            )

        # Keep every vnode watcher live while the final generations are sampled.
        # A mutation after this point cannot have affected the already-finished
        # child build; the install script still performs independent cryptographic
        # verification immediately after this guard returns.
        final_snapshot = inputs.generation_snapshot()
        final_build_subject = build_subject.snapshot() if build_subject is not None else None
        if final_snapshot != initial_snapshot or final_build_subject != initial_build_subject:
            raise BuildGuardError("admitted build inputs changed across the guarded xcodebuild window")
        trailing = backend.events(0)
        if trailing:
            raise BuildGuardError(
                "admitted build-input mutation was observed during final build-window verification: "
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


def _parse_args(
    argv: Sequence[str],
) -> tuple[PrivateInputs, CocoaPodsBuildSubject | None, list[str]]:
    parser = argparse.ArgumentParser(
        description="Run the Capture field build while macOS vnode custody watches every admitted private/generated build input."
    )
    parser.add_argument("--lockfile", required=True, type=Path)
    parser.add_argument("--security-podspec", required=True, type=Path)
    parser.add_argument("--security-build", required=True, type=Path)
    parser.add_argument("--identity-podspec", required=True, type=Path)
    parser.add_argument("--identity-sources", required=True, type=Path)
    parser.add_argument("--cocoapods-root", type=Path)
    parser.add_argument("--cocoapods-build-subject-sha256", default="")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(list(argv))
    command = list(args.command)
    if command and command[0] == "--":
        command = command[1:]

    root_supplied = args.cocoapods_root is not None
    digest_supplied = bool(args.cocoapods_build_subject_sha256)
    if root_supplied != digest_supplied:
        parser.error(
            "--cocoapods-root and --cocoapods-build-subject-sha256 must be supplied together"
        )
    build_subject: CocoaPodsBuildSubject | None = None
    if root_supplied:
        expected_digest = args.cocoapods_build_subject_sha256.lower()
        if len(expected_digest) != 64 or any(character not in "0123456789abcdef" for character in expected_digest):
            parser.error("--cocoapods-build-subject-sha256 must be exactly 64 hexadecimal characters")
        build_subject = CocoaPodsBuildSubject(
            root=args.cocoapods_root.resolve(),
            expected_digest=expected_digest,
        )

    return (
        PrivateInputs(
            lockfile=args.lockfile.resolve(),
            security_podspec=args.security_podspec.resolve(),
            security_build=args.security_build.resolve(),
            identity_podspec=args.identity_podspec.resolve(),
            identity_sources=args.identity_sources.resolve(),
        ),
        build_subject,
        command,
    )


def _build_subject_from_final_go_environment(inputs: PrivateInputs) -> CocoaPodsBuildSubject:
    expected_digest = os.environ.get(
        "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256",
        "",
    ).lower()
    if len(expected_digest) != 64 or any(character not in "0123456789abcdef" for character in expected_digest):
        raise BuildGuardError(
            "Final GO did not provide a valid NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 for build-window custody"
        )
    return CocoaPodsBuildSubject(
        root=inputs.lockfile.parent,
        expected_digest=expected_digest,
    )


def main(argv: Sequence[str] | None = None) -> int:
    inputs, build_subject, command = _parse_args(sys.argv[1:] if argv is None else argv)
    try:
        if build_subject is None:
            build_subject = _build_subject_from_final_go_environment(inputs)
        return run_guarded_build(inputs, command, build_subject=build_subject)
    except BuildGuardError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 74
    except provenance.ProvenanceError as error:
        print(f"ERROR: private-input provenance rejected build-window custody: {error}", file=sys.stderr)
        return 75
    except cocoapods_build_subject.BuildSubjectError as error:
        print(f"ERROR: generated CocoaPods build subject rejected build-window custody: {error}", file=sys.stderr)
        return 76


if __name__ == "__main__":
    raise SystemExit(main())

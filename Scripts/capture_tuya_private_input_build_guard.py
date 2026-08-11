#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import os
import resource
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


def _load_helper(module_name: str, filename: str):
    helper = Path(__file__).with_name(filename)
    spec = importlib.util.spec_from_file_location(module_name, helper)
    if spec is None or spec.loader is None:
        raise BuildGuardError(f"accepted build-input helper could not be loaded: {filename}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


provenance = _load_helper(
    "capture_tuya_private_input_provenance",
    "capture_tuya_private_input_provenance.py",
)
build_subject = _load_helper(
    "capture_cocoapods_build_subject",
    "capture_cocoapods_build_subject.py",
)


def _normalize_sha256(value: str) -> str:
    normalized = value.lower()
    if len(normalized) != 64 or any(character not in "0123456789abcdef" for character in normalized):
        raise BuildGuardError("expected accepted lock digest must be exactly 64 hexadecimal characters")
    return normalized


@dataclass(frozen=True)
class PrivateInputs:
    lockfile: Path
    security_podspec: Path
    security_build: Path
    identity_podspec: Path
    identity_sources: Path
    expected_lock_sha256: str

    @property
    def generated_pods(self) -> Path:
        return self.lockfile.parent / "Pods"

    @property
    def generated_workspace(self) -> Path:
        return self.lockfile.parent / "NembraCapture.xcworkspace"

    @property
    def generated_manifest(self) -> Path:
        return self.generated_pods / "Manifest.lock"

    def _lock_mirror_snapshot(self) -> tuple[str, str]:
        expected_lock_sha256 = _normalize_sha256(self.expected_lock_sha256)
        try:
            lock_sha256 = build_subject.stable_file_sha256(self.lockfile)
            manifest_sha256 = build_subject.stable_file_sha256(self.generated_manifest)
        except build_subject.BuildSubjectError as error:
            raise BuildGuardError(
                f"CocoaPods lock/manifest mirror could not be admitted: {error}"
            ) from error
        if lock_sha256 != expected_lock_sha256:
            raise BuildGuardError(
                "current attested Podfile.lock does not match the preaccepted field-build lock digest"
            )
        if manifest_sha256 != lock_sha256:
            raise BuildGuardError(
                "Pods/Manifest.lock does not exactly mirror the reviewed attested Podfile.lock"
            )
        return lock_sha256, manifest_sha256

    def generation_snapshot(self):
        private_snapshot = provenance._private_input_record_generation_snapshot(
            lockfile=self.lockfile,
            security_podspec=self.security_podspec,
            security_build=self.security_build,
            identity_podspec=self.identity_podspec,
            identity_sources=self.identity_sources,
        )
        lock_mirror_snapshot = self._lock_mirror_snapshot()
        try:
            accepted_generated_sha256 = build_subject.read_attestation(self.lockfile)
            observed_generated_sha256 = build_subject.build_subject_fingerprint(
                pods=self.generated_pods,
                workspace=self.generated_workspace,
            )
        except build_subject.BuildSubjectError as error:
            raise BuildGuardError(
                f"CocoaPods generated-build subject could not be admitted: {error}"
            ) from error
        if observed_generated_sha256 != accepted_generated_sha256:
            raise BuildGuardError(
                "CocoaPods generated-build subject does not match the reviewed Podfile.lock attestation"
            )

        # The private subject, mirrored lock, and generated graph are collected
        # sequentially. Re-sample both independent authority halves before
        # returning one generation witness so a transient mixed state cannot be
        # represented as an accepted compile input.
        final_lock_mirror_snapshot = self._lock_mirror_snapshot()
        final_private_snapshot = provenance._private_input_record_generation_snapshot(
            lockfile=self.lockfile,
            security_podspec=self.security_podspec,
            security_build=self.security_build,
            identity_podspec=self.identity_podspec,
            identity_sources=self.identity_sources,
        )
        if final_private_snapshot != private_snapshot:
            raise BuildGuardError(
                "accepted private inputs changed while the generated-build subject was snapshotted"
            )
        if final_lock_mirror_snapshot != lock_mirror_snapshot:
            raise BuildGuardError(
                "CocoaPods attested lock/manifest mirror changed while the generated-build subject was snapshotted"
            )
        return (
            private_snapshot,
            lock_mirror_snapshot,
            accepted_generated_sha256,
            observed_generated_sha256,
        )


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
        raise BuildGuardError(f"accepted build input disappeared before vnode admission: {path}") from error
    return provenance._stat_identity(metadata)


def _watch_paths(inputs: PrivateInputs) -> tuple[Path, ...]:
    """Return every real regular file/directory that can change accepted build inputs.

    Symlink objects are covered by their containing directory watcher. Private
    provenance separately proves its admitted links stay internal. CocoaPods
    links may intentionally point to LocalSecrets; this guard fingerprints their
    link text while the private-input half separately guards the target bytes.
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
            raise BuildGuardError(f"accepted build input tree is not one real directory: {root}")
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


def _ensure_watch_descriptor_budget(path_count: int) -> None:
    """Raise only this process' soft file-descriptor limit when the OS permits it."""

    # Keep headroom for Python, kqueue, xcodebuild launch plumbing, and the
    # installer's inherited descriptors. The hard limit remains unchanged.
    required = path_count + 128
    try:
        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
    except (OSError, ValueError) as error:
        raise BuildGuardError("could not inspect the field-build vnode descriptor limit") from error
    if soft >= required:
        return
    if hard != resource.RLIM_INFINITY and hard < required:
        raise BuildGuardError(
            f"accepted generated build subject requires {required} vnode descriptors but the process hard limit is {hard}"
        )
    try:
        resource.setrlimit(resource.RLIMIT_NOFILE, (required, hard))
        raised_soft, _ = resource.getrlimit(resource.RLIMIT_NOFILE)
    except (OSError, ValueError) as error:
        raise BuildGuardError(
            f"could not raise the field-build vnode descriptor limit from {soft} to {required}"
        ) from error
    if raised_soft < required:
        raise BuildGuardError(
            f"field-build vnode descriptor limit remained {raised_soft}; {required} are required for exact generated-input custody"
        )


def _open_watched_inputs(paths: Iterable[Path], backend: EventBackend) -> tuple[tuple[int, Path], ...]:
    opened: list[tuple[int, Path]] = []
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        for path in paths:
            before = _lstat_identity(path)
            try:
                descriptor = os.open(path, flags)
            except OSError as error:
                raise BuildGuardError(f"accepted build input could not be opened for build-window custody: {path}") from error
            try:
                after = provenance._stat_identity(os.fstat(descriptor))
                if before != after:
                    raise BuildGuardError(f"accepted build input changed while vnode custody was armed: {path}")
                mode = os.fstat(descriptor).st_mode
                if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
                    raise BuildGuardError(f"accepted build input is not a watchable regular file/directory: {path}")
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
    watch_paths = _watch_paths(inputs)
    _ensure_watch_descriptor_budget(len(watch_paths))
    backend = backend_factory()
    watched: tuple[tuple[int, Path], ...] = ()
    process: subprocess.Popen | None = None
    try:
        watched = _open_watched_inputs(watch_paths, backend)

        # Registration itself has a race boundary. Reprove the complete private
        # + generated build subject after every vnode watch is armed, then reject
        # any queued mutation before the child build is allowed to start.
        armed_snapshot = inputs.generation_snapshot()
        if armed_snapshot != initial_snapshot:
            raise BuildGuardError("accepted build inputs changed while build-window monitoring was armed")
        queued = backend.events(0)
        if queued:
            raise BuildGuardError(
                "accepted build inputs changed before xcodebuild admission: "
                + _describe_events(queued, watched)
            )

        process = popen_factory(list(command))
        while process.poll() is None:
            events = backend.events(poll_interval)
            if events:
                _stop_process(process)
                raise BuildGuardError(
                    "accepted build input mutation was observed while xcodebuild was running: "
                    + _describe_events(events, watched)
                )

        trailing = backend.events(0)
        if trailing:
            raise BuildGuardError(
                "accepted build input mutation was observed at xcodebuild completion: "
                + _describe_events(trailing, watched)
            )

        # Keep every vnode watcher live while the final complete generation is
        # sampled. A later mutation cannot affect the already-finished child;
        # the installer still performs its independent cryptographic private-
        # input verification immediately after this guard returns.
        final_snapshot = inputs.generation_snapshot()
        if final_snapshot != initial_snapshot:
            raise BuildGuardError("accepted build inputs changed across the guarded xcodebuild window")
        trailing = backend.events(0)
        if trailing:
            raise BuildGuardError(
                "accepted build input mutation was observed during final build-window verification: "
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
        description="Run the Capture field build while macOS vnode custody watches every accepted private and generated build input."
    )
    parser.add_argument("--lockfile", required=True, type=Path)
    parser.add_argument("--security-podspec", required=True, type=Path)
    parser.add_argument("--security-build", required=True, type=Path)
    parser.add_argument("--identity-podspec", required=True, type=Path)
    parser.add_argument("--identity-sources", required=True, type=Path)
    parser.add_argument("--expected-lock-sha256", required=True)
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
            expected_lock_sha256=_normalize_sha256(args.expected_lock_sha256),
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


if __name__ == "__main__":
    raise SystemExit(main())

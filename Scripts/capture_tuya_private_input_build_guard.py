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


def _load_sibling(name: str):
    helper = Path(__file__).with_name(name)
    spec = importlib.util.spec_from_file_location(helper.stem, helper)
    if spec is None or spec.loader is None:
        raise BuildGuardError(f"accepted build-custody helper could not be loaded: {helper.name}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


provenance = _load_sibling("capture_tuya_private_input_provenance.py")
cocoapods_subject = _load_sibling("capture_cocoapods_build_subject.py")


@dataclass(frozen=True)
class PrivateInputs:
    lockfile: Path
    security_podspec: Path
    security_build: Path
    identity_podspec: Path
    identity_sources: Path
    generated_pods: Path | None = None
    generated_workspace: Path | None = None
    accepted_generated_sha256: str | None = None

    def _private_snapshot(self):
        return provenance._private_input_record_generation_snapshot(
            lockfile=self.lockfile,
            security_podspec=self.security_podspec,
            security_build=self.security_build,
            identity_podspec=self.identity_podspec,
            identity_sources=self.identity_sources,
        )

    def generated_snapshot(self) -> str | None:
        if self.generated_pods is None and self.generated_workspace is None:
            return None
        if self.generated_pods is None or self.generated_workspace is None:
            raise BuildGuardError("generated CocoaPods custody requires both Pods and workspace roots")
        try:
            return cocoapods_subject.digest_generated_subject(
                self.generated_pods,
                self.generated_workspace,
            )
        except (OSError, ValueError) as error:
            raise BuildGuardError(f"generated CocoaPods subject could not be sampled: {error}") from error

    def generation_snapshot(self):
        return self._private_snapshot(), self.generated_snapshot()

    def require_accepted_generated_subject(self) -> None:
        actual = self.generated_snapshot()
        if actual is None:
            return
        expected = (self.accepted_generated_sha256 or "").lower()
        if re.fullmatch(r"[0-9a-f]{64}", expected) is None:
            raise BuildGuardError(
                "accepted CocoaPods generated build-subject authority is missing or malformed before xcodebuild"
            )
        if actual != expected:
            raise BuildGuardError(
                "generated CocoaPods build subject changed after bootstrap acceptance and before xcodebuild"
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
            raise BuildGuardError("macOS kqueue vnode monitoring is unavailable: " + ", ".join(missing))
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
        self._queue.control(
            [
                select.kevent(
                    descriptor,
                    filter=select.KQ_FILTER_VNODE,
                    flags=select.KQ_EV_ADD | select.KQ_EV_ENABLE | select.KQ_EV_CLEAR,
                    fflags=self._fflags,
                )
            ],
            0,
            0,
        )

    def events(self, timeout: float) -> Sequence[object]:
        return self._queue.control(None, 256, timeout)

    def close(self) -> None:
        self._queue.close()


def _lstat_identity(path: Path) -> tuple[int, int, int, int, int, int, int]:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise BuildGuardError(f"field build input disappeared before vnode admission: {path}") from error
    return provenance._stat_identity(metadata)


def _add_real_tree(paths: set[Path], root: Path, label: str) -> None:
    if not root.is_dir() or root.is_symlink():
        raise BuildGuardError(f"{label} is not one real directory: {root}")
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


def _watch_paths(inputs: PrivateInputs) -> tuple[Path, ...]:
    """Return every regular file + directory whose mutation could change admitted build bytes."""

    paths: set[Path] = {inputs.lockfile, inputs.security_podspec, inputs.identity_podspec}
    _add_real_tree(paths, inputs.security_build, "private security build tree")
    _add_real_tree(paths, inputs.identity_sources, "private identity source tree")
    if inputs.generated_pods is not None:
        _add_real_tree(paths, inputs.generated_pods, "generated Pods tree")
    if inputs.generated_workspace is not None:
        _add_real_tree(paths, inputs.generated_workspace, "generated Capture workspace")
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
                raise BuildGuardError(f"field build input could not be opened for build-window custody: {path}") from error
            try:
                after = provenance._stat_identity(os.fstat(descriptor))
                if before != after:
                    raise BuildGuardError(f"field build input changed while vnode custody was armed: {path}")
                mode = os.fstat(descriptor).st_mode
                if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
                    raise BuildGuardError(f"field build input is not a watchable regular file/directory: {path}")
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

    # Rebind the generated subject to externally accepted authority at the last
    # possible point before watcher admission. This closes the bootstrap -> build
    # gap; the watchers + before/after snapshots close the compiler-window gap.
    inputs.require_accepted_generated_subject()
    initial_snapshot = inputs.generation_snapshot()
    backend = backend_factory()
    watched: tuple[tuple[int, Path], ...] = ()
    process: subprocess.Popen | None = None
    try:
        watched = _open_watched_inputs(_watch_paths(inputs), backend)
        armed_snapshot = inputs.generation_snapshot()
        if armed_snapshot != initial_snapshot:
            raise BuildGuardError("field build inputs changed while build-window monitoring was armed")
        queued = backend.events(0)
        if queued:
            raise BuildGuardError(
                "field build inputs changed before xcodebuild admission: " + _describe_events(queued, watched)
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


def _parse_args(argv: Sequence[str]) -> tuple[PrivateInputs, list[str]]:
    parser = argparse.ArgumentParser(
        description="Run the Capture field build while macOS vnode custody watches every admitted private/generated input."
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

    # The lockfile is the repository-root Podfile.lock in the canonical installer.
    # Discover ignored generated roots from that same accepted root without adding
    # new caller-controlled path authority. Non-field/unit callers without those
    # roots preserve the preexisting private-input-only guard behavior.
    repository_root = args.lockfile.resolve().parent
    generated_pods = repository_root / "Pods"
    generated_workspace = repository_root / "NembraCapture.xcworkspace"
    if not generated_pods.exists() and not generated_workspace.exists():
        generated_pods_value = None
        generated_workspace_value = None
        accepted_generated = None
    elif generated_pods.is_dir() and generated_workspace.is_dir():
        generated_pods_value = generated_pods
        generated_workspace_value = generated_workspace
        accepted_generated = os.environ.get("NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SHA256")
    else:
        raise BuildGuardError("generated CocoaPods custody roots are incomplete before xcodebuild")

    return (
        PrivateInputs(
            lockfile=args.lockfile.resolve(),
            security_podspec=args.security_podspec.resolve(),
            security_build=args.security_build.resolve(),
            identity_podspec=args.identity_podspec.resolve(),
            identity_sources=args.identity_sources.resolve(),
            generated_pods=generated_pods_value,
            generated_workspace=generated_workspace_value,
            accepted_generated_sha256=accepted_generated,
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

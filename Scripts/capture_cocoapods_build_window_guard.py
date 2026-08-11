#!/usr/bin/env python3
"""Run the field build while the accepted CocoaPods-generated subject stays immutable."""

from __future__ import annotations

import argparse
import importlib.util
import os
import subprocess
import sys
from pathlib import Path
from typing import Callable, Iterable, Sequence


class GeneratedBuildGuardError(RuntimeError):
    pass


def _load(name: str, filename: str):
    path = Path(__file__).with_name(filename)
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise GeneratedBuildGuardError(f"could not load accepted helper: {filename}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


subject = _load("capture_cocoapods_build_subject", "capture_cocoapods_build_subject.py")
private_guard = _load("capture_private_build_guard", "capture_tuya_private_input_build_guard.py")


def _watch_tree_paths(root: Path) -> tuple[Path, ...]:
    if not root.is_dir() or root.is_symlink():
        raise GeneratedBuildGuardError(f"generated build tree is not one real directory: {root}")
    paths: set[Path] = {root}
    for current_text, directories, files in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_text)
        paths.add(current)
        for name in directories:
            candidate = current / name
            if not candidate.is_symlink():
                paths.add(candidate)
        for name in files:
            candidate = current / name
            if not candidate.is_symlink():
                paths.add(candidate)
    return tuple(sorted(paths, key=lambda item: str(item)))


def _watch_paths(pods: Path, workspace: Path) -> tuple[Path, ...]:
    return tuple(sorted(set(_watch_tree_paths(pods)) | set(_watch_tree_paths(workspace)), key=lambda item: str(item)))


def run_guarded_build(
    *,
    pods: Path,
    workspace: Path,
    accepted_sha256: str,
    command: Sequence[str],
    backend_factory: Callable[[], object] = private_guard.KqueueVnodeBackend,
    popen_factory: Callable[..., subprocess.Popen] = subprocess.Popen,
    poll_interval: float = 0.10,
) -> int:
    if not command:
        raise GeneratedBuildGuardError("no build command was supplied")
    if len(accepted_sha256) != 64 or any(character not in "0123456789abcdef" for character in accepted_sha256):
        raise GeneratedBuildGuardError("accepted generated-build subject must be lowercase 64-hex")

    initial = subject.build_subject_fingerprint(pods=pods, workspace=workspace)
    if initial != accepted_sha256:
        raise GeneratedBuildGuardError("generated CocoaPods build subject does not match the reviewed Podfile.lock attestation")

    backend = backend_factory()
    watched: tuple[tuple[int, Path], ...] = ()
    process: subprocess.Popen | None = None
    try:
        watched = private_guard._open_watched_inputs(_watch_paths(pods, workspace), backend)
        armed = subject.build_subject_fingerprint(pods=pods, workspace=workspace)
        if armed != initial:
            raise GeneratedBuildGuardError("generated CocoaPods subject changed while vnode custody was armed")
        queued = backend.events(0)
        if queued:
            raise GeneratedBuildGuardError(
                "generated CocoaPods subject changed before xcodebuild admission: "
                + private_guard._describe_events(queued, watched)
            )

        process = popen_factory(list(command))
        while process.poll() is None:
            events = backend.events(poll_interval)
            if events:
                private_guard._stop_process(process)
                raise GeneratedBuildGuardError(
                    "generated CocoaPods input mutation was observed while xcodebuild was running: "
                    + private_guard._describe_events(events, watched)
                )

        trailing = backend.events(0)
        if trailing:
            raise GeneratedBuildGuardError(
                "generated CocoaPods input mutation was observed at xcodebuild completion: "
                + private_guard._describe_events(trailing, watched)
            )
        final = subject.build_subject_fingerprint(pods=pods, workspace=workspace)
        if final != initial:
            raise GeneratedBuildGuardError("generated CocoaPods build subject changed across the guarded xcodebuild window")
        trailing = backend.events(0)
        if trailing:
            raise GeneratedBuildGuardError(
                "generated CocoaPods input mutation was observed during final build-window verification: "
                + private_guard._describe_events(trailing, watched)
            )
        return int(process.returncode or 0)
    finally:
        if process is not None and process.poll() is None:
            private_guard._stop_process(process)
        for descriptor, _ in watched:
            try:
                os.close(descriptor)
            except OSError:
                pass
        backend.close()


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Guard accepted CocoaPods-generated Capture inputs during xcodebuild")
    parser.add_argument("--pods", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--accepted-sha256", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    args = _parser().parse_args(list(argv) if argv is not None else None)
    command = list(args.command)
    if command and command[0] == "--":
        command = command[1:]
    try:
        return run_guarded_build(
            pods=args.pods.resolve(),
            workspace=args.workspace.resolve(),
            accepted_sha256=args.accepted_sha256,
            command=command,
        )
    except GeneratedBuildGuardError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 76
    except subject.BuildSubjectError as error:
        print(f"ERROR: generated-build subject custody rejected build: {error}", file=sys.stderr)
        return 77
    except private_guard.BuildGuardError as error:
        print(f"ERROR: generated-build vnode custody rejected build: {error}", file=sys.stderr)
        return 78


if __name__ == "__main__":
    raise SystemExit(main())

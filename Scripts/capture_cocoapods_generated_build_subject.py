#!/usr/bin/env python3
"""Fingerprint CocoaPods-generated Capture build inputs without exposing their bytes.

This helper binds the generated build graph that sits between an accepted
Podfile.lock and xcodebuild.  It deliberately fingerprints ignored generated
inputs (Pods/ and NembraCapture.xcworkspace/) as a finite pathname/metadata/byte
snapshot.  Symlinks are fingerprinted as links and are not followed; the
separate private-input provenance contract remains authority for local private
Tuya targets.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import stat
from pathlib import Path
from typing import Iterable, Sequence

SCHEMA = b"nembra-capture-cocoapods-generated-build-subject-v1"


class GeneratedBuildSubjectError(RuntimeError):
    pass


def _feed(digest: "hashlib._Hash", value: bytes) -> None:
    digest.update(len(value).to_bytes(8, "big"))
    digest.update(value)


def _identity(metadata: os.stat_result) -> tuple[int, ...]:
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


def _members(path: Path) -> tuple[str, ...]:
    try:
        return tuple(sorted(os.listdir(path), key=os.fsencode))
    except OSError as error:
        raise GeneratedBuildSubjectError(
            f"generated build directory changed while fingerprinting: {path}"
        ) from error


def _read_regular(path: Path, expected: tuple[int, ...]) -> bytes:
    nofollow = getattr(os, "O_NOFOLLOW", None)
    if nofollow is None:
        raise GeneratedBuildSubjectError("generated build admission requires O_NOFOLLOW support")
    flags = os.O_RDONLY | nofollow | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise GeneratedBuildSubjectError(
            f"generated build file could not be opened safely: {path}"
        ) from error
    try:
        before = os.fstat(descriptor)
        if _identity(before) != expected or not stat.S_ISREG(before.st_mode):
            raise GeneratedBuildSubjectError(
                f"generated build file changed before read custody: {path}"
            )
        digest = hashlib.sha256()
        bytes_read = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
            bytes_read += len(chunk)
        after = os.fstat(descriptor)
        if _identity(after) != expected or bytes_read != after.st_size:
            raise GeneratedBuildSubjectError(
                f"generated build file changed while fingerprinting: {path}"
            )
        current = path.lstat()
        if _identity(current) != expected or not stat.S_ISREG(current.st_mode):
            raise GeneratedBuildSubjectError(
                f"generated build file pathname changed while fingerprinting: {path}"
            )
        return digest.digest()
    finally:
        os.close(descriptor)


def _tree_entries(root: Path) -> tuple[tuple[str, str, int, bytes], ...]:
    try:
        root_metadata = root.lstat()
    except OSError as error:
        raise GeneratedBuildSubjectError(
            f"required generated build directory is unavailable: {root}"
        ) from error
    if stat.S_ISLNK(root_metadata.st_mode) or not stat.S_ISDIR(root_metadata.st_mode):
        raise GeneratedBuildSubjectError(
            f"required generated build root is not a real directory: {root}"
        )

    states: list[tuple[Path, tuple[int, ...], str, str | None]] = [
        (root, _identity(root_metadata), "D", None)
    ]
    directory_members: dict[Path, tuple[str, ...]] = {}
    entries: list[tuple[str, str, int, bytes]] = []

    for current_text, directory_names, file_names in os.walk(
        root, topdown=True, followlinks=False
    ):
        current = Path(current_text)
        directory_members[current] = tuple(
            sorted((*directory_names, *file_names), key=os.fsencode)
        )
        kept_directories: list[str] = []

        for name in sorted(directory_names, key=os.fsencode):
            candidate = current / name
            relative = candidate.relative_to(root).as_posix()
            metadata = candidate.lstat()
            identity = _identity(metadata)
            mode = stat.S_IMODE(metadata.st_mode)
            if stat.S_ISLNK(metadata.st_mode):
                target = os.readlink(candidate)
                states.append((candidate, identity, "L", target))
                entries.append(("L", relative, mode, os.fsencode(target)))
            elif stat.S_ISDIR(metadata.st_mode):
                states.append((candidate, identity, "D", None))
                entries.append(("D", relative, mode, b""))
                kept_directories.append(name)
            else:
                raise GeneratedBuildSubjectError(
                    f"unsupported generated directory entry: {candidate}"
                )
        directory_names[:] = kept_directories

        for name in sorted(file_names, key=os.fsencode):
            candidate = current / name
            relative = candidate.relative_to(root).as_posix()
            metadata = candidate.lstat()
            identity = _identity(metadata)
            mode = stat.S_IMODE(metadata.st_mode)
            if stat.S_ISLNK(metadata.st_mode):
                target = os.readlink(candidate)
                states.append((candidate, identity, "L", target))
                entries.append(("L", relative, mode, os.fsencode(target)))
            elif stat.S_ISREG(metadata.st_mode):
                content_digest = _read_regular(candidate, identity)
                states.append((candidate, identity, "F", None))
                entries.append(("F", relative, mode, content_digest))
            else:
                raise GeneratedBuildSubjectError(
                    f"unsupported generated file entry: {candidate}"
                )

    for path, expected, kind, target in states:
        try:
            metadata = path.lstat()
        except OSError as error:
            raise GeneratedBuildSubjectError(
                f"generated build entry disappeared during final custody: {path}"
            ) from error
        if _identity(metadata) != expected:
            raise GeneratedBuildSubjectError(
                f"generated build entry changed during final custody: {path}"
            )
        if kind == "D" and not stat.S_ISDIR(metadata.st_mode):
            raise GeneratedBuildSubjectError(f"generated directory changed kind: {path}")
        if kind == "F" and not stat.S_ISREG(metadata.st_mode):
            raise GeneratedBuildSubjectError(f"generated file changed kind: {path}")
        if kind == "L":
            if not stat.S_ISLNK(metadata.st_mode) or os.readlink(path) != target:
                raise GeneratedBuildSubjectError(f"generated symlink changed: {path}")

    for directory, expected_members in directory_members.items():
        if _members(directory) != expected_members:
            raise GeneratedBuildSubjectError(
                f"generated build directory membership changed: {directory}"
            )

    return tuple(sorted(entries, key=lambda item: os.fsencode(item[1])))


def _tree_fingerprint(root: Path) -> str:
    digest = hashlib.sha256()
    _feed(digest, b"nembra-cocoapods-generated-tree-v1")
    for kind, relative, mode, payload in _tree_entries(root):
        _feed(digest, kind.encode("ascii"))
        _feed(digest, os.fsencode(relative))
        _feed(digest, mode.to_bytes(4, "big"))
        _feed(digest, payload)
    return digest.hexdigest()


def _regular_fingerprint(path: Path) -> str:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise GeneratedBuildSubjectError(
            f"required generated build file is unavailable: {path}"
        ) from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise GeneratedBuildSubjectError(
            f"required generated build file is not a regular file: {path}"
        )
    content_digest = _read_regular(path, _identity(metadata))
    digest = hashlib.sha256()
    _feed(digest, b"nembra-cocoapods-generated-file-v1")
    _feed(digest, stat.S_IMODE(metadata.st_mode).to_bytes(4, "big"))
    _feed(digest, metadata.st_size.to_bytes(8, "big"))
    _feed(digest, content_digest)
    return digest.hexdigest()


def build_subject(*, lockfile: Path, pods: Path, workspace: Path) -> str:
    digest = hashlib.sha256()
    _feed(digest, SCHEMA)
    _feed(digest, bytes.fromhex(_regular_fingerprint(lockfile)))
    _feed(digest, bytes.fromhex(_tree_fingerprint(pods)))
    _feed(digest, bytes.fromhex(_tree_fingerprint(workspace)))
    return digest.hexdigest()


def generation_snapshot(roots: Sequence[Path]) -> tuple[tuple[str, str], ...]:
    """Return stable fingerprints suitable for before/after build-window comparison."""
    snapshots: list[tuple[str, str]] = []
    for root in roots:
        snapshots.append((str(root), _tree_fingerprint(root)))
    return tuple(snapshots)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Fingerprint the exact generated CocoaPods build subject used by Nembra Capture."
    )
    parser.add_argument("--lockfile", required=True, type=Path)
    parser.add_argument("--pods", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    arguments = _parser().parse_args(list(argv) if argv is not None else None)
    try:
        fingerprint = build_subject(
            lockfile=arguments.lockfile.resolve(),
            pods=arguments.pods.resolve(),
            workspace=arguments.workspace.resolve(),
        )
    except (GeneratedBuildSubjectError, OSError, ValueError) as error:
        print(f"ERROR: generated CocoaPods build subject rejected: {error}", file=os.sys.stderr)
        return 73
    print(fingerprint)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

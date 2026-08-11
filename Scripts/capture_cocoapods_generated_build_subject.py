#!/usr/bin/env python3
"""Fingerprint the exact CocoaPods-generated build subject used by Nembra Capture.

This digest is review authority for generated build inputs only. It does not make
Podfile.lock, CocoaPods output, or any private Tuya input physical evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import stat
import sys
import tempfile
from pathlib import Path
from typing import Iterable


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


def _stable_file_digest(path: Path) -> tuple[int, str]:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise GeneratedBuildSubjectError(f"generated build input is unavailable or unsafe: {path}") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise GeneratedBuildSubjectError(f"generated build input is not a regular file: {path}")
        before_identity = _identity(before)
        digest = hashlib.sha256()
        size = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            size += len(chunk)
            digest.update(chunk)
        after = os.fstat(descriptor)
        if _identity(after) != before_identity or size != after.st_size:
            raise GeneratedBuildSubjectError(f"generated build input changed while fingerprinted: {path}")
        try:
            path_after = path.lstat()
        except OSError as error:
            raise GeneratedBuildSubjectError(f"generated build pathname changed while fingerprinted: {path}") from error
        if stat.S_ISLNK(path_after.st_mode) or _identity(path_after) != before_identity:
            raise GeneratedBuildSubjectError(f"generated build pathname changed while fingerprinted: {path}")
        return stat.S_IMODE(after.st_mode), digest.hexdigest()
    finally:
        os.close(descriptor)


def _tree_digest(root: Path) -> str:
    try:
        root_before = root.lstat()
    except OSError as error:
        raise GeneratedBuildSubjectError(f"generated build directory is unavailable: {root}") from error
    if stat.S_ISLNK(root_before.st_mode) or not stat.S_ISDIR(root_before.st_mode):
        raise GeneratedBuildSubjectError(f"generated build directory is not one real directory: {root}")

    observed: list[tuple[Path, tuple[int, ...], str, str | None]] = [
        (root, _identity(root_before), "D", None)
    ]
    memberships: dict[Path, tuple[str, ...]] = {}
    entries: list[tuple[str, str, int, bytes]] = []

    for current_text, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_text)
        memberships[current] = tuple(sorted((*directory_names, *file_names), key=os.fsencode))
        kept_directories: list[str] = []

        for name in sorted(directory_names, key=os.fsencode):
            path = current / name
            relative = path.relative_to(root).as_posix()
            metadata = path.lstat()
            identity = _identity(metadata)
            mode = stat.S_IMODE(metadata.st_mode)
            if stat.S_ISLNK(metadata.st_mode):
                target = os.readlink(path)
                observed.append((path, identity, "L", target))
                entries.append(("L", relative, mode, os.fsencode(target)))
            elif stat.S_ISDIR(metadata.st_mode):
                observed.append((path, identity, "D", None))
                entries.append(("D", relative, mode, b""))
                kept_directories.append(name)
            else:
                raise GeneratedBuildSubjectError(f"unsupported generated directory entry: {path}")
        directory_names[:] = kept_directories

        for name in sorted(file_names, key=os.fsencode):
            path = current / name
            relative = path.relative_to(root).as_posix()
            metadata = path.lstat()
            identity = _identity(metadata)
            mode = stat.S_IMODE(metadata.st_mode)
            if stat.S_ISLNK(metadata.st_mode):
                target = os.readlink(path)
                observed.append((path, identity, "L", target))
                entries.append(("L", relative, mode, os.fsencode(target)))
            elif stat.S_ISREG(metadata.st_mode):
                stable_mode, content_sha = _stable_file_digest(path)
                if stable_mode != mode:
                    raise GeneratedBuildSubjectError(f"generated build file mode changed while fingerprinted: {path}")
                observed.append((path, identity, "F", None))
                entries.append(("F", relative, mode, bytes.fromhex(content_sha)))
            else:
                raise GeneratedBuildSubjectError(f"unsupported generated file entry: {path}")

    for path, identity, kind, target in observed:
        try:
            metadata = path.lstat()
        except OSError as error:
            raise GeneratedBuildSubjectError("generated build tree changed while fingerprinted") from error
        if _identity(metadata) != identity:
            raise GeneratedBuildSubjectError("generated build tree changed while fingerprinted")
        if kind == "D" and not stat.S_ISDIR(metadata.st_mode):
            raise GeneratedBuildSubjectError("generated build tree changed while fingerprinted")
        if kind == "F" and not stat.S_ISREG(metadata.st_mode):
            raise GeneratedBuildSubjectError("generated build tree changed while fingerprinted")
        if kind == "L":
            if not stat.S_ISLNK(metadata.st_mode) or os.readlink(path) != target:
                raise GeneratedBuildSubjectError("generated build symlink changed while fingerprinted")

    for directory, members in memberships.items():
        try:
            current_members = tuple(sorted(os.listdir(directory), key=os.fsencode))
        except OSError as error:
            raise GeneratedBuildSubjectError("generated build tree membership changed while fingerprinted") from error
        if current_members != members:
            raise GeneratedBuildSubjectError("generated build tree membership changed while fingerprinted")

    digest = hashlib.sha256()
    _feed(digest, b"nembra-cocoapods-generated-tree-v1")
    _feed(digest, stat.S_IMODE(root_before.st_mode).to_bytes(4, "big"))
    for kind, relative, mode, payload in sorted(entries, key=lambda item: os.fsencode(item[1])):
        _feed(digest, kind.encode("ascii"))
        _feed(digest, os.fsencode(relative))
        _feed(digest, mode.to_bytes(4, "big"))
        _feed(digest, payload)
    return digest.hexdigest()


def _subject_components(lockfile: Path, pods: Path, workspace: Path) -> tuple[str, str, str]:
    _, lock_digest = _stable_file_digest(lockfile)
    return (lock_digest, _tree_digest(pods), _tree_digest(workspace))


def build_subject_digest(*, lockfile: Path, pods: Path, workspace: Path) -> str:
    first = _subject_components(lockfile, pods, workspace)
    second = _subject_components(lockfile, pods, workspace)
    if first != second:
        raise GeneratedBuildSubjectError("generated CocoaPods build subject changed while admitted")
    digest = hashlib.sha256()
    _feed(digest, b"nembra-cocoapods-generated-build-subject-v1")
    for value in first:
        _feed(digest, bytes.fromhex(value))
    return digest.hexdigest()


def _self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="nembra-cocoapods-subject-selftest-") as temporary:
        root = Path(temporary)
        lockfile = root / "Podfile.lock"
        pods = root / "Pods"
        workspace = root / "NembraCapture.xcworkspace"
        pods.mkdir()
        workspace.mkdir()
        lockfile.write_text("LOCK\n", encoding="utf-8")
        (pods / "a.xcconfig").write_text("A\n", encoding="utf-8")
        (workspace / "contents.xcworkspacedata").write_text("W\n", encoding="utf-8")
        baseline = build_subject_digest(lockfile=lockfile, pods=pods, workspace=workspace)
        again = build_subject_digest(lockfile=lockfile, pods=pods, workspace=workspace)
        if baseline != again:
            raise GeneratedBuildSubjectError("stable generated subject did not reproduce")
        (pods / "a.xcconfig").write_text("B\n", encoding="utf-8")
        changed = build_subject_digest(lockfile=lockfile, pods=pods, workspace=workspace)
        if changed == baseline:
            raise GeneratedBuildSubjectError("generated file substitution did not change subject digest")
        (pods / "link").symlink_to("a.xcconfig")
        with_link = build_subject_digest(lockfile=lockfile, pods=pods, workspace=workspace)
        (pods / "link").unlink()
        (pods / "link").symlink_to("missing.xcconfig")
        retargeted = build_subject_digest(lockfile=lockfile, pods=pods, workspace=workspace)
        if with_link == retargeted:
            raise GeneratedBuildSubjectError("generated symlink retarget did not change subject digest")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Fingerprint Nembra Capture CocoaPods generated build inputs")
    parser.add_argument("mode", choices=("digest", "verify", "self-test"))
    parser.add_argument("--lockfile")
    parser.add_argument("--pods")
    parser.add_argument("--workspace")
    parser.add_argument("--expected")
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    arguments = _parser().parse_args(argv)
    try:
        if arguments.mode == "self-test":
            _self_test()
            print("CocoaPods generated build subject self-test passed.")
            return 0
        if not arguments.lockfile or not arguments.pods or not arguments.workspace:
            raise GeneratedBuildSubjectError("--lockfile, --pods, and --workspace are required")
        digest = build_subject_digest(
            lockfile=Path(arguments.lockfile),
            pods=Path(arguments.pods),
            workspace=Path(arguments.workspace),
        )
        if arguments.mode == "verify":
            expected = (arguments.expected or "").lower()
            if len(expected) != 64 or any(character not in "0123456789abcdef" for character in expected):
                raise GeneratedBuildSubjectError("--expected must be exactly 64 hex characters")
            if digest != expected:
                raise GeneratedBuildSubjectError("generated CocoaPods build subject does not match preaccepted digest")
            print("CocoaPods generated build subject matched preaccepted digest.")
        else:
            print(digest)
    except (OSError, GeneratedBuildSubjectError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

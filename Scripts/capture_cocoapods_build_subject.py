#!/usr/bin/env python3
"""Fingerprint the exact CocoaPods-generated build subject consumed by Nembra Capture.

The digest covers relative path, node kind, mode, regular-file bytes, and symlink
target text for both Pods/ and NembraCapture.xcworkspace/. It is descriptive
build provenance only; it never grants physical authority.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import stat
import tempfile
from pathlib import Path

SCHEMA = b"nembra-cocoapods-build-subject-v1"


class BuildSubjectError(RuntimeError):
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


def _stable_file(path: Path, expected: tuple[int, ...]) -> tuple[int, int, bytes]:
    nofollow = getattr(os, "O_NOFOLLOW", None)
    if nofollow is None:
        raise BuildSubjectError("generated build-subject custody requires O_NOFOLLOW")
    try:
        descriptor = os.open(path, os.O_RDONLY | nofollow | getattr(os, "O_CLOEXEC", 0))
    except OSError as error:
        raise BuildSubjectError(f"generated build file is unavailable or unsafe: {path}") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or _identity(before) != expected:
            raise BuildSubjectError("generated build file changed before fingerprint read")
        content = hashlib.sha256()
        bytes_read = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            bytes_read += len(chunk)
            content.update(chunk)
        after = os.fstat(descriptor)
        if _identity(after) != expected or bytes_read != after.st_size:
            raise BuildSubjectError("generated build file changed while fingerprinted")
        return stat.S_IMODE(after.st_mode), after.st_size, content.digest()
    finally:
        os.close(descriptor)


def _tree_digest(root: Path, label: bytes) -> bytes:
    try:
        root_meta = root.lstat()
    except OSError as error:
        raise BuildSubjectError(f"generated build root is unavailable: {root}") from error
    if stat.S_ISLNK(root_meta.st_mode) or not stat.S_ISDIR(root_meta.st_mode):
        raise BuildSubjectError(f"generated build root must be a real directory: {root}")

    root_identity = _identity(root_meta)
    entries: list[tuple[bytes, bytes, int, int, bytes]] = []
    observed: list[tuple[Path, tuple[int, ...], str, str | None]] = [
        (root, root_identity, "D", None)
    ]
    members: dict[Path, tuple[str, ...]] = {}

    for current_text, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_text)
        members[current] = tuple(sorted((*directory_names, *file_names), key=os.fsencode))
        kept: list[str] = []

        for name in sorted(directory_names, key=os.fsencode):
            path = current / name
            relative = path.relative_to(root).as_posix()
            meta = path.lstat()
            identity = _identity(meta)
            mode = stat.S_IMODE(meta.st_mode)
            if stat.S_ISLNK(meta.st_mode):
                target = os.readlink(path)
                observed.append((path, identity, "L", target))
                entries.append((b"L", os.fsencode(relative), mode, 0, os.fsencode(target)))
            elif stat.S_ISDIR(meta.st_mode):
                observed.append((path, identity, "D", None))
                entries.append((b"D", os.fsencode(relative), mode, 0, b""))
                kept.append(name)
            else:
                raise BuildSubjectError("generated build tree contains unsupported directory entry")
        directory_names[:] = kept

        for name in sorted(file_names, key=os.fsencode):
            path = current / name
            relative = path.relative_to(root).as_posix()
            meta = path.lstat()
            identity = _identity(meta)
            mode = stat.S_IMODE(meta.st_mode)
            if stat.S_ISLNK(meta.st_mode):
                target = os.readlink(path)
                observed.append((path, identity, "L", target))
                entries.append((b"L", os.fsencode(relative), mode, 0, os.fsencode(target)))
            elif stat.S_ISREG(meta.st_mode):
                file_mode, size, content = _stable_file(path, identity)
                observed.append((path, identity, "F", None))
                entries.append((b"F", os.fsencode(relative), file_mode, size, content))
            else:
                raise BuildSubjectError("generated build tree contains unsupported file entry")

    for path, expected, kind, target in observed:
        try:
            current = path.lstat()
        except OSError as error:
            raise BuildSubjectError("generated build tree changed during fingerprint") from error
        if _identity(current) != expected:
            raise BuildSubjectError("generated build tree changed during fingerprint")
        if kind == "L" and os.readlink(path) != target:
            raise BuildSubjectError("generated build symlink changed during fingerprint")
    for directory, expected_members in members.items():
        try:
            current_members = tuple(sorted(os.listdir(directory), key=os.fsencode))
        except OSError as error:
            raise BuildSubjectError("generated build directory changed during fingerprint") from error
        if current_members != expected_members:
            raise BuildSubjectError("generated build directory membership changed during fingerprint")

    digest = hashlib.sha256()
    _feed(digest, SCHEMA)
    _feed(digest, label)
    _feed(digest, stat.S_IMODE(root_meta.st_mode).to_bytes(4, "big"))
    for kind, relative, mode, size, payload in sorted(entries, key=lambda item: item[1]):
        _feed(digest, kind)
        _feed(digest, relative)
        _feed(digest, mode.to_bytes(4, "big"))
        _feed(digest, size.to_bytes(8, "big"))
        _feed(digest, payload)
    return digest.digest()


def build_subject_digest(pods: Path, workspace: Path) -> str:
    digest = hashlib.sha256()
    _feed(digest, SCHEMA)
    _feed(digest, b"Pods")
    _feed(digest, _tree_digest(pods, b"Pods"))
    _feed(digest, b"NembraCapture.xcworkspace")
    _feed(digest, _tree_digest(workspace, b"NembraCapture.xcworkspace"))
    return digest.hexdigest()


def _self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="nembra-cocoapods-subject-") as temporary:
        root = Path(temporary)
        pods = root / "Pods"
        workspace = root / "NembraCapture.xcworkspace"
        pods.mkdir()
        workspace.mkdir()
        (pods / "config.xcconfig").write_text("A\n", encoding="utf-8")
        (workspace / "contents.xcworkspacedata").write_text("workspace\n", encoding="utf-8")
        first = build_subject_digest(pods, workspace)
        second = build_subject_digest(pods, workspace)
        if first != second:
            raise BuildSubjectError("stable generated build subject did not reproduce")
        (pods / "config.xcconfig").write_text("B\n", encoding="utf-8")
        if build_subject_digest(pods, workspace) == first:
            raise BuildSubjectError("generated build subject did not change with file bytes")


def main() -> int:
    parser = argparse.ArgumentParser(description="Nembra CocoaPods generated build-subject fingerprint")
    parser.add_argument("--pods")
    parser.add_argument("--workspace")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    try:
        if arguments.self_test:
            _self_test()
            return 0
        if not arguments.pods or not arguments.workspace:
            parser.error("--pods and --workspace are required unless --self-test is used")
        print(build_subject_digest(Path(arguments.pods), Path(arguments.workspace)))
    except (BuildSubjectError, OSError) as error:
        print(f"ERROR: {error}", file=os.sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

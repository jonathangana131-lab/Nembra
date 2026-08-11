#!/usr/bin/env python3
"""Fingerprint the exact CocoaPods-generated build subject consumed by Nembra Capture.

The digest covers relative path, node kind, mode, regular-file bytes, and symlink
target text for both Pods/ and NembraCapture.xcworkspace/. Symlinks must resolve
inside one of those generated roots or an explicitly named externally-custodied
root whose bytes are bound by a separate accepted provenance contract. Broken or
unadmitted targets fail closed. This is descriptive build provenance only; it
never grants physical authority.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import stat
import tempfile
from pathlib import Path
from typing import Iterable

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


def _stable_real_directory(path: Path, label: str) -> Path:
    try:
        metadata = path.lstat()
        resolved = path.resolve(strict=True)
        resolved_metadata = resolved.lstat()
    except OSError as error:
        raise BuildSubjectError(f"{label} is unavailable") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise BuildSubjectError(f"{label} must be a real directory")
    if not stat.S_ISDIR(resolved_metadata.st_mode):
        raise BuildSubjectError(f"{label} must resolve to a directory")
    return resolved


def _is_within(candidate: Path, roots: tuple[Path, ...]) -> bool:
    for root in roots:
        try:
            candidate.relative_to(root)
            return True
        except ValueError:
            continue
    return False


def _admit_symlink(path: Path, trusted_roots: tuple[Path, ...]) -> str:
    try:
        target = os.readlink(path)
        resolved = path.resolve(strict=True)
    except OSError as error:
        raise BuildSubjectError("generated build symlink is broken or unavailable") from error
    if not _is_within(resolved, trusted_roots):
        raise BuildSubjectError(
            "generated build symlink escapes the generated subject and externally-custodied roots"
        )
    return target


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


def _tree_digest(root: Path, label: bytes, trusted_roots: tuple[Path, ...]) -> bytes:
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
                target = _admit_symlink(path, trusted_roots)
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
                target = _admit_symlink(path, trusted_roots)
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
        if kind == "L":
            current_target = _admit_symlink(path, trusted_roots)
            if current_target != target:
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


def build_subject_digest(
    pods: Path,
    workspace: Path,
    externally_custodied_roots: Iterable[Path] = (),
) -> str:
    pods_resolved = _stable_real_directory(pods, "Pods generated root")
    workspace_resolved = _stable_real_directory(workspace, "workspace generated root")
    external_resolved = tuple(
        _stable_real_directory(path, "externally-custodied build root")
        for path in externally_custodied_roots
    )
    trusted_roots = (pods_resolved, workspace_resolved, *external_resolved)

    digest = hashlib.sha256()
    _feed(digest, SCHEMA)
    _feed(digest, b"Pods")
    _feed(digest, _tree_digest(pods, b"Pods", trusted_roots))
    _feed(digest, b"NembraCapture.xcworkspace")
    _feed(digest, _tree_digest(workspace, b"NembraCapture.xcworkspace", trusted_roots))
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

        outside = root / "outside"
        outside.mkdir()
        external_file = outside / "external.xcconfig"
        external_file.write_text("external\n", encoding="utf-8")
        link = pods / "external.xcconfig"
        link.symlink_to(external_file)
        try:
            build_subject_digest(pods, workspace)
        except BuildSubjectError:
            pass
        else:
            raise BuildSubjectError("unadmitted external generated symlink was accepted")
        build_subject_digest(pods, workspace, (outside,))


def main() -> int:
    parser = argparse.ArgumentParser(description="Nembra CocoaPods generated build-subject fingerprint")
    parser.add_argument("--pods")
    parser.add_argument("--workspace")
    parser.add_argument(
        "--externally-custodied-root",
        action="append",
        default=[],
        help="real directory whose bytes are bound by a separate accepted provenance contract",
    )
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    try:
        if arguments.self_test:
            _self_test()
            return 0
        if not arguments.pods or not arguments.workspace:
            parser.error("--pods and --workspace are required unless --self-test is used")
        print(
            build_subject_digest(
                Path(arguments.pods),
                Path(arguments.workspace),
                tuple(Path(value) for value in arguments.externally_custodied_root),
            )
        )
    except (BuildSubjectError, OSError) as error:
        print(f"ERROR: {error}", file=os.sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Fingerprint the exact CocoaPods-generated build subject for Nembra Capture.

This helper fingerprints only non-secret build graph material: Podfile.lock,
Pods/, and NembraCapture.xcworkspace/. It never serializes private Tuya
credentials or device identifiers. Symlinks are fingerprinted as link objects;
their targets are not followed by this helper.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import stat
import tempfile
from pathlib import Path

DOMAIN = b"nembra-cocoapods-build-subject-v1"


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


def _stable_file(path: Path) -> tuple[int, int, str]:
    nofollow = getattr(os, "O_NOFOLLOW", None)
    if nofollow is None:
        raise BuildSubjectError("generated-build subject requires O_NOFOLLOW support")
    flags = os.O_RDONLY | nofollow | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as exc:
        raise BuildSubjectError(f"generated build file is unavailable or unsafe: {path.name}") from exc
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise BuildSubjectError(f"generated build input is not a regular file: {path.name}")
        initial = _identity(before)
        digest = hashlib.sha256()
        read_count = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            read_count += len(chunk)
            digest.update(chunk)
        after = os.fstat(descriptor)
        try:
            current = path.lstat()
        except OSError as exc:
            raise BuildSubjectError(f"generated build file pathname changed: {path.name}") from exc
        if initial != _identity(after) or initial != _identity(current) or read_count != after.st_size:
            raise BuildSubjectError(f"generated build file changed while fingerprinted: {path.name}")
        return stat.S_IMODE(after.st_mode), after.st_size, digest.hexdigest()
    finally:
        os.close(descriptor)


def _member_names(path: Path) -> tuple[str, ...]:
    try:
        return tuple(sorted(os.listdir(path), key=os.fsencode))
    except OSError as exc:
        raise BuildSubjectError("generated build tree changed during fingerprinting") from exc


def _tree(root: Path) -> bytes:
    try:
        root_meta = root.lstat()
    except OSError as exc:
        raise BuildSubjectError(f"generated build directory is unavailable: {root.name}") from exc
    if stat.S_ISLNK(root_meta.st_mode) or not stat.S_ISDIR(root_meta.st_mode):
        raise BuildSubjectError(f"generated build root must be one real directory: {root.name}")

    entries: list[tuple[str, str, int, int, bytes]] = []
    observed: list[tuple[Path, tuple[int, ...], str]] = [(root, _identity(root_meta), "D")]
    members: dict[Path, tuple[str, ...]] = {}

    for current_text, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_text)
        members[current] = tuple(sorted((*directory_names, *file_names), key=os.fsencode))
        kept: list[str] = []
        for name in sorted(directory_names, key=os.fsencode):
            candidate = current / name
            relative = candidate.relative_to(root).as_posix()
            meta = candidate.lstat()
            mode = stat.S_IMODE(meta.st_mode)
            if stat.S_ISLNK(meta.st_mode):
                target = os.readlink(candidate)
                observed.append((candidate, _identity(meta), "L"))
                entries.append(("L", relative, mode, 0, os.fsencode(target)))
            elif stat.S_ISDIR(meta.st_mode):
                observed.append((candidate, _identity(meta), "D"))
                entries.append(("D", relative, mode, 0, b""))
                kept.append(name)
            else:
                raise BuildSubjectError("generated build tree contains unsupported directory entry")
        directory_names[:] = kept

        for name in sorted(file_names, key=os.fsencode):
            candidate = current / name
            relative = candidate.relative_to(root).as_posix()
            meta = candidate.lstat()
            mode = stat.S_IMODE(meta.st_mode)
            if stat.S_ISLNK(meta.st_mode):
                target = os.readlink(candidate)
                observed.append((candidate, _identity(meta), "L"))
                entries.append(("L", relative, mode, 0, os.fsencode(target)))
            elif stat.S_ISREG(meta.st_mode):
                file_mode, size, content_sha = _stable_file(candidate)
                current_meta = candidate.lstat()
                if _identity(current_meta) != _identity(meta):
                    raise BuildSubjectError("generated build file changed around fingerprint admission")
                observed.append((candidate, _identity(meta), "F"))
                entries.append(("F", relative, file_mode, size, bytes.fromhex(content_sha)))
            else:
                raise BuildSubjectError("generated build tree contains unsupported file entry")

    for candidate, expected, kind in observed:
        try:
            current = candidate.lstat()
        except OSError as exc:
            raise BuildSubjectError("generated build tree entry disappeared during fingerprinting") from exc
        if _identity(current) != expected:
            raise BuildSubjectError("generated build tree entry changed during fingerprinting")
        if kind == "D" and not stat.S_ISDIR(current.st_mode):
            raise BuildSubjectError("generated build directory changed type")
        if kind == "F" and not stat.S_ISREG(current.st_mode):
            raise BuildSubjectError("generated build file changed type")
        if kind == "L" and not stat.S_ISLNK(current.st_mode):
            raise BuildSubjectError("generated build symlink changed type")
    for directory, expected_members in members.items():
        if _member_names(directory) != expected_members:
            raise BuildSubjectError("generated build directory membership changed during fingerprinting")

    digest = hashlib.sha256()
    _feed(digest, b"tree-v1")
    _feed(digest, stat.S_IMODE(root_meta.st_mode).to_bytes(4, "big"))
    for kind, relative, mode, size, payload in sorted(entries, key=lambda row: os.fsencode(row[1])):
        _feed(digest, kind.encode("ascii"))
        _feed(digest, os.fsencode(relative))
        _feed(digest, mode.to_bytes(4, "big"))
        _feed(digest, size.to_bytes(8, "big"))
        _feed(digest, payload)
    return digest.digest()


def fingerprint(lockfile: Path, pods: Path, workspace: Path) -> str:
    lock_mode, lock_size, lock_sha = _stable_file(lockfile)
    digest = hashlib.sha256()
    _feed(digest, DOMAIN)
    _feed(digest, b"Podfile.lock")
    _feed(digest, lock_mode.to_bytes(4, "big"))
    _feed(digest, lock_size.to_bytes(8, "big"))
    _feed(digest, bytes.fromhex(lock_sha))
    _feed(digest, b"Pods")
    _feed(digest, _tree(pods))
    _feed(digest, b"NembraCapture.xcworkspace")
    _feed(digest, _tree(workspace))
    return digest.hexdigest()


def _self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="nembra-cocoapods-subject-") as temporary:
        root = Path(temporary)
        lock = root / "Podfile.lock"
        pods = root / "Pods"
        workspace = root / "NembraCapture.xcworkspace"
        pods.mkdir()
        workspace.mkdir()
        lock.write_text("PODS:\n  - A (1.0)\n", encoding="utf-8")
        (pods / "generated.xcconfig").write_text("VALUE=A\n", encoding="utf-8")
        (workspace / "contents.xcworkspacedata").write_text("A\n", encoding="utf-8")
        first = fingerprint(lock, pods, workspace)
        second = fingerprint(lock, pods, workspace)
        if first != second or len(first) != 64:
            raise BuildSubjectError("self-test fingerprint is not deterministic")
        (pods / "generated.xcconfig").write_text("VALUE=B\n", encoding="utf-8")
        changed = fingerprint(lock, pods, workspace)
        if changed == first:
            raise BuildSubjectError("self-test did not detect generated build mutation")

        outside = root / "outside"
        outside.mkdir()
        escaped = root / "escaped-pods"
        escaped.symlink_to(outside, target_is_directory=True)
        try:
            fingerprint(lock, escaped, workspace)
        except BuildSubjectError:
            pass
        else:
            raise BuildSubjectError("self-test followed a symlinked generated build root")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--lockfile", type=Path)
    parser.add_argument("--pods", type=Path)
    parser.add_argument("--workspace", type=Path)
    args = parser.parse_args()
    try:
        if args.self_test:
            _self_test()
            return 0
        if args.lockfile is None or args.pods is None or args.workspace is None:
            parser.error("--lockfile, --pods, and --workspace are required unless --self-test is used")
        print(fingerprint(args.lockfile, args.pods, args.workspace))
        return 0
    except (BuildSubjectError, OSError) as exc:
        print(f"ERROR: {exc}", file=os.sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

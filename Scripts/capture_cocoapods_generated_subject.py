#!/usr/bin/env python3
"""Fingerprint the exact ignored CocoaPods build subject used by Nembra Capture.

This helper intentionally fingerprints generated build inputs rather than trusting
Podfile.lock alone. It records only structure, modes, symlink targets, and file
content digests; it never serializes private Tuya bytes or credentials.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import stat
import tempfile
from pathlib import Path
from typing import Iterable, Sequence

SCHEMA = b"nembra-cocoapods-generated-subject-v1"


class GeneratedSubjectError(RuntimeError):
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


def _inside(path: Path, root: Path) -> Path:
    resolved = path.resolve(strict=True)
    try:
        resolved.relative_to(root)
    except ValueError as error:
        raise GeneratedSubjectError("generated CocoaPods subject escapes the repository root") from error
    return resolved


def _stable_file_digest(path: Path, expected: tuple[int, ...]) -> bytes:
    nofollow = getattr(os, "O_NOFOLLOW", None)
    if nofollow is None:
        raise GeneratedSubjectError("generated build subject admission requires O_NOFOLLOW support")
    flags = os.O_RDONLY | nofollow | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise GeneratedSubjectError(f"generated build file could not be opened safely: {path}") from error
    try:
        before = os.fstat(descriptor)
        if _identity(before) != expected or not stat.S_ISREG(before.st_mode):
            raise GeneratedSubjectError("generated build file changed before fingerprinting")
        digest = hashlib.sha256()
        count = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
            count += len(chunk)
        after = os.fstat(descriptor)
        if _identity(after) != expected or count != after.st_size:
            raise GeneratedSubjectError("generated build file changed while fingerprinting")
        current = path.lstat()
        if stat.S_ISLNK(current.st_mode) or _identity(current) != expected:
            raise GeneratedSubjectError("generated build pathname changed during fingerprinting")
        return digest.digest()
    finally:
        os.close(descriptor)


def _members(path: Path) -> tuple[str, ...]:
    try:
        return tuple(sorted(os.listdir(path), key=os.fsencode))
    except OSError as error:
        raise GeneratedSubjectError("generated build tree changed during fingerprinting") from error


def _tree_fingerprint(root: Path, repository_root: Path) -> bytes:
    try:
        metadata = root.lstat()
    except OSError as error:
        raise GeneratedSubjectError(f"generated build tree is unavailable: {root.name}") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise GeneratedSubjectError(f"generated build tree is not a real directory: {root.name}")

    root_identity = _identity(metadata)
    root_relative = root.relative_to(repository_root).as_posix()
    observed: list[tuple[Path, tuple[int, ...], str, str | None]] = [(root, root_identity, "D", None)]
    directories: dict[Path, tuple[str, ...]] = {}
    entries: list[tuple[str, str, int, bytes]] = []

    for current_text, dir_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_text)
        directories[current] = tuple(sorted((*dir_names, *file_names), key=os.fsencode))
        kept: list[str] = []

        for name in sorted(dir_names, key=os.fsencode):
            candidate = current / name
            relative = candidate.relative_to(repository_root).as_posix()
            item = candidate.lstat()
            item_identity = _identity(item)
            mode = stat.S_IMODE(item.st_mode)
            if stat.S_ISLNK(item.st_mode):
                target = os.readlink(candidate)
                _inside(candidate, repository_root)
                observed.append((candidate, item_identity, "L", target))
                entries.append(("L", relative, mode, os.fsencode(target)))
            elif stat.S_ISDIR(item.st_mode):
                observed.append((candidate, item_identity, "D", None))
                entries.append(("D", relative, mode, b""))
                kept.append(name)
            else:
                raise GeneratedSubjectError("generated build tree contains an unsupported directory entry")
        dir_names[:] = kept

        for name in sorted(file_names, key=os.fsencode):
            candidate = current / name
            relative = candidate.relative_to(repository_root).as_posix()
            item = candidate.lstat()
            item_identity = _identity(item)
            mode = stat.S_IMODE(item.st_mode)
            if stat.S_ISLNK(item.st_mode):
                target = os.readlink(candidate)
                _inside(candidate, repository_root)
                observed.append((candidate, item_identity, "L", target))
                entries.append(("L", relative, mode, os.fsencode(target)))
            elif stat.S_ISREG(item.st_mode):
                payload = _stable_file_digest(candidate, item_identity)
                observed.append((candidate, item_identity, "F", None))
                entries.append(("F", relative, mode, payload))
            else:
                raise GeneratedSubjectError("generated build tree contains an unsupported file entry")

    for candidate, expected, kind, target in observed:
        current = candidate.lstat()
        if _identity(current) != expected:
            raise GeneratedSubjectError("generated build tree changed during final fingerprint custody")
        if kind == "D" and not stat.S_ISDIR(current.st_mode):
            raise GeneratedSubjectError("generated build directory changed type")
        if kind == "F" and not stat.S_ISREG(current.st_mode):
            raise GeneratedSubjectError("generated build file changed type")
        if kind == "L":
            if not stat.S_ISLNK(current.st_mode) or os.readlink(candidate) != target:
                raise GeneratedSubjectError("generated build symlink changed during fingerprinting")
            _inside(candidate, repository_root)

    for directory, expected_members in directories.items():
        if _members(directory) != expected_members:
            raise GeneratedSubjectError("generated build directory membership changed during fingerprinting")

    digest = hashlib.sha256()
    _feed(digest, b"tree")
    _feed(digest, root_relative.encode("utf-8"))
    _feed(digest, stat.S_IMODE(metadata.st_mode).to_bytes(4, "big"))
    for kind, relative, mode, payload in sorted(entries, key=lambda item: os.fsencode(item[1])):
        _feed(digest, kind.encode("ascii"))
        _feed(digest, relative.encode("utf-8"))
        _feed(digest, mode.to_bytes(4, "big"))
        _feed(digest, payload)
    return digest.digest()


def fingerprint_subject(repository_root: Path, roots: Iterable[Path]) -> str:
    repository_root = repository_root.resolve(strict=True)
    digest = hashlib.sha256()
    _feed(digest, SCHEMA)
    count = 0
    for root in roots:
        resolved_parent = root.parent.resolve(strict=True)
        try:
            resolved_parent.relative_to(repository_root)
        except ValueError as error:
            raise GeneratedSubjectError("generated build root is outside the repository") from error
        _feed(digest, _tree_fingerprint(root, repository_root))
        count += 1
    if count == 0:
        raise GeneratedSubjectError("no generated build roots were supplied")
    return digest.hexdigest()


def _self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="nembra-generated-subject-") as temporary:
        repository = Path(temporary).resolve()
        pods = repository / "Pods"
        workspace = repository / "NembraCapture.xcworkspace"
        pods.mkdir()
        workspace.mkdir()
        (pods / "project.pbxproj").write_text("A\n", encoding="utf-8")
        (workspace / "contents.xcworkspacedata").write_text("workspace\n", encoding="utf-8")
        first = fingerprint_subject(repository, (pods, workspace))
        second = fingerprint_subject(repository, (pods, workspace))
        if first != second:
            raise AssertionError("unchanged generated build subject was not stable")
        (pods / "project.pbxproj").write_text("B\n", encoding="utf-8")
        third = fingerprint_subject(repository, (pods, workspace))
        if third == first:
            raise AssertionError("generated build byte substitution was not detected")

        outside = repository.parent / (repository.name + "-outside")
        outside.write_text("escape", encoding="utf-8")
        try:
            (pods / "escape").symlink_to(outside)
            try:
                fingerprint_subject(repository, (pods, workspace))
            except GeneratedSubjectError:
                pass
            else:
                raise AssertionError("escaping generated-build symlink was accepted")
        finally:
            try:
                outside.unlink()
            except FileNotFoundError:
                pass


def _parse(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Fingerprint ignored generated CocoaPods build inputs.")
    parser.add_argument("--self-test", action="store_true")
    subparsers = parser.add_subparsers(dest="command")
    fingerprint = subparsers.add_parser("fingerprint")
    fingerprint.add_argument("--repository-root", required=True, type=Path)
    fingerprint.add_argument("--pods", required=True, type=Path)
    fingerprint.add_argument("--workspace", required=True, type=Path)
    return parser.parse_args(list(argv))


def main(argv: Sequence[str] | None = None) -> int:
    args = _parse(os.sys.argv[1:] if argv is None else argv)
    try:
        if args.self_test:
            _self_test()
            return 0
        if args.command != "fingerprint":
            raise GeneratedSubjectError("fingerprint command is required")
        print(fingerprint_subject(args.repository_root, (args.pods, args.workspace)))
        return 0
    except (GeneratedSubjectError, OSError, ValueError) as error:
        print(f"ERROR: {error}", file=os.sys.stderr)
        return 72


if __name__ == "__main__":
    raise SystemExit(main())

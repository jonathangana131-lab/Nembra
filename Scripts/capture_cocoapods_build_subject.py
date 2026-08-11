#!/usr/bin/env python3
"""Fingerprint CocoaPods-generated Capture build inputs without serializing their bytes.

The digest is review authority for the generated build graph only. It does not
replace the accepted Podfile.lock or the private Tuya input fingerprints.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import stat
from pathlib import Path

SCHEMA = b"nembra-capture-cocoapods-generated-build-subject-v1"
REQUIRED_PATHS = (
    Path("Podfile.lock"),
    Path("Pods"),
    Path("NembraCapture.xcworkspace"),
)


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
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _stable_file_digest(path: Path) -> tuple[os.stat_result, str]:
    nofollow = getattr(os, "O_NOFOLLOW", None)
    if nofollow is None:
        raise BuildSubjectError("generated build subject admission requires O_NOFOLLOW support")
    flags = os.O_RDONLY | nofollow | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise BuildSubjectError(f"generated build input is unavailable or unsafe: {path}") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise BuildSubjectError(f"generated build input is not a regular file: {path}")
        digest = hashlib.sha256()
        count = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            count += len(chunk)
            digest.update(chunk)
        after = os.fstat(descriptor)
        if _identity(before) != _identity(after) or count != after.st_size:
            raise BuildSubjectError(f"generated build input changed while fingerprinted: {path}")
        current = path.lstat()
        if stat.S_ISLNK(current.st_mode) or _identity(current) != _identity(after):
            raise BuildSubjectError(f"generated build input pathname changed while fingerprinted: {path}")
        return after, digest.hexdigest()
    finally:
        os.close(descriptor)


def _assert_internal_symlink(path: Path, root: Path) -> str:
    try:
        target = os.readlink(path)
        resolved = path.resolve(strict=True)
        resolved.relative_to(root)
    except (OSError, ValueError) as error:
        raise BuildSubjectError(f"generated build subject contains an escaping or broken symlink: {path}") from error
    return target


def _tree_entries(root: Path, tree: Path) -> tuple[tuple[str, str, int, bytes], ...]:
    try:
        root_meta = tree.lstat()
    except OSError as error:
        raise BuildSubjectError(f"required generated build directory is missing: {tree}") from error
    if stat.S_ISLNK(root_meta.st_mode) or not stat.S_ISDIR(root_meta.st_mode):
        raise BuildSubjectError(f"required generated build directory is not a real directory: {tree}")

    root_resolved = root.resolve(strict=True)
    entries: list[tuple[str, str, int, bytes]] = []
    observed: list[tuple[Path, tuple[int, ...], str]] = [(tree, _identity(root_meta), "D")]
    members: dict[Path, tuple[str, ...]] = {}

    for current_text, directory_names, file_names in os.walk(tree, topdown=True, followlinks=False):
        current = Path(current_text)
        members[current] = tuple(sorted((*directory_names, *file_names), key=os.fsencode))
        kept: list[str] = []

        for name in sorted(directory_names, key=os.fsencode):
            path = current / name
            relative = path.relative_to(root).as_posix()
            metadata = path.lstat()
            identity = _identity(metadata)
            mode = stat.S_IMODE(metadata.st_mode)
            if stat.S_ISLNK(metadata.st_mode):
                target = _assert_internal_symlink(path, root_resolved)
                observed.append((path, identity, "L"))
                entries.append(("L", relative, mode, os.fsencode(target)))
            elif stat.S_ISDIR(metadata.st_mode):
                observed.append((path, identity, "D"))
                entries.append(("D", relative, mode, b""))
                kept.append(name)
            else:
                raise BuildSubjectError(f"unsupported generated directory entry: {path}")
        directory_names[:] = kept

        for name in sorted(file_names, key=os.fsencode):
            path = current / name
            relative = path.relative_to(root).as_posix()
            metadata = path.lstat()
            identity = _identity(metadata)
            mode = stat.S_IMODE(metadata.st_mode)
            if stat.S_ISLNK(metadata.st_mode):
                target = _assert_internal_symlink(path, root_resolved)
                observed.append((path, identity, "L"))
                entries.append(("L", relative, mode, os.fsencode(target)))
            elif stat.S_ISREG(metadata.st_mode):
                after, content_digest = _stable_file_digest(path)
                if _identity(after) != identity:
                    raise BuildSubjectError(f"generated build input changed during tree fingerprint: {path}")
                observed.append((path, identity, "F"))
                entries.append(("F", relative, mode, bytes.fromhex(content_digest)))
            else:
                raise BuildSubjectError(f"unsupported generated file entry: {path}")

    for path, expected, kind in observed:
        current = path.lstat()
        if _identity(current) != expected:
            raise BuildSubjectError("generated build subject changed while fingerprinted")
        if kind == "D" and not stat.S_ISDIR(current.st_mode):
            raise BuildSubjectError("generated build subject changed while fingerprinted")
        if kind == "F" and not stat.S_ISREG(current.st_mode):
            raise BuildSubjectError("generated build subject changed while fingerprinted")
        if kind == "L" and not stat.S_ISLNK(current.st_mode):
            raise BuildSubjectError("generated build subject changed while fingerprinted")

    for directory, expected_names in members.items():
        if tuple(sorted(os.listdir(directory), key=os.fsencode)) != expected_names:
            raise BuildSubjectError("generated build subject membership changed while fingerprinted")

    return tuple(entries)


def fingerprint(root: Path) -> str:
    root = root.resolve(strict=True)
    lockfile = root / REQUIRED_PATHS[0]
    pods = root / REQUIRED_PATHS[1]
    workspace = root / REQUIRED_PATHS[2]

    lock_meta, lock_digest = _stable_file_digest(lockfile)
    digest = hashlib.sha256()
    _feed(digest, SCHEMA)
    _feed(digest, b"F")
    _feed(digest, REQUIRED_PATHS[0].as_posix().encode("utf-8"))
    _feed(digest, stat.S_IMODE(lock_meta.st_mode).to_bytes(4, "big"))
    _feed(digest, bytes.fromhex(lock_digest))

    for tree in (pods, workspace):
        for kind, relative, mode, payload in _tree_entries(root, tree):
            _feed(digest, kind.encode("ascii"))
            _feed(digest, relative.encode("utf-8"))
            _feed(digest, mode.to_bytes(4, "big"))
            _feed(digest, payload)

    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("fingerprint",))
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--expect", default="")
    args = parser.parse_args()

    try:
        actual = fingerprint(args.root)
    except (BuildSubjectError, OSError) as error:
        parser.error(str(error))

    if args.expect:
        expected = args.expect.lower()
        if len(expected) != 64 or any(character not in "0123456789abcdef" for character in expected):
            parser.error("--expect must be exactly 64 hexadecimal characters")
        if actual != expected:
            parser.error("generated CocoaPods build subject does not match the preaccepted digest")
    print(actual)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

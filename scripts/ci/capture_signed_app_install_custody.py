#!/usr/bin/env python3
"""Bind the exact signed Capture.app bytes consumed by the physical install side effect.

The field installer admits xcodebuild output only through the root-supervised build-origin handoff.
That supervisor locks its isolated DerivedData root, snapshots the exact bundle into a root-owned
staging directory, and returns only that protected stage. This helper fingerprints the finite bundle
and proves the staged path cannot be replaced or modified by the invoking non-root user before
devicectl consumes it.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import stat
import sys
from typing import Iterable

STAGE_PARENT = Path("/private/tmp")
STAGE_PREFIX = "nembra-authenticated-capture-install."
APP_NAME = "Nembra Capture.app"


class CustodyError(RuntimeError):
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
        metadata.st_nlink,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _read_regular(path: Path, expected: tuple[int, ...]) -> tuple[int, str]:
    nofollow = getattr(os, "O_NOFOLLOW", None)
    if nofollow is None:
        raise CustodyError("signed-app custody requires O_NOFOLLOW support")
    flags = os.O_RDONLY | nofollow | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise CustodyError(f"could not open signed-app file without following a symlink: {path}") from error
    try:
        before = os.fstat(descriptor)
        if _identity(before) != expected or not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            raise CustodyError(f"signed-app file changed before admission: {path}")
        digest = hashlib.sha256()
        total = 0
        while True:
            chunk = os.read(descriptor, 1 << 20)
            if not chunk:
                break
            total += len(chunk)
            digest.update(chunk)
        after = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    if _identity(after) != expected or total != after.st_size:
        raise CustodyError(f"signed-app file changed while fingerprinting: {path}")
    final = path.lstat()
    if _identity(final) != expected:
        raise CustodyError(f"signed-app pathname changed while fingerprinting: {path}")
    return total, digest.hexdigest()


def _within(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def _manifest_once(root: Path) -> bytes:
    try:
        root_metadata = root.lstat()
    except OSError as error:
        raise CustodyError("signed app is unavailable") from error
    if stat.S_ISLNK(root_metadata.st_mode) or not stat.S_ISDIR(root_metadata.st_mode):
        raise CustodyError("signed app must be one real directory")

    canonical_root = root.resolve(strict=True)
    observed: list[tuple[Path, tuple[int, ...], str]] = [
        (root, _identity(root_metadata), "D")
    ]
    memberships: dict[Path, tuple[str, ...]] = {}
    entries: list[tuple[str, str, int, int, str]] = [
        ("D", ".", stat.S_IMODE(root_metadata.st_mode), 0, "")
    ]

    for current_text, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_text)
        memberships[current] = tuple(sorted((*directory_names, *file_names), key=os.fsencode))
        kept_directories: list[str] = []

        for name in sorted(directory_names, key=os.fsencode):
            candidate = current / name
            relative = candidate.relative_to(root).as_posix()
            metadata = candidate.lstat()
            identity = _identity(metadata)
            mode = stat.S_IMODE(metadata.st_mode)
            if stat.S_ISLNK(metadata.st_mode):
                target = os.readlink(candidate)
                try:
                    resolved = candidate.resolve(strict=True)
                except OSError as error:
                    raise CustodyError(f"signed app contains a broken symlink: {relative}") from error
                if not _within(resolved, canonical_root):
                    raise CustodyError(f"signed app contains an escaping symlink: {relative}")
                observed.append((candidate, identity, "L"))
                entries.append(("L", relative, mode, 0, target))
            elif stat.S_ISDIR(metadata.st_mode):
                observed.append((candidate, identity, "D"))
                entries.append(("D", relative, mode, 0, ""))
                kept_directories.append(name)
            else:
                raise CustodyError(f"signed app contains an unsupported directory entry: {relative}")
        directory_names[:] = kept_directories

        for name in sorted(file_names, key=os.fsencode):
            candidate = current / name
            relative = candidate.relative_to(root).as_posix()
            metadata = candidate.lstat()
            identity = _identity(metadata)
            mode = stat.S_IMODE(metadata.st_mode)
            if stat.S_ISLNK(metadata.st_mode):
                target = os.readlink(candidate)
                try:
                    resolved = candidate.resolve(strict=True)
                except OSError as error:
                    raise CustodyError(f"signed app contains a broken symlink: {relative}") from error
                if not _within(resolved, canonical_root):
                    raise CustodyError(f"signed app contains an escaping symlink: {relative}")
                observed.append((candidate, identity, "L"))
                entries.append(("L", relative, mode, 0, target))
            elif stat.S_ISREG(metadata.st_mode):
                size, content_sha = _read_regular(candidate, identity)
                observed.append((candidate, identity, "F"))
                entries.append(("F", relative, mode, size, content_sha))
            else:
                raise CustodyError(f"signed app contains an unsupported file entry: {relative}")

    for candidate, identity, kind in observed:
        try:
            metadata = candidate.lstat()
        except OSError as error:
            raise CustodyError("signed app changed while its finite tree was fingerprinted") from error
        if _identity(metadata) != identity:
            raise CustodyError("signed app changed while its finite tree was fingerprinted")
        if kind == "D" and not stat.S_ISDIR(metadata.st_mode):
            raise CustodyError("signed app entry kind changed during fingerprinting")
        if kind == "F" and not stat.S_ISREG(metadata.st_mode):
            raise CustodyError("signed app entry kind changed during fingerprinting")
        if kind == "L" and not stat.S_ISLNK(metadata.st_mode):
            raise CustodyError("signed app entry kind changed during fingerprinting")
    for directory, expected_names in memberships.items():
        try:
            current_names = tuple(sorted(os.listdir(directory), key=os.fsencode))
        except OSError as error:
            raise CustodyError("signed app directory changed during fingerprinting") from error
        if current_names != expected_names:
            raise CustodyError("signed app membership changed during fingerprinting")

    digest = hashlib.sha256()
    _feed(digest, b"nembra-capture-signed-app-tree-v1")
    for kind, relative, mode, size, payload in entries:
        _feed(digest, kind.encode("ascii"))
        _feed(digest, os.fsencode(relative))
        _feed(digest, mode.to_bytes(4, "big"))
        _feed(digest, size.to_bytes(8, "big"))
        _feed(digest, payload.encode("utf-8"))
    return digest.hexdigest().encode("ascii")


def fingerprint(root: Path) -> str:
    first = _manifest_once(root)
    second = _manifest_once(root)
    if first != second:
        raise CustodyError("signed app changed across the two-pass finite-tree fingerprint")
    return first.decode("ascii")


def _require_root_owned_read_only(path: Path, *, directory: bool) -> None:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise CustodyError(f"protected install subject disappeared: {path}") from error
    if stat.S_ISLNK(metadata.st_mode):
        raise CustodyError(f"protected install custody path is a symlink: {path}")
    if directory and not stat.S_ISDIR(metadata.st_mode):
        raise CustodyError(f"protected install custody path is not a directory: {path}")
    if not directory and not stat.S_ISREG(metadata.st_mode):
        raise CustodyError(f"protected install custody file is not regular: {path}")
    if metadata.st_uid != 0:
        raise CustodyError(f"protected install custody entry is not root-owned: {path}")
    mode = stat.S_IMODE(metadata.st_mode)
    if mode & 0o022:
        raise CustodyError(f"protected install custody entry is group/other writable: {path}")
    if directory and (mode & 0o005) != 0o005:
        raise CustodyError(f"protected install custody directory is not readable/traversable by devicectl user: {path}")
    if not directory and (mode & 0o004) != 0o004:
        raise CustodyError(f"protected install custody file is not readable by devicectl user: {path}")


def verify_stage(stage_root: Path, app: Path, *, expected: str | None = None) -> str:
    if not stage_root.is_absolute() or stage_root.parent != STAGE_PARENT or not stage_root.name.startswith(STAGE_PREFIX):
        raise CustodyError("protected install stage must be one direct canonical child of /private/tmp")
    if app != stage_root / APP_NAME:
        raise CustodyError("protected install app must be the canonical direct child of its stage root")

    _require_root_owned_read_only(stage_root, directory=True)
    _require_root_owned_read_only(app, directory=True)
    canonical_app = app.resolve(strict=True)

    for current_text, directory_names, file_names in os.walk(app, topdown=True, followlinks=False):
        current = Path(current_text)
        _require_root_owned_read_only(current, directory=True)
        for name in directory_names:
            candidate = current / name
            metadata = candidate.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                if metadata.st_uid != 0:
                    raise CustodyError(f"protected install symlink is not root-owned: {candidate}")
                try:
                    resolved = candidate.resolve(strict=True)
                except OSError as error:
                    raise CustodyError(f"protected install symlink is broken: {candidate}") from error
                if not _within(resolved, canonical_app):
                    raise CustodyError(f"protected install symlink escapes staged app: {candidate}")
            else:
                _require_root_owned_read_only(candidate, directory=True)
        for name in file_names:
            candidate = current / name
            metadata = candidate.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                if metadata.st_uid != 0:
                    raise CustodyError(f"protected install symlink is not root-owned: {candidate}")
                try:
                    resolved = candidate.resolve(strict=True)
                except OSError as error:
                    raise CustodyError(f"protected install symlink is broken: {candidate}") from error
                if not _within(resolved, canonical_app):
                    raise CustodyError(f"protected install symlink escapes staged app: {candidate}")
            else:
                _require_root_owned_read_only(candidate, directory=False)

    actual = fingerprint(app)
    if expected is not None:
        normalized = expected.lower()
        if len(normalized) != 64 or any(character not in "0123456789abcdef" for character in normalized):
            raise CustodyError("expected signed-app tree digest is malformed")
        if actual != normalized:
            raise CustodyError("protected install stage does not match the exact pre-staging signed-app tree")
    return actual


def _parse(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    fp = sub.add_parser("fingerprint")
    fp.add_argument("--app", required=True, type=Path)
    verify = sub.add_parser("verify-stage")
    verify.add_argument("--stage-root", required=True, type=Path)
    verify.add_argument("--app", required=True, type=Path)
    verify.add_argument("--expected")
    return parser.parse_args(argv)


def main(argv: Iterable[str] | None = None) -> int:
    args = _parse(list(sys.argv[1:] if argv is None else argv))
    try:
        if args.command == "fingerprint":
            value = fingerprint(args.app)
        else:
            value = verify_stage(args.stage_root, args.app, expected=args.expected)
    except (CustodyError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 74
    print(value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

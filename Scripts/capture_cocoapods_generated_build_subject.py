#!/usr/bin/env python3
"""Fingerprint the exact CocoaPods-generated Capture build subject.

The digest intentionally covers generated build inputs (`Pods/` and the
NembraCapture workspace) rather than trusting Podfile.lock or a CocoaPods
version string as a proxy. Absolute checkout paths are not serialized; only
root labels, relative paths, file bytes, entry type, mode, and symlink targets
are admitted.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import stat
import tempfile
from pathlib import Path
from typing import Iterable

SCHEMA = b"nembra-capture-cocoapods-generated-build-v1"


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


def _read_regular_file(path: Path, expected: tuple[int, ...]) -> bytes:
    nofollow = getattr(os, "O_NOFOLLOW", None)
    if nofollow is None:
        raise GeneratedBuildSubjectError("generated build custody requires O_NOFOLLOW support")
    flags = os.O_RDONLY | nofollow | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise GeneratedBuildSubjectError(f"generated build file could not be opened safely: {path}") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or _identity(before) != expected:
            raise GeneratedBuildSubjectError(f"generated build file changed before read: {path}")
        digest = hashlib.sha256()
        size = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            size += len(chunk)
            digest.update(chunk)
        after = os.fstat(descriptor)
        if _identity(after) != expected or size != after.st_size:
            raise GeneratedBuildSubjectError(f"generated build file changed during read: {path}")
        try:
            final = path.lstat()
        except OSError as error:
            raise GeneratedBuildSubjectError(f"generated build file pathname changed during read: {path}") from error
        if _identity(final) != expected or stat.S_ISLNK(final.st_mode):
            raise GeneratedBuildSubjectError(f"generated build file changed during final custody: {path}")
        return digest.digest()
    finally:
        os.close(descriptor)


def _directory_members(path: Path) -> tuple[str, ...]:
    try:
        return tuple(sorted(os.listdir(path), key=os.fsencode))
    except OSError as error:
        raise GeneratedBuildSubjectError(f"generated build directory changed during fingerprinting: {path}") from error


def _root_entries(root: Path) -> tuple[tuple[str, str, int, bytes], ...]:
    try:
        root_meta = root.lstat()
    except OSError as error:
        raise GeneratedBuildSubjectError(f"generated build root is unavailable: {root}") from error
    if stat.S_ISLNK(root_meta.st_mode) or not stat.S_ISDIR(root_meta.st_mode):
        raise GeneratedBuildSubjectError(f"generated build root must be one real directory: {root}")

    observed: list[tuple[Path, tuple[int, ...], str]] = [(root, _identity(root_meta), "D")]
    memberships: dict[Path, tuple[str, ...]] = {}
    entries: list[tuple[str, str, int, bytes]] = []

    for current_text, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_text)
        memberships[current] = tuple(sorted((*directory_names, *file_names), key=os.fsencode))
        kept: list[str] = []

        for name in sorted(directory_names, key=os.fsencode):
            candidate = current / name
            relative = candidate.relative_to(root).as_posix()
            meta = candidate.lstat()
            ident = _identity(meta)
            mode = stat.S_IMODE(meta.st_mode)
            if stat.S_ISLNK(meta.st_mode):
                target = os.readlink(candidate)
                observed.append((candidate, ident, "L"))
                entries.append(("L", relative, mode, os.fsencode(target)))
            elif stat.S_ISDIR(meta.st_mode):
                observed.append((candidate, ident, "D"))
                entries.append(("D", relative, mode, b""))
                kept.append(name)
            else:
                raise GeneratedBuildSubjectError(f"unsupported generated directory entry: {candidate}")
        directory_names[:] = kept

        for name in sorted(file_names, key=os.fsencode):
            candidate = current / name
            relative = candidate.relative_to(root).as_posix()
            meta = candidate.lstat()
            ident = _identity(meta)
            mode = stat.S_IMODE(meta.st_mode)
            if stat.S_ISLNK(meta.st_mode):
                target = os.readlink(candidate)
                observed.append((candidate, ident, "L"))
                entries.append(("L", relative, mode, os.fsencode(target)))
            elif stat.S_ISREG(meta.st_mode):
                content_hash = _read_regular_file(candidate, ident)
                observed.append((candidate, ident, "F"))
                entries.append(("F", relative, mode, content_hash))
            else:
                raise GeneratedBuildSubjectError(f"unsupported generated file entry: {candidate}")

    for candidate, ident, kind in observed:
        try:
            meta = candidate.lstat()
        except OSError as error:
            raise GeneratedBuildSubjectError(f"generated build entry disappeared: {candidate}") from error
        if _identity(meta) != ident:
            raise GeneratedBuildSubjectError(f"generated build entry changed during fingerprinting: {candidate}")
        if kind == "D" and not stat.S_ISDIR(meta.st_mode):
            raise GeneratedBuildSubjectError(f"generated build directory changed type: {candidate}")
        if kind == "F" and not stat.S_ISREG(meta.st_mode):
            raise GeneratedBuildSubjectError(f"generated build file changed type: {candidate}")
        if kind == "L" and not stat.S_ISLNK(meta.st_mode):
            raise GeneratedBuildSubjectError(f"generated build symlink changed type: {candidate}")
    for directory, members in memberships.items():
        if _directory_members(directory) != members:
            raise GeneratedBuildSubjectError(f"generated build directory membership changed: {directory}")

    return tuple(sorted(entries, key=lambda item: os.fsencode(item[1])))


def fingerprint(*, pods: Path, workspace: Path) -> str:
    digest = hashlib.sha256()
    _feed(digest, SCHEMA)
    for label, root in (("Pods", pods), ("NembraCapture.xcworkspace", workspace)):
        root_meta = root.lstat()
        _feed(digest, label.encode("utf-8"))
        _feed(digest, stat.S_IMODE(root_meta.st_mode).to_bytes(4, "big"))
        for kind, relative, mode, payload in _root_entries(root):
            _feed(digest, kind.encode("ascii"))
            _feed(digest, os.fsencode(relative))
            _feed(digest, mode.to_bytes(4, "big"))
            _feed(digest, payload)
    return digest.hexdigest()


def _self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="nembra-cocoapods-subject-") as temporary:
        root = Path(temporary)
        pods = root / "Pods"
        workspace = root / "NembraCapture.xcworkspace"
        support = pods / "Target Support Files/Pods-NembraCapture"
        support.mkdir(parents=True)
        workspace.mkdir()
        (support / "Pods-NembraCapture.debug.xcconfig").write_text("SWIFT_VERSION = 6.0\n", encoding="utf-8")
        (workspace / "contents.xcworkspacedata").write_text("<Workspace/>\n", encoding="utf-8")
        first = fingerprint(pods=pods, workspace=workspace)
        second = fingerprint(pods=pods, workspace=workspace)
        if first != second:
            raise AssertionError("stable generated graph must fingerprint deterministically")
        (support / "Pods-NembraCapture.debug.xcconfig").write_text("SWIFT_VERSION = 6.1\n", encoding="utf-8")
        changed = fingerprint(pods=pods, workspace=workspace)
        if changed == first:
            raise AssertionError("generated build byte mutation must change authority digest")
        link = pods / "External"
        link.symlink_to("../LocalSecrets/TuyaRuntime")
        linked = fingerprint(pods=pods, workspace=workspace)
        link.unlink()
        link.symlink_to("../LocalSecrets/TuyaRuntime2")
        if fingerprint(pods=pods, workspace=workspace) == linked:
            raise AssertionError("generated symlink target mutation must change authority digest")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Fingerprint exact CocoaPods-generated Capture build inputs")
    parser.add_argument("mode", nargs="?", choices=("fingerprint",), default="fingerprint")
    parser.add_argument("--pods", type=Path)
    parser.add_argument("--workspace", type=Path)
    parser.add_argument("--self-test", action="store_true")
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.self_test:
            _self_test()
            print("CocoaPods generated-build subject self-test passed.")
            return 0
        if args.pods is None or args.workspace is None:
            raise GeneratedBuildSubjectError("--pods and --workspace are required")
        print(fingerprint(pods=args.pods, workspace=args.workspace))
        return 0
    except (OSError, GeneratedBuildSubjectError, AssertionError) as error:
        print(f"ERROR: {error}", file=os.sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Fingerprint the exact CocoaPods-generated build subject for Nembra Capture.

The digest binds generated Pods support files and the generated Xcode workspace.
It hashes paths, entry kinds, permission bits, regular-file bytes, and symlink
link text without following symlinks into private inputs. Private source bytes
remain independently covered by the existing Tuya private-input provenance.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import stat
import tempfile
from pathlib import Path

SCHEMA = b"nembra-cocoapods-generated-build-subject-v1"


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
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _members(path: Path) -> tuple[str, ...]:
    try:
        return tuple(sorted(os.listdir(path), key=os.fsencode))
    except OSError as error:
        raise GeneratedBuildSubjectError(f"generated build directory changed: {path}") from error


def _stable_file_digest(path: Path, expected: tuple[int, ...]) -> bytes:
    nofollow = getattr(os, "O_NOFOLLOW", None)
    if nofollow is None:
        raise GeneratedBuildSubjectError("generated build custody requires O_NOFOLLOW support")
    try:
        descriptor = os.open(path, os.O_RDONLY | nofollow | getattr(os, "O_CLOEXEC", 0))
    except OSError as error:
        raise GeneratedBuildSubjectError(f"generated build file could not be opened safely: {path}") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or _identity(before) != expected:
            raise GeneratedBuildSubjectError(f"generated build file changed before hashing: {path}")
        digest = hashlib.sha256()
        size = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            size += len(chunk)
            digest.update(chunk)
        after = os.fstat(descriptor)
        current = path.lstat()
        if _identity(after) != expected or _identity(current) != expected or size != after.st_size:
            raise GeneratedBuildSubjectError(f"generated build file changed while hashing: {path}")
        return digest.digest()
    finally:
        os.close(descriptor)


def _tree_records(root: Path, label: str) -> tuple[list[tuple[bytes, ...]], list[tuple[Path, tuple[int, ...], str]], dict[Path, tuple[str, ...]]]:
    try:
        root_meta = root.lstat()
    except OSError as error:
        raise GeneratedBuildSubjectError(f"required generated build directory is missing: {label}") from error
    if stat.S_ISLNK(root_meta.st_mode) or not stat.S_ISDIR(root_meta.st_mode):
        raise GeneratedBuildSubjectError(f"required generated build subject is not a real directory: {label}")

    records: list[tuple[bytes, ...]] = []
    states: list[tuple[Path, tuple[int, ...], str]] = [(root, _identity(root_meta), "D")]
    memberships: dict[Path, tuple[str, ...]] = {}
    records.append((b"D", label.encode(), stat.S_IMODE(root_meta.st_mode).to_bytes(4, "big"), b""))

    for current_text, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_text)
        memberships[current] = tuple(sorted((*directory_names, *file_names), key=os.fsencode))
        kept: list[str] = []
        for name in sorted(directory_names, key=os.fsencode):
            path = current / name
            relative = f"{label}/{path.relative_to(root).as_posix()}".encode()
            meta = path.lstat()
            ident = _identity(meta)
            mode = stat.S_IMODE(meta.st_mode).to_bytes(4, "big")
            if stat.S_ISLNK(meta.st_mode):
                target = os.readlink(path).encode()
                if _identity(path.lstat()) != ident:
                    raise GeneratedBuildSubjectError(f"generated build symlink changed while hashing: {path}")
                states.append((path, ident, "L"))
                records.append((b"L", relative, mode, target))
            elif stat.S_ISDIR(meta.st_mode):
                states.append((path, ident, "D"))
                records.append((b"D", relative, mode, b""))
                kept.append(name)
            else:
                raise GeneratedBuildSubjectError(f"unsupported generated build directory entry: {path}")
        directory_names[:] = kept

        for name in sorted(file_names, key=os.fsencode):
            path = current / name
            relative = f"{label}/{path.relative_to(root).as_posix()}".encode()
            meta = path.lstat()
            ident = _identity(meta)
            mode = stat.S_IMODE(meta.st_mode).to_bytes(4, "big")
            if stat.S_ISLNK(meta.st_mode):
                target = os.readlink(path).encode()
                if _identity(path.lstat()) != ident:
                    raise GeneratedBuildSubjectError(f"generated build symlink changed while hashing: {path}")
                states.append((path, ident, "L"))
                records.append((b"L", relative, mode, target))
            elif stat.S_ISREG(meta.st_mode):
                payload = _stable_file_digest(path, ident)
                states.append((path, ident, "F"))
                records.append((b"F", relative, mode, payload))
            else:
                raise GeneratedBuildSubjectError(f"unsupported generated build file entry: {path}")
    return records, states, memberships


def fingerprint(pods: Path, workspace: Path) -> str:
    records: list[tuple[bytes, ...]] = []
    all_states: list[tuple[Path, tuple[int, ...], str]] = []
    memberships: dict[Path, tuple[str, ...]] = {}
    for root, label in ((pods, "Pods"), (workspace, "NembraCapture.xcworkspace")):
        tree_records, states, tree_memberships = _tree_records(root, label)
        records.extend(tree_records)
        all_states.extend(states)
        memberships.update(tree_memberships)

    for path, expected, kind in all_states:
        current = path.lstat()
        if _identity(current) != expected:
            raise GeneratedBuildSubjectError(f"generated build {kind} entry changed during final custody: {path}")
    for directory, expected_members in memberships.items():
        if _members(directory) != expected_members:
            raise GeneratedBuildSubjectError(f"generated build directory membership changed during hashing: {directory}")

    digest = hashlib.sha256()
    _feed(digest, SCHEMA)
    for record in sorted(records, key=lambda item: item[1]):
        for field in record:
            _feed(digest, field)
    return digest.hexdigest()


def _self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="nembra-generated-subject-") as temporary:
        root = Path(temporary)
        pods = root / "Pods"
        workspace = root / "NembraCapture.xcworkspace"
        support = pods / "Target Support Files/Pods-NembraCapture"
        support.mkdir(parents=True)
        workspace.mkdir()
        config = support / "Pods-NembraCapture.debug.xcconfig"
        config.write_text("SWIFT_ACTIVE_COMPILATION_CONDITIONS = REVIEWED\n", encoding="utf-8")
        (workspace / "contents.xcworkspacedata").write_text("reviewed\n", encoding="utf-8")
        first = fingerprint(pods, workspace)
        if len(first) != 64:
            raise AssertionError("fingerprint must be sha256")
        config.write_text("SWIFT_ACTIVE_COMPILATION_CONDITIONS = SUBSTITUTED\n", encoding="utf-8")
        second = fingerprint(pods, workspace)
        if first == second:
            raise AssertionError("build-affecting generated-byte change must change fingerprint")
        link = pods / "Development Pods"
        link.symlink_to("../LocalSecrets/TuyaRuntime")
        third = fingerprint(pods, workspace)
        link.unlink()
        link.symlink_to("../LocalSecrets/TuyaSDK")
        fourth = fingerprint(pods, workspace)
        if third == fourth:
            raise AssertionError("generated symlink target change must change fingerprint")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pods", type=Path)
    parser.add_argument("--workspace", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        _self_test()
        print("generated build subject self-test: PASS")
        return 0
    if args.pods is None or args.workspace is None:
        parser.error("--pods and --workspace are required unless --self-test is used")
    print(fingerprint(args.pods, args.workspace))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

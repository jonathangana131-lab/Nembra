#!/usr/bin/env python3
"""Fingerprint the exact ignored CocoaPods build subject used by Nembra Capture.

The accepted subject binds generated Pods/workspace structure, modes, regular-file
bytes, symlink text, and the bytes of every in-repository object reached through a
symlink. The same traversal can expose the real files/directories that must remain
under vnode custody while xcodebuild consumes the subject.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import stat
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Sequence

SCHEMA = b"nembra-cocoapods-generated-subject-v2"


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


def _relative(path: Path, repository_root: Path) -> str:
    try:
        return path.relative_to(repository_root).as_posix()
    except ValueError as error:
        raise GeneratedSubjectError("generated CocoaPods subject escapes the repository root") from error


def _inside(path: Path, root: Path) -> Path:
    try:
        resolved = path.resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise GeneratedSubjectError("generated CocoaPods symlink target could not be resolved safely") from error
    _relative(resolved, root)
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


@dataclass
class _Inspection:
    repository_root: Path
    active: set[Path] = field(default_factory=set)
    cache: dict[Path, bytes] = field(default_factory=dict)
    watch_paths: set[Path] = field(default_factory=set)

    def _watch_target_ancestry(self, target: Path) -> None:
        current = target.parent
        while True:
            _relative(current, self.repository_root)
            self.watch_paths.add(current)
            if current == self.repository_root:
                break
            current = current.parent

    def _symlink_payload(self, path: Path, metadata: os.stat_result) -> bytes:
        expected = _identity(metadata)
        try:
            target_text = os.readlink(path)
        except OSError as error:
            raise GeneratedSubjectError("generated build symlink changed before fingerprinting") from error
        resolved = _inside(path, self.repository_root)
        self._watch_target_ancestry(resolved)
        target_payload = self._real_payload(resolved)

        current = path.lstat()
        if _identity(current) != expected or not stat.S_ISLNK(current.st_mode):
            raise GeneratedSubjectError("generated build symlink changed during fingerprinting")
        if os.readlink(path) != target_text or _inside(path, self.repository_root) != resolved:
            raise GeneratedSubjectError("generated build symlink target changed during fingerprinting")

        digest = hashlib.sha256()
        _feed(digest, b"symlink")
        _feed(digest, _relative(path, self.repository_root).encode("utf-8"))
        _feed(digest, stat.S_IMODE(metadata.st_mode).to_bytes(4, "big"))
        _feed(digest, os.fsencode(target_text))
        _feed(digest, _relative(resolved, self.repository_root).encode("utf-8"))
        _feed(digest, target_payload)
        return digest.digest()

    def _real_payload(self, path: Path) -> bytes:
        try:
            metadata = path.lstat()
        except OSError as error:
            raise GeneratedSubjectError(f"generated build object is unavailable: {path}") from error
        if stat.S_ISLNK(metadata.st_mode):
            return self._symlink_payload(path, metadata)

        resolved = _inside(path, self.repository_root)
        if resolved != path.resolve(strict=True):
            raise GeneratedSubjectError("generated build object canonicalization changed unexpectedly")
        relative = _relative(resolved, self.repository_root)

        cached = self.cache.get(resolved)
        if cached is not None:
            return cached
        if resolved in self.active:
            digest = hashlib.sha256()
            _feed(digest, b"cycle-reference")
            _feed(digest, relative.encode("utf-8"))
            return digest.digest()

        expected = _identity(metadata)
        mode = stat.S_IMODE(metadata.st_mode)
        if stat.S_ISREG(metadata.st_mode):
            self.watch_paths.add(resolved)
            content_digest = _stable_file_digest(resolved, expected)
            digest = hashlib.sha256()
            _feed(digest, b"file")
            _feed(digest, relative.encode("utf-8"))
            _feed(digest, mode.to_bytes(4, "big"))
            _feed(digest, content_digest)
            payload = digest.digest()
            self.cache[resolved] = payload
            return payload

        if not stat.S_ISDIR(metadata.st_mode):
            raise GeneratedSubjectError("generated build subject contains an unsupported object type")

        self.watch_paths.add(resolved)
        expected_members = _members(resolved)
        self.active.add(resolved)
        try:
            child_payloads: list[tuple[bytes, bytes]] = []
            for name in expected_members:
                child = resolved / name
                child_payloads.append((os.fsencode(name), self._real_payload(child)))
        finally:
            self.active.remove(resolved)

        current = resolved.lstat()
        if _identity(current) != expected or not stat.S_ISDIR(current.st_mode):
            raise GeneratedSubjectError("generated build directory changed during fingerprinting")
        if _members(resolved) != expected_members:
            raise GeneratedSubjectError("generated build directory membership changed during fingerprinting")

        digest = hashlib.sha256()
        _feed(digest, b"directory")
        _feed(digest, relative.encode("utf-8"))
        _feed(digest, mode.to_bytes(4, "big"))
        for name, payload in child_payloads:
            _feed(digest, name)
            _feed(digest, payload)
        result = digest.digest()
        self.cache[resolved] = result
        return result

    def inspect_roots(self, roots: Iterable[Path]) -> str:
        ordered: list[tuple[str, Path]] = []
        for root in roots:
            try:
                metadata = root.lstat()
            except OSError as error:
                raise GeneratedSubjectError(f"generated build tree is unavailable: {root.name}") from error
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
                raise GeneratedSubjectError(f"generated build tree is not a real directory: {root.name}")
            resolved = _inside(root, self.repository_root)
            ordered.append((_relative(resolved, self.repository_root), resolved))
        if not ordered:
            raise GeneratedSubjectError("no generated build roots were supplied")

        digest = hashlib.sha256()
        _feed(digest, SCHEMA)
        for relative, root in sorted(ordered, key=lambda item: os.fsencode(item[0])):
            _feed(digest, relative.encode("utf-8"))
            _feed(digest, self._real_payload(root))
        return digest.hexdigest()


def inspect_subject(repository_root: Path, roots: Iterable[Path]) -> tuple[str, tuple[Path, ...]]:
    repository_root = repository_root.resolve(strict=True)
    inspection = _Inspection(repository_root)
    digest = inspection.inspect_roots(roots)
    return digest, tuple(sorted(inspection.watch_paths, key=lambda item: os.fsencode(str(item))))


def fingerprint_subject(repository_root: Path, roots: Iterable[Path]) -> str:
    digest, _ = inspect_subject(repository_root, roots)
    return digest


def subject_watch_paths(repository_root: Path, roots: Iterable[Path]) -> tuple[Path, ...]:
    _, paths = inspect_subject(repository_root, roots)
    return paths


def _self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="nembra-generated-subject-") as temporary:
        repository = Path(temporary).resolve()
        pods = repository / "Pods"
        workspace = repository / "NembraCapture.xcworkspace"
        sources = repository / "Sources"
        pods.mkdir()
        workspace.mkdir()
        sources.mkdir()
        project = pods / "project.pbxproj"
        project.write_text("A\n", encoding="utf-8")
        (workspace / "contents.xcworkspacedata").write_text("workspace\n", encoding="utf-8")

        first = fingerprint_subject(repository, (pods, workspace))
        second = fingerprint_subject(repository, (pods, workspace))
        if first != second:
            raise AssertionError("unchanged generated build subject was not stable")
        project.write_text("B\n", encoding="utf-8")
        third = fingerprint_subject(repository, (pods, workspace))
        if third == first:
            raise AssertionError("generated build byte substitution was not detected")

        target = sources / "Shared.swift"
        target.write_text("let value = 1\n", encoding="utf-8")
        link = pods / "Shared.swift"
        link.symlink_to(target)
        linked_first, watched = inspect_subject(repository, (pods, workspace))
        if target.resolve() not in watched:
            raise AssertionError("resolved generated-build symlink target was not placed under watch custody")
        target.write_text("let value = 2\n", encoding="utf-8")
        linked_second = fingerprint_subject(repository, (pods, workspace))
        if linked_second == linked_first:
            raise AssertionError("resolved generated-build symlink target byte substitution was not detected")

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

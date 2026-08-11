#!/usr/bin/env python3
"""Fingerprint and attest the exact CocoaPods-generated Capture build subject.

The accepted Podfile.lock digest is already reviewed by Final GO. This helper
binds the generated Pods/workspace bytes into that same reviewed digest through
one canonical comment attestation. It never follows symlinks while hashing;
external local-pod targets remain independently covered by private-input custody.

Pods/Manifest.lock is deliberately excluded from the generated-tree digest. It
is CocoaPods' mirrored copy of Podfile.lock and is consumed only by the standard
manifest consistency build phase. Bootstrap and the build-window guard require
that mirror to be byte-for-byte equal to the attested Podfile.lock, avoiding a
self-referential digest while preserving its build-time authority.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import stat
import tempfile
from pathlib import Path
from typing import Iterable

ATTESTATION_PREFIX = b"# NEMBRA_CAPTURE_GENERATED_BUILD_SUBJECT_SHA256="
_DIGEST_RE = re.compile(r"^[0-9a-f]{64}$")
_PODS_EXCLUDED_FROM_GRAPH = frozenset({"Manifest.lock"})


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


def _stable_file(path: Path, expected: tuple[int, ...]) -> tuple[int, str]:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise BuildSubjectError(f"generated build file is unavailable or unsafe: {path}") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or _identity(before) != expected:
            raise BuildSubjectError("generated build file changed before fingerprinting")
        digest = hashlib.sha256()
        count = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            count += len(chunk)
            digest.update(chunk)
        after = os.fstat(descriptor)
        if _identity(after) != expected or count != after.st_size:
            raise BuildSubjectError("generated build file changed while fingerprinting")
        current = path.lstat()
        if _identity(current) != expected or not stat.S_ISREG(current.st_mode):
            raise BuildSubjectError("generated build file pathname changed while fingerprinting")
        return stat.S_IMODE(after.st_mode), digest.hexdigest()
    finally:
        os.close(descriptor)


def stable_file_sha256(path: Path) -> str:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise BuildSubjectError(f"required build file is unavailable: {path}") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise BuildSubjectError(f"required build file is not one regular file: {path}")
    return _stable_file(path, _identity(metadata))[1]


def tree_fingerprint(
    root: Path,
    *,
    excluded_relative_paths: frozenset[str] = frozenset(),
) -> str:
    try:
        root_metadata = root.lstat()
    except OSError as error:
        raise BuildSubjectError(f"generated build tree is unavailable: {root}") from error
    if stat.S_ISLNK(root_metadata.st_mode) or not stat.S_ISDIR(root_metadata.st_mode):
        raise BuildSubjectError(f"generated build tree is not one real directory: {root}")

    entries: list[tuple[str, str, int, bytes]] = []
    states: list[tuple[Path, tuple[int, ...], str]] = [(root, _identity(root_metadata), "D")]
    memberships: dict[Path, tuple[str, ...]] = {}

    for current_text, directories, files in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_text)
        memberships[current] = tuple(sorted((*directories, *files), key=os.fsencode))
        kept: list[str] = []
        for name in sorted(directories, key=os.fsencode):
            path = current / name
            relative = path.relative_to(root).as_posix()
            metadata = path.lstat()
            identity = _identity(metadata)
            mode = stat.S_IMODE(metadata.st_mode)
            if relative in excluded_relative_paths:
                raise BuildSubjectError("generated-build exclusion unexpectedly names a directory")
            if stat.S_ISLNK(metadata.st_mode):
                target = os.readlink(path)
                states.append((path, identity, "L"))
                entries.append(("L", relative, mode, os.fsencode(target)))
            elif stat.S_ISDIR(metadata.st_mode):
                states.append((path, identity, "D"))
                entries.append(("D", relative, mode, b""))
                kept.append(name)
            else:
                raise BuildSubjectError("generated build tree contains unsupported directory entry")
        directories[:] = kept

        for name in sorted(files, key=os.fsencode):
            path = current / name
            relative = path.relative_to(root).as_posix()
            metadata = path.lstat()
            identity = _identity(metadata)
            mode = stat.S_IMODE(metadata.st_mode)
            if relative in excluded_relative_paths:
                if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
                    raise BuildSubjectError("excluded generated lock mirror is not one regular file")
                # Keep the mirror under traversal-stability checks but do not feed
                # its bytes into the graph digest. Its exact bytes are instead
                # required to equal the attested Podfile.lock.
                states.append((path, identity, "F"))
                continue
            if stat.S_ISLNK(metadata.st_mode):
                target = os.readlink(path)
                states.append((path, identity, "L"))
                entries.append(("L", relative, mode, os.fsencode(target)))
            elif stat.S_ISREG(metadata.st_mode):
                file_mode, content_sha = _stable_file(path, identity)
                states.append((path, identity, "F"))
                entries.append(("F", relative, file_mode, bytes.fromhex(content_sha)))
            else:
                raise BuildSubjectError("generated build tree contains unsupported file entry")

    for path, expected, kind in states:
        current = path.lstat()
        if _identity(current) != expected:
            raise BuildSubjectError("generated build tree changed while fingerprinting")
        if kind == "D" and not stat.S_ISDIR(current.st_mode):
            raise BuildSubjectError("generated build tree type changed while fingerprinting")
        if kind == "F" and not stat.S_ISREG(current.st_mode):
            raise BuildSubjectError("generated build tree type changed while fingerprinting")
        if kind == "L" and not stat.S_ISLNK(current.st_mode):
            raise BuildSubjectError("generated build tree type changed while fingerprinting")
    for directory, expected in memberships.items():
        if tuple(sorted(os.listdir(directory), key=os.fsencode)) != expected:
            raise BuildSubjectError("generated build tree membership changed while fingerprinting")

    digest = hashlib.sha256()
    _feed(digest, b"nembra-cocoapods-generated-tree-v2")
    _feed(digest, stat.S_IMODE(root_metadata.st_mode).to_bytes(4, "big"))
    for kind, relative, mode, payload in sorted(entries, key=lambda item: os.fsencode(item[1])):
        _feed(digest, kind.encode("ascii"))
        _feed(digest, os.fsencode(relative))
        _feed(digest, mode.to_bytes(4, "big"))
        _feed(digest, payload)
    return digest.hexdigest()


def build_subject_fingerprint(*, pods: Path, workspace: Path) -> str:
    digest = hashlib.sha256()
    _feed(digest, b"nembra-cocoapods-build-subject-v2")
    _feed(digest, b"Pods")
    _feed(
        digest,
        bytes.fromhex(
            tree_fingerprint(
                pods,
                excluded_relative_paths=_PODS_EXCLUDED_FROM_GRAPH,
            )
        ),
    )
    _feed(digest, b"NembraCapture.xcworkspace")
    _feed(digest, bytes.fromhex(tree_fingerprint(workspace)))
    return digest.hexdigest()


def read_attestation(lockfile: Path) -> str:
    try:
        data = lockfile.read_bytes()
    except OSError as error:
        raise BuildSubjectError("Podfile.lock attestation subject is unavailable") from error
    matches: list[str] = []
    for raw in data.splitlines():
        if raw.startswith(ATTESTATION_PREFIX):
            value = raw[len(ATTESTATION_PREFIX):].decode("ascii", errors="strict")
            matches.append(value)
    if len(matches) != 1 or _DIGEST_RE.fullmatch(matches[0]) is None:
        raise BuildSubjectError("Podfile.lock must contain exactly one canonical generated-build attestation")
    return matches[0]


def attest_lock(lockfile: Path, digest: str) -> None:
    if _DIGEST_RE.fullmatch(digest) is None:
        raise BuildSubjectError("generated build subject digest must be lowercase 64-hex")
    try:
        metadata = lockfile.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
            raise BuildSubjectError("lock attestation subject must be one regular file")
        data = lockfile.read_bytes()
    except OSError as error:
        raise BuildSubjectError("lock attestation subject is unavailable") from error

    kept = [line for line in data.splitlines(keepends=True) if not line.startswith(ATTESTATION_PREFIX)]
    base = b"".join(kept)
    if base and not base.endswith(b"\n"):
        base += b"\n"
    rendered = base + ATTESTATION_PREFIX + digest.encode("ascii") + b"\n"

    temporary_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(dir=lockfile.parent, prefix=".nembra-lock-attest.", delete=False) as handle:
            temporary_name = handle.name
            os.fchmod(handle.fileno(), stat.S_IMODE(metadata.st_mode))
            handle.write(rendered)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, lockfile)
        temporary_name = None
    finally:
        if temporary_name is not None:
            try:
                os.unlink(temporary_name)
            except FileNotFoundError:
                pass


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Nembra Capture CocoaPods generated-build subject")
    sub = parser.add_subparsers(dest="mode", required=True)
    fingerprint = sub.add_parser("fingerprint")
    fingerprint.add_argument("--pods", required=True, type=Path)
    fingerprint.add_argument("--workspace", required=True, type=Path)
    read = sub.add_parser("read-attestation")
    read.add_argument("--lockfile", required=True, type=Path)
    attest = sub.add_parser("attest-lock")
    attest.add_argument("--lockfile", required=True, type=Path)
    attest.add_argument("--digest", required=True)
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.mode == "fingerprint":
            print(build_subject_fingerprint(pods=args.pods, workspace=args.workspace))
        elif args.mode == "read-attestation":
            print(read_attestation(args.lockfile))
        else:
            attest_lock(args.lockfile, args.digest)
            print(args.digest)
    except (OSError, UnicodeError, BuildSubjectError) as error:
        print(f"ERROR: {error}", file=os.sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

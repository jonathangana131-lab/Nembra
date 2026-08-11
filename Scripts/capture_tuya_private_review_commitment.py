#!/usr/bin/env python3
"""Secret-safe external review commitment for Capture private Tuya inputs.

The public commitment is HMAC-SHA256 over the canonical race-aware private
provenance subject. Its random 256-bit key stays only in ignored LocalSecrets,
so publishing the HMAC does not expose a raw credential-bearing source digest or
create a public offline AppKey/AppSecret guessing oracle.
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import importlib.util
import os
import stat
import sys
from pathlib import Path
from typing import Sequence

DOMAIN = b"nembra-capture-private-review-hmac-v1\x00"
KEY_BYTES = 32


class CommitmentError(RuntimeError):
    pass


def _load_provenance():
    helper = Path(__file__).with_name("capture_tuya_private_input_provenance.py")
    spec = importlib.util.spec_from_file_location(
        "capture_tuya_private_input_provenance_for_commitment",
        helper,
    )
    if spec is None or spec.loader is None:
        raise CommitmentError("private provenance helper could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


provenance = _load_provenance()


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


def _directory_identity(metadata: os.stat_result) -> tuple[int, ...]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_uid,
        metadata.st_gid,
    )


def _canonical_absolute_path(path: Path, label: str) -> Path:
    path = path.expanduser()
    if not path.is_absolute() or path.anchor != os.sep:
        raise CommitmentError(f"{label} path must be absolute")
    if any(component in ("", ".", "..") for component in path.parts[1:]):
        raise CommitmentError(f"{label} path must be canonical")
    if len(path.parts) < 2:
        raise CommitmentError(f"{label} path must name a file")
    return path


def _open_nosymlink_chain(path: Path) -> tuple[list[int], int, tuple[tuple[int, ...], ...]]:
    nofollow = getattr(os, "O_NOFOLLOW", None)
    directory_flag = getattr(os, "O_DIRECTORY", None)
    if nofollow is None or directory_flag is None:
        raise CommitmentError("private review authority requires O_NOFOLLOW and O_DIRECTORY support")

    directory_flags = os.O_RDONLY | directory_flag | nofollow | getattr(os, "O_CLOEXEC", 0)
    file_flags = os.O_RDONLY | nofollow | getattr(os, "O_CLOEXEC", 0)
    directories: list[int] = []
    identities: list[tuple[int, ...]] = []
    try:
        root_descriptor = os.open(os.sep, directory_flags)
        directories.append(root_descriptor)
        root_metadata = os.fstat(root_descriptor)
        if not stat.S_ISDIR(root_metadata.st_mode):
            raise CommitmentError("filesystem root is not a directory")
        identities.append(_directory_identity(root_metadata))

        parent_descriptor = root_descriptor
        for component in path.parts[1:-1]:
            try:
                descriptor = os.open(component, directory_flags, dir_fd=parent_descriptor)
            except OSError as error:
                raise CommitmentError(
                    "private review key path contains an unavailable or symlinked directory component"
                ) from error
            metadata = os.fstat(descriptor)
            if not stat.S_ISDIR(metadata.st_mode):
                os.close(descriptor)
                raise CommitmentError("private review key path component is not a directory")
            directories.append(descriptor)
            identities.append(_directory_identity(metadata))
            parent_descriptor = descriptor

        try:
            key_descriptor = os.open(path.name, file_flags, dir_fd=parent_descriptor)
        except OSError as error:
            raise CommitmentError("private review key is unavailable, unsafe, or symlinked") from error
        return directories, key_descriptor, tuple(identities)
    except Exception:
        for descriptor in reversed(directories):
            try:
                os.close(descriptor)
            except OSError:
                pass
        raise


def _close_descriptors(descriptors: Sequence[int]) -> None:
    for descriptor in reversed(tuple(descriptors)):
        try:
            os.close(descriptor)
        except OSError:
            pass


def _current_chain_identity(path: Path) -> tuple[tuple[tuple[int, ...], ...], tuple[int, ...]]:
    directories, key_descriptor, identities = _open_nosymlink_chain(path)
    try:
        return identities, _identity(os.fstat(key_descriptor))
    finally:
        os.close(key_descriptor)
        _close_descriptors(directories)


def _read_review_key(path: Path) -> bytes:
    path = _canonical_absolute_path(path, "private review key")
    directories, descriptor, directory_identities = _open_nosymlink_chain(path)
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise CommitmentError("private review key is not a regular file")
        if stat.S_IMODE(before.st_mode) != 0o600:
            raise CommitmentError("private review key must be mode 0600")
        if before.st_uid != os.getuid():
            raise CommitmentError("private review key is not owned by the current field user")
        if before.st_size != KEY_BYTES:
            raise CommitmentError("private review key must contain exactly 32 random bytes")
        raw = bytearray()
        while len(raw) < KEY_BYTES:
            chunk = os.read(descriptor, KEY_BYTES - len(raw))
            if not chunk:
                break
            raw.extend(chunk)
        extra = os.read(descriptor, 1)
        after = os.fstat(descriptor)
        if len(raw) != KEY_BYTES or extra or _identity(before) != _identity(after):
            raise CommitmentError("private review key changed while it was read")
        final_identity = _identity(after)
    finally:
        os.close(descriptor)
        _close_descriptors(directories)

    # Rewalk from the filesystem root after the descriptor read. Holding the
    # original directory chain makes the read itself symlink-safe; this second
    # independent walk proves the lexical field path still names that same chain
    # and key generation after the read completes.
    current_directories, current_key = _current_chain_identity(path)
    if current_directories != directory_identities or current_key != final_identity:
        raise CommitmentError("private review key pathname changed while it was read")
    return bytes(raw)


def commitment(
    *,
    key_file: Path,
    lockfile: Path,
    security_podspec: Path,
    security_build: Path,
    identity_podspec: Path,
    identity_sources: Path,
) -> str:
    key = _read_review_key(key_file)
    record = provenance.build_record(
        lockfile=lockfile,
        security_podspec=security_podspec,
        security_build=security_build,
        identity_podspec=identity_podspec,
        identity_sources=identity_sources,
    )
    canonical = provenance._record_text(record).encode("utf-8")
    return hmac.new(key, DOMAIN + canonical, hashlib.sha256).hexdigest()


def verify(expected: str, **paths: Path) -> None:
    normalized = expected.lower()
    if len(normalized) != 64 or any(character not in "0123456789abcdef" for character in normalized):
        raise CommitmentError("accepted private review HMAC must be exactly 64 hexadecimal characters")
    actual = commitment(**paths)
    if not hmac.compare_digest(actual, normalized):
        raise CommitmentError("current private Tuya generation does not match external review authority")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("review", "verify"))
    parser.add_argument("--key-file", required=True, type=Path)
    parser.add_argument("--lockfile", required=True, type=Path)
    parser.add_argument("--security-podspec", required=True, type=Path)
    parser.add_argument("--security-build", required=True, type=Path)
    parser.add_argument("--identity-podspec", required=True, type=Path)
    parser.add_argument("--identity-sources", required=True, type=Path)
    parser.add_argument("--expect", default="")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = _parser()
    args = parser.parse_args(list(sys.argv[1:] if argv is None else argv))
    paths = {
        "key_file": args.key_file,
        "lockfile": args.lockfile,
        "security_podspec": args.security_podspec,
        "security_build": args.security_build,
        "identity_podspec": args.identity_podspec,
        "identity_sources": args.identity_sources,
    }
    try:
        if args.mode == "review":
            if args.expect:
                raise CommitmentError("review mode does not accept external authority")
            print(commitment(**paths))
        else:
            if not args.expect:
                raise CommitmentError("verify mode requires --expect external authority")
            verify(args.expect, **paths)
            print("Private Tuya review HMAC matched external authority.")
        return 0
    except (CommitmentError, provenance.ProvenanceError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 73


if __name__ == "__main__":
    raise SystemExit(main())

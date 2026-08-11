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


def _read_review_key(path: Path) -> bytes:
    nofollow = getattr(os, "O_NOFOLLOW", None)
    if nofollow is None:
        raise CommitmentError("private review authority requires O_NOFOLLOW support")
    flags = os.O_RDONLY | nofollow | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise CommitmentError("private review key is unavailable or unsafe") from error
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
        try:
            current = path.lstat()
        except OSError as error:
            raise CommitmentError("private review key pathname changed while it was read") from error
        if stat.S_ISLNK(current.st_mode) or _identity(current) != _identity(after):
            raise CommitmentError("private review key pathname changed while it was read")
        return bytes(raw)
    finally:
        os.close(descriptor)


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
        "key_file": args.key_file.resolve(),
        "lockfile": args.lockfile.resolve(),
        "security_podspec": args.security_podspec.resolve(),
        "security_build": args.security_build.resolve(),
        "identity_podspec": args.identity_podspec.resolve(),
        "identity_sources": args.identity_sources.resolve(),
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

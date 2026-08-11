#!/usr/bin/env python3
"""Create and verify the secret-safe Nembra Capture private review commitment.

The private Tuya provenance witness contains hashes of credential-bearing local
inputs. Publishing a raw witness/source hash would create an avoidable offline
credential-guess oracle. Instead, review-only candidate generation creates a
fresh 256-bit local key and exposes only a domain-separated HMAC-SHA256 tag.
The key and witness remain ignored local mode-0600 files. Field admission must
receive the already owner-reviewed tag from the closed Final-GO environment and
recompute it from descriptor-stable local subjects before any build side effect.
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import os
import secrets
import stat
import tempfile
from pathlib import Path
from typing import Iterable

DOMAIN = b"nembra-capture-private-input-review-v1\x00"
KEY_BYTES = 32
MAX_WITNESS_BYTES = 64 * 1024
TAG_HEX_BYTES = 64


class PrivateReviewCommitmentError(RuntimeError):
    pass


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


def _require_private_regular(path: Path, *, exact_size: int | None, max_size: int) -> tuple[os.stat_result, bytes]:
    try:
        before_path = path.lstat()
    except OSError as error:
        raise PrivateReviewCommitmentError(f"private review subject is unavailable: {path}") from error
    if stat.S_ISLNK(before_path.st_mode) or not stat.S_ISREG(before_path.st_mode):
        raise PrivateReviewCommitmentError(f"private review subject is not one regular file: {path}")
    if before_path.st_uid != os.geteuid():
        raise PrivateReviewCommitmentError(f"private review subject is not owned by the current user: {path}")
    if before_path.st_nlink != 1:
        raise PrivateReviewCommitmentError(f"private review subject has unexpected hard links: {path}")
    if stat.S_IMODE(before_path.st_mode) != 0o600:
        raise PrivateReviewCommitmentError(f"private review subject must be mode 0600: {path}")
    if exact_size is not None and before_path.st_size != exact_size:
        raise PrivateReviewCommitmentError(f"private review key must be exactly {exact_size} bytes")
    if before_path.st_size > max_size:
        raise PrivateReviewCommitmentError(f"private review subject exceeds the accepted size bound: {path}")

    nofollow = getattr(os, "O_NOFOLLOW", None)
    if nofollow is None:
        raise PrivateReviewCommitmentError("private review commitment requires O_NOFOLLOW support")
    flags = os.O_RDONLY | nofollow | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise PrivateReviewCommitmentError(f"private review subject could not be opened safely: {path}") from error
    try:
        before_fd = os.fstat(descriptor)
        if _identity(before_fd) != _identity(before_path):
            raise PrivateReviewCommitmentError(f"private review subject changed before descriptor custody: {path}")
        chunks: list[bytes] = []
        total = 0
        while True:
            chunk = os.read(descriptor, min(1024 * 1024, max_size + 1 - total))
            if not chunk:
                break
            chunks.append(chunk)
            total += len(chunk)
            if total > max_size:
                raise PrivateReviewCommitmentError(f"private review subject exceeded the accepted size bound while reading: {path}")
        after_fd = os.fstat(descriptor)
        if _identity(after_fd) != _identity(before_fd) or total != after_fd.st_size:
            raise PrivateReviewCommitmentError(f"private review subject changed while reading: {path}")
        try:
            after_path = path.lstat()
        except OSError as error:
            raise PrivateReviewCommitmentError(f"private review subject pathname changed after reading: {path}") from error
        if _identity(after_path) != _identity(after_fd):
            raise PrivateReviewCommitmentError(f"private review subject pathname changed after descriptor read: {path}")
        return after_fd, b"".join(chunks)
    finally:
        os.close(descriptor)


def _require_private_parent(path: Path) -> Path:
    parent = path.parent
    try:
        metadata = parent.lstat()
    except OSError as error:
        raise PrivateReviewCommitmentError(f"private review key parent is unavailable: {parent}") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise PrivateReviewCommitmentError(f"private review key parent is not one real directory: {parent}")
    if metadata.st_uid != os.geteuid():
        raise PrivateReviewCommitmentError(f"private review key parent is not owned by the current user: {parent}")
    return parent


def _write_fresh_key(path: Path) -> bytes:
    parent = _require_private_parent(path)
    key = secrets.token_bytes(KEY_BYTES)
    temporary_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(dir=parent, prefix=".nembra-private-review-key.", delete=False) as handle:
            temporary_name = handle.name
            os.fchmod(handle.fileno(), 0o600)
            handle.write(key)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, path)
        temporary_name = None
        try:
            directory_fd = os.open(parent, os.O_RDONLY | getattr(os, "O_CLOEXEC", 0))
        except OSError as error:
            raise PrivateReviewCommitmentError("private review key directory could not be opened for durability") from error
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if temporary_name is not None:
            try:
                os.unlink(temporary_name)
            except FileNotFoundError:
                pass
    _, observed = _require_private_regular(path, exact_size=KEY_BYTES, max_size=KEY_BYTES)
    if not hmac.compare_digest(observed, key):
        raise PrivateReviewCommitmentError("private review key bytes changed during creation")
    return key


def _tag(key: bytes, witness: bytes) -> str:
    return hmac.new(key, DOMAIN + witness, hashlib.sha256).hexdigest()


def create_commitment(*, witness: Path, key_path: Path) -> str:
    _, witness_bytes = _require_private_regular(witness, exact_size=None, max_size=MAX_WITNESS_BYTES)
    key = _write_fresh_key(key_path)
    _, stable_witness = _require_private_regular(witness, exact_size=None, max_size=MAX_WITNESS_BYTES)
    _, stable_key = _require_private_regular(key_path, exact_size=KEY_BYTES, max_size=KEY_BYTES)
    if stable_witness != witness_bytes or not hmac.compare_digest(stable_key, key):
        raise PrivateReviewCommitmentError("private review witness/key changed while commitment was created")
    return _tag(stable_key, stable_witness)


def verify_commitment(*, witness: Path, key_path: Path, expected_tag: str) -> str:
    normalized = expected_tag.lower()
    if len(normalized) != TAG_HEX_BYTES or any(character not in "0123456789abcdef" for character in normalized):
        raise PrivateReviewCommitmentError("accepted private review commitment must be exactly 64 hexadecimal characters")
    _, witness_bytes = _require_private_regular(witness, exact_size=None, max_size=MAX_WITNESS_BYTES)
    _, key = _require_private_regular(key_path, exact_size=KEY_BYTES, max_size=KEY_BYTES)
    observed = _tag(key, witness_bytes)
    if not hmac.compare_digest(observed, normalized):
        raise PrivateReviewCommitmentError("private review witness/key do not match the externally accepted commitment")
    _, final_witness = _require_private_regular(witness, exact_size=None, max_size=MAX_WITNESS_BYTES)
    _, final_key = _require_private_regular(key_path, exact_size=KEY_BYTES, max_size=KEY_BYTES)
    if final_witness != witness_bytes or not hmac.compare_digest(final_key, key):
        raise PrivateReviewCommitmentError("private review witness/key changed during commitment verification")
    return observed


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Nembra Capture opaque private review commitment")
    subparsers = parser.add_subparsers(dest="mode", required=True)
    create = subparsers.add_parser("create")
    create.add_argument("--witness", required=True, type=Path)
    create.add_argument("--key", required=True, type=Path)
    verify = subparsers.add_parser("verify")
    verify.add_argument("--witness", required=True, type=Path)
    verify.add_argument("--key", required=True, type=Path)
    verify.add_argument("--expected", required=True)
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    arguments = _parser().parse_args(list(argv) if argv is not None else None)
    try:
        if arguments.mode == "create":
            value = create_commitment(witness=arguments.witness, key_path=arguments.key)
        else:
            value = verify_commitment(witness=arguments.witness, key_path=arguments.key, expected_tag=arguments.expected)
    except (OSError, PrivateReviewCommitmentError) as error:
        print(f"ERROR: private review commitment rejected: {error}", file=os.sys.stderr)
        return 79
    print(value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Create and verify the opaque review commitment for private Tuya build inputs.

The public review subject is an HMAC-SHA256 tag over the canonical private
provenance witness. Its random 256-bit key remains local beneath ignored
LocalSecrets and is never printed. Publishing the tag therefore does not expose
an offline oracle over credential-bearing source bytes.
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import os
from pathlib import Path
import secrets
import stat
import sys
import tempfile
from typing import Sequence

DOMAIN = b"nembra-capture-private-input-review-v1\0"
KEY_BYTES = 32
MAX_WITNESS_BYTES = 64 * 1024


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


def _lexical_absolute(path: Path) -> Path:
    return Path(os.path.abspath(os.fspath(path.expanduser())))


def _require_real_checkout_path(path: Path, repository_root: Path, *, label: str) -> Path:
    candidate = _lexical_absolute(path)
    root = _lexical_absolute(repository_root)
    try:
        relative = candidate.relative_to(root)
    except ValueError as error:
        raise PrivateReviewCommitmentError(f"{label} must remain inside the accepted checkout") from error

    try:
        root_metadata = root.lstat()
    except OSError as error:
        raise PrivateReviewCommitmentError("accepted checkout root is unavailable") from error
    if stat.S_ISLNK(root_metadata.st_mode) or not stat.S_ISDIR(root_metadata.st_mode):
        raise PrivateReviewCommitmentError("accepted checkout root must be one real directory")

    current = root
    for component in relative.parts[:-1]:
        current = current / component
        try:
            metadata = current.lstat()
        except OSError as error:
            raise PrivateReviewCommitmentError(f"{label} ancestry is unavailable") from error
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            raise PrivateReviewCommitmentError(f"{label} ancestry must contain only real directories")
    return candidate


def _read_private_regular_file(
    path: Path,
    *,
    label: str,
    exact_size: int | None = None,
    maximum_size: int | None = None,
) -> tuple[bytes, tuple[int, ...]]:
    nofollow = getattr(os, "O_NOFOLLOW", None)
    if nofollow is None:
        raise PrivateReviewCommitmentError("private review custody requires O_NOFOLLOW support")

    try:
        before_path = path.lstat()
    except OSError as error:
        raise PrivateReviewCommitmentError(f"{label} is unavailable") from error
    if stat.S_ISLNK(before_path.st_mode) or not stat.S_ISREG(before_path.st_mode):
        raise PrivateReviewCommitmentError(f"{label} must be one real regular file")
    if before_path.st_uid != os.getuid():
        raise PrivateReviewCommitmentError(f"{label} must be owned by the current field user")
    if before_path.st_nlink != 1:
        raise PrivateReviewCommitmentError(f"{label} must have exactly one hard link")
    if stat.S_IMODE(before_path.st_mode) != 0o600:
        raise PrivateReviewCommitmentError(f"{label} must be mode 0600")
    if exact_size is not None and before_path.st_size != exact_size:
        raise PrivateReviewCommitmentError(f"{label} has an invalid size")
    if maximum_size is not None and before_path.st_size > maximum_size:
        raise PrivateReviewCommitmentError(f"{label} exceeds its accepted size bound")

    flags = os.O_RDONLY | nofollow | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise PrivateReviewCommitmentError(f"{label} could not be opened safely") from error
    try:
        before = os.fstat(descriptor)
        if _identity(before) != _identity(before_path):
            raise PrivateReviewCommitmentError(f"{label} changed while custody was established")
        data = bytearray()
        while True:
            chunk = os.read(descriptor, 64 * 1024)
            if not chunk:
                break
            data.extend(chunk)
            if maximum_size is not None and len(data) > maximum_size:
                raise PrivateReviewCommitmentError(f"{label} exceeds its accepted size bound")
        after = os.fstat(descriptor)
        if _identity(after) != _identity(before) or len(data) != after.st_size:
            raise PrivateReviewCommitmentError(f"{label} changed while it was read")
        try:
            final_path = path.lstat()
        except OSError as error:
            raise PrivateReviewCommitmentError(f"{label} pathname changed during custody") from error
        if _identity(final_path) != _identity(after):
            raise PrivateReviewCommitmentError(f"{label} pathname changed during custody")
        return bytes(data), _identity(after)
    finally:
        os.close(descriptor)


def _atomic_private_key(path: Path) -> None:
    parent = path.parent
    try:
        parent_metadata = parent.lstat()
    except OSError as error:
        raise PrivateReviewCommitmentError("private review key directory is unavailable") from error
    if stat.S_ISLNK(parent_metadata.st_mode) or not stat.S_ISDIR(parent_metadata.st_mode):
        raise PrivateReviewCommitmentError("private review key directory must be one real directory")
    if parent_metadata.st_uid != os.getuid():
        raise PrivateReviewCommitmentError("private review key directory must be owned by the current field user")

    key = secrets.token_bytes(KEY_BYTES)
    descriptor: int | None = None
    temporary_name: str | None = None
    try:
        descriptor, temporary_name = tempfile.mkstemp(prefix=".nembra-private-review-key-", dir=parent)
        os.fchmod(descriptor, 0o600)
        written = 0
        while written < len(key):
            count = os.write(descriptor, key[written:])
            if count <= 0:
                raise PrivateReviewCommitmentError("private review key write did not make progress")
            written += count
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = None
        os.replace(temporary_name, path)
        temporary_name = None
        directory_descriptor = os.open(parent, os.O_RDONLY | getattr(os, "O_CLOEXEC", 0))
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    except OSError as error:
        raise PrivateReviewCommitmentError("private review key could not be created atomically") from error
    finally:
        if descriptor is not None:
            os.close(descriptor)
        if temporary_name is not None:
            try:
                os.unlink(temporary_name)
            except OSError:
                pass


def _commitment(witness: bytes, key: bytes) -> str:
    return hmac.new(key, DOMAIN + witness, hashlib.sha256).hexdigest()


def create_commitment(*, witness: Path, key_file: Path, repository_root: Path) -> str:
    witness_path = _require_real_checkout_path(witness, repository_root, label="private provenance witness")
    key_path = _require_real_checkout_path(key_file, repository_root, label="private review key")
    if witness_path.parent != key_path.parent:
        raise PrivateReviewCommitmentError("private witness and review key must share one private identity directory")

    witness_bytes, witness_identity = _read_private_regular_file(
        witness_path,
        label="private provenance witness",
        maximum_size=MAX_WITNESS_BYTES,
    )
    _atomic_private_key(key_path)
    key_bytes, _ = _read_private_regular_file(
        key_path,
        label="private review key",
        exact_size=KEY_BYTES,
    )
    # Re-read after key creation so the public tag cannot describe a witness that
    # was swapped while the local secret was being rotated.
    final_witness, final_identity = _read_private_regular_file(
        witness_path,
        label="private provenance witness",
        maximum_size=MAX_WITNESS_BYTES,
    )
    if witness_identity != final_identity or not hmac.compare_digest(witness_bytes, final_witness):
        raise PrivateReviewCommitmentError("private provenance witness changed while review commitment was created")
    return _commitment(final_witness, key_bytes)


def verify_commitment(
    *,
    witness: Path,
    key_file: Path,
    repository_root: Path,
    accepted_tag: str,
) -> None:
    normalized = accepted_tag.lower()
    if len(normalized) != 64 or any(character not in "0123456789abcdef" for character in normalized):
        raise PrivateReviewCommitmentError("accepted private review commitment must be exactly 64 hex characters")

    witness_path = _require_real_checkout_path(witness, repository_root, label="private provenance witness")
    key_path = _require_real_checkout_path(key_file, repository_root, label="private review key")
    if witness_path.parent != key_path.parent:
        raise PrivateReviewCommitmentError("private witness and review key must share one private identity directory")

    witness_bytes, witness_identity = _read_private_regular_file(
        witness_path,
        label="private provenance witness",
        maximum_size=MAX_WITNESS_BYTES,
    )
    key_bytes, key_identity = _read_private_regular_file(
        key_path,
        label="private review key",
        exact_size=KEY_BYTES,
    )
    actual = _commitment(witness_bytes, key_bytes)
    if not hmac.compare_digest(actual, normalized):
        raise PrivateReviewCommitmentError("private Tuya inputs do not match the owner-reviewed opaque commitment")

    # One final pathname-stable reread closes key/witness replacement between
    # computation and caller admission.
    final_witness, final_witness_identity = _read_private_regular_file(
        witness_path,
        label="private provenance witness",
        maximum_size=MAX_WITNESS_BYTES,
    )
    final_key, final_key_identity = _read_private_regular_file(
        key_path,
        label="private review key",
        exact_size=KEY_BYTES,
    )
    if (
        witness_identity != final_witness_identity
        or key_identity != final_key_identity
        or not hmac.compare_digest(witness_bytes, final_witness)
        or not hmac.compare_digest(key_bytes, final_key)
        or not hmac.compare_digest(_commitment(final_witness, final_key), normalized)
    ):
        raise PrivateReviewCommitmentError("private review commitment subjects changed during verification")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Create/verify Nembra's secret-safe private Tuya review commitment")
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name in ("create", "verify"):
        child = subparsers.add_parser(name)
        child.add_argument("--repository-root", required=True, type=Path)
        child.add_argument("--witness", required=True, type=Path)
        child.add_argument("--key-file", required=True, type=Path)
        if name == "verify":
            child.add_argument("--accepted-tag", required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(list(sys.argv[1:] if argv is None else argv))
    try:
        if args.command == "create":
            tag = create_commitment(
                witness=args.witness,
                key_file=args.key_file,
                repository_root=args.repository_root,
            )
            print(tag)
            return 0
        verify_commitment(
            witness=args.witness,
            key_file=args.key_file,
            repository_root=args.repository_root,
            accepted_tag=args.accepted_tag,
        )
        return 0
    except PrivateReviewCommitmentError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 76


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Opaque review commitment for ignored/private Tuya field-build inputs.

The underlying provenance record remains mode-0600 beneath LocalSecrets and may
contain hashes derived from credential-bearing generated Swift. A random local
HMAC key makes the value exported to the Final-GO review plane an opaque
commitment instead of a public password/AppSecret verification oracle.
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import importlib.util
import os
import stat
import tempfile
from pathlib import Path
from typing import Iterable

DOMAIN = b"nembra-capture-private-input-review-v1\x00"
KEY_BYTES = 32


class PrivateReviewError(RuntimeError):
    pass


def _load_provenance():
    helper = Path(__file__).with_name("capture_tuya_private_input_provenance.py")
    spec = importlib.util.spec_from_file_location("capture_tuya_private_input_provenance", helper)
    if spec is None or spec.loader is None:
        raise PrivateReviewError("private-input provenance helper could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


provenance = _load_provenance()


def _stat_identity(metadata: os.stat_result) -> tuple[int, ...]:
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


def _require_private_parent(path: Path) -> None:
    try:
        metadata = path.parent.lstat()
    except OSError as error:
        raise PrivateReviewError("private review directory is unavailable") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise PrivateReviewError("private review directory must be one real directory")
    if hasattr(os, "getuid") and metadata.st_uid != os.getuid():
        raise PrivateReviewError("private review directory is not owned by the current user")
    if stat.S_IMODE(metadata.st_mode) & 0o022:
        raise PrivateReviewError("private review directory is group/world writable")


def _read_key(path: Path) -> bytes:
    nofollow = getattr(os, "O_NOFOLLOW", None)
    if nofollow is None:
        raise PrivateReviewError("private review key custody requires O_NOFOLLOW support")
    try:
        descriptor = os.open(path, os.O_RDONLY | nofollow | getattr(os, "O_CLOEXEC", 0))
    except OSError as error:
        raise PrivateReviewError("private review key is unavailable or unsafe") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise PrivateReviewError("private review key is not a regular file")
        if hasattr(os, "getuid") and before.st_uid != os.getuid():
            raise PrivateReviewError("private review key is not owned by the current user")
        if before.st_nlink != 1:
            raise PrivateReviewError("private review key has an unexpected hard-link alias")
        if stat.S_IMODE(before.st_mode) & 0o077:
            raise PrivateReviewError("private review key permissions are too broad")
        key = b""
        while len(key) <= KEY_BYTES:
            chunk = os.read(descriptor, KEY_BYTES + 1 - len(key))
            if not chunk:
                break
            key += chunk
        after = os.fstat(descriptor)
        try:
            pathname = path.lstat()
        except OSError as error:
            raise PrivateReviewError("private review key pathname changed during custody") from error
        if (
            _stat_identity(before) != _stat_identity(after)
            or stat.S_ISLNK(pathname.st_mode)
            or _stat_identity(pathname) != _stat_identity(after)
        ):
            raise PrivateReviewError("private review key changed while it was read")
        if len(key) != KEY_BYTES:
            raise PrivateReviewError("private review key has an invalid length")
        return key
    finally:
        os.close(descriptor)


def _write_new_key(path: Path) -> bytes:
    _require_private_parent(path)
    key = os.urandom(KEY_BYTES)
    temporary_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb",
            dir=path.parent,
            prefix=".nembra-private-review-key.",
            delete=False,
        ) as handle:
            temporary_name = handle.name
            os.chmod(temporary_name, 0o600)
            handle.write(key)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, path)
        temporary_name = None
        os.chmod(path, 0o600)
        return _read_key(path)
    except OSError as error:
        raise PrivateReviewError("private review key could not be published") from error
    finally:
        if temporary_name is not None:
            try:
                os.unlink(temporary_name)
            except FileNotFoundError:
                pass


def _canonical_record_bytes(record: dict[str, str]) -> bytes:
    try:
        return provenance._record_text(record).encode("utf-8")
    except (AttributeError, provenance.ProvenanceError) as error:
        raise PrivateReviewError("private provenance record cannot be canonicalized") from error


def commitment(record: dict[str, str], key: bytes) -> str:
    if len(key) != KEY_BYTES:
        raise PrivateReviewError("private review key has an invalid length")
    return hmac.new(key, DOMAIN + _canonical_record_bytes(record), hashlib.sha256).hexdigest()


def _accepted_commitment(value: str) -> str:
    if len(value) != 64 or any(character not in "0123456789abcdef" for character in value):
        raise PrivateReviewError("accepted private-input commitment must be canonical lowercase SHA-256")
    return value


def create_review(
    *,
    record_path: Path,
    key_path: Path,
    current: dict[str, str],
) -> str:
    """Publish one new local witness and return only its opaque external token."""
    if record_path.parent != key_path.parent:
        raise PrivateReviewError("private review record and key must share one protected directory")
    _require_private_parent(record_path)
    provenance.write_record(record_path, current)
    key = _write_new_key(key_path)
    # Re-read the record after key publication. A partial/crashed or concurrent
    # review must fail closed rather than emit authority for mixed generations.
    provenance.verify_record(record_path, current)
    return commitment(provenance.read_record(record_path), key)


def verify_review_paths(
    *,
    record_path: Path,
    key_path: Path,
    accepted: str,
    lockfile: Path,
    security_podspec: Path,
    security_build: Path,
    identity_podspec: Path,
    identity_sources: Path,
) -> str:
    """Verify accepted commitment with generation brackets around all reads."""
    paths = {
        "lockfile": lockfile,
        "security_podspec": security_podspec,
        "security_build": security_build,
        "identity_podspec": identity_podspec,
        "identity_sources": identity_sources,
    }
    before = provenance._private_input_record_generation_snapshot(**paths)
    current = provenance.build_record(**paths)
    accepted_value = _accepted_commitment(accepted)
    provenance.verify_record(record_path, current)
    recorded = provenance.read_record(record_path)
    key = _read_key(key_path)
    observed = commitment(recorded, key)
    if not hmac.compare_digest(observed, accepted_value):
        raise PrivateReviewError(
            "private Tuya build inputs do not match the externally accepted review commitment"
        )
    after = provenance._private_input_record_generation_snapshot(**paths)
    if after != before:
        raise PrivateReviewError(
            "private Tuya build inputs changed while external review authority was rebound"
        )
    return observed


def _paths(arguments: argparse.Namespace) -> dict[str, Path]:
    return {
        "lockfile": Path(arguments.lockfile),
        "security_podspec": Path(arguments.security_podspec),
        "security_build": Path(arguments.security_build),
        "identity_podspec": Path(arguments.identity_podspec),
        "identity_sources": Path(arguments.identity_sources),
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Nembra Capture opaque private-input review authority")
    parser.add_argument("mode", choices=("review", "verify"))
    parser.add_argument("--lockfile", required=True)
    parser.add_argument("--security-podspec", required=True)
    parser.add_argument("--security-build", required=True)
    parser.add_argument("--identity-podspec", required=True)
    parser.add_argument("--identity-sources", required=True)
    parser.add_argument("--record", required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--accepted-commitment")
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    arguments = _parser().parse_args(argv)
    paths = _paths(arguments)
    record_path = Path(arguments.record)
    key_path = Path(arguments.key)
    try:
        if arguments.mode == "review":
            if arguments.accepted_commitment is not None:
                raise PrivateReviewError("review mode does not accept preexisting authority")
            current = provenance.build_record(**paths)
            value = create_review(record_path=record_path, key_path=key_path, current=current)
            print(value)
        else:
            if arguments.accepted_commitment is None:
                raise PrivateReviewError("verify mode requires --accepted-commitment")
            value = verify_review_paths(
                record_path=record_path,
                key_path=key_path,
                accepted=arguments.accepted_commitment,
                **paths,
            )
            print(value)
    except (OSError, provenance.ProvenanceError, PrivateReviewError) as error:
        print(f"ERROR: {error}", file=os.sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

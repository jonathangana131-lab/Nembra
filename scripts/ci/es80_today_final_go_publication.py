#!/usr/bin/env python3
"""Failure-atomic publication for an already-validated external Final GO record.

This module owns only durable file publication. It does not decide GO, validate Capture evidence,
install an IPA, or authorize physical Experiment One. A failed invocation must never leave a
consumable authoritative GO pathname when the module can prove the bytes are the ones it published.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import secrets
import stat
import tempfile
from typing import Callable


class FinalGoPublicationError(RuntimeError):
    pass


def _sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _fsync_directory(parent: Path) -> None:
    directory_fd = os.open(parent, os.O_RDONLY)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)


def _regular(path: Path, label: str) -> bytes:
    try:
        metadata = path.lstat()
    except FileNotFoundError as error:
        raise FinalGoPublicationError(f"{label} is missing") from error
    if not stat.S_ISREG(metadata.st_mode) or path.is_symlink():
        raise FinalGoPublicationError(f"{label} is not a regular file")
    return path.read_bytes()


def _publish_file_no_replace(source: Path, destination: Path) -> None:
    try:
        os.link(source, destination, follow_symlinks=False)
    except FileExistsError as error:
        raise FinalGoPublicationError(f"output already exists: {destination}") from error
    source.unlink()


def _same_regular_inode(identity: os.stat_result, path: Path) -> bool:
    """Return true only when `path` is still the exact staged inode we created."""
    try:
        current = path.lstat()
    except FileNotFoundError:
        return False
    return stat.S_ISREG(current.st_mode) and os.path.samestat(identity, current)


def _retract_published_record(output: Path, raw: bytes) -> None:
    if not (output.exists() or output.is_symlink()):
        _fsync_directory(output.parent)
        return
    published = _regular(output, "failed published Final GO record")
    if published != raw:
        raise FinalGoPublicationError(
            "post-publication failure left changed destination bytes; refusing to delete unknown data"
        )
    output.unlink()
    _fsync_directory(output.parent)
    if output.exists() or output.is_symlink():
        raise FinalGoPublicationError(
            "post-publication rollback did not remove the authoritative destination"
        )


def _quarantine_published_record(output: Path, raw: bytes) -> Path | None:
    if not (output.exists() or output.is_symlink()):
        _fsync_directory(output.parent)
        return None
    published = _regular(output, "ambiguous published Final GO record")
    if published != raw:
        raise FinalGoPublicationError(
            "ambiguous Final GO destination bytes changed before quarantine"
        )
    quarantine = output.parent / (
        f".{output.name}.QUARANTINED-NO-GO.{os.getpid()}.{secrets.token_hex(8)}"
    )
    _publish_file_no_replace(output, quarantine)
    _fsync_directory(output.parent)
    if output.exists() or output.is_symlink():
        raise FinalGoPublicationError(
            "quarantine move did not remove the authoritative Final GO destination"
        )
    return quarantine


def publish_record_no_replace(
    output_path: Path,
    raw: bytes,
    *,
    publisher: Callable[[Path, Path], None] = _publish_file_no_replace,
) -> str:
    """Durably publish exact bytes or fail with the GO pathname non-authoritative.

    Publication is no-replace. A post-publication failure first attempts exact-byte rollback. If ordinary
    rollback cannot be proven, the exact bytes are moved to a non-authoritative quarantine pathname
    when possible. If neither cleanup path can be proven, the error explicitly reports AMBIGUOUS
    NO-GO and callers must not consume the destination.

    The staged inode identity is retained across the publisher call. This matters because a no-replace
    publisher can create the destination and then fail before returning (for example, while unlinking
    the staging pathname). In that case a callback-return Boolean is insufficient; matching inode
    identity proves that the destination is our staged authority and enables fail-closed cleanup.
    """
    if not raw:
        raise FinalGoPublicationError("Final GO record bytes must not be empty")

    output = output_path.expanduser()
    output.parent.mkdir(parents=True, exist_ok=True)
    parent = output.parent.resolve(strict=True)
    output = parent / output.name
    if output.exists() or output.is_symlink():
        raise FinalGoPublicationError(f"output already exists: {output}")

    fd = -1
    staging: Path | None = None
    staged_identity: os.stat_result | None = None
    published = False

    def cleanup_staging_best_effort() -> None:
        if staging is None:
            return
        try:
            staging.unlink(missing_ok=True)
        except OSError:
            pass

    try:
        fd, staging_name = tempfile.mkstemp(
            prefix=f".{output.name}.", suffix=".staging", dir=parent
        )
        staging = Path(staging_name)
        os.fchmod(fd, 0o600)
        offset = 0
        while offset < len(raw):
            written = os.write(fd, raw[offset:])
            if written <= 0:
                raise OSError("short write while staging Final GO record")
            offset += written
        os.fsync(fd)
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size != len(raw):
            raise FinalGoPublicationError(
                "staged Final GO record does not match expected byte count"
            )
        staged_identity = metadata
        os.close(fd)
        fd = -1

        if _regular(staging, "staged Final GO record") != raw:
            raise FinalGoPublicationError(
                "staged Final GO record bytes changed before publication"
            )

        publisher(staging, output)
        published = True
        # A custom no-replace publisher may preserve the source pathname. Once destination creation
        # returned successfully, removing that private staging name is part of the post-publish phase.
        if staging.exists() or staging.is_symlink():
            staging.unlink()
        staging = None
        _fsync_directory(parent)
        if _regular(output, "published Final GO record") != raw:
            raise FinalGoPublicationError(
                "published Final GO record bytes differ from staged authority"
            )
        return _sha(raw)
    except Exception as original_error:
        if fd >= 0:
            os.close(fd)

        if not published and staged_identity is not None:
            try:
                published = _same_regular_inode(staged_identity, output)
            except OSError:
                published = False

        if not published:
            cleanup_staging_best_effort()
            raise

        try:
            _retract_published_record(output, raw)
        except Exception as rollback_error:
            try:
                quarantine = _quarantine_published_record(output, raw)
            except Exception as quarantine_error:
                cleanup_staging_best_effort()
                raise FinalGoPublicationError(
                    "Final GO publication failed after rename and durable rollback/quarantine "
                    f"could not be proven. Treat {output} as AMBIGUOUS NO-GO and do not consume it. "
                    f"rollback={rollback_error}; quarantine={quarantine_error}"
                ) from quarantine_error
            cleanup_staging_best_effort()
            quarantine_note = (
                f"; bytes quarantined at {quarantine}" if quarantine is not None else ""
            )
            raise FinalGoPublicationError(
                "Final GO publication failed after rename; authoritative destination was "
                f"removed but ordinary rollback was not proven{quarantine_note}"
            ) from rollback_error

        cleanup_staging_best_effort()
        raise original_error

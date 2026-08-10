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


def _regular_metadata(path: Path, label: str) -> os.stat_result:
    try:
        metadata = path.lstat()
    except FileNotFoundError as error:
        raise FinalGoPublicationError(f"{label} is missing") from error
    if not stat.S_ISREG(metadata.st_mode) or path.is_symlink():
        raise FinalGoPublicationError(f"{label} is not a regular file")
    return metadata


def _regular(path: Path, label: str) -> bytes:
    _regular_metadata(path, label)
    return path.read_bytes()


def _require_publication_link_custody(staging: Path, output: Path) -> None:
    staging_metadata = _regular_metadata(staging, "staged Final GO record")
    output_metadata = _regular_metadata(output, "published Final GO record")
    if (staging_metadata.st_dev, staging_metadata.st_ino) != (
        output_metadata.st_dev,
        output_metadata.st_ino,
    ):
        raise FinalGoPublicationError(
            "published Final GO record does not reference the exact staged inode"
        )
    if staging_metadata.st_nlink != 2 or output_metadata.st_nlink != 2:
        raise FinalGoPublicationError(
            "published Final GO record has an unexpected hard-link alias before staging cleanup"
        )


def _require_single_link_output(output: Path) -> None:
    metadata = _regular_metadata(output, "published Final GO record")
    if metadata.st_nlink != 1:
        raise FinalGoPublicationError(
            "published Final GO record retains an unexpected hard-link alias"
        )


def _publish_file_no_replace(source: Path, destination: Path) -> None:
    """Create the destination exclusively.

    Staging cleanup deliberately remains with the caller. Keeping the publish primitive to one
    destination-creating operation means any later cleanup failure is unambiguously post-publication.
    """
    try:
        os.link(source, destination, follow_symlinks=False)
    except FileExistsError as error:
        raise FinalGoPublicationError(f"output already exists: {destination}") from error


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
    output.unlink()
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

    Publication is no-replace. Once the publisher is attempted, any destination that appears is
    treated as potentially authoritative: exact intended bytes are retracted (or quarantined if
    ordinary rollback cannot be proven), while changed/unknown bytes force explicit AMBIGUOUS NO-GO.

    The hard-link publisher must also preserve exact inode custody: before staging cleanup there may
    be exactly the staging and destination links, and after cleanup the destination must be the sole
    remaining link. This prevents a same-user alias created while the randomized staging pathname is
    visible from surviving a successful return and mutating the authoritative record later.

    Pre-publisher failures never touch an independently-created destination.
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
    publication_attempted = False
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
        os.close(fd)
        fd = -1

        if _regular(staging, "staged Final GO record") != raw:
            raise FinalGoPublicationError(
                "staged Final GO record bytes changed before publication"
            )

        publication_attempted = True
        publisher(staging, output)
        _require_publication_link_custody(staging, output)
        if _regular(output, "published Final GO record") != raw:
            raise FinalGoPublicationError(
                "published Final GO record bytes differ from staged authority"
            )

        # Destination existence is now established. Staging cleanup is deliberately outside the
        # publisher so a cleanup exception cannot be misclassified as a pre-publication failure.
        staging.unlink()
        staging = None
        _fsync_directory(parent)
        if _regular(output, "published Final GO record") != raw:
            raise FinalGoPublicationError(
                "published Final GO record bytes differ from staged authority"
            )
        _require_single_link_output(output)
        return _sha(raw)
    except Exception as original_error:
        if fd >= 0:
            os.close(fd)

        if publication_attempted and (output.exists() or output.is_symlink()):
            try:
                _retract_published_record(output, raw)
            except Exception as rollback_error:
                try:
                    quarantine = _quarantine_published_record(output, raw)
                except Exception as quarantine_error:
                    if staging is not None:
                        try:
                            staging.unlink(missing_ok=True)
                        except OSError:
                            pass
                    raise FinalGoPublicationError(
                        "Final GO publication failed after destination creation and durable "
                        f"rollback/quarantine could not be proven. Treat {output} as AMBIGUOUS "
                        "NO-GO and do not consume it. "
                        f"rollback={rollback_error}; quarantine={quarantine_error}"
                    ) from quarantine_error
                quarantine_note = (
                    f"; bytes quarantined at {quarantine}" if quarantine is not None else ""
                )
                if staging is not None:
                    try:
                        staging.unlink(missing_ok=True)
                    except OSError:
                        pass
                raise FinalGoPublicationError(
                    "Final GO publication failed after destination creation; authoritative "
                    f"destination was removed but ordinary rollback was not proven{quarantine_note}"
                ) from rollback_error

        if staging is not None:
            try:
                staging.unlink(missing_ok=True)
            except OSError:
                pass
        raise original_error

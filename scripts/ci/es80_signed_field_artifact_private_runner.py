#!/usr/bin/env python3
"""Read one private intended-device identifier without following symlinks."""

from __future__ import annotations

import os
import re
import stat
import sys
import tempfile
from pathlib import Path
from typing import Callable


class PrivateIdentifierError(RuntimeError):
    pass


def _stable_file_identity(
    metadata: os.stat_result,
) -> tuple[int, int, int, int, int, int, int, int, int]:
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


def _directory_identity(metadata: os.stat_result) -> tuple[int, int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_uid,
        metadata.st_gid,
        metadata.st_nlink,
    )


def _is_within(candidate: Path, root: Path) -> bool:
    try:
        candidate.relative_to(root)
        return True
    except ValueError:
        return False


def _split_absolute(path: Path) -> tuple[str, ...]:
    raw = os.fspath(path)
    if not raw.startswith(os.sep):
        raise PrivateIdentifierError("private intended-device path must be absolute")
    parts = Path(raw).parts[1:]
    if not parts or any(part in {"", ".", ".."} for part in parts):
        raise PrivateIdentifierError("private intended-device path is invalid")
    return tuple(parts)


def _open_directory_chain(path: Path, repository_identity: tuple[int, int]) -> int:
    """Open every parent from / with descriptor-relative no-follow traversal."""

    if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_DIRECTORY"):
        raise PrivateIdentifierError("required no-follow directory operations are unavailable")
    if os.open not in os.supports_dir_fd:
        raise PrivateIdentifierError("required descriptor-relative operations are unavailable")

    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(os.sep, flags)
    except OSError as error:
        raise PrivateIdentifierError("private intended-device root failed no-follow validation") from error

    try:
        root_metadata = os.fstat(descriptor)
        if (root_metadata.st_dev, root_metadata.st_ino) == repository_identity:
            raise PrivateIdentifierError("private intended-device path resolves inside the Nembra repository")
        for component in _split_absolute(path):
            try:
                next_descriptor = os.open(component, flags, dir_fd=descriptor)
            except OSError as error:
                raise PrivateIdentifierError(
                    "private intended-device ancestor failed no-follow validation"
                ) from error
            os.close(descriptor)
            descriptor = next_descriptor
            metadata = os.fstat(descriptor)
            if not stat.S_ISDIR(metadata.st_mode):
                raise PrivateIdentifierError("private intended-device ancestor is not a directory")
            if (metadata.st_dev, metadata.st_ino) == repository_identity:
                raise PrivateIdentifierError(
                    "private intended-device path resolves inside the Nembra repository"
                )
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def _read_private_identifier(
    path: Path,
    repository_root: Path,
    *,
    after_read_hook: Callable[[], None] | None = None,
) -> str:
    """Return a mode-0600, owner-only Apple device UDID outside the repository."""

    if not path.is_absolute():
        raise PrivateIdentifierError("private intended-device path must be absolute")
    repository_root = repository_root.resolve(strict=True)
    repository_metadata = repository_root.stat()
    if not stat.S_ISDIR(repository_metadata.st_mode):
        raise PrivateIdentifierError("Nembra repository root is unavailable")
    repository_identity = (repository_metadata.st_dev, repository_metadata.st_ino)
    lexical = Path(os.path.abspath(os.fspath(path)))
    if _is_within(lexical, repository_root):
        raise PrivateIdentifierError("private intended-device file must live outside the Nembra repository")
    try:
        resolved = lexical.resolve(strict=True)
    except OSError as error:
        raise PrivateIdentifierError("private intended-device input is unavailable") from error
    if _is_within(resolved, repository_root):
        raise PrivateIdentifierError("private intended-device path resolves inside the Nembra repository")

    parent = lexical.parent
    name = lexical.name
    if not name or name in {".", ".."}:
        raise PrivateIdentifierError("private intended-device filename is invalid")

    # Traverse from the filesystem root so a symlink in any ancestor is rejected,
    # then open the final subject relative to the validated parent descriptor.
    parent_descriptor = _open_directory_chain(parent, repository_identity)
    parent_identity = _directory_identity(os.fstat(parent_descriptor))
    nofollow = os.O_NOFOLLOW

    try:
        try:
            descriptor = os.open(
                name,
                os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | nofollow,
                dir_fd=parent_descriptor,
            )
        except OSError as error:
            raise PrivateIdentifierError(
                "private intended-device input failed no-follow validation"
            ) from error
        try:
            metadata = os.fstat(descriptor)
            if not stat.S_ISREG(metadata.st_mode):
                raise PrivateIdentifierError("private intended-device input is not a regular file")
            if metadata.st_mode & 0o077:
                raise PrivateIdentifierError("private intended-device input must not be group/world accessible")
            if stat.S_IMODE(metadata.st_mode) != 0o600:
                raise PrivateIdentifierError("private intended-device input must be mode 0600")
            if metadata.st_uid != os.geteuid():
                raise PrivateIdentifierError("private intended-device input must be owned by the current user")
            if metadata.st_nlink != 1:
                raise PrivateIdentifierError("private intended-device input must have exactly one hard link")
            if metadata.st_size <= 0 or metadata.st_size > 256:
                raise PrivateIdentifierError("private intended-device input size is invalid")

            chunks: list[bytes] = []
            remaining = 257
            while remaining > 0:
                chunk = os.read(descriptor, min(remaining, 256))
                if not chunk:
                    break
                chunks.append(chunk)
                remaining -= len(chunk)
            final_metadata = os.fstat(descriptor)
        finally:
            os.close(descriptor)

        if _stable_file_identity(final_metadata) != _stable_file_identity(metadata):
            raise PrivateIdentifierError("private intended-device input changed while being read")
        if sum(map(len, chunks)) != metadata.st_size:
            raise PrivateIdentifierError("private intended-device input size changed while being read")
        if after_read_hook is not None:
            after_read_hook()

        rebound_parent = _open_directory_chain(parent, repository_identity)
        try:
            if _directory_identity(os.fstat(rebound_parent)) != parent_identity:
                raise PrivateIdentifierError("private intended-device parent changed while being read")
            try:
                path_metadata = os.stat(name, dir_fd=rebound_parent, follow_symlinks=False)
            except OSError as error:
                raise PrivateIdentifierError(
                    "private intended-device input disappeared after read"
                ) from error
            if _stable_file_identity(path_metadata) != _stable_file_identity(metadata):
                raise PrivateIdentifierError("private intended-device path changed while being read")
        finally:
            os.close(rebound_parent)

        try:
            value = b"".join(chunks).decode("utf-8")
        except UnicodeDecodeError as error:
            raise PrivateIdentifierError("private intended-device input is not UTF-8") from error
        if value != value.strip():
            raise PrivateIdentifierError("private intended-device input must contain no surrounding whitespace")
        if re.fullmatch(r"(?:[0-9A-Fa-f]{40}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16})", value) is None:
            raise PrivateIdentifierError("private intended-device identifier is not a valid Apple UDID shape")
        if value in os.fspath(path):
            raise PrivateIdentifierError("private intended-device filename must not disclose its value")
        return value
    finally:
        os.close(parent_descriptor)


def read_private_identifier(path: Path, repository_root: Path) -> str:
    """Return a mode-0600, owner-only Apple device UDID outside the repository."""

    return _read_private_identifier(path, repository_root)


def self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="nembra-private-device-") as raw:
        # Darwin commonly exposes /var as a symlink to /private/var. The reader
        # intentionally requires the operator's private path to be canonical,
        # so exercise the self-test through the canonical temporary root too.
        root = Path(raw).resolve(strict=True)
        repository = root / "repo"
        private = root / "private"
        repository.mkdir()
        private.mkdir(mode=0o700)
        target = private / "intended-device"
        value = "00008110-0011223344556677"
        target.write_text(value, encoding="utf-8")
        target.chmod(0o600)
        if read_private_identifier(target, repository) != value:
            raise PrivateIdentifierError("private intended-device reader self-test mismatch")

        legacy_value = "0123456789abcdef0123456789ABCDEF01234567"
        target.write_text(legacy_value, encoding="utf-8")
        target.chmod(0o600)
        if read_private_identifier(target, repository) != legacy_value:
            raise PrivateIdentifierError("legacy Apple UDID reader self-test mismatch")

        target.write_text("01234567-0123456789abcdef-extra", encoding="utf-8")
        target.chmod(0o600)
        try:
            read_private_identifier(target, repository)
        except PrivateIdentifierError:
            pass
        else:
            raise PrivateIdentifierError("private intended-device reader accepted a malformed UDID")

        target.write_text(value, encoding="utf-8")
        target.chmod(0o600)
        try:
            _read_private_identifier(
                target,
                repository,
                after_read_hook=lambda: os.utime(
                    target,
                    ns=(target.stat().st_atime_ns, target.stat().st_mtime_ns - 1_000_000_000),
                ),
            )
        except PrivateIdentifierError:
            pass
        else:
            raise PrivateIdentifierError("private intended-device reader accepted mutation during read")

        real_parent = root / "real-private"
        real_parent.mkdir(mode=0o700)
        symlink_parent = root / "linked-private"
        symlink_parent.symlink_to(real_parent, target_is_directory=True)
        linked_target = real_parent / "intended-device"
        linked_target.write_text(value, encoding="utf-8")
        linked_target.chmod(0o600)
        try:
            read_private_identifier(symlink_parent / linked_target.name, repository)
        except PrivateIdentifierError:
            pass
        else:
            raise PrivateIdentifierError("private intended-device reader accepted a symlink ancestor")

        repository_target = repository / "intended-device"
        repository_target.write_text(value, encoding="utf-8")
        repository_target.chmod(0o600)
        repository_alias = private / "repository-alias"
        repository_alias.symlink_to(repository_target)
        try:
            read_private_identifier(repository_alias, repository)
        except PrivateIdentifierError:
            pass
        else:
            raise PrivateIdentifierError("private intended-device reader accepted a resolved in-repo target")

        target.chmod(0o644)
        try:
            read_private_identifier(target, repository)
        except PrivateIdentifierError:
            pass
        else:
            raise PrivateIdentifierError("private intended-device reader accepted broad permissions")


if __name__ == "__main__":
    if sys.argv == [sys.argv[0], "--self-test"]:
        self_test()
    else:
        raise SystemExit("usage: es80_signed_field_artifact_private_runner.py --self-test")

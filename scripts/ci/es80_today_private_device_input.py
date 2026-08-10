#!/usr/bin/env python3
"""Create the private TODAY intended-device input without pathname-retarget writes.

This operator helper is deliberately non-authorizing. It never grants Bluetooth activity,
physical Experiment One, or signing acceptance. It only creates the private UDID input that the
accepted preflight and frozen producer will independently re-open and validate.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import getpass
import os
from pathlib import Path
import stat
import sys
from typing import Callable

MAX_PRIVATE_IDENTIFIER_BYTES = 128
READY_MARKER = "CREATED_PRIVATE_INTENDED_DEVICE_INPUT"


class PrivateInputError(RuntimeError):
    pass


@dataclass(frozen=True)
class FileIdentity:
    device: int
    inode: int
    mode: int
    uid: int
    gid: int
    nlink: int
    size: int

    @classmethod
    def from_stat(cls, metadata: os.stat_result) -> "FileIdentity":
        return cls(
            metadata.st_dev,
            metadata.st_ino,
            metadata.st_mode,
            metadata.st_uid,
            metadata.st_gid,
            metadata.st_nlink,
            metadata.st_size,
        )


SecretProvider = Callable[[], str]
AfterCreateHook = Callable[[], None]


def _split_absolute(path: Path) -> tuple[str, ...]:
    raw = os.fspath(path)
    if not raw.startswith(os.sep):
        raise PrivateInputError("private-directory-must-be-absolute")
    parts = Path(raw).parts[1:]
    if not parts or any(part in ("", ".", "..") for part in parts):
        raise PrivateInputError("private-directory-path-invalid")
    return tuple(parts)


def _open_directory_chain(path: Path, *, create_leaf: bool) -> int:
    if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_DIRECTORY"):
        raise PrivateInputError("required-nofollow-directory-operations-unavailable")
    if os.open not in os.supports_dir_fd:
        raise PrivateInputError("required-descriptor-relative-operations-unavailable")

    parts = _split_absolute(path)
    cloexec = os.O_CLOEXEC if hasattr(os, "O_CLOEXEC") else 0
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | cloexec
    try:
        descriptor = os.open(os.sep, flags)
    except OSError as error:
        raise PrivateInputError("private-directory-root-open-failed") from error

    try:
        for index, part in enumerate(parts):
            is_leaf = index == len(parts) - 1
            try:
                next_descriptor = os.open(part, flags, dir_fd=descriptor)
            except FileNotFoundError as error:
                if not (create_leaf and is_leaf):
                    raise PrivateInputError("private-directory-component-missing") from error
                try:
                    os.mkdir(part, mode=0o700, dir_fd=descriptor)
                    next_descriptor = os.open(part, flags, dir_fd=descriptor)
                except OSError as create_error:
                    raise PrivateInputError("private-directory-create-failed") from create_error
            except OSError as error:
                raise PrivateInputError("private-directory-component-invalid") from error

            os.close(descriptor)
            descriptor = next_descriptor

        metadata = os.fstat(descriptor)
        if not stat.S_ISDIR(metadata.st_mode):
            raise PrivateInputError("private-directory-not-directory")
        if hasattr(os, "geteuid") and metadata.st_uid != os.geteuid():
            raise PrivateInputError("private-directory-owner-invalid")
        if stat.S_IMODE(metadata.st_mode) != 0o700:
            raise PrivateInputError("private-directory-mode-must-be-0700")
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


def _directory_contains_repository(private_dir: Path, repository_root: Path) -> bool:
    try:
        repository = repository_root.resolve(strict=True)
        repository_stat = os.stat(repository)
    except OSError as error:
        raise PrivateInputError("source-repository-unavailable") from error
    if not stat.S_ISDIR(repository_stat.st_mode):
        raise PrivateInputError("source-repository-unavailable")

    target_identity = (repository_stat.st_dev, repository_stat.st_ino)
    cloexec = os.O_CLOEXEC if hasattr(os, "O_CLOEXEC") else 0
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | cloexec
    descriptor = os.open(os.sep, flags)
    try:
        root_metadata = os.fstat(descriptor)
        if (root_metadata.st_dev, root_metadata.st_ino) == target_identity:
            return True
        for part in _split_absolute(private_dir):
            next_descriptor = os.open(part, flags, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = next_descriptor
            current = os.fstat(descriptor)
            if (current.st_dev, current.st_ino) == target_identity:
                return True
        return False
    except OSError as error:
        raise PrivateInputError("private-directory-component-invalid") from error
    finally:
        os.close(descriptor)


def _validated_secret(secret: str, output_path: Path) -> bytes:
    if not secret or secret != secret.strip():
        raise PrivateInputError("intended-device-value-has-surrounding-whitespace")
    if any(ord(character) < 33 or ord(character) == 127 for character in secret):
        raise PrivateInputError("intended-device-value-has-control-character")
    encoded = secret.encode("utf-8")
    if len(encoded) > MAX_PRIVATE_IDENTIFIER_BYTES:
        raise PrivateInputError("intended-device-value-too-large")
    if secret in os.fspath(output_path):
        raise PrivateInputError("intended-device-value-must-not-appear-in-path")
    return encoded


def _write_all(descriptor: int, payload: bytes) -> None:
    offset = 0
    while offset < len(payload):
        written = os.write(descriptor, payload[offset:])
        if written <= 0:
            raise PrivateInputError("private-intended-device-write-failed")
        offset += written


def create_private_input(
    private_directory: Path,
    repository_root: Path,
    filename: str,
    *,
    secret_provider: SecretProvider,
    after_create_hook: AfterCreateHook | None = None,
) -> Path:
    if not filename or filename in (".", "..") or os.sep in filename:
        raise PrivateInputError("private-filename-invalid")
    if os.altsep and os.altsep in filename:
        raise PrivateInputError("private-filename-invalid")

    private_directory = Path(os.path.abspath(os.fspath(private_directory)))
    output_path = private_directory / filename

    directory_descriptor = _open_directory_chain(private_directory, create_leaf=True)
    file_descriptor: int | None = None
    created_object_identity: tuple[int, int] | None = None
    final_identity: FileIdentity | None = None
    try:
        if _directory_contains_repository(private_directory, repository_root):
            raise PrivateInputError("private-directory-traverses-source-repository")

        secret = secret_provider()
        payload = _validated_secret(secret, output_path)
        secret = ""

        cloexec = os.O_CLOEXEC if hasattr(os, "O_CLOEXEC") else 0
        nofollow = os.O_NOFOLLOW if hasattr(os, "O_NOFOLLOW") else 0
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | nofollow | cloexec
        try:
            file_descriptor = os.open(filename, flags, 0o600, dir_fd=directory_descriptor)
        except FileExistsError as error:
            raise PrivateInputError("private-intended-device-path-already-exists") from error
        except OSError as error:
            raise PrivateInputError("private-intended-device-create-failed") from error

        # Capture the created filesystem object immediately after O_EXCL succeeds. Cleanup must not
        # depend on a later successful write/fsync/fstat: any failure after creation is responsible
        # for removing this exact object, but never a pathname replacement created by another actor.
        opened_metadata = os.fstat(file_descriptor)
        created_object_identity = (opened_metadata.st_dev, opened_metadata.st_ino)

        _write_all(file_descriptor, payload)
        os.fsync(file_descriptor)
        metadata = os.fstat(file_descriptor)
        final_identity = FileIdentity.from_stat(metadata)
        if not stat.S_ISREG(metadata.st_mode):
            raise PrivateInputError("private-intended-device-not-regular-file")
        if stat.S_IMODE(metadata.st_mode) != 0o600:
            raise PrivateInputError("private-intended-device-mode-must-be-0600")
        if metadata.st_nlink != 1:
            raise PrivateInputError("private-intended-device-link-count-invalid")
        if metadata.st_size != len(payload):
            raise PrivateInputError("private-intended-device-size-mismatch")
        if hasattr(os, "geteuid") and metadata.st_uid != os.geteuid():
            raise PrivateInputError("private-intended-device-owner-invalid")

        if after_create_hook is not None:
            after_create_hook()

        rebound_directory = _open_directory_chain(private_directory, create_leaf=False)
        try:
            original_directory = os.fstat(directory_descriptor)
            rebound_metadata = os.fstat(rebound_directory)
            if (original_directory.st_dev, original_directory.st_ino) != (
                rebound_metadata.st_dev,
                rebound_metadata.st_ino,
            ):
                raise PrivateInputError("private-directory-path-retargeted")

            read_flags = os.O_RDONLY | nofollow | cloexec
            try:
                rebound_file = os.open(filename, read_flags, dir_fd=rebound_directory)
            except OSError as error:
                raise PrivateInputError("private-intended-device-path-retargeted") from error
            try:
                rebound_identity = FileIdentity.from_stat(os.fstat(rebound_file))
                if rebound_identity != final_identity:
                    raise PrivateInputError("private-intended-device-path-retargeted")
                observed = os.read(rebound_file, MAX_PRIVATE_IDENTIFIER_BYTES + 1)
                if observed != payload:
                    raise PrivateInputError("private-intended-device-readback-mismatch")
            finally:
                os.close(rebound_file)
        finally:
            os.close(rebound_directory)

        os.fsync(directory_descriptor)
        return output_path
    except Exception:
        if created_object_identity is not None:
            try:
                current = os.stat(filename, dir_fd=directory_descriptor, follow_symlinks=False)
            except OSError:
                pass
            else:
                if (current.st_dev, current.st_ino) == created_object_identity:
                    try:
                        os.unlink(filename, dir_fd=directory_descriptor)
                    except OSError:
                        pass
                    else:
                        try:
                            os.fsync(directory_descriptor)
                        except OSError:
                            pass
        raise
    finally:
        if file_descriptor is not None:
            os.close(file_descriptor)
        os.close(directory_descriptor)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--private-directory", required=True, type=Path)
    parser.add_argument("--source-repo", required=True, type=Path)
    parser.add_argument("--filename", default="es80-intended-device.udid")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        create_private_input(
            args.private_directory,
            args.source_repo,
            args.filename,
            secret_provider=lambda: getpass.getpass("Intended iPhone UDID: "),
        )
    except PrivateInputError as error:
        print(f"NOT_READY: {error}", file=sys.stderr)
        return 2
    print(READY_MARKER)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations

import argparse
import getpass
import os
import stat
import sys
from pathlib import PurePosixPath

_MAX_IDENTIFIER_BYTES = 512


class PrivateInputError(RuntimeError):
    pass


def _directory_flags() -> int:
    flags = os.O_RDONLY | os.O_DIRECTORY
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    else:
        raise PrivateInputError("O_NOFOLLOW is required")
    return flags


def _file_flags() -> int:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    else:
        raise PrivateInputError("O_NOFOLLOW is required")
    return flags


def _validate_identifier(value: str) -> bytes:
    if not value or value != value.strip():
        raise PrivateInputError("intended-device identifier must be nonempty with no surrounding whitespace")
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in value):
        raise PrivateInputError("intended-device identifier contains a control character")
    encoded = value.encode("utf-8")
    if len(encoded) > _MAX_IDENTIFIER_BYTES:
        raise PrivateInputError("intended-device identifier is unexpectedly large")
    return encoded


def _open_parent_directory(output_path: str) -> tuple[int, str]:
    pure = PurePosixPath(output_path)
    if not pure.is_absolute():
        raise PrivateInputError("output path must be absolute")
    if pure.name in ("", ".", ".."):
        raise PrivateInputError("output path must name a file")

    components = pure.parts[1:-1]
    directory_fd = os.open("/", _directory_flags())
    try:
        for component in components:
            if component in ("", ".", ".."):
                raise PrivateInputError("output path contains an invalid component")
            next_fd = os.open(component, _directory_flags(), dir_fd=directory_fd)
            os.close(directory_fd)
            directory_fd = next_fd
        return directory_fd, pure.name
    except Exception:
        os.close(directory_fd)
        raise


def create_private_input(output_path: str, identifier: str) -> None:
    payload = _validate_identifier(identifier)
    parent_fd, filename = _open_parent_directory(output_path)
    file_fd: int | None = None
    try:
        parent_stat = os.fstat(parent_fd)
        if parent_stat.st_uid != os.getuid():
            raise PrivateInputError("output parent is not owned by the current user")
        if parent_stat.st_mode & 0o077:
            raise PrivateInputError("output parent must not be group/world accessible")

        file_fd = os.open(filename, _file_flags(), 0o600, dir_fd=parent_fd)
        written = 0
        while written < len(payload):
            count = os.write(file_fd, payload[written:])
            if count <= 0:
                raise PrivateInputError("short write while creating intended-device input")
            written += count
        os.fsync(file_fd)

        result = os.fstat(file_fd)
        if not stat.S_ISREG(result.st_mode):
            raise PrivateInputError("created intended-device input is not a regular file")
        if result.st_uid != os.getuid() or stat.S_IMODE(result.st_mode) != 0o600 or result.st_nlink != 1:
            raise PrivateInputError("created intended-device input has unsafe ownership, mode, or link count")
        if result.st_size != len(payload):
            raise PrivateInputError("created intended-device input size does not match exact identifier bytes")
        os.fsync(parent_fd)
    except Exception:
        if file_fd is not None:
            os.close(file_fd)
            file_fd = None
            try:
                os.unlink(filename, dir_fd=parent_fd)
            except OSError:
                pass
        raise
    finally:
        if file_fd is not None:
            os.close(file_fd)
        os.close(parent_fd)


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a private intended-device input using descriptor-bound no-follow custody."
    )
    parser.add_argument("--output-path", required=True, help="Fresh absolute file path in a private mode-0700 directory")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = _parse_args(argv)
    try:
        identifier = getpass.getpass("Intended iPhone UDID: ")
        create_private_input(args.output_path, identifier)
    except (PrivateInputError, OSError) as error:
        print(f"PRIVATE_INPUT_NOT_CREATED: {error}", file=sys.stderr)
        return 2
    finally:
        try:
            del identifier
        except UnboundLocalError:
            pass
    print("PRIVATE_INPUT_CREATED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Snapshot and verify exact local-only Tuya inputs for the Capture field build.

The record contains only cryptographic fingerprints and reviewed public version
labels. It never serializes AppKey/AppSecret, SDK bytes, device identifiers, or
other private material.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import stat
import tempfile
from pathlib import Path
from typing import Iterable

SCHEMA = "nembra-capture-tuya-dependencies-v2"
THING_SMART_HOME_KIT_VERSION = "7.8.0"
THING_SMART_BUSINESS_EXTENSION_KIT_VERSION = "7.8.0"
_RECORD_KEYS = (
    "schema",
    "podfile_lock_sha256",
    "thing_smart_home_kit",
    "thing_smart_business_extension_kit",
    "thing_smart_cryption_podspec_sha256",
    "thing_smart_cryption_build_tree_sha256",
    "private_identity_podspec_sha256",
    "private_identity_sources_tree_sha256",
)


class ProvenanceError(RuntimeError):
    pass


def _feed(digest: "hashlib._Hash", value: bytes) -> None:
    digest.update(len(value).to_bytes(8, "big"))
    digest.update(value)


def _require_regular_file(path: Path) -> os.stat_result:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise ProvenanceError(f"required private build input is unavailable: {path.name}") from error
    if not stat.S_ISREG(metadata.st_mode) or path.is_symlink():
        raise ProvenanceError(f"required private build input is not a regular file: {path.name}")
    return metadata


def _file_fingerprint(path: Path) -> str:
    metadata = _require_regular_file(path)
    digest = hashlib.sha256()
    _feed(digest, b"nembra-private-file-v1")
    _feed(digest, stat.S_IMODE(metadata.st_mode).to_bytes(4, "big"))
    _feed(digest, metadata.st_size.to_bytes(8, "big"))
    content = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                content.update(chunk)
    except OSError as error:
        raise ProvenanceError(f"private build input could not be read: {path.name}") from error
    _feed(digest, content.digest())
    return digest.hexdigest()


def _assert_internal_symlink(path: Path, root: Path) -> str:
    try:
        target = os.readlink(path)
        resolved = path.resolve(strict=True)
        resolved.relative_to(root.resolve(strict=True))
    except (OSError, ValueError) as error:
        raise ProvenanceError("private build input contains an escaping or broken symlink") from error
    return target


def _tree_fingerprint(root: Path) -> str:
    try:
        root_metadata = root.lstat()
    except OSError as error:
        raise ProvenanceError(f"required private build directory is unavailable: {root.name}") from error
    if root.is_symlink() or not stat.S_ISDIR(root_metadata.st_mode):
        raise ProvenanceError(f"required private build directory is not a real directory: {root.name}")

    entries: list[tuple[str, str, int, bytes]] = []
    root_resolved = root.resolve(strict=True)
    for current_text, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_text)
        kept_directories: list[str] = []
        for name in sorted(directory_names, key=os.fsencode):
            path = current / name
            relative = path.relative_to(root).as_posix()
            metadata = path.lstat()
            mode = stat.S_IMODE(metadata.st_mode)
            if stat.S_ISLNK(metadata.st_mode):
                target = _assert_internal_symlink(path, root_resolved)
                entries.append(("L", relative, mode, os.fsencode(target)))
            elif stat.S_ISDIR(metadata.st_mode):
                entries.append(("D", relative, mode, b""))
                kept_directories.append(name)
            else:
                raise ProvenanceError("private build tree contains an unsupported directory entry")
        directory_names[:] = kept_directories

        for name in sorted(file_names, key=os.fsencode):
            path = current / name
            relative = path.relative_to(root).as_posix()
            metadata = path.lstat()
            mode = stat.S_IMODE(metadata.st_mode)
            if stat.S_ISLNK(metadata.st_mode):
                target = _assert_internal_symlink(path, root_resolved)
                entries.append(("L", relative, mode, os.fsencode(target)))
            elif stat.S_ISREG(metadata.st_mode):
                entries.append(("F", relative, mode, bytes.fromhex(_file_fingerprint(path))))
            else:
                raise ProvenanceError("private build tree contains an unsupported file entry")

    digest = hashlib.sha256()
    _feed(digest, b"nembra-private-tree-v1")
    _feed(digest, stat.S_IMODE(root_metadata.st_mode).to_bytes(4, "big"))
    for kind, relative, mode, payload in sorted(entries, key=lambda item: os.fsencode(item[1])):
        _feed(digest, kind.encode("ascii"))
        _feed(digest, os.fsencode(relative))
        _feed(digest, mode.to_bytes(4, "big"))
        _feed(digest, payload)
    return digest.hexdigest()


def build_record(
    *,
    lockfile: Path,
    security_podspec: Path,
    security_build: Path,
    identity_podspec: Path,
    identity_sources: Path,
) -> dict[str, str]:
    return {
        "schema": SCHEMA,
        "podfile_lock_sha256": hashlib.sha256(lockfile.read_bytes()).hexdigest()
        if _require_regular_file(lockfile)
        else "",
        "thing_smart_home_kit": THING_SMART_HOME_KIT_VERSION,
        "thing_smart_business_extension_kit": THING_SMART_BUSINESS_EXTENSION_KIT_VERSION,
        "thing_smart_cryption_podspec_sha256": _file_fingerprint(security_podspec),
        "thing_smart_cryption_build_tree_sha256": _tree_fingerprint(security_build),
        "private_identity_podspec_sha256": _file_fingerprint(identity_podspec),
        "private_identity_sources_tree_sha256": _tree_fingerprint(identity_sources),
    }


def _record_text(record: dict[str, str]) -> str:
    if set(record) != set(_RECORD_KEYS):
        raise ProvenanceError("private provenance record has an unexpected schema")
    return "".join(f"{key}={record[key]}\n" for key in _RECORD_KEYS)


def write_record(path: Path, record: dict[str, str]) -> None:
    parent = path.parent
    try:
        parent_metadata = parent.lstat()
    except OSError as error:
        raise ProvenanceError("private provenance directory is unavailable") from error
    if parent.is_symlink() or not stat.S_ISDIR(parent_metadata.st_mode):
        raise ProvenanceError("private provenance directory must be a real directory")

    temporary_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=parent,
            prefix=".nembra-tuya-provenance.",
            delete=False,
        ) as handle:
            temporary_name = handle.name
            os.chmod(temporary_name, 0o600)
            handle.write(_record_text(record))
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, path)
        temporary_name = None
        os.chmod(path, 0o600)
    except OSError as error:
        raise ProvenanceError("private provenance record could not be written") from error
    finally:
        if temporary_name is not None:
            try:
                os.unlink(temporary_name)
            except FileNotFoundError:
                pass


def read_record(path: Path) -> dict[str, str]:
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise ProvenanceError("private provenance record is unavailable or unsafe") from error
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            raise ProvenanceError("private provenance record is not a regular file")
        if hasattr(os, "getuid") and metadata.st_uid != os.getuid():
            raise ProvenanceError("private provenance record is not owned by the current user")
        if stat.S_IMODE(metadata.st_mode) & 0o077:
            raise ProvenanceError("private provenance record permissions are too broad")
        chunks: list[bytes] = []
        while True:
            chunk = os.read(descriptor, 64 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
    finally:
        os.close(descriptor)

    try:
        text = b"".join(chunks).decode("utf-8")
    except UnicodeDecodeError as error:
        raise ProvenanceError("private provenance record is malformed") from error

    record: dict[str, str] = {}
    for line in text.splitlines():
        if not line or "=" not in line:
            raise ProvenanceError("private provenance record is malformed")
        key, value = line.split("=", 1)
        if key in record or not value:
            raise ProvenanceError("private provenance record is malformed")
        record[key] = value
    if tuple(record.keys()) != _RECORD_KEYS:
        raise ProvenanceError("private provenance record has an unexpected schema")
    return record


def verify_record(path: Path, current: dict[str, str]) -> None:
    recorded = read_record(path)
    if recorded != current:
        raise ProvenanceError(
            "private Tuya build inputs changed after bootstrap; rerun bootstrap and require a new field-build candidate"
        )


def _paths_from_arguments(arguments: argparse.Namespace) -> dict[str, Path]:
    return {
        "lockfile": Path(arguments.lockfile),
        "security_podspec": Path(arguments.security_podspec),
        "security_build": Path(arguments.security_build),
        "identity_podspec": Path(arguments.identity_podspec),
        "identity_sources": Path(arguments.identity_sources),
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Nembra Capture private Tuya input provenance")
    parser.add_argument("mode", choices=("snapshot", "verify"))
    parser.add_argument("--lockfile", required=True)
    parser.add_argument("--security-podspec", required=True)
    parser.add_argument("--security-build", required=True)
    parser.add_argument("--identity-podspec", required=True)
    parser.add_argument("--identity-sources", required=True)
    parser.add_argument("--record", required=True)
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    arguments = _parser().parse_args(argv)
    paths = _paths_from_arguments(arguments)
    try:
        current = build_record(**paths)
        record_path = Path(arguments.record)
        if arguments.mode == "snapshot":
            write_record(record_path, current)
            print("Private Tuya field-input provenance snapshot recorded.")
        else:
            verify_record(record_path, current)
            print("Private Tuya field-input provenance matched.")
    except (OSError, ProvenanceError) as error:
        print(f"ERROR: {error}", file=os.sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

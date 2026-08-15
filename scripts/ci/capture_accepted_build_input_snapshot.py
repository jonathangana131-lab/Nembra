#!/usr/bin/env python3
"""Build a compiler-input stage from exact Git + preaccepted generated inputs.

Tracked source is materialized from one exact Git commit, never copied from the
mutable checkout. Only the generated/private subjects required by the CocoaPods
field workspace are copied from the field tree, and those copied subjects are
admitted only when their canonical byte/topology manifest matches an independently
preaccepted SHA-256 digest.

Generated/private selectors are opened from one held repository root descriptor
with component-by-component no-follow semantics. Shared generated directories are
also generation-stamped while they are held so child-entry replacement cannot mix
multiple live directory generations into one accepted operation. The manifest
contains paths, file hashes/sizes, executable-bit state, and relative symlink
targets only. It never records private file contents.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import unicodedata
from typing import Iterable, Sequence

SCHEMA_VERSION = 1
GENERATED_SUBJECTS = (
    Path("Podfile.lock"),
    Path("NembraCapture.xcworkspace"),
    Path("Pods"),
    Path("LocalSecrets/TuyaSDK"),
    Path("LocalSecrets/TuyaRuntime"),
)
_GENERATED_SUBJECT_KINDS = {
    Path("Podfile.lock"): "file",
    Path("NembraCapture.xcworkspace"): "directory",
    Path("Pods"): "directory",
    Path("LocalSecrets/TuyaSDK"): "directory",
    Path("LocalSecrets/TuyaRuntime"): "directory",
}
_DIRECTORY_OPEN_FLAGS = (
    os.O_RDONLY
    | getattr(os, "O_DIRECTORY", 0)
    | getattr(os, "O_CLOEXEC", 0)
    | getattr(os, "O_NOFOLLOW", 0)
)
_FILE_OPEN_FLAGS = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)


class AcceptedBuildInputSnapshotError(RuntimeError):
    pass


def _absolute(path: Path) -> Path:
    if not path.is_absolute():
        raise AcceptedBuildInputSnapshotError(f"path must be absolute: {path}")
    if "\0" in str(path) or "\n" in str(path) or "\t" in str(path):
        raise AcceptedBuildInputSnapshotError("authority path contains a forbidden separator")
    return Path(os.path.abspath(str(path)))


def _safe_relative(relative: Path) -> Path:
    if relative.is_absolute() or not relative.parts:
        raise AcceptedBuildInputSnapshotError("build-input relative path is invalid")
    if any(part in ("", ".", "..") for part in relative.parts):
        raise AcceptedBuildInputSnapshotError(f"unsafe build-input path: {relative}")
    if any("\0" in part or "\n" in part or "\t" in part for part in relative.parts):
        raise AcceptedBuildInputSnapshotError("build-input path contains a forbidden separator")
    return relative


def _namespace_key(relative: Path) -> tuple[str, ...]:
    """Conservative case-insensitive/canonical namespace identity for field macOS."""

    _safe_relative(relative)
    return tuple(unicodedata.normalize("NFD", part).casefold() for part in relative.parts)


def _namespace_paths_overlap(first: Path, second: Path) -> bool:
    first_key = _namespace_key(first)
    second_key = _namespace_key(second)
    return (
        first_key[: len(second_key)] == second_key
        or second_key[: len(first_key)] == first_key
    )


def _assert_tracked_namespace_coherence(paths: Iterable[Path]) -> None:
    """Reject Git paths whose prefixes collapse in the field macOS namespace."""

    seen: dict[tuple[str, ...], tuple[str, ...]] = {}
    for relative in sorted(paths, key=lambda value: value.as_posix()):
        _safe_relative(relative)
        raw_parts = relative.parts
        key_parts = _namespace_key(relative)
        for length in range(1, len(raw_parts) + 1):
            raw_prefix = raw_parts[:length]
            key_prefix = key_parts[:length]
            previous = seen.get(key_prefix)
            if previous is not None and previous != raw_prefix:
                raise AcceptedBuildInputSnapshotError(
                    "accepted tracked source has namespace-equivalent paths: "
                    f"{'/'.join(previous)} vs {'/'.join(raw_prefix)}"
                )
            seen[key_prefix] = raw_prefix


def _git_environment() -> dict[str, str]:
    return {
        "HOME": "/var/empty",
        "PATH": "/usr/bin:/bin",
        "LANG": "C",
        "LC_ALL": "C",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
    }


def _run_git(repo: Path, arguments: Sequence[str], *, binary: bool = False) -> bytes | str:
    repo = _absolute(repo)
    completed = subprocess.run(
        ["/usr/bin/git", "-c", f"safe.directory={repo}", "-C", str(repo), *arguments],
        env=_git_environment(),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        text=not binary,
    )
    if completed.returncode != 0:
        stderr = completed.stderr.decode("utf-8", "replace") if binary else (completed.stderr or "")
        raise AcceptedBuildInputSnapshotError(
            "accepted Git read failed" + (f": {stderr.strip()[-800:]}" if stderr.strip() else "")
        )
    return bytes(completed.stdout) if binary else str(completed.stdout)


def _git_blob_oid(raw: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(raw)).encode("ascii") + b"\0" + raw).hexdigest()


def _git_tree_entries(repo: Path, source_sha: str) -> tuple[tuple[str, str, str, Path], ...]:
    if re.fullmatch(r"[0-9a-f]{40}", source_sha) is None:
        raise AcceptedBuildInputSnapshotError("accepted source SHA is malformed")
    raw = _run_git(repo, ["ls-tree", "-rz", "--full-tree", source_sha], binary=True)
    assert isinstance(raw, bytes)
    entries: list[tuple[str, str, str, Path]] = []
    for record in raw.split(b"\0"):
        if not record:
            continue
        try:
            header, path_raw = record.split(b"\t", 1)
            mode_raw, kind_raw, oid_raw = header.split(b" ", 2)
            relative = Path(path_raw.decode("utf-8", "strict"))
            mode = mode_raw.decode("ascii")
            kind = kind_raw.decode("ascii")
            oid = oid_raw.decode("ascii").lower()
        except (ValueError, UnicodeDecodeError) as error:
            raise AcceptedBuildInputSnapshotError("accepted Git tree entry is malformed") from error
        _safe_relative(relative)
        if kind not in ("blob", "commit") or re.fullmatch(r"[0-9a-f]{40}", oid) is None:
            raise AcceptedBuildInputSnapshotError(f"unsupported accepted Git entry: {relative}")
        if kind == "commit":
            raise AcceptedBuildInputSnapshotError(
                f"submodule/gitlink is not admitted into Capture build input: {relative}"
            )
        if mode not in ("100644", "100755", "120000"):
            raise AcceptedBuildInputSnapshotError(f"unsupported accepted Git mode {mode}: {relative}")
        entries.append((mode, kind, oid, relative))
    _assert_tracked_namespace_coherence(relative for _mode, _kind, _oid, relative in entries)
    return tuple(entries)


def _write_exact_file(path: Path, raw: bytes, executable: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags, 0o700 if executable else 0o600)
    try:
        view = memoryview(raw)
        while view:
            written = os.write(descriptor, view)
            if written <= 0:
                raise AcceptedBuildInputSnapshotError("tracked-source write made no progress")
            view = view[written:]
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    os.chmod(path, 0o755 if executable else 0o644)


def _validate_relative_symlink_target(link: Path, root: Path, target_text: str) -> None:
    target = Path(target_text)
    if target.is_absolute() or not target.parts:
        raise AcceptedBuildInputSnapshotError(f"absolute/empty symlink target is forbidden: {link}")
    lexical = Path(os.path.abspath(str(link.parent / target)))
    try:
        lexical.relative_to(root)
    except ValueError as error:
        raise AcceptedBuildInputSnapshotError(f"symlink escapes admitted build root: {link}") from error


def _validate_logical_symlink_target(relative: Path, target_text: str) -> None:
    target = Path(target_text)
    if target.is_absolute() or not target.parts:
        raise AcceptedBuildInputSnapshotError(
            f"absolute/empty symlink target is forbidden: {relative}"
        )
    stack = list(relative.parent.parts)
    for part in target.parts:
        if part in ("", "."):
            continue
        if part == "..":
            if not stack:
                raise AcceptedBuildInputSnapshotError(
                    f"symlink escapes admitted build root: {relative}"
                )
            stack.pop()
        else:
            if "\0" in part or "\n" in part or "\t" in part:
                raise AcceptedBuildInputSnapshotError(
                    f"unsafe symlink target component: {relative}"
                )
            stack.append(part)


def materialize_tracked_source(repo: Path, source_sha: str, destination: Path) -> set[Path]:
    repo = _absolute(repo)
    destination = _absolute(destination)
    if destination.exists():
        raise AcceptedBuildInputSnapshotError("tracked-source destination already exists")
    entries = _git_tree_entries(repo, source_sha)
    destination.mkdir(parents=True, mode=0o755)
    written: set[Path] = set()
    for mode, _kind, oid, relative in entries:
        if relative in written:
            raise AcceptedBuildInputSnapshotError(f"duplicate accepted Git path: {relative}")
        raw = _run_git(repo, ["cat-file", "blob", oid], binary=True)
        assert isinstance(raw, bytes)
        if _git_blob_oid(raw) != oid:
            raise AcceptedBuildInputSnapshotError(f"accepted Git blob identity mismatch: {relative}")
        target = destination / relative
        if mode == "120000":
            try:
                target_text = raw.decode("utf-8", "strict")
            except UnicodeDecodeError as error:
                raise AcceptedBuildInputSnapshotError(f"symlink target is not UTF-8: {relative}") from error
            _validate_relative_symlink_target(target, destination, target_text)
            target.parent.mkdir(parents=True, exist_ok=True)
            os.symlink(target_text, target)
        else:
            _write_exact_file(target, raw, executable=(mode == "100755"))
        written.add(relative)
    return written


def _same_object(first: os.stat_result, second: os.stat_result) -> bool:
    return (
        first.st_dev,
        first.st_ino,
        stat.S_IFMT(first.st_mode),
    ) == (
        second.st_dev,
        second.st_ino,
        stat.S_IFMT(second.st_mode),
    )


def _directory_generation(metadata: os.stat_result) -> tuple[int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        stat.S_IFMT(metadata.st_mode),
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _assert_directory_generation(
    descriptor: int,
    admitted: os.stat_result,
    relative: Path,
) -> None:
    current = os.fstat(descriptor)
    if (
        not stat.S_ISDIR(current.st_mode)
        or _directory_generation(current) != _directory_generation(admitted)
    ):
        raise AcceptedBuildInputSnapshotError(
            f"generated build-input directory membership changed during operation: {relative}"
        )


def _open_repository_root(root: Path) -> int:
    root = _absolute(root)
    try:
        before = root.lstat()
        descriptor = os.open(root, _DIRECTORY_OPEN_FLAGS)
    except OSError as error:
        raise AcceptedBuildInputSnapshotError(
            f"generated build-input root is not one stable real directory: {root}"
        ) from error
    try:
        opened = os.fstat(descriptor)
        after = root.lstat()
        if (
            not stat.S_ISDIR(before.st_mode)
            or stat.S_ISLNK(before.st_mode)
            or not stat.S_ISDIR(opened.st_mode)
            or not _same_object(before, opened)
            or not _same_object(opened, after)
        ):
            raise AcceptedBuildInputSnapshotError(
                f"generated build-input root changed identity while opening: {root}"
            )
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


def _open_directory_at(parent_fd: int, name: str, relative: Path) -> int:
    try:
        before = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        descriptor = os.open(name, _DIRECTORY_OPEN_FLAGS, dir_fd=parent_fd)
    except OSError as error:
        raise AcceptedBuildInputSnapshotError(
            f"generated build-input selector is not one real directory: {relative}"
        ) from error
    try:
        opened = os.fstat(descriptor)
        after = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        if (
            not stat.S_ISDIR(before.st_mode)
            or stat.S_ISLNK(before.st_mode)
            or not stat.S_ISDIR(opened.st_mode)
            or not _same_object(before, opened)
            or not _same_object(opened, after)
        ):
            raise AcceptedBuildInputSnapshotError(
                f"generated build-input directory changed identity while opening: {relative}"
            )
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


def _open_file_at(parent_fd: int, name: str, relative: Path) -> tuple[int, os.stat_result]:
    try:
        before = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        descriptor = os.open(name, _FILE_OPEN_FLAGS, dir_fd=parent_fd)
    except OSError as error:
        raise AcceptedBuildInputSnapshotError(
            f"generated build-input file is unavailable without symlink traversal: {relative}"
        ) from error
    try:
        opened = os.fstat(descriptor)
        after = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        if (
            not stat.S_ISREG(before.st_mode)
            or not stat.S_ISREG(opened.st_mode)
            or not _same_object(before, opened)
            or not _same_object(opened, after)
        ):
            raise AcceptedBuildInputSnapshotError(
                f"generated build-input file changed identity while opening: {relative}"
            )
        return descriptor, opened
    except Exception:
        os.close(descriptor)
        raise


def _open_subject(
    root_fd: int,
    subject: Path,
    directory_cache: dict[Path, tuple[int, os.stat_result]] | None = None,
) -> tuple[int, os.stat_result, str]:
    _safe_relative(subject)
    expected_kind = _GENERATED_SUBJECT_KINDS.get(subject)
    if expected_kind is None:
        raise AcceptedBuildInputSnapshotError(f"unrecognized generated subject: {subject}")
    current = os.dup(root_fd)
    try:
        for index, component in enumerate(subject.parts):
            relative = Path(*subject.parts[: index + 1])
            is_last = index == len(subject.parts) - 1
            if not is_last and directory_cache is not None and relative in directory_cache:
                cached_descriptor, admitted = directory_cache[relative]
                _assert_directory_generation(cached_descriptor, admitted, relative)
                os.close(current)
                current = os.dup(cached_descriptor)
                continue
            if is_last and expected_kind == "file":
                descriptor, metadata = _open_file_at(current, component, relative)
                os.close(current)
                return descriptor, metadata, "file"
            child = _open_directory_at(current, component, relative)
            if not is_last and directory_cache is not None:
                held = os.dup(child)
                directory_cache[relative] = (held, os.fstat(held))
            os.close(current)
            current = child
        metadata = os.fstat(current)
        return current, metadata, "directory"
    except Exception:
        try:
            os.close(current)
        except OSError:
            pass
        raise


def _close_directory_cache(
    directory_cache: dict[Path, tuple[int, os.stat_result]],
) -> None:
    for descriptor, _metadata in reversed(tuple(directory_cache.values())):
        try:
            os.close(descriptor)
        except OSError:
            pass
    directory_cache.clear()


def _safe_entry_name(name: str, parent: Path) -> None:
    if name in ("", ".", "..") or "\n" in name or "\t" in name or "\0" in name:
        raise AcceptedBuildInputSnapshotError(f"unsafe build-input entry name under {parent}")


def _hash_open_file(descriptor: int, relative: Path) -> tuple[str, int, os.stat_result]:
    digest = hashlib.sha256()
    size = 0
    before = os.fstat(descriptor)
    if not stat.S_ISREG(before.st_mode):
        raise AcceptedBuildInputSnapshotError(f"manifest file is not regular: {relative}")
    os.lseek(descriptor, 0, os.SEEK_SET)
    while True:
        block = os.read(descriptor, 1024 * 1024)
        if not block:
            break
        size += len(block)
        digest.update(block)
    after = os.fstat(descriptor)
    if (
        before.st_dev,
        before.st_ino,
        before.st_size,
        before.st_mtime_ns,
        before.st_ctime_ns,
    ) != (
        after.st_dev,
        after.st_ino,
        after.st_size,
        after.st_mtime_ns,
        after.st_ctime_ns,
    ):
        raise AcceptedBuildInputSnapshotError(f"manifest file changed while reading: {relative}")
    return digest.hexdigest(), size, after


def _manifest_directory(
    directory_fd: int,
    relative: Path,
    records: list[dict[str, object]],
    seen: set[Path],
) -> None:
    admitted_generation = os.fstat(directory_fd)
    try:
        names = sorted(os.listdir(directory_fd))
    except OSError as error:
        raise AcceptedBuildInputSnapshotError(
            f"could not enumerate build-input directory: {relative}"
        ) from error
    for name in names:
        _safe_entry_name(name, relative)
        child_relative = relative / name
        if child_relative in seen:
            raise AcceptedBuildInputSnapshotError(
                f"overlapping build-input subject: {child_relative}"
            )
        try:
            metadata = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        except OSError as error:
            raise AcceptedBuildInputSnapshotError(
                f"could not inspect generated build-input entry: {child_relative}"
            ) from error
        mode = metadata.st_mode
        record: dict[str, object] = {"path": child_relative.as_posix()}
        if stat.S_ISREG(mode):
            descriptor, opened = _open_file_at(directory_fd, name, child_relative)
            try:
                digest, size, after = _hash_open_file(descriptor, child_relative)
                if not _same_object(metadata, opened) or not _same_object(opened, after):
                    raise AcceptedBuildInputSnapshotError(
                        f"generated file selection changed identity: {child_relative}"
                    )
            finally:
                os.close(descriptor)
            record.update(
                type="file",
                sha256=digest,
                size=size,
                executable=bool(opened.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)),
            )
        elif stat.S_ISDIR(mode) and not stat.S_ISLNK(mode):
            child_fd = _open_directory_at(directory_fd, name, child_relative)
            try:
                opened = os.fstat(child_fd)
                if not _same_object(metadata, opened):
                    raise AcceptedBuildInputSnapshotError(
                        f"generated directory selection changed identity: {child_relative}"
                    )
                record.update(type="directory")
                seen.add(child_relative)
                records.append(record)
                _manifest_directory(child_fd, child_relative, records, seen)
                continue
            finally:
                os.close(child_fd)
        elif stat.S_ISLNK(mode):
            try:
                target_text = os.readlink(name, dir_fd=directory_fd)
                after = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
            except OSError as error:
                raise AcceptedBuildInputSnapshotError(
                    f"could not read generated symlink: {child_relative}"
                ) from error
            if not _same_object(metadata, after) or metadata.st_size != after.st_size:
                raise AcceptedBuildInputSnapshotError(
                    f"generated symlink changed identity while reading: {child_relative}"
                )
            _validate_logical_symlink_target(child_relative, target_text)
            record.update(type="symlink", target=target_text)
        else:
            raise AcceptedBuildInputSnapshotError(
                f"special build-input file is forbidden: {child_relative}"
            )
        seen.add(child_relative)
        records.append(record)
    _assert_directory_generation(directory_fd, admitted_generation, relative)


def canonical_generated_manifest(root: Path, source_sha: str) -> bytes:
    root = _absolute(root)
    if re.fullmatch(r"[0-9a-f]{40}", source_sha) is None:
        raise AcceptedBuildInputSnapshotError("accepted source SHA is malformed")
    records: list[dict[str, object]] = []
    seen: set[Path] = set()
    root_fd = _open_repository_root(root)
    directory_cache: dict[Path, tuple[int, os.stat_result]] = {}
    try:
        for subject in GENERATED_SUBJECTS:
            if subject in seen:
                raise AcceptedBuildInputSnapshotError(f"overlapping build-input subject: {subject}")
            descriptor, metadata, kind = _open_subject(root_fd, subject, directory_cache)
            try:
                record: dict[str, object] = {"path": subject.as_posix()}
                if kind == "file":
                    digest, size, after = _hash_open_file(descriptor, subject)
                    if not _same_object(metadata, after):
                        raise AcceptedBuildInputSnapshotError(
                            f"generated subject changed identity while reading: {subject}"
                        )
                    record.update(
                        type="file",
                        sha256=digest,
                        size=size,
                        executable=bool(metadata.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)),
                    )
                    seen.add(subject)
                    records.append(record)
                else:
                    record.update(type="directory")
                    seen.add(subject)
                    records.append(record)
                    _manifest_directory(descriptor, subject, records, seen)
            finally:
                os.close(descriptor)
    finally:
        _close_directory_cache(directory_cache)
        os.close(root_fd)
    payload = {
        "schemaVersion": SCHEMA_VERSION,
        "sourceSHA": source_sha,
        "generatedSubjects": [subject.as_posix() for subject in GENERATED_SUBJECTS],
        "entries": sorted(records, key=lambda value: str(value["path"])),
    }
    return (json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True) + "\n").encode("utf-8")


def generated_manifest_sha256(root: Path, source_sha: str) -> str:
    return hashlib.sha256(canonical_generated_manifest(root, source_sha)).hexdigest()


def _copy_open_file(
    source_fd: int,
    source_metadata: os.stat_result,
    destination: Path,
    relative: Path,
) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    out = os.open(destination, flags, 0o700 if (source_metadata.st_mode & 0o111) else 0o600)
    try:
        os.lseek(source_fd, 0, os.SEEK_SET)
        before = os.fstat(source_fd)
        while True:
            block = os.read(source_fd, 1024 * 1024)
            if not block:
                break
            view = memoryview(block)
            while view:
                written = os.write(out, view)
                if written <= 0:
                    raise AcceptedBuildInputSnapshotError("build-input copy made no progress")
                view = view[written:]
        os.fsync(out)
        after = os.fstat(source_fd)
        if (
            before.st_dev,
            before.st_ino,
            before.st_size,
            before.st_mtime_ns,
            before.st_ctime_ns,
        ) != (
            after.st_dev,
            after.st_ino,
            after.st_size,
            after.st_mtime_ns,
            after.st_ctime_ns,
        ):
            raise AcceptedBuildInputSnapshotError(
                f"build-input source changed while copying: {relative}"
            )
    finally:
        os.close(out)
    os.chmod(destination, 0o700 if (source_metadata.st_mode & 0o111) else 0o600)


def _copy_directory_fd(
    source_fd: int,
    destination_root: Path,
    relative: Path,
) -> None:
    admitted_generation = os.fstat(source_fd)
    destination = destination_root / relative
    destination.mkdir(mode=0o700, parents=True, exist_ok=False)
    os.chmod(destination, 0o700)
    try:
        names = sorted(os.listdir(source_fd))
    except OSError as error:
        raise AcceptedBuildInputSnapshotError(
            f"could not enumerate build-input directory during copy: {relative}"
        ) from error
    for name in names:
        _safe_entry_name(name, relative)
        child_relative = relative / name
        try:
            metadata = os.stat(name, dir_fd=source_fd, follow_symlinks=False)
        except OSError as error:
            raise AcceptedBuildInputSnapshotError(
                f"could not inspect build-input copy source: {child_relative}"
            ) from error
        if stat.S_ISREG(metadata.st_mode):
            descriptor, opened = _open_file_at(source_fd, name, child_relative)
            try:
                if not _same_object(metadata, opened):
                    raise AcceptedBuildInputSnapshotError(
                        f"copy source selection changed identity: {child_relative}"
                    )
                _copy_open_file(
                    descriptor,
                    opened,
                    destination_root / child_relative,
                    child_relative,
                )
            finally:
                os.close(descriptor)
        elif stat.S_ISDIR(metadata.st_mode) and not stat.S_ISLNK(metadata.st_mode):
            child_fd = _open_directory_at(source_fd, name, child_relative)
            try:
                if not _same_object(metadata, os.fstat(child_fd)):
                    raise AcceptedBuildInputSnapshotError(
                        f"copy directory selection changed identity: {child_relative}"
                    )
                _copy_directory_fd(child_fd, destination_root, child_relative)
            finally:
                os.close(child_fd)
        elif stat.S_ISLNK(metadata.st_mode):
            try:
                target_text = os.readlink(name, dir_fd=source_fd)
                after = os.stat(name, dir_fd=source_fd, follow_symlinks=False)
            except OSError as error:
                raise AcceptedBuildInputSnapshotError(
                    f"could not read build-input copy symlink: {child_relative}"
                ) from error
            if not _same_object(metadata, after) or metadata.st_size != after.st_size:
                raise AcceptedBuildInputSnapshotError(
                    f"copy symlink changed identity while reading: {child_relative}"
                )
            _validate_logical_symlink_target(child_relative, target_text)
            symlink_destination = destination_root / child_relative
            symlink_destination.parent.mkdir(parents=True, exist_ok=True)
            os.symlink(target_text, symlink_destination)
        else:
            raise AcceptedBuildInputSnapshotError(
                f"special build-input file is forbidden: {child_relative}"
            )
    _assert_directory_generation(source_fd, admitted_generation, relative)


def _copy_subject(source_root: Path, destination_root: Path, relative: Path) -> None:
    source_root = _absolute(source_root)
    destination_root = _absolute(destination_root)
    root_fd = _open_repository_root(source_root)
    try:
        descriptor, metadata, kind = _open_subject(root_fd, relative)
        try:
            if kind == "file":
                _copy_open_file(
                    descriptor,
                    metadata,
                    destination_root / relative,
                    relative,
                )
            else:
                _copy_directory_fd(descriptor, destination_root, relative)
        finally:
            os.close(descriptor)
    finally:
        os.close(root_fd)


def _copy_generated_subjects(source_root: Path, destination_root: Path) -> None:
    source_root = _absolute(source_root)
    destination_root = _absolute(destination_root)
    root_fd = _open_repository_root(source_root)
    directory_cache: dict[Path, tuple[int, os.stat_result]] = {}
    try:
        for subject in GENERATED_SUBJECTS:
            descriptor, metadata, kind = _open_subject(root_fd, subject, directory_cache)
            try:
                if kind == "file":
                    _copy_open_file(
                        descriptor,
                        metadata,
                        destination_root / subject,
                        subject,
                    )
                else:
                    _copy_directory_fd(descriptor, destination_root, subject)
            finally:
                os.close(descriptor)
    finally:
        _close_directory_cache(directory_cache)
        os.close(root_fd)


def stage_accepted_build_inputs(
    repo: Path,
    source_sha: str,
    destination: Path,
    expected_generated_manifest_sha256: str,
) -> str:
    repo = _absolute(repo)
    destination = _absolute(destination)
    if re.fullmatch(r"[0-9a-f]{64}", expected_generated_manifest_sha256) is None:
        raise AcceptedBuildInputSnapshotError("accepted generated-input manifest digest is malformed")
    entries = _git_tree_entries(repo, source_sha)
    tracked = {relative for _mode, _kind, _oid, relative in entries}
    for subject in GENERATED_SUBJECTS:
        if any(_namespace_paths_overlap(path, subject) for path in tracked):
            raise AcceptedBuildInputSnapshotError(
                f"generated build-input subject collides with accepted tracked source: {subject}"
            )
    materialize_tracked_source(repo, source_sha, destination)
    try:
        _copy_generated_subjects(repo, destination)
        actual = generated_manifest_sha256(destination, source_sha)
        if actual != expected_generated_manifest_sha256:
            raise AcceptedBuildInputSnapshotError(
                "copied generated/private compiler inputs do not match the preaccepted manifest digest"
            )
        return actual
    except Exception:
        shutil.rmtree(destination, ignore_errors=True)
        raise


def _parse(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Capture accepted build-input manifest/stage validation")
    sub = parser.add_subparsers(dest="mode", required=True)
    manifest = sub.add_parser("manifest")
    manifest.add_argument("--root", required=True)
    manifest.add_argument("--source-sha", required=True)
    stage = sub.add_parser("stage")
    stage.add_argument("--repo", required=True)
    stage.add_argument("--source-sha", required=True)
    stage.add_argument("--destination", required=True)
    stage.add_argument("--accepted-generated-manifest-sha256", required=True)
    return parser.parse_args(list(argv))


def main(argv: Sequence[str] | None = None) -> int:
    try:
        args = _parse(sys.argv[1:] if argv is None else argv)
        if args.mode == "manifest":
            sys.stdout.buffer.write(canonical_generated_manifest(Path(args.root), args.source_sha.lower()))
            return 0
        actual = stage_accepted_build_inputs(
            Path(args.repo),
            args.source_sha.lower(),
            Path(args.destination),
            args.accepted_generated_manifest_sha256.lower(),
        )
        print(actual)
        return 0
    except Exception as error:
        print(f"ERROR: accepted build-input snapshot failed: {error}", file=sys.stderr)
        return 78


if __name__ == "__main__":
    raise SystemExit(main())

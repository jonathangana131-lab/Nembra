#!/usr/bin/env python3
"""Build a compiler-input stage from exact Git + preaccepted generated inputs.

Tracked source is materialized from one exact Git commit, never copied from the
mutable checkout. Only the generated/private subjects required by the CocoaPods
field workspace are copied from the field tree, and those copied subjects are
admitted only when their canonical byte/topology manifest matches an independently
preaccepted SHA-256 digest.

The manifest contains paths, file hashes/sizes, executable-bit state, and relative
symlink targets only. It never records private file contents.
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


def materialize_tracked_source(repo: Path, source_sha: str, destination: Path) -> set[Path]:
    repo = _absolute(repo)
    destination = _absolute(destination)
    if destination.exists():
        raise AcceptedBuildInputSnapshotError("tracked-source destination already exists")
    destination.mkdir(parents=True, mode=0o755)
    written: set[Path] = set()
    for mode, _kind, oid, relative in _git_tree_entries(repo, source_sha):
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


def _open_root_directory(root: Path) -> int:
    root = _absolute(root)
    try:
        before = root.lstat()
    except OSError as error:
        raise AcceptedBuildInputSnapshotError(f"build-input root is unavailable: {root}") from error
    if not stat.S_ISDIR(before.st_mode) or stat.S_ISLNK(before.st_mode):
        raise AcceptedBuildInputSnapshotError(f"build-input root must be one real directory: {root}")
    flags = (
        os.O_RDONLY
        | getattr(os, "O_CLOEXEC", 0)
        | getattr(os, "O_NOFOLLOW", 0)
        | getattr(os, "O_DIRECTORY", 0)
    )
    try:
        descriptor = os.open(root, flags)
    except OSError as error:
        raise AcceptedBuildInputSnapshotError(
            f"could not open build-input root without following links: {root}"
        ) from error
    opened = os.fstat(descriptor)
    if (
        not stat.S_ISDIR(opened.st_mode)
        or (before.st_dev, before.st_ino, stat.S_IFMT(before.st_mode))
        != (opened.st_dev, opened.st_ino, stat.S_IFMT(opened.st_mode))
    ):
        os.close(descriptor)
        raise AcceptedBuildInputSnapshotError("build-input root changed during descriptor admission")
    return descriptor


def _open_generated_subject_set(root: Path) -> tuple[dict[Path, int], tuple[int, ...]]:
    root = _absolute(root)
    root_fd = _open_root_directory(root)
    owned: list[int] = [root_fd]
    directory_cache: dict[Path, int] = {Path(): root_fd}
    subjects: dict[Path, int] = {}
    expected_directories = {
        Path("NembraCapture.xcworkspace"),
        Path("Pods"),
        Path("LocalSecrets/TuyaSDK"),
        Path("LocalSecrets/TuyaRuntime"),
    }
    try:
        for subject in GENERATED_SUBJECTS:
            _safe_relative(subject)
            parent_fd = root_fd
            prefix = Path()
            for index, part in enumerate(subject.parts):
                prefix /= part
                final = index == len(subject.parts) - 1
                if not final and prefix in directory_cache:
                    parent_fd = directory_cache[prefix]
                    continue
                expect_directory = not final or subject in expected_directories
                flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
                if expect_directory:
                    flags |= getattr(os, "O_DIRECTORY", 0)
                try:
                    descriptor = os.open(part, flags, dir_fd=parent_fd)
                except OSError as error:
                    raise AcceptedBuildInputSnapshotError(
                        f"generated build-input selector is not one no-follow in-root object: {prefix}"
                    ) from error
                metadata = os.fstat(descriptor)
                valid_type = stat.S_ISDIR(metadata.st_mode) if expect_directory else stat.S_ISREG(metadata.st_mode)
                if not valid_type:
                    os.close(descriptor)
                    raise AcceptedBuildInputSnapshotError(
                        f"generated build-input selector has unexpected type: {prefix}"
                    )
                owned.append(descriptor)
                if final:
                    subjects[subject] = descriptor
                else:
                    directory_cache[prefix] = descriptor
                    parent_fd = descriptor
        return subjects, tuple(owned)
    except Exception:
        for descriptor in reversed(owned):
            try:
                os.close(descriptor)
            except OSError:
                pass
        raise


def _close_descriptors(descriptors: Sequence[int]) -> None:
    for descriptor in reversed(tuple(descriptors)):
        try:
            os.close(descriptor)
        except OSError:
            pass


def _safe_entry_name(name: str, parent: Path) -> None:
    if name in ("", ".", "..") or "\n" in name or "\t" in name or "\0" in name:
        raise AcceptedBuildInputSnapshotError(f"unsafe build-input entry name under {parent}")


def _opened_child(parent_fd: int, name: str, metadata: os.stat_result, relative: Path) -> int:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    if stat.S_ISDIR(metadata.st_mode):
        flags |= getattr(os, "O_DIRECTORY", 0)
    try:
        descriptor = os.open(name, flags, dir_fd=parent_fd)
    except OSError as error:
        raise AcceptedBuildInputSnapshotError(
            f"build-input object changed before descriptor admission: {relative}"
        ) from error
    opened = os.fstat(descriptor)
    if (
        opened.st_dev,
        opened.st_ino,
        stat.S_IFMT(opened.st_mode),
    ) != (
        metadata.st_dev,
        metadata.st_ino,
        stat.S_IFMT(metadata.st_mode),
    ):
        os.close(descriptor)
        raise AcceptedBuildInputSnapshotError(
            f"build-input object changed generation during admission: {relative}"
        )
    return descriptor


def _file_sha256_descriptor(descriptor: int, relative: Path) -> tuple[str, int, os.stat_result]:
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
    ) != (
        after.st_dev,
        after.st_ino,
        after.st_size,
        after.st_mtime_ns,
    ):
        raise AcceptedBuildInputSnapshotError(f"manifest file changed while reading: {relative}")
    return digest.hexdigest(), size, before


def _append_descriptor_records(
    root: Path,
    descriptor: int,
    relative: Path,
    records: list[dict[str, object]],
    seen: set[Path],
) -> None:
    if relative in seen:
        raise AcceptedBuildInputSnapshotError(f"overlapping build-input subject: {relative}")
    seen.add(relative)
    metadata = os.fstat(descriptor)
    mode = metadata.st_mode
    if stat.S_ISREG(mode):
        digest, size, before = _file_sha256_descriptor(descriptor, relative)
        records.append(
            {
                "path": relative.as_posix(),
                "type": "file",
                "sha256": digest,
                "size": size,
                "executable": bool(before.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)),
            }
        )
        return
    if not stat.S_ISDIR(mode):
        raise AcceptedBuildInputSnapshotError(f"generated subject root has forbidden type: {relative}")

    records.append({"path": relative.as_posix(), "type": "directory"})
    try:
        names = sorted(os.listdir(descriptor))
    except OSError as error:
        raise AcceptedBuildInputSnapshotError(
            f"could not enumerate build-input directory: {relative}"
        ) from error
    for name in names:
        _safe_entry_name(name, relative)
        child_relative = relative / name
        try:
            child_metadata = os.stat(name, dir_fd=descriptor, follow_symlinks=False)
        except OSError as error:
            raise AcceptedBuildInputSnapshotError(
                f"could not classify build-input entry: {child_relative}"
            ) from error
        if stat.S_ISLNK(child_metadata.st_mode):
            try:
                target_text = os.readlink(name, dir_fd=descriptor)
            except OSError as error:
                raise AcceptedBuildInputSnapshotError(
                    f"could not read build-input symlink: {child_relative}"
                ) from error
            _validate_relative_symlink_target(root / child_relative, root, target_text)
            if child_relative in seen:
                raise AcceptedBuildInputSnapshotError(
                    f"overlapping build-input subject: {child_relative}"
                )
            seen.add(child_relative)
            records.append(
                {"path": child_relative.as_posix(), "type": "symlink", "target": target_text}
            )
            continue
        if not (stat.S_ISREG(child_metadata.st_mode) or stat.S_ISDIR(child_metadata.st_mode)):
            raise AcceptedBuildInputSnapshotError(
                f"special build-input file is forbidden: {child_relative}"
            )
        child_fd = _opened_child(descriptor, name, child_metadata, child_relative)
        try:
            _append_descriptor_records(root, child_fd, child_relative, records, seen)
        finally:
            os.close(child_fd)


def canonical_generated_manifest(root: Path, source_sha: str) -> bytes:
    root = _absolute(root)
    if re.fullmatch(r"[0-9a-f]{40}", source_sha) is None:
        raise AcceptedBuildInputSnapshotError("accepted source SHA is malformed")
    records: list[dict[str, object]] = []
    seen: set[Path] = set()
    subjects, descriptors = _open_generated_subject_set(root)
    try:
        for subject in GENERATED_SUBJECTS:
            _append_descriptor_records(root, subjects[subject], subject, records, seen)
    finally:
        _close_descriptors(descriptors)
    payload = {
        "schemaVersion": SCHEMA_VERSION,
        "sourceSHA": source_sha,
        "generatedSubjects": [subject.as_posix() for subject in GENERATED_SUBJECTS],
        "entries": sorted(records, key=lambda value: str(value["path"])),
    }
    return (
        json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True) + "\n"
    ).encode("utf-8")


def generated_manifest_sha256(root: Path, source_sha: str) -> str:
    return hashlib.sha256(canonical_generated_manifest(root, source_sha)).hexdigest()

def _ensure_owner_only_parent(destination_root: Path, relative_parent: Path) -> None:
    current = destination_root
    for part in relative_parent.parts:
        current /= part
        if current.exists():
            metadata = current.lstat()
            if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
                raise AcceptedBuildInputSnapshotError(
                    f"copy destination ancestry changed type: {current}"
                )
            continue
        current.mkdir(mode=0o700)
        os.chmod(current, 0o700)


def _copy_opened_subject(
    source_root: Path,
    descriptor: int,
    destination_root: Path,
    relative: Path,
) -> None:
    destination = destination_root / relative
    metadata = os.fstat(descriptor)
    if stat.S_ISREG(metadata.st_mode):
        _ensure_owner_only_parent(destination_root, relative.parent)
        os.lseek(descriptor, 0, os.SEEK_SET)
        opened = os.fstat(descriptor)
        flags = (
            os.O_WRONLY
            | os.O_CREAT
            | os.O_EXCL
            | getattr(os, "O_CLOEXEC", 0)
            | getattr(os, "O_NOFOLLOW", 0)
        )
        out = os.open(destination, flags, 0o700 if (opened.st_mode & 0o111) else 0o600)
        try:
            while True:
                block = os.read(descriptor, 1024 * 1024)
                if not block:
                    break
                view = memoryview(block)
                while view:
                    written = os.write(out, view)
                    if written <= 0:
                        raise AcceptedBuildInputSnapshotError("build-input copy made no progress")
                    view = view[written:]
            os.fsync(out)
        finally:
            os.close(out)
        after = os.fstat(descriptor)
        if (
            opened.st_dev,
            opened.st_ino,
            opened.st_size,
            opened.st_mtime_ns,
        ) != (
            after.st_dev,
            after.st_ino,
            after.st_size,
            after.st_mtime_ns,
        ):
            raise AcceptedBuildInputSnapshotError(
                f"build-input source changed while copying: {relative}"
            )
        os.chmod(destination, 0o700 if (opened.st_mode & 0o111) else 0o600)
        return

    if not stat.S_ISDIR(metadata.st_mode):
        raise AcceptedBuildInputSnapshotError(
            f"generated subject root has forbidden type: {relative}"
        )
    _ensure_owner_only_parent(destination_root, relative.parent)
    destination.mkdir(mode=0o700, exist_ok=False)
    os.chmod(destination, 0o700)
    try:
        names = sorted(os.listdir(descriptor))
    except OSError as error:
        raise AcceptedBuildInputSnapshotError(
            f"could not enumerate build-input directory: {relative}"
        ) from error
    for name in names:
        _safe_entry_name(name, relative)
        child_relative = relative / name
        try:
            child_metadata = os.stat(name, dir_fd=descriptor, follow_symlinks=False)
        except OSError as error:
            raise AcceptedBuildInputSnapshotError(
                f"could not classify copy source: {child_relative}"
            ) from error
        if stat.S_ISLNK(child_metadata.st_mode):
            try:
                target_text = os.readlink(name, dir_fd=descriptor)
            except OSError as error:
                raise AcceptedBuildInputSnapshotError(
                    f"could not read copy-source symlink: {child_relative}"
                ) from error
            _validate_relative_symlink_target(
                source_root / child_relative, source_root, target_text
            )
            _ensure_owner_only_parent(destination_root, child_relative.parent)
            os.symlink(target_text, destination_root / child_relative)
            continue
        if not (stat.S_ISREG(child_metadata.st_mode) or stat.S_ISDIR(child_metadata.st_mode)):
            raise AcceptedBuildInputSnapshotError(
                f"special build-input file is forbidden: {child_relative}"
            )
        child_fd = _opened_child(descriptor, name, child_metadata, child_relative)
        try:
            _copy_opened_subject(source_root, child_fd, destination_root, child_relative)
        finally:
            os.close(child_fd)


def _copy_generated_subjects(source_root: Path, destination_root: Path) -> None:
    source_root = _absolute(source_root)
    destination_root = _absolute(destination_root)
    subjects, descriptors = _open_generated_subject_set(source_root)
    try:
        for subject in GENERATED_SUBJECTS:
            _copy_opened_subject(source_root, subjects[subject], destination_root, subject)
    finally:
        _close_descriptors(descriptors)

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
    tracked = {relative for _mode, _kind, _oid, relative in _git_tree_entries(repo, source_sha)}
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

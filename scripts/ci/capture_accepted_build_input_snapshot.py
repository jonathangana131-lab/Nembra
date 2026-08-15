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


def _iter_subject_entries(root: Path, subject: Path) -> Iterable[tuple[Path, os.stat_result]]:
    subject_path = root / subject
    try:
        metadata = subject_path.lstat()
    except OSError as error:
        raise AcceptedBuildInputSnapshotError(f"required build-input subject is unavailable: {subject}") from error
    yield subject, metadata
    if stat.S_ISDIR(metadata.st_mode) and not stat.S_ISLNK(metadata.st_mode):
        stack = [subject]
        while stack:
            current = stack.pop()
            try:
                names = sorted(os.listdir(root / current))
            except OSError as error:
                raise AcceptedBuildInputSnapshotError(f"could not enumerate build-input directory: {current}") from error
            directories: list[Path] = []
            for name in names:
                if name in ("", ".", "..") or "\n" in name or "\t" in name or "\0" in name:
                    raise AcceptedBuildInputSnapshotError(f"unsafe build-input entry name under {current}")
                relative = current / name
                metadata = (root / relative).lstat()
                yield relative, metadata
                if stat.S_ISDIR(metadata.st_mode) and not stat.S_ISLNK(metadata.st_mode):
                    directories.append(relative)
            stack.extend(reversed(directories))


def _file_sha256(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0))
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise AcceptedBuildInputSnapshotError(f"manifest file is not regular: {path}")
        while True:
            block = os.read(descriptor, 1024 * 1024)
            if not block:
                break
            size += len(block)
            digest.update(block)
        after = os.fstat(descriptor)
        if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (
            after.st_dev,
            after.st_ino,
            after.st_size,
            after.st_mtime_ns,
        ):
            raise AcceptedBuildInputSnapshotError(f"manifest file changed while reading: {path}")
    finally:
        os.close(descriptor)
    return digest.hexdigest(), size


def canonical_generated_manifest(root: Path, source_sha: str) -> bytes:
    root = _absolute(root)
    if re.fullmatch(r"[0-9a-f]{40}", source_sha) is None:
        raise AcceptedBuildInputSnapshotError("accepted source SHA is malformed")
    records: list[dict[str, object]] = []
    seen: set[Path] = set()
    for subject in GENERATED_SUBJECTS:
        _safe_relative(subject)
        for relative, metadata in _iter_subject_entries(root, subject):
            if relative in seen:
                raise AcceptedBuildInputSnapshotError(f"overlapping build-input subject: {relative}")
            seen.add(relative)
            mode = metadata.st_mode
            record: dict[str, object] = {"path": relative.as_posix()}
            if stat.S_ISREG(mode):
                digest, size = _file_sha256(root / relative)
                record.update(
                    type="file",
                    sha256=digest,
                    size=size,
                    executable=bool(mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)),
                )
            elif stat.S_ISDIR(mode):
                record.update(type="directory")
            elif stat.S_ISLNK(mode):
                target_text = os.readlink(root / relative)
                _validate_relative_symlink_target(root / relative, root, target_text)
                record.update(type="symlink", target=target_text)
            else:
                raise AcceptedBuildInputSnapshotError(f"special build-input file is forbidden: {relative}")
            records.append(record)
    payload = {
        "schemaVersion": SCHEMA_VERSION,
        "sourceSHA": source_sha,
        "generatedSubjects": [subject.as_posix() for subject in GENERATED_SUBJECTS],
        "entries": sorted(records, key=lambda value: str(value["path"])),
    }
    return (json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True) + "\n").encode("utf-8")


def generated_manifest_sha256(root: Path, source_sha: str) -> str:
    return hashlib.sha256(canonical_generated_manifest(root, source_sha)).hexdigest()


def _copy_subject(source_root: Path, destination_root: Path, relative: Path) -> None:
    source = source_root / relative
    destination = destination_root / relative
    metadata = source.lstat()
    if stat.S_ISREG(metadata.st_mode):
        destination.parent.mkdir(parents=True, exist_ok=True)
        descriptor = os.open(source, os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0))
        try:
            opened = os.fstat(descriptor)
            if not stat.S_ISREG(opened.st_mode):
                raise AcceptedBuildInputSnapshotError(f"copy source changed type: {relative}")
            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
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
            if (opened.st_dev, opened.st_ino, opened.st_size, opened.st_mtime_ns) != (
                after.st_dev,
                after.st_ino,
                after.st_size,
                after.st_mtime_ns,
            ):
                raise AcceptedBuildInputSnapshotError(f"build-input source changed while copying: {relative}")
            os.chmod(destination, 0o700 if (opened.st_mode & 0o111) else 0o600)
        finally:
            os.close(descriptor)
    elif stat.S_ISDIR(metadata.st_mode) and not stat.S_ISLNK(metadata.st_mode):
        destination.mkdir(mode=0o700, parents=True, exist_ok=False)
        os.chmod(destination, 0o700)
        for name in sorted(os.listdir(source)):
            if name in ("", ".", "..") or "\n" in name or "\t" in name or "\0" in name:
                raise AcceptedBuildInputSnapshotError(f"unsafe build-input entry name under {relative}")
            _copy_subject(source_root, destination_root, relative / name)
    elif stat.S_ISLNK(metadata.st_mode):
        target_text = os.readlink(source)
        _validate_relative_symlink_target(source, source_root, target_text)
        destination.parent.mkdir(parents=True, exist_ok=True)
        os.symlink(target_text, destination)
    else:
        raise AcceptedBuildInputSnapshotError(f"special build-input file is forbidden: {relative}")


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
        if any(
            path.parts[: len(subject.parts)] == subject.parts
            or subject.parts[: len(path.parts)] == path.parts
            for path in tracked
        ):
            raise AcceptedBuildInputSnapshotError(
                f"generated build-input subject collides with accepted tracked source: {subject}"
            )
    materialize_tracked_source(repo, source_sha, destination)
    try:
        for subject in GENERATED_SUBJECTS:
            _copy_subject(repo, destination, subject)
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

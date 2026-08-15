#!/usr/bin/env python3
"""Root-custody wrapper for an already-admitted Nembra Capture build-input tree.

This helper is intentionally macOS/root-only. It consumes the exact-Git +
preaccepted-generated-input admission primitive, creates the candidate inside a
fresh root-only container, strips inherited ACL authority, and leaves one
root-custodied build root for a later dedicated build identity to consume through
a separately accepted read lease.

It does not run Xcode, sign, install, touch a device, or create physical authority.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from types import ModuleType
from typing import Sequence


class AcceptedBuildRootCustodyError(RuntimeError):
    pass


def _load_snapshot_module() -> ModuleType:
    path = Path(__file__).with_name("capture_accepted_build_input_snapshot.py")
    spec = importlib.util.spec_from_file_location("nembra_capture_accepted_build_input_snapshot", path)
    if spec is None or spec.loader is None:
        raise AcceptedBuildRootCustodyError("accepted build-input admission helper is unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


snapshot = _load_snapshot_module()
DEFAULT_PARENT = Path("/private/tmp")
CONTAINER_PREFIX = "nembra-capture-accepted-build."


def _absolute(path: Path) -> Path:
    if not path.is_absolute():
        raise AcceptedBuildRootCustodyError(f"path must be absolute: {path}")
    if any(token in str(path) for token in ("\0", "\n", "\t")):
        raise AcceptedBuildRootCustodyError("custody path contains a forbidden separator")
    return Path(os.path.abspath(str(path)))


def _require_root_macos() -> None:
    if sys.platform != "darwin":
        raise AcceptedBuildRootCustodyError("accepted build-root custody requires macOS")
    if os.geteuid() != 0:
        raise AcceptedBuildRootCustodyError("accepted build-root custody requires root")


def _require_real_directory(path: Path, label: str) -> os.stat_result:
    path = _absolute(path)
    try:
        metadata = path.lstat()
    except OSError as error:
        raise AcceptedBuildRootCustodyError(f"{label} is unavailable: {path}") from error
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        raise AcceptedBuildRootCustodyError(f"{label} must be one real directory: {path}")
    return metadata


def _run(argv: Sequence[str]) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        list(argv),
        env={"PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or "").strip()
        raise AcceptedBuildRootCustodyError(
            f"custody command failed: {list(argv)!r}" + (f": {detail[-800:]}" if detail else "")
        )
    return completed


def _strip_acl(path: Path) -> None:
    _run(("/bin/chmod", "-N", str(path)))


def _assert_no_extended_acl(path: Path) -> None:
    output = _run(("/bin/ls", "-lde", str(path))).stdout.splitlines()
    if len(output) != 1:
        raise AcceptedBuildRootCustodyError(f"accepted build-root path carries extended ACL authority: {path}")


def _file_sha256(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags)
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise AcceptedBuildRootCustodyError(f"fingerprint subject is not regular: {path}")
        while True:
            block = os.read(descriptor, 1024 * 1024)
            if not block:
                break
            digest.update(block)
            size += len(block)
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
            raise AcceptedBuildRootCustodyError(f"fingerprint subject changed while reading: {path}")
    finally:
        os.close(descriptor)
    return digest.hexdigest(), size


def _tree_records(root: Path) -> tuple[dict[str, object], ...]:
    root = _absolute(root)
    root_metadata = _require_real_directory(root, "accepted build root")
    records: list[dict[str, object]] = [
        {
            "path": ".",
            "type": "directory",
            "mode": stat.S_IMODE(root_metadata.st_mode),
            "uid": root_metadata.st_uid,
            "gid": root_metadata.st_gid,
        }
    ]
    seen: set[Path] = set()
    for current_raw, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_raw)
        current_relative = current.relative_to(root)
        for name in sorted(list(directory_names)):
            candidate = current / name
            relative = current_relative / name
            metadata = candidate.lstat()
            if relative in seen:
                raise AcceptedBuildRootCustodyError(f"duplicate build-root entry: {relative}")
            seen.add(relative)
            if stat.S_ISLNK(metadata.st_mode):
                directory_names.remove(name)
                records.append(
                    {
                        "path": relative.as_posix(),
                        "type": "symlink",
                        "target": os.readlink(candidate),
                        "uid": metadata.st_uid,
                        "gid": metadata.st_gid,
                    }
                )
            elif stat.S_ISDIR(metadata.st_mode):
                records.append(
                    {
                        "path": relative.as_posix(),
                        "type": "directory",
                        "mode": stat.S_IMODE(metadata.st_mode),
                        "uid": metadata.st_uid,
                        "gid": metadata.st_gid,
                    }
                )
            else:
                raise AcceptedBuildRootCustodyError(f"unsupported directory entry in accepted root: {relative}")
        directory_names[:] = sorted(directory_names)
        for name in sorted(file_names):
            candidate = current / name
            relative = current_relative / name
            metadata = candidate.lstat()
            if relative in seen:
                raise AcceptedBuildRootCustodyError(f"duplicate build-root entry: {relative}")
            seen.add(relative)
            if stat.S_ISLNK(metadata.st_mode):
                records.append(
                    {
                        "path": relative.as_posix(),
                        "type": "symlink",
                        "target": os.readlink(candidate),
                        "uid": metadata.st_uid,
                        "gid": metadata.st_gid,
                    }
                )
            elif stat.S_ISREG(metadata.st_mode):
                digest, size = _file_sha256(candidate)
                records.append(
                    {
                        "path": relative.as_posix(),
                        "type": "file",
                        "sha256": digest,
                        "size": size,
                        "mode": stat.S_IMODE(metadata.st_mode),
                        "uid": metadata.st_uid,
                        "gid": metadata.st_gid,
                    }
                )
            else:
                raise AcceptedBuildRootCustodyError(f"special file in accepted build root: {relative}")
    return tuple(sorted(records, key=lambda value: str(value["path"])))


def accepted_build_root_fingerprint(root: Path) -> str:
    payload = json.dumps(
        _tree_records(root),
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True,
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _walk_custody_subjects(root: Path) -> tuple[tuple[Path, ...], tuple[Path, ...], tuple[Path, ...]]:
    directories: list[Path] = []
    files: list[Path] = []
    symlinks: list[Path] = []
    for current_raw, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_raw)
        metadata = current.lstat()
        if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            raise AcceptedBuildRootCustodyError(f"accepted build-root ancestry changed type: {current}")
        directories.append(current)
        for name in list(directory_names):
            candidate = current / name
            metadata = candidate.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                directory_names.remove(name)
                symlinks.append(candidate)
            elif not stat.S_ISDIR(metadata.st_mode):
                raise AcceptedBuildRootCustodyError(f"accepted build-root directory entry changed type: {candidate}")
        for name in file_names:
            candidate = current / name
            metadata = candidate.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                symlinks.append(candidate)
            elif stat.S_ISREG(metadata.st_mode):
                files.append(candidate)
            else:
                raise AcceptedBuildRootCustodyError(f"special file in accepted build root: {candidate}")
    return tuple(directories), tuple(files), tuple(symlinks)


def seal_accepted_build_root(root: Path) -> str:
    """Remove field authority while preserving admission-selected executable/read modes."""

    _require_root_macos()
    root = _absolute(root)
    directories, files, symlinks = _walk_custody_subjects(root)

    for path in files:
        metadata = path.lstat()
        if metadata.st_mode & 0o022:
            raise AcceptedBuildRootCustodyError(f"accepted build-root file is group/other writable: {path}")
        os.chown(path, 0, 0)
        _strip_acl(path)

    for path in symlinks:
        os.lchown(path, 0, 0)

    for path in sorted(directories, key=lambda item: len(item.parts), reverse=True):
        metadata = path.lstat()
        if metadata.st_mode & 0o022:
            raise AcceptedBuildRootCustodyError(f"accepted build-root directory is group/other writable: {path}")
        os.chown(path, 0, 0)
        _strip_acl(path)

    # The admitted tree becomes unreachable to the field identity. A later dedicated
    # build identity must receive explicitly bounded read/search authority.
    os.chmod(root, 0o700)

    for path in files:
        metadata = path.lstat()
        if metadata.st_uid != 0 or metadata.st_gid != 0 or metadata.st_mode & 0o022:
            raise AcceptedBuildRootCustodyError(f"accepted build-root file custody is not root-only: {path}")
        _assert_no_extended_acl(path)
    for path in symlinks:
        metadata = path.lstat()
        if metadata.st_uid != 0 or metadata.st_gid != 0:
            raise AcceptedBuildRootCustodyError(f"accepted build-root symlink custody is not root-owned: {path}")
    for path in directories:
        metadata = path.lstat()
        if metadata.st_uid != 0 or metadata.st_gid != 0 or metadata.st_mode & 0o022:
            raise AcceptedBuildRootCustodyError(f"accepted build-root directory custody is not root-only: {path}")
        _assert_no_extended_acl(path)
    if stat.S_IMODE(root.lstat().st_mode) != 0o700:
        raise AcceptedBuildRootCustodyError("accepted build-root root is not root:0700")

    return accepted_build_root_fingerprint(root)


def _prepare_container(parent: Path) -> Path:
    parent = _absolute(parent)
    parent_metadata = _require_real_directory(parent, "accepted build-root parent")
    parent_mode = stat.S_IMODE(parent_metadata.st_mode)
    if parent_metadata.st_uid != 0:
        raise AcceptedBuildRootCustodyError("accepted build-root parent must be root-owned")
    if parent_mode & 0o022 and not (parent_metadata.st_mode & stat.S_ISVTX):
        raise AcceptedBuildRootCustodyError(
            "writable accepted build-root parent must carry sticky-directory protection"
        )

    container = Path(tempfile.mkdtemp(prefix=CONTAINER_PREFIX, dir=str(parent)))
    try:
        os.chown(container, 0, 0)
        _strip_acl(container)
        os.chmod(container, 0o700)
        metadata = container.lstat()
        if metadata.st_uid != 0 or metadata.st_gid != 0 or stat.S_IMODE(metadata.st_mode) != 0o700:
            raise AcceptedBuildRootCustodyError("accepted build-root container custody is invalid")
        _assert_no_extended_acl(container)
        return container
    except Exception:
        shutil.rmtree(container, ignore_errors=True)
        raise


def create_accepted_build_root(
    repo: Path,
    source_sha: str,
    accepted_generated_manifest_sha256: str,
    *,
    parent: Path = DEFAULT_PARENT,
) -> tuple[Path, str, str]:
    _require_root_macos()
    repo = _absolute(repo)
    _require_real_directory(repo, "field repository")
    if re.fullmatch(r"[0-9a-f]{40}", source_sha) is None:
        raise AcceptedBuildRootCustodyError("accepted source SHA is malformed")
    if re.fullmatch(r"[0-9a-f]{64}", accepted_generated_manifest_sha256) is None:
        raise AcceptedBuildRootCustodyError("accepted generated manifest digest is malformed")

    container = _prepare_container(parent)
    accepted_root = container / "accepted-root"
    try:
        admitted_digest = snapshot.stage_accepted_build_inputs(
            repo,
            source_sha,
            accepted_root,
            accepted_generated_manifest_sha256,
        )
        if admitted_digest != accepted_generated_manifest_sha256:
            raise AcceptedBuildRootCustodyError("admission helper returned an unexpected generated manifest digest")
        fingerprint = seal_accepted_build_root(accepted_root)
        postseal_digest = snapshot.generated_manifest_sha256(accepted_root, source_sha)
        if postseal_digest != accepted_generated_manifest_sha256:
            raise AcceptedBuildRootCustodyError("root sealing changed accepted generated/private build-input identity")
        return accepted_root, fingerprint, admitted_digest
    except Exception:
        shutil.rmtree(container, ignore_errors=True)
        raise


def destroy_accepted_build_root(root: Path) -> None:
    _require_root_macos()
    root = _absolute(root)
    if root.name != "accepted-root" or not root.parent.name.startswith(CONTAINER_PREFIX):
        raise AcceptedBuildRootCustodyError("refusing to destroy a path outside accepted build-root custody")
    container = root.parent
    if container.parent != DEFAULT_PARENT:
        raise AcceptedBuildRootCustodyError("refusing to destroy accepted build-root outside /private/tmp")
    shutil.rmtree(container)


def _parse(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a root-custodied accepted Nembra Capture build root")
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--accepted-generated-manifest-sha256", required=True)
    return parser.parse_args(list(argv))


def main(argv: Sequence[str] | None = None) -> int:
    try:
        args = _parse(sys.argv[1:] if argv is None else argv)
        root, fingerprint, digest = create_accepted_build_root(
            args.repo,
            args.source_sha.lower(),
            args.accepted_generated_manifest_sha256.lower(),
        )
        print(f"{root}\t{fingerprint}\t{digest}")
        return 0
    except Exception as error:
        print(f"ERROR: accepted build-root custody failed: {error}", file=sys.stderr)
        return 78


if __name__ == "__main__":
    raise SystemExit(main())

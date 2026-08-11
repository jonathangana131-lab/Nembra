#!/usr/bin/env python3
"""Fingerprint CocoaPods-generated Capture build inputs without exposing their bytes.

This helper binds the generated build graph that sits between an accepted
Podfile.lock and xcodebuild. It fingerprints ignored generated inputs (Pods/ and
NembraCapture.xcworkspace/) as a finite pathname/metadata/byte snapshot.
Generated symlinks are fingerprinted as link objects, never followed during the
tree walk, and may resolve only inside the generated tree or the two separately
provenanced local Tuya roots used by this Capture Podfile.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import stat
from pathlib import Path
from typing import Iterable

SCHEMA = b"nembra-capture-cocoapods-generated-build-subject-v1"


class GeneratedBuildSubjectError(RuntimeError):
    pass


def _feed(digest: "hashlib._Hash", value: bytes) -> None:
    digest.update(len(value).to_bytes(8, "big"))
    digest.update(value)


def _identity(metadata: os.stat_result) -> tuple[int, ...]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_uid,
        metadata.st_gid,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _members(path: Path) -> tuple[str, ...]:
    try:
        return tuple(sorted(os.listdir(path), key=os.fsencode))
    except OSError as error:
        raise GeneratedBuildSubjectError(
            f"generated build directory changed while fingerprinting: {path}"
        ) from error


def _read_regular(path: Path, expected: tuple[int, ...]) -> bytes:
    nofollow = getattr(os, "O_NOFOLLOW", None)
    if nofollow is None:
        raise GeneratedBuildSubjectError("generated build admission requires O_NOFOLLOW support")
    flags = os.O_RDONLY | nofollow | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise GeneratedBuildSubjectError(
            f"generated build file could not be opened safely: {path}"
        ) from error
    try:
        before = os.fstat(descriptor)
        if _identity(before) != expected or not stat.S_ISREG(before.st_mode):
            raise GeneratedBuildSubjectError(
                f"generated build file changed before read custody: {path}"
            )
        digest = hashlib.sha256()
        bytes_read = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
            bytes_read += len(chunk)
        after = os.fstat(descriptor)
        if _identity(after) != expected or bytes_read != after.st_size:
            raise GeneratedBuildSubjectError(
                f"generated build file changed while fingerprinting: {path}"
            )
        current = path.lstat()
        if _identity(current) != expected or not stat.S_ISREG(current.st_mode):
            raise GeneratedBuildSubjectError(
                f"generated build file pathname changed while fingerprinting: {path}"
            )
        return digest.digest()
    finally:
        os.close(descriptor)


def _is_within(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def _authorized_symlink_target(
    path: Path,
    *,
    generated_root: Path,
    repository_root: Path,
) -> str:
    try:
        target_text = os.readlink(path)
        resolved = path.resolve(strict=True)
        generated_resolved = generated_root.resolve(strict=True)
    except OSError as error:
        raise GeneratedBuildSubjectError(
            f"generated build contains a broken or unreadable symlink: {path}"
        ) from error

    allowed_roots = [generated_resolved]
    # The only external local pods in the accepted Capture Podfile are these two
    # ignored Tuya roots. Their build-relevant bytes are independently bound and
    # watched by capture_tuya_private_input_provenance/build_guard. Reject any
    # generated link that points somewhere else instead of silently trusting a
    # mutable external pathname.
    for relative in ("LocalSecrets/TuyaSDK", "LocalSecrets/TuyaRuntime"):
        candidate = repository_root / relative
        try:
            allowed_roots.append(candidate.resolve(strict=True))
        except OSError:
            continue

    if not any(_is_within(resolved, allowed) for allowed in allowed_roots):
        raise GeneratedBuildSubjectError(
            f"generated CocoaPods symlink escapes accepted generated/private roots: {path}"
        )
    return target_text


def _tree_entries(
    root: Path,
    *,
    repository_root: Path,
) -> tuple[tuple[str, str, int, bytes], ...]:
    try:
        root_metadata = root.lstat()
    except OSError as error:
        raise GeneratedBuildSubjectError(
            f"required generated build directory is unavailable: {root}"
        ) from error
    if stat.S_ISLNK(root_metadata.st_mode) or not stat.S_ISDIR(root_metadata.st_mode):
        raise GeneratedBuildSubjectError(
            f"required generated build root is not a real directory: {root}"
        )

    states: list[tuple[Path, tuple[int, ...], str, str | None]] = [
        (root, _identity(root_metadata), "D", None)
    ]
    directory_members: dict[Path, tuple[str, ...]] = {}
    entries: list[tuple[str, str, int, bytes]] = []

    for current_text, directory_names, file_names in os.walk(
        root, topdown=True, followlinks=False
    ):
        current = Path(current_text)
        directory_members[current] = tuple(
            sorted((*directory_names, *file_names), key=os.fsencode)
        )
        kept_directories: list[str] = []

        for name in sorted(directory_names, key=os.fsencode):
            candidate = current / name
            relative = candidate.relative_to(root).as_posix()
            metadata = candidate.lstat()
            identity = _identity(metadata)
            mode = stat.S_IMODE(metadata.st_mode)
            if stat.S_ISLNK(metadata.st_mode):
                target = _authorized_symlink_target(
                    candidate,
                    generated_root=root,
                    repository_root=repository_root,
                )
                states.append((candidate, identity, "L", target))
                entries.append(("L", relative, mode, os.fsencode(target)))
            elif stat.S_ISDIR(metadata.st_mode):
                states.append((candidate, identity, "D", None))
                entries.append(("D", relative, mode, b""))
                kept_directories.append(name)
            else:
                raise GeneratedBuildSubjectError(
                    f"unsupported generated directory entry: {candidate}"
                )
        directory_names[:] = kept_directories

        for name in sorted(file_names, key=os.fsencode):
            candidate = current / name
            relative = candidate.relative_to(root).as_posix()
            metadata = candidate.lstat()
            identity = _identity(metadata)
            mode = stat.S_IMODE(metadata.st_mode)
            if stat.S_ISLNK(metadata.st_mode):
                target = _authorized_symlink_target(
                    candidate,
                    generated_root=root,
                    repository_root=repository_root,
                )
                states.append((candidate, identity, "L", target))
                entries.append(("L", relative, mode, os.fsencode(target)))
            elif stat.S_ISREG(metadata.st_mode):
                content_digest = _read_regular(candidate, identity)
                states.append((candidate, identity, "F", None))
                entries.append(("F", relative, mode, content_digest))
            else:
                raise GeneratedBuildSubjectError(
                    f"unsupported generated file entry: {candidate}"
                )

    for path, expected, kind, target in states:
        try:
            metadata = path.lstat()
        except OSError as error:
            raise GeneratedBuildSubjectError(
                f"generated build entry disappeared during final custody: {path}"
            ) from error
        if _identity(metadata) != expected:
            raise GeneratedBuildSubjectError(
                f"generated build entry changed during final custody: {path}"
            )
        if kind == "D" and not stat.S_ISDIR(metadata.st_mode):
            raise GeneratedBuildSubjectError(f"generated directory changed kind: {path}")
        if kind == "F" and not stat.S_ISREG(metadata.st_mode):
            raise GeneratedBuildSubjectError(f"generated file changed kind: {path}")
        if kind == "L":
            if not stat.S_ISLNK(metadata.st_mode) or os.readlink(path) != target:
                raise GeneratedBuildSubjectError(f"generated symlink changed: {path}")
            _authorized_symlink_target(
                path,
                generated_root=root,
                repository_root=repository_root,
            )

    for directory, expected_members in directory_members.items():
        if _members(directory) != expected_members:
            raise GeneratedBuildSubjectError(
                f"generated build directory membership changed: {directory}"
            )

    return tuple(sorted(entries, key=lambda item: os.fsencode(item[1])))


def _tree_fingerprint(root: Path, *, repository_root: Path) -> str:
    digest = hashlib.sha256()
    _feed(digest, b"nembra-cocoapods-generated-tree-v1")
    for kind, relative, mode, payload in _tree_entries(
        root,
        repository_root=repository_root,
    ):
        _feed(digest, kind.encode("ascii"))
        _feed(digest, os.fsencode(relative))
        _feed(digest, mode.to_bytes(4, "big"))
        _feed(digest, payload)
    return digest.hexdigest()


def _regular_fingerprint(path: Path) -> str:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise GeneratedBuildSubjectError(
            f"required generated build file is unavailable: {path}"
        ) from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise GeneratedBuildSubjectError(
            f"required generated build file is not a regular file: {path}"
        )
    content_digest = _read_regular(path, _identity(metadata))
    digest = hashlib.sha256()
    _feed(digest, b"nembra-cocoapods-generated-file-v1")
    _feed(digest, stat.S_IMODE(metadata.st_mode).to_bytes(4, "big"))
    _feed(digest, metadata.st_size.to_bytes(8, "big"))
    _feed(digest, content_digest)
    return digest.hexdigest()


def _tree_generation_witness(
    root: Path,
    *,
    repository_root: Path,
) -> tuple[tuple[object, ...], ...]:
    """Capture pathname/metadata authority without consuming file contents.

    Per-tree content hashing already proves stable reads locally. This witness is
    intentionally cheaper and spans the *whole* lock + Pods + workspace call so
    a path that changes after its local tree pass cannot become part of a hybrid
    subject. ctime/inode/membership are retained, so same-size rewrites and path
    replacement are rejected by the final joint comparison.
    """

    try:
        root_metadata = root.lstat()
    except OSError as error:
        raise GeneratedBuildSubjectError(
            f"required generated build directory is unavailable: {root}"
        ) from error
    if stat.S_ISLNK(root_metadata.st_mode) or not stat.S_ISDIR(root_metadata.st_mode):
        raise GeneratedBuildSubjectError(
            f"required generated build root is not a real directory: {root}"
        )

    witness: list[tuple[object, ...]] = [
        ("D", ".", _identity(root_metadata), _members(root))
    ]
    for current_text, directory_names, file_names in os.walk(
        root, topdown=True, followlinks=False
    ):
        current = Path(current_text)
        if current != root:
            current_metadata = current.lstat()
            if stat.S_ISLNK(current_metadata.st_mode) or not stat.S_ISDIR(current_metadata.st_mode):
                raise GeneratedBuildSubjectError(
                    f"generated build directory changed kind while witnessing: {current}"
                )
            witness.append(
                (
                    "D",
                    current.relative_to(root).as_posix(),
                    _identity(current_metadata),
                    _members(current),
                )
            )

        kept_directories: list[str] = []
        for name in sorted(directory_names, key=os.fsencode):
            candidate = current / name
            metadata = candidate.lstat()
            relative = candidate.relative_to(root).as_posix()
            if stat.S_ISLNK(metadata.st_mode):
                target = _authorized_symlink_target(
                    candidate,
                    generated_root=root,
                    repository_root=repository_root,
                )
                witness.append(("L", relative, _identity(metadata), target))
            elif stat.S_ISDIR(metadata.st_mode):
                kept_directories.append(name)
            else:
                raise GeneratedBuildSubjectError(
                    f"unsupported generated directory entry while witnessing: {candidate}"
                )
        directory_names[:] = kept_directories

        for name in sorted(file_names, key=os.fsencode):
            candidate = current / name
            metadata = candidate.lstat()
            relative = candidate.relative_to(root).as_posix()
            if stat.S_ISLNK(metadata.st_mode):
                target = _authorized_symlink_target(
                    candidate,
                    generated_root=root,
                    repository_root=repository_root,
                )
                witness.append(("L", relative, _identity(metadata), target))
            elif stat.S_ISREG(metadata.st_mode):
                witness.append(("F", relative, _identity(metadata)))
            else:
                raise GeneratedBuildSubjectError(
                    f"unsupported generated file entry while witnessing: {candidate}"
                )

    return tuple(sorted(witness, key=lambda item: (str(item[1]), str(item[0]))))


def _generation_witness(
    *,
    lockfile: Path,
    pods: Path,
    workspace: Path,
) -> tuple[object, ...]:
    repository_root = lockfile.parent
    try:
        lock_metadata = lockfile.lstat()
    except OSError as error:
        raise GeneratedBuildSubjectError(
            f"required generated build file is unavailable: {lockfile}"
        ) from error
    if stat.S_ISLNK(lock_metadata.st_mode) or not stat.S_ISREG(lock_metadata.st_mode):
        raise GeneratedBuildSubjectError(
            f"required generated build file is not a regular file: {lockfile}"
        )
    return (
        ("LOCK", _identity(lock_metadata)),
        ("PODS", _tree_generation_witness(pods, repository_root=repository_root)),
        (
            "WORKSPACE",
            _tree_generation_witness(workspace, repository_root=repository_root),
        ),
    )


def build_subject(*, lockfile: Path, pods: Path, workspace: Path) -> str:
    repository_root = lockfile.parent
    initial_generation = _generation_witness(
        lockfile=lockfile,
        pods=pods,
        workspace=workspace,
    )

    digest = hashlib.sha256()
    _feed(digest, SCHEMA)
    _feed(digest, bytes.fromhex(_regular_fingerprint(lockfile)))
    _feed(
        digest,
        bytes.fromhex(_tree_fingerprint(pods, repository_root=repository_root)),
    )
    _feed(
        digest,
        bytes.fromhex(_tree_fingerprint(workspace, repository_root=repository_root)),
    )

    final_generation = _generation_witness(
        lockfile=lockfile,
        pods=pods,
        workspace=workspace,
    )
    if final_generation != initial_generation:
        raise GeneratedBuildSubjectError(
            "generated CocoaPods build inputs changed across the combined lock/Pods/workspace fingerprint"
        )
    return digest.hexdigest()


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Fingerprint the exact generated CocoaPods build subject used by Nembra Capture."
    )
    parser.add_argument("--lockfile", required=True, type=Path)
    parser.add_argument("--pods", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    arguments = _parser().parse_args(list(argv) if argv is not None else None)
    try:
        fingerprint = build_subject(
            lockfile=arguments.lockfile.resolve(),
            pods=arguments.pods.resolve(),
            workspace=arguments.workspace.resolve(),
        )
    except (GeneratedBuildSubjectError, OSError, ValueError) as error:
        print(f"ERROR: generated CocoaPods build subject rejected: {error}", file=os.sys.stderr)
        return 73
    print(fingerprint)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

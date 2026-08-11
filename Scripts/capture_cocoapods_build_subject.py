#!/usr/bin/env python3
"""Bind the generated CocoaPods field-build graph to one exact reviewed digest.

The subject covers Podfile.lock plus the complete generated Pods/ and
NembraCapture.xcworkspace/ trees. Generated symlinks are admitted only when they
resolve inside either generated tree or the two canonical local Tuya pod roots,
whose bytes are independently fingerprinted and guarded by the private-input
custody layer. Absolute checkout paths and private bytes are never serialized.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import os
import stat
import tempfile
from pathlib import Path
from typing import Iterable


class GeneratedSubjectError(RuntimeError):
    pass


def _load_provenance_module():
    helper = Path(__file__).with_name("capture_tuya_private_input_provenance.py")
    spec = importlib.util.spec_from_file_location("capture_tuya_private_input_provenance", helper)
    if spec is None or spec.loader is None:
        raise GeneratedSubjectError("Capture provenance helper could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


provenance = _load_provenance_module()


def _identity(metadata: os.stat_result) -> tuple[int, ...]:
    return provenance._stat_identity(metadata)


def _feed(digest: "hashlib._Hash", value: bytes) -> None:
    digest.update(len(value).to_bytes(8, "big"))
    digest.update(value)


def _real_directory(path: Path, label: str) -> Path:
    try:
        metadata = path.lstat()
        resolved = path.resolve(strict=True)
    except OSError as error:
        raise GeneratedSubjectError(f"{label} is unavailable") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise GeneratedSubjectError(f"{label} must be one real directory")
    return resolved


def _contains(root: Path, candidate: Path) -> bool:
    try:
        candidate.relative_to(root)
        return True
    except ValueError:
        return False


def _allowed_roots(
    *, lockfile: Path, pods: Path, workspace: Path
) -> tuple[tuple[str, Path], ...]:
    roots: list[tuple[str, Path]] = [
        ("Pods", _real_directory(pods, "Pods generated root")),
        ("Workspace", _real_directory(workspace, "workspace generated root")),
    ]
    repository = lockfile.parent.resolve(strict=True)
    for label, relative in (
        ("TuyaSDK", Path("LocalSecrets/TuyaSDK")),
        ("TuyaRuntime", Path("LocalSecrets/TuyaRuntime")),
    ):
        candidate = repository / relative
        try:
            candidate.lstat()
        except FileNotFoundError:
            continue
        roots.append((label, _real_directory(candidate, f"{label} externally-custodied root")))
    return tuple(roots)


def _admit_symlink(
    path: Path, allowed_roots: tuple[tuple[str, Path], ...]
) -> tuple[str, str, str, tuple[int, ...]]:
    try:
        before_text = os.readlink(path)
        resolved = path.resolve(strict=True)
        resolved_metadata = resolved.lstat()
        after_text = os.readlink(path)
        final_link = path.lstat()
    except OSError as error:
        raise GeneratedSubjectError("generated build symlink is broken or unavailable") from error
    if before_text != after_text or not stat.S_ISLNK(final_link.st_mode):
        raise GeneratedSubjectError("generated build symlink changed during admission")

    for label, root in allowed_roots:
        if _contains(root, resolved):
            return (
                before_text,
                label,
                resolved.relative_to(root).as_posix(),
                _identity(resolved_metadata),
            )
    raise GeneratedSubjectError(
        "generated build symlink escapes generated trees and separately-custodied Tuya roots"
    )


def _directory_members(path: Path) -> tuple[str, ...]:
    try:
        return tuple(sorted(os.listdir(path), key=os.fsencode))
    except OSError as error:
        raise GeneratedSubjectError("generated build directory changed during custody") from error


def _tree_generation_snapshot(
    root: Path,
    *,
    allowed_roots: tuple[tuple[str, Path], ...],
) -> tuple[tuple[object, ...], ...]:
    root_metadata = root.lstat()
    if stat.S_ISLNK(root_metadata.st_mode) or not stat.S_ISDIR(root_metadata.st_mode):
        raise GeneratedSubjectError("generated build root must remain one real directory")

    entries: list[tuple[object, ...]] = [
        (".", "D", _identity(root_metadata), None)
    ]
    memberships: dict[Path, tuple[str, ...]] = {}

    for current_text, directory_names, file_names in os.walk(
        root, topdown=True, followlinks=False
    ):
        current = Path(current_text)
        memberships[current] = tuple(
            sorted((*directory_names, *file_names), key=os.fsencode)
        )
        kept: list[str] = []

        for name in sorted(directory_names, key=os.fsencode):
            path = current / name
            relative = path.relative_to(root).as_posix()
            metadata = path.lstat()
            identity = _identity(metadata)
            if stat.S_ISLNK(metadata.st_mode):
                entries.append((relative, "L", identity, _admit_symlink(path, allowed_roots)))
            elif stat.S_ISDIR(metadata.st_mode):
                entries.append((relative, "D", identity, None))
                kept.append(name)
            else:
                raise GeneratedSubjectError("generated tree contains unsupported directory entry")
        directory_names[:] = kept

        for name in sorted(file_names, key=os.fsencode):
            path = current / name
            relative = path.relative_to(root).as_posix()
            metadata = path.lstat()
            identity = _identity(metadata)
            if stat.S_ISLNK(metadata.st_mode):
                entries.append((relative, "L", identity, _admit_symlink(path, allowed_roots)))
            elif stat.S_ISREG(metadata.st_mode):
                entries.append((relative, "F", identity, None))
            else:
                raise GeneratedSubjectError("generated tree contains unsupported file entry")

    for relative, kind, expected_identity, token in entries:
        path = root if relative == "." else root / str(relative)
        try:
            current = path.lstat()
        except OSError as error:
            raise GeneratedSubjectError("generated tree entry disappeared during custody") from error
        if _identity(current) != expected_identity:
            raise GeneratedSubjectError("generated tree entry changed during custody")
        if kind == "L":
            if _admit_symlink(path, allowed_roots) != token:
                raise GeneratedSubjectError("generated symlink target changed during custody")
        elif kind == "D" and not stat.S_ISDIR(current.st_mode):
            raise GeneratedSubjectError("generated directory changed kind during custody")
        elif kind == "F" and not stat.S_ISREG(current.st_mode):
            raise GeneratedSubjectError("generated file changed kind during custody")

    for directory, members in memberships.items():
        if _directory_members(directory) != members:
            raise GeneratedSubjectError("generated directory membership changed during custody")

    return tuple(sorted(entries, key=lambda entry: os.fsencode(str(entry[0]))))


def _generation_snapshot(
    *,
    lockfile: Path,
    pods: Path,
    workspace: Path,
    allowed_roots: tuple[tuple[str, Path], ...] | None = None,
) -> tuple[object, ...]:
    # Keep this three-path API callable by the existing build guard. Callers may
    # supply a precomputed root set only when taking several samples inside one
    # higher-level subject operation.
    if allowed_roots is None:
        allowed_roots = _allowed_roots(lockfile=lockfile, pods=pods, workspace=workspace)

    lock_identity = provenance._regular_file_generation_identity(lockfile)
    pods_snapshot = _tree_generation_snapshot(pods, allowed_roots=allowed_roots)
    workspace_snapshot = _tree_generation_snapshot(workspace, allowed_roots=allowed_roots)

    # Re-read both trees only after both first-pass snapshots exist. This makes
    # one witness span the pair instead of accepting a Pods generation from t1
    # and a workspace generation from t2 as one hybrid authority subject.
    if _tree_generation_snapshot(pods, allowed_roots=allowed_roots) != pods_snapshot:
        raise GeneratedSubjectError("Pods changed while the combined build subject was snapshotted")
    if _tree_generation_snapshot(workspace, allowed_roots=allowed_roots) != workspace_snapshot:
        raise GeneratedSubjectError("workspace changed while the combined build subject was snapshotted")
    if provenance._regular_file_generation_identity(lockfile) != lock_identity:
        raise GeneratedSubjectError("Podfile.lock changed while the combined build subject was snapshotted")
    return (lock_identity, pods_snapshot, workspace_snapshot)


def _tree_fingerprint(
    root: Path,
    *,
    allowed_roots: tuple[tuple[str, Path], ...],
) -> str:
    before = _tree_generation_snapshot(root, allowed_roots=allowed_roots)
    digest = hashlib.sha256()
    _feed(digest, b"nembra-cocoapods-generated-tree-v2")

    for relative, kind, identity, token in before:
        path = root if relative == "." else root / str(relative)
        metadata = path.lstat()
        _feed(digest, str(kind).encode("ascii"))
        _feed(digest, os.fsencode(str(relative)))
        _feed(digest, stat.S_IMODE(metadata.st_mode).to_bytes(4, "big"))
        if kind == "F":
            _, content_sha256 = provenance._read_stable_regular_file_sha256(
                path,
                expected_identity=identity,
            )
            _feed(digest, bytes.fromhex(content_sha256))
        elif kind == "L":
            # Link text belongs to the generated graph. Resolved external bytes
            # stay under the separate private-input provenance/build guard.
            target_text = token[0]
            _feed(digest, os.fsencode(str(target_text)))
        else:
            _feed(digest, b"")

    after = _tree_generation_snapshot(root, allowed_roots=allowed_roots)
    if after != before:
        raise GeneratedSubjectError("generated tree changed while it was fingerprinted")
    return digest.hexdigest()


def subject_digest(
    *,
    lockfile: Path,
    pods: Path,
    workspace: Path,
) -> str:
    allowed_roots = _allowed_roots(lockfile=lockfile, pods=pods, workspace=workspace)
    before = _generation_snapshot(
        lockfile=lockfile,
        pods=pods,
        workspace=workspace,
        allowed_roots=allowed_roots,
    )
    lock_sha256 = provenance._read_stable_regular_file_sha256(lockfile)[1]
    pods_sha256 = _tree_fingerprint(pods, allowed_roots=allowed_roots)
    workspace_sha256 = _tree_fingerprint(workspace, allowed_roots=allowed_roots)
    after = _generation_snapshot(
        lockfile=lockfile,
        pods=pods,
        workspace=workspace,
        allowed_roots=allowed_roots,
    )
    if after != before:
        raise GeneratedSubjectError("CocoaPods generated build subject changed while it was fingerprinted")

    digest = hashlib.sha256()
    _feed(digest, b"nembra-cocoapods-generated-build-subject-v1")
    _feed(digest, bytes.fromhex(lock_sha256))
    _feed(digest, bytes.fromhex(pods_sha256))
    _feed(digest, bytes.fromhex(workspace_sha256))
    return digest.hexdigest()


def _canonical_expected(value: str) -> str:
    normalized = value.lower()
    if len(normalized) != 64 or any(character not in "0123456789abcdef" for character in normalized):
        raise GeneratedSubjectError("accepted CocoaPods build-subject digest must be exactly 64 hex characters")
    return normalized


def _self_test() -> int:
    with tempfile.TemporaryDirectory(prefix="nembra-cocoapods-subject-selftest-") as temporary:
        root = Path(temporary)
        lockfile = root / "Podfile.lock"
        pods = root / "Pods"
        workspace = root / "NembraCapture.xcworkspace"
        (pods / "Target Support Files/Pods-NembraCapture").mkdir(parents=True)
        workspace.mkdir()
        lockfile.write_text("PODS:\n  - Example (1.0)\n", encoding="utf-8")
        generated = pods / "Target Support Files/Pods-NembraCapture/Pods-NembraCapture.debug.xcconfig"
        generated.write_text("SETTING = REVIEWED\n", encoding="utf-8")
        (workspace / "contents.xcworkspacedata").write_text("REVIEWED\n", encoding="utf-8")

        first = subject_digest(lockfile=lockfile, pods=pods, workspace=workspace)
        if _canonical_expected(first.upper()) != first:
            raise GeneratedSubjectError("digest canonicalization self-test failed")
        if subject_digest(lockfile=lockfile, pods=pods, workspace=workspace) != first:
            raise GeneratedSubjectError("stable generated build subject produced an unstable digest")

        generated.write_text("SETTING = SUBSTITUTED\n", encoding="utf-8")
        second = subject_digest(lockfile=lockfile, pods=pods, workspace=workspace)
        if second == first:
            raise GeneratedSubjectError("generated build mutation did not change the subject digest")

        private = root / "LocalSecrets/TuyaSDK"
        private.mkdir(parents=True)
        (private / "ThingSmartCryption.podspec").write_text("private\n", encoding="utf-8")
        (pods / "ThingSmartCryption").symlink_to(private)
        subject_digest(lockfile=lockfile, pods=pods, workspace=workspace)
    print("CocoaPods generated build-subject self-test passed.")
    return 0


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Nembra Capture CocoaPods generated build-subject custody")
    parser.add_argument("mode", choices=("digest", "verify"), nargs="?", default="digest")
    parser.add_argument("--lockfile")
    parser.add_argument("--pods")
    parser.add_argument("--workspace")
    parser.add_argument("--expected")
    parser.add_argument("--self-test", action="store_true")
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    arguments = _parser().parse_args(argv)
    if arguments.self_test:
        try:
            return _self_test()
        except (OSError, GeneratedSubjectError, provenance.ProvenanceError) as error:
            print(f"ERROR: {error}", file=os.sys.stderr)
            return 2

    if not arguments.lockfile or not arguments.pods or not arguments.workspace:
        print("ERROR: --lockfile, --pods, and --workspace are required", file=os.sys.stderr)
        return 2

    try:
        digest = subject_digest(
            lockfile=Path(arguments.lockfile),
            pods=Path(arguments.pods),
            workspace=Path(arguments.workspace),
        )
        if arguments.mode == "verify":
            if arguments.expected is None:
                raise GeneratedSubjectError("--expected is required in verify mode")
            expected = _canonical_expected(arguments.expected)
            if digest != expected:
                raise GeneratedSubjectError(
                    "generated CocoaPods build subject does not match the externally accepted digest"
                )
            print("Accepted CocoaPods generated build subject matched.")
        else:
            print(digest)
    except (OSError, GeneratedSubjectError, provenance.ProvenanceError) as error:
        print(f"ERROR: {error}", file=os.sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

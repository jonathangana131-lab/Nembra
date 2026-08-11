#!/usr/bin/env python3
"""Deterministically fingerprint CocoaPods-generated build inputs for Nembra Capture.

The digest is presentation-independent authority over the ignored generated Pods/ and
NembraCapture.xcworkspace trees. It hashes relative path, entry type, executable mode,
symlink target text, and regular-file bytes without following symlinks.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import stat
import sys

SCHEMA = b"nembra-capture-cocoapods-build-subject-v1\0"


def _record(hasher: "hashlib._Hash", kind: bytes, relative: str, mode: int, payload: bytes = b"") -> None:
    rel = relative.encode("utf-8")
    hasher.update(kind)
    hasher.update(len(rel).to_bytes(8, "big"))
    hasher.update(rel)
    hasher.update((mode & 0o7777).to_bytes(4, "big"))
    hasher.update(len(payload).to_bytes(8, "big"))
    hasher.update(payload)


def _digest_tree(root: Path, label: str, hasher: "hashlib._Hash") -> None:
    root = root.resolve(strict=True)
    root_stat = root.lstat()
    if not stat.S_ISDIR(root_stat.st_mode):
        raise ValueError(f"{label} is not a directory")

    _record(hasher, b"R", label, root_stat.st_mode)
    for current, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        directory_names.sort()
        file_names.sort()
        current_path = Path(current)

        retained_directories: list[str] = []
        for name in directory_names:
            path = current_path / name
            metadata = path.lstat()
            relative = f"{label}/{path.relative_to(root).as_posix()}"
            if stat.S_ISLNK(metadata.st_mode):
                _record(hasher, b"L", relative, metadata.st_mode, os.readlink(path).encode("utf-8"))
            elif stat.S_ISDIR(metadata.st_mode):
                _record(hasher, b"D", relative, metadata.st_mode)
                retained_directories.append(name)
            else:
                raise ValueError(f"unsupported CocoaPods directory entry: {relative}")
        directory_names[:] = retained_directories

        for name in file_names:
            path = current_path / name
            metadata = path.lstat()
            relative = f"{label}/{path.relative_to(root).as_posix()}"
            if stat.S_ISLNK(metadata.st_mode):
                _record(hasher, b"L", relative, metadata.st_mode, os.readlink(path).encode("utf-8"))
            elif stat.S_ISREG(metadata.st_mode):
                digest = hashlib.sha256()
                with path.open("rb", buffering=0) as handle:
                    while chunk := handle.read(1024 * 1024):
                        digest.update(chunk)
                _record(hasher, b"F", relative, metadata.st_mode, digest.digest())
            else:
                raise ValueError(f"unsupported CocoaPods file entry: {relative}")


def digest_generated_subject(pods: Path, workspace: Path) -> str:
    hasher = hashlib.sha256()
    hasher.update(SCHEMA)
    _digest_tree(pods, "Pods", hasher)
    _digest_tree(workspace, "NembraCapture.xcworkspace", hasher)
    return hasher.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pods", type=Path, required=True)
    parser.add_argument("--workspace", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        print(digest_generated_subject(arguments.pods, arguments.workspace))
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import stat
import subprocess
import tempfile


class CheckoutAuthorityError(RuntimeError):
    pass


DELEGATED_ROOTS = {
    "LocalSecrets",
    "Pods",
    "NembraCapture.xcworkspace",
    ".build",
    ".swiftpm",
    "build",
    "DerivedData",
}
DELEGATED_FILES = {"Podfile.lock", ".DS_Store"}


def git_environment(index_path: str) -> dict[str, str]:
    return {
        "HOME": "/tmp",
        "PATH": "/usr/bin:/bin",
        "LANG": "C",
        "LC_ALL": "C",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_INDEX_FILE": index_path,
    }


def git_base(root: Path, git_dir: Path) -> list[str]:
    return [
        "/usr/bin/git",
        f"--git-dir={git_dir}",
        f"--work-tree={root}",
        "-c",
        f"core.worktree={root}",
        "-c",
        "core.bare=false",
        "-c",
        "core.fsmonitor=false",
        "-c",
        "core.ignorestat=false",
        "-c",
        "core.untrackedCache=false",
        "-c",
        "core.fileMode=true",
        "-c",
        "core.excludesFile=/dev/null",
    ]


def run_git(root: Path, git_dir: Path, index_path: str, *args: str, text: bool = False):
    return subprocess.run(
        [*git_base(root, git_dir), *args],
        cwd=root,
        env=git_environment(index_path),
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=text,
    ).stdout


def git_blob_digest(payload: bytes) -> str:
    header = f"blob {len(payload)}\0".encode("ascii")
    return hashlib.sha1(header + payload).hexdigest()


def safe_relative_path(raw: str) -> Path:
    relative = Path(raw)
    if relative.is_absolute() or not raw or any(part in {"", ".", ".."} for part in relative.parts):
        raise CheckoutAuthorityError(f"unsafe accepted Git path: {raw!r}")
    return relative


def read_regular_no_follow(path: Path) -> tuple[bytes, os.stat_result]:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags)
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            raise CheckoutAuthorityError(f"tracked file is not one regular single-link inode: {path}")
        chunks: list[bytes] = []
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        after = os.fstat(descriptor)
        identity_before = (before.st_dev, before.st_ino, before.st_mode, before.st_size, before.st_mtime_ns, before.st_ctime_ns)
        identity_after = (after.st_dev, after.st_ino, after.st_mode, after.st_size, after.st_mtime_ns, after.st_ctime_ns)
        if identity_before != identity_after:
            raise CheckoutAuthorityError(f"tracked file changed during raw audit: {path}")
        return b"".join(chunks), after
    finally:
        os.close(descriptor)


def accepted_tree(root: Path, git_dir: Path, index_path: str, source_sha: str) -> dict[str, tuple[str, str]]:
    output = run_git(root, git_dir, index_path, "ls-tree", "-r", "-z", "--full-tree", source_sha)
    entries: dict[str, tuple[str, str]] = {}
    for raw_entry in output.split(b"\0"):
        if not raw_entry:
            continue
        metadata, separator, raw_path = raw_entry.partition(b"\t")
        if not separator:
            raise CheckoutAuthorityError("malformed accepted Git tree entry")
        mode, object_type, oid = metadata.decode("ascii").split(" ")
        if object_type != "blob":
            raise CheckoutAuthorityError(f"unsupported accepted Git object type {object_type!r} at {raw_path!r}")
        path = raw_path.decode("utf-8", "surrogateescape")
        safe_relative_path(path)
        entries[path] = (mode, oid.lower())
    if not entries:
        raise CheckoutAuthorityError("accepted Git tree unexpectedly contains no blobs")
    return entries


def verify_tracked_bytes(root: Path, entries: dict[str, tuple[str, str]]) -> None:
    for raw_path, (mode, expected_oid) in entries.items():
        relative = safe_relative_path(raw_path)
        path = root / relative
        try:
            metadata = os.lstat(path)
        except FileNotFoundError as error:
            raise CheckoutAuthorityError(f"accepted tracked path is missing: {raw_path}") from error
        if mode == "120000":
            if not stat.S_ISLNK(metadata.st_mode):
                raise CheckoutAuthorityError(f"accepted symlink changed type: {raw_path}")
            payload = os.readlink(path).encode("utf-8", "surrogateescape")
        elif mode in {"100644", "100755"}:
            if stat.S_ISLNK(metadata.st_mode):
                raise CheckoutAuthorityError(f"accepted regular file became symlink: {raw_path}")
            payload, stable = read_regular_no_follow(path)
            executable = bool(stable.st_mode & 0o111)
            if executable != (mode == "100755"):
                raise CheckoutAuthorityError(f"accepted executable mode changed: {raw_path}")
        else:
            raise CheckoutAuthorityError(f"unsupported accepted Git mode {mode!r} at {raw_path}")
        actual_oid = git_blob_digest(payload)
        if actual_oid != expected_oid:
            raise CheckoutAuthorityError(f"raw tracked bytes differ from accepted Git blob: {raw_path}")


def delegated(relative: Path) -> bool:
    if not relative.parts:
        return False
    top = relative.parts[0]
    if top == ".git" or top in DELEGATED_ROOTS:
        return True
    if len(relative.parts) == 1 and relative.name in DELEGATED_FILES:
        return True
    if relative.name == ".DS_Store" or relative.name.endswith(".log"):
        return True
    if any(part.endswith(".xcresult") for part in relative.parts):
        return True
    return False


def verify_no_unexpected_entries(root: Path, tracked: set[str]) -> None:
    stack = [root]
    while stack:
        directory = stack.pop()
        with os.scandir(directory) as iterator:
            for entry in iterator:
                path = Path(entry.path)
                relative = path.relative_to(root)
                if delegated(relative):
                    continue
                raw_relative = relative.as_posix()
                if entry.is_dir(follow_symlinks=False):
                    stack.append(path)
                    continue
                if raw_relative not in tracked:
                    raise CheckoutAuthorityError(f"unexpected build-visible worktree entry outside delegated roots: {raw_relative}")


def verify(root: Path, git_dir: Path, source_sha: str) -> None:
    root = root.resolve(strict=True)
    git_dir = git_dir.resolve(strict=True)
    expected_git_dir = root / ".git"
    if git_dir != expected_git_dir or not expected_git_dir.is_dir() or expected_git_dir.is_symlink():
        raise CheckoutAuthorityError("field checkout authority requires one physical standalone .git directory under the admitted root")
    source_sha = source_sha.lower()
    if len(source_sha) != 40 or any(character not in "0123456789abcdef" for character in source_sha):
        raise CheckoutAuthorityError("accepted field source SHA must be exactly 40 lowercase hex characters")

    descriptor, index_path = tempfile.mkstemp(prefix="nembra-field-authority-index-")
    os.close(descriptor)
    os.unlink(index_path)
    try:
        head = run_git(root, git_dir, index_path, "rev-parse", "--verify", "HEAD^{commit}", text=True).strip().lower()
        if head != source_sha:
            raise CheckoutAuthorityError(f"physical checkout HEAD {head} does not match accepted source {source_sha}")
        run_git(root, git_dir, index_path, "read-tree", source_sha)
        status = run_git(root, git_dir, index_path, "status", "--porcelain=v1", "--untracked-files=all", text=True)
        if status.strip():
            raise CheckoutAuthorityError("field checkout has Git-visible changes under a fresh authority index")
        entries = accepted_tree(root, git_dir, index_path, source_sha)
        verify_tracked_bytes(root, entries)
        verify_no_unexpected_entries(root, set(entries))
    finally:
        try:
            os.unlink(index_path)
        except FileNotFoundError:
            pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--git-dir", required=True)
    parser.add_argument("--source-sha", required=True)
    args = parser.parse_args()
    try:
        verify(Path(args.root), Path(args.git_dir), args.source_sha)
    except (CheckoutAuthorityError, OSError, subprocess.CalledProcessError) as error:
        print(f"ERROR: field checkout authority rejected build-visible workspace: {error}", file=os.sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

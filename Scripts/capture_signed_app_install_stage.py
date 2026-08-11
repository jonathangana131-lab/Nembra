#!/usr/bin/env python3
"""Create a root-owned read-only staging subject for Nembra Capture installation.

Root never opens the mutable build product. It creates an inaccessible outer directory,
then a forked child drops permanently to the invoking field user's UID/GID and copies the
app with /usr/bin/ditto through an inherited destination working directory. After that
child exits, root freezes the private copy before exposing it read-only. The installer
must perform all signature/provenance/entitlement checks on the returned staged app and
pass that exact path to devicectl.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import tempfile

PREFIX = "nembra-capture-install-"
APP_NAME = "Nembra Capture.app"
DEFAULT_PARENT = Path("/private/var/tmp")


class StageError(RuntimeError):
    pass


def _require_root() -> None:
    if os.geteuid() != 0:
        raise StageError("signed-app install staging must run as root")


def _safe_ids(uid: int, gid: int) -> None:
    if uid <= 0 or gid < 0:
        raise StageError("invoking field user identity is invalid")


def _symlink_stays_inside(app_root: Path, link: Path, target: str) -> bool:
    if target.startswith("/"):
        return False
    relative_parent = PurePosixPath(link.relative_to(app_root).parent.as_posix())
    normalized = PurePosixPath(os.path.normpath(str(relative_parent / target)))
    return not normalized.parts or normalized.parts[0] != ".."


def _freeze_tree(app_root: Path, uid: int, gid: int) -> None:
    root_meta = app_root.lstat()
    if not stat.S_ISDIR(root_meta.st_mode) or stat.S_ISLNK(root_meta.st_mode):
        raise StageError("staged app root is not one real directory")
    if root_meta.st_uid != uid:
        raise StageError("copy child did not own staged app before freeze")

    directories: list[Path] = []
    for current_text, directory_names, file_names in os.walk(app_root, topdown=True, followlinks=False):
        current = Path(current_text)
        directories.append(current)
        for name in directory_names + file_names:
            path = current / name
            meta = path.lstat()
            if stat.S_ISLNK(meta.st_mode):
                target = os.readlink(path)
                if not _symlink_stays_inside(app_root, path, target):
                    raise StageError(f"staged app contains escaping symlink: {path.relative_to(app_root)}")
                os.chown(path, 0, gid, follow_symlinks=False)
                continue
            if stat.S_ISDIR(meta.st_mode):
                continue
            if not stat.S_ISREG(meta.st_mode) or meta.st_nlink != 1:
                raise StageError(f"staged app contains unsupported or aliased file: {path.relative_to(app_root)}")
            if meta.st_uid != uid:
                raise StageError("staged app file owner drifted before freeze")
            owner_rx = stat.S_IMODE(meta.st_mode) & 0o500
            if not owner_rx & 0o400:
                raise StageError("staged app contains an owner-unreadable file")
            frozen_mode = owner_rx | (owner_rx >> 3)
            os.chown(path, 0, gid, follow_symlinks=False)
            os.chmod(path, frozen_mode, follow_symlinks=False)

    for directory in reversed(directories):
        meta = directory.lstat()
        if not stat.S_ISDIR(meta.st_mode) or stat.S_ISLNK(meta.st_mode):
            raise StageError("staged app directory changed during freeze")
        if directory != app_root and meta.st_uid != uid:
            raise StageError("staged app directory owner drifted before freeze")
        os.chown(directory, 0, gid, follow_symlinks=False)
        os.chmod(directory, 0o550, follow_symlinks=False)


def _copy_as_user(source: Path, payload_fd: int, uid: int, gid: int) -> None:
    pid = os.fork()
    if pid == 0:
        try:
            os.fchdir(payload_fd)
            try:
                os.setgroups([gid])
            except OSError:
                os.setgroups([])
            os.setgid(gid)
            os.setuid(uid)
            environment = {
                "PATH": "/usr/bin:/bin",
                "HOME": "/var/empty",
                "LANG": "C",
                "LC_ALL": "C",
                "TMPDIR": "/tmp",
            }
            os.execve("/usr/bin/ditto", ["/usr/bin/ditto", str(source), APP_NAME], environment)
        except BaseException:
            os._exit(126)
    _, status = os.waitpid(pid, 0)
    if not os.WIFEXITED(status) or os.WEXITSTATUS(status) != 0:
        raise StageError("unprivileged app copy failed")


def stage(source: Path, uid: int, gid: int, parent: Path = DEFAULT_PARENT) -> Path:
    _require_root()
    _safe_ids(uid, gid)
    if not source.is_absolute():
        raise StageError("source app path must be absolute")
    parent_meta = parent.lstat()
    if not stat.S_ISDIR(parent_meta.st_mode) or stat.S_ISLNK(parent_meta.st_mode):
        raise StageError("install staging parent is unsafe")

    outer = Path(tempfile.mkdtemp(prefix=PREFIX, dir=parent))
    payload = outer / "payload"
    try:
        os.chown(outer, 0, 0)
        os.chmod(outer, 0o700)
        payload.mkdir(mode=0o700)
        os.chown(payload, uid, gid)
        payload_fd = os.open(payload, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0))
        try:
            _copy_as_user(source, payload_fd, uid, gid)
        finally:
            os.close(payload_fd)
        app = payload / APP_NAME
        _freeze_tree(app, uid, gid)
        os.chown(payload, 0, gid)
        os.chmod(payload, 0o550)
        os.chown(outer, 0, gid)
        os.chmod(outer, 0o550)
        return app
    except BaseException:
        shutil.rmtree(outer, ignore_errors=True)
        raise


def cleanup(stage_root: Path) -> None:
    _require_root()
    resolved_parent = stage_root.parent.resolve(strict=True)
    expected_parent = DEFAULT_PARENT.resolve(strict=True)
    if resolved_parent != expected_parent or not stage_root.name.startswith(PREFIX):
        raise StageError("refusing cleanup outside canonical install staging parent")
    meta = stage_root.lstat()
    if not stat.S_ISDIR(meta.st_mode) or stat.S_ISLNK(meta.st_mode) or meta.st_uid != 0:
        raise StageError("refusing cleanup of non-root-owned staging subject")
    shutil.rmtree(stage_root)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    create = sub.add_parser("stage")
    create.add_argument("--source", type=Path, required=True)
    create.add_argument("--uid", type=int, required=True)
    create.add_argument("--gid", type=int, required=True)
    remove = sub.add_parser("cleanup")
    remove.add_argument("--stage-root", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "stage":
            print(stage(args.source, args.uid, args.gid))
        else:
            cleanup(args.stage_root)
    except (StageError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Run the structured-credential APFS oracle with minimal, reachable authority.

GitHub's macOS runner account belongs to more supplementary groups than the
Xcode 16.4 Python 3.9 ``subprocess`` implementation will accept through
``extra_groups``. The authority oracle does not need those ambient groups: the
field child needs only its primary GID plus the fresh one-run capability GID,
and ordinary same-UID attack children need no supplementary groups at all.

The root probe creates its temporary workspace as root (0700) before allocating
that fresh capability GID. A structured child can therefore have correct
permissions on the inner mount/control paths yet still die before its READY
marker because it cannot traverse the outer workspace. This wrapper grants only
the freshly allocated capability group execute/traversal authority on that one
root-owned workspace (root:<capability>, 0710). The underlying APFS oracle,
inner-path ownership, live-FD attack, non-forced detach, read-only remount, and
post-freeze mutation checks remain unchanged.
"""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import pwd
import stat
import sys

HERE = Path(__file__).resolve().parent
SUBJECT_PATH = HERE / "test_capture_signed_app_unmount_freeze_structured_credentials.py"


def load_subject():
    spec = importlib.util.spec_from_file_location("nembra_unmount_structured_subject", SUBJECT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load structured-credential APFS subject")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        raise SystemExit("minimal-group APFS replay requires sudo on macOS")

    try:
        uid = int(os.environ["SUDO_UID"])
        gid = int(os.environ["SUDO_GID"])
        user = os.environ["SUDO_USER"]
    except (KeyError, ValueError) as error:
        raise SystemExit(f"missing sudo invoking identity: {error}")

    account = pwd.getpwuid(uid)
    if account.pw_name != user or account.pw_gid != gid:
        raise SystemExit("sudo invoking identity does not match account database")

    normal_groups = set(os.getgrouplist(user, gid))
    subject = load_subject()

    def minimal_structured_credentials(child_uid: int, child_gid: int, groups: list[int]) -> dict[str, object]:
        requested = set(groups)
        extra_authority = sorted(requested.difference(normal_groups))
        if len(extra_authority) > 1:
            raise ValueError(
                "oracle requested more than one non-ambient supplementary capability: "
                f"{extra_authority}"
            )
        return {
            "user": child_uid,
            "group": child_gid,
            "extra_groups": extra_authority,
        }

    workspace_state: dict[str, Path] = {}
    original_mkdtemp = subject.tempfile.mkdtemp
    original_allocate_capability_gid = subject.allocate_capability_gid

    def capture_workspace(*args, **kwargs) -> str:
        path = Path(original_mkdtemp(*args, **kwargs)).resolve(strict=True)
        metadata = path.lstat()
        if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            raise RuntimeError("structured-credential oracle workspace is not one real directory")
        if metadata.st_uid != 0:
            raise RuntimeError("structured-credential oracle workspace is not root-owned")
        workspace_state["path"] = path
        return str(path)

    def allocate_reachable_capability(normal_group_ids: set[int]) -> int:
        capability_gid = int(original_allocate_capability_gid(normal_group_ids))
        workspace = workspace_state.get("path")
        if workspace is None:
            raise RuntimeError("capability allocated before root workspace capture")
        before = workspace.lstat()
        if before.st_uid != 0 or not stat.S_ISDIR(before.st_mode) or stat.S_ISLNK(before.st_mode):
            raise RuntimeError("root workspace identity changed before capability traversal grant")
        os.chown(workspace, 0, capability_gid)
        os.chmod(workspace, 0o710)
        after = workspace.lstat()
        if after.st_uid != 0 or after.st_gid != capability_gid or stat.S_IMODE(after.st_mode) != 0o710:
            raise RuntimeError("could not bind outer workspace traversal to fresh capability GID")
        if capability_gid in normal_groups:
            raise RuntimeError("fresh workspace capability unexpectedly belongs to normal field groups")
        print(f"NEMBRA_UNMOUNT_WORKSPACE_CAPABILITY_GID={capability_gid}")
        return capability_gid

    subject.structured_credentials = minimal_structured_credentials
    subject.tempfile.mkdtemp = capture_workspace
    subject.allocate_capability_gid = allocate_reachable_capability
    return int(subject.root_probe())


if __name__ == "__main__":
    raise SystemExit(main())

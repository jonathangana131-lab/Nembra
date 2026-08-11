#!/usr/bin/env python3
"""Run the structured-credential APFS oracle with a minimal supplementary-group set.

GitHub's macOS runner account belongs to more supplementary groups than the
Xcode 16.4 Python 3.9 ``subprocess`` implementation will accept through
``extra_groups``. The authority oracle does not need those ambient groups: the
field child needs only its primary GID plus the fresh one-run capability GID,
and ordinary same-UID attack children need no supplementary groups at all.

This wrapper leaves the #3027 filesystem oracle unchanged and narrows only the
synthetic child credential set. A green run therefore still has to prove the
same busy-live-writer -> quiescent-detach -> read-only-remount sequence.
"""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import pwd
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
        # Deliberately do not replay the runner account's ambient supplementary
        # memberships. The primary GID is supplied separately; the only extra
        # authority admitted here is the one fresh capability GID chosen by the
        # underlying oracle.
        return {
            "user": child_uid,
            "group": child_gid,
            "extra_groups": extra_authority,
        }

    subject.structured_credentials = minimal_structured_credentials
    return int(subject.root_probe())


if __name__ == "__main__":
    raise SystemExit(main())

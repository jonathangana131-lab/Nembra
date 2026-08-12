#!/usr/bin/env python3
"""Replay #3143's retained-authority oracle with APFS ownership enforced.

#3143 reached its real pathname-revocation prerequisite and proved the default
APFS attach shape let the former dedicated build identity create a fresh path
after root attempted chown(0,0)+chmod(0700). #3162 then proved the exact same
fresh UID/GID topology denies both fresh- and existing-path mutation when the
image is attached with ``hdiutil attach -owners on``.

This validation-only wrapper does not weaken #3143's dirfd/mmap oracle. It loads
that exact committed witness, changes only its APFS attach helper to request
ownership enforcement for writable and read-only mounts, then replays both
retained-authority classes with the original semantic acceptance contract.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys

HERE = Path(__file__).resolve().parent
PARENT_PATH = HERE / "test_capture_signed_app_dedicated_uid_retained_authority.py"
WRAPPER_MARKER = "NEMBRA_RETAINED_AUTHORITY_OWNERS_ON_JSON="
WRAPPER_ERROR = "NEMBRA_RETAINED_AUTHORITY_OWNERS_ON_ERROR="


class ReplayError(RuntimeError):
    pass


def load_parent():
    spec = importlib.util.spec_from_file_location("nembra_retained_authority_owners_on_parent", PARENT_PATH)
    if spec is None or spec.loader is None:
        raise ReplayError("could not load exact #3143 retained-authority witness")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def emit_error(kind: str, message: str, *, authority: str, **extra: object) -> None:
    payload: dict[str, object] = {
        "schemaVersion": 1,
        "kind": kind,
        "authorityClass": authority,
        "message": message,
        "physicalAuthorityCreated": False,
    }
    payload.update(extra)
    print(WRAPPER_ERROR + json.dumps(payload, sort_keys=True), file=sys.stderr)


def owners_on_attach(image: Path, mountpoint: Path, readonly: bool) -> str:
    command = ["/usr/bin/hdiutil", "attach", "-plist", "-nobrowse", "-owners", "on"]
    if readonly:
        command.append("-readonly")
    command.extend(["-mountpoint", str(mountpoint), str(image)])
    completed = subprocess.run(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        raise ReplayError(
            "ownership-enforced APFS attach failed: "
            + completed.stderr.decode("utf-8", errors="replace")[-3000:]
        )
    try:
        payload = plistlib.loads(completed.stdout)
    except Exception as error:
        raise ReplayError(f"ownership-enforced attach emitted malformed plist: {error}") from error
    for entity in payload.get("system-entities", []):
        if entity.get("mount-point") == str(mountpoint) and entity.get("dev-entry"):
            return str(entity["dev-entry"])
    raise ReplayError("ownership-enforced attach returned no exact mounted device")


def install_attach_override(parent) -> None:
    dedicated = parent.load_dedicated_helper()
    original_load_freeze = dedicated.load_freeze_helper

    def load_freeze_with_owners_on():
        helper = original_load_freeze()
        helper.hdiutil_attach = owners_on_attach
        return helper

    dedicated.load_freeze_helper = load_freeze_with_owners_on
    parent.load_dedicated_helper = lambda: dedicated


def semantic_accept(parent, evidence: dict[str, object], authority: str, field_uid: int, field_gid: int, active_groups: list[int]) -> bool:
    writer_python = evidence.get("writerPythonExecutable")
    return bool(
        evidence.get("schemaVersion") == 1
        and evidence.get("authorityClass") == authority
        and evidence.get("fieldUID") == field_uid
        and evidence.get("fieldPrimaryGID") == field_gid
        and evidence.get("fieldActiveSupplementaryGroups") == active_groups
        and evidence.get("fieldActiveGroupsSubsetOfDirectoryService") is True
        and evidence.get("buildIdentityDistinctFromField") is True
        and evidence.get("fieldGroupsContainBuildGID") is False
        and evidence.get("fieldActiveGroupsContainBuildGID") is False
        and isinstance(writer_python, str)
        and Path(writer_python).is_absolute()
        and writer_python != "/usr/bin/python3"
        and evidence.get("fieldPathAttackReturnCode") != 0
        and evidence.get("formerBuildPathAttackReturnCode") != 0
        and evidence.get("retainedAuthorityArmed") is True
        and evidence.get("detachClassification") in {"BUSY", "DETACHED"}
        and evidence.get("postDetachMutationPersisted") is False
        and evidence.get("rootReadonlyAttackReturnCode") != 0
        and evidence.get("formerBuildReadonlyAttackReturnCode") != 0
        and evidence.get("physicalAuthorityCreated") is False
    )


def root_probe(authority: str, field_uid: int, field_gid: int, active_groups: list[int]) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "owners-on retained-authority root probe requires sudo on real macOS", authority=authority)
        return 70
    parent = load_parent()
    install_attach_override(parent)
    status = parent.root_probe(authority, field_uid, field_gid, active_groups)
    if status == 0:
        print(
            WRAPPER_MARKER
            + json.dumps(
                {
                    "schemaVersion": 1,
                    "authorityClass": authority,
                    "attachOwners": "on",
                    "parentOracleReturnCode": status,
                    "physicalAuthorityCreated": False,
                },
                sort_keys=True,
            )
        )
    return status


def parent_probe(authority: str) -> int:
    if sys.platform != "darwin":
        emit_error("environment", "owners-on retained-authority replay requires macOS", authority=authority)
        return 80
    field_uid = os.getuid()
    field_gid = os.getgid()
    if field_uid <= 0 or os.geteuid() != field_uid or os.getegid() != field_gid:
        emit_error("identity", "parent requires one stable non-root invoking identity", authority=authority)
        return 80
    active_groups = sorted({group for group in os.getgroups() if group != field_gid})
    if 0 in active_groups:
        emit_error("identity", "field process carries active root-group authority", authority=authority)
        return 80
    if subprocess.run(
        ["/usr/bin/sudo", "-n", "/usr/bin/true"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode != 0:
        emit_error("environment", "runner does not expose noninteractive sudo", authority=authority)
        return 80

    group_args = [item for group in active_groups for item in ("--field-active-group", str(group))]
    completed = subprocess.run(
        [
            "/usr/bin/sudo",
            "-n",
            "/usr/bin/python3",
            "-B",
            "-I",
            str(Path(__file__).resolve()),
            "--root-probe",
            "--authority",
            authority,
            "--field-uid",
            str(field_uid),
            "--field-gid",
            str(field_gid),
            "--field-active-group-count",
            str(len(active_groups)),
            *group_args,
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    sys.stdout.write(completed.stdout)
    sys.stderr.write(completed.stderr)
    if completed.returncode != 0:
        return completed.returncode

    parent = load_parent()
    records = [
        line[len(parent.MARKER):]
        for line in completed.stdout.splitlines()
        if line.startswith(parent.MARKER)
    ]
    wrapper_records = [
        line[len(WRAPPER_MARKER):]
        for line in completed.stdout.splitlines()
        if line.startswith(WRAPPER_MARKER)
    ]
    if len(records) != 1 or len(wrapper_records) != 1:
        emit_error("evidence", "missing or ambiguous parent/wrapper evidence", authority=authority)
        return 81
    try:
        evidence = json.loads(records[0])
        wrapper = json.loads(wrapper_records[0])
    except json.JSONDecodeError as error:
        emit_error("evidence", f"malformed parent/wrapper evidence: {error}", authority=authority)
        return 81
    accepted = (
        semantic_accept(parent, evidence, authority, field_uid, field_gid, active_groups)
        and wrapper.get("schemaVersion") == 1
        and wrapper.get("authorityClass") == authority
        and wrapper.get("attachOwners") == "on"
        and wrapper.get("parentOracleReturnCode") == 0
        and wrapper.get("physicalAuthorityCreated") is False
    )
    if not accepted:
        emit_error(
            "evidence",
            "owners-on retained-authority evidence failed exact semantic acceptance",
            authority=authority,
            parentEvidence=evidence,
            wrapperEvidence=wrapper,
        )
        return 82
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--authority", choices=("dirfd", "mmap"), required=True)
    parser.add_argument("--root-probe", action="store_true")
    parser.add_argument("--field-uid", type=int)
    parser.add_argument("--field-gid", type=int)
    parser.add_argument("--field-active-group", action="append", type=int, default=[])
    parser.add_argument("--field-active-group-count", type=int)
    args = parser.parse_args()
    if args.root_probe:
        if args.field_uid is None or args.field_gid is None:
            emit_error("arguments", "root probe requires exact pre-sudo UID/GID", authority=args.authority)
            return 83
        if args.field_active_group_count is None or args.field_active_group_count != len(args.field_active_group):
            emit_error("arguments", "root probe requires one exact active field group vector", authority=args.authority)
            return 83
        return root_probe(args.authority, args.field_uid, args.field_gid, args.field_active_group)
    if (
        args.field_uid is not None
        or args.field_gid is not None
        or args.field_active_group
        or args.field_active_group_count is not None
    ):
        emit_error("arguments", "root-only identity arguments are unavailable in parent mode", authority=args.authority)
        return 83
    return parent_probe(args.authority)


if __name__ == "__main__":
    raise SystemExit(main())

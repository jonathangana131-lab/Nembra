#!/usr/bin/env python3
"""Replay the post-detach directory-FD oracle with primary-group authority.

#3130 correctly preserved the real field process's active supplementary groups,
but its synthetic authority-bearing writer never reached READY: adding the fresh
capability GID overflowed the hosted macOS supplementary-group ceiling. The first
minimal-group replay removed that overflow but APFS still denied traversal when
the fresh unnamed capability existed only as a supplementary group.

This validation-only successor changes no production bytes. It runs the exact
#3130 APFS/directory-FD oracle while adapting only synthetic child credentials:
- the ordinary field negative control keeps the exact pre-sudo primary GID and
  exact pre-sudo active supplementary groups;
- any child carrying the one fresh capability GID uses that capability as its
  primary GID with zero supplementary groups;
- requested versus effective primary/supplementary credentials are retained and
  acceptance requires exactly two capability-bearing launches plus one exact
  field negative-control launch.

Using a dedicated primary group matches the accepted dedicated-build-identity
shape more closely than the failed supplementary-only fixture. No signing,
install, device, Bluetooth, Tuya, telemetry, or physical action is performed.
A green result is architecture evidence only.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
PARENT_PATH = HERE / "test_capture_signed_app_post_detach_dirfd_probe.py"
REPLAY_MARKER = "NEMBRA_POST_DETACH_DIRFD_MINIMAL_GROUPS_JSON="
ERROR_MARKER = "NEMBRA_POST_DETACH_DIRFD_MINIMAL_GROUPS_ERROR="


class ReplayError(RuntimeError):
    pass


def load_parent():
    spec = importlib.util.spec_from_file_location("nembra_post_detach_dirfd_parent", PARENT_PATH)
    if spec is None or spec.loader is None:
        raise ReplayError("could not load exact #3130 directory-FD oracle")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def emit_error(kind: str, message: str, **extra: object) -> None:
    payload: dict[str, object] = {
        "kind": kind,
        "message": message,
        "physicalAuthorityCreated": False,
    }
    payload.update(extra)
    print(ERROR_MARKER + json.dumps(payload, sort_keys=True), file=sys.stderr)


def _install_primary_capability_replay(parent, field_active_groups: list[int]):
    active = set(field_active_groups)
    original = parent.structured_credentials
    calls: list[dict[str, object]] = []

    def replay(uid: int, gid: int, groups: list[int]) -> dict[str, object]:
        requested = sorted({int(group) for group in groups if int(group) != gid})
        capability = [group for group in requested if group not in active]
        if capability:
            if len(capability) != 1:
                raise parent.ProbeError(
                    "synthetic capability launch exposed more than one non-field supplementary group"
                )
            capability_gid = capability[0]
            result = original(uid, capability_gid, [])
            role = "capability-primary"
        else:
            result = original(uid, gid, requested)
            role = "field"
        calls.append(
            {
                "role": role,
                "requestedPrimaryGID": gid,
                "requestedSupplementaryGroups": requested,
                "effectivePrimaryGID": result["group"],
                "effectiveSupplementaryGroups": list(result["extra_groups"]),
            }
        )
        return result

    parent.structured_credentials = replay
    return calls


def root_probe(field_uid: int, field_primary_gid: int, field_active_groups: list[int]) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "primary-capability replay root probe requires sudo on real macOS")
        return 70
    parent = load_parent()
    calls = _install_primary_capability_replay(parent, field_active_groups)
    status = parent.root_probe(field_uid, field_primary_gid, field_active_groups)
    if status != 0:
        return status
    print(
        REPLAY_MARKER
        + json.dumps(
            {
                "schemaVersion": 2,
                "fieldUID": field_uid,
                "fieldPrimaryGID": field_primary_gid,
                "fieldActiveSupplementaryGroups": field_active_groups,
                "credentialCalls": calls,
                "physicalAuthorityCreated": False,
            },
            sort_keys=True,
        )
    )
    return 0


def _semantic_accept(
    parent_evidence: dict[str, object],
    replay_evidence: dict[str, object],
    field_uid: int,
    field_gid: int,
    field_active_groups: list[int],
) -> bool:
    capability = parent_evidence.get("capabilityGID")
    if not isinstance(capability, int) or capability <= 0:
        return False

    calls = replay_evidence.get("credentialCalls")
    if not isinstance(calls, list):
        return False
    capability_calls = [
        call
        for call in calls
        if isinstance(call, dict) and call.get("role") == "capability-primary"
    ]
    field_calls = [
        call
        for call in calls
        if isinstance(call, dict) and call.get("role") == "field"
    ]
    group_replay_is_exact = (
        len(capability_calls) == 2
        and all(call.get("effectivePrimaryGID") == capability for call in capability_calls)
        and all(call.get("effectiveSupplementaryGroups") == [] for call in capability_calls)
        and all(
            capability in call.get("requestedSupplementaryGroups", [])
            for call in capability_calls
        )
        and len(field_calls) == 1
        and field_calls[0].get("requestedPrimaryGID") == field_gid
        and field_calls[0].get("effectivePrimaryGID") == field_gid
        and field_calls[0].get("requestedSupplementaryGroups") == field_active_groups
        and field_calls[0].get("effectiveSupplementaryGroups") == field_active_groups
    )

    busy_evidence = (
        parent_evidence.get("detachWasBusy") is True
        and "resource busy" in str(parent_evidence.get("firstDetachOutput", "")).casefold()
    )
    detached_safely = (
        parent_evidence.get("detachWasBusy") is False
        and str(parent_evidence.get("postDetachResult", "")).startswith("POSTDETACH_ERR:")
    )
    return bool(
        group_replay_is_exact
        and parent_evidence.get("fieldUID") == field_uid
        and parent_evidence.get("fieldPrimaryGID") == field_gid
        and parent_evidence.get("fieldActiveSupplementaryGroups") == field_active_groups
        and parent_evidence.get("fieldActiveGroupsSubsetOfDirectoryService") is True
        and parent_evidence.get("fieldActiveGroupsContainCapability") is False
        and parent_evidence.get("normalGroupsContainCapability") is False
        and parent_evidence.get("freshPathAttackReturnCode") != 0
        and parent_evidence.get("postDetachPersisted") is False
        and parent_evidence.get("rootReadonlyCreateReturnCode") != 0
        and parent_evidence.get("formerCapabilityReadonlyCreateReturnCode") != 0
        and parent_evidence.get("physicalAuthorityCreated") is False
        and replay_evidence.get("fieldUID") == field_uid
        and replay_evidence.get("fieldPrimaryGID") == field_gid
        and replay_evidence.get("fieldActiveSupplementaryGroups") == field_active_groups
        and replay_evidence.get("physicalAuthorityCreated") is False
        and (busy_evidence or detached_safely)
    )


def parent_probe() -> int:
    if sys.platform != "darwin":
        emit_error("environment", "primary-capability replay requires macOS")
        return 80
    field_uid = os.getuid()
    field_gid = os.getgid()
    if field_uid <= 0 or field_gid <= 0 or os.geteuid() != field_uid or os.getegid() != field_gid:
        emit_error("identity", "field parent requires one stable non-root invoking uid/gid")
        return 80
    field_active_groups = sorted({group for group in os.getgroups() if group != field_gid})
    if any(group <= 0 for group in field_active_groups):
        emit_error("identity", "field parent carries root or invalid active supplementary authority")
        return 80
    if subprocess.run(
        ["/usr/bin/sudo", "-n", "/usr/bin/true"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode != 0:
        emit_error("environment", "runner does not expose noninteractive sudo for validation")
        return 80

    active_args = [
        item
        for group in field_active_groups
        for item in ("--field-active-group", str(group))
    ]
    completed = subprocess.run(
        [
            "/usr/bin/sudo",
            "-n",
            "/usr/bin/python3",
            "-I",
            str(Path(__file__).resolve()),
            "--root-probe",
            "--field-uid",
            str(field_uid),
            "--field-primary-gid",
            str(field_gid),
            "--field-active-group-count",
            str(len(field_active_groups)),
            *active_args,
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
    parent_records = [
        line[len(parent.MARKER):]
        for line in completed.stdout.splitlines()
        if line.startswith(parent.MARKER)
    ]
    replay_records = [
        line[len(REPLAY_MARKER):]
        for line in completed.stdout.splitlines()
        if line.startswith(REPLAY_MARKER)
    ]
    if len(parent_records) != 1 or len(replay_records) != 1:
        emit_error("evidence", "missing or ambiguous parent/replay evidence")
        return 81
    try:
        parent_evidence = json.loads(parent_records[0])
        replay_evidence = json.loads(replay_records[0])
    except json.JSONDecodeError as error:
        emit_error("evidence", f"malformed parent/replay evidence: {error}")
        return 81
    if not _semantic_accept(
        parent_evidence,
        replay_evidence,
        field_uid,
        field_gid,
        field_active_groups,
    ):
        emit_error(
            "evidence",
            "primary-capability replay failed semantic acceptance",
            parentEvidence=parent_evidence,
            replayEvidence=replay_evidence,
        )
        return 82
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    parser.add_argument("--field-uid", type=int)
    parser.add_argument("--field-primary-gid", type=int)
    parser.add_argument("--field-active-group", action="append", type=int, default=[])
    parser.add_argument("--field-active-group-count", type=int)
    args = parser.parse_args()
    if args.root_probe:
        if (
            args.field_uid is None
            or args.field_primary_gid is None
            or args.field_active_group_count is None
            or args.field_active_group_count != len(args.field_active_group)
        ):
            emit_error("arguments", "root probe requires exact pre-sudo uid/gid and counted active groups")
            return 83
        return root_probe(
            args.field_uid,
            args.field_primary_gid,
            args.field_active_group,
        )
    if (
        args.field_uid is not None
        or args.field_primary_gid is not None
        or args.field_active_group
        or args.field_active_group_count is not None
    ):
        emit_error("arguments", "root-only identity arguments are unavailable in field parent mode")
        return 83
    return parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())

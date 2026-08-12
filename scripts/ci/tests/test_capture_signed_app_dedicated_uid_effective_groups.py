#!/usr/bin/env python3
"""Attest effective kernel groups for the dedicated Capture build identity.

The accepted dedicated-UID/APFS Xcode proof and production successor request
``extra_groups=[]`` when launching the fresh build account. Real macOS evidence
from the first exact run of this witness showed why source-level wording is not
enough: a freshly created local account still materializes macOS system-wide
Directory Services memberships in ``os.getgroups()`` even when the requested
extra-group vector is empty.

That first run also distinguished this from field-account authority leakage. The
production-shaped child and an independent ``sudo -u/-g`` launch both exposed the
same vector returned by ``os.getgrouplist(fresh_user, fresh_gid)``. Field-only
memberships did not cross into the fresh build identity.

The threat-relevant contract is therefore exact and mechanical:
- real/effective UID and primary GID equal the fresh dedicated identity;
- raw kernel supplementary authority, after removing a duplicate primary GID,
  equals the fresh account's own Directory Services baseline exactly;
- no field-only GID appears;
- no unexpected GID beyond that fresh-account baseline appears.

This does not pretend effective supplementary groups are empty. It records both
requested and effective authority so production can use truthful terminology.
No Xcode build, signing, private Tuya input, install, device, Bluetooth, telemetry,
or physical authority is created.
"""
from __future__ import annotations

import argparse
import grp
import importlib.util
import json
import os
from pathlib import Path
import pwd
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
PARENT_PATH = HERE / "test_capture_signed_app_real_xcode_dedicated_uid_freeze.py"
MARKER = "NEMBRA_DEDICATED_UID_EFFECTIVE_GROUPS_JSON="
ERROR_MARKER = "NEMBRA_DEDICATED_UID_EFFECTIVE_GROUPS_ERROR="
CHILD_MARKER = "NEMBRA_DEDICATED_UID_GROUP_CHILD_JSON="


class ProbeError(RuntimeError):
    pass


def load_parent():
    spec = importlib.util.spec_from_file_location(
        "nembra_dedicated_uid_effective_groups_parent",
        PARENT_PATH,
    )
    if spec is None or spec.loader is None:
        raise ProbeError("could not load accepted dedicated-UID validation helper")
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


def child_code() -> str:
    return r'''
import json
import os
import pwd
payload = {
    "realUID": os.getuid(),
    "effectiveUID": os.geteuid(),
    "realPrimaryGID": os.getgid(),
    "effectivePrimaryGID": os.getegid(),
    "rawKernelSupplementaryGroups": sorted(set(os.getgroups())),
    "resolvedUser": pwd.getpwuid(os.getuid()).pw_name,
}
print("NEMBRA_DEDICATED_UID_GROUP_CHILD_JSON=" + json.dumps(payload, sort_keys=True), flush=True)
'''


def parse_child(completed: subprocess.CompletedProcess[str], *, label: str) -> dict[str, object]:
    records = [
        line[len(CHILD_MARKER):]
        for line in completed.stdout.splitlines()
        if line.startswith(CHILD_MARKER)
    ]
    if completed.returncode != 0 or len(records) != 1:
        raise ProbeError(
            f"{label} attestor failed: rc={completed.returncode} "
            f"stdout={completed.stdout[-2000:]!r} stderr={completed.stderr[-2000:]!r}"
        )
    try:
        payload = json.loads(records[0])
    except json.JSONDecodeError as error:
        raise ProbeError(f"{label} attestor emitted malformed JSON: {error}") from error
    if not isinstance(payload, dict):
        raise ProbeError(f"{label} attestor did not emit one JSON object")
    return payload


def group_names(groups: list[int]) -> dict[str, str]:
    result: dict[str, str] = {}
    for group in groups:
        try:
            result[str(group)] = grp.getgrgid(group).gr_name
        except KeyError:
            result[str(group)] = "<unresolved>"
    return result


def root_probe(field_uid: int, field_gid: int, field_active_groups: list[int]) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "dedicated-UID group attestation requires sudo on real macOS")
        return 70
    try:
        sudo_uid = int(os.environ["SUDO_UID"])
        sudo_gid = int(os.environ["SUDO_GID"])
        sudo_user = os.environ["SUDO_USER"]
    except (KeyError, ValueError) as error:
        emit_error("identity", f"missing sudo invoking identity: {error}")
        return 71
    if sudo_uid != field_uid or sudo_gid != field_gid or field_uid <= 0 or field_gid <= 0:
        emit_error(
            "identity",
            "root phase is not bound to the exact pre-sudo field UID/GID",
            sudoUID=sudo_uid,
            sudoGID=sudo_gid,
            fieldUID=field_uid,
            fieldPrimaryGID=field_gid,
        )
        return 71
    account = pwd.getpwuid(field_uid)
    if account.pw_name != sudo_user or account.pw_gid != field_gid:
        emit_error("identity", "sudo tuple does not resolve to the invoking local account")
        return 71
    if len(field_active_groups) != len(set(field_active_groups)):
        emit_error("identity", "pre-sudo active supplementary vector is duplicated")
        return 71
    if any(group <= 0 for group in field_active_groups) or field_gid in field_active_groups:
        emit_error("identity", "pre-sudo active supplementary vector is invalid")
        return 71

    parent = load_parent()
    workspace = Path(tempfile.mkdtemp(prefix="nembra-dedicated-uid-groups.", dir="/private/tmp"))
    home = workspace / "home"
    build_name = f"nembragroups{os.getpid()}"
    build_uid: int | None = None
    identity_created = False
    try:
        build_uid = parent.choose_ephemeral_id()
        build_gid = build_uid
        home.mkdir()
        os.chown(workspace, 0, build_gid)
        os.chmod(workspace, 0o710)
        parent.create_local_build_identity(build_name, build_uid, build_gid, home)
        identity_created = True
        os.chown(home, build_uid, build_gid)
        os.chmod(home, 0o700)

        if build_uid == field_uid or build_gid == field_gid or build_gid in field_active_groups:
            emit_error("identity", "fresh build identity overlaps invoking field authority")
            return 71

        directory_groups = sorted(set(os.getgrouplist(build_name, build_gid)))
        if build_gid not in directory_groups or any(group <= 0 for group in directory_groups):
            emit_error("identity", "fresh build Directory Services group baseline is invalid")
            return 71
        if field_gid in directory_groups:
            emit_error("identity", "fresh build account unexpectedly includes the field primary GID")
            return 71
        directory_distinct = sorted({group for group in directory_groups if group != build_gid})
        field_baseline = {field_gid, *field_active_groups}
        field_only_groups = sorted(field_baseline.difference(directory_groups))

        environment = {
            "HOME": str(home),
            "USER": build_name,
            "LOGNAME": build_name,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": str(home),
            "LANG": "C",
            "LC_ALL": "C",
        }
        current = subprocess.run(
            ["/usr/bin/python3", "-B", "-I", "-c", child_code()],
            cwd=home,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            **parent.structured_credentials(build_uid, build_gid, []),
        )
        current_evidence = parse_child(current, label="production-shaped structured-credential")
        raw = current_evidence.get("rawKernelSupplementaryGroups")
        if not isinstance(raw, list) or any(not isinstance(group, int) for group in raw):
            emit_error("evidence", "production-shaped child did not expose an integer kernel group vector")
            return 72
        raw_distinct = sorted({group for group in raw if group != build_gid})
        unexpected = sorted(set(raw_distinct).difference(directory_distinct))
        missing = sorted(set(directory_distinct).difference(raw_distinct))
        field_only_leaked = sorted(set(raw_distinct).intersection(field_only_groups))

        sudo_candidate: dict[str, object]
        sudo_run = subprocess.run(
            [
                "/usr/bin/sudo",
                "-n",
                "-u",
                build_name,
                "-g",
                build_name,
                "/usr/bin/python3",
                "-B",
                "-I",
                "-c",
                child_code(),
            ],
            cwd=home,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        try:
            sudo_candidate = parse_child(sudo_run, label="sudo identity-bound diagnostic")
            sudo_candidate["returnCode"] = sudo_run.returncode
            sudo_raw = sudo_candidate.get("rawKernelSupplementaryGroups", [])
            sudo_distinct = sorted(
                {group for group in sudo_raw if isinstance(group, int) and group != build_gid}
            )
            sudo_candidate["distinctSupplementaryGroups"] = sudo_distinct
            sudo_candidate["directoryServiceBaselinePreservedExact"] = sudo_distinct == directory_distinct
        except ProbeError as error:
            sudo_candidate = {
                "returnCode": sudo_run.returncode,
                "error": str(error),
                "stdoutTail": sudo_run.stdout[-1200:],
                "stderrTail": sudo_run.stderr[-1200:],
            }

        identity_exact = (
            current_evidence.get("realUID") == build_uid
            and current_evidence.get("effectiveUID") == build_uid
            and current_evidence.get("realPrimaryGID") == build_gid
            and current_evidence.get("effectivePrimaryGID") == build_gid
            and current_evidence.get("resolvedUser") == build_name
        )
        baseline_exact = raw_distinct == directory_distinct and not unexpected and not missing
        accepted = identity_exact and baseline_exact and not field_only_leaked
        evidence = {
            "schemaVersion": 2,
            "fieldUID": field_uid,
            "fieldPrimaryGID": field_gid,
            "fieldActiveSupplementaryGroups": field_active_groups,
            "fieldGroupNames": group_names(sorted(field_baseline)),
            "buildUser": build_name,
            "buildUID": build_uid,
            "buildPrimaryGID": build_gid,
            "buildDirectoryServiceGroups": directory_groups,
            "buildDirectoryServiceDistinctSupplementaryGroups": directory_distinct,
            "buildDirectoryServiceGroupNames": group_names(directory_groups),
            "fieldOnlyGroups": field_only_groups,
            "requestedExtraGroups": [],
            "productionShapedChild": current_evidence,
            "productionShapedDistinctSupplementaryGroups": raw_distinct,
            "productionShapedUnexpectedGroupsBeyondDirectoryService": unexpected,
            "productionShapedMissingDirectoryServiceGroups": missing,
            "productionShapedFieldOnlyGroupsLeaked": field_only_leaked,
            "productionShapedIdentityExact": identity_exact,
            "productionShapedDirectoryServiceBaselinePreservedExact": baseline_exact,
            "productionShapedKernelGroupsAccepted": accepted,
            "effectiveZeroSupplementaryGroupsClaim": raw_distinct == [],
            "sudoIdentityBoundDiagnostic": sudo_candidate,
            "physicalAuthorityCreated": False,
        }
        print(MARKER + json.dumps(evidence, sort_keys=True))
        if not accepted:
            emit_error(
                "effective-credentials",
                "fresh dedicated build UID diverged from its exact Directory Services authority baseline",
                evidence=evidence,
            )
            return 72
        return 0
    except (OSError, KeyError, ProbeError, subprocess.CalledProcessError) as error:
        emit_error("fixture", f"dedicated-UID group attestation fixture failed: {type(error).__name__}: {error}")
        return 79
    finally:
        if identity_created:
            parent.remove_local_build_identity(build_name, build_uid)
        try:
            import shutil
            shutil.rmtree(workspace, ignore_errors=True)
        except Exception:
            pass


def parent_probe() -> int:
    if sys.platform != "darwin":
        emit_error("environment", "dedicated-UID group attestation requires macOS")
        return 80
    field_uid = os.getuid()
    field_gid = os.getgid()
    if field_uid <= 0 or field_gid <= 0 or os.geteuid() != field_uid or os.getegid() != field_gid:
        emit_error("identity", "parent requires one stable non-root invoking identity")
        return 80
    active = sorted({group for group in os.getgroups() if group != field_gid})
    if any(group <= 0 for group in active):
        emit_error("identity", "field parent carries root or invalid supplementary authority")
        return 80
    if subprocess.run(
        ["/usr/bin/sudo", "-n", "/usr/bin/true"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode != 0:
        emit_error("environment", "runner lacks noninteractive sudo required for validation")
        return 80
    active_args = [item for group in active for item in ("--field-active-group", str(group))]
    completed = subprocess.run(
        [
            "/usr/bin/sudo",
            "-n",
            "/usr/bin/python3",
            "-B",
            "-I",
            str(Path(__file__).resolve()),
            "--root-probe",
            "--field-uid",
            str(field_uid),
            "--field-primary-gid",
            str(field_gid),
            "--field-active-group-count",
            str(len(active)),
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
    return completed.returncode


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
            emit_error("arguments", "root probe requires exact counted pre-sudo identity arguments")
            return 83
        return root_probe(args.field_uid, args.field_primary_gid, args.field_active_group)
    if (
        args.field_uid is not None
        or args.field_primary_gid is not None
        or args.field_active_group
        or args.field_active_group_count is not None
    ):
        emit_error("arguments", "root-only identity arguments are unavailable in parent mode")
        return 83
    return parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())

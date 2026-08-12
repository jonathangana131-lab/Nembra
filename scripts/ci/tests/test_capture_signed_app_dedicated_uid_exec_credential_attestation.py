#!/usr/bin/env python3
"""Validate an exec-bound credential attestor for the Capture build identity.

Accepted validation #3147 established the macOS kernel truth for a freshly
created dedicated build account: ``extra_groups=[]`` does not produce an empty
supplementary vector. The child receives that fresh account's own Directory
Services baseline, while field-only groups stay out.

Production #3142 still needs a stronger property than an independent preflight:
the *same process* that is about to enter the compiler must attest its real and
effective UID/GID/groups, then immediately ``exec`` the guarded command without
an intervening credential transition. This validation exercises that exact
shape with a harmless Python payload and proves the PID and credential baseline
are preserved across exec. A deliberately wrong expected group baseline must
fail before the payload executes.

This is architecture validation only. It does not build or sign Nembra, touch
private Tuya inputs, provision/install an app, access a device, use Bluetooth,
or create physical authority.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import pwd
import grp
import secrets
import shutil
import subprocess
import sys
import tempfile
from typing import Any

HERE = Path(__file__).resolve().parent
PRODUCTION_HELPER = HERE.parent / "capture_signed_app_build_origin_custody.py"
RESULT_MARKER = "NEMBRA_DEDICATED_UID_EXEC_ATTESTATION_JSON="
ERROR_MARKER = "NEMBRA_DEDICATED_UID_EXEC_ATTESTATION_ERROR="
PREEXEC_MARKER = "NEMBRA_EXEC_ATTEST_PREEXEC_JSON="
POSTEXEC_MARKER = "NEMBRA_EXEC_ATTEST_POSTEXEC_JSON="
ATTEST_ERROR_MARKER = "NEMBRA_EXEC_ATTEST_ERROR_JSON="


class ProbeError(RuntimeError):
    pass


def emit_error(kind: str, message: str, **extra: object) -> None:
    payload: dict[str, object] = {
        "kind": kind,
        "message": message,
        "physicalAuthorityCreated": False,
    }
    payload.update(extra)
    print(ERROR_MARKER + json.dumps(payload, sort_keys=True), file=sys.stderr)


def load_production_helper():
    spec = importlib.util.spec_from_file_location(
        "nembra_capture_build_origin_custody_for_exec_attestation",
        PRODUCTION_HELPER,
    )
    if spec is None or spec.loader is None:
        raise ProbeError("could not load current production build-origin helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def snapshot() -> dict[str, Any]:
    uid = os.getuid()
    gid = os.getgid()
    return {
        "pid": os.getpid(),
        "realUID": uid,
        "effectiveUID": os.geteuid(),
        "realPrimaryGID": gid,
        "effectivePrimaryGID": os.getegid(),
        "rawKernelSupplementaryGroups": sorted(set(os.getgroups())),
        "resolvedUser": pwd.getpwuid(uid).pw_name,
    }


def payload_code() -> str:
    return r'''
import json
import os
import pwd
uid = os.getuid()
gid = os.getgid()
payload = {
    "pid": os.getpid(),
    "realUID": uid,
    "effectiveUID": os.geteuid(),
    "realPrimaryGID": gid,
    "effectivePrimaryGID": os.getegid(),
    "rawKernelSupplementaryGroups": sorted(set(os.getgroups())),
    "resolvedUser": pwd.getpwuid(uid).pw_name,
    "token": os.environ.get("NEMBRA_EXEC_ATTEST_TOKEN", ""),
    "execPayloadRan": True,
}
print("NEMBRA_EXEC_ATTEST_POSTEXEC_JSON=" + json.dumps(payload, sort_keys=True), flush=True)
'''


def launcher_code() -> str:
    # This code is deliberately self-contained because production can consume the
    # same shape as a narrow exec gate: attest current credentials, emit evidence,
    # then exec the real guarded command in the same process.
    return r'''
import json
import os
import pwd
import sys

PRE = "NEMBRA_EXEC_ATTEST_PREEXEC_JSON="
ERR = "NEMBRA_EXEC_ATTEST_ERROR_JSON="

uid = int(os.environ["NEMBRA_EXEC_ATTEST_EXPECTED_UID"])
gid = int(os.environ["NEMBRA_EXEC_ATTEST_EXPECTED_GID"])
user = os.environ["NEMBRA_EXEC_ATTEST_EXPECTED_USER"]
expected_groups = sorted(set(json.loads(os.environ["NEMBRA_EXEC_ATTEST_EXPECTED_GROUPS_JSON"])))

real_uid = os.getuid()
effective_uid = os.geteuid()
real_gid = os.getgid()
effective_gid = os.getegid()
raw_groups = sorted(set(os.getgroups()))
distinct_groups = sorted(group for group in raw_groups if group != gid)
try:
    resolved_user = pwd.getpwuid(real_uid).pw_name
except KeyError:
    resolved_user = "<unresolved>"

record = {
    "pid": os.getpid(),
    "realUID": real_uid,
    "effectiveUID": effective_uid,
    "realPrimaryGID": real_gid,
    "effectivePrimaryGID": effective_gid,
    "rawKernelSupplementaryGroups": raw_groups,
    "distinctSupplementaryGroups": distinct_groups,
    "expectedDistinctSupplementaryGroups": expected_groups,
    "resolvedUser": resolved_user,
}
identity_exact = (
    real_uid == uid
    and effective_uid == uid
    and real_gid == gid
    and effective_gid == gid
    and resolved_user == user
)
baseline_exact = distinct_groups == expected_groups
record["identityExact"] = identity_exact
record["directoryServiceBaselineExact"] = baseline_exact

if not identity_exact or not baseline_exact:
    record["payloadExecAttempted"] = False
    print(ERR + json.dumps(record, sort_keys=True), flush=True)
    raise SystemExit(86)

record["payloadExecAttempted"] = True
print(PRE + json.dumps(record, sort_keys=True), flush=True)
payload = os.environ["NEMBRA_EXEC_ATTEST_PAYLOAD_CODE"]
os.execve(
    "/usr/bin/python3",
    ["/usr/bin/python3", "-B", "-I", "-c", payload],
    os.environ,
)
raise SystemExit(87)
'''


def records(stdout: str, marker: str) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for line in stdout.splitlines():
        if not line.startswith(marker):
            continue
        try:
            value = json.loads(line[len(marker):])
        except json.JSONDecodeError as error:
            raise ProbeError(f"malformed {marker} record: {error}") from error
        if not isinstance(value, dict):
            raise ProbeError(f"{marker} record is not a JSON object")
        result.append(value)
    return result


def normalized_groups(record: dict[str, Any], primary_gid: int) -> list[int]:
    raw = record.get("rawKernelSupplementaryGroups")
    if not isinstance(raw, list) or any(not isinstance(value, int) for value in raw):
        raise ProbeError("credential record did not contain an integer kernel group vector")
    return sorted({value for value in raw if value != primary_gid})


def run_exec_gate(
    helper,
    *,
    build_name: str,
    build_uid: int,
    build_gid: int,
    home: Path,
    expected_groups: list[int],
    token: str,
) -> subprocess.CompletedProcess[str]:
    environment = {
        "HOME": str(home),
        "USER": build_name,
        "LOGNAME": build_name,
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "TMPDIR": str(home),
        "LANG": "C",
        "LC_ALL": "C",
        "NEMBRA_EXEC_ATTEST_EXPECTED_UID": str(build_uid),
        "NEMBRA_EXEC_ATTEST_EXPECTED_GID": str(build_gid),
        "NEMBRA_EXEC_ATTEST_EXPECTED_USER": build_name,
        "NEMBRA_EXEC_ATTEST_EXPECTED_GROUPS_JSON": json.dumps(expected_groups, separators=(",", ":")),
        "NEMBRA_EXEC_ATTEST_PAYLOAD_CODE": payload_code(),
        "NEMBRA_EXEC_ATTEST_TOKEN": token,
    }
    return subprocess.run(
        ["/usr/bin/python3", "-B", "-I", "-c", launcher_code()],
        cwd=home,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        **helper._structured_credentials(build_uid, build_gid, ()),
    )


def choose_bogus_group(*occupied_sets: set[int]) -> int:
    occupied: set[int] = set()
    for values in occupied_sets:
        occupied.update(values)
    for candidate in range(63000, 65000):
        if candidate > 0 and candidate not in occupied:
            return candidate
    raise ProbeError("could not select one impossible expected group for negative control")


def root_probe(field_uid: int, field_gid: int, field_active_groups: list[int]) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "exec credential attestation requires sudo on real macOS")
        return 70
    try:
        sudo_uid = int(os.environ["SUDO_UID"])
        sudo_gid = int(os.environ["SUDO_GID"])
        sudo_user = os.environ["SUDO_USER"]
    except (KeyError, ValueError) as error:
        emit_error("identity", f"missing sudo invoking identity: {error}")
        return 71
    if sudo_uid != field_uid or sudo_gid != field_gid or field_uid <= 0 or field_gid <= 0:
        emit_error("identity", "root phase is not bound to exact pre-sudo UID/GID")
        return 71
    account = pwd.getpwuid(field_uid)
    if account.pw_name != sudo_user or account.pw_gid != field_gid:
        emit_error("identity", "sudo tuple does not resolve to the invoking field account")
        return 71
    if len(field_active_groups) != len(set(field_active_groups)):
        emit_error("identity", "pre-sudo active group vector contains duplicates")
        return 71
    if any(value <= 0 for value in field_active_groups) or field_gid in field_active_groups:
        emit_error("identity", "pre-sudo active group vector is invalid")
        return 71

    helper = load_production_helper()
    workspace = Path(tempfile.mkdtemp(prefix="nembra-exec-credential-attest.", dir="/private/tmp"))
    home = workspace / "home"
    build_name = f"nembraexec{os.getpid()}"
    build_uid: int | None = None
    identity_created = False
    try:
        build_uid = helper._choose_ephemeral_id()
        build_gid = build_uid
        home.mkdir()
        os.chown(workspace, 0, build_gid)
        os.chmod(workspace, 0o710)
        helper._create_local_build_identity(build_name, build_uid, build_gid, home)
        identity_created = True
        os.chown(home, build_uid, build_gid)
        os.chmod(home, 0o700)

        if build_uid == field_uid or build_gid == field_gid or build_gid in field_active_groups:
            raise ProbeError("fresh build identity overlaps field authority")

        directory_groups = sorted(set(os.getgrouplist(build_name, build_gid)))
        if build_gid not in directory_groups or any(value <= 0 for value in directory_groups):
            raise ProbeError("fresh build Directory Services baseline is invalid")
        directory_distinct = sorted({value for value in directory_groups if value != build_gid})
        field_baseline = {field_gid, *field_active_groups}
        field_only = sorted(field_baseline.difference(directory_groups))

        token = secrets.token_hex(16)
        positive = run_exec_gate(
            helper,
            build_name=build_name,
            build_uid=build_uid,
            build_gid=build_gid,
            home=home,
            expected_groups=directory_distinct,
            token=token,
        )
        positive_pre = records(positive.stdout, PREEXEC_MARKER)
        positive_post = records(positive.stdout, POSTEXEC_MARKER)
        positive_errors = records(positive.stdout, ATTEST_ERROR_MARKER)
        if positive.returncode != 0 or len(positive_pre) != 1 or len(positive_post) != 1 or positive_errors:
            raise ProbeError(
                "positive exec gate failed: "
                f"rc={positive.returncode} stdout={positive.stdout[-3000:]!r} stderr={positive.stderr[-3000:]!r}"
            )
        pre = positive_pre[0]
        post = positive_post[0]
        pre_groups = normalized_groups(pre, build_gid)
        post_groups = normalized_groups(post, build_gid)
        pre_identity_exact = (
            pre.get("realUID") == build_uid
            and pre.get("effectiveUID") == build_uid
            and pre.get("realPrimaryGID") == build_gid
            and pre.get("effectivePrimaryGID") == build_gid
            and pre.get("resolvedUser") == build_name
            and pre.get("identityExact") is True
        )
        post_identity_exact = (
            post.get("realUID") == build_uid
            and post.get("effectiveUID") == build_uid
            and post.get("realPrimaryGID") == build_gid
            and post.get("effectivePrimaryGID") == build_gid
            and post.get("resolvedUser") == build_name
        )
        pre_baseline_exact = pre_groups == directory_distinct and pre.get("directoryServiceBaselineExact") is True
        post_baseline_exact = post_groups == directory_distinct
        same_pid = pre.get("pid") == post.get("pid") and isinstance(pre.get("pid"), int)
        token_exact = post.get("token") == token and post.get("execPayloadRan") is True
        field_only_leaked_pre = sorted(set(pre_groups).intersection(field_only))
        field_only_leaked_post = sorted(set(post_groups).intersection(field_only))

        bogus = choose_bogus_group(set(directory_groups), field_baseline)
        negative_expected = sorted({*directory_distinct, bogus})
        negative = run_exec_gate(
            helper,
            build_name=build_name,
            build_uid=build_uid,
            build_gid=build_gid,
            home=home,
            expected_groups=negative_expected,
            token=secrets.token_hex(16),
        )
        negative_pre = records(negative.stdout, PREEXEC_MARKER)
        negative_post = records(negative.stdout, POSTEXEC_MARKER)
        negative_errors = records(negative.stdout, ATTEST_ERROR_MARKER)
        negative_rejected = negative.returncode != 0 and len(negative_errors) == 1
        negative_payload_suppressed = not negative_pre and not negative_post

        accepted = (
            pre_identity_exact
            and post_identity_exact
            and pre_baseline_exact
            and post_baseline_exact
            and same_pid
            and token_exact
            and not field_only_leaked_pre
            and not field_only_leaked_post
            and negative_rejected
            and negative_payload_suppressed
        )
        evidence = {
            "schemaVersion": 1,
            "fieldUID": field_uid,
            "fieldPrimaryGID": field_gid,
            "fieldActiveSupplementaryGroups": field_active_groups,
            "buildUser": build_name,
            "buildUID": build_uid,
            "buildPrimaryGID": build_gid,
            "buildDirectoryServiceGroups": directory_groups,
            "buildDirectoryServiceDistinctSupplementaryGroups": directory_distinct,
            "fieldOnlyGroups": field_only,
            "preExecIdentityExact": pre_identity_exact,
            "postExecIdentityExact": post_identity_exact,
            "preExecDirectoryServiceBaselineExact": pre_baseline_exact,
            "postExecDirectoryServiceBaselineExact": post_baseline_exact,
            "samePIDAcrossExec": same_pid,
            "execPayloadTokenBound": token_exact,
            "preExecFieldOnlyGroupsLeaked": field_only_leaked_pre,
            "postExecFieldOnlyGroupsLeaked": field_only_leaked_post,
            "negativeUnexpectedGroup": bogus,
            "negativeUnexpectedGroupRejected": negative_rejected,
            "negativePayloadSuppressed": negative_payload_suppressed,
            "effectiveZeroSupplementaryGroupsClaim": directory_distinct == [],
            "execBoundCredentialAttestationAccepted": accepted,
            "privateTuyaInputExercised": False,
            "appleIdentityExercised": False,
            "xcodebuildExercised": False,
            "provisioningExercised": False,
            "deviceInstallExercised": False,
            "bluetoothExercised": False,
            "physicalAuthorityCreated": False,
        }
        print(RESULT_MARKER + json.dumps(evidence, sort_keys=True))
        if not accepted:
            emit_error("acceptance", "exec-bound dedicated-UID credential contract was not established", evidence=evidence)
            return 72
        return 0
    except (OSError, KeyError, ProbeError, subprocess.CalledProcessError) as error:
        emit_error("fixture", f"exec credential attestation failed: {type(error).__name__}: {error}")
        return 79
    finally:
        if identity_created:
            try:
                helper._remove_local_build_identity(build_name, build_uid)
            except Exception:
                pass
        shutil.rmtree(workspace, ignore_errors=True)


def parent_probe() -> int:
    if sys.platform != "darwin":
        emit_error("environment", "exec credential attestation requires macOS")
        return 80
    field_uid = os.getuid()
    field_gid = os.getgid()
    if field_uid <= 0 or field_gid <= 0 or os.geteuid() != field_uid or os.getegid() != field_gid:
        emit_error("identity", "parent requires one stable non-root invoking identity")
        return 80
    active = sorted({value for value in os.getgroups() if value != field_gid})
    if any(value <= 0 for value in active):
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
    active_args = [item for value in active for item in ("--field-active-group", str(value))]
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

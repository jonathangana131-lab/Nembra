#!/usr/bin/env python3
"""Attest fail-closed retirement of a dedicated Capture build principal on macOS.

This validation is intentionally outside production. It measures three independent
postconditions after a fresh hidden build UID/GID is retired:
1. no non-zombie process remains under the numeric build UID;
2. the local Directory Services user/group records are gone;
3. name + numeric pwd/grp lookups are gone after bounded cache-flushed convergence.

A direct-child zombie is recorded separately because it has no executable/open-FD
runtime authority and is reaped before final success. A second principal is only
partially deleted (user removed, group retained) and must remain rejected.

No Xcode build, signing, private Tuya input, install, device, Bluetooth, telemetry,
command, or physical authority is created.
"""
from __future__ import annotations

import argparse
import grp
import json
import os
from pathlib import Path
import pwd
import subprocess
import sys
import tempfile
import time

SUCCESS_MARKER = "NEMBRA_DEDICATED_UID_PRINCIPAL_RETIREMENT_JSON="
ERROR_MARKER = "NEMBRA_DEDICATED_UID_PRINCIPAL_RETIREMENT_ERROR="


class ProbeError(RuntimeError):
    pass


def emit_error(kind: str, message: str, **extra: object) -> None:
    payload: dict[str, object] = {"kind": kind, "message": message, "physicalAuthorityCreated": False}
    payload.update(extra)
    print(ERROR_MARKER + json.dumps(payload, sort_keys=True), file=sys.stderr)


def run(argv: list[str], *, check: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=check,
    )


def flush_directory_cache() -> None:
    run(["/usr/bin/dscacheutil", "-flushcache"])


def cleanup_best_effort(name: str, uid: int) -> None:
    run(["/usr/bin/pkill", "-9", "-u", str(uid)])
    run(["/usr/bin/dscl", ".", "-delete", f"/Users/{name}"])
    run(["/usr/bin/dscl", ".", "-delete", f"/Groups/{name}"])
    flush_directory_cache()


def id_in_use(candidate: int) -> bool:
    try:
        pwd.getpwuid(candidate)
        return True
    except KeyError:
        pass
    try:
        grp.getgrgid(candidate)
        return True
    except KeyError:
        return False


def choose_ephemeral_id(offset: int = 0) -> int:
    start = 52000 + ((os.getpid() + offset) % 7000)
    for candidate in list(range(start, 62000)) + list(range(52000, start)):
        if candidate > 0 and not id_in_use(candidate):
            return candidate
    raise ProbeError("could not allocate isolated ephemeral UID/GID")


def create_identity(name: str, uid: int) -> None:
    if uid <= 0:
        raise ProbeError("dedicated principal requires a positive UID/GID")
    for kind in ("Users", "Groups"):
        if run(["/usr/bin/dscl", ".", "-read", f"/{kind}/{name}"]).returncode == 0:
            raise ProbeError(f"dedicated principal {kind.lower()} name already exists")
    try:
        commands = (
            ["/usr/bin/dscl", ".", "-create", f"/Groups/{name}"],
            ["/usr/bin/dscl", ".", "-create", f"/Groups/{name}", "PrimaryGroupID", str(uid)],
            ["/usr/bin/dscl", ".", "-create", f"/Groups/{name}", "RealName", "Nembra Capture Retirement Probe"],
            ["/usr/bin/dscl", ".", "-create", f"/Users/{name}"],
            ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UniqueID", str(uid)],
            ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "PrimaryGroupID", str(uid)],
            ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "NFSHomeDirectory", "/var/empty"],
            ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UserShell", "/usr/bin/false"],
            ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "RealName", "Nembra Capture Retirement Probe"],
            ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "IsHidden", "1"],
        )
        for command in commands:
            run(command, check=True)
        flush_directory_cache()
        deadline = time.monotonic() + 3.0
        while time.monotonic() < deadline:
            try:
                account = pwd.getpwnam(name)
                group = grp.getgrnam(name)
            except KeyError:
                time.sleep(0.05)
                continue
            if account.pw_uid == uid and account.pw_gid == uid and group.gr_gid == uid:
                return
            raise ProbeError("Directory Services materialized the wrong dedicated numeric identity")
        raise ProbeError("Directory Services did not materialize the dedicated principal")
    except Exception:
        cleanup_best_effort(name, uid)
        raise


def ds_record_resolved(kind: str, name: str) -> tuple[bool, int, str]:
    completed = run(["/usr/bin/dscl", ".", "-read", f"/{kind}/{name}"])
    detail = ((completed.stdout or "") + "\n" + (completed.stderr or "")).strip()
    if completed.returncode == 0:
        return True, 0, detail[-1000:]
    if "eDSRecordNotFound" in detail or "-14136" in detail:
        return False, completed.returncode, detail[-1000:]
    raise ProbeError(f"could not classify Directory Services {kind} record: rc={completed.returncode} {detail[-1000:]!r}")


def process_state_for_uid(uid: int) -> tuple[list[int], list[int], dict[str, str]]:
    completed = run(["/bin/ps", "-axo", "pid=,uid=,state="])
    if completed.returncode != 0:
        raise ProbeError(f"could not inspect process table: {completed.stderr[-1000:]!r}")
    live: list[int] = []
    zombies: list[int] = []
    states: dict[str, str] = {}
    for line in completed.stdout.splitlines():
        parts = line.split()
        if len(parts) < 3:
            continue
        try:
            pid, owner = int(parts[0]), int(parts[1])
        except ValueError:
            continue
        if owner != uid:
            continue
        state = parts[2]
        states[str(pid)] = state
        if state.upper().startswith("Z"):
            zombies.append(pid)
        else:
            live.append(pid)
    return sorted(live), sorted(zombies), states


def lookup_state(name: str, uid: int) -> dict[str, object]:
    state: dict[str, object] = {}
    for key, lookup, value in (
        ("userNameResolved", pwd.getpwnam, name),
        ("groupNameResolved", grp.getgrnam, name),
        ("uidResolved", pwd.getpwuid, uid),
        ("gidResolved", grp.getgrgid, uid),
    ):
        try:
            subject = lookup(value)
        except KeyError:
            state[key] = False
        else:
            state[key] = True
            state[key + "As"] = getattr(subject, "pw_name", getattr(subject, "gr_name", "<unknown>"))
    user_record, user_rc, user_detail = ds_record_resolved("Users", name)
    group_record, group_rc, group_detail = ds_record_resolved("Groups", name)
    live, zombies, process_states = process_state_for_uid(uid)
    state.update(
        {
            "userDirectoryServiceRecordResolved": user_record,
            "groupDirectoryServiceRecordResolved": group_record,
            "userDirectoryServiceReadReturnCode": user_rc,
            "groupDirectoryServiceReadReturnCode": group_rc,
            "userDirectoryServiceReadTail": user_detail,
            "groupDirectoryServiceReadTail": group_detail,
            "liveUIDProcesses": live,
            "zombieUIDProcesses": zombies,
            "uidProcessStates": process_states,
        }
    )
    resolved = any(
        bool(state.get(key))
        for key in (
            "userNameResolved",
            "groupNameResolved",
            "uidResolved",
            "gidResolved",
            "userDirectoryServiceRecordResolved",
            "groupDirectoryServiceRecordResolved",
        )
    )
    state["retirementAccepted"] = not live and not resolved
    return state


def wait_for_retirement(name: str, uid: int, timeout: float = 6.0) -> dict[str, object]:
    deadline = time.monotonic() + timeout
    latest: dict[str, object] = {}
    while time.monotonic() < deadline:
        latest = lookup_state(name, uid)
        if latest["retirementAccepted"]:
            return latest
        flush_directory_cache()
        time.sleep(0.05)
    return lookup_state(name, uid)


def retire_identity(name: str, uid: int) -> tuple[dict[str, int], dict[str, object]]:
    pkill = run(["/usr/bin/pkill", "-9", "-u", str(uid)])
    if pkill.returncode not in (0, 1):
        raise ProbeError(f"build-UID pkill failed: rc={pkill.returncode} {pkill.stderr[-1000:]!r}")
    user_delete = run(["/usr/bin/dscl", ".", "-delete", f"/Users/{name}"])
    group_delete = run(["/usr/bin/dscl", ".", "-delete", f"/Groups/{name}"])
    commands = {
        "pkillReturnCode": pkill.returncode,
        "userDeleteReturnCode": user_delete.returncode,
        "groupDeleteReturnCode": group_delete.returncode,
    }
    if user_delete.returncode != 0 or group_delete.returncode != 0:
        raise ProbeError(f"dedicated principal delete command failed: {commands}")
    flush_directory_cache()
    final_state = wait_for_retirement(name, uid)
    if not final_state["retirementAccepted"]:
        raise ProbeError(f"dedicated principal survived checked retirement: commands={commands} state={final_state}")
    return commands, final_state


def root_probe(field_uid: int, field_gid: int) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "principal-retirement validation requires root on real macOS")
        return 70
    try:
        sudo_uid = int(os.environ["SUDO_UID"])
        sudo_gid = int(os.environ["SUDO_GID"])
        sudo_user = os.environ["SUDO_USER"]
    except (KeyError, ValueError) as error:
        emit_error("identity", f"missing sudo invoking identity: {error}")
        return 71
    if sudo_uid != field_uid or sudo_gid != field_gid or field_uid <= 0 or field_gid <= 0:
        emit_error("identity", "root phase is not bound to exact pre-sudo field UID/GID")
        return 71
    account = pwd.getpwuid(field_uid)
    if account.pw_name != sudo_user or account.pw_gid != field_gid:
        emit_error("identity", "sudo tuple does not resolve to the exact field account")
        return 71

    positive_name = f"nembrartp{os.getpid()}"
    partial_name = f"nembrartn{os.getpid()}"
    positive_uid = choose_ephemeral_id(0)
    partial_uid = choose_ephemeral_id(101)
    if partial_uid == positive_uid:
        partial_uid = choose_ephemeral_id(503)
    positive_created = False
    partial_created = False
    sleeper: subprocess.Popen[str] | None = None
    workspace = Path(tempfile.mkdtemp(prefix="nembra-principal-retirement.", dir="/private/tmp"))
    try:
        create_identity(positive_name, positive_uid)
        positive_created = True
        create_identity(partial_name, partial_uid)
        partial_created = True

        sleeper = subprocess.Popen(
            ["/bin/sleep", "120"],
            cwd=workspace,
            env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/var/empty", "TMPDIR": "/tmp"},
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
            user=positive_uid,
            group=positive_uid,
            extra_groups=[],
        )
        time.sleep(0.15)
        prestate = lookup_state(positive_name, positive_uid)
        if prestate["retirementAccepted"] or sleeper.pid not in prestate["liveUIDProcesses"]:
            raise ProbeError(f"live-principal negative did not fail closed: {prestate}")

        commands, retirement_state = retire_identity(positive_name, positive_uid)
        positive_created = False
        sleeper.wait(timeout=2.0)
        post_reap_state = lookup_state(positive_name, positive_uid)
        if not post_reap_state["retirementAccepted"] or post_reap_state["liveUIDProcesses"] or post_reap_state["zombieUIDProcesses"]:
            raise ProbeError(f"reaped positive principal did not remain retired: {post_reap_state}")

        user_only = run(["/usr/bin/dscl", ".", "-delete", f"/Users/{partial_name}"])
        if user_only.returncode != 0:
            raise ProbeError(f"partial user delete failed: rc={user_only.returncode} {user_only.stderr[-1000:]!r}")
        flush_directory_cache()
        deadline = time.monotonic() + 2.0
        partial_state = lookup_state(partial_name, partial_uid)
        while time.monotonic() < deadline and partial_state["userDirectoryServiceRecordResolved"]:
            flush_directory_cache()
            time.sleep(0.05)
            partial_state = lookup_state(partial_name, partial_uid)
        if partial_state["retirementAccepted"]:
            raise ProbeError(f"partial user-only deletion was incorrectly accepted: {partial_state}")
        if partial_state["userDirectoryServiceRecordResolved"] or not partial_state["groupDirectoryServiceRecordResolved"]:
            raise ProbeError(f"partial control did not establish user-gone/group-survives state: {partial_state}")

        group_cleanup = run(["/usr/bin/dscl", ".", "-delete", f"/Groups/{partial_name}"])
        if group_cleanup.returncode != 0:
            raise ProbeError(f"partial group cleanup failed: rc={group_cleanup.returncode} {group_cleanup.stderr[-1000:]!r}")
        flush_directory_cache()
        partial_final = wait_for_retirement(partial_name, partial_uid)
        if not partial_final["retirementAccepted"]:
            raise ProbeError(f"partial-control principal could not fully retire: {partial_final}")
        partial_created = False

        evidence = {
            "schemaVersion": 2,
            "fieldUID": field_uid,
            "fieldPrimaryGID": field_gid,
            "positiveBuildUser": positive_name,
            "positiveBuildUID": positive_uid,
            "livePrincipalRejectedBeforeCleanup": True,
            "livePrincipalPreCleanupState": prestate,
            "checkedRetirementCommands": commands,
            "checkedRetirementStateBeforeDirectChildReap": retirement_state,
            "checkedRetirementStateAfterDirectChildReap": post_reap_state,
            "zombieClassifiedNonAuthoritative": True,
            "partialUserOnlyDeleteReturnCode": user_only.returncode,
            "partialGroupSurvivalRejected": True,
            "partialRetirementState": partial_state,
            "partialFinalState": partial_final,
            "principalRetirementAccepted": True,
            "productionBytesChanged": False,
            "productionAcceptanceClaimed": False,
            "physicalAuthorityCreated": False,
        }
        print(SUCCESS_MARKER + json.dumps(evidence, sort_keys=True))
        return 0
    except (OSError, KeyError, ProbeError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        emit_error("retirement", f"dedicated principal retirement witness failed: {type(error).__name__}: {error}")
        return 79
    finally:
        if sleeper is not None:
            if sleeper.poll() is None:
                try:
                    sleeper.kill()
                except ProcessLookupError:
                    pass
            try:
                sleeper.wait(timeout=1.0)
            except Exception:
                pass
        if positive_created:
            cleanup_best_effort(positive_name, positive_uid)
        if partial_created:
            cleanup_best_effort(partial_name, partial_uid)
        try:
            import shutil
            shutil.rmtree(workspace, ignore_errors=True)
        except Exception:
            pass


def parent_probe() -> int:
    if sys.platform != "darwin":
        emit_error("environment", "principal-retirement validation requires macOS")
        return 80
    field_uid = os.getuid()
    field_gid = os.getgid()
    if field_uid <= 0 or field_gid <= 0 or os.geteuid() != field_uid or os.getegid() != field_gid:
        emit_error("identity", "parent requires one stable non-root invoking identity")
        return 80
    if run(["/usr/bin/sudo", "-n", "/usr/bin/true"]).returncode != 0:
        emit_error("environment", "runner lacks noninteractive sudo required for validation")
        return 80
    completed = run(
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
        ]
    )
    sys.stdout.write(completed.stdout)
    sys.stderr.write(completed.stderr)
    return completed.returncode


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    parser.add_argument("--field-uid", type=int)
    parser.add_argument("--field-primary-gid", type=int)
    args = parser.parse_args()
    if args.root_probe:
        if args.field_uid is None or args.field_primary_gid is None:
            emit_error("arguments", "root probe requires exact pre-sudo UID/GID")
            return 83
        return root_probe(args.field_uid, args.field_primary_gid)
    if args.field_uid is not None or args.field_primary_gid is not None:
        emit_error("arguments", "root-only identity arguments are unavailable in parent mode")
        return 83
    return parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Prove fail-closed retirement of a dedicated Capture build principal on macOS.

Production #3142 creates one hidden local build user/group, then currently removes
that principal through best-effort pkill/dscl cleanup. This validation isolates the
missing lifecycle postcondition without changing production bytes.

The witness requires all of the following on real macOS:
- the root phase is bound to the exact pre-sudo non-root field UID/GID;
- a fresh dedicated UID/GID is materialized as a hidden local user/group;
- a real process running as that UID makes retirement verification fail closed;
- retirement kills every process owned by the UID, checks user and group deletion,
  flushes Directory Services caches, and waits until name + numeric identity lookups
  are all unresolved;
- a deliberately partial cleanup that deletes the user but leaves the group is
  rejected by the same postcondition before final cleanup.

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
    payload: dict[str, object] = {
        "kind": kind,
        "message": message,
        "physicalAuthorityCreated": False,
    }
    payload.update(extra)
    print(ERROR_MARKER + json.dumps(payload, sort_keys=True), file=sys.stderr)


def run_checked(argv: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )


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


def flush_directory_cache() -> None:
    subprocess.run(
        ["/usr/bin/dscacheutil", "-flushcache"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )


def cleanup_best_effort(name: str, uid: int) -> None:
    subprocess.run(
        ["/usr/bin/pkill", "-9", "-u", str(uid)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    subprocess.run(
        ["/usr/bin/dscl", ".", "-delete", f"/Users/{name}"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    subprocess.run(
        ["/usr/bin/dscl", ".", "-delete", f"/Groups/{name}"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    flush_directory_cache()


def create_identity(name: str, uid: int, gid: int) -> None:
    if uid <= 0 or gid <= 0 or uid != gid:
        raise ProbeError("dedicated principal requires one positive equal UID/GID")
    for kind in ("Users", "Groups"):
        existing = subprocess.run(
            ["/usr/bin/dscl", ".", "-read", f"/{kind}/{name}"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if existing.returncode == 0:
            raise ProbeError(f"dedicated principal {kind.lower()} name already exists")

    try:
        run_checked(["/usr/bin/dscl", ".", "-create", f"/Groups/{name}"])
        run_checked(["/usr/bin/dscl", ".", "-create", f"/Groups/{name}", "PrimaryGroupID", str(gid)])
        run_checked(["/usr/bin/dscl", ".", "-create", f"/Groups/{name}", "RealName", "Nembra Capture Retirement Probe"])
        run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}"])
        run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UniqueID", str(uid)])
        run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "PrimaryGroupID", str(gid)])
        run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "NFSHomeDirectory", "/var/empty"])
        run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UserShell", "/usr/bin/false"])
        run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "RealName", "Nembra Capture Retirement Probe"])
        run_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "IsHidden", "1"])
        flush_directory_cache()

        deadline = time.monotonic() + 3.0
        while time.monotonic() < deadline:
            try:
                account = pwd.getpwnam(name)
                group = grp.getgrnam(name)
            except KeyError:
                time.sleep(0.05)
                continue
            if account.pw_uid == uid and account.pw_gid == gid and group.gr_gid == gid:
                return
            raise ProbeError("Directory Services materialized the dedicated principal with the wrong numeric identity")
        raise ProbeError("Directory Services did not materialize the dedicated principal")
    except Exception:
        cleanup_best_effort(name, uid)
        raise


def lookup_state(name: str, uid: int, gid: int) -> dict[str, object]:
    state: dict[str, object] = {}
    for key, lookup, value in (
        ("userNameResolved", pwd.getpwnam, name),
        ("groupNameResolved", grp.getgrnam, name),
        ("uidResolved", pwd.getpwuid, uid),
        ("gidResolved", grp.getgrgid, gid),
    ):
        try:
            subject = lookup(value)
        except KeyError:
            state[key] = False
        else:
            state[key] = True
            state[key + "As"] = getattr(subject, "pw_name", getattr(subject, "gr_name", "<unknown>"))
    return state


def live_processes_for_uid(uid: int) -> list[int]:
    completed = subprocess.run(
        ["/bin/ps", "-axo", "pid=,uid="],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise ProbeError(f"could not inspect process table for build UID: {completed.stderr[-1000:]!r}")
    result: list[int] = []
    for line in completed.stdout.splitlines():
        parts = line.split()
        if len(parts) != 2:
            continue
        try:
            pid, owner = int(parts[0]), int(parts[1])
        except ValueError:
            continue
        if owner == uid:
            result.append(pid)
    return sorted(result)


def verify_retired(name: str, uid: int, gid: int) -> tuple[bool, dict[str, object]]:
    state = lookup_state(name, uid, gid)
    live = live_processes_for_uid(uid)
    state["liveUIDProcesses"] = live
    accepted = not live and not any(
        bool(state.get(key))
        for key in ("userNameResolved", "groupNameResolved", "uidResolved", "gidResolved")
    )
    state["retirementAccepted"] = accepted
    return accepted, state


def wait_for_retirement(name: str, uid: int, gid: int, timeout: float = 4.0) -> tuple[bool, dict[str, object]]:
    deadline = time.monotonic() + timeout
    latest: dict[str, object] = {}
    while time.monotonic() < deadline:
        accepted, latest = verify_retired(name, uid, gid)
        if accepted:
            return True, latest
        flush_directory_cache()
        time.sleep(0.05)
    accepted, latest = verify_retired(name, uid, gid)
    return accepted, latest


def retire_identity(name: str, uid: int, gid: int) -> dict[str, object]:
    pkill = subprocess.run(
        ["/usr/bin/pkill", "-9", "-u", str(uid)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if pkill.returncode not in (0, 1):
        raise ProbeError(f"build-UID process retirement failed: rc={pkill.returncode} {pkill.stderr[-1000:]!r}")

    user_delete = subprocess.run(
        ["/usr/bin/dscl", ".", "-delete", f"/Users/{name}"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    group_delete = subprocess.run(
        ["/usr/bin/dscl", ".", "-delete", f"/Groups/{name}"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if user_delete.returncode != 0 or group_delete.returncode != 0:
        raise ProbeError(
            "dedicated principal deletion command failed: "
            f"user_rc={user_delete.returncode} group_rc={group_delete.returncode} "
            f"user_err={user_delete.stderr[-600:]!r} group_err={group_delete.stderr[-600:]!r}"
        )
    flush_directory_cache()
    accepted, final_state = wait_for_retirement(name, uid, gid)
    if not accepted:
        raise ProbeError(f"dedicated principal survived checked retirement: {final_state}")
    return {
        "pkillReturnCode": pkill.returncode,
        "userDeleteReturnCode": user_delete.returncode,
        "groupDeleteReturnCode": group_delete.returncode,
        "finalState": final_state,
    }


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
        emit_error("identity", "root phase is not bound to the exact pre-sudo field UID/GID")
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
        create_identity(positive_name, positive_uid, positive_uid)
        positive_created = True
        create_identity(partial_name, partial_uid, partial_uid)
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
        if sleeper.poll() is not None:
            raise ProbeError("dedicated build-UID sentinel process exited before retirement test")

        preaccepted, prestate = verify_retired(positive_name, positive_uid, positive_uid)
        if preaccepted or sleeper.pid not in prestate.get("liveUIDProcesses", []):
            raise ProbeError(f"live-principal negative control did not fail closed: {prestate}")

        positive = retire_identity(positive_name, positive_uid, positive_uid)
        positive_created = False
        try:
            sleeper.wait(timeout=2.0)
        except subprocess.TimeoutExpired as error:
            raise ProbeError("retired build-UID sentinel process remained alive") from error

        user_only = subprocess.run(
            ["/usr/bin/dscl", ".", "-delete", f"/Users/{partial_name}"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if user_only.returncode != 0:
            raise ProbeError(f"partial-retirement negative could not delete user: {user_only.stderr[-1000:]!r}")
        flush_directory_cache()
        partial_accepted = True
        partial_state: dict[str, object] = {}
        deadline = time.monotonic() + 2.0
        while time.monotonic() < deadline:
            partial_accepted, partial_state = verify_retired(partial_name, partial_uid, partial_uid)
            if not partial_state.get("userNameResolved") and not partial_state.get("uidResolved"):
                break
            flush_directory_cache()
            time.sleep(0.05)
        if partial_accepted or not partial_state.get("groupNameResolved") or not partial_state.get("gidResolved"):
            raise ProbeError(f"partial group-survival negative did not remain fail closed: {partial_state}")

        group_cleanup = subprocess.run(
            ["/usr/bin/dscl", ".", "-delete", f"/Groups/{partial_name}"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if group_cleanup.returncode != 0:
            raise ProbeError(f"negative-control group cleanup failed: {group_cleanup.stderr[-1000:]!r}")
        flush_directory_cache()
        partial_final_ok, partial_final = wait_for_retirement(partial_name, partial_uid, partial_uid)
        if not partial_final_ok:
            raise ProbeError(f"negative-control principal could not be fully retired: {partial_final}")
        partial_created = False

        evidence = {
            "schemaVersion": 1,
            "fieldUID": field_uid,
            "fieldPrimaryGID": field_gid,
            "positiveBuildUser": positive_name,
            "positiveBuildUID": positive_uid,
            "livePrincipalRejectedBeforeCleanup": True,
            "livePrincipalPreCleanupState": prestate,
            "checkedRetirement": positive,
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
    except (OSError, KeyError, ProbeError, subprocess.CalledProcessError) as error:
        emit_error("retirement", f"dedicated principal retirement witness failed: {type(error).__name__}: {error}")
        return 79
    finally:
        if sleeper is not None and sleeper.poll() is None:
            try:
                sleeper.kill()
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
    if subprocess.run(
        ["/usr/bin/sudo", "-n", "/usr/bin/true"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode != 0:
        emit_error("environment", "runner lacks noninteractive sudo required for validation")
        return 80
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

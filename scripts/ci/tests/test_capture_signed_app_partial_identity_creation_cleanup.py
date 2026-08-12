#!/usr/bin/env python3
"""Red-team the dedicated build identity partial-creation cleanup boundary.

This validation pins one production helper head and deliberately creates a real,
uniquely named local group on macOS. It then injects a failure in the *next*
Directory Services creation command and denies the helper's best-effort group
delete. The current production exception path is expected to re-raise without
verifying absence, so the group record remains observable.

The validator always restores the real subprocess implementation and performs
trusted cleanup with direct dscl calls before it can report success. A green
validation run therefore means the pinned production parent was mechanically
shown RED at this cleanup boundary; it is not product acceptance.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from typing import Any

HERE = Path(__file__).resolve().parent
PRODUCTION_HELPER = HERE.parent / "capture_signed_app_build_origin_custody.py"
RESULT_MARKER = "NEMBRA_PARTIAL_IDENTITY_CLEANUP_REDTEAM_JSON="
ERROR_MARKER = "NEMBRA_PARTIAL_IDENTITY_CLEANUP_REDTEAM_ERROR="


class ProbeError(RuntimeError):
    pass


def emit_error(kind: str, message: str, **extra: object) -> None:
    payload: dict[str, object] = {
        "kind": kind,
        "message": message,
        "productionAcceptanceClaimed": False,
        "physicalAuthorityCreated": False,
    }
    payload.update(extra)
    print(ERROR_MARKER + json.dumps(payload, sort_keys=True), file=sys.stderr)


def load_helper():
    spec = importlib.util.spec_from_file_location(
        "nembra_capture_build_origin_custody_partial_cleanup_probe",
        PRODUCTION_HELPER,
    )
    if spec is None or spec.loader is None:
        raise ProbeError("could not load pinned production helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def real_run(
    argv: list[str],
    *,
    check: bool = False,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=check,
    )


def ds_record_state(kind: str, name: str) -> dict[str, Any]:
    completed = real_run(["/usr/bin/dscl", ".", "-read", f"/{kind}/{name}"])
    detail = ((completed.stdout or "") + "\n" + (completed.stderr or "")).strip()
    if completed.returncode == 0:
        return {"exists": True, "returnCode": 0, "detailTail": detail[-800:]}
    if "eDSRecordNotFound" in detail or "-14136" in detail:
        return {
            "exists": False,
            "returnCode": completed.returncode,
            "detailTail": detail[-800:],
        }
    raise ProbeError(
        f"could not classify Directory Services {kind} record "
        f"rc={completed.returncode}: {detail[-800:]!r}"
    )


def trusted_cleanup(name: str, uid: int) -> dict[str, Any]:
    real_run(["/usr/bin/pkill", "-9", "-u", str(uid)])
    user_delete = real_run(["/usr/bin/dscl", ".", "-delete", f"/Users/{name}"])
    group_delete = real_run(["/usr/bin/dscl", ".", "-delete", f"/Groups/{name}"])
    real_run(["/usr/bin/dscacheutil", "-flushcache"])
    deadline = time.monotonic() + 4.0
    user_state: dict[str, Any] = {}
    group_state: dict[str, Any] = {}
    while time.monotonic() < deadline:
        user_state = ds_record_state("Users", name)
        group_state = ds_record_state("Groups", name)
        if not user_state["exists"] and not group_state["exists"]:
            break
        real_run(["/usr/bin/dscacheutil", "-flushcache"])
        time.sleep(0.05)
    user_state = ds_record_state("Users", name)
    group_state = ds_record_state("Groups", name)
    verified = not user_state["exists"] and not group_state["exists"]
    return {
        "userDeleteReturnCode": user_delete.returncode,
        "groupDeleteReturnCode": group_delete.returncode,
        "userState": user_state,
        "groupState": group_state,
        "verified": verified,
    }


def root_probe() -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "partial-creation cleanup red-team requires root on real macOS")
        return 70

    helper = load_helper()
    workspace = Path(tempfile.mkdtemp(prefix="nembra-partial-identity-cleanup.", dir="/private/tmp"))
    name = f"nembrapartial{os.getpid()}"
    uid = helper._choose_ephemeral_id()
    gid = uid
    home = workspace / "home"

    # Capture the function object before replacing the shared subprocess module's
    # run attribute. Calls through this saved object remain real system calls.
    actual_subprocess_run = subprocess.run
    injection = {
        "groupCreateReached": False,
        "creationFailureInjected": False,
        "groupDeleteSuppressed": False,
    }
    production_error = ""
    surviving_group: dict[str, Any] = {}
    cleanup: dict[str, Any] = {}

    def injected_run(argv, *args, **kwargs):
        command = [str(value) for value in argv]
        group_path = f"/Groups/{name}"
        if command == ["/usr/bin/dscl", ".", "-create", group_path]:
            completed = actual_subprocess_run(argv, *args, **kwargs)
            if completed.returncode == 0:
                injection["groupCreateReached"] = True
            return completed

        if (
            injection["groupCreateReached"]
            and not injection["creationFailureInjected"]
            and command[:4] == ["/usr/bin/dscl", ".", "-create", group_path]
            and len(command) > 4
        ):
            injection["creationFailureInjected"] = True
            raise subprocess.CalledProcessError(
                returncode=97,
                cmd=command,
                stderr="injected mid-creation failure",
            )

        if command == ["/usr/bin/dscl", ".", "-delete", group_path]:
            injection["groupDeleteSuppressed"] = True
            return subprocess.CompletedProcess(
                args=command,
                returncode=98,
                stdout="",
                stderr="injected cleanup delete denial",
            )

        return actual_subprocess_run(argv, *args, **kwargs)

    try:
        # helper.subprocess is the imported subprocess module object. Replacing
        # run here intentionally affects only this Python process; the saved
        # actual_subprocess_run function remains available for trusted cleanup.
        helper.subprocess.run = injected_run
        try:
            helper._create_local_build_identity(name, uid, gid, home)
        except Exception as error:
            production_error = f"{type(error).__name__}: {error}"
        else:
            raise ProbeError("production identity creation unexpectedly succeeded through injected failure")
        finally:
            helper.subprocess.run = actual_subprocess_run
            subprocess.run = actual_subprocess_run

        if not all(injection.values()):
            raise ProbeError(f"red-team injection did not exercise intended path: {injection}")

        surviving_group = ds_record_state("Groups", name)
        if not surviving_group["exists"]:
            raise ProbeError(
                "pinned production exception cleanup removed the partial group despite denied delete; "
                "parent is not vulnerable to this exact witness"
            )

        cleanup = trusted_cleanup(name, uid)
        if not cleanup["verified"]:
            raise ProbeError(f"trusted fixture cleanup could not verify record absence: {cleanup}")

        evidence = {
            "schemaVersion": 1,
            "productionHelper": str(PRODUCTION_HELPER.relative_to(HERE.parent.parent)),
            "probePrincipalName": name,
            "probeUIDGID": uid,
            "groupCreateReached": injection["groupCreateReached"],
            "midCreationFailureInjected": injection["creationFailureInjected"],
            "productionCleanupGroupDeleteSuppressed": injection["groupDeleteSuppressed"],
            "productionCreateRaised": bool(production_error),
            "productionCreateError": production_error,
            "survivingGroupRecordObserved": surviving_group["exists"],
            "parentExceptionCleanupFailClosed": False,
            "fixtureCleanupVerified": cleanup["verified"],
            "fixtureCleanup": cleanup,
            "productionBytesChanged": False,
            "productionAcceptanceClaimed": False,
            "physicalAuthorityCreated": False,
        }
        print(RESULT_MARKER + json.dumps(evidence, sort_keys=True))
        return 0
    except (OSError, KeyError, ProbeError, subprocess.CalledProcessError) as error:
        emit_error(
            "red-team",
            f"partial-creation cleanup red-team failed: {type(error).__name__}: {error}",
            injection=injection,
            survivingGroup=surviving_group,
            cleanup=cleanup,
        )
        return 79
    finally:
        helper.subprocess.run = actual_subprocess_run
        subprocess.run = actual_subprocess_run
        try:
            final_cleanup = trusted_cleanup(name, uid)
            if not final_cleanup["verified"]:
                emit_error("cleanup", "final fixture cleanup could not verify principal absence", cleanup=final_cleanup)
        except Exception as error:
            emit_error("cleanup", f"final fixture cleanup raised: {type(error).__name__}: {error}")
        try:
            workspace.rmdir()
        except OSError:
            pass


def parent_probe() -> int:
    if sys.platform != "darwin":
        emit_error("environment", "partial-creation cleanup red-team requires macOS")
        return 80
    if os.geteuid() == 0:
        emit_error("identity", "parent probe must start under the non-root runner identity")
        return 80
    sudo = real_run(["/usr/bin/sudo", "-n", "/usr/bin/true"])
    if sudo.returncode != 0:
        emit_error("environment", "runner lacks noninteractive sudo required for validation")
        return 80
    completed = real_run(
        [
            "/usr/bin/sudo",
            "-n",
            "/usr/bin/python3",
            "-B",
            "-I",
            str(Path(__file__).resolve()),
            "--root-probe",
        ]
    )
    sys.stdout.write(completed.stdout or "")
    sys.stderr.write(completed.stderr or "")
    return completed.returncode


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    args = parser.parse_args()
    return root_probe() if args.root_probe else parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())

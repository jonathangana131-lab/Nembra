#!/usr/bin/env python3
"""Real-macOS validation for Capture numeric build-principal allocation.

The production successor must not reuse a numeric UID/GID while any process still
owns that UID, even when pwd/grp and Directory Services have no principal record.
This witness creates such a numeric-only process without ever creating a local
account and exercises production's exact process-aware allocator.

Validation only. No production bytes, signing, device, Bluetooth, Tuya, telemetry,
command, or physical authority are changed or created.
"""

from __future__ import annotations

import argparse
import grp
import importlib.util
import json
import os
from pathlib import Path
import pwd
import signal
import subprocess
import sys
import time

SUCCESS_MARKER = "NEMBRA_LIVE_NUMERIC_UID_ALLOCATION_JSON="
ERROR_MARKER = "NEMBRA_LIVE_NUMERIC_UID_ALLOCATION_ERROR="
PRODUCTION = Path("scripts/ci/capture_signed_app_build_origin_custody.py")
LOW_UID = 52000
HIGH_UID_EXCLUSIVE = 59000


class ProbeError(RuntimeError):
    pass


def _run(argv: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )


def _load_production():
    spec = importlib.util.spec_from_file_location("nembra_build_origin_custody_validation", PRODUCTION)
    if spec is None or spec.loader is None:
        raise ProbeError("could not load current production build-origin helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    for name in ("_id_in_use", "_numeric_principal_in_use", "_choose_ephemeral_id"):
        if not callable(getattr(module, name, None)):
            raise ProbeError(f"production helper exposes no auditable {name} contract")
    return module


def _resolver_in_use(candidate: int) -> bool:
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


def _uid_processes(candidate: int) -> list[tuple[int, str]]:
    completed = _run(["/bin/ps", "-axo", "pid=,uid=,state="])
    if completed.returncode != 0:
        raise ProbeError(f"could not inspect process table: {completed.stderr[-1000:]!r}")
    matches: list[tuple[int, str]] = []
    for line in completed.stdout.splitlines():
        parts = line.split()
        if len(parts) < 3:
            continue
        try:
            pid = int(parts[0])
            uid = int(parts[1])
        except ValueError:
            continue
        if uid == candidate:
            matches.append((pid, parts[2]))
    return sorted(matches)


def _direct_ds_numeric_matches(kind: str, attribute: str, candidate: int) -> list[str]:
    completed = _run(["/usr/bin/dscl", ".", "-search", f"/{kind}", attribute, str(candidate)])
    if completed.returncode != 0:
        detail = ((completed.stdout or "") + "\n" + (completed.stderr or "")).strip()
        raise ProbeError(f"could not search Directory Services {kind}: {detail[-1000:]!r}")
    return [line.strip() for line in completed.stdout.splitlines() if line.strip()]


def _choose_clean_candidate() -> int:
    for candidate in range(LOW_UID, HIGH_UID_EXCLUSIVE):
        if _resolver_in_use(candidate) or _uid_processes(candidate):
            continue
        if _direct_ds_numeric_matches("Users", "UniqueID", candidate):
            continue
        if _direct_ds_numeric_matches("Groups", "PrimaryGroupID", candidate):
            continue
        return candidate
    raise ProbeError("could not find one unresolved, process-free validation UID/GID")


def _spawn_numeric_uid_sleeper(candidate: int) -> int:
    ready_read, ready_write = os.pipe()
    child = os.fork()
    if child == 0:
        try:
            os.close(ready_read)
            os.setgroups([])
            os.setgid(candidate)
            os.setuid(candidate)
            os.write(ready_write, b"R")
            os.close(ready_write)
            os.execve(
                "/bin/sleep",
                ["sleep", "120"],
                {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/var/empty", "TMPDIR": "/tmp"},
            )
        except BaseException:
            try:
                os.write(ready_write, b"E")
            except OSError:
                pass
            os._exit(111)
    os.close(ready_write)
    try:
        marker = os.read(ready_read, 1)
    finally:
        os.close(ready_read)
    if marker != b"R":
        try:
            os.waitpid(child, 0)
        except ChildProcessError:
            pass
        raise ProbeError("could not launch harmless process under unresolved numeric UID/GID")
    deadline = time.monotonic() + 2.0
    while time.monotonic() < deadline:
        state = _uid_processes(candidate)
        if any(pid == child and not value.upper().startswith("Z") for pid, value in state):
            return child
        waited, status = os.waitpid(child, os.WNOHANG)
        if waited == child:
            raise ProbeError(f"numeric-UID sleeper exited before validation: status={status}")
        time.sleep(0.02)
    raise ProbeError("numeric-UID sleeper did not become observable in the process table")


def _choose_starting_at(production, candidate: int) -> int:
    # Production starts at 52000 + (pid % 7000). Make this candidate the first
    # examined UID without changing production source or its authority predicate.
    original_getpid = production.os.getpid
    try:
        production.os.getpid = lambda: candidate - LOW_UID
        return int(production._choose_ephemeral_id())
    finally:
        production.os.getpid = original_getpid


def _wait_for_zombie(candidate: int, child: int) -> list[tuple[int, str]]:
    deadline = time.monotonic() + 2.0
    while time.monotonic() < deadline:
        state = _uid_processes(candidate)
        if any(pid == child and value.upper().startswith("Z") for pid, value in state):
            return state
        time.sleep(0.02)
    raise ProbeError("killed numeric-UID child did not become an observable zombie before reap")


def root_probe(field_uid: int, field_gid: int) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        raise ProbeError("live numeric UID validation requires root on real macOS")
    try:
        sudo_uid = int(os.environ["SUDO_UID"])
        sudo_gid = int(os.environ["SUDO_GID"])
    except (KeyError, ValueError) as error:
        raise ProbeError(f"missing exact pre-sudo field identity: {error}") from error
    if field_uid <= 0 or field_gid <= 0 or sudo_uid != field_uid or sudo_gid != field_gid:
        raise ProbeError("root witness is not bound to the exact pre-sudo field UID/GID")

    production = _load_production()
    candidate = _choose_clean_candidate()
    child: int | None = None
    try:
        if production._id_in_use(candidate) or production._numeric_principal_in_use(candidate):
            raise ProbeError("clean validation UID was unexpectedly occupied before control setup")

        child = _spawn_numeric_uid_sleeper(candidate)
        live_state = _uid_processes(candidate)
        if not any(pid == child and not value.upper().startswith("Z") for pid, value in live_state):
            raise ProbeError("live numeric UID control disappeared before allocator attack")
        if _resolver_in_use(candidate):
            raise ProbeError("numeric-only process unexpectedly became pwd/grp-resolvable")
        user_ds = _direct_ds_numeric_matches("Users", "UniqueID", candidate)
        group_ds = _direct_ds_numeric_matches("Groups", "PrimaryGroupID", candidate)
        if user_ds or group_ds:
            raise ProbeError(f"numeric-only process unexpectedly acquired DS records: {user_ds} {group_ds}")

        resolver_only_live = bool(production._id_in_use(candidate))
        process_aware_live = bool(production._numeric_principal_in_use(candidate))
        selected_while_live = _choose_starting_at(production, candidate)
        if resolver_only_live:
            raise ProbeError("control no longer isolates process-only numeric authority")
        if not process_aware_live or selected_while_live == candidate:
            raise ProbeError("production allocator failed to reject live unresolved numeric UID")

        os.kill(child, signal.SIGKILL)
        zombie_state = _wait_for_zombie(candidate, child)
        process_aware_zombie = bool(production._numeric_principal_in_use(candidate))
        selected_while_zombie = _choose_starting_at(production, candidate)
        if not process_aware_zombie or selected_while_zombie == candidate:
            raise ProbeError("production allocator failed to conservatively reject zombie numeric UID")

        os.waitpid(child, 0)
        child = None
        if _uid_processes(candidate):
            raise ProbeError("numeric validation process survived explicit reap")
        process_aware_after_reap = bool(production._numeric_principal_in_use(candidate))
        selected_after_reap = _choose_starting_at(production, candidate)
        if process_aware_after_reap or selected_after_reap != candidate:
            raise ProbeError("production allocator did not release process-free unresolved UID after reap")

        evidence = {
            "schemaVersion": 1,
            "fieldUID": field_uid,
            "fieldPrimaryGID": field_gid,
            "candidateUID": candidate,
            "candidateGID": candidate,
            "directoryServiceUserMatches": user_ds,
            "directoryServiceGroupMatches": group_ds,
            "resolverOnlyInUseWhileLive": resolver_only_live,
            "liveUIDProcesses": [{"pid": pid, "state": value} for pid, value in live_state],
            "processAwareInUseWhileLive": process_aware_live,
            "selectedUIDWhileLive": selected_while_live,
            "zombieUIDProcesses": [{"pid": pid, "state": value} for pid, value in zombie_state],
            "processAwareInUseWhileZombie": process_aware_zombie,
            "selectedUIDWhileZombie": selected_while_zombie,
            "processAwareInUseAfterReap": process_aware_after_reap,
            "selectedUIDAfterReap": selected_after_reap,
            "numericPrincipalAllocationAccepted": True,
            "productionBytesChanged": False,
            "productionAcceptanceClaimed": False,
            "physicalAuthorityCreated": False,
        }
        print(SUCCESS_MARKER + json.dumps(evidence, sort_keys=True))
        return 0
    finally:
        if child is not None:
            try:
                os.kill(child, signal.SIGKILL)
            except OSError:
                pass
            try:
                os.waitpid(child, 0)
            except ChildProcessError:
                pass


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    parser.add_argument("--field-uid", type=int)
    parser.add_argument("--field-gid", type=int)
    args = parser.parse_args(sys.argv[1:] if argv is None else argv)
    try:
        if not args.root_probe or args.field_uid is None or args.field_gid is None:
            raise ProbeError("validation entry requires --root-probe and exact field UID/GID")
        return root_probe(args.field_uid, args.field_gid)
    except (OSError, ProbeError, subprocess.SubprocessError) as error:
        print(
            ERROR_MARKER
            + json.dumps(
                {"kind": "validation", "message": str(error), "physicalAuthorityCreated": False},
                sort_keys=True,
            ),
            file=sys.stderr,
        )
        return 79


if __name__ == "__main__":
    raise SystemExit(main())

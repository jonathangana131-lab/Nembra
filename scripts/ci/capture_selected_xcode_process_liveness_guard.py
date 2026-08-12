#!/usr/bin/env python3
"""Fail-closed exact-process liveness guard for Capture selected-Xcode custody.

A lifecycle cleanup/recovery decision may destroy the only admitted frozen Xcode
subject for an active field shell. Therefore metadata inspection failure is never
proof of process absence. Only a kernel ProcessLookupError from kill(pid, 0) proves
that the numeric PID is currently absent. If the PID exists but its UID/start
identity no longer matches, the original exact process is gone (PID reuse) and the
old lifecycle may be retired.

This module is intentionally a narrow hardening shim while the freeze helper and
launcher remain additive review candidates. It patches their process-identity
oracles in-memory before any stale recovery or freeze construction is allowed.
No device, signing, Bluetooth, Tuya, telemetry, or scooter action occurs here.
"""

from __future__ import annotations

import os
from typing import Callable, MutableMapping, Type


class ProcessLivenessGuardError(RuntimeError):
    pass


def same_exact_process_fail_closed(
    pid: int,
    uid: int,
    start_identity: str,
    *,
    ps_value: Callable[[int, str], str],
    inspection_error: Type[BaseException],
    kill_probe: Callable[[int, int], None] = os.kill,
) -> bool:
    """Return False only when absence or exact-process replacement is proven.

    Ambiguous kernel/metadata failures return True so cleanup/recovery waits rather
    than destroying authority that may still belong to the active field shell.
    """
    if pid <= 1 or uid <= 0 or not start_identity:
        return True
    try:
        kill_probe(pid, 0)
    except ProcessLookupError:
        return False
    except (PermissionError, OSError):
        return True

    try:
        raw_uid = ps_value(pid, "uid")
        current_start = ps_value(pid, "lstart")
    except inspection_error:
        return True
    except (OSError, RuntimeError):
        return True

    # Malformed successful inspection is not absence evidence.
    if not raw_uid.isdigit() or not current_start:
        return True

    # A live PID with a different UID or kernel start identity is PID reuse: the
    # lifecycle's original exact process is definitely gone.
    return int(raw_uid) == uid and current_start == start_identity


def install_into_launcher(namespace: MutableMapping[str, object]) -> None:
    """Patch launcher stale recovery and every helper it loads before use."""
    ps_value = namespace.get("_ps_value")
    launcher_error = namespace.get("FreezeLauncherError")
    original_loader = namespace.get("_load_freeze_helper")
    if not callable(ps_value) or not isinstance(launcher_error, type) or not callable(original_loader):
        raise ProcessLivenessGuardError("freeze launcher does not expose the required liveness patch contract")

    def launcher_same(pid: int, uid: int, start_identity: str) -> bool:
        return same_exact_process_fail_closed(
            pid,
            uid,
            start_identity,
            ps_value=ps_value,  # type: ignore[arg-type]
            inspection_error=launcher_error,
        )

    def guarded_loader(encoded: str, expected_blob: str) -> dict[str, object]:
        helper = original_loader(encoded, expected_blob)  # type: ignore[operator]
        helper_ps = helper.get("_ps_value")
        helper_error = helper.get("SelectedXcodeFreezeError")
        if not callable(helper_ps) or not isinstance(helper_error, type):
            raise ProcessLivenessGuardError("freeze helper does not expose the required liveness patch contract")

        def helper_same(pid: int, uid: int, start_identity: str) -> bool:
            return same_exact_process_fail_closed(
                pid,
                uid,
                start_identity,
                ps_value=helper_ps,  # type: ignore[arg-type]
                inspection_error=helper_error,
            )

        helper["_field_process_is_same"] = helper_same
        return helper

    namespace["_same_field_process"] = launcher_same
    namespace["_load_freeze_helper"] = guarded_loader


def _self_test() -> None:
    class InspectionError(RuntimeError):
        pass

    def absent(_: int, __: int) -> None:
        raise ProcessLookupError

    def alive(_: int, __: int) -> None:
        return None

    def ambiguous(_: int, __: str) -> str:
        raise InspectionError("transient ps failure")

    values = {"uid": "501", "lstart": "Wed Aug 12 03:00:00 2026"}

    def exact(_: int, key: str) -> str:
        return values[key]

    if same_exact_process_fail_closed(
        99999, 501, values["lstart"], ps_value=exact, inspection_error=InspectionError, kill_probe=absent
    ):
        raise ProcessLivenessGuardError("definite kernel absence was not classified absent")
    if not same_exact_process_fail_closed(
        123, 501, values["lstart"], ps_value=ambiguous, inspection_error=InspectionError, kill_probe=alive
    ):
        raise ProcessLivenessGuardError("ambiguous live-PID inspection was incorrectly classified absent")
    if not same_exact_process_fail_closed(
        123, 501, values["lstart"], ps_value=exact, inspection_error=InspectionError, kill_probe=alive
    ):
        raise ProcessLivenessGuardError("matching exact process was not classified live")
    if same_exact_process_fail_closed(
        123, 502, values["lstart"], ps_value=exact, inspection_error=InspectionError, kill_probe=alive
    ):
        raise ProcessLivenessGuardError("PID reuse by another UID was not classified retired")
    if same_exact_process_fail_closed(
        123, 501, "different-start", ps_value=exact, inspection_error=InspectionError, kill_probe=alive
    ):
        raise ProcessLivenessGuardError("PID reuse by another start identity was not classified retired")


if __name__ == "__main__":
    _self_test()
    print("CAPTURE_SELECTED_XCODE_LIVENESS_GUARD_SELF_TEST_ACCEPTED physicalAuthorityCreated=false")

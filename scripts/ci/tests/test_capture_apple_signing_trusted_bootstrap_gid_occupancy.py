#!/usr/bin/env python3
"""Expected-red adversary for trusted-bootstrap numeric GID authority.

The parent hardening witness allocates one numeric value as both UID and GID. This validation
requires that numeric freshness and retirement treat primary/supplementary GID authority as real
principal occupancy, and that an existing user's PrimaryGroupID blocks group-number reuse.

Validation only: no signing identity, xcodebuild, device, Bluetooth, or physical authority.
"""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time


class ValidationError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def run(command: list[str], *, check: bool = False) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise ValidationError(
            f"command failed rc={result.returncode}: {command!r}; "
            f"stdout={result.stdout[-800:]!r}; stderr={result.stderr[-800:]!r}"
        )
    return result


def load_target(path: Path):
    spec = importlib.util.spec_from_file_location("nembra_bootstrap_hardening_target", path)
    require(spec is not None and spec.loader is not None, "could not load hardening target module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def choose_probe_id(target, *, offset: int, excluded: set[int] | None = None) -> int:
    excluded = excluded or set()
    seed = 670_000 + (os.getpid() % 10_000) + offset
    for candidate in range(seed, seed + 8_000):
        if candidate in excluded:
            continue
        if target.identity_records_are_free(candidate) and not target.numeric_uid_processes(candidate):
            return candidate
    raise ValidationError("could not find record/UID-process-free numeric GID probe")


def spawn_gid_only_probe(numeric_id: int, *, supplementary: bool) -> subprocess.Popen[str]:
    if supplementary:
        credential_change = f"os.setgroups([{numeric_id}])"
    else:
        credential_change = f"os.setgroups([]); os.setgid({numeric_id})"
    code = (
        "import json,os,time; "
        f"{credential_change}; "
        "print(json.dumps([os.getuid(), os.getgid(), os.getgroups()]), flush=True); "
        "time.sleep(30)"
    )
    probe = subprocess.Popen(
        ["/usr/bin/python3", "-B", "-I", "-c", code],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    require(probe.stdout is not None, "GID-only probe stdout unavailable")
    observed_line = probe.stdout.readline().strip()
    try:
        uid, gid, groups = json.loads(observed_line)
    except Exception as error:
        detail = probe.stderr.read()[-800:] if probe.stderr is not None else ""
        stop_probe(probe)
        raise ValidationError(
            f"GID-only probe did not emit credential JSON: {observed_line!r}; stderr={detail!r}"
        ) from error

    require(uid == 0, f"GID-only adversary unexpectedly changed UID: {uid!r}")
    if supplementary:
        require(gid == 0, f"supplementary-GID adversary unexpectedly changed primary GID: {gid!r}")
        require(numeric_id in groups, f"supplementary GID {numeric_id} was not retained: {groups!r}")
    else:
        require(gid == numeric_id, f"primary GID {numeric_id} was not retained: {gid!r}")
        require(numeric_id not in groups, f"primary-GID adversary unexpectedly also used supplementary GID: {groups!r}")
    time.sleep(0.10)
    require(probe.poll() is None, "GID-only adversary exited before occupancy assertion")
    return probe


def stop_probe(probe: subprocess.Popen[str] | None) -> None:
    if probe is None or probe.poll() is not None:
        return
    probe.kill()
    probe.wait(timeout=5)


def ds_user_exists(name: str) -> bool:
    result = run(["/usr/bin/dscl", ".", "-read", f"/Users/{name}"])
    if result.returncode == 0:
        return True
    detail = (result.stdout or "") + "\n" + (result.stderr or "")
    if "eDSRecordNotFound" in detail or "-14136" in detail or "Record was not found" in detail:
        return False
    listing = run(["/usr/bin/dscl", ".", "-list", "/Users", "RecordName"], check=True)
    return name in {line.split()[0] for line in listing.stdout.splitlines() if line.split()}


def create_user_with_primary_gid(name: str, *, unique_id: int, primary_gid: int) -> None:
    require(not ds_user_exists(name), f"probe user unexpectedly exists before creation: {name}")
    commands = [
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}"],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UniqueID", str(unique_id)],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "PrimaryGroupID", str(primary_gid)],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "NFSHomeDirectory", "/var/empty"],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UserShell", "/usr/bin/false"],
    ]
    try:
        for command in commands:
            run(command, check=True)
        run(["/usr/bin/dscacheutil", "-flushcache"], check=True)
        require(ds_user_exists(name), "PrimaryGroupID probe user was not materialized")
        readback = run(
            ["/usr/bin/dscl", ".", "-read", f"/Users/{name}", "PrimaryGroupID"],
            check=True,
        )
        require(str(primary_gid) in readback.stdout.split(), "probe user's PrimaryGroupID readback mismatched")
    except Exception:
        delete_probe_user(name)
        raise


def delete_probe_user(name: str) -> None:
    if ds_user_exists(name):
        run(["/usr/bin/dscl", ".", "-delete", f"/Users/{name}"], check=True)
    run(["/usr/bin/dscacheutil", "-flushcache"], check=True)
    require(not ds_user_exists(name), f"probe user survived cleanup: {name}")


def require_process_gid_blocks_admission(target, numeric_id: int, *, supplementary: bool) -> None:
    probe: subprocess.Popen[str] | None = None
    mode = "supplementary" if supplementary else "primary"
    try:
        probe = spawn_gid_only_probe(numeric_id, supplementary=supplementary)
        require(
            not target.numeric_identity_is_fresh(numeric_id),
            f"BLOCKER: combined UID/GID candidate remained fresh while a live process carried the candidate as {mode} GID only",
        )
    finally:
        stop_probe(probe)


def require_user_primary_gid_blocks_admission(target, *, candidate_gid: int, unique_uid: int) -> None:
    name = f"_nembra_gid_admission_{os.getpid()}_{candidate_gid}"
    try:
        create_user_with_primary_gid(name, unique_id=unique_uid, primary_gid=candidate_gid)
        require(
            not target.identity_records_are_free(candidate_gid),
            "BLOCKER: GID candidate remained record-free while an existing local user referenced it as PrimaryGroupID",
        )
    finally:
        delete_probe_user(name)


def require_gid_process_is_retired_before_identity_deletion(
    target,
    numeric_id: int,
    *,
    supplementary: bool,
) -> None:
    name = f"_nembra_gid_retire_{'supp' if supplementary else 'primary'}_{os.getpid()}_{numeric_id}"
    probe: subprocess.Popen[str] | None = None
    identity_created = False
    try:
        target.create_identity(name, numeric_id)
        identity_created = True
        probe = spawn_gid_only_probe(numeric_id, supplementary=supplementary)
        target.delete_identity_after_process_retirement(name, numeric_id)
        identity_created = False
        require(
            probe.poll() is not None,
            f"BLOCKER: cleanup deleted/released numeric GID {numeric_id} while a {'supplementary' if supplementary else 'primary'}-GID process retained that authority",
        )
    finally:
        stop_probe(probe)
        if identity_created:
            # The target cleanup remains the subject under test, but never leave a synthetic record
            # behind if an earlier assertion/repair raises. With the probe stopped, retry its strict
            # cleanup once so validation-host state is restored or fail authoritatively.
            target.delete_identity_after_process_retirement(name, numeric_id)


def main() -> int:
    require(sys.platform == "darwin", "GID occupancy red-team requires macOS")
    require(os.geteuid() == 0, "GID occupancy red-team must run as root")

    target_path = Path("scripts/ci/tests/test_capture_apple_signing_trusted_bootstrap_hardening.py").resolve()
    target = load_target(target_path)

    used: set[int] = set()
    primary_gid = choose_probe_id(target, offset=0, excluded=used)
    used.add(primary_gid)
    supplementary_gid = choose_probe_id(target, offset=20_000, excluded=used)
    used.add(supplementary_gid)
    ds_gid = choose_probe_id(target, offset=40_000, excluded=used)
    used.add(ds_gid)
    ds_uid = choose_probe_id(target, offset=60_000, excluded=used)
    used.add(ds_uid)
    retire_primary_gid = choose_probe_id(target, offset=80_000, excluded=used)
    used.add(retire_primary_gid)
    retire_supp_gid = choose_probe_id(target, offset=100_000, excluded=used)

    # Admission must reject process authority even when the process UID is unrelated.
    require_process_gid_blocks_admission(target, primary_gid, supplementary=False)
    require_process_gid_blocks_admission(target, supplementary_gid, supplementary=True)

    # Group-number freshness must include user references, not only group records and user UIDs.
    require_user_primary_gid_blocks_admission(target, candidate_gid=ds_gid, unique_uid=ds_uid)

    # Cleanup must retire both primary and supplementary GID authority before releasing the group
    # number in Directory Services. A deleted record is not proof that a live credential vanished.
    require_gid_process_is_retired_before_identity_deletion(
        target, retire_primary_gid, supplementary=False
    )
    require_gid_process_is_retired_before_identity_deletion(
        target, retire_supp_gid, supplementary=True
    )

    print(
        "TRUSTED_BOOTSTRAP_GID_OCCUPANCY_ACCEPTED "
        "primaryGidAware=true supplementaryGidAware=true userPrimaryGroupAware=true "
        "cleanupGidAware=true physicalAuthorityCreated=false"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValidationError as error:
        print(f"TRUSTED_BOOTSTRAP_GID_OCCUPANCY_REJECTED: {error}", file=sys.stderr)
        raise SystemExit(1)

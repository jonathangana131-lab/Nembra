#!/usr/bin/env python3
"""Expected-red adversary for trusted-bootstrap numeric GID occupancy.

The parent hardening witness allocates one numeric value as both UID and GID. This test proves
that a process carrying only that numeric GID must block allocation even when its UID is unrelated,
and that Directory Services user PrimaryGroupID occupancy is part of the GID freshness contract.
It is validation-only: no signing identity, xcodebuild, device, Bluetooth, or physical authority.
"""
from __future__ import annotations

import importlib.util
import inspect
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


def load_target(path: Path):
    spec = importlib.util.spec_from_file_location("nembra_bootstrap_hardening_target", path)
    require(spec is not None and spec.loader is not None, "could not load hardening target module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def choose_probe_id(target) -> int:
    seed = 670_000 + (os.getpid() % 10_000)
    for candidate in range(seed, seed + 10_000):
        if target.identity_records_are_free(candidate) and not target.numeric_uid_processes(candidate):
            return candidate
    raise ValidationError("could not find record/UID-process-free numeric GID probe")


def spawn_gid_only_probe(numeric_id: int) -> subprocess.Popen[str]:
    code = (
        "import os,time; "
        f"os.setgid({numeric_id}); "
        "print(f'{os.getuid()}:{os.getgid()}', flush=True); "
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
    observed = probe.stdout.readline().strip()
    expected = f"0:{numeric_id}"
    if observed != expected:
        detail = probe.stderr.read()[-800:] if probe.stderr is not None else ""
        try:
            probe.kill()
        except ProcessLookupError:
            pass
        probe.wait(timeout=5)
        raise ValidationError(
            f"GID-only probe did not retain root UID with target GID: observed={observed!r} expected={expected!r} stderr={detail!r}"
        )
    return probe


def stop_probe(probe: subprocess.Popen[str] | None) -> None:
    if probe is None or probe.poll() is not None:
        return
    probe.kill()
    probe.wait(timeout=5)


def main() -> int:
    require(sys.platform == "darwin", "GID occupancy red-team requires macOS")
    require(os.geteuid() == 0, "GID occupancy red-team must run as root")

    target_path = Path("scripts/ci/tests/test_capture_apple_signing_trusted_bootstrap_hardening.py").resolve()
    target = load_target(target_path)
    numeric_id = choose_probe_id(target)

    probe: subprocess.Popen[str] | None = None
    try:
        probe = spawn_gid_only_probe(numeric_id)
        time.sleep(0.10)

        # The adversary deliberately keeps UID 0, so the parent's UID-only process inventory
        # should not be allowed to classify this combined UID/GID candidate as fresh.
        require(
            not target.numeric_identity_is_fresh(numeric_id),
            "BLOCKER: combined UID/GID candidate remained fresh while a live process carried the candidate as GID only",
        )
    finally:
        stop_probe(probe)

    identity_source = inspect.getsource(target.identity_records_are_free)
    require(
        'direct_ds_numeric_ids("Users", "PrimaryGroupID")' in identity_source,
        "BLOCKER: GID freshness does not reject existing Directory Services Users/PrimaryGroupID occupancy",
    )

    print("TRUSTED_BOOTSTRAP_GID_OCCUPANCY_ACCEPTED processGidAware=true userPrimaryGroupAware=true physicalAuthorityCreated=false")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValidationError as error:
        print(f"TRUSTED_BOOTSTRAP_GID_OCCUPANCY_REJECTED: {error}", file=sys.stderr)
        raise SystemExit(1)

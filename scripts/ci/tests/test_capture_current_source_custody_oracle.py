#!/usr/bin/env python3
"""Expected-red source contract for current Capture build-origin custody.

Validation only. This oracle fails while production still runs the dedicated build
from the caller-selected mutable checkout instead of a root-custodied accepted source
snapshot. It creates no device, Bluetooth, Tuya, signing, telemetry, or physical authority.
"""
from __future__ import annotations

from pathlib import Path

PRODUCTION = Path("scripts/ci/capture_signed_app_build_origin_custody.py")


def main() -> int:
    source = PRODUCTION.read_text(encoding="utf-8")

    required_existing = (
        "def run_custodied_build(",
        "_run_exec_bound_build(",
        "cwd=Path(os.getcwd())",
        "DERIVED_PLACEHOLDER",
    )
    missing = [marker for marker in required_existing if marker not in source]
    if missing:
        raise SystemExit(f"oracle drift: current production markers missing: {missing!r}")

    accepted_snapshot_markers = (
        "accepted_source_snapshot",
        "accepted-source-snapshot",
        "root_custodied_source",
        "root-custodied source",
    )
    if not any(marker in source for marker in accepted_snapshot_markers):
        raise SystemExit(
            "EXPECTED RED: production dedicated build still has no explicit accepted root-custodied source snapshot"
        )

    mutable_cwd = "cwd=Path(os.getcwd())" in source
    if mutable_cwd:
        raise SystemExit(
            "EXPECTED RED: guarded build still executes from caller-selected os.getcwd() rather than the accepted source snapshot"
        )

    print("PASS: production no longer exhibits the current mutable-checkout source-custody signature")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

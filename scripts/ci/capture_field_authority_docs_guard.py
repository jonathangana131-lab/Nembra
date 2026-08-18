#!/usr/bin/env python3
"""Fail closed when retired ES80 field procedures regain operational authority."""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]

RETIRED_DOCS = (
    ROOT / "docs/ES80_TODAY_PRIVATE_FIELD_RUNBOOK.md",
    ROOT / "docs/ES80_TODAY_FINAL_GO_OPERATOR_ATTESTATION.md",
)
CURRENT_GATE = ROOT / "docs/ES80_AUTHENTICATED_STATIONARY_GATE_V14.md"

REQUIRED_RETIRED_MARKERS = (
    "RETIRED / NON-AUTHORIZING",
    "PHYSICAL STATUS: NO-GO",
    "ES80-AUTHENTICATED-STATIONARY-v1",
)

LEGACY_OPERATIONAL_PINS = (
    "#833@a0f4a33451f61411d6e0541f2e70edea5438342d",
    "Capture Build V14-a0f4a33451f6",
    "scripts/ci/es80_today_final_go_hardened.py --",
)

CURRENT_GATE_MARKERS = (
    "Status: **NO-GO",
    "ES80_TODAY_PRIVATE_FIELD_RUNBOOK.md",
    "RETIRED / NON-AUTHORIZING",
    "historical evidence",
    "at least **45 seconds**",
)

STALE_CURRENT_GATE_WORDING = (
    "is still pinned to the earlier frozen Capture subject",
    "remains historical evidence for the first fingerprint field path",
)


def fail(message: str) -> None:
    print(f"::error::{message}")
    raise SystemExit(1)


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        fail(f"cannot read {path.relative_to(ROOT)}: {exc}")


def main() -> int:
    for path in RETIRED_DOCS:
        text = read(path)
        rel = path.relative_to(ROOT)
        for marker in REQUIRED_RETIRED_MARKERS:
            if marker not in text:
                fail(f"{rel} lost required fail-closed marker: {marker!r}")
        for stale in LEGACY_OPERATIONAL_PINS:
            if stale in text:
                fail(f"{rel} resurrects retired operational authority: {stale!r}")

    gate = read(CURRENT_GATE)
    for marker in CURRENT_GATE_MARKERS:
        if marker not in gate:
            fail(f"{CURRENT_GATE.relative_to(ROOT)} lost current physical-gate marker: {marker!r}")
    for stale in STALE_CURRENT_GATE_WORDING:
        if stale in gate:
            fail(f"{CURRENT_GATE.relative_to(ROOT)} contradicts retired field authority: {stale!r}")

    print("CAPTURE_FIELD_AUTHORITY_DOCS_GUARD PASS")
    print("physical_status=NO-GO")
    print("current_procedure=ES80-AUTHENTICATED-STATIONARY-v1")
    return 0


if __name__ == "__main__":
    sys.exit(main())

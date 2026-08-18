#!/usr/bin/env python3
"""Fail closed when retired ES80 field procedures regain operational authority."""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]

RETIRED_DOCS = (
    ROOT / "docs/ES80_TODAY_PRIVATE_FIELD_RUNBOOK.md",
    ROOT / "docs/ES80_TODAY_FINAL_GO_OPERATOR_ATTESTATION.md",
    ROOT / "docs/ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md",
    ROOT / "docs/ES80_TODAY_EXACT_RETAINED_IPA_INSTALL.md",
    ROOT / "docs/ES80_TODAY_RESEARCH_AUTHORIZATION_CONTRACT.md",
    ROOT / "docs/ES80_TODAY_EXPORT_READINESS_TRUTH.md",
    ROOT / "docs/ES80_TODAY_PRIVATE_DEVICE_INPUT_CUSTODY.md",
)
ROOT_DIRECTIVE = ROOT / "CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md"
CURRENT_GATE = ROOT / "docs/ES80_AUTHENTICATED_STATIONARY_GATE_V14.md"
CURRENT_PROCEDURE = ROOT / "docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md"

REQUIRED_RETIRED_MARKERS = (
    "RETIRED / NON-AUTHORIZING",
    "PHYSICAL STATUS: NO-GO",
    "ES80-AUTHENTICATED-STATIONARY-v1",
)

LEGACY_OPERATIONAL_PINS = (
    "#833@a0f4a33451f61411d6e0541f2e70edea5438342d",
    "Capture Build V14-a0f4a33451f6",
    "scripts/ci/es80_today_final_go_hardened.py --",
    "READY_TO_INVOKE_SIGNED_FIELD_PRODUCER",
)

ROOT_DIRECTIVE_MARKERS = (
    "RETIRED / NON-AUTHORITATIVE / PHYSICAL NO-GO",
    "ES80-AUTHENTICATED-STATIONARY-v1",
    "docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md",
    "current shipping source plus `docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md` wins",
)

CURRENT_GATE_MARKERS = (
    "Status: **NO-GO",
    "ES80_TODAY_PRIVATE_FIELD_RUNBOOK.md",
    "historical evidence",
    "at least **45 seconds**",
)

CURRENT_PROCEDURE_MARKERS = (
    "PROCEDURE_ID: `ES80-AUTHENTICATED-STATIONARY-v1`",
    "physical secure-link experiment is **NO-GO**",
    "at least 45 seconds of canonical authenticated observation",
    "rawFD50BytesCaptured=false",
    "dpQueriesSent=false",
    "dpCommandsSent=false",
)


def fail(message: str) -> None:
    print(f"::error::{message}")
    raise SystemExit(1)


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        fail(f"cannot read {path.relative_to(ROOT)}: {exc}")


def require_markers(path: Path, markers: tuple[str, ...]) -> None:
    text = read(path)
    for marker in markers:
        if marker not in text:
            fail(f"{path.relative_to(ROOT)} lost required authority marker: {marker!r}")


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

    require_markers(ROOT_DIRECTIVE, ROOT_DIRECTIVE_MARKERS)
    require_markers(CURRENT_GATE, CURRENT_GATE_MARKERS)
    require_markers(CURRENT_PROCEDURE, CURRENT_PROCEDURE_MARKERS)

    runbook = read(RETIRED_DOCS[0])
    if "docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md" not in runbook:
        fail("retired runbook no longer points operators at the current secure-link procedure")

    print("CAPTURE_FIELD_AUTHORITY_DOCS_GUARD PASS")
    print(f"retired_docs={len(RETIRED_DOCS)}")
    print("physical_status=NO-GO")
    print("current_procedure=ES80-AUTHENTICATED-STATIONARY-v1")
    print("current_runbook=docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())

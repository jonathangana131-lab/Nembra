#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
IDENTITY = (ROOT / "NembraApp/App/NembraCaptureBuildIdentity.swift").read_text(encoding="utf-8")
RUNBOOK = (ROOT / "docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md").read_text(encoding="utf-8")
TODAY = (ROOT / "CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md").read_text(encoding="utf-8")

match = re.search(
    r'static let requiredFieldProcedureIdentifier = "([^"]+)"',
    IDENTITY,
)
if not match:
    raise SystemExit("shipping Capture source does not expose the required field procedure identifier")
procedure = match.group(1)

if procedure != "ES80-AUTHENTICATED-STATIONARY-v1":
    raise SystemExit(f"unexpected shipping field procedure identifier: {procedure}")

runbook_marker = f"PROCEDURE_ID: `{procedure}`"
if RUNBOOK.count(runbook_marker) != 1:
    raise SystemExit(f"current operator runbook must declare exactly one {runbook_marker}")

required_runbook = [
    "This test is indoors and stationary.",
    "it does **not** repeat the old ride sequence",
    "physical test remains NO-GO until all are accepted",
    "repository explicitly records `GO`",
    "keep Capture in the foreground",
]
for marker in required_runbook:
    if marker not in RUNBOOK:
        raise SystemExit(f"current operator runbook lost fail-closed stationary authority marker: {marker}")

if "ES80-FINGERPRINT-v1" in RUNBOOK or "NEMBRA_ES80_TODAY_RESEARCH" in RUNBOOK:
    raise SystemExit("current authenticated stationary runbook must not depend on the retired passive Research lane")

required_today = [
    "Status: **RETIRED / NON-AUTHORITATIVE / PHYSICAL NO-GO.**",
    f"`{procedure}`",
    "`docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md`",
    "Retired authority — MUST NOT be reused",
    "Any mismatch between them is **NO-GO** until reconciled.",
]
for marker in required_today:
    if marker not in TODAY:
        raise SystemExit(f"retired TODAY directive lost procedure-authority boundary: {marker}")

for forbidden in (
    "Status: **ACTIVE TODAY OVERRIDE",
    "this directive supersedes",
    "makeResearchAuthorizedES80ForCurrentApplication()\n->",
):
    if forbidden.lower() in TODAY.lower():
        raise SystemExit(f"retired TODAY directive regained runnable/precedence authority: {forbidden}")

print(f"capture physical procedure authority coherence: PASS ({procedure})")

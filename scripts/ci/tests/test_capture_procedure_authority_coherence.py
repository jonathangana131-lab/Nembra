#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
IDENTITY = (ROOT / "NembraApp/App/NembraCaptureBuildIdentity.swift").read_text(encoding="utf-8")
RUNBOOK = (ROOT / "docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md").read_text(encoding="utf-8")
TODAY = (ROOT / "CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md").read_text(encoding="utf-8")
PASSIVE_HISTORY = (ROOT / "docs/ES80_PHYSICAL_CAPTURE_RUNBOOK.md").read_text(encoding="utf-8")

match = re.search(r'static let requiredFieldProcedureIdentifier = "([^"]+)"', IDENTITY)
if not match:
    raise SystemExit("shipping Capture source does not expose the required field procedure identifier")
procedure = match.group(1)
if procedure != "ES80-AUTHENTICATED-STATIONARY-v1":
    raise SystemExit(f"unexpected shipping field procedure identifier: {procedure}")

runbook_marker = f"PROCEDURE_ID: `{procedure}`"
if RUNBOOK.count(runbook_marker) != 1:
    raise SystemExit(f"current operator runbook must declare exactly one {runbook_marker}")
for marker in (
    "This test is indoors and stationary.",
    "it does **not** repeat the old ride sequence",
    "physical test remains NO-GO until all are accepted",
    "repository explicitly records `GO`",
    "keep Capture in the foreground",
):
    if marker not in RUNBOOK:
        raise SystemExit(f"current operator runbook lost fail-closed stationary authority marker: {marker}")
if "ES80-FINGERPRINT-v1" in RUNBOOK or "NEMBRA_ES80_TODAY_RESEARCH" in RUNBOOK:
    raise SystemExit("current authenticated stationary runbook must not depend on the retired passive Research lane")

for marker in (
    "Status: **RETIRED / NON-AUTHORITATIVE / PHYSICAL NO-GO.**",
    f"`{procedure}`",
    "`docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md`",
    "Retired authority — MUST NOT be reused",
    "Any mismatch between them is **NO-GO** until reconciled.",
):
    if marker not in TODAY:
        raise SystemExit(f"retired TODAY directive lost procedure-authority boundary: {marker}")
for forbidden in ("Status: **ACTIVE TODAY OVERRIDE", "this directive supersedes"):
    if forbidden.lower() in TODAY.lower():
        raise SystemExit(f"retired TODAY directive regained precedence authority: {forbidden}")

for marker in (
    "Status: **RETIRED / NON-AUTHORITATIVE / PHYSICAL NO-GO.**",
    f"`{procedure}`",
    "`docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md`",
    "this historical file loses",
    "Any mismatch is NO-GO.",
    "not kept here as runnable operator instructions",
    "NO-GO / DO NOT SCAN / DO NOT RUN / DO NOT REPEAT THE OLD RIDE",
):
    if marker not in PASSIVE_HISTORY:
        raise SystemExit(f"retired passive physical runbook lost authority boundary: {marker}")
if "Retiring this document creates no Bluetooth write authority" not in PASSIVE_HISTORY:
    raise SystemExit("retired passive runbook lost explicit no-write-authority boundary")

print(f"capture physical procedure authority coherence: PASS ({procedure})")
#!/usr/bin/env python3
"""Exact-head red-team classifier for Capture's exported SDK-local BLE state.

This is intentionally a validation-only detector. It exits successfully only while the
canonical parent still has the specific V16.1 ambiguity where a single exported Boolean
represents both loss of current proof and an actually observed offline transport state.
It must not be merged as a product fix; the shipping repair should replace the ambiguous
machine-readable contract with an explicit provenance/currentness state.
"""

from pathlib import Path
import sys

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = APP.read_text(encoding="utf-8")


def section(start: str, end: str) -> str:
    start_index = source.find(start)
    if start_index < 0:
        raise RuntimeError(f"missing source marker: {start}")
    end_index = source.find(end, start_index + len(start))
    if end_index < 0:
        raise RuntimeError(f"missing source marker after {start!r}: {end}")
    return source[start_index:end_index]


export_decl = section("struct Export: Codable {", "struct Event: Codable")
make_export = section("private func makeExport", "func prepareExport")
continuity_mirror = section(
    "private func mirrorAlreadyTerminalObservationContinuity",
    "private func mirrorAlreadyTerminalIncompleteObservationHorizon",
)
incomplete_mirror = section(
    "private func mirrorAlreadyTerminalIncompleteObservationHorizon",
    "private func invalidateObservationContinuity",
)

checks = {
    "schema is still v10": "schemaVersion: 10" in make_export,
    "export exposes bare Bool": "let sdkLocalBLEOnline: Bool" in export_decl,
    "makeExport serializes bare proof bit": "sdkLocalBLEOnline: sdkLocalBLEOnline" in make_export,
    "continuity retirement clears proof bit without a transport receipt": (
        "sdkLocalBLEOnline = false" in continuity_mirror
        and "endConnection" not in continuity_mirror
        and "recordObservedTransportLoss" not in continuity_mirror
    ),
    "incomplete-horizon retirement clears proof bit without a transport receipt": (
        "sdkLocalBLEOnline = false" in incomplete_mirror
        and "endConnection" not in incomplete_mirror
        and "recordObservedTransportLoss" not in incomplete_mirror
    ),
    "UI explicitly treats false as Not proven": (
        'test.sdkLocalBLEOnline ? "Online" : "Not proven"' in source
    ),
}

missing = [name for name, present in checks.items() if not present]
if missing:
    print("The exact V16.1 ambiguity is no longer mechanically present:", file=sys.stderr)
    for item in missing:
        print(f"- {item}", file=sys.stderr)
    print(
        "Re-review the replacement export/currentness contract instead of treating this detector as acceptance.",
        file=sys.stderr,
    )
    sys.exit(1)

print("BLOCKER_CONFIRMED: Capture schema v10 exports sdkLocalBLEOnline as one Bool.")
print("Both non-transport evidence terminals clear that Bool while product copy means 'Not proven'.")
print("A downstream analyzer therefore cannot distinguish not-currently-proven from observed offline.")
print("PHYSICAL NO-GO: shipping artifact needs an explicit provenance/currentness state before promotion.")

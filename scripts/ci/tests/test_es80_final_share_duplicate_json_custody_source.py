#!/usr/bin/env python3
"""Expected-red source contract for exact-byte final Share JSON custody.

Foundation keyed JSON APIs collapse duplicate object members. Both the primary Experiment One final
Share verifier and its exact nested SoftwareExport verifier must reject duplicate top-level semantic
keys before JSONSerialization/JSONDecoder can choose parser precedence. This regression is
intentionally source-level so the contract remains pinned while active UI/signed-publication lanes
move independently.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCES = {
    "final Share": ROOT / "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneFinalShareArtifact.swift",
    "nested SoftwareExport": ROOT / "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneSoftwareExport.swift",
}

marker = "PassiveBluetoothStrictJSON.duplicateTopLevelObjectKey(in: data)"
missing = []
for label, path in SOURCES.items():
    text = path.read_text(encoding="utf-8")
    if marker not in text:
        missing.append(label)

if missing:
    raise SystemExit(
        "P0 exact-byte provenance contract missing: closed-world final Share evidence must reject "
        "duplicate top-level JSON keys before Foundation decoding in: " + ", ".join(missing)
    )

print("PASS: outer final Share and nested SoftwareExport both pin duplicate top-level JSON rejection")

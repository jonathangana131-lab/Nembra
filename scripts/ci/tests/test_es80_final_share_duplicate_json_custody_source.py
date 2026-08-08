#!/usr/bin/env python3
"""Expected-red source contract for exact-byte final Share JSON custody.

Foundation keyed JSON APIs collapse duplicate object members. The primary Experiment One final
Share verifier must reject duplicate top-level semantic keys before JSONSerialization/JSONDecoder
can choose parser precedence. This regression is intentionally source-level so the contract remains
pinned while the active Capture shell/signed-publication lanes move independently.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneFinalShareArtifact.swift"

text = SOURCE.read_text(encoding="utf-8")

required = [
    "PassiveBluetoothStrictJSON.duplicateTopLevelObjectKey(in: data)",
    "duplicate",
]

missing = [needle for needle in required if needle not in text]
if missing:
    raise SystemExit(
        "P0 exact-byte provenance contract missing: final Share closed-world validation must reject "
        "duplicate top-level JSON keys before Foundation decoding. Missing source markers: "
        + ", ".join(repr(item) for item in missing)
    )

print("PASS: final Share verifier pins duplicate top-level JSON rejection before decode")

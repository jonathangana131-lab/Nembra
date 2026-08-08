from pathlib import Path

path = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift")
source = path.read_text()
old = """                    case let .recorded(recordedReady):
                        do {
                            // This typed queue commit is intentionally the immediate
"""
new = """                    case let .recorded(recordedReady):
                        do {
                            try self.requireForegroundEvidenceIntegrity()
                            // This typed queue commit is intentionally the immediate
"""
count = source.count(old)
if count != 1:
    raise SystemExit(f"expected exactly one Ready recorded-return seam, found {count}")
updated = source.replace(old, new, 1)
start = updated.index("case let .recorded(recordedReady):")
end = updated.index("recordedReady.markBoundaryRecorded(", start)
seam = updated[start:end]
if "try self.requireForegroundEvidenceIntegrity()" not in seam:
    raise SystemExit("foreground integrity recheck missing from Ready post-recorder seam")
path.write_text(updated)

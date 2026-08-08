from pathlib import Path

path = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
source = path.read_text()
old = "        currentWindow: PassiveBluetoothPowerCycleObservationPhase?,\n"
new = "        currentWindow: Int?,\n"
count = source.count(old)
if count != 1:
    raise RuntimeError(f"expected one progress helper type anchor, found {count}")
source = source.replace(old, new, 1)

if "private func presentationCurrentWindow(\n        status: PassiveBluetoothExperimentOneCoordinator.Status\n    ) -> Int?" not in source:
    raise RuntimeError("presentationCurrentWindow no longer returns Int?")
path.write_text(source)

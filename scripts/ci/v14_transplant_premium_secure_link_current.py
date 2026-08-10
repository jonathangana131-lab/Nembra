from pathlib import Path
import subprocess

DONOR = "f2f2b606dbc0b6a42894d6ec6dc19eb22f4d3630"
APP_PATH = "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST_PATH = "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSecureLinkProductSurfaceSourceTests.swift"

app_file = Path(APP_PATH)
current = app_file.read_text()
donor = subprocess.check_output(["git", "show", f"{DONOR}:{APP_PATH}"], text=True)
marker = "@MainActor\nprivate struct SecureLinkView: View {"
current_start = current.find(marker)
donor_start = donor.find(marker)
if current_start < 0 or donor_start < 0:
    raise SystemExit("SecureLinkView marker changed")

# The Capture controller/driver/account authority all live before this presentation tail. Replacing
# only the tail preserves the current flagship's newer production truth code byte-for-byte while
# reusing the reviewed guided Secure Link presentation and its input helper.
current_prefix = current[:current_start]
donor_tail = donor[donor_start:]
app_file.write_text(current_prefix + donor_tail)

Path(TEST_PATH).write_text(subprocess.check_output(["git", "show", f"{DONOR}:{TEST_PATH}"], text=True))

app = app_file.read_text()
assert "NEMBRA CAPTURE" in app
assert "CAPTURE COMPLETE" in app
assert 'Label("Share Capture"' in app
assert 'Label("Engineering details"' in app
assert "func inputSurface() -> some View" in app
assert "func card() -> some View" not in app

# Current-head truth/field authority must remain present outside the transplanted view tail.
prefix = app[:app.index(marker)]
for anchor in (
    "captureAttemptEventStartIndex",
    "applicationUpdateAdmissionsInFlight",
    "acceptanceCutIsClosed",
    "sealedAcceptedExport",
    "sessionLedger.sealAcceptedObservation",
    "consumeCorrelationAsyncInvalidation",
):
    assert anchor in prefix, anchor

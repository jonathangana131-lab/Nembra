from pathlib import Path
import subprocess

DONOR = "d5915a97c1359846b103f08602db78eac815a47f"
APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSecureLinkProductSurfaceSourceTests.swift")
HARNESS = Path("scripts/ci/capture_standalone_visual_evidence.sh")
HARNESS_TEST = Path("scripts/ci/tests/test_capture_standalone_visual_evidence.py")
VISUAL_WORKFLOW = Path(".github/workflows/capture-standalone-visual-acceptance.yml")


def donor(path: Path) -> str:
    return subprocess.check_output(["git", "show", f"{DONOR}:{path.as_posix()}"], text=True)

# Preserve every current controller/truth byte and replace only the reviewed presentation tail.
current = APP.read_text()
donor_app = donor(APP)
marker = "@MainActor\nprivate struct SecureLinkView: View {"
current_start = current.find(marker)
donor_start = donor_app.find(marker)
if current_start < 0 or donor_start < 0:
    raise SystemExit("SecureLinkView marker changed")
app = current[:current_start] + donor_app[donor_start:]

# The procedure rendezvous landed after the visual donor. Restore it in the collapsed authority details.
old = '                LabeledContent("Source commit", value: test.fieldBuildSourceCommitSHA)\n'
new = old + '                LabeledContent("Procedure", value: test.fieldProcedureIdentifier)\n'
if app.count(old) != 1:
    raise SystemExit("visual engineering-details source commit row changed")
app = app.replace(old, new, 1)
APP.write_text(app)

# Reuse the reviewed product contract, then pin current procedure visibility as well.
tests = donor(TEST)
anchor = '        #expect(body.contains("test.fieldBuildIsAuthoritative"))\n'
if tests.count(anchor) != 1:
    raise SystemExit("visual truth contract anchor changed")
tests = tests.replace(
    anchor,
    anchor + '        #expect(body.contains("LabeledContent(\\"Procedure\\", value: test.fieldProcedureIdentifier)"))\n',
    1,
)
TEST.write_text(tests)

# Reuse the stronger standalone evidence harness already reviewed on the visual donor.
HARNESS.parent.mkdir(parents=True, exist_ok=True)
HARNESS_TEST.parent.mkdir(parents=True, exist_ok=True)
HARNESS.write_text(donor(HARNESS))
HARNESS_TEST.write_text(donor(HARNESS_TEST))
VISUAL_WORKFLOW.parent.mkdir(parents=True, exist_ok=True)
workflow = donor(VISUAL_WORKFLOW)
workflow = workflow.replace(
    "      - product/v14-capture-premium-secure-link-current-sol",
    "      - product/v14-capture-premium-secure-link-procedure-current-sol",
)
VISUAL_WORKFLOW.write_text(workflow)

# Portable invariants. Apple typecheck/runtime/screenshot proof belongs to xcode-27.
app = APP.read_text()
prefix = app[:app.index(marker)]
for authority in (
    "fieldProcedureIdentifier",
    "procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier",
    "schemaVersion: 10",
    "captureAttemptEventStartIndex",
    "applicationUpdateAdmissionsInFlight",
    "acceptanceCutIsClosed",
    "sealedAcceptedExport",
    "sessionLedger.sealAcceptedObservation",
    "consumeCorrelationAsyncInvalidation",
):
    assert authority in prefix, authority
surface = app[app.index(marker):]
for product in (
    "NEMBRA CAPTURE",
    "CAPTURE COMPLETE",
    "Ready for analysis",
    'Label("Share Capture"',
    'Label("Engineering details"',
    'LabeledContent("Procedure", value: test.fieldProcedureIdentifier)',
):
    assert product in surface, product
assert "Prepare sanitized diagnostic JSON" not in surface
assert "Canonical acceptance" not in surface
assert "func inputSurface() -> some View" in surface
assert "func card() -> some View" not in surface
assert "ES80-AUTHENTICATED-STATIONARY-v1" in Path("NembraApp/App/NembraCaptureBuildIdentity.swift").read_text()

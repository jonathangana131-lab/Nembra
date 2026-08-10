from pathlib import Path
import subprocess

DONOR = "d5915a97c1359846b103f08602db78eac815a47f"
PROCEDURE = "ES80-AUTHENTICATED-STATIONARY-v1"
APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSecureLinkProductSurfaceSourceTests.swift")
HARNESS = Path("scripts/ci/capture_standalone_visual_evidence.sh")
HARNESS_TEST = Path("scripts/ci/tests/test_capture_standalone_visual_evidence.py")
VISUAL_WORKFLOW = Path(".github/workflows/capture-standalone-visual-acceptance.yml")

def show(path: Path) -> str:
    return subprocess.check_output(["git", "show", f"{DONOR}:{path.as_posix()}"], text=True)

# Preserve all current procedure/truth/controller bytes and transplant only the reviewed presentation tail.
current = APP.read_text()
donor_app = show(APP)
marker = "@MainActor\nprivate struct SecureLinkView: View {"
cs, ds = current.find(marker), donor_app.find(marker)
if cs < 0 or ds < 0:
    raise SystemExit("SecureLinkView marker changed")
app = current[:cs] + donor_app[ds:]
row = '                LabeledContent("Source commit", value: test.fieldBuildSourceCommitSHA)\n'
if app.count(row) != 1:
    raise SystemExit("engineering details source row changed")
app = app.replace(row, row + '                LabeledContent("Procedure", value: test.fieldProcedureIdentifier)\n', 1)
APP.write_text(app)

# Reuse reviewed product contracts and add a separate, stable procedure rendezvous contract.
tests = show(TEST)
helper = "\n    private func section(in source: String, from start: String, to end: String) throws -> Substring {\n"
if tests.count(helper) != 1:
    raise SystemExit("test helper anchor changed")
procedure_test = r'''
    @Test("procedure rendezvous remains visible in collapsed engineering details")
    func procedureRendezvousRemainsVisible() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(in: app, from: "private struct SecureLinkView: View", to: "private struct SecureTransfer: Transferable")
        #expect(surface.contains("LabeledContent(\"Procedure\", value: test.fieldProcedureIdentifier)"))
        #expect(app.contains("fieldProcedureIdentifier"))
        #expect(app.contains("ES80-AUTHENTICATED-STATIONARY-v1"))
        #expect(app.contains("schemaVersion: 10"))
    }
'''
tests = tests.replace(helper, "\n" + procedure_test + helper, 1)
TEST.write_text(tests)

# Carry forward canonical standalone visual evidence tooling, then bind its manifest to the exact procedure.
HARNESS.parent.mkdir(parents=True, exist_ok=True)
HARNESS_TEST.parent.mkdir(parents=True, exist_ok=True)
harness = show(HARNESS)
harness = harness.replace('EXPECTED_BUNDLE_ID="com.jonathangana131.nembra.capturelearn"\n', f'EXPECTED_BUNDLE_ID="com.jonathangana131.nembra.capturelearn"\nEXPECTED_PROCEDURE_ID="{PROCEDURE}"\n', 1)
harness = harness.replace('  "$TUYA_DEPENDENCY_LOCK_SHA256" \\\n  "$BUNDLE_ID" \\\n', '  "$TUYA_DEPENDENCY_LOCK_SHA256" \\\n  "$EXPECTED_PROCEDURE_ID" \\\n  "$BUNDLE_ID" \\\n', 1)
harness = harness.replace('    tuya_dependency_lock_sha256,\n    bundle_id,\n', '    tuya_dependency_lock_sha256,\n    procedure_identifier,\n    bundle_id,\n', 1)
harness = harness.replace('    "tuyaDependencyLockSHA256": tuya_dependency_lock_sha256,\n', '    "tuyaDependencyLockSHA256": tuya_dependency_lock_sha256,\n    "procedureIdentifier": procedure_identifier,\n', 1)
harness = harness.replace('  "Tuya dependency lock: $TUYA_DEPENDENCY_LOCK_SHA256" \\\n', '  "Tuya dependency lock: $TUYA_DEPENDENCY_LOCK_SHA256" \\\n  "Procedure: $EXPECTED_PROCEDURE_ID" \\\n', 1)
HARNESS.write_text(harness)
HARNESS_TEST.write_text(show(HARNESS_TEST))

workflow = show(VISUAL_WORKFLOW).replace(
    "product/v14-capture-premium-secure-link-current-sol",
    "product/v14-capture-premium-secure-link-procedure-r2-sol",
)
workflow = workflow.replace('assert record["buildIdentifier"] == f"capture-v14-{expected_sha[:12]}"\n', 'assert record["buildIdentifier"] == f"capture-v14-{expected_sha[:12]}"\n          assert record["procedureIdentifier"] == "ES80-AUTHENTICATED-STATIONARY-v1"\n', 1)
VISUAL_WORKFLOW.write_text(workflow)

app = APP.read_text()
prefix = app[:app.index(marker)]
surface = app[app.index(marker):]
for anchor in ("fieldProcedureIdentifier", "schemaVersion: 10", "sealedAcceptedExport", "sessionLedger.sealAcceptedObservation", "consumeCorrelationAsyncInvalidation"):
    assert anchor in prefix, anchor
for anchor in ("NEMBRA CAPTURE", "CAPTURE COMPLETE", "Ready for analysis", 'Label("Share Capture"', 'LabeledContent("Procedure", value: test.fieldProcedureIdentifier)'):
    assert anchor in surface, anchor
assert PROCEDURE in Path("NembraApp/App/NembraCaptureBuildIdentity.swift").read_text()
assert '"procedureIdentifier": procedure_identifier' in HARNESS.read_text()

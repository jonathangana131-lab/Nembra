#!/usr/bin/env python3
from pathlib import Path
import subprocess

BASE = "29fb304613c142ba99e1259e9d612c1919309145"

extra_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationReceiptChronologyTests.swift")
ledger_tests_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAuthenticatedReadOnlySessionLedgerTests.swift")
extra = extra_path.read_text()
ledger_tests = ledger_tests_path.read_text()

if "func delayedApplicationAdmissionUsesLedgerDeliveryTime()" in ledger_tests:
    raise SystemExit("receipt runtime tests already merged")
start = extra.index("    @Test(")
end = extra.index("\n}\n\nprivate final class ReceiptAuthorityTestUptimeClock")
methods = extra[start:end].replace("ReceiptAuthorityTestUptimeClock", "TestUptimeClock")
methods += r'''

    @Test("package seal refuses while an exact application delivery receipt is pending")
    func acceptedSealCannotOvertakePendingApplicationReceipt() async throws {
        let clock = TestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        let pending = try ledger.captureApplicationReceipt(isNonEmpty: true, for: token)

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.applicationAdmissionPending) {
            try await ledger.sealAcceptedObservation(for: token)
        }
        ledger.releaseApplicationReceipt(pending)
        #expect((await ledger.currentPreflightSnapshot()).applicationPayloadCount == 0)
    }
'''

struct_end_marker = "\n}\n\nprivate final class TestUptimeClock"
insert_at = ledger_tests.index(struct_end_marker)
ledger_tests = ledger_tests[:insert_at] + "\n\n" + methods + ledger_tests[insert_at:]
ledger_tests_path.write_text(ledger_tests)
extra_path.unlink()

# Keep the exact standalone workflow on canonical bytes. The existing canonical filter already runs
# TuyaAuthenticatedReadOnlySessionLedgerTests + TuyaAcceptedApplicationEvidenceSealSourceTests.
for path in [
    ".github/workflows/capture-v16-standalone.yml",
    "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/ES80CaptureSimulatorPreflightSnapshotHandoffTests.swift",
]:
    blob = subprocess.check_output(["git", "show", f"{BASE}:{path}"])
    Path(path).write_bytes(blob)

# Tighten the already-gated source contract for the two final refinements without adding a new suite.
source_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAcceptedApplicationEvidenceSealSourceTests.swift")
source = source_path.read_text()
old = '''        let packageReceipt = try #require(watchdog.range(of: "captureLivenessReceipt(for: token)", range: directBLE.upperBound..<watchdog.endIndex))\n        let pendingCatch = try #require(watchdog.range(of: "MutationError.applicationAdmissionPending", range: packageReceipt.upperBound..<watchdog.endIndex))\n        let ledgerMutation = try #require(watchdog.range(of: "self.sessionLedger.observeCurrentConnection(", range: pendingCatch.upperBound..<watchdog.endIndex))\n        let receiptArgument = try #require(watchdog.range(of: "receipt: livenessReceipt", range: ledgerMutation.upperBound..<watchdog.endIndex))\n\n        #expect(localDrain.lowerBound < directBLE.lowerBound)\n        #expect(directBLE.lowerBound < packageReceipt.lowerBound)\n        #expect(packageReceipt.lowerBound < pendingCatch.lowerBound)\n        #expect(pendingCatch.lowerBound < ledgerMutation.lowerBound)\n        #expect(ledgerMutation.lowerBound < receiptArgument.lowerBound)'''
new = '''        let packageReceipt = try #require(watchdog.range(of: "captureLivenessReceipt(for: token)", range: directBLE.upperBound..<watchdog.endIndex))\n        let pendingCatch = try #require(watchdog.range(of: "MutationError.applicationAdmissionPending", range: packageReceipt.upperBound..<watchdog.endIndex))\n        let localClockAdvance = try #require(watchdog.range(of: "previousPollUptime = now", range: pendingCatch.upperBound..<watchdog.endIndex))\n        let ledgerMutation = try #require(watchdog.range(of: "self.sessionLedger.observeCurrentConnection(", range: localClockAdvance.upperBound..<watchdog.endIndex))\n        let receiptArgument = try #require(watchdog.range(of: "receipt: livenessReceipt", range: ledgerMutation.upperBound..<watchdog.endIndex))\n\n        #expect(localDrain.lowerBound < directBLE.lowerBound)\n        #expect(directBLE.lowerBound < packageReceipt.lowerBound)\n        #expect(packageReceipt.lowerBound < pendingCatch.lowerBound)\n        #expect(pendingCatch.lowerBound < localClockAdvance.lowerBound)\n        #expect(localClockAdvance.lowerBound < ledgerMutation.lowerBound)\n        #expect(ledgerMutation.lowerBound < receiptArgument.lowerBound)'''
if source.count(old) != 1:
    raise SystemExit("source watchdog assertion target drifted")
source = source.replace(old, new, 1)
old2 = '''        #expect(ledger.contains("throw MutationError.applicationAdmissionPending"))\n        #expect(ledger.contains("throw MutationError.observationAdmissionInvalidOrConsumed"))'''
new2 = '''        #expect(ledger.contains("throw MutationError.applicationAdmissionPending"))\n        #expect(ledger.contains("guard !receiptAuthority.hasPendingApplicationReceipt(for: token) else"))\n        #expect(ledger.contains("throw MutationError.observationAdmissionInvalidOrConsumed"))'''
if source.count(old2) != 1:
    raise SystemExit("source receipt authority assertion target drifted")
source_path.write_text(source.replace(old2, new2, 1))

# Effective product diff must no longer carry transient gate files.
assert not extra_path.exists()
assert Path(".github/workflows/capture-v16-standalone.yml").read_bytes() == subprocess.check_output(
    ["git", "show", f"{BASE}:.github/workflows/capture-v16-standalone.yml"]
)
assert "func delayedApplicationAdmissionUsesLedgerDeliveryTime()" in ledger_tests_path.read_text()
assert "acceptedSealCannotOvertakePendingApplicationReceipt" in ledger_tests_path.read_text()

Path(".github/workflows/capture-receipt-gate-collapse-materializer.yml").unlink()
Path(__file__).unlink()

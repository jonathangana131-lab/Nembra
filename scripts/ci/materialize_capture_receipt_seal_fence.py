#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one target, found {count}: {old[:140]!r}")
    p.write_text(text.replace(old, new, 1))


app_path = "NembraApp/App/NembraCaptureEntrypoint.swift"
replace_once(
    app_path,
    '''                previousPollUptime = now\n\n                guard self.sdkAccountLoggedIn,''',
    '''                guard self.sdkAccountLoggedIn,'''
)
replace_once(
    app_path,
    '''                } catch {\n                    await self.invalidateInternalLifecycle(\n                        token: token,\n                        message: "Liveness receipt issuance violated the current internal session lifecycle: \\(error.localizedDescription)",\n                        kind: "liveness_receipt_admission_failed"\n                    )\n                    return\n                }\n\n                do {\n                    try await self.sessionLedger.observeCurrentConnection(''',
    '''                } catch {\n                    await self.invalidateInternalLifecycle(\n                        token: token,\n                        message: "Liveness receipt issuance violated the current internal session lifecycle: \\(error.localizedDescription)",\n                        kind: "liveness_receipt_admission_failed"\n                    )\n                    return\n                }\n\n                // Only a package-issued liveness receipt advances the app's watchdog cadence. If\n                // package arbitration reports an earlier application delivery still pending, the\n                // prior poll time stays frozen and the existing 5 s continuity gate can still fail\n                // closed instead of being refreshed by a non-observation.\n                previousPollUptime = now\n\n                do {\n                    try await self.sessionLedger.observeCurrentConnection('''
)

ledger_path = "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
replace_once(
    ledger_path,
    '''    public func sealAcceptedObservation(\n        for token: TuyaReadOnlyConnectionToken\n    ) throws {\n        try requireCurrent(token)\n        let now = try nextMonotonicObservation()''',
    '''    public func sealAcceptedObservation(\n        for token: TuyaReadOnlyConnectionToken\n    ) throws {\n        try requireCurrent(token)\n        guard !receiptAuthority.hasPendingApplicationReceipt(for: token) else {\n            throw MutationError.applicationAdmissionPending\n        }\n        let now = try nextMonotonicObservation()'''
)
replace_once(
    ledger_path,
    '''        func releaseApplicationReceipt(_ receipt: TuyaReadOnlyApplicationReceipt) {\n            lock.lock()\n            defer { lock.unlock() }\n            guard receipt.issuerID == issuerID else { return }\n            pendingApplicationSequences.remove(receipt.deliverySequence)\n        }\n\n        func consumeApplicationReceipt(''',
    '''        func releaseApplicationReceipt(_ receipt: TuyaReadOnlyApplicationReceipt) {\n            lock.lock()\n            defer { lock.unlock() }\n            guard receipt.issuerID == issuerID else { return }\n            pendingApplicationSequences.remove(receipt.deliverySequence)\n        }\n\n        func hasPendingApplicationReceipt(for token: TuyaReadOnlyConnectionToken) -> Bool {\n            lock.lock()\n            defer { lock.unlock() }\n            return activeToken == token && !pendingApplicationSequences.isEmpty\n        }\n\n        func consumeApplicationReceipt('''
)

app = Path(app_path).read_text()
watchdog_start = app.index("private func startWatchdog")
watchdog_end = app.index("private func recordObservedTransportLoss", watchdog_start)
watchdog = app[watchdog_start:watchdog_end]
assert watchdog.index("captureLivenessReceipt(for: token)") < watchdog.index("previousPollUptime = now")
assert watchdog.index("previousPollUptime = now") < watchdog.index("observeCurrentConnection(")
ledger = Path(ledger_path).read_text()
assert "guard !receiptAuthority.hasPendingApplicationReceipt(for: token) else" in ledger

Path(".github/workflows/capture-receipt-seal-fence-materializer.yml").unlink()
Path(__file__).unlink()

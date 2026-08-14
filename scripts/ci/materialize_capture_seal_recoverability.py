#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


ledger_path = ROOT / "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
ledger = ledger_path.read_text(encoding="utf-8")
old = '''    public func sealAcceptedObservation(for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }
        switch receiptAuthority.beginSeal(for: token) {
        case .admitted:
            break
        case .applicationReceiptPending:
            throw MutationError.applicationAdmissionPending
        case .invalidToken:
            throw MutationError.observationAdmissionInvalidOrConsumed
        }
        let now = try nextMonotonicObservation()
        try requireContinuousAuthenticatedObservation(at: now)
        let snapshot = makeSnapshot()
        guard TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .readyForStationaryMapping else {
            throw MutationError.preflightNotReady
        }
        currentToken = nil
        latestObservedUptimeNanoseconds = now
    }
'''
new = '''    public func sealAcceptedObservation(for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }
        let now = try nextMonotonicObservation()
        try requireContinuousAuthenticatedObservation(at: now)
        let snapshot = makeSnapshot()
        guard TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .readyForStationaryMapping else {
            throw MutationError.preflightNotReady
        }
        // Readiness is already proven before the irreversible receipt-authority cut. A callback
        // delivered between the snapshot and this lock acquisition is registered as pending and
        // causes beginSeal to refuse admission, preserving both the callback and a recoverable
        // observing session instead of stranding currentToken behind a dead receipt issuer.
        switch receiptAuthority.beginSeal(for: token) {
        case .admitted:
            break
        case .applicationReceiptPending:
            throw MutationError.applicationAdmissionPending
        case .invalidToken:
            throw MutationError.observationAdmissionInvalidOrConsumed
        }
        currentToken = nil
        latestObservedUptimeNanoseconds = now
    }
'''
ledger_path.write_text(replace_once(ledger, old, new, "seal ordering"), encoding="utf-8")

test_path = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAuthenticatedTerminalHorizonTests.swift"
tests = test_path.read_text(encoding="utf-8")
old_test = '''        clock.advance(to: 300)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
'''
new_test = '''        // A refused premature seal must leave the real shipping receipt path recoverable.
        // The package-internal compatibility mutation would bypass ReceiptAuthority and therefore
        // cannot prove this invariant.
        clock.advance(to: 300)
        let delivery = try ledger.captureApplicationDelivery(for: token)
        try await ledger.recordApplicationUpdate(receipt: delivery, for: token)
        let recovered = await ledger.currentPreflightSnapshot()
        #expect(recovered.applicationPayloadCount == 1)
        #expect(recovered.latestApplicationPayloadUptimeNanoseconds == 300)
        #expect(recovered.authenticationState == .authenticated)
'''
test_path.write_text(replace_once(tests, old_test, new_test, "early seal shipping recovery test"), encoding="utf-8")

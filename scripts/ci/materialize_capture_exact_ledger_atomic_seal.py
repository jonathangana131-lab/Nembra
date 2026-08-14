#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one target, found {count}: {old[:180]!r}")
    p.write_text(text.replace(old, new, 1))


ledger_path = "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"

replace_once(
    ledger_path,
    '''        func hasPendingApplicationReceipt(for token: TuyaReadOnlyConnectionToken) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return activeToken == token && !pendingApplicationSequences.isEmpty
        }
''',
    '''        enum SealAdmissionResult {
            case admitted
            case applicationReceiptPending
            case invalidToken
        }

        /// Atomically admits immutable acceptance. No application delivery may already be pending,
        /// and successful admission simultaneously closes future receipt issuance for this exact
        /// generation before any later seal-time clock sample can overtake callback chronology.
        func beginSeal(for token: TuyaReadOnlyConnectionToken) -> SealAdmissionResult {
            lock.lock()
            defer { lock.unlock() }
            guard activeToken == token else { return .invalidToken }
            guard pendingApplicationSequences.isEmpty else {
                return .applicationReceiptPending
            }
            activeToken = nil
            lastIssuedUptimeNanoseconds = nil
            pendingApplicationSequences.removeAll(keepingCapacity: false)
            pendingLivenessSequences.removeAll(keepingCapacity: false)
            return .admitted
        }
'''
)

replace_once(
    ledger_path,
    '''    public func sealAcceptedObservation(
        for token: TuyaReadOnlyConnectionToken
    ) throws {
        try requireCurrent(token)
        guard !receiptAuthority.hasPendingApplicationReceipt(for: token) else {
            throw MutationError.applicationAdmissionPending
        }
        let now = try nextMonotonicObservation()
        try requireContinuousAuthenticatedObservation(at: now)
        let snapshot = makeSnapshot()
        guard TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .readyForStationaryMapping else {
            throw MutationError.preflightNotReady
        }
        currentToken = nil
    }
''',
    '''    public func sealAcceptedObservation(
        for token: TuyaReadOnlyConnectionToken
    ) throws {
        try requireCurrent(token)

        // Atomically reject an already-delivered application callback and close all future receipt
        // issuance before sampling any later actor-time boundary. This removes the check-then-retire
        // race between nonisolated callback admission and immutable acceptance.
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
    }
'''
)

source_test_path = "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAcceptedApplicationEvidenceSealSourceTests.swift"
source = Path(source_test_path).read_text()
old = '''        #expect(ledger.contains("guard pendingApplicationSequences.isEmpty else"))
        #expect(ledger.contains("throw MutationError.applicationAdmissionPending"))
        #expect(ledger.contains("guard !receiptAuthority.hasPendingApplicationReceipt(for: token) else"))
        #expect(ledger.contains("throw MutationError.observationAdmissionInvalidOrConsumed"))
        #expect(!ledger.contains("public func observeCurrentConnection(for token:"))
'''
new = '''        #expect(ledger.contains("guard pendingApplicationSequences.isEmpty else"))
        #expect(ledger.contains("throw MutationError.applicationAdmissionPending"))
        #expect(ledger.contains("func beginSeal(for token: TuyaReadOnlyConnectionToken) -> SealAdmissionResult"))
        #expect(ledger.contains("receiptAuthority.beginSeal(for: token)"))
        #expect(!ledger.contains("hasPendingApplicationReceipt(for token:"))
        #expect(ledger.contains("throw MutationError.observationAdmissionInvalidOrConsumed"))
        #expect(!ledger.contains("public func observeCurrentConnection(for token:"))
'''
if source.count(old) != 1:
    raise SystemExit("accepted seal source oracle drifted")
source = source.replace(old, new, 1)

# Prove atomic package cut precedes seal-time sampling in source, not merely that both exist.
needle = '''        #expect(!ledger.contains("public func observeCurrentConnection(for token:"))
    }
'''
replacement = '''        #expect(!ledger.contains("public func observeCurrentConnection(for token:"))

        let sealStart = try #require(ledger.range(of: "public func sealAcceptedObservation("))
        let sealEnd = try #require(ledger.range(of: "public func endConnection(", range: sealStart.upperBound..<ledger.endIndex))
        let seal = String(ledger[sealStart.lowerBound..<sealEnd.lowerBound])
        let atomicCut = try #require(seal.range(of: "receiptAuthority.beginSeal(for: token)"))
        let sealClock = try #require(seal.range(of: "let now = try nextMonotonicObservation()"))
        #expect(atomicCut.lowerBound < sealClock.lowerBound)
    }
'''
if source.count(needle) != 1:
    raise SystemExit("accepted seal source insertion drifted")
Path(source_test_path).write_text(source.replace(needle, replacement, 1))

tests_path = "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAuthenticatedReadOnlySessionLedgerTests.swift"
tests = Path(tests_path).read_text()
old_test = '''        clock.advance(to: 3_000)
        let pending = try ledger.captureApplicationDelivery(for: token)

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.applicationAdmissionPending) {
            try await ledger.sealAcceptedObservation(for: token)
        }
        ledger.releaseApplicationReceipt(pending)
        #expect((await ledger.currentPreflightSnapshot()).applicationPayloadCount == 0)
'''
new_test = '''        clock.advance(to: 3_000)
        let pending = try ledger.captureApplicationDelivery(for: token)

        // Deliberately delay actor seal execution beyond the continuity gap. Pending callback
        // admission must win before seal samples that later actor-time or retires the generation.
        clock.advance(to: 20_000_000_000)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.applicationAdmissionPending) {
            try await ledger.sealAcceptedObservation(for: token)
        }

        // A refused seal attempt must leave the one-shot callback receipt and generation usable.
        try await ledger.recordApplicationUpdate(receipt: pending, for: token)
        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 1)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == 3_000)
'''
if tests.count(old_test) != 1:
    raise SystemExit("pending seal runtime test drifted")
Path(tests_path).write_text(tests.replace(old_test, new_test, 1))

ledger = Path(ledger_path).read_text()
seal_start = ledger.index("public func sealAcceptedObservation(")
seal_end = ledger.index("public func endConnection(", seal_start)
seal = ledger[seal_start:seal_end]
assert seal.index("receiptAuthority.beginSeal(for: token)") < seal.index("let now = try nextMonotonicObservation()")
assert "hasPendingApplicationReceipt" not in ledger

Path(".github/workflows/capture-exact-ledger-atomic-seal-materializer.yml").unlink()
Path(__file__).unlink()

#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one target, found {count}: {old[:160]!r}")
    p.write_text(text.replace(old, new, 1))


ledger_path = "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
replace_once(
    ledger_path,
    '''    enum LivenessBoundaryResult {
        case sampled(UInt64)
        case applicationReceiptPending
        case invalidToken
    }
''',
    '''    enum LivenessBoundaryResult {
        case sampled(UInt64)
        case applicationReceiptPending
        case invalidToken
    }

    enum SealAdmissionResult {
        case admitted
        case applicationReceiptPending
        case invalidToken
    }
'''
)

replace_once(
    ledger_path,
    '''    func hasPendingApplicationReceipt(for token: TuyaReadOnlyConnectionToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard activeToken == token else { return false }
        return !pendingApplicationDeliveries.isEmpty
    }
''',
    '''    /// Atomically admits the immutable acceptance cut. A seal can proceed only when no
    /// application delivery is already pending, and successful admission simultaneously revokes
    /// all future synchronous receipt issuance for this generation before any seal-time clock
    /// sample occurs. This closes the check-then-retire race against nonisolated receipt minting.
    func beginSeal(for token: TuyaReadOnlyConnectionToken) -> SealAdmissionResult {
        lock.lock()
        defer { lock.unlock() }
        guard activeToken == token else { return .invalidToken }
        guard pendingApplicationDeliveries.isEmpty else {
            return .applicationReceiptPending
        }
        activeToken = nil
        pendingApplicationDeliveries.removeAll(keepingCapacity: false)
        consumedApplicationDeliveryIDs.removeAll(keepingCapacity: false)
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
        let now = try nextMonotonicObservation()
        try requireContinuousAuthenticatedObservation(at: now)
        let snapshot = makeSnapshot()
        guard TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .readyForStationaryMapping else {
            throw MutationError.preflightNotReady
        }
        guard !applicationDeliveryArbiter.hasPendingApplicationReceipt(for: token) else {
            throw MutationError.applicationReceiptPending
        }
        applicationDeliveryArbiter.retire(for: token)
        currentToken = nil
    }
''',
    '''    public func sealAcceptedObservation(
        for token: TuyaReadOnlyConnectionToken
    ) throws {
        try requireCurrent(token)

        // Receipt authority closes atomically before sampling any later actor-time boundary. An
        // already-delivered application callback therefore wins as pending, while a callback that
        // occurs after this cut can no longer mint evidence for the immutable accepted prefix.
        switch applicationDeliveryArbiter.beginSeal(for: token) {
        case .admitted:
            break
        case .applicationReceiptPending:
            throw MutationError.applicationReceiptPending
        case .invalidToken:
            throw MutationError.invalidApplicationReceipt
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

source_test_path = "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationReceiptArbitrationSourceTests.swift"
source = Path(source_test_path).read_text()
old_terminal = '''        for start in [
            "public func markAuthenticationFailed(",
            "public func markInternalLifecycleFailure(",
            "public func markSourceAuthorityInvalidated(",
            "public func markObservationContinuityInvalidated(",
            "public func markApplicationObservationTimedOut(",
            "public func sealAcceptedObservation(",
            "public func endConnection("
        ] {
            let section = String(try receiptArbitrationFunctionBody(in: ledger, startingAt: start))
            #expect(section.contains("applicationDeliveryArbiter.retire(for: token)"),
                    Comment(rawValue: "Every explicit current-token terminal/seal must synchronously retire pending receipt authority: \\(start)"))
        }
'''
new_terminal = '''        for start in [
            "public func markAuthenticationFailed(",
            "public func markInternalLifecycleFailure(",
            "public func markSourceAuthorityInvalidated(",
            "public func markObservationContinuityInvalidated(",
            "public func markApplicationObservationTimedOut(",
            "public func endConnection("
        ] {
            let section = String(try receiptArbitrationFunctionBody(in: ledger, startingAt: start))
            #expect(section.contains("applicationDeliveryArbiter.retire(for: token)"),
                    Comment(rawValue: "Every explicit current-token terminal must synchronously retire pending receipt authority: \\(start)"))
        }

        let seal = String(try receiptArbitrationFunctionBody(
            in: ledger,
            startingAt: "public func sealAcceptedObservation("
        ))
        let atomicCut = try receiptArbitrationRequired("applicationDeliveryArbiter.beginSeal(for: token)", in: seal)
        let sealClock = try receiptArbitrationRequired("let now = try nextMonotonicObservation()", in: seal)
        #expect(atomicCut < sealClock,
                Comment(rawValue: "Acceptance must atomically reject pending delivery and close future receipt issuance before any later seal-time clock sample."))
        #expect(seal.contains("case .applicationReceiptPending"))
        #expect(seal.contains("throw MutationError.applicationReceiptPending"))
'''
if source.count(old_terminal) != 1:
    raise SystemExit("terminal/seal source oracle drifted")
source = source.replace(old_terminal, new_terminal, 1)

needle = '''        #expect(arbiter.contains("guard pendingApplicationDeliveries.isEmpty else"))
        #expect(arbiter.contains("return .applicationReceiptPending"))
        #expect(arbiter.contains("let now = nowUptimeNanoseconds()"))
'''
replacement = '''        #expect(arbiter.contains("guard pendingApplicationDeliveries.isEmpty else"))
        #expect(arbiter.contains("return .applicationReceiptPending"))
        #expect(arbiter.contains("func beginSeal(for token: TuyaReadOnlyConnectionToken) -> SealAdmissionResult"))
        #expect(arbiter.contains("activeToken = nil"))
        #expect(arbiter.contains("let now = nowUptimeNanoseconds()"))
'''
if source.count(needle) != 1:
    raise SystemExit("arbiter source oracle drifted")
Path(source_test_path).write_text(source.replace(needle, replacement, 1))

# Add a deterministic package regression to the same already-filtered extension suite. It proves
# pending receipt wins before a deliberately late seal-time sample can terminalize continuity.
path = Path(source_test_path)
text = path.read_text()
insert = r'''

    @Test("seal refuses a pending delivered callback before sampling later actor time")
    func pendingDeliveryWinsAtomicSealCut() async throws {
        let clock = SealCutTestClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        // This receipt is delivered well inside continuity. Actor seal execution is then delayed
        // beyond the continuity gap. Correct arbitration returns pending without sampling that late
        // clock or retiring the exact generation first.
        clock.advance(to: 3_000)
        let pending = try #require(ledger.captureApplicationDelivery(for: token))
        clock.advance(to: 20_000_000_000)

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.applicationReceiptPending) {
            try await ledger.sealAcceptedObservation(for: token)
        }

        // The generation and one-shot receipt remain usable after the refused seal attempt.
        try await ledger.recordApplicationUpdate(delivery: pending, for: token)
        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 1)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == 3_000)
    }
'''
marker = "\n    private func receiptArbitrationFunctionBody"
if text.count(marker) != 1:
    raise SystemExit("source test insertion marker drifted")
text = text.replace(marker, insert + marker, 1)
path.write_text(text)

# File-private lock clock for the async package regression.
text = path.read_text()
clock_type = r'''

private final class SealCutTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    init(_ value: UInt64) { self.value = value }

    func now() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(to newValue: UInt64) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}
'''
path.write_text(text + clock_type)

ledger = Path(ledger_path).read_text()
seal_start = ledger.index("public func sealAcceptedObservation(")
seal_end = ledger.index("public func endConnection(", seal_start)
seal = ledger[seal_start:seal_end]
assert seal.index("applicationDeliveryArbiter.beginSeal(for: token)") < seal.index("let now = try nextMonotonicObservation()")
assert "hasPendingApplicationReceipt" not in ledger

Path(".github/workflows/capture-atomic-seal-cut-materializer.yml").unlink()
Path(__file__).unlink()

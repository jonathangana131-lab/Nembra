import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated read-only deadline admission")
struct TuyaAuthenticatedReadOnlyDeadlineBypassTests {
    @Test("deadline-crossing application callback cannot manufacture readiness")
    func callbackAtIncompleteHorizonFailsBeforeEvidenceMutation() async throws {
        let clock = DeadlineBypassUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        clock.advance(to: 3_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)

        let horizon = 2_000 + TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds
        try await advanceDeadlineBypassLiveness(
            clock: clock,
            ledger: ledger,
            token: token,
            from: 3_000,
            untilBefore: horizon
        )

        clock.advance(to: horizon)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 1)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == 3_000)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) != .readyForStationaryMapping)
    }
}

private func advanceDeadlineBypassLiveness(
    clock: DeadlineBypassUptimeClock,
    ledger: TuyaAuthenticatedReadOnlySessionLedger,
    token: TuyaReadOnlyConnectionToken,
    from start: UInt64,
    untilBefore target: UInt64
) async throws {
    var cursor = start
    let gap = TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds
    while cursor + gap < target {
        cursor += gap
        clock.advance(to: cursor)
        try await ledger.observeCurrentConnection(for: token)
    }
}

private final class DeadlineBypassUptimeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    init(_ value: UInt64) {
        self.value = value
    }

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

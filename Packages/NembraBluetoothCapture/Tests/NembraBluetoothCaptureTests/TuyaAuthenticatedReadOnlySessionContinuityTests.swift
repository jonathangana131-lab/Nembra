import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated observation continuity")
struct TuyaAuthenticatedReadOnlySessionContinuityTests {
    @Test("observation gap is terminal without inventing a BLE disconnect")
    func observationGapRejectsLateCallbacksAndPreservesHistory() async throws {
        let clock = ContinuityTestUptimeClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 200)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 300)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        clock.advance(to: 6_000_000_300)
        try await ledger.markObservationContinuityInvalidated(for: token)

        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Authenticated observation continuity was interrupted."))
        #expect(failed.authenticationMethod == .smartLifeAppSDK)
        #expect(failed.authenticatedAtUptimeNanoseconds == 200)
        #expect(failed.applicationPayloadCount == 1)
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == 300)
        #expect(failed.latestObservedUptimeNanoseconds == 6_000_000_300)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: failed) == .blocked(reason: "Authenticated observation continuity was interrupted."))

        clock.advance(to: 7_000_000_300)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.observeCurrentConnection(for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == failed)
    }
}

private final class ContinuityTestUptimeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    init(_ value: UInt64) {
        self.value = value
    }

    var now: @Sendable () -> UInt64 {
        { [self] in
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    func advance(to newValue: UInt64) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

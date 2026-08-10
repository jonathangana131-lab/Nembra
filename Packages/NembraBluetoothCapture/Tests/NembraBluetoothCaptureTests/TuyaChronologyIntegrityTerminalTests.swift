import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya internal-lifecycle no-clock terminal")
struct TuyaChronologyIntegrityTerminalTests {
    private static let failureReason =
        "Session authority was retired after an internal lifecycle or chronology failure."

    @Test("authentication clock regression can retire the generation without another clock sample")
    func authenticationRegressionCannotStrandCallbackAuthority() async throws {
        let clock = MutableUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: { clock.now() })
        let token = try await ledger.beginConnection()

        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        let beforeRegression = await ledger.currentPreflightSnapshot()

        clock.advance(to: 1_499)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed) {
            try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        }

        // The emergency terminal deliberately does not read the still-regressed clock.
        try await ledger.markInternalLifecycleFailure(for: token)
        let failed = await ledger.currentPreflightSnapshot()

        #expect(failed.authenticationState == .failed(reason: Self.failureReason))
        #expect(failed.authenticationMethod == nil)
        #expect(failed.authenticatedAtUptimeNanoseconds == nil)
        #expect(failed.applicationPayloadCount == 0)
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == nil)
        #expect(failed.latestObservedUptimeNanoseconds == beforeRegression.latestObservedUptimeNanoseconds)

        clock.advance(to: 2_000)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        }
    }

    @Test("post-auth clock regression preserves earned diagnostics while retiring callbacks")
    func postAuthenticationRegressionPreservesOnlyEarnedEvidence() async throws {
        let clock = MutableUptimeClock(10_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: { clock.now() })
        let token = try await ledger.beginConnection()

        clock.advance(to: 11_000)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 12_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 13_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        clock.advance(to: 14_000)
        try await ledger.observeCurrentConnection(for: token)
        let earned = await ledger.currentPreflightSnapshot()

        clock.advance(to: 13_999)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed) {
            try await ledger.observeCurrentConnection(for: token)
        }

        try await ledger.markInternalLifecycleFailure(for: token)
        let failed = await ledger.currentPreflightSnapshot()

        #expect(failed.authenticationState == .failed(reason: Self.failureReason))
        #expect(failed.authenticationMethod == earned.authenticationMethod)
        #expect(failed.authenticatedAtUptimeNanoseconds == earned.authenticatedAtUptimeNanoseconds)
        #expect(failed.applicationPayloadCount == earned.applicationPayloadCount)
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == earned.latestApplicationPayloadUptimeNanoseconds)
        #expect(failed.latestObservedUptimeNanoseconds == earned.latestObservedUptimeNanoseconds)

        clock.advance(to: 15_000)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
    }
}

private final class MutableUptimeClock: @unchecked Sendable {
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

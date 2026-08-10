import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya internal lifecycle failure terminal")
struct TuyaInternalLifecycleFailureTerminalTests {
    @Test("clock-regressed auth promotion can retire exact generation without another clock sample")
    func regressedAuthenticationPromotionRetiresWithoutClockRecovery() async throws {
        let clock = InternalLifecycleFailureClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.set(150)
        try await ledger.markAuthenticationStarted(for: token)
        let before = await ledger.currentPreflightSnapshot()
        clock.set(149)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed) {
            try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        }
        try await ledger.markInternalLifecycleFailure(for: token)
        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Session authority was retired after an internal lifecycle or chronology failure."))
        #expect(failed.authenticationMethod == nil)
        #expect(failed.authenticatedAtUptimeNanoseconds == nil)
        #expect(failed.applicationPayloadCount == 0)
        #expect(failed.latestObservedUptimeNanoseconds == before.latestObservedUptimeNanoseconds)
        clock.set(200)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        }
    }

    @Test("post-auth internal failure preserves earned evidence only diagnostically")
    func postAuthenticationFailurePreservesEarnedChronology() async throws {
        let clock = InternalLifecycleFailureClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.set(1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.set(2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.set(2_500)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        let earned = await ledger.currentPreflightSnapshot()
        clock.set(1)
        try await ledger.markInternalLifecycleFailure(for: token)
        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Session authority was retired after an internal lifecycle or chronology failure."))
        #expect(failed.authenticationMethod == earned.authenticationMethod)
        #expect(failed.authenticatedAtUptimeNanoseconds == earned.authenticatedAtUptimeNanoseconds)
        #expect(failed.applicationPayloadCount == earned.applicationPayloadCount)
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == earned.latestApplicationPayloadUptimeNanoseconds)
        #expect(failed.latestObservedUptimeNanoseconds == earned.latestObservedUptimeNanoseconds)
    }
}

private final class InternalLifecycleFailureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64
    init(_ value: UInt64) { self.value = value }
    var now: @Sendable () -> UInt64 {
        { [self] in lock.lock(); defer { lock.unlock() }; return value }
    }
    func set(_ newValue: UInt64) { lock.lock(); value = newValue; lock.unlock() }
}

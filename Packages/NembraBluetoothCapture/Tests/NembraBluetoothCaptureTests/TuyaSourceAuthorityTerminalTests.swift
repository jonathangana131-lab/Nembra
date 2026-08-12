import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya source-authority terminal")
struct TuyaSourceAuthorityTerminalTests {
    @Test("source authority can retire an authenticating generation without leaving callback authority")
    func authenticatingAuthorityLossIsTerminal() async throws {
        let clock = SourceAuthorityTestClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 110)
        try await ledger.markAuthenticationStarted(for: token)
        let before = await ledger.currentPreflightSnapshot()
        clock.advance(to: 120)
        try await ledger.markSourceAuthorityInvalidated(for: token)
        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Tuya SDK source authority was invalidated."))
        #expect(failed.authenticationMethod == nil)
        #expect(failed.authenticatedAtUptimeNanoseconds == nil)
        #expect(failed.applicationPayloadCount == 0)
        #expect(failed.latestObservedUptimeNanoseconds == before.latestObservedUptimeNanoseconds)
        clock.advance(to: 130)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        }
        #expect(await ledger.currentPreflightSnapshot() == failed)
    }

    @Test("post-auth source authority loss preserves earned chronology without inventing liveness")
    func authenticatedAuthorityLossPreservesEarnedPrefix() async throws {
        let clock = SourceAuthorityTestClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_100)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 1_200)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 1_300)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        clock.advance(to: 1_400)
        try await ledger.observeCurrentConnection(for: token)
        let before = await ledger.currentPreflightSnapshot()
        clock.advance(to: 1_900)
        try await ledger.markSourceAuthorityInvalidated(for: token)
        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Tuya SDK source authority was invalidated."))
        #expect(failed.authenticationMethod == .smartLifeAppSDK)
        #expect(failed.authenticatedAtUptimeNanoseconds == before.authenticatedAtUptimeNanoseconds)
        #expect(failed.applicationPayloadCount == before.applicationPayloadCount)
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == before.latestApplicationPayloadUptimeNanoseconds)
        #expect(failed.latestObservedUptimeNanoseconds == before.latestObservedUptimeNanoseconds)
        clock.advance(to: 2_000)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.observeCurrentConnection(for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == failed)
    }

    @Test("waiting generation can be retired when source authority disappears before authentication starts")
    func waitingAuthorityLossIsTerminal() async throws {
        let clock = SourceAuthorityTestClock(10)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        let before = await ledger.currentPreflightSnapshot()
        clock.advance(to: 20)
        try await ledger.markSourceAuthorityInvalidated(for: token)
        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Tuya SDK source authority was invalidated."))
        #expect(failed.authenticationMethod == nil)
        #expect(failed.authenticatedAtUptimeNanoseconds == nil)
        #expect(failed.latestObservedUptimeNanoseconds == before.latestObservedUptimeNanoseconds)
        #expect(failed.applicationPayloadCount == 0)
    }

    @Test("terminal deadlines and late SDK failure do not manufacture later liveness")
    func nonLivenessTerminalsPreserveLastObservedReceipt() async throws {
        let timeoutClock = SourceAuthorityTestClock(100)
        let timeoutLedger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: timeoutClock.now)
        let timeoutToken = try await timeoutLedger.beginConnection()
        timeoutClock.advance(to: 110)
        try await timeoutLedger.markAuthenticationStarted(for: timeoutToken)
        timeoutClock.advance(to: 120)
        try await timeoutLedger.markAuthenticated(for: timeoutToken, method: .smartLifeAppSDK)
        timeoutClock.advance(to: 130)
        try await timeoutLedger.observeCurrentConnection(for: timeoutToken)
        let timeoutBefore = await timeoutLedger.currentPreflightSnapshot()
        timeoutClock.advance(to: 9_000)
        try await timeoutLedger.markApplicationObservationTimedOut(for: timeoutToken)
        #expect((await timeoutLedger.currentPreflightSnapshot()).latestObservedUptimeNanoseconds == timeoutBefore.latestObservedUptimeNanoseconds)

        let failureClock = SourceAuthorityTestClock(1_000)
        let failureLedger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: failureClock.now)
        let failureToken = try await failureLedger.beginConnection()
        failureClock.advance(to: 1_100)
        try await failureLedger.markAuthenticationStarted(for: failureToken)
        failureClock.advance(to: 1_200)
        try await failureLedger.markAuthenticated(for: failureToken, method: .smartLifeAppSDK)
        failureClock.advance(to: 1_300)
        try await failureLedger.observeCurrentConnection(for: failureToken)
        let failureBefore = await failureLedger.currentPreflightSnapshot()
        failureClock.advance(to: 1_900)
        try await failureLedger.markAuthenticationFailed(for: failureToken)
        #expect((await failureLedger.currentPreflightSnapshot()).latestObservedUptimeNanoseconds == failureBefore.latestObservedUptimeNanoseconds)
    }

    @Test("explicit continuity terminal uses canonical package reason and frozen horizon")
    func explicitContinuityTerminalIsCanonical() async throws {
        let clock = SourceAuthorityTestClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 110)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 120)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 130)
        try await ledger.observeCurrentConnection(for: token)
        let before = await ledger.currentPreflightSnapshot()
        clock.advance(to: 140)
        try await ledger.markObservationContinuityInvalidated(for: token)
        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Authenticated observation continuity was invalidated by a long observation gap."))
        #expect(failed.latestObservedUptimeNanoseconds == before.latestObservedUptimeNanoseconds)
    }
}

private final class SourceAuthorityTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    init(_ value: UInt64) { self.value = value }

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

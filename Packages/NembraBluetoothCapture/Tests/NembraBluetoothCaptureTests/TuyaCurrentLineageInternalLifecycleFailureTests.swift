import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya current-lineage internal lifecycle failure terminal")
struct TuyaCurrentLineageInternalLifecycleFailureTests {
    @Test("waiting generation can retire even when auth-start chronology regresses")
    func waitingGenerationRetiresAfterAuthenticationStartRegression() async throws {
        let clock = CurrentLineageLifecycleClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        let waiting = await ledger.currentPreflightSnapshot()

        clock.set(99)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed) {
            try await ledger.markAuthenticationStarted(for: token)
        }

        try await ledger.markInternalLifecycleFailure(for: token)
        let failed = await ledger.currentPreflightSnapshot()

        #expect(failed.authenticationState == .failed(reason: "Session authority was retired after an internal lifecycle or chronology failure."))
        #expect(failed.authenticationMethod == nil)
        #expect(failed.authenticatedAtUptimeNanoseconds == nil)
        #expect(failed.applicationPayloadCount == 0)
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == nil)
        #expect(failed.latestObservedUptimeNanoseconds == waiting.latestObservedUptimeNanoseconds)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: failed) == .blocked(reason: "Session authority was retired after an internal lifecycle or chronology failure."))

        clock.set(200)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.markAuthenticationStarted(for: token)
        }
    }

    @Test("auth promotion can retire exact generation without clock recovery")
    func regressedAuthenticationPromotionRetiresWithoutClockRecovery() async throws {
        let clock = CurrentLineageLifecycleClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.set(150)
        try await ledger.markAuthenticationStarted(for: token)
        let beforeRegression = await ledger.currentPreflightSnapshot()

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
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == nil)
        #expect(failed.latestObservedUptimeNanoseconds == beforeRegression.latestObservedUptimeNanoseconds)

        clock.set(200)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        }
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.markSourceAuthorityInvalidated(for: token)
        }
    }

    @Test("post-auth internal failure preserves earned evidence only as diagnostics")
    func postAuthenticationFailurePreservesEarnedChronology() async throws {
        let clock = CurrentLineageLifecycleClock(1_000)
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
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: failed) == .blocked(reason: "Session authority was retired after an internal lifecycle or chronology failure."))
    }
}

private final class CurrentLineageLifecycleClock: @unchecked Sendable {
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

    func set(_ newValue: UInt64) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

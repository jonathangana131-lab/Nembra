import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya current terminal recovery")
struct TuyaCurrentTerminalRecoveryTests {
    @Test("authentication success still requires explicit auth-start transition")
    func explicitAuthenticationStartRemainsRequired() async throws {
        let clock = TerminalRecoveryClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.invalidAuthenticationTransition) {
            try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        }

        clock.advance(to: 200)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 300)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        #expect((await ledger.currentPreflightSnapshot()).authenticationState == .authenticated)
    }

    @Test("late SDK terminal failure preserves earned chronology and retires callbacks")
    func lateAuthenticationFailureIsTerminal() async throws {
        let clock = TerminalRecoveryClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 200)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 300)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 400)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        clock.advance(to: 500)
        try await ledger.markAuthenticationFailed(for: token)

        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Tuya SDK session failed."))
        #expect(failed.authenticationMethod == .smartLifeAppSDK)
        #expect(failed.authenticatedAtUptimeNanoseconds == 300)
        #expect(failed.applicationPayloadCount == 1)
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == 400)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.observeCurrentConnection(for: token)
        }
    }

    @Test("long authenticated observation gap fails before liveness can advance")
    func longGapCannotBeErased() async throws {
        let clock = TerminalRecoveryClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 200)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 300)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 400)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        clock.advance(to: 5_000_000_401)

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated) {
            try await ledger.observeCurrentConnection(for: token)
        }
        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Authenticated observation continuity was invalidated by a long observation gap."))
        #expect(failed.latestObservedUptimeNanoseconds == 400)
        #expect(failed.applicationPayloadCount == 1)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
    }

    @Test("no-application deadline is terminal without inventing disconnect")
    func applicationTimeoutPreservesAuthenticationFact() async throws {
        let clock = TerminalRecoveryClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 200)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 300)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 1_000)
        try await ledger.markApplicationObservationTimedOut(for: token)

        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Authenticated session produced no application update before the observation deadline."))
        #expect(failed.authenticationMethod == .smartLifeAppSDK)
        #expect(failed.authenticatedAtUptimeNanoseconds == 300)
        #expect(failed.applicationPayloadCount == 0)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.observeCurrentConnection(for: token)
        }
    }

    @Test("canonical ready prefix seals without accepting later callbacks")
    func acceptedPrefixBecomesImmutable() async throws {
        let clock = TerminalRecoveryClock(0)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 1_000_000_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)

        for second in stride(from: 5, through: 45, by: 5) {
            clock.advance(to: UInt64(second) * 1_000_000_000 + 2)
            try await ledger.observeCurrentConnection(for: token)
        }

        let ready = await ledger.currentPreflightSnapshot()
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: ready) == .readyForStationaryMapping)
        try await ledger.sealAcceptedObservation(for: token)
        let sealed = await ledger.currentPreflightSnapshot()

        clock.advance(to: 46_000_000_002)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == sealed)
    }
}

private final class TerminalRecoveryClock: @unchecked Sendable {
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

import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya terminal witnessed-liveness clock")
struct TuyaTerminalWitnessClockTests {
    @Test("continuity invalidation does not manufacture a later liveness observation")
    func continuityInvalidationFreezesWitnessedClock() async throws {
        let clock = WitnessClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await authenticatedSession(ledger: ledger, clock: clock)

        clock.advance(to: 300)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        clock.advance(to: 400)
        try await ledger.observeCurrentConnection(for: token)
        let before = await ledger.currentPreflightSnapshot()

        clock.advance(to: 6_000_000_400)
        try await ledger.markObservationContinuityInvalidated(for: token)
        let terminal = await ledger.currentPreflightSnapshot()

        #expect(terminal.authenticationState == .failed(reason: "Authenticated observation continuity was invalidated."))
        #expect(terminal.authenticationMethod == before.authenticationMethod)
        #expect(terminal.authenticatedAtUptimeNanoseconds == before.authenticatedAtUptimeNanoseconds)
        #expect(terminal.applicationPayloadCount == before.applicationPayloadCount)
        #expect(terminal.latestApplicationPayloadUptimeNanoseconds == before.latestApplicationPayloadUptimeNanoseconds)
        #expect(terminal.latestObservedUptimeNanoseconds == before.latestObservedUptimeNanoseconds)

        clock.advance(to: 7_000_000_400)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == terminal)
    }

    @Test("no-application deadline does not become witnessed liveness")
    func applicationTimeoutFreezesWitnessedClock() async throws {
        let clock = WitnessClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await authenticatedSession(ledger: ledger, clock: clock)
        let before = await ledger.currentPreflightSnapshot()

        clock.advance(to: 70_000_000_000)
        try await ledger.markApplicationObservationTimedOut(for: token)
        let terminal = await ledger.currentPreflightSnapshot()

        #expect(terminal.authenticationState == .failed(reason: "Authenticated session produced no application update before the observation deadline."))
        #expect(terminal.latestObservedUptimeNanoseconds == before.latestObservedUptimeNanoseconds)
        #expect(terminal.authenticatedAtUptimeNanoseconds == before.authenticatedAtUptimeNanoseconds)
        #expect(terminal.applicationPayloadCount == 0)
    }

    @Test("late SDK failure preserves earned chronology and does not advance liveness")
    func lateSDKFailurePreservesEarnedHistory() async throws {
        let clock = WitnessClock(10)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await authenticatedSession(ledger: ledger, clock: clock)
        clock.advance(to: 30)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        clock.advance(to: 40)
        try await ledger.observeCurrentConnection(for: token)
        let before = await ledger.currentPreflightSnapshot()

        clock.advance(to: 90)
        try await ledger.markAuthenticationFailed(for: token)
        let terminal = await ledger.currentPreflightSnapshot()

        #expect(terminal.authenticationState == .failed(reason: "Tuya SDK session failed."))
        #expect(terminal.authenticationMethod == before.authenticationMethod)
        #expect(terminal.authenticatedAtUptimeNanoseconds == before.authenticatedAtUptimeNanoseconds)
        #expect(terminal.applicationPayloadCount == before.applicationPayloadCount)
        #expect(terminal.latestApplicationPayloadUptimeNanoseconds == before.latestApplicationPayloadUptimeNanoseconds)
        #expect(terminal.latestObservedUptimeNanoseconds == before.latestObservedUptimeNanoseconds)

        clock.advance(to: 100)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.observeCurrentConnection(for: token)
        }
    }

    @Test("pre-auth SDK failure retains no never-earned authentication evidence")
    func preAuthFailureRemainsEmpty() async throws {
        let clock = WitnessClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 150)
        try await ledger.markAuthenticationStarted(for: token)
        let before = await ledger.currentPreflightSnapshot()

        clock.advance(to: 200)
        try await ledger.markAuthenticationFailed(for: token)
        let failed = await ledger.currentPreflightSnapshot()

        #expect(failed.authenticationState == .failed(reason: "Tuya SDK session failed."))
        #expect(failed.authenticationMethod == nil)
        #expect(failed.authenticatedAtUptimeNanoseconds == nil)
        #expect(failed.applicationPayloadCount == 0)
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == nil)
        #expect(failed.latestObservedUptimeNanoseconds == before.latestObservedUptimeNanoseconds)
    }

    private func authenticatedSession(
        ledger: TuyaAuthenticatedReadOnlySessionLedger,
        clock: WitnessClock
    ) async throws -> TuyaReadOnlyConnectionToken {
        let token = try await ledger.beginConnection()
        clock.advance(by: 10)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(by: 10)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        return token
    }
}

private final class WitnessClock: @unchecked Sendable {
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

    func advance(by delta: UInt64) {
        lock.lock()
        value += delta
        lock.unlock()
    }
}

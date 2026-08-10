import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated terminal horizons")
struct TuyaAuthenticatedTerminalHorizonTests {
    @Test("accepted prefix freezes and rejects every late mutation")
    func acceptedPrefixIsImmutable() async throws {
        let clock = TerminalClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        clock.advance(to: 2_000 + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds)
        try await ledger.observeCurrentConnection(for: token)

        let ready = await ledger.currentPreflightSnapshot()
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: ready) == .readyForStationaryMapping)
        try await ledger.sealAcceptedObservation(for: token)
        let sealed = await ledger.currentPreflightSnapshot()

        clock.advance(to: 90_000_000_000)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.observeCurrentConnection(for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == sealed)
    }

    @Test("ready seal cannot be forged early")
    func earlySealFailsClosed() async throws {
        let clock = TerminalClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 200)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.preflightNotReady) {
            try await ledger.sealAcceptedObservation(for: token)
        }

        clock.advance(to: 300)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
    }

    @Test("no-application deadline is terminal without inventing disconnect")
    func applicationTimeoutIsDistinctTerminalFact() async throws {
        let clock = TerminalClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        clock.advance(to: 60_000_002_000)
        try await ledger.markApplicationObservationTimedOut(for: token)
        let terminal = await ledger.currentPreflightSnapshot()

        #expect(terminal.authenticationState == .failed(reason: "Authenticated session produced no application update before the observation deadline."))
        #expect(terminal.authenticationMethod == .smartLifeAppSDK)
        #expect(terminal.authenticatedAtUptimeNanoseconds == 2_000)
        #expect(terminal.applicationPayloadCount == 0)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: terminal) == .blocked(reason: "Authenticated session produced no application update before the observation deadline."))

        clock.advance(to: 61_000_002_000)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == terminal)
    }

    @Test("continuity invalidation preserves earned evidence but retires callbacks")
    func continuityInvalidationIsTerminal() async throws {
        let clock = TerminalClock(10)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 20)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 30)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        let before = await ledger.currentPreflightSnapshot()

        clock.advance(to: 40)
        try await ledger.markObservationContinuityInvalidated(for: token)
        let terminal = await ledger.currentPreflightSnapshot()

        #expect(terminal.authenticationState == .failed(reason: "Authenticated observation continuity was invalidated."))
        #expect(terminal.authenticationMethod == before.authenticationMethod)
        #expect(terminal.authenticatedAtUptimeNanoseconds == before.authenticatedAtUptimeNanoseconds)
        #expect(terminal.applicationPayloadCount == before.applicationPayloadCount)
        #expect(terminal.latestApplicationPayloadUptimeNanoseconds == before.latestApplicationPayloadUptimeNanoseconds)

        clock.advance(to: 50)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.observeCurrentConnection(for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == terminal)
    }

    @Test("late SDK failure after authentication clears authority and retires token")
    func lateSDKFailureRetiresToken() async throws {
        let clock = TerminalClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 200)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 300)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        clock.advance(to: 400)
        try await ledger.markAuthenticationFailed(for: token)

        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Tuya authentication failed."))
        #expect(failed.authenticationMethod == nil)
        #expect(failed.authenticatedAtUptimeNanoseconds == nil)
        #expect(failed.applicationPayloadCount == 0)

        clock.advance(to: 500)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == failed)
    }

    @Test("true transport end remains distinct from continuity invalidation")
    func disconnectKeepsTransportSemantics() async throws {
        let clock = TerminalClock(1)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 2)
        try await ledger.endConnection(for: token)

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.authenticationState == .unavailable(reason: "Bluetooth connection ended."))
    }
}

private final class TerminalClock: @unchecked Sendable {
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

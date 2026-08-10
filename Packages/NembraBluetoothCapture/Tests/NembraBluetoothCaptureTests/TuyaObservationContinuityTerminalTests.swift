import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya observation continuity terminal")
struct TuyaObservationContinuityTerminalTests {
    @Test("continuity invalidation preserves the last witnessed chronology and retires callback authority")
    func continuityInvalidationIsTerminal() async throws {
        let clock = ContinuityTestClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        clock.advance(to: 4_000)
        try await ledger.observeCurrentConnection(for: token)
        let before = await ledger.currentPreflightSnapshot()

        // Gap discovery is negative evidence. Advancing the test clock here must not
        // become a successful liveness receipt in the terminal snapshot.
        clock.advance(to: 9_000)
        try await ledger.markObservationContinuityInvalidated(for: token)
        let terminal = await ledger.currentPreflightSnapshot()

        #expect(terminal.authenticationState == .failed(reason: "Authenticated observation continuity was invalidated."))
        #expect(terminal.authenticationMethod == .smartLifeAppSDK)
        #expect(terminal.connectionStartedAtUptimeNanoseconds == before.connectionStartedAtUptimeNanoseconds)
        #expect(terminal.authenticatedAtUptimeNanoseconds == before.authenticatedAtUptimeNanoseconds)
        #expect(terminal.applicationPayloadCount == before.applicationPayloadCount)
        #expect(terminal.latestApplicationPayloadUptimeNanoseconds == before.latestApplicationPayloadUptimeNanoseconds)
        #expect(terminal.latestObservedUptimeNanoseconds == before.latestObservedUptimeNanoseconds)
        #expect(terminal.latestObservedUptimeNanoseconds == 4_000)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: terminal) == .blocked(reason: "Authenticated observation continuity was invalidated."))

        clock.advance(to: 10_000)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.observeCurrentConnection(for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == terminal)
    }

    @Test("pre-auth continuity invalidation is rejected without retiring or mutating the attempt")
    func preAuthInvalidationIsNonMutating() async throws {
        let clock = ContinuityTestClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        let before = await ledger.currentPreflightSnapshot()

        clock.advance(to: 200)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.authenticationRequired) {
            try await ledger.markObservationContinuityInvalidated(for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == before)

        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 300)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        let authenticated = await ledger.currentPreflightSnapshot()
        #expect(authenticated.authenticationState == .authenticated)
        #expect(authenticated.authenticatedAtUptimeNanoseconds == 300)
    }

    @Test("foreign continuity token cannot mutate the owner ledger")
    func foreignTokenIsRejectedWithoutMutation() async throws {
        let ownerClock = ContinuityTestClock(100)
        let foreignClock = ContinuityTestClock(500)
        let owner = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: ownerClock.now)
        let foreign = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: foreignClock.now)

        let ownerToken = try await owner.beginConnection()
        ownerClock.advance(to: 150)
        try await owner.markAuthenticationStarted(for: ownerToken)
        ownerClock.advance(to: 200)
        try await owner.markAuthenticated(for: ownerToken, method: .smartLifeAppSDK)
        let before = await owner.currentPreflightSnapshot()

        let foreignToken = try await foreign.beginConnection()
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection) {
            try await owner.markObservationContinuityInvalidated(for: foreignToken)
        }
        #expect(await owner.currentPreflightSnapshot() == before)

        ownerClock.advance(to: 300)
        try await owner.observeCurrentConnection(for: ownerToken)
        #expect((await owner.currentPreflightSnapshot()).latestObservedUptimeNanoseconds == 300)
    }

    @Test("superseded generation cannot invalidate the current generation")
    func staleGenerationIsRejectedWithoutMutation() async throws {
        let clock = ContinuityTestClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let staleToken = try await ledger.beginConnection()
        clock.advance(to: 200)
        let currentToken = try await ledger.beginConnection()
        let before = await ledger.currentPreflightSnapshot()

        clock.advance(to: 300)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection) {
            try await ledger.markObservationContinuityInvalidated(for: staleToken)
        }
        #expect(await ledger.currentPreflightSnapshot() == before)

        try await ledger.markAuthenticationStarted(for: currentToken)
        #expect((await ledger.currentPreflightSnapshot()).authenticationState == .authenticating)
    }

    @Test("ordinary connection end remains distinct from observation invalidation")
    func connectionEndKeepsDisconnectSemantics() async throws {
        let clock = ContinuityTestClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 200)
        try await ledger.endConnection(for: token)

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.authenticationState == .unavailable(reason: "Bluetooth connection ended."))
    }
}

private final class ContinuityTestClock: @unchecked Sendable {
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

import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated observation continuity authority")
struct TuyaAuthenticatedReadOnlySessionContinuityAuthorityTests {
    @Test("continuity invalidation freezes the last legitimate liveness receipt")
    func invalidationDoesNotManufactureObservationTime() async throws {
        let clock = ContinuityAuthorityClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 200)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 300)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        clock.advance(to: 400)
        try await ledger.observeCurrentConnection(for: token)

        let lastWitnessed = await ledger.currentPreflightSnapshot()
        #expect(lastWitnessed.latestObservedUptimeNanoseconds == 400)

        // The controller may discover a long gap much later. Discovering that gap is
        // negative evidence; it is not a successful local-BLE liveness observation.
        clock.advance(to: 6_000_000_400)
        try await ledger.markObservationContinuityInvalidated(for: token)

        let failed = await ledger.currentPreflightSnapshot()
        #expect(
            failed.authenticationState
                == .failed(reason: "Authenticated observation continuity was invalidated.")
        )
        #expect(failed.authenticationMethod == lastWitnessed.authenticationMethod)
        #expect(
            failed.authenticatedAtUptimeNanoseconds
                == lastWitnessed.authenticatedAtUptimeNanoseconds
        )
        #expect(failed.applicationPayloadCount == lastWitnessed.applicationPayloadCount)
        #expect(
            failed.latestApplicationPayloadUptimeNanoseconds
                == lastWitnessed.latestApplicationPayloadUptimeNanoseconds
        )
        #expect(
            failed.latestObservedUptimeNanoseconds
                == lastWitnessed.latestObservedUptimeNanoseconds
        )
        #expect(failed.latestObservedUptimeNanoseconds == 400)
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.verdict(for: failed)
                == .blocked(reason: "Authenticated observation continuity was invalidated.")
        )

        clock.advance(to: 7_000_000_400)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.observeCurrentConnection(for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == failed)
    }

    @Test("pre-auth continuity invalidation is rejected without mutating the active attempt")
    func preAuthInvalidationIsNonMutating() async throws {
        let clock = ContinuityAuthorityClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        let before = await ledger.currentPreflightSnapshot()

        clock.advance(to: 200)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.authenticationRequired) {
            try await ledger.markObservationContinuityInvalidated(for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == before)

        // The rejected terminal attempt must not retire or poison the current token.
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 300)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        let authenticated = await ledger.currentPreflightSnapshot()
        #expect(authenticated.authenticationState == .authenticated)
        #expect(authenticated.authenticatedAtUptimeNanoseconds == 300)
    }

    @Test("foreign continuity token cannot mutate the owner ledger")
    func foreignTokenIsRejectedWithoutMutation() async throws {
        let ownerClock = ContinuityAuthorityClock(100)
        let foreignClock = ContinuityAuthorityClock(500)
        let owner = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: ownerClock.now)
        let foreign = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: foreignClock.now)

        let ownerToken = try await owner.beginConnection()
        ownerClock.advance(to: 200)
        try await owner.markAuthenticated(for: ownerToken, method: .smartLifeAppSDK)
        let before = await owner.currentPreflightSnapshot()

        let foreignToken = try await foreign.beginConnection()
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection) {
            try await owner.markObservationContinuityInvalidated(for: foreignToken)
        }
        #expect(await owner.currentPreflightSnapshot() == before)

        // Owner authority is still live after rejecting the foreign token.
        ownerClock.advance(to: 300)
        try await owner.observeCurrentConnection(for: ownerToken)
        #expect((await owner.currentPreflightSnapshot()).latestObservedUptimeNanoseconds == 300)
    }

    @Test("superseded generation cannot invalidate the current generation")
    func staleGenerationIsRejectedWithoutMutation() async throws {
        let clock = ContinuityAuthorityClock(100)
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
}

private final class ContinuityAuthorityClock: @unchecked Sendable {
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

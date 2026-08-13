import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated read-only incomplete horizon")
struct TuyaAuthenticatedReadOnlyHorizonTests {
    @Test("one bootstrap application callback retires at the incomplete horizon")
    func bootstrapCallbackCannotKeepGenerationAlive() async throws {
        let clock = HorizonTestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)

        let horizon = 2_000 + TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds
        try await advanceHorizonLiveness(
            clock: clock,
            ledger: ledger,
            token: token,
            from: 3_000,
            untilBefore: horizon
        )

        clock.advance(to: horizon)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached) {
            try await ledger.observeCurrentConnection(for: token)
        }

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 1)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) != .readyForStationaryMapping)
    }

    @Test("application callback cannot rescue an expired incomplete generation")
    func applicationCallbackCannotRescueExpiredGeneration() async throws {
        let clock = HorizonTestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)

        let horizon = 2_000 + TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds
        try await advanceHorizonLiveness(
            clock: clock,
            ledger: ledger,
            token: token,
            from: 3_000,
            untilBefore: horizon
        )

        clock.advance(to: horizon)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 1)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == 3_000)
        #expect(snapshot.latestObservedUptimeNanoseconds == horizon)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) != .readyForStationaryMapping)
    }

    @Test("Device Sharing provenance cannot enter authenticated BLE chronology")
    func deviceSharingProvenanceIsRejectedBeforeAuthenticatedChronology() async throws {
        let clock = HorizonTestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.invalidAuthenticationTransition) {
            try await ledger.markAuthenticated(for: token, method: .documentedDeviceSharing)
        }

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.authenticationState == .authenticating)
        #expect(snapshot.authenticationMethod == nil)
        #expect(snapshot.authenticatedAtUptimeNanoseconds == nil)
        #expect(snapshot.latestObservedUptimeNanoseconds == 1_500)
        #expect(snapshot.applicationPayloadCount == 0)
    }

    @Test("non-authoritative authenticated snapshot still fails closed at incomplete horizon")
    func nonAuthoritativeSnapshotRetiresAtIncompleteHorizon() {
        let authenticatedAt: UInt64 = 2_000
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .documentedDeviceSharing,
            connectionStartedAtUptimeNanoseconds: 1_000,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: authenticatedAt + TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds,
            applicationPayloadCount: 1,
            latestApplicationPayloadUptimeNanoseconds: authenticatedAt + 1_000,
            connectionGeneration: 1
        )

        #expect(TuyaAuthenticatedReadOnlyPreflight.shouldRetireIncompleteObservation(snapshot))
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot)
                == .blocked(reason: "Tuya Device Sharing proves account/device authority, not authentication of the current BLE connection generation.")
        )
    }

    @Test("canonically ready generation survives the incomplete horizon")
    func readyGenerationIsNotRetiredAtHorizon() async throws {
        let clock = HorizonTestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)

        let latePayload = 2_000 + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds + 1
        try await advanceHorizonLiveness(
            clock: clock,
            ledger: ledger,
            token: token,
            from: 3_000,
            untilBefore: latePayload
        )
        clock.advance(to: latePayload)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)

        let horizon = 2_000 + TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds
        try await advanceHorizonLiveness(
            clock: clock,
            ledger: ledger,
            token: token,
            from: latePayload,
            untilBefore: horizon
        )
        clock.advance(to: horizon)
        try await ledger.observeCurrentConnection(for: token)

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 2)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .readyForStationaryMapping)
        #expect(TuyaAuthenticatedReadOnlyPreflight.shouldRetireIncompleteObservation(snapshot) == false)
    }
}

private func advanceHorizonLiveness(
    clock: HorizonTestUptimeClock,
    ledger: TuyaAuthenticatedReadOnlySessionLedger,
    token: TuyaReadOnlyConnectionToken,
    from start: UInt64,
    untilBefore target: UInt64
) async throws {
    var cursor = start
    let gap = TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds
    while cursor + gap < target {
        cursor += gap
        clock.advance(to: cursor)
        try await ledger.observeCurrentConnection(for: token)
    }
}

private final class HorizonTestUptimeClock: @unchecked Sendable {
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

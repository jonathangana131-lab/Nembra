import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated observation continuity")
struct TuyaAuthenticatedReadOnlySessionContinuityTests {
    @Test("queued application update cannot erase a long observation gap")
    func queuedUpdateAfterGapFailsBeforeAdvancingChronology() async throws {
        let clock = ContinuityTestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        let beforeGap = await ledger.currentPreflightSnapshot()

        clock.advance(
            to: 2_000
                + TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds
                + 1
        )
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }

        let failed = await ledger.currentPreflightSnapshot()
        #expect(
            failed.authenticationState
                == .failed(reason: "Authenticated observation continuity was invalidated by a long observation gap.")
        )
        #expect(failed.authenticationMethod == .smartLifeAppSDK)
        #expect(failed.applicationPayloadCount == 0)
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == nil)
        #expect(failed.latestObservedUptimeNanoseconds == beforeGap.latestObservedUptimeNanoseconds)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.observeCurrentConnection(for: token)
        }
    }

    @Test("exact maximum observation gap is still admitted")
    func exactGapBoundaryIsAccepted() async throws {
        let clock = ContinuityTestUptimeClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 200)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(
            to: 200 + TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds
        )
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.authenticationState == .authenticated)
        #expect(snapshot.applicationPayloadCount == 1)
    }

    @Test("liveness after a long gap also retires callback authority")
    func livenessAfterGapFailsClosed() async throws {
        let clock = ContinuityTestUptimeClock(10)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 20)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(
            to: 20
                + TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds
                + 1
        )
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated) {
            try await ledger.observeCurrentConnection(for: token)
        }
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
    }

    @Test("explicit observation invalidation preserves last legitimate chronology")
    func explicitObservationInvalidationDoesNotMintLiveness() async throws {
        let clock = ContinuityTestUptimeClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 200)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 300)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        let before = await ledger.currentPreflightSnapshot()

        clock.advance(to: 6_000_000_300)
        try await ledger.markObservationContinuityInvalidated(for: token)

        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Authenticated observation continuity was interrupted."))
        #expect(failed.authenticationMethod == .smartLifeAppSDK)
        #expect(failed.authenticatedAtUptimeNanoseconds == 200)
        #expect(failed.applicationPayloadCount == 1)
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == 300)
        #expect(failed.latestObservedUptimeNanoseconds == before.latestObservedUptimeNanoseconds)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: failed) == .blocked(reason: "Authenticated observation continuity was interrupted."))

        clock.advance(to: 7_000_000_300)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == failed)
    }

    @Test("accepted canonical prefix becomes immutable after continuous horizon")
    func acceptedSealRejectsLateCallbacks() async throws {
        let clock = ContinuityTestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)

        let target = 2_000 + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds
        try await advanceContinuously(clock: clock, ledger: ledger, token: token, from: 3_000, through: target)
        try await ledger.sealAcceptedObservation(for: token)
        let sealed = await ledger.currentPreflightSnapshot()

        clock.advance(to: target + 1)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == sealed)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: sealed) == .readyForStationaryMapping)
    }
}

private func advanceContinuously(
    clock: ContinuityTestUptimeClock,
    ledger: TuyaAuthenticatedReadOnlySessionLedger,
    token: TuyaReadOnlyConnectionToken,
    from start: UInt64,
    through target: UInt64
) async throws {
    var cursor = start
    let gap = TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds
    while cursor < target {
        cursor = min(target, cursor + gap)
        clock.advance(to: cursor)
        try await ledger.observeCurrentConnection(for: token)
    }
}

private final class ContinuityTestUptimeClock: @unchecked Sendable {
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

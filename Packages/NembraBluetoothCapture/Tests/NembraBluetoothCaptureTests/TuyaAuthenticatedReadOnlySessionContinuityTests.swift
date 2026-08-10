import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated session continuity horizons")
struct TuyaAuthenticatedReadOnlySessionContinuityTests {
    @Test("queued application update cannot erase a long observation gap")
    func queuedUpdateAfterGapFailsBeforeAdvancingChronology() async throws {
        let clock = ContinuityTestClock(1_000)
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
        #expect(failed.applicationPayloadCount == 0)
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == nil)
        #expect(failed.latestObservedUptimeNanoseconds == beforeGap.latestObservedUptimeNanoseconds)
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.verdict(for: failed)
                == .blocked(reason: "Authenticated observation continuity was invalidated by a long observation gap.")
        )

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.observeCurrentConnection(for: token)
        }
    }

    @Test("exact maximum observation gap is still admitted")
    func exactGapBoundaryIsAccepted() async throws {
        let clock = ContinuityTestClock(100)
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

    @Test("liveness poll after long gap also retires callback authority")
    func livenessAfterGapFailsClosed() async throws {
        let clock = ContinuityTestClock(10)
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

    @Test("accepted canonical prefix becomes immutable after seal")
    func acceptedSealRejectsLateCallbacks() async throws {
        let clock = ContinuityTestClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)

        var next = 3_000 + TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds
        let target = 2_000 + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds
        while next < target {
            clock.advance(to: next)
            try await ledger.observeCurrentConnection(for: token)
            next += TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds
        }
        clock.advance(to: target)
        try await ledger.observeCurrentConnection(for: token)
        try await ledger.sealAcceptedObservation(for: token)
        let sealed = await ledger.currentPreflightSnapshot()

        clock.advance(to: target + 1)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == sealed)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: sealed) == .readyForStationaryMapping)
    }

    @Test("no-application deadline is terminal without claiming disconnect")
    func noApplicationDeadlineRetiresToken() async throws {
        let clock = ContinuityTestClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 60_000_002_000)
        try await ledger.markApplicationObservationTimedOut(for: token)

        let failed = await ledger.currentPreflightSnapshot()
        #expect(
            failed.authenticationState
                == .failed(reason: "Authenticated session produced no application update before the observation deadline.")
        )
        #expect(failed.authenticationMethod == .smartLifeAppSDK)
        #expect(failed.authenticatedAtUptimeNanoseconds == 2_000)
        #expect(failed.applicationPayloadCount == 0)

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
    }
}

private final class ContinuityTestClock: @unchecked Sendable {
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

import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated continuity fence")
struct TuyaAuthenticatedReadOnlySessionContinuityFenceTests {
    @Test("queued application callback cannot erase a suspension gap")
    func queuedApplicationUpdateFailsBeforeAdvancingChronology() async throws {
        let clock = ContinuityFenceClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 150)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 200)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 300)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        clock.advance(to: 400)
        try await ledger.observeCurrentConnection(for: token)
        let lastWitnessed = await ledger.currentPreflightSnapshot()

        clock.advance(to: 400 + TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds + 1)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }

        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Authenticated observation continuity was interrupted."))
        #expect(failed.authenticationMethod == lastWitnessed.authenticationMethod)
        #expect(failed.authenticatedAtUptimeNanoseconds == lastWitnessed.authenticatedAtUptimeNanoseconds)
        #expect(failed.applicationPayloadCount == lastWitnessed.applicationPayloadCount)
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == lastWitnessed.latestApplicationPayloadUptimeNanoseconds)
        #expect(failed.latestObservedUptimeNanoseconds == lastWitnessed.latestObservedUptimeNanoseconds)

        clock.advance(to: 6_000_000_000)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.observeCurrentConnection(for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == failed)
    }

    @Test("direct watchdog invalidation freezes last witnessed liveness")
    func directInvalidationDoesNotManufactureObservationTime() async throws {
        let clock = ContinuityFenceClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 150)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 200)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 300)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        clock.advance(to: 400)
        try await ledger.observeCurrentConnection(for: token)
        let lastWitnessed = await ledger.currentPreflightSnapshot()

        clock.advance(to: 6_000_000_400)
        try await ledger.markObservationContinuityInvalidated(for: token)

        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Authenticated observation continuity was interrupted."))
        #expect(failed.authenticationMethod == lastWitnessed.authenticationMethod)
        #expect(failed.authenticatedAtUptimeNanoseconds == lastWitnessed.authenticatedAtUptimeNanoseconds)
        #expect(failed.applicationPayloadCount == lastWitnessed.applicationPayloadCount)
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == lastWitnessed.latestApplicationPayloadUptimeNanoseconds)
        #expect(failed.latestObservedUptimeNanoseconds == lastWitnessed.latestObservedUptimeNanoseconds)
        #expect(failed.latestObservedUptimeNanoseconds == 400)
    }

    @Test("stale ready prefix cannot be sealed after an unobserved gap")
    func sealRechecksContinuityWithoutMintingLiveness() async throws {
        let clock = ContinuityFenceClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        let readyTime = 2_000 + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds
        clock.advance(to: readyTime)
        try await ledger.observeCurrentConnection(for: token)
        let ready = await ledger.currentPreflightSnapshot()
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: ready) == .readyForStationaryMapping)

        clock.advance(to: readyTime + TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds + 1)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated) {
            try await ledger.sealAcceptedObservation(for: token)
        }

        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Authenticated observation continuity was interrupted."))
        #expect(failed.latestObservedUptimeNanoseconds == ready.latestObservedUptimeNanoseconds)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: failed) == .blocked(reason: "Authenticated observation continuity was interrupted."))
    }
}

private final class ContinuityFenceClock: @unchecked Sendable {
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

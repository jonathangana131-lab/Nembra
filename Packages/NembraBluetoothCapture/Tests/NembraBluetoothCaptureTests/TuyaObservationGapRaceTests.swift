import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya observation gap races")
struct TuyaObservationGapRaceTests {
    @Test("queued application update cannot heal a long observation gap")
    func queuedApplicationUpdateCannotHealGap() async throws {
        let clock = GapRaceClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        let before = await ledger.currentPreflightSnapshot()

        clock.advance(by: TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds + 1)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }

        let terminal = await ledger.currentPreflightSnapshot()
        #expect(terminal.authenticationState == .failed(reason: "Authenticated observation continuity was invalidated by a long observation gap."))
        #expect(terminal.authenticationMethod == .smartLifeAppSDK)
        #expect(terminal.authenticatedAtUptimeNanoseconds == before.authenticatedAtUptimeNanoseconds)
        #expect(terminal.applicationPayloadCount == 0)
        #expect(terminal.latestApplicationPayloadUptimeNanoseconds == nil)
        #expect(terminal.latestObservedUptimeNanoseconds == before.latestObservedUptimeNanoseconds)

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
    }

    @Test("queued liveness callback cannot heal a long observation gap")
    func queuedLivenessCannotHealGap() async throws {
        let clock = GapRaceClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 200)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 300)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        let before = await ledger.currentPreflightSnapshot()

        clock.advance(by: TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds + 1)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated) {
            try await ledger.observeCurrentConnection(for: token)
        }

        let terminal = await ledger.currentPreflightSnapshot()
        #expect(terminal.latestObservedUptimeNanoseconds == before.latestObservedUptimeNanoseconds)
        #expect(terminal.authenticationState == .failed(reason: "Authenticated observation continuity was invalidated by a long observation gap."))
    }

    @Test("exact continuity boundary remains admissible")
    func exactGapBoundaryIsAdmissible() async throws {
        let clock = GapRaceClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 200)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 300)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(by: TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds)
        try await ledger.observeCurrentConnection(for: token)

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.authenticationState == .authenticated)
        #expect(snapshot.latestObservedUptimeNanoseconds == 300 + TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds)
    }

    @Test("ready prefix cannot be sealed after an unobserved long pause")
    func readyPrefixCannotSealAcrossGap() async throws {
        let clock = GapRaceClock(0)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 100)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 200)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 300)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)

        for step in 1...9 {
            clock.advance(to: 200 + UInt64(step) * TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds)
            try await ledger.observeCurrentConnection(for: token)
        }

        let ready = await ledger.currentPreflightSnapshot()
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: ready) == .readyForStationaryMapping)
        let lastWitnessed = ready.latestObservedUptimeNanoseconds

        clock.advance(by: TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds + 1)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated) {
            try await ledger.sealAcceptedObservation(for: token)
        }

        let terminal = await ledger.currentPreflightSnapshot()
        #expect(terminal.authenticationState == .failed(reason: "Authenticated observation continuity was invalidated by a long observation gap."))
        #expect(terminal.latestObservedUptimeNanoseconds == lastWitnessed)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: terminal) == .blocked(reason: "Authenticated observation continuity was invalidated by a long observation gap."))
    }
}

private final class GapRaceClock: @unchecked Sendable {
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

    func advance(by delta: UInt64) {
        lock.lock()
        value += delta
        lock.unlock()
    }
}

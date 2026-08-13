import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated read-only horizon boundary red team")
struct TuyaAuthenticatedReadOnlyHorizonBoundaryRedTeamTests {
    @Test("late second application callback cannot rescue an incomplete generation at the deadline")
    func lateSecondPayloadCannotRescueGeneration() async throws {
        let clock = HorizonBoundaryClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)

        let horizon = 2_000 + TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds
        try await advanceBoundaryLiveness(
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
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) != .readyForStationaryMapping)
    }

    @Test("device-sharing provenance cannot remain authenticated beyond the incomplete horizon")
    func deviceSharingGenerationRetiresAtHorizon() async throws {
        let clock = HorizonBoundaryClock(10_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 10_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 11_000)
        try await ledger.markAuthenticated(for: token, method: .documentedDeviceSharing)
        clock.advance(to: 12_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)

        let horizon = 11_000 + TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds
        try await advanceBoundaryLiveness(
            clock: clock,
            ledger: ledger,
            token: token,
            from: 12_000,
            untilBefore: horizon
        )

        clock.advance(to: horizon)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached) {
            try await ledger.observeCurrentConnection(for: token)
        }

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot)
                == .blocked(reason: "Tuya Device Sharing proves account/device authority, not authentication of the current BLE connection generation.")
        )
    }
}

private func advanceBoundaryLiveness(
    clock: HorizonBoundaryClock,
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

private final class HorizonBoundaryClock: @unchecked Sendable {
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

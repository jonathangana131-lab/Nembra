import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated incomplete observation horizon")
struct TuyaAuthenticatedIncompleteObservationHorizonTests {
    @Test("bootstrap-only generation retires at package-owned 60 second horizon")
    func bootstrapOnlyGenerationRetires() async throws {
        let clock = HorizonClock(1_000_000_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.set(1_100_000_000)
        try await ledger.markAuthenticationStarted(for: token)
        let authenticatedAt: UInt64 = 1_200_000_000
        clock.set(authenticatedAt)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.set(authenticatedAt + 1_000_000_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)

        try await pollContinuously(
            clock: clock,
            ledger: ledger,
            token: token,
            authenticatedAt: authenticatedAt,
            throughOffset: 56_000_000_000
        )
        clock.set(authenticatedAt + TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached) {
            try await ledger.observeCurrentConnection(for: token)
        }
        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 1)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == authenticatedAt + 1_000_000_000)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) != .readyForStationaryMapping)
    }

    @Test("deadline-crossing second callback is rejected before evidence mutation")
    func deadlineCrossingPayloadCannotManufactureReadiness() async throws {
        let clock = HorizonClock(2_000_000_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.set(2_100_000_000)
        try await ledger.markAuthenticationStarted(for: token)
        let authenticatedAt: UInt64 = 2_200_000_000
        clock.set(authenticatedAt)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.set(authenticatedAt + 1_000_000_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        try await pollContinuously(
            clock: clock,
            ledger: ledger,
            token: token,
            authenticatedAt: authenticatedAt,
            throughOffset: 56_000_000_000
        )

        let before = await ledger.currentPreflightSnapshot()
        clock.set(authenticatedAt + TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        let after = await ledger.currentPreflightSnapshot()
        #expect(after.applicationPayloadCount == before.applicationPayloadCount)
        #expect(after.latestApplicationPayloadUptimeNanoseconds == before.latestApplicationPayloadUptimeNanoseconds)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: after) != .readyForStationaryMapping)
    }

    @Test("canonically ready generation survives incomplete horizon")
    func readyGenerationSurvivesHorizon() async throws {
        let clock = HorizonClock(3_000_000_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.set(3_100_000_000)
        try await ledger.markAuthenticationStarted(for: token)
        let authenticatedAt: UInt64 = 3_200_000_000
        clock.set(authenticatedAt)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.set(authenticatedAt + 1_000_000_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        try await pollContinuously(
            clock: clock,
            ledger: ledger,
            token: token,
            authenticatedAt: authenticatedAt,
            throughOffset: 26_000_000_000
        )
        clock.set(authenticatedAt + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds + 1)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        try await pollContinuously(
            clock: clock,
            ledger: ledger,
            token: token,
            authenticatedAt: authenticatedAt,
            fromOffset: 35_000_000_000,
            throughOffset: 60_000_000_000
        )
        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 2)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .readyForStationaryMapping)
    }

    private func pollContinuously(
        clock: HorizonClock,
        ledger: TuyaAuthenticatedReadOnlySessionLedger,
        token: TuyaReadOnlyConnectionToken,
        authenticatedAt: UInt64,
        fromOffset: UInt64 = 6_000_000_000,
        throughOffset: UInt64
    ) async throws {
        var offset = fromOffset
        while offset <= throughOffset {
            clock.set(authenticatedAt + offset)
            try await ledger.observeCurrentConnection(for: token)
            offset += 5_000_000_000
        }
    }
}

private final class HorizonClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    init(_ value: UInt64) {
        self.value = value
    }

    func set(_ value: UInt64) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func now() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

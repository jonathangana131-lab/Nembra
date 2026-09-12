import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated legacy observation horizon")
struct TuyaAuthenticatedIncompleteObservationHorizonTests {
    @Test("SDK-silent authenticated generation stays alive beyond legacy 60 second horizon")
    func sdkSilentGenerationStaysAlive() async throws {
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
            throughOffset: 66_000_000_000
        )

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.authenticationState == .authenticated)
        #expect(snapshot.authenticationMethod == .smartLifeAppSDK)
        #expect(snapshot.applicationPayloadCount == 1)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == authenticatedAt + 1_000_000_000)
        #expect(TuyaAuthenticatedReadOnlyPreflight.shouldRetireIncompleteObservation(snapshot) == false)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) != .readyForStationaryMapping)
    }

    @Test("late SDK callback does not retire a healthy authenticated generation")
    func lateSDKCallbackDoesNotRetireGeneration() async throws {
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
            throughOffset: 61_000_000_000
        )
        clock.set(authenticatedAt + 62_000_000_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.authenticationState == .authenticated)
        #expect(snapshot.applicationPayloadCount == 2)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == authenticatedAt + 62_000_000_000)
        #expect(TuyaAuthenticatedReadOnlyPreflight.shouldRetireIncompleteObservation(snapshot) == false)
    }

    @Test("actual continuity loss remains terminal after legacy horizon retirement is disabled")
    func continuityLossRemainsTerminal() async throws {
        let clock = HorizonClock(3_000_000_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.set(3_100_000_000)
        try await ledger.markAuthenticationStarted(for: token)
        let authenticatedAt: UInt64 = 3_200_000_000
        clock.set(authenticatedAt)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        clock.set(authenticatedAt + TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds + 1)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated) {
            try await ledger.observeCurrentConnection(for: token)
        }
        let snapshot = await ledger.currentPreflightSnapshot()
        if case .failed = snapshot.authenticationState {
            // Expected: only real continuity/lifecycle/source failures remain terminal here.
        } else {
            Issue.record("Observation continuity loss must still fail the authenticated generation.")
        }
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

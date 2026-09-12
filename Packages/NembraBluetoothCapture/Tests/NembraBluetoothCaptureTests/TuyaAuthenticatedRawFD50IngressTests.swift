import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated raw FD50 ingress")
struct TuyaAuthenticatedRawFD50IngressTests {
    private func authenticatedLedger(
        clock: RawIngressTestUptimeClock
    ) async throws -> (TuyaAuthenticatedReadOnlySessionLedger, TuyaReadOnlyConnectionToken) {
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        return (ledger, token)
    }

    @Test("ingress mints generation characteristic and receipt chronology instead of accepting caller provenance")
    func mintsPackageOwnedProvenance() async throws {
        let clock = RawIngressTestUptimeClock(1_000)
        let (ledger, token) = try await authenticatedLedger(clock: clock)
        let ingress = TuyaAuthenticatedRawFD50Ingress(
            snapshotProvider: { await ledger.currentPreflightSnapshot() },
            uptimeProvider: clock.now
        )
        let bytes = Data([0x01, 0x02, 0xFD, 0x50])

        clock.advance(to: 3_000)
        let verdict = await ingress.recordDocumentedSameSessionNotify(
            payload: bytes,
            connectionToken: token
        )
        let observations = await ingress.observations(for: token)

        #expect(verdict == .retained)
        #expect(observations.count == 1)
        #expect(observations.first?.connectionGeneration == token.diagnosticGeneration)
        #expect(observations.first?.characteristicUUID == TuyaAuthenticatedRawFD50Acceptance.deviceToAppNotifyCharacteristicUUID)
        #expect(observations.first?.observedAtUptimeNanoseconds == 3_000)
        #expect(observations.first?.payload == bytes)
    }

    @Test("stale generation cannot relabel bytes as current authenticated raw custody")
    func staleGenerationIsBlocked() async throws {
        let clock = RawIngressTestUptimeClock(1_000)
        let (ledger, firstToken) = try await authenticatedLedger(clock: clock)
        let ingress = TuyaAuthenticatedRawFD50Ingress(
            snapshotProvider: { await ledger.currentPreflightSnapshot() },
            uptimeProvider: clock.now
        )

        clock.advance(to: 4_000)
        _ = try await ledger.beginConnection()
        clock.advance(to: 5_000)

        let verdict = await ingress.recordDocumentedSameSessionNotify(
            payload: Data([0xAA]),
            connectionToken: firstToken
        )
        let observations = await ingress.observations(for: firstToken)

        #expect(verdict == .blockedInactiveGeneration)
        #expect(observations.isEmpty)
    }

    @Test("empty callback and callback at authentication boundary are not retained")
    func emptyAndBoundaryCallbacksAreBlocked() async throws {
        let clock = RawIngressTestUptimeClock(1_000)
        let (ledger, token) = try await authenticatedLedger(clock: clock)
        let ingress = TuyaAuthenticatedRawFD50Ingress(
            snapshotProvider: { await ledger.currentPreflightSnapshot() },
            uptimeProvider: clock.now
        )

        let emptyVerdict = await ingress.recordDocumentedSameSessionNotify(
            payload: Data(),
            connectionToken: token
        )
        let boundaryVerdict = await ingress.recordDocumentedSameSessionNotify(
            payload: Data([0xAA]),
            connectionToken: token
        )
        let observations = await ingress.observations(for: token)

        #expect(emptyVerdict == .blockedEmptyPayload)
        #expect(boundaryVerdict == .blockedBeforeAuthenticationBoundary)
        #expect(observations.isEmpty)
    }

    @Test("retirement clears only the exact generation's retained bytes")
    func retirementClearsExactGeneration() async throws {
        let clock = RawIngressTestUptimeClock(1_000)
        let (ledger, token) = try await authenticatedLedger(clock: clock)
        let ingress = TuyaAuthenticatedRawFD50Ingress(
            snapshotProvider: { await ledger.currentPreflightSnapshot() },
            uptimeProvider: clock.now
        )

        clock.advance(to: 3_000)
        let verdict = await ingress.recordDocumentedSameSessionNotify(
            payload: Data([0x10, 0x20]),
            connectionToken: token
        )
        let retainedBeforeRetirement = await ingress.observations(for: token)

        #expect(verdict == .retained)
        #expect(retainedBeforeRetirement.count == 1)

        await ingress.retire(connectionToken: token)
        let retainedAfterRetirement = await ingress.observations(for: token)
        #expect(retainedAfterRetirement.isEmpty)
    }
}

private final class RawIngressTestUptimeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    init(_ initialValue: UInt64) {
        value = initialValue
    }

    var now: @Sendable () -> UInt64 {
        { [weak self] in
            guard let self else { return 0 }
            return self.lock.withLock { self.value }
        }
    }

    func advance(to newValue: UInt64) {
        lock.withLock { value = newValue }
    }
}

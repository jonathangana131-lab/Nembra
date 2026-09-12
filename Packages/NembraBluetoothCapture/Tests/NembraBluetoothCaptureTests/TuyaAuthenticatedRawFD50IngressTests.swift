import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated raw FD50 ingress")
struct TuyaAuthenticatedRawFD50IngressTests {
    private func authenticatedLedger(
        clock: TestUptimeClock
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
        let clock = TestUptimeClock(1_000)
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
        let clock = TestUptimeClock(1_000)
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

        #expect(verdict == .blockedInactiveGeneration)
        #expect(await ingress.observations(for: firstToken).isEmpty)
    }

    @Test("empty callback and callback at authentication boundary are not retained")
    func emptyAndBoundaryCallbacksAreBlocked() async throws {
        let clock = TestUptimeClock(1_000)
        let (ledger, token) = try await authenticatedLedger(clock: clock)
        let ingress = TuyaAuthenticatedRawFD50Ingress(
            snapshotProvider: { await ledger.currentPreflightSnapshot() },
            uptimeProvider: clock.now
        )

        #expect(
            await ingress.recordDocumentedSameSessionNotify(
                payload: Data(),
                connectionToken: token
            ) == .blockedEmptyPayload
        )
        #expect(
            await ingress.recordDocumentedSameSessionNotify(
                payload: Data([0xAA]),
                connectionToken: token
            ) == .blockedBeforeAuthenticationBoundary
        )
        #expect(await ingress.observations(for: token).isEmpty)
    }

    @Test("retirement clears only the exact generation's retained bytes")
    func retirementClearsExactGeneration() async throws {
        let clock = TestUptimeClock(1_000)
        let (ledger, token) = try await authenticatedLedger(clock: clock)
        let ingress = TuyaAuthenticatedRawFD50Ingress(
            snapshotProvider: { await ledger.currentPreflightSnapshot() },
            uptimeProvider: clock.now
        )

        clock.advance(to: 3_000)
        #expect(
            await ingress.recordDocumentedSameSessionNotify(
                payload: Data([0x10, 0x20]),
                connectionToken: token
            ) == .retained
        )
        #expect(await ingress.observations(for: token).count == 1)

        await ingress.retire(connectionToken: token)
        #expect(await ingress.observations(for: token).isEmpty)
    }
}

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

    private func snapshotEvidence(
        ledger: TuyaAuthenticatedReadOnlySessionLedger,
        token: TuyaReadOnlyConnectionToken
    ) async -> TuyaAuthenticatedRawFD50Ingress.SnapshotEvidence {
        TuyaAuthenticatedRawFD50Ingress.SnapshotEvidence(
            snapshot: await ledger.currentPreflightSnapshot(),
            connectionToken: token
        )
    }

    @Test("ingress mints generation characteristic and receipt chronology instead of accepting caller provenance")
    func mintsPackageOwnedProvenance() async throws {
        let clock = RawIngressTestUptimeClock(1_000)
        let (ledger, token) = try await authenticatedLedger(clock: clock)
        let ingress = TuyaAuthenticatedRawFD50Ingress(
            authenticatedConnectionToken: token,
            snapshotProvider: { await snapshotEvidence(ledger: ledger, token: token) },
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

    @Test("equal or backwards receipt timestamps cannot enter raw physical custody")
    func nonMonotonicReceiptsAreBlockedAtIngress() async throws {
        let clock = RawIngressTestUptimeClock(1_000)
        let (ledger, token) = try await authenticatedLedger(clock: clock)
        let ingress = TuyaAuthenticatedRawFD50Ingress(
            authenticatedConnectionToken: token,
            snapshotProvider: { await snapshotEvidence(ledger: ledger, token: token) },
            uptimeProvider: clock.now
        )

        clock.advance(to: 3_000)
        let firstVerdict = await ingress.recordDocumentedSameSessionNotify(
            payload: Data([0x01]),
            connectionToken: token
        )
        let equalVerdict = await ingress.recordDocumentedSameSessionNotify(
            payload: Data([0x02]),
            connectionToken: token
        )
        clock.advance(to: 2_500)
        let backwardsVerdict = await ingress.recordDocumentedSameSessionNotify(
            payload: Data([0x03]),
            connectionToken: token
        )
        clock.advance(to: 3_001)
        let laterVerdict = await ingress.recordDocumentedSameSessionNotify(
            payload: Data([0x04]),
            connectionToken: token
        )
        let observations = await ingress.observations(for: token)

        #expect(firstVerdict == .retained)
        #expect(equalVerdict == .blockedNonMonotonicReceipt)
        #expect(backwardsVerdict == .blockedNonMonotonicReceipt)
        #expect(laterVerdict == .retained)
        #expect(observations.map(\.observedAtUptimeNanoseconds) == [3_000, 3_001])
        #expect(observations.map(\.payload) == [Data([0x01]), Data([0x04])])
    }

    @Test("stale generation cannot relabel bytes as current authenticated raw custody")
    func staleGenerationIsBlocked() async throws {
        let clock = RawIngressTestUptimeClock(1_000)
        let (ledger, firstToken) = try await authenticatedLedger(clock: clock)
        let ingress = TuyaAuthenticatedRawFD50Ingress(
            authenticatedConnectionToken: firstToken,
            snapshotProvider: { await snapshotEvidence(ledger: ledger, token: firstToken) },
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

    @Test("same generation from another ledger cannot impersonate authenticated raw callback custody")
    func foreignLedgerTokenWithSameGenerationIsBlocked() async throws {
        let primaryClock = RawIngressTestUptimeClock(1_000)
        let (primaryLedger, primaryToken) = try await authenticatedLedger(clock: primaryClock)
        let ingress = TuyaAuthenticatedRawFD50Ingress(
            authenticatedConnectionToken: primaryToken,
            snapshotProvider: { await snapshotEvidence(ledger: primaryLedger, token: primaryToken) },
            uptimeProvider: primaryClock.now
        )

        let foreignClock = RawIngressTestUptimeClock(1_000)
        let (_, foreignToken) = try await authenticatedLedger(clock: foreignClock)
        #expect(foreignToken.diagnosticGeneration == primaryToken.diagnosticGeneration)
        #expect(foreignToken != primaryToken)

        primaryClock.advance(to: 3_000)
        let verdict = await ingress.recordDocumentedSameSessionNotify(
            payload: Data([0xFD, 0x50]),
            connectionToken: foreignToken
        )
        let foreignObservations = await ingress.observations(for: foreignToken)
        let primaryObservations = await ingress.observations(for: primaryToken)

        #expect(verdict == .blockedForeignConnectionToken)
        #expect(foreignObservations.isEmpty)
        #expect(primaryObservations.isEmpty)
    }

    @Test("same numeric generation from another ledger cannot authorize the bound raw ingress snapshot")
    func foreignLedgerSnapshotWithSameGenerationIsBlocked() async throws {
        let primaryClock = RawIngressTestUptimeClock(1_000)
        let (_, primaryToken) = try await authenticatedLedger(clock: primaryClock)

        let foreignClock = RawIngressTestUptimeClock(1_000)
        let (foreignLedger, foreignToken) = try await authenticatedLedger(clock: foreignClock)
        #expect(foreignToken.diagnosticGeneration == primaryToken.diagnosticGeneration)
        #expect(foreignToken != primaryToken)

        let ingress = TuyaAuthenticatedRawFD50Ingress(
            authenticatedConnectionToken: primaryToken,
            snapshotProvider: { await snapshotEvidence(ledger: foreignLedger, token: foreignToken) },
            uptimeProvider: primaryClock.now
        )

        primaryClock.advance(to: 3_000)
        let verdict = await ingress.recordDocumentedSameSessionNotify(
            payload: Data([0xFD, 0x50]),
            connectionToken: primaryToken
        )
        let observations = await ingress.observations(for: primaryToken)

        #expect(verdict == .blockedForeignSnapshotAuthority)
        #expect(observations.isEmpty)
    }

    @Test("empty callback and callback at authentication boundary are not retained")
    func emptyAndBoundaryCallbacksAreBlocked() async throws {
        let clock = RawIngressTestUptimeClock(1_000)
        let (ledger, token) = try await authenticatedLedger(clock: clock)
        let ingress = TuyaAuthenticatedRawFD50Ingress(
            authenticatedConnectionToken: token,
            snapshotProvider: { await snapshotEvidence(ledger: ledger, token: token) },
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

    @Test("invalid authenticated chronology is rejected before raw bytes enter custody")
    func invalidAuthenticatedChronologyIsBlockedAtIngress() async throws {
        let clock = RawIngressTestUptimeClock(1_000)
        let (_, token) = try await authenticatedLedger(clock: clock)
        let invalidSnapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: nil,
            authenticatedAtUptimeNanoseconds: 2_000,
            latestObservedUptimeNanoseconds: 2_500,
            applicationPayloadCount: 0,
            connectionGeneration: token.diagnosticGeneration,
            hasActiveCallbackAuthority: true
        )
        let ingress = TuyaAuthenticatedRawFD50Ingress(
            authenticatedConnectionToken: token,
            snapshotProvider: {
                TuyaAuthenticatedRawFD50Ingress.SnapshotEvidence(
                    snapshot: invalidSnapshot,
                    connectionToken: token
                )
            },
            uptimeProvider: clock.now
        )

        clock.advance(to: 3_000)
        let verdict = await ingress.recordDocumentedSameSessionNotify(
            payload: Data([0xFD, 0x50]),
            connectionToken: token
        )
        let observations = await ingress.observations(for: token)

        #expect(verdict == .blockedInvalidAuthenticatedChronology)
        #expect(observations.isEmpty)
    }

    @Test("retirement clears only the exact authenticated token's retained bytes")
    func retirementClearsExactToken() async throws {
        let clock = RawIngressTestUptimeClock(1_000)
        let (ledger, token) = try await authenticatedLedger(clock: clock)
        let ingress = TuyaAuthenticatedRawFD50Ingress(
            authenticatedConnectionToken: token,
            snapshotProvider: { await snapshotEvidence(ledger: ledger, token: token) },
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

        let foreignClock = RawIngressTestUptimeClock(1_000)
        let (_, foreignToken) = try await authenticatedLedger(clock: foreignClock)
        await ingress.retire(connectionToken: foreignToken)
        let retainedAfterForeignRetirement = await ingress.observations(for: token)
        #expect(retainedAfterForeignRetirement.count == 1)

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

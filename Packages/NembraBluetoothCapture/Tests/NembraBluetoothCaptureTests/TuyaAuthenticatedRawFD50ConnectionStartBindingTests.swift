import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated raw FD50 connection-start binding")
struct TuyaAuthenticatedRawFD50ConnectionStartBindingTests {
    @Test("connection start mutation between admission and custody cannot retain raw bytes")
    func connectionStartMutationIsBlockedBeforeCustody() async throws {
        let clock = ConnectionStartBindingClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        let admitted = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 1_000,
            authenticatedAtUptimeNanoseconds: 2_000,
            latestObservedUptimeNanoseconds: 2_500,
            applicationPayloadCount: 0,
            connectionGeneration: token.diagnosticGeneration,
            hasActiveCallbackAuthority: true
        )
        let mutated = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 1_100,
            authenticatedAtUptimeNanoseconds: 2_000,
            latestObservedUptimeNanoseconds: 2_500,
            applicationPayloadCount: 0,
            connectionGeneration: token.diagnosticGeneration,
            hasActiveCallbackAuthority: true
        )
        let evidence = ConnectionStartBindingEvidenceSequence([
            .init(snapshot: admitted, connectionToken: token),
            .init(snapshot: mutated, connectionToken: token),
            .init(snapshot: mutated, connectionToken: token)
        ])
        let ingress = TuyaAuthenticatedRawFD50Ingress(
            authenticatedConnectionToken: token,
            snapshotProvider: { await evidence.next() },
            uptimeProvider: clock.now
        )

        clock.advance(to: 3_000)
        let verdict = await ingress.recordDocumentedSameSessionNotify(
            payload: Data([0xFD, 0x50, 0x01]),
            connectionToken: token
        )
        let observations = await ingress.observations(for: token)

        #expect(verdict == .blockedAuthorityChangedDuringReceipt)
        #expect(observations.isEmpty)
    }
}

private actor ConnectionStartBindingEvidenceSequence {
    private let evidence: [TuyaAuthenticatedRawFD50Ingress.SnapshotEvidence]
    private var index = 0

    init(_ evidence: [TuyaAuthenticatedRawFD50Ingress.SnapshotEvidence]) {
        precondition(!evidence.isEmpty)
        self.evidence = evidence
    }

    func next() -> TuyaAuthenticatedRawFD50Ingress.SnapshotEvidence {
        let current = evidence[index]
        if index < evidence.count - 1 {
            index += 1
        }
        return current
    }
}

private final class ConnectionStartBindingClock: @unchecked Sendable {
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

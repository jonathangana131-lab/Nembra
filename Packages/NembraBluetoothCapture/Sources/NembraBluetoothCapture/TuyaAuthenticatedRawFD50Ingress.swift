import Foundation

/// Package-owned ingress for a future *documented* same-session FD50 characteristic callback.
///
/// Callers do not supply a generation number, characteristic UUID, or receipt timestamp. Those
/// provenance fields are derived here from the exact authenticated connection token and a package
/// monotonic clock. This prevents an app/UI integration from accidentally manufacturing physical
/// custody by copying metadata from a previous capture.
///
/// This type performs no BLE writes, DP queries, reset/remove/unbind operations, or payload parsing.
/// It is intentionally internal until a documented Tuya-owned raw characteristic callback exists.
actor TuyaAuthenticatedRawFD50Ingress {
    /// Couples a preflight snapshot to the exact opaque token whose ledger produced it. Keeping
    /// these values in one provider result prevents a second authenticated ledger with the same
    /// numeric generation from accidentally authorizing this ingress's bytes.
    struct SnapshotEvidence: Sendable {
        let snapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot
        let connectionToken: TuyaReadOnlyConnectionToken?

        init(
            snapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot,
            connectionToken: TuyaReadOnlyConnectionToken?
        ) {
            self.snapshot = snapshot
            self.connectionToken = connectionToken
        }
    }

    typealias SnapshotProvider = @Sendable () async -> SnapshotEvidence
    typealias UptimeProvider = @Sendable () -> UInt64

    enum RecordVerdict: Equatable, Sendable {
        case retained
        case blockedEmptyPayload
        case blockedForeignConnectionToken
        case blockedForeignSnapshotAuthority
        case blockedInactiveGeneration
        case blockedUnauthenticatedGeneration
        case blockedWrongAuthenticationMethod
        case blockedInvalidAuthenticatedChronology
        case blockedBeforeAuthenticationBoundary
        case blockedNonMonotonicReceipt
    }

    /// Exact opaque token this ingress was bound to when the authenticated same-session callback
    /// path was installed. Token equality includes the package-private ledger identity as well as
    /// the generation, so another ledger's generation `1` cannot impersonate this session.
    private let authenticatedConnectionToken: TuyaReadOnlyConnectionToken
    private let snapshotProvider: SnapshotProvider
    private let uptimeProvider: UptimeProvider
    private var retained: [TuyaAuthenticatedRawFD50Acceptance.Observation] = []

    init(
        authenticatedConnectionToken: TuyaReadOnlyConnectionToken,
        snapshotProvider: @escaping SnapshotProvider,
        uptimeProvider: @escaping UptimeProvider = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.authenticatedConnectionToken = authenticatedConnectionToken
        self.snapshotProvider = snapshotProvider
        self.uptimeProvider = uptimeProvider
    }

    /// Retains bytes delivered by the documented same-session device→app notify callback.
    ///
    /// The fixed FD50 notify UUID, exact token generation, and callback receipt time are minted at
    /// this boundary rather than accepted as caller input. The callback must also present the exact
    /// opaque token this ingress was bound to; matching generation numbers from another ledger are
    /// insufficient physical custody. The snapshot provider must independently return that same
    /// opaque token with its snapshot, so a cross-ledger snapshot cannot authorize this ingress.
    func recordDocumentedSameSessionNotify(
        payload: Data,
        connectionToken: TuyaReadOnlyConnectionToken
    ) async -> RecordVerdict {
        guard !payload.isEmpty else { return .blockedEmptyPayload }
        guard connectionToken == authenticatedConnectionToken else {
            return .blockedForeignConnectionToken
        }

        let snapshotEvidence = await snapshotProvider()
        guard snapshotEvidence.connectionToken == authenticatedConnectionToken else {
            return .blockedForeignSnapshotAuthority
        }
        let snapshot = snapshotEvidence.snapshot
        guard snapshot.hasActiveCallbackAuthority,
              snapshot.connectionGeneration == authenticatedConnectionToken.diagnosticGeneration else {
            return .blockedInactiveGeneration
        }
        guard snapshot.authenticationState == .authenticated else {
            return .blockedUnauthenticatedGeneration
        }
        guard snapshot.authenticationMethod == .smartLifeAppSDK else {
            return .blockedWrongAuthenticationMethod
        }
        guard let connectionStarted = snapshot.connectionStartedAtUptimeNanoseconds,
              let authenticatedAt = snapshot.authenticatedAtUptimeNanoseconds,
              let latestObserved = snapshot.latestObservedUptimeNanoseconds,
              authenticatedAt >= connectionStarted,
              latestObserved >= authenticatedAt else {
            return .blockedInvalidAuthenticatedChronology
        }

        let observedAt = uptimeProvider()
        guard observedAt > authenticatedAt else {
            return .blockedBeforeAuthenticationBoundary
        }
        if let previousReceipt = retained.last?.observedAtUptimeNanoseconds,
           observedAt <= previousReceipt {
            return .blockedNonMonotonicReceipt
        }

        retained.append(
            TuyaAuthenticatedRawFD50Acceptance.Observation(
                connectionGeneration: authenticatedConnectionToken.diagnosticGeneration,
                characteristicUUID: TuyaAuthenticatedRawFD50Acceptance.deviceToAppNotifyCharacteristicUUID,
                observedAtUptimeNanoseconds: observedAt,
                payload: payload
            )
        )
        return .retained
    }

    /// Returns observations only when queried with this ingress's exact opaque connection token.
    /// A token from another ledger with the same diagnostic generation receives no retained bytes.
    func observations(for connectionToken: TuyaReadOnlyConnectionToken) -> [TuyaAuthenticatedRawFD50Acceptance.Observation] {
        guard connectionToken == authenticatedConnectionToken else { return [] }
        return retained.filter { $0.connectionGeneration == authenticatedConnectionToken.diagnosticGeneration }
    }

    /// Exact-token retirement. This is local evidence hygiene only and never touches scooter state
    /// or asks Tuya to disconnect, reset, remove, or unbind anything.
    func retire(connectionToken: TuyaReadOnlyConnectionToken) {
        guard connectionToken == authenticatedConnectionToken else { return }
        retained.removeAll { $0.connectionGeneration == authenticatedConnectionToken.diagnosticGeneration }
    }
}

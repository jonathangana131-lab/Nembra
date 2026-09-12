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
    typealias SnapshotProvider = @Sendable () async -> TuyaAuthenticatedReadOnlyPreflightSnapshot
    typealias UptimeProvider = @Sendable () -> UInt64

    enum RecordVerdict: Equatable, Sendable {
        case retained
        case blockedEmptyPayload
        case blockedInactiveGeneration
        case blockedUnauthenticatedGeneration
        case blockedWrongAuthenticationMethod
        case blockedBeforeAuthenticationBoundary
    }

    private let snapshotProvider: SnapshotProvider
    private let uptimeProvider: UptimeProvider
    private var retained: [TuyaAuthenticatedRawFD50Acceptance.Observation] = []

    init(
        snapshotProvider: @escaping SnapshotProvider,
        uptimeProvider: @escaping UptimeProvider = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.snapshotProvider = snapshotProvider
        self.uptimeProvider = uptimeProvider
    }

    /// Retains bytes delivered by the documented same-session device→app notify callback.
    ///
    /// The fixed FD50 notify UUID, exact token generation, and callback receipt time are minted at
    /// this boundary rather than accepted as caller input. A stale token therefore cannot be used
    /// to relabel bytes as belonging to the current authenticated generation.
    func recordDocumentedSameSessionNotify(
        payload: Data,
        connectionToken: TuyaReadOnlyConnectionToken
    ) async -> RecordVerdict {
        guard !payload.isEmpty else { return .blockedEmptyPayload }

        let snapshot = await snapshotProvider()
        guard snapshot.hasActiveCallbackAuthority,
              snapshot.connectionGeneration == connectionToken.diagnosticGeneration else {
            return .blockedInactiveGeneration
        }
        guard snapshot.authenticationState == .authenticated else {
            return .blockedUnauthenticatedGeneration
        }
        guard snapshot.authenticationMethod == .smartLifeAppSDK else {
            return .blockedWrongAuthenticationMethod
        }
        guard let authenticatedAt = snapshot.authenticatedAtUptimeNanoseconds else {
            return .blockedUnauthenticatedGeneration
        }

        let observedAt = uptimeProvider()
        guard observedAt > authenticatedAt else {
            return .blockedBeforeAuthenticationBoundary
        }

        retained.append(
            TuyaAuthenticatedRawFD50Acceptance.Observation(
                connectionGeneration: connectionToken.diagnosticGeneration,
                characteristicUUID: TuyaAuthenticatedRawFD50Acceptance.deviceToAppNotifyCharacteristicUUID,
                observedAtUptimeNanoseconds: observedAt,
                payload: payload
            )
        )
        return .retained
    }

    /// Returns only observations belonging to this exact connection token. The physical acceptance
    /// evaluator still independently validates the current authenticated snapshot and chronology.
    func observations(for connectionToken: TuyaReadOnlyConnectionToken) -> [TuyaAuthenticatedRawFD50Acceptance.Observation] {
        retained.filter { $0.connectionGeneration == connectionToken.diagnosticGeneration }
    }

    /// Exact-generation retirement. This is local evidence hygiene only and never touches scooter
    /// state or asks Tuya to disconnect, reset, remove, or unbind anything.
    func retire(connectionToken: TuyaReadOnlyConnectionToken) {
        retained.removeAll { $0.connectionGeneration == connectionToken.diagnosticGeneration }
    }
}

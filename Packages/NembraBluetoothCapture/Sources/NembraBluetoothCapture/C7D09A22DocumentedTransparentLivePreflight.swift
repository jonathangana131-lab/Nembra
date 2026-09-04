import Foundation

/// App-facing read-only coordinator for the documented Smart Life transparent receive path.
///
/// This is intentionally the narrow seam the live `ThingSmartBLEManagerDelegate` adapter needs:
/// arm only after the package-owned session has authenticated through the official Smart Life SDK,
/// forward documented device-to-app transparent bytes synchronously, query a non-secret transport
/// milestone, and retire the exact generation on terminal lifecycle.
///
/// The coordinator never publishes DPs, writes transparent data, pairs, resets, removes, or
/// unbinds a device. A satisfied documented-transport milestone is still not raw FD50 GATT
/// characteristic custody and cannot assign scooter semantics.
@MainActor
public final class C7D09A22DocumentedTransparentLivePreflight {
    public typealias SnapshotProvider = C7D09A22DocumentedTransparentDelegateHandoff.PreflightSnapshotProvider
    public typealias RecordObserver = C7D09A22DocumentedTransparentDelegateHandoff.RecordObserver

    /// One coherent diagnostic cut for the live field attempt.
    ///
    /// `milestone` and `artifact` are derived from the same package-owned transparent-receive
    /// snapshot so UI/export code cannot accidentally combine a newer milestone with older bytes
    /// (or vice versa) across actor suspension points. This remains documented SDK transport
    /// evidence only and never upgrades to raw-FD50 characteristic or scooter-semantic authority.
    public struct FieldAttemptEvidence: Equatable, Sendable {
        public let milestone: C7D09A22DocumentedTransparentTransportMilestone.Verdict
        public let artifact: C7D09A22DocumentedTransparentEvidenceArtifact?

        public var satisfiesDocumentedAuthenticatedTransportAcceptance: Bool {
            milestone == .satisfied &&
                (artifact?.payloadCount ?? 0) > 0 &&
                artifact?.hasPayloadStrictlyBeyondHistoricalRejectionHorizon == true
        }

        public var authorizesRawFD50CharacteristicCustody: Bool { false }
        public var authorizesPhysicalFirstAcceptance: Bool { false }
        public var authorizesStationaryMapping: Bool { false }
        public var authorizesTelemetrySemantics: Bool { false }
        public var authorizesControlWrites: Bool { false }
        public var authorizesPairingResetOrUnbind: Bool { false }
    }

    private let handoff: C7D09A22DocumentedTransparentDelegateHandoff
    private var authenticatedSnapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot?
    private var activeGeneration: UInt64?

    public init(
        preflightSnapshotProvider: @escaping SnapshotProvider,
        recordObserver: RecordObserver? = nil
    ) {
        self.handoff = C7D09A22DocumentedTransparentDelegateHandoff(
            preflightSnapshotProvider: preflightSnapshotProvider,
            recordObserver: recordObserver
        )
    }

    /// Arms only the exact already-authenticated package generation and exact Tuya device ID.
    /// Failed arming retires any previous generation and leaves the coordinator fail-closed.
    @discardableResult
    public func arm(
        connectionToken: TuyaReadOnlyConnectionToken,
        expectedDeviceID: String,
        authenticatedPreflightSnapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot
    ) async -> Bool {
        authenticatedSnapshot = nil
        activeGeneration = nil
        let armed = await handoff.begin(
            connectionToken: connectionToken,
            expectedDeviceID: expectedDeviceID,
            authenticatedPreflightSnapshot: authenticatedPreflightSnapshot
        )
        guard armed else { return false }
        self.authenticatedSnapshot = authenticatedPreflightSnapshot
        self.activeGeneration = connectionToken.diagnosticGeneration
        return true
    }

    /// Forward directly from Tuya's documented `bleReceiveTransparentData(_:devId:)` callback.
    /// Generation and exact-device custody are sealed synchronously before any actor hop.
    public func receive(payload: Data, callbackDeviceID: String) {
        handoff.receive(payload: payload, callbackDeviceID: callbackDeviceID)
    }

    /// Objective-C callback shaped ingress for the live Smart Life BLE-manager delegate.
    ///
    /// Tuya delegate values can cross into Swift as optionals depending on SDK annotations. Keep
    /// nil/empty callback handling inside the package-owned read-only boundary so the app adapter
    /// does not invent fallback identities, synthesize bytes, or retry against a later generation.
    /// The underlying handoff still performs exact-device and generation admission synchronously.
    public func receiveDocumentedSmartLifeCallback(payload: Data?, deviceID: String?) {
        guard let payload, !payload.isEmpty,
              let deviceID else {
            return
        }
        let normalizedDeviceID = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDeviceID.isEmpty else { return }
        handoff.receive(payload: payload, callbackDeviceID: normalizedDeviceID)
    }

    /// Returns the current documented authenticated transport milestone only.
    /// This never upgrades the evidence into raw FD50 characteristic or DP semantic authority.
    public func transportMilestone() async -> C7D09A22DocumentedTransparentTransportMilestone.Verdict {
        guard let authenticatedSnapshot else {
            return .blockedUnauthenticated
        }
        return C7D09A22DocumentedTransparentTransportMilestone.verdict(
            authenticatedPreflight: authenticatedSnapshot,
            transparent: await handoff.diagnosticSnapshot()
        )
    }

    /// Returns one coherent package-owned cut of the live field-attempt milestone plus exact bytes.
    ///
    /// Callers should prefer this when rendering/exporting the P0 physical lane because it samples
    /// the transparent ledger only once. A satisfied value means documented authenticated Tuya
    /// transport delivered real bytes beyond the historical rejection horizon; it still does not
    /// claim the underlying FD50 GATT characteristic or any DP meaning.
    public func fieldAttemptEvidence() async -> FieldAttemptEvidence {
        guard let authenticatedSnapshot else {
            return FieldAttemptEvidence(milestone: .blockedUnauthenticated, artifact: nil)
        }
        let transparent = await handoff.diagnosticSnapshot()
        let milestone = C7D09A22DocumentedTransparentTransportMilestone.verdict(
            authenticatedPreflight: authenticatedSnapshot,
            transparent: transparent
        )
        let artifact = transparent.map(C7D09A22DocumentedTransparentEvidenceArtifact.init(snapshot:))
        return FieldAttemptEvidence(milestone: milestone, artifact: artifact)
    }

    /// Non-secret diagnostics for the exact active generation, if any.
    public func diagnosticSnapshot() async -> C7D09A22DocumentedTransparentReceiveIngress.DiagnosticSnapshot? {
        await handoff.diagnosticSnapshot()
    }

    /// Portable exact-byte evidence for the currently armed authenticated generation.
    ///
    /// The artifact is derived only from the package-owned diagnostic snapshot, so the app never
    /// reconstructs callback bytes or chronology from mutable presentation state. It remains
    /// documented Smart Life transport evidence only: the callback does not expose the underlying
    /// GATT service/characteristic tuple required for raw FD50 physical first acceptance.
    public func evidenceArtifact() async -> C7D09A22DocumentedTransparentEvidenceArtifact? {
        guard authenticatedSnapshot != nil,
              let snapshot = await handoff.diagnosticSnapshot() else {
            return nil
        }
        return C7D09A22DocumentedTransparentEvidenceArtifact(snapshot: snapshot)
    }

    /// Retires only when the caller still owns the exact armed package generation.
    ///
    /// This is the preferred live-app terminal path. An asynchronous failure/disconnect callback
    /// from generation N must never be able to retire a subsequently armed generation N+1.
    /// Returns `true` only when this call actually retired the active generation.
    @discardableResult
    public func retire(connectionToken: TuyaReadOnlyConnectionToken) async -> Bool {
        guard activeGeneration == connectionToken.diagnosticGeneration else { return false }
        await handoff.retire()
        authenticatedSnapshot = nil
        activeGeneration = nil
        return true
    }

    /// Unconditional owner teardown for view/process destruction where no newer generation can
    /// exist. Live asynchronous lifecycle callbacks should use `retire(connectionToken:)` instead.
    public func retire() async {
        await handoff.retire()
        authenticatedSnapshot = nil
        activeGeneration = nil
    }

    public var hasActiveAuthenticatedGeneration: Bool {
        authenticatedSnapshot != nil && activeGeneration != nil && handoff.hasActiveGeneration
    }

    public var activeDiagnosticGeneration: UInt64? { activeGeneration }

    // Transport evidence cannot authorize protocol meaning or scooter mutation.
    public var authorizesRawFD50CharacteristicCustody: Bool { false }
    public var authorizesPhysicalFirstAcceptance: Bool { false }
    public var authorizesStationaryMapping: Bool { false }
    public var authorizesTelemetrySemantics: Bool { false }
    public var authorizesControlWrites: Bool { false }
    public var authorizesPairingResetOrUnbind: Bool { false }
}
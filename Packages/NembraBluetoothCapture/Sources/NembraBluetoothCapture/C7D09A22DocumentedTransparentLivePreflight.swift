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

    private let handoff: C7D09A22DocumentedTransparentDelegateHandoff
    private var authenticatedSnapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot?

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
        let armed = await handoff.begin(
            connectionToken: connectionToken,
            expectedDeviceID: expectedDeviceID,
            authenticatedPreflightSnapshot: authenticatedPreflightSnapshot
        )
        guard armed else { return false }
        self.authenticatedSnapshot = authenticatedPreflightSnapshot
        return true
    }

    /// Forward directly from Tuya's documented `bleReceiveTransparentData(_:devId:)` callback.
    /// Generation and exact-device custody are sealed synchronously before any actor hop.
    public func receive(payload: Data, callbackDeviceID: String) {
        handoff.receive(payload: payload, callbackDeviceID: callbackDeviceID)
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

    /// Non-secret diagnostics for the exact active generation, if any.
    public func diagnosticSnapshot() async -> C7D09A22DocumentedTransparentReceiveIngress.DiagnosticSnapshot? {
        await handoff.diagnosticSnapshot()
    }

    /// Terminally retires callback custody before forgetting the authenticated snapshot.
    public func retire() async {
        await handoff.retire()
        authenticatedSnapshot = nil
    }

    public var hasActiveAuthenticatedGeneration: Bool {
        authenticatedSnapshot != nil && handoff.hasActiveGeneration
    }

    // Transport evidence cannot authorize protocol meaning or scooter mutation.
    public var authorizesRawFD50CharacteristicCustody: Bool { false }
    public var authorizesPhysicalFirstAcceptance: Bool { false }
    public var authorizesStationaryMapping: Bool { false }
    public var authorizesTelemetrySemantics: Bool { false }
    public var authorizesControlWrites: Bool { false }
    public var authorizesPairingResetOrUnbind: Bool { false }
}

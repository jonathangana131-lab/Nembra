import Foundation

/// Main-actor lifecycle bridge for Tuya's documented
/// `ThingSmartBLEManagerDelegate.bleReceiveTransparentData(_:devId:)` callback.
///
/// The app adapter owns one instance for the exact official Smart Life BLE attempt.
/// `capture(...)` is intentionally synchronous so the package connection generation and
/// expected Tuya device identity are sealed at the SDK delegate boundary before any actor
/// hop. `record(...)` then admits that immutable receipt through the actor-owned
/// authenticated session.
///
/// This bridge is read-only. It has no API for publishing DPs, transparent writes,
/// pairing, reset, removal, or unbind. Recorded SDK-transparent bytes remain diagnostic
/// evidence only because Tuya's documented callback does not expose the underlying GATT
/// service/characteristic tuple required for raw FD50 physical first acceptance.
@MainActor
public final class C7D09A22DocumentedTransparentReceiveIngress {
    public typealias Receipt = C7D09A22GenerationBoundTransparentReceiveReceipt
    public typealias RecordResult = C7D09A22AuthenticatedTransparentReceiveSession.RecordResult
    public typealias DiagnosticSnapshot = TuyaSmartLifeTransparentReceiveObservationLedger.Snapshot

    private var activeConnectionToken: TuyaReadOnlyConnectionToken?
    private var expectedDeviceID: String?
    private var session: C7D09A22AuthenticatedTransparentReceiveSession?

    public init() {}

    /// Preferred app-adapter entrypoint. Chronology is derived from the immutable package
    /// authentication snapshot rather than from a second app-owned clock sample. This prevents
    /// the live SDK adapter from accidentally inventing or drifting the connection-start time
    /// while wiring Tuya's process-global transparent receive delegate after authentication.
    @discardableResult
    public func begin(
        connectionToken: TuyaReadOnlyConnectionToken,
        expectedDeviceID: String,
        authenticatedPreflightSnapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot
    ) async -> Bool {
        guard let connectionStartedAt = authenticatedPreflightSnapshot.connectionStartedAtUptimeNanoseconds else {
            await retire()
            return false
        }
        return await begin(
            connectionToken: connectionToken,
            expectedDeviceID: expectedDeviceID,
            sdkConnectionStartedAtUptimeNanoseconds: connectionStartedAt,
            authenticatedPreflightSnapshot: authenticatedPreflightSnapshot
        )
    }

    /// Arms ingress only for a package-issued generation that is already authenticated by
    /// the official Smart Life SDK for this same generation. A connection token by itself
    /// is not authentication authority. A second begin always retires the previous
    /// generation and device identity first.
    @discardableResult
    public func begin(
        connectionToken: TuyaReadOnlyConnectionToken,
        expectedDeviceID: String,
        sdkConnectionStartedAtUptimeNanoseconds: UInt64,
        authenticatedPreflightSnapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot
    ) async -> Bool {
        await retire()

        let normalizedExpectedDeviceID = expectedDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedExpectedDeviceID.isEmpty,
              authenticatedPreflightSnapshot.connectionGeneration == connectionToken.diagnosticGeneration,
              authenticatedPreflightSnapshot.authenticationState == .authenticated,
              authenticatedPreflightSnapshot.authenticationMethod == .smartLifeAppSDK,
              let authenticatedAt = authenticatedPreflightSnapshot.authenticatedAtUptimeNanoseconds,
              authenticatedAt >= sdkConnectionStartedAtUptimeNanoseconds,
              let nextSession = C7D09A22AuthenticatedTransparentReceiveSession(
                connectionToken: connectionToken,
                expectedDeviceID: normalizedExpectedDeviceID,
                sdkConnectionStartedAtUptimeNanoseconds: sdkConnectionStartedAtUptimeNanoseconds
              ) else {
            return false
        }

        activeConnectionToken = connectionToken
        self.expectedDeviceID = normalizedExpectedDeviceID
        session = nextSession
        return true
    }

    /// Call synchronously inside Tuya's documented BLE-manager delegate callback.
    /// Invalid, empty, unowned, wrong-device, or post-retirement callbacks are discarded
    /// before an actor hop. This prevents process-global manager callbacks from another
    /// Tuya device being stamped with the scooter's active package generation.
    public func capture(payload: Data, callbackDeviceID: String) -> Receipt? {
        let normalizedCallbackDeviceID = callbackDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let expectedDeviceID,
              normalizedCallbackDeviceID == expectedDeviceID else {
            return nil
        }

        return C7D09A22GenerationBoundTransparentReceiveReceipt.capture(
            payload: payload,
            callbackDeviceID: normalizedCallbackDeviceID,
            activeConnectionToken: activeConnectionToken
        )
    }

    /// Actor-serialized admission for one already sealed callback receipt.
    /// The caller supplies the package-owned authenticated snapshot for this same
    /// connection generation; cross-generation and stale callbacks fail closed.
    public func record(
        _ receipt: Receipt,
        preflightSnapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot
    ) async -> RecordResult? {
        guard let session else { return nil }
        return await session.recordDocumentedTransparentReceive(
            receipt,
            preflightSnapshot: preflightSnapshot,
            activeConnectionToken: activeConnectionToken
        )
    }

    /// Returns only non-secret, read-only transport diagnostics for the currently armed
    /// authenticated generation. This is the package boundary the app can use to show and
    /// export whether documented Tuya device-to-app bytes actually arrived and whether a
    /// payload arrived strictly beyond C7D09A22's historical ~30-second rejection horizon.
    ///
    /// A positive snapshot still does not establish the raw FD50 GATT characteristic tuple,
    /// so it cannot authorize physical first acceptance or any DP/telemetry semantics.
    public func diagnosticSnapshot() async -> DiagnosticSnapshot? {
        guard let session else { return nil }
        return await session.snapshot
    }

    /// Permanently retires the active generation and device identity before releasing its
    /// token. Delayed process-global Tuya callbacks therefore cannot be borrowed by a later
    /// attempt or a different selected device.
    public func retire() async {
        if let session {
            await session.retire()
        }
        session = nil
        expectedDeviceID = nil
        activeConnectionToken = nil
    }

    public var hasActiveGeneration: Bool {
        activeConnectionToken != nil && expectedDeviceID != nil && session != nil
    }

    // SDK-transparent callback custody is diagnostic-only and cannot mint protocol truth.
    public var authorizesRawFD50CharacteristicCustody: Bool { false }
    public var authorizesPhysicalFirstAcceptance: Bool { false }
    public var authorizesStationaryMapping: Bool { false }
    public var authorizesTelemetrySemantics: Bool { false }
    public var authorizesControlWrites: Bool { false }
    public var authorizesPairingResetOrUnbind: Bool { false }
}

import Foundation
import NembraBluetoothCapture

#if canImport(ThingSmartHomeKit)
import ThingSmartHomeKit

/// Single-owner, read-only field session for capture C7D09A22's documented Tuya
/// transparent receive path.
///
/// This intentionally packages the process-global BLE-manager delegate lease with the
/// package-owned authenticated receive preflight so `SecureLinkController` only has one
/// object to own across its authenticated generation. It does not send DPs, transparent
/// writes, reset/remove/unbind requests, or infer scooter semantics.
@MainActor
final class SmartLifeTransparentFieldSession {
    typealias Generation = TuyaReadOnlyConnectionToken
    typealias FieldAttemptEvidence = C7D09A22DocumentedTransparentLivePreflight.FieldAttemptEvidence

    private let preflight: C7D09A22DocumentedTransparentLivePreflight
    private let lease: SmartLifeTransparentReceiveLease

    init(
        preflightSnapshotProvider: @escaping C7D09A22DocumentedTransparentLivePreflight.SnapshotProvider,
        recordObserver: C7D09A22DocumentedTransparentLivePreflight.RecordObserver? = nil,
        manager: ThingSmartBLEManager = ThingSmartBLEManager.sharedInstance()
    ) {
        let preflight = C7D09A22DocumentedTransparentLivePreflight(
            preflightSnapshotProvider: preflightSnapshotProvider,
            recordObserver: recordObserver
        )
        self.preflight = preflight
        self.lease = SmartLifeTransparentReceiveLease(preflight: preflight, manager: manager)
    }

    /// Installs the documented receive callback only after the caller supplies the exact
    /// package-authenticated generation and its authenticated snapshot.
    @discardableResult
    func armAfterAuthenticatedLocalBLE(
        connectionToken: Generation,
        expectedDeviceID: String,
        authenticatedPreflightSnapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot
    ) async -> Bool {
        await lease.armAndInstallAfterSmartLifeAuthentication(
            connectionToken: connectionToken,
            expectedDeviceID: expectedDeviceID,
            authenticatedPreflightSnapshot: authenticatedPreflightSnapshot
        ) != nil
    }

    /// Returns one exact-generation coherent cut of the received documented transport
    /// bytes and milestone. A positive result is transport evidence only; it is not raw
    /// FD50 characteristic custody and cannot assign any scooter DP meaning.
    func fieldAttemptEvidence(for connectionToken: Generation) async -> FieldAttemptEvidence? {
        await lease.fieldAttemptEvidence(for: connectionToken)
    }

    func diagnosticSnapshot(
        for connectionToken: Generation
    ) async -> C7D09A22DocumentedTransparentReceiveIngress.DiagnosticSnapshot? {
        await lease.diagnosticSnapshot(for: connectionToken)
    }

    /// Exact-generation terminal retirement. Stale callbacks cannot retire a later field
    /// generation because the underlying lease is generation-fenced.
    func terminalLifecycleDidOccur(for connectionToken: Generation) async {
        await lease.terminalLifecycleDidOccur(for: connectionToken)
    }

    /// Owner teardown for view/process destruction when no later generation can survive.
    func terminalOwnerTeardown() async {
        await lease.terminalOwnerTeardown()
    }

    var authorizesRawFD50CharacteristicCustody: Bool { false }
    var authorizesPhysicalFirstAcceptance: Bool { false }
    var authorizesStationaryMapping: Bool { false }
    var authorizesTelemetrySemantics: Bool { false }
    var authorizesControlWrites: Bool { false }
    var authorizesPairingResetOrUnbind: Bool { false }
}
#endif

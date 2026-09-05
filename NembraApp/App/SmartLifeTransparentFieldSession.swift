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

    /// App-local admission diagnostics for installing the documented receive-only callback.
    ///
    /// These verdicts deliberately describe only why the manager delegate lease was or was not
    /// installed. They never promote transparent callback bytes into raw FD50 characteristic
    /// custody, scooter DP meaning, or mutation authority.
    enum ArmVerdict: Equatable {
        case installed
        case blockedMissingDeviceID
        case blockedUnauthenticated
        case blockedWrongAuthenticationMethod
        case blockedStaleGeneration
        case blockedDelegateLease

        var installedReceiveOnlyDelegate: Bool { self == .installed }
    }

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
    ///
    /// This app-side boundary deliberately repeats the minimum provenance checks before the
    /// process-global Tuya manager delegate can be leased. A stale or merely transport-successful
    /// snapshot therefore cannot install receive custody even if a caller reaches this method by
    /// mistake. The package-owned preflight remains the final authority.
    ///
    /// The explicit verdict is intended for live field diagnostics so a failed installation is
    /// observable without weakening any admission gate or guessing a recovery write.
    func armVerdictAfterAuthenticatedLocalBLE(
        connectionToken: Generation,
        expectedDeviceID: String,
        authenticatedPreflightSnapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot
    ) async -> ArmVerdict {
        let normalizedDeviceID = expectedDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDeviceID.isEmpty else {
            return .blockedMissingDeviceID
        }
        guard authenticatedPreflightSnapshot.authenticationState == .authenticated else {
            return .blockedUnauthenticated
        }
        guard authenticatedPreflightSnapshot.authenticationMethod == .smartLifeAppSDK else {
            return .blockedWrongAuthenticationMethod
        }
        guard authenticatedPreflightSnapshot.connectionGeneration == connectionToken.diagnosticGeneration else {
            return .blockedStaleGeneration
        }

        let installed = await lease.armAndInstallAfterSmartLifeAuthentication(
            connectionToken: connectionToken,
            expectedDeviceID: normalizedDeviceID,
            authenticatedPreflightSnapshot: authenticatedPreflightSnapshot
        ) != nil
        return installed ? .installed : .blockedDelegateLease
    }

    @discardableResult
    func armAfterAuthenticatedLocalBLE(
        connectionToken: Generation,
        expectedDeviceID: String,
        authenticatedPreflightSnapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot
    ) async -> Bool {
        await armVerdictAfterAuthenticatedLocalBLE(
            connectionToken: connectionToken,
            expectedDeviceID: expectedDeviceID,
            authenticatedPreflightSnapshot: authenticatedPreflightSnapshot
        ).installedReceiveOnlyDelegate
    }

    /// Returns one exact-generation coherent cut of the received documented transport
    /// bytes and milestone. A positive result is transport evidence only; it is not raw
    /// FD50 characteristic custody and cannot assign any scooter DP meaning.
    ///
    /// Every coherent cut is also best-effort persisted as an app-local JSON sidecar. This
    /// closes the field-artifact gap where the live watchdog could observe authenticated Tuya
    /// callback bytes while the primary capture JSON only retained the milestone event. The
    /// sidecar is keyed by the exact authenticated generation, replaced atomically as evidence
    /// grows, and contains the projection's explicit false authority flags. Persistence failure
    /// never changes transport acceptance or triggers a scooter-side recovery action.
    func fieldAttemptEvidence(for connectionToken: Generation) async -> FieldAttemptEvidence? {
        guard let evidence = await lease.fieldAttemptEvidence(for: connectionToken) else {
            return nil
        }
        persistEvidenceSidecarBestEffort(
            SmartLifeTransparentFieldEvidenceProjection.from(evidence)
        )
        return evidence
    }

    private func persistEvidenceSidecarBestEffort(
        _ projection: SmartLifeTransparentFieldEvidenceProjection
    ) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(projection),
              let applicationSupport = try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
              ) else {
            return
        }

        let directory = applicationSupport
            .appendingPathComponent("Nembra", isDirectory: true)
            .appendingPathComponent("PhysicalTruth", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let url = directory.appendingPathComponent(
                "authenticated-transparent-generation-\(projection.connectionGeneration).json",
                isDirectory: false
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // Local evidence persistence is deliberately non-authoritative. A filesystem
            // failure must never alter the authenticated read-only transport lifecycle.
        }
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

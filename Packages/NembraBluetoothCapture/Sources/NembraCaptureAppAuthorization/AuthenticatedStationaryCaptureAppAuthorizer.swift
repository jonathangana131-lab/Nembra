import Foundation
import NembraBluetoothCapture

/// Process-local handle for one live authorization attempt.
///
/// Callers can inspect the package-generated challenge needed by the independent signer, but they
/// cannot construct the underlying attempt or the physical-attempt capability themselves.
public struct AuthenticatedStationaryCapturePreparedAttempt: Sendable {
    public let challengeSHA256: String
    public let startedAtWallClockUnixMilliseconds: Int64
    public let startedAtUptimeNanoseconds: UInt64
    public let procedureID: String

    fileprivate let packageAttempt: AuthenticatedStationaryCaptureAttempt

    fileprivate init(packageAttempt: AuthenticatedStationaryCaptureAttempt) {
        self.packageAttempt = packageAttempt
        challengeSHA256 = packageAttempt.challengeSHA256
        startedAtWallClockUnixMilliseconds = packageAttempt.startedAtWallClockUnixMilliseconds
        startedAtUptimeNanoseconds = packageAttempt.startedAtUptimeNanoseconds
        procedureID = AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID
    }
}

public enum AuthenticatedStationaryCaptureAppAuthorizerError: Error, Equatable, Sendable {
    case manifestBundleMismatch
    case manifestRuntimeMismatch
    case manifestAttemptBindingsMismatch
}

/// App-owned composition seam for authenticated stationary Capture authorization.
///
/// This adapter deliberately owns no Boolean field-authority switch. It can only:
/// 1. ask `NembraBluetoothCapture` to create a live, runtime-bound attempt;
/// 2. expose that attempt's random challenge to the independent signing workflow; and
/// 3. cross-bind the retained install manifest to the running build and stable attempt bindings
///    before presenting the post-install signed envelope to the package verifier.
///
/// The retained install manifest intentionally cannot contain the signed authorization envelope:
/// that envelope depends on the fresh process-local challenge created after installation. The
/// package verifier instead binds the envelope itself to this exact prepared attempt, runtime build,
/// external evidence bindings, time window, and one-time replay-consumption request.
///
/// With the package production trust root still unset, `authorize` remains mechanically NO-GO.
/// Pinning that root later is a separate independently reviewed change; this type must not grow a
/// caller-supplied trust-key escape hatch.
@MainActor
public final class AuthenticatedStationaryCaptureAppAuthorizer {
    private let consumptionStore: any AuthenticatedStationaryCaptureAuthorizationConsumptionStore

    public convenience init() {
        self.init(consumptionStore: ThisDeviceAuthorizationConsumptionStore())
    }

    package init(
        consumptionStore: any AuthenticatedStationaryCaptureAuthorizationConsumptionStore
    ) {
        self.consumptionStore = consumptionStore
    }

    /// Starts one live authorization attempt from the separately accepted external install/evidence
    /// bindings. The app-generated challenge is needed before the signer can create the envelope.
    /// This does not start OFF1, scan Bluetooth, authenticate Tuya, or grant physical GO.
    public func beginAttempt(
        externalBindings: AuthenticatedStationaryCaptureExternalBindings
    ) throws -> AuthenticatedStationaryCapturePreparedAttempt {
        let attempt = try AuthenticatedStationaryCaptureFieldAuthorizationVerifier
            .makeCurrentApplicationAttempt(externalBindings: externalBindings)
        return AuthenticatedStationaryCapturePreparedAttempt(packageAttempt: attempt)
    }

    /// Verifies the retained install manifest against the running app and the exact prepared
    /// attempt's stable evidence bindings before the package-pinned signature verifier evaluates
    /// the post-install envelope and may consume replay state or mint the opaque capability.
    public func authorize(
        envelopeData: Data,
        installManifestData: Data,
        preparedAttempt: AuthenticatedStationaryCapturePreparedAttempt
    ) throws -> AuthenticatedStationaryCaptureAttemptCapability {
        let runtimeBuildIdentity = try PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .currentApplication()
        try validateInstallManifest(
            installManifestData,
            preparedAttempt: preparedAttempt,
            currentBundleIdentifier: Bundle.main.bundleIdentifier,
            runtimeBuildIdentity: runtimeBuildIdentity
        )

        return try AuthenticatedStationaryCaptureFieldAuthorizationVerifier.verifyForCurrentApplication(
            envelopeData,
            attempt: preparedAttempt.packageAttempt,
            consumptionStore: consumptionStore
        )
    }

    private func validateInstallManifest(
        _ installManifestData: Data,
        preparedAttempt: AuthenticatedStationaryCapturePreparedAttempt,
        currentBundleIdentifier: String?,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) throws {
        let manifest = try AuthenticatedStationaryCaptureInstallManifestVerifier
            .decodeCanonical(installManifestData)

        guard currentBundleIdentifier == manifest.bundleIdentifier else {
            throw AuthenticatedStationaryCaptureAppAuthorizerError.manifestBundleMismatch
        }
        guard manifest.matches(runtimeBuildIdentity: runtimeBuildIdentity) else {
            throw AuthenticatedStationaryCaptureAppAuthorizerError.manifestRuntimeMismatch
        }
        guard try manifest.externalBindings() == preparedAttempt.packageAttempt.externalBindings else {
            throw AuthenticatedStationaryCaptureAppAuthorizerError.manifestAttemptBindingsMismatch
        }
    }

    /// Deterministic manifest-cross-binding seam used only by tests in this Swift package. It does
    /// not invoke the production trust root, consume replay state, or mint a capability.
    package func validateInstallManifestForTesting(
        _ installManifestData: Data,
        preparedAttempt: AuthenticatedStationaryCapturePreparedAttempt,
        currentBundleIdentifier: String?,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) throws {
        try validateInstallManifest(
            installManifestData,
            preparedAttempt: preparedAttempt,
            currentBundleIdentifier: currentBundleIdentifier,
            runtimeBuildIdentity: runtimeBuildIdentity
        )
    }

    /// Deterministic construction seam used only by tests in this Swift package. It preserves the
    /// same opaque wrapper while avoiding dependence on a test host's Bundle.main metadata.
    package func prepareForTesting(
        externalBindings: AuthenticatedStationaryCaptureExternalBindings,
        challenge: Data,
        bundleIdentifier: String,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        wallClockUnixMilliseconds: Int64,
        uptimeNanoseconds: UInt64
    ) throws -> AuthenticatedStationaryCapturePreparedAttempt {
        let attempt = try AuthenticatedStationaryCaptureFieldAuthorizationVerifier.makeAttempt(
            externalBindings: externalBindings,
            challenge: challenge,
            bundleIdentifier: bundleIdentifier,
            runtimeBuildIdentity: runtimeBuildIdentity,
            wallClockUnixMilliseconds: wallClockUnixMilliseconds,
            uptimeNanoseconds: uptimeNanoseconds
        )
        return AuthenticatedStationaryCapturePreparedAttempt(packageAttempt: attempt)
    }
}

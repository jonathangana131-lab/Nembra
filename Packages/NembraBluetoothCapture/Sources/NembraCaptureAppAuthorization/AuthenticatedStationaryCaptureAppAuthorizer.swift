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
/// 1. prove the retained install manifest matches the application that is actually running;
/// 2. ask `NembraBluetoothCapture` to create a live, runtime-bound attempt from those exact stable
///    manifest bindings;
/// 3. expose that attempt's random challenge to the independent signing workflow; and
/// 4. re-check the retained manifest before presenting the post-install signed envelope to the
///    package verifier.
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

    /// Preferred production entry point. The signer rendezvous cannot begin until the exact retained
    /// install manifest has been decoded and cross-bound to the running bundle/build identity.
    /// Returning a challenge is not physical authority and does not consume replay state.
    public func beginAttempt(
        installManifestData: Data
    ) throws -> AuthenticatedStationaryCapturePreparedAttempt {
        let runtimeBuildIdentity = try PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .currentApplication()
        let manifest = try validateInstallManifestForRunningApplication(
            installManifestData,
            currentBundleIdentifier: Bundle.main.bundleIdentifier,
            runtimeBuildIdentity: runtimeBuildIdentity
        )
        return try beginAttempt(externalBindings: manifest.externalBindings())
    }

    /// Lower-level composition seam retained for callers that have already established the exact
    /// stable external bindings through a separately accepted path. Normal app flow should prefer
    /// `beginAttempt(installManifestData:)` so stale/caller-substituted retained subjects cannot even
    /// obtain a signer challenge.
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

    private func validateInstallManifestForRunningApplication(
        _ installManifestData: Data,
        currentBundleIdentifier: String?,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) throws -> AuthenticatedStationaryCaptureInstallManifest {
        let manifest = try AuthenticatedStationaryCaptureInstallManifestVerifier
            .decodeCanonical(installManifestData)
        guard currentBundleIdentifier == manifest.bundleIdentifier else {
            throw AuthenticatedStationaryCaptureAppAuthorizerError.manifestBundleMismatch
        }
        guard manifest.matches(runtimeBuildIdentity: runtimeBuildIdentity) else {
            throw AuthenticatedStationaryCaptureAppAuthorizerError.manifestRuntimeMismatch
        }
        return manifest
    }

    private func validateInstallManifest(
        _ installManifestData: Data,
        preparedAttempt: AuthenticatedStationaryCapturePreparedAttempt,
        currentBundleIdentifier: String?,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) throws {
        let manifest = try validateInstallManifestForRunningApplication(
            installManifestData,
            currentBundleIdentifier: currentBundleIdentifier,
            runtimeBuildIdentity: runtimeBuildIdentity
        )
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

    /// Deterministic pre-signing seam used only by package tests. It proves the exact manifest is
    /// accepted for the supplied test runtime before creating the challenge-bound attempt.
    package func prepareFromInstallManifestForTesting(
        _ installManifestData: Data,
        challenge: Data,
        currentBundleIdentifier: String?,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        wallClockUnixMilliseconds: Int64,
        uptimeNanoseconds: UInt64
    ) throws -> AuthenticatedStationaryCapturePreparedAttempt {
        let manifest = try validateInstallManifestForRunningApplication(
            installManifestData,
            currentBundleIdentifier: currentBundleIdentifier,
            runtimeBuildIdentity: runtimeBuildIdentity
        )
        return try prepareForTesting(
            externalBindings: manifest.externalBindings(),
            challenge: challenge,
            bundleIdentifier: try requireBundleIdentifier(currentBundleIdentifier),
            runtimeBuildIdentity: runtimeBuildIdentity,
            wallClockUnixMilliseconds: wallClockUnixMilliseconds,
            uptimeNanoseconds: uptimeNanoseconds
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

    private func requireBundleIdentifier(_ value: String?) throws -> String {
        guard let value else {
            throw AuthenticatedStationaryCaptureAppAuthorizerError.manifestBundleMismatch
        }
        return value
    }
}

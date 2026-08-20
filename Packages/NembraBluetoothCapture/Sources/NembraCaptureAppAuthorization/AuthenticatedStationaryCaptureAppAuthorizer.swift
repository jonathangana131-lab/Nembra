import Foundation
import NembraBluetoothCapture

/// Process-local handle for one live authorization attempt.
///
/// Callers can inspect the package-generated challenge needed by the independent signer, but they
/// cannot construct the underlying attempt or the physical-attempt capability themselves. The exact
/// retained-install manifest that admitted this attempt is also pinned by SHA-256 for the lifetime
/// of the process-local handle so a different install subject cannot be substituted later.
public struct AuthenticatedStationaryCapturePreparedAttempt: Sendable {
    public let challengeSHA256: String
    public let startedAtWallClockUnixMilliseconds: Int64
    public let startedAtUptimeNanoseconds: UInt64
    public let procedureID: String
    public let installManifestSHA256: String

    fileprivate let packageAttempt: AuthenticatedStationaryCaptureAttempt

    fileprivate init(
        packageAttempt: AuthenticatedStationaryCaptureAttempt,
        installManifestSHA256: String
    ) {
        self.packageAttempt = packageAttempt
        challengeSHA256 = packageAttempt.challengeSHA256
        startedAtWallClockUnixMilliseconds = packageAttempt.startedAtWallClockUnixMilliseconds
        startedAtUptimeNanoseconds = packageAttempt.startedAtUptimeNanoseconds
        procedureID = AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID
        self.installManifestSHA256 = installManifestSHA256
    }
}

public enum AuthenticatedStationaryCaptureAppAuthorizerError: Error, Equatable, Sendable {
    case manifestBundleMismatch
    case manifestRuntimeMismatch
    case manifestAttemptBindingsMismatch
    case manifestChangedSinceAttemptBegan
}

/// App-owned composition seam for authenticated stationary Capture authorization.
///
/// Production attempt creation starts from the one canonical retained-install manifest. The adapter
/// verifies that manifest against the running build, derives its stable evidence bindings, asks
/// `NembraBluetoothCapture` to create the process-local signer challenge, and pins the exact manifest
/// SHA into the prepared handle. The same exact manifest must be presented again with the signed
/// post-install envelope before the package verifier can consume replay state or mint capability.
///
/// The envelope itself remains post-install because it binds the fresh process-local challenge.
/// This adapter owns no Boolean field-authority switch and no caller-selectable trust key. With the
/// package production trust root still unset, `authorize` remains mechanically NO-GO.
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

    /// Starts one live authorization attempt from the exact retained-install manifest already
    /// admitted by the install pipeline. This validates runtime/build identity before challenge
    /// creation. It does not start OFF1, scan Bluetooth, authenticate Tuya, or grant physical GO.
    public func beginAttempt(
        installManifestData: Data
    ) throws -> AuthenticatedStationaryCapturePreparedAttempt {
        let runtimeBuildIdentity = try PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .currentApplication()
        let manifest = try validateManifestRuntime(
            installManifestData,
            currentBundleIdentifier: Bundle.main.bundleIdentifier,
            runtimeBuildIdentity: runtimeBuildIdentity
        )
        let packageAttempt = try AuthenticatedStationaryCaptureFieldAuthorizationVerifier
            .makeCurrentApplicationAttempt(externalBindings: manifest.externalBindings())
        return AuthenticatedStationaryCapturePreparedAttempt(
            packageAttempt: packageAttempt,
            installManifestSHA256: manifest.canonicalManifestSHA256
        )
    }

    /// Verifies that the exact retained manifest which admitted the process-local attempt is still
    /// present and still matches the running app and stable attempt bindings. Only then may the
    /// package-pinned signature verifier evaluate the post-install envelope and consume replay state.
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

    private func validateManifestRuntime(
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
        let manifest = try validateManifestRuntime(
            installManifestData,
            currentBundleIdentifier: currentBundleIdentifier,
            runtimeBuildIdentity: runtimeBuildIdentity
        )
        guard manifest.canonicalManifestSHA256 == preparedAttempt.installManifestSHA256 else {
            throw AuthenticatedStationaryCaptureAppAuthorizerError
                .manifestChangedSinceAttemptBegan
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
        installManifestSHA256: String,
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
        return AuthenticatedStationaryCapturePreparedAttempt(
            packageAttempt: attempt,
            installManifestSHA256: installManifestSHA256
        )
    }
}
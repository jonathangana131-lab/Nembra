import CryptoKit
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
    case runtimeBundleIdentifierUnavailable
    case signedBuildEvidenceDoesNotMatchRunningApplication
    case manifestBundleMismatch
    case manifestRuntimeMismatch
    case manifestAttemptBindingsMismatch
    case manifestAuthorizationEnvelopeMismatch
}

/// App-owned composition seam for authenticated stationary Capture authorization.
///
/// Production attempt creation starts from the exact signed-build evidence bytes retained by the
/// independently accepted build pipeline. The adapter verifies those bytes against the running
/// executable/Info.plist tuple, derives the exact external bindings, then asks
/// `NembraBluetoothCapture` for the process-local signer challenge. After the signer returns an
/// envelope, the final retained-install manifest must cross-bind that exact envelope, running build,
/// and prepared attempt before the package-pinned signature verifier can consume replay state or mint
/// the opaque one-attempt capability.
///
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

    /// Begins one live signer-rendezvous attempt from exact non-authorizing signed-build evidence.
    /// This step validates evidence bytes and runtime/build identity only. It does not start OFF1,
    /// scan Bluetooth, authenticate Tuya, or grant physical GO.
    public func beginAttempt(
        signedBuildEvidenceData: Data
    ) throws -> AuthenticatedStationaryCapturePreparedAttempt {
        let evidence = try AuthenticatedStationaryCaptureSignedBuildEvidenceVerifier
            .decodeCanonical(signedBuildEvidenceData)
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            throw AuthenticatedStationaryCaptureAppAuthorizerError
                .runtimeBundleIdentifierUnavailable
        }
        let runtime = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()
        guard evidence.matches(
            runtimeBuildIdentity: runtime,
            bundleIdentifier: bundleIdentifier
        ) else {
            throw AuthenticatedStationaryCaptureAppAuthorizerError
                .signedBuildEvidenceDoesNotMatchRunningApplication
        }
        return try beginAttempt(externalBindings: evidence.externalBindings())
    }

    /// Package-only seam for already-validated bindings. Keeping this non-public prevents the app
    /// product from accidentally creating signer challenges from arbitrary caller-authored digests.
    package func beginAttempt(
        externalBindings: AuthenticatedStationaryCaptureExternalBindings
    ) throws -> AuthenticatedStationaryCapturePreparedAttempt {
        let attempt = try AuthenticatedStationaryCaptureFieldAuthorizationVerifier
            .makeCurrentApplicationAttempt(externalBindings: externalBindings)
        return AuthenticatedStationaryCapturePreparedAttempt(packageAttempt: attempt)
    }

    /// Verifies the final retained-install manifest against the running app, exact prepared attempt,
    /// and exact signed envelope bytes before the package-pinned signature verifier can consume
    /// replay state or mint the opaque one-attempt capability.
    public func authorize(
        envelopeData: Data,
        installManifestData: Data,
        preparedAttempt: AuthenticatedStationaryCapturePreparedAttempt
    ) throws -> AuthenticatedStationaryCaptureAttemptCapability {
        let runtimeBuildIdentity = try PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .currentApplication()
        try validateFinalManifest(
            installManifestData,
            envelopeData: envelopeData,
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

    private func validateFinalManifest(
        _ installManifestData: Data,
        envelopeData: Data,
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
        guard manifest.authorizationEnvelopeSHA256 == Self.sha256Hex(envelopeData) else {
            throw AuthenticatedStationaryCaptureAppAuthorizerError
                .manifestAuthorizationEnvelopeMismatch
        }
    }

    /// Deterministic final-manifest cross-binding seam used only by tests in this Swift package. It
    /// does not invoke the production trust root, consume replay state, or mint a capability.
    package func validateFinalManifestForTesting(
        _ installManifestData: Data,
        envelopeData: Data,
        preparedAttempt: AuthenticatedStationaryCapturePreparedAttempt,
        currentBundleIdentifier: String?,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) throws {
        try validateFinalManifest(
            installManifestData,
            envelopeData: envelopeData,
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

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
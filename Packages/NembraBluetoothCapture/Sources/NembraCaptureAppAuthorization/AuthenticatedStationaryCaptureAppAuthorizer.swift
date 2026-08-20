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
}

/// App-owned composition seam for authenticated stationary Capture authorization.
///
/// This adapter deliberately owns no Boolean field-authority switch. Production attempt creation
/// starts from the exact signed-build evidence bytes retained by the independently accepted build
/// pipeline. The adapter validates that evidence against the running executable/Info.plist tuple,
/// hashes those exact evidence bytes into the external bindings, asks `NembraBluetoothCapture` to
/// create a process-local challenge, and later presents the independent signed response back to the
/// package verifier using the durable ThisDeviceOnly Keychain replay-consumption store.
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

    /// Begins one live signer-rendezvous attempt from the exact non-authorizing signed-build
    /// evidence. This verifies byte grammar and runtime/build identity only; it does not trust the
    /// evidence as physical authority. Only the later package-pinned signature can mint capability.
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

    /// Verifies the independent signed response for exactly the prepared live attempt.
    /// Successful replay consumption and capability construction remain package-owned.
    public func authorize(
        envelopeData: Data,
        preparedAttempt: AuthenticatedStationaryCapturePreparedAttempt
    ) throws -> AuthenticatedStationaryCaptureAttemptCapability {
        try AuthenticatedStationaryCaptureFieldAuthorizationVerifier.verifyForCurrentApplication(
            envelopeData,
            attempt: preparedAttempt.packageAttempt,
            consumptionStore: consumptionStore
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
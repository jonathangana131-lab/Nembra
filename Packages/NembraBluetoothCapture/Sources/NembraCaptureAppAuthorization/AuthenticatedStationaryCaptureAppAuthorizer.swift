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

/// App-owned composition seam for authenticated stationary Capture authorization.
///
/// This adapter deliberately owns no Boolean field-authority switch. It can only:
/// 1. ask `NembraBluetoothCapture` to create a live, runtime-bound attempt;
/// 2. expose that attempt's random challenge to the independent signing workflow; and
/// 3. present the returned signed envelope back to the package verifier using the durable
///    ThisDeviceOnly Keychain replay-consumption store.
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

    /// Starts one live authorization attempt from already-validated external install/evidence
    /// bindings. This does not start OFF1, scan Bluetooth, authenticate Tuya, or grant physical GO.
    public func beginAttempt(
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

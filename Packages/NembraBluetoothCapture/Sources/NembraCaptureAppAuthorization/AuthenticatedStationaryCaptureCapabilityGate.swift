import Foundation
import NembraBluetoothCapture

public enum AuthenticatedStationaryCaptureCapabilityGateError: Error, Equatable, Sendable {
    case invalidCapability
    case authorizationExpired
    case invalidTransition
    case authorizationRevoked
    case capabilityAlreadyClaimed
}

/// App-owned lifecycle gate for one verifier-minted authenticated-stationary capability.
///
/// The verifier remains the only authority that can mint
/// `AuthenticatedStationaryCaptureAttemptCapability`. This gate does not parse envelopes, select
/// keys, authorize a build, touch Bluetooth, or create a second authority path. It only keeps the
/// opaque capability private and makes the app prove the accepted one-attempt sequence at every
/// boundary that can advance toward physical observation.
///
/// A gate is single-use, and one verifier-minted capability may claim OFF1 in at most one gate in
/// this process. `revoke()` is terminal for an unfinished attempt, every transition re-checks both
/// wall and monotonic expiry, and no API returns the underlying capability to a caller. Once sealed,
/// later lifecycle cleanup cannot downgrade the already-terminal sealed state.
@MainActor
public final class AuthenticatedStationaryCaptureCapabilityGate {
    public enum Stage: Equatable, Sendable {
        case armed
        case off1Started
        case authenticationAdmitted
        case officialConnectionAdmitted
        case observationAdmitted
        case sealed
        case revoked
    }

    public private(set) var stage: Stage = .armed

    /// Replay consumption prevents the same signed authorization from minting a second capability.
    /// This process-local fence closes the remaining object-aliasing path: callers cannot take one
    /// already-minted capability reference, wrap it in multiple gates, and spend it on multiple
    /// OFF1 starts. Claims are intentionally never released by revoke/seal. After process restart,
    /// the durable consumption store still prevents the authorization from being minted again.
    private static var claimedOFF1ConsumptionRequestIdentities = Set<String>()

    private let capability: AuthenticatedStationaryCaptureAttemptCapability
    private let wallClockUnixMilliseconds: @Sendable () -> Int64
    private let uptimeNanoseconds: @Sendable () -> UInt64

    public convenience init(capability: AuthenticatedStationaryCaptureAttemptCapability) {
        self.init(
            capability: capability,
            wallClockUnixMilliseconds: {
                Int64((Date().timeIntervalSince1970 * 1_000.0).rounded(.towardZero))
            },
            uptimeNanoseconds: { DispatchTime.now().uptimeNanoseconds }
        )
    }

    package init(
        capability: AuthenticatedStationaryCaptureAttemptCapability,
        wallClockUnixMilliseconds: @escaping @Sendable () -> Int64,
        uptimeNanoseconds: @escaping @Sendable () -> UInt64
    ) {
        self.capability = capability
        self.wallClockUnixMilliseconds = wallClockUnixMilliseconds
        self.uptimeNanoseconds = uptimeNanoseconds
    }

    /// The only admission that can begin a physical power-cycle series. It can succeed once for
    /// this gate and once for this exact verifier-minted capability across all gates in the process.
    public func admitOFF1Start() throws {
        guard stage != .revoked else {
            throw AuthenticatedStationaryCaptureCapabilityGateError.authorizationRevoked
        }
        guard stage == .armed else {
            throw AuthenticatedStationaryCaptureCapabilityGateError.invalidTransition
        }
        try validateCapabilityIsCurrent()

        let identity = capability.consumptionRequest.requestIdentitySHA256
        guard Self.claimedOFF1ConsumptionRequestIdentities.insert(identity).inserted else {
            revoke()
            throw AuthenticatedStationaryCaptureCapabilityGateError.capabilityAlreadyClaimed
        }
        stage = .off1Started
    }

    /// Re-checks the same capability immediately before authenticated Tuya ownership is requested.
    public func admitAuthenticationStart() throws {
        try advance(from: .off1Started, to: .authenticationAdmitted)
    }

    /// Re-checks the capability immediately before the official SDK connection request is emitted.
    public func admitOfficialConnectionStart() throws {
        try advance(from: .authenticationAdmitted, to: .officialConnectionAdmitted)
    }

    /// Re-checks the capability before authenticated application evidence can enter observation.
    public func admitObservationStart() throws {
        try advance(from: .officialConnectionAdmitted, to: .observationAdmitted)
    }

    /// Seals this authority after the accepted artifact has been frozen. A sealed gate cannot be
    /// restarted or reused for another OFF1 series.
    public func seal() throws {
        try advance(from: .observationAdmitted, to: .sealed)
    }

    /// Terminally retires unfinished authority after foreground loss, view exit, account/source
    /// loss, lifecycle failure, cancellation, or any other abandoned attempt. A successfully sealed
    /// authority remains sealed so later cleanup cannot repaint completed evidence as abandoned.
    /// Revocation never releases an OFF1 claim for reuse by another gate.
    public func revoke() {
        guard stage != .sealed else { return }
        stage = .revoked
    }

    private func advance(from expected: Stage, to next: Stage) throws {
        guard stage != .revoked else {
            throw AuthenticatedStationaryCaptureCapabilityGateError.authorizationRevoked
        }
        guard stage == expected else {
            throw AuthenticatedStationaryCaptureCapabilityGateError.invalidTransition
        }
        try validateCapabilityIsCurrent()
        stage = next
    }

    private func validateCapabilityIsCurrent() throws {
        guard capability.procedureID == AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID,
              capability.maximumOFF1Starts == 1 else {
            revoke()
            throw AuthenticatedStationaryCaptureCapabilityGateError.invalidCapability
        }

        let nowWall = wallClockUnixMilliseconds()
        let nowUptime = uptimeNanoseconds()
        guard nowWall > 0,
              nowUptime > 0,
              nowWall < capability.expiresAtUnixMilliseconds,
              nowUptime < capability.expiresAtUptimeNanoseconds else {
            revoke()
            throw AuthenticatedStationaryCaptureCapabilityGateError.authorizationExpired
        }
    }
}

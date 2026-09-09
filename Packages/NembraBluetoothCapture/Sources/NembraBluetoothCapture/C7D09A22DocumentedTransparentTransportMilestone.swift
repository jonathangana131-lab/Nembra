import Foundation

/// Read-only milestone evaluator for C7D09A22's documented Tuya transparent-receive path.
///
/// This gate intentionally distinguishes a *documented authenticated transport milestone* from
/// raw-FD50 physical first acceptance. Tuya's public BLE-manager callback proves that bytes were
/// delivered through the authenticated Smart Life SDK session, but it does not expose the GATT
/// service/characteristic tuple required to claim raw FD50 custody or assign any DP semantics.
public enum C7D09A22DocumentedTransparentTransportMilestone {
    public enum Verdict: Equatable, Sendable {
        case blockedUnauthenticated
        case waitingForFirstPayload
        case waitingForHistoricalRejectionWindow
        case satisfied
    }

    public static func verdict(
        authenticatedPreflight: TuyaAuthenticatedReadOnlyPreflightSnapshot,
        transparent: TuyaSmartLifeTransparentReceiveObservationLedger.Snapshot?
    ) -> Verdict {
        guard authenticatedPreflight.authenticationState == .authenticated,
              authenticatedPreflight.authenticationMethod == .smartLifeAppSDK,
              authenticatedPreflight.authenticatedAtUptimeNanoseconds != nil else {
            return .blockedUnauthenticated
        }
        guard let transparent, transparent.payloadCount > 0 else {
            return .waitingForFirstPayload
        }
        guard transparent.hasPayloadStrictlyBeyondHistoricalRejectionHorizon else {
            return .waitingForHistoricalRejectionWindow
        }
        return .satisfied
    }

    // This milestone is transport evidence only. It cannot mint protocol meaning or mutation.
    public static var authorizesRawFD50CharacteristicCustody: Bool { false }
    public static var authorizesPhysicalFirstAcceptance: Bool { false }
    public static var authorizesStationaryMapping: Bool { false }
    public static var authorizesTelemetrySemantics: Bool { false }
    public static var authorizesControlWrites: Bool { false }
    public static var authorizesPairingResetOrUnbind: Bool { false }
}

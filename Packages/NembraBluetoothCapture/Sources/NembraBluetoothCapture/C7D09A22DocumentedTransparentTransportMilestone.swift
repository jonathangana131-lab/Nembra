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
              authenticatedPreflight.hasActiveCallbackAuthority,
              let authenticatedAt = authenticatedPreflight.authenticatedAtUptimeNanoseconds else {
            return .blockedUnauthenticated
        }
        guard let transparent, transparent.payloadCount > 0 else {
            return .waitingForFirstPayload
        }
        // Keep the visible transport milestone aligned with physical acceptance's repeated-receive
        // contract. A single delayed/bootstrap callback, even one arriving after 30 seconds, is not
        // enough to present this generation as having satisfied authenticated receive liveness.
        guard transparent.payloadCount >= TuyaPhysicalFirstAcceptanceGate.minimumDocumentedReceivePayloadCount else {
            return .waitingForHistoricalRejectionWindow
        }

        // The historical unauthenticated failure happened around 30 seconds after connection, but
        // the P0 acceptance claim is stronger: the *authenticated* Smart Life session itself must
        // be independently observed alive beyond that window, and a documented device-to-app
        // callback must also land beyond the same post-authentication boundary. Do not reuse the
        // transparent ledger's connection-start-relative convenience bit here because authentication
        // can occur seconds after connect. Likewise, a queued callback cannot prove transport
        // survival if the package ledger was not independently observed at or after that callback.
        guard let latestObserved = authenticatedPreflight.latestObservedUptimeNanoseconds,
              let latestPayload = transparent.latestPayloadAtUptimeNanoseconds,
              latestObserved >= latestPayload,
              latestObserved >= authenticatedAt,
              latestPayload >= authenticatedAt else {
            return .waitingForHistoricalRejectionWindow
        }

        let horizon = TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
        guard latestObserved - authenticatedAt > horizon,
              latestPayload - authenticatedAt > horizon else {
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

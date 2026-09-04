import Foundation

/// Final fail-closed boundary for C7D09A22 physical first acceptance.
///
/// Smart Life SDK authentication and SDK-level DPS/transparent callbacks are useful
/// transport evidence, but they are not raw application-characteristic custody. This
/// gate therefore requires independently observed, non-empty subscribed-notify bytes
/// on the same authenticated physical transport before stationary semantic-mapping
/// work becomes eligible.
///
/// Physical first acceptance is deliberately not telemetry-semantic acceptance. Real
/// authenticated FD50 bytes prove that there is application payload evidence worth
/// mapping; they do not prove that any field/DP means speed, battery, mode, light,
/// brake, power, or another product semantic.
public enum C7D09A22PhysicalFirstAcceptanceGate {
    public struct Evidence: Equatable, Sendable {
        public let authenticatedPreflight: TuyaAuthenticatedReadOnlyPreflightSnapshot
        public let rawNotifyPayloadCount: Int
        public let rawNotifyObservedAfterAuthentication: Bool
        public let canonicalFD50CharacteristicTupleProven: Bool
        public let sameAuthenticatedTransportCustodyProven: Bool

        public init(
            authenticatedPreflight: TuyaAuthenticatedReadOnlyPreflightSnapshot,
            rawNotifyPayloadCount: Int,
            rawNotifyObservedAfterAuthentication: Bool,
            canonicalFD50CharacteristicTupleProven: Bool,
            sameAuthenticatedTransportCustodyProven: Bool
        ) {
            self.authenticatedPreflight = authenticatedPreflight
            self.rawNotifyPayloadCount = max(0, rawNotifyPayloadCount)
            self.rawNotifyObservedAfterAuthentication = rawNotifyObservedAfterAuthentication
            self.canonicalFD50CharacteristicTupleProven = canonicalFD50CharacteristicTupleProven
            self.sameAuthenticatedTransportCustodyProven = sameAuthenticatedTransportCustodyProven
        }
    }

    public enum Verdict: Equatable, Sendable {
        case blocked(reason: String)
        case accepted
    }

    public static func verdict(for evidence: Evidence) -> Verdict {
        guard TuyaAuthenticatedReadOnlyPreflight.verdict(for: evidence.authenticatedPreflight) == .readyForStationaryMapping else {
            return .blocked(reason: "Authenticated Smart Life preflight has not survived the required stability and application-evidence horizon.")
        }
        guard evidence.rawNotifyPayloadCount > 0 else {
            return .blocked(reason: "No non-empty raw application-characteristic notification payload has been captured.")
        }
        guard evidence.rawNotifyObservedAfterAuthentication else {
            return .blocked(reason: "Raw notification evidence is not proven to have arrived after authentication of this connection generation.")
        }
        guard evidence.canonicalFD50CharacteristicTupleProven else {
            return .blocked(reason: "The raw notification is not yet proven to belong to the canonical FD50 application characteristic tuple.")
        }
        guard evidence.sameAuthenticatedTransportCustodyProven else {
            return .blocked(reason: "Raw notification evidence is not proven to belong to the same authenticated physical transport.")
        }
        return .accepted
    }

    /// Physical acceptance authorizes only the next read-only evidence phase: bounded,
    /// stationary semantic mapping against real authenticated payloads.
    public static func authorizesStationarySemanticMapping(for evidence: Evidence) -> Bool {
        verdict(for: evidence) == .accepted
    }

    /// A payload existing on the authenticated physical transport does not identify
    /// the meaning of any field/DP. Semantic authority must be earned independently by
    /// the mapping/evidence layer after physical first acceptance.
    public static func authorizesTelemetrySemantics(for evidence: Evidence) -> Bool {
        _ = evidence
        return false
    }

    public static func authorizesControlWrites(for evidence: Evidence) -> Bool {
        _ = evidence
        return false
    }

    public static func authorizesPairingResetOrUnbind(for evidence: Evidence) -> Bool {
        _ = evidence
        return false
    }
}

import Foundation

/// Opaque, semantics-free evidence for the first physical Tuya acceptance gate.
///
/// This value deliberately carries no DP identifier, decoded value, control intent, token,
/// local key, session key, or other credential material. It can prove only that non-empty
/// device-to-app bytes were observed on the canonical FD50 notify characteristic while the
/// package owned the same authenticated transport generation.
public struct TuyaPhysicalNotifyEvidence: Equatable, Sendable {
    public enum Direction: String, Equatable, Sendable {
        case deviceToApp
        case appToDevice
    }

    public let connectionGeneration: UInt64
    public let characteristicUUID: String
    public let direction: Direction
    public let receivedAtUptimeNanoseconds: UInt64
    public let payloadByteCount: Int
    public let packageOwnedRawTransportEvidence: Bool
    public let samePhysicalTransportCustodyProven: Bool

    public init(
        connectionGeneration: UInt64,
        characteristicUUID: String,
        direction: Direction,
        receivedAtUptimeNanoseconds: UInt64,
        payloadByteCount: Int,
        packageOwnedRawTransportEvidence: Bool,
        samePhysicalTransportCustodyProven: Bool
    ) {
        self.connectionGeneration = connectionGeneration
        self.characteristicUUID = characteristicUUID
        self.direction = direction
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.payloadByteCount = max(0, payloadByteCount)
        self.packageOwnedRawTransportEvidence = packageOwnedRawTransportEvidence
        self.samePhysicalTransportCustodyProven = samePhysicalTransportCustodyProven
    }
}

/// Final fail-closed boundary for Nembra's first physical acceptance.
///
/// `TuyaAuthenticatedReadOnlyPreflight` proves the documented Smart Life SDK-authenticated
/// application path survived the historical rejection window. This gate additionally requires
/// genuine, package-owned raw FD50 notify bytes from that exact authenticated connection
/// generation. It does not decode or assign any scooter semantics and grants no write authority.
public enum TuyaPhysicalFirstAcceptance {
    public static let canonicalDeviceToAppCharacteristicUUID =
        "00000002-0000-1001-8001-00805F9B07D0"

    public enum Verdict: Equatable, Sendable {
        case blocked(reason: String)
        case accepted
    }

    public static func verdict(
        preflight: TuyaAuthenticatedReadOnlyPreflightSnapshot,
        notify: TuyaPhysicalNotifyEvidence
    ) -> Verdict {
        guard TuyaAuthenticatedReadOnlyPreflight.verdict(for: preflight) == .readyForStationaryMapping else {
            return .blocked(reason: "Authenticated read-only preflight is not ready.")
        }
        guard notify.packageOwnedRawTransportEvidence else {
            return .blocked(reason: "Raw notify evidence is not owned by the live capture transport.")
        }
        guard notify.samePhysicalTransportCustodyProven else {
            return .blocked(reason: "Raw notify evidence lacks same-transport custody proof.")
        }
        guard notify.direction == .deviceToApp else {
            return .blocked(reason: "Physical acceptance requires device-to-app notify evidence.")
        }
        guard notify.payloadByteCount > 0 else {
            return .blocked(reason: "Physical acceptance requires a non-empty notify payload.")
        }
        guard notify.connectionGeneration > 0,
              notify.connectionGeneration == preflight.connectionGeneration else {
            return .blocked(reason: "Notify evidence is not from the authenticated connection generation.")
        }
        guard canonicalizedUUID(notify.characteristicUUID) == canonicalDeviceToAppCharacteristicUUID else {
            return .blocked(reason: "Notify evidence is not from the canonical FD50 device-to-app characteristic.")
        }
        guard let authenticatedAt = preflight.authenticatedAtUptimeNanoseconds,
              notify.receivedAtUptimeNanoseconds >= authenticatedAt else {
            return .blocked(reason: "Notify chronology is unavailable or predates authentication.")
        }
        guard notify.receivedAtUptimeNanoseconds - authenticatedAt
                > TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds else {
            return .blocked(reason: "Raw notify evidence has not survived beyond the historical rejection window.")
        }
        return .accepted
    }

    private static func canonicalizedUUID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

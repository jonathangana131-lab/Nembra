import Foundation

/// Legacy, summary-only Tuya notify metadata.
///
/// This value deliberately carries no DP identifier, decoded value, control intent, token,
/// local key, session key, or other credential material. It is retained for diagnostic/source
/// compatibility only. Summary fields and caller-supplied provenance booleans are not physical
/// evidence and can never authorize Nembra's physical GO boundary.
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

/// Compatibility facade over the canonical C7D09A22 physical-truth boundary.
///
/// Physical GO authority lives only in `C7D09A22PhysicalFirstAcceptance`, whose evidence retains
/// repeated non-empty raw notify bytes and whose initializer is package-internal. The older
/// summary-only path below is deliberately fail-closed so counters, timestamps, or provenance
/// booleans supplied by app/UI code cannot become physical truth.
public enum TuyaPhysicalFirstAcceptance {
    public static let canonicalDeviceToAppCharacteristicUUID =
        "00000002-0000-1001-8001-00805F9B07D0"

    public enum Verdict: Equatable, Sendable {
        case blocked(reason: String)
        case accepted
    }

    /// Authoritative compatibility entry point. This delegates to the single canonical physical
    /// acceptance implementation rather than maintaining a parallel definition of GO.
    public static func verdict(
        preflight: TuyaAuthenticatedReadOnlyPreflightSnapshot,
        rawNotifyEvidence: C7D09A22PhysicalFirstAcceptance.RawNotifyEvidence
    ) -> Verdict {
        switch C7D09A22PhysicalFirstAcceptance.verdict(
            preflight: preflight,
            rawNotifyEvidence: rawNotifyEvidence
        ) {
        case .acceptedRawNotifyTransport:
            return .accepted
        case .blocked(let reason):
            return .blocked(reason: reason)
        }
    }

    /// Legacy summary-only evidence is intentionally non-authoritative.
    ///
    /// Even apparently valid values cannot prove retained bytes or package-owned callback custody,
    /// so this overload must never produce `.accepted`.
    public static func verdict(
        preflight: TuyaAuthenticatedReadOnlyPreflightSnapshot,
        notify: TuyaPhysicalNotifyEvidence
    ) -> Verdict {
        _ = preflight
        _ = notify
        return .blocked(
            reason: "Legacy summary-only notify metadata cannot authorize physical acceptance; retained package-owned raw notify evidence is required."
        )
    }
}

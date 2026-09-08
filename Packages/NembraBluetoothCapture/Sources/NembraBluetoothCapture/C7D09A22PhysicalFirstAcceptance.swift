import Foundation

/// Evidence-only gate for the first physical acceptance rung after C7D09A22.
///
/// This type does not parse payloads, assign DP meanings, perform BLE writes, or grant control
/// authority. It only answers whether raw application notification bytes were observed inside the
/// exact SmartLife-authenticated generation that already satisfied the canonical read-only
/// preflight chronology.
public enum C7D09A22PhysicalFirstAcceptance {
    public struct RawNotifyEvidence: Equatable, Sendable {
        public let connectionGeneration: UInt64
        public let rawNotifyPayloadCount: Int
        public let latestRawNotifyUptimeNanoseconds: UInt64?

        public init(
            connectionGeneration: UInt64,
            rawNotifyPayloadCount: Int,
            latestRawNotifyUptimeNanoseconds: UInt64?
        ) {
            self.connectionGeneration = connectionGeneration
            self.rawNotifyPayloadCount = max(0, rawNotifyPayloadCount)
            self.latestRawNotifyUptimeNanoseconds = latestRawNotifyUptimeNanoseconds
        }
    }

    public enum Verdict: Equatable, Sendable {
        case blocked(reason: String)
        case acceptedRawNotifyTransport
    }

    /// Require repeated raw notifications so one bootstrap packet cannot become physical truth.
    public static let minimumRawNotifyPayloadCount = 2

    public static func verdict(
        preflight: TuyaAuthenticatedReadOnlyPreflightSnapshot,
        rawNotifyEvidence: RawNotifyEvidence
    ) -> Verdict {
        guard TuyaAuthenticatedReadOnlyPreflight.verdict(for: preflight) == .readyForStationaryMapping else {
            return .blocked(reason: "Authenticated read-only preflight is not canonically ready.")
        }
        guard rawNotifyEvidence.connectionGeneration == preflight.connectionGeneration else {
            return .blocked(reason: "Raw notify evidence belongs to a different Bluetooth connection generation.")
        }
        guard rawNotifyEvidence.rawNotifyPayloadCount >= minimumRawNotifyPayloadCount else {
            return .blocked(reason: "Repeated raw application notify payload evidence is required.")
        }
        guard let authenticatedAt = preflight.authenticatedAtUptimeNanoseconds,
              let latestObserved = preflight.latestObservedUptimeNanoseconds,
              let latestRawNotify = rawNotifyEvidence.latestRawNotifyUptimeNanoseconds,
              latestRawNotify >= authenticatedAt,
              latestObserved >= latestRawNotify else {
            return .blocked(reason: "Raw notify chronology is unavailable or invalid.")
        }
        guard latestRawNotify - authenticatedAt > TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds else {
            return .blocked(reason: "Raw application notify evidence has not survived beyond the historical rejection window yet.")
        }
        return .acceptedRawNotifyTransport
    }
}

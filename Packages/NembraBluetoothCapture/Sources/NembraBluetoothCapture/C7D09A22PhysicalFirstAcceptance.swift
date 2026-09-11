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

        /// Retained, non-semantic raw notification bytes from the physical characteristic path.
        ///
        /// Counts/timestamps are useful summaries but are not physical evidence by themselves.
        /// Keeping the bytes here prevents a caller from minting first acceptance with only a
        /// claimed counter. No parsing or DP meaning is attached to these payloads.
        public let retainedRawNotifyPayloads: [Data]

        /// Package-internal on purpose. Physical acceptance evidence must be minted by a
        /// package-owned CoreBluetooth custody path, not assembled by app/UI callers from
        /// counters, timestamps, or copied bytes. `@testable` fixtures may still exercise the
        /// canonical decision boundary without making fabrication part of the public API.
        init(
            connectionGeneration: UInt64,
            rawNotifyPayloadCount: Int,
            latestRawNotifyUptimeNanoseconds: UInt64?,
            retainedRawNotifyPayloads: [Data] = []
        ) {
            self.connectionGeneration = connectionGeneration
            self.rawNotifyPayloadCount = max(0, rawNotifyPayloadCount)
            self.latestRawNotifyUptimeNanoseconds = latestRawNotifyUptimeNanoseconds
            self.retainedRawNotifyPayloads = retainedRawNotifyPayloads
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

        let retainedNonEmptyPayloadCount = rawNotifyEvidence.retainedRawNotifyPayloads.reduce(into: 0) { count, payload in
            if !payload.isEmpty { count += 1 }
        }
        guard retainedNonEmptyPayloadCount >= minimumRawNotifyPayloadCount else {
            return .blocked(reason: "Repeated retained non-empty raw notification bytes are required; summary counters alone are not physical evidence.")
        }
        guard retainedNonEmptyPayloadCount == rawNotifyEvidence.rawNotifyPayloadCount,
              rawNotifyEvidence.retainedRawNotifyPayloads.allSatisfy({ !$0.isEmpty }) else {
            return .blocked(reason: "Raw notification summary does not match the retained physical payload bytes.")
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

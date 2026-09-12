import Foundation

/// Package-level physical-truth contract for C7D09A22 follow-up evidence.
///
/// This evaluator is intentionally separate from `TuyaAuthenticatedReadOnlyPreflight`: SDK
/// application/transparent callbacks can establish authenticated Tuya transport survival, but
/// they cannot mint raw FD50 characteristic custody. Callers must provide observations produced
/// by a documented same-session characteristic path owned by the authenticated generation.
public enum TuyaAuthenticatedRawFD50Acceptance {
    public static let deviceToAppNotifyCharacteristicUUID = "00000002-0000-1001-8001-00805F9B07D0"
    public static let historicalRejectionBoundaryNanoseconds: UInt64 = 30_000_000_000
    public static let minimumRetainedNotifyCount = 2

    public struct Observation: Equatable, Sendable {
        public let connectionGeneration: UInt64
        public let characteristicUUID: String
        public let observedAtUptimeNanoseconds: UInt64
        public let payloadByteCount: Int

        /// Observation construction is package-owned so app/UI code cannot manufacture physical
        /// custody. A future documented same-session raw callback must be integrated inside this
        /// package and may then construct observations at that ingress boundary.
        init(
            connectionGeneration: UInt64,
            characteristicUUID: String,
            observedAtUptimeNanoseconds: UInt64,
            payloadByteCount: Int
        ) {
            self.connectionGeneration = connectionGeneration
            self.characteristicUUID = characteristicUUID.uppercased()
            self.observedAtUptimeNanoseconds = observedAtUptimeNanoseconds
            self.payloadByteCount = max(0, payloadByteCount)
        }
    }

    public enum Verdict: Equatable, Sendable {
        case blocked(reason: String)
        case accepted
    }

    /// Evaluates only physical raw-notify acceptance. It does not parse payload contents or assign
    /// any DP/telemetry/control meaning.
    public static func verdict(
        authenticatedSnapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot,
        observations: [Observation]
    ) -> Verdict {
        guard authenticatedSnapshot.connectionGeneration > 0 else {
            return .blocked(reason: "No current authenticated Bluetooth generation.")
        }
        guard authenticatedSnapshot.authenticationState == .authenticated,
              authenticatedSnapshot.authenticationMethod == .smartLifeAppSDK else {
            return .blocked(reason: "Current generation is not authenticated by the documented Smart Life SDK path.")
        }
        guard let authenticatedAt = authenticatedSnapshot.authenticatedAtUptimeNanoseconds,
              let latestObserved = authenticatedSnapshot.latestObservedUptimeNanoseconds,
              latestObserved >= authenticatedAt else {
            return .blocked(reason: "Authenticated connection chronology is unavailable or invalid.")
        }

        let qualifying = observations.filter {
            $0.connectionGeneration == authenticatedSnapshot.connectionGeneration
                && $0.characteristicUUID == deviceToAppNotifyCharacteristicUUID
                && $0.payloadByteCount > 0
                && $0.observedAtUptimeNanoseconds >= authenticatedAt
                && $0.observedAtUptimeNanoseconds <= latestObserved
        }

        guard qualifying.count >= minimumRetainedNotifyCount else {
            return .blocked(reason: "Fewer than two retained non-empty raw FD50 notify payloads belong to this authenticated generation.")
        }
        guard qualifying.contains(where: {
            $0.observedAtUptimeNanoseconds - authenticatedAt > historicalRejectionBoundaryNanoseconds
        }) else {
            return .blocked(reason: "No retained raw FD50 notify payload survives beyond the historical rejection boundary.")
        }

        return .accepted
    }
}
